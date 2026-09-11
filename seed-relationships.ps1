# seed-relationships.ps1 — ~310 mirrored LodgeIT edges -> ~160 true edges (DATA)
#
# DOCTRINE (decision 2 + vocabulary findings 11 Sep 2026):
#   House sentence: FROM is TYPE of TO.
#   "...Of" rows assert forward: Code is TYPE of RelatedCode -> load as-is.
#   Bare-type rows are LodgeIT's mirrors -> load ends-SWAPPED.
#   Parent Of is the cross-label mirror of Child Of -> CANONICALISED to
#     Child of, ends swapped (one direction of the truth).
#   Symmetric types (Spouse, Associated With): ends normalised to code order
#     (unordered pair) before dedupe - LodgeIT mirrors these within one label.
#   Dedupe on (from, to, type) AFTER normalisation.
#   cap_name = "FROM TYPE TO" sentence = rerun-safe key.
#   Temporal: Relationship Start/End Date carry into cap_startdate/cap_enddate;
#     blank end = continuing. Dates parsed dd/MM/yyyy then yyyy-MM-dd.
#   Missing ends (codes not in cap_entity) -> RED finding, skip, retry after
#     resolution. Unmapped type text -> RED HALT (never load wrong).

$ErrorActionPreference = "Stop"

$clientId = "bcf0d51c-81f7-40e0-a485-c75ed82a02e3"
$tenantId = "46bc20d5-9c02-426f-b030-aea373177d31"
$envUrl   = "https://org020f7b5c.crm6.dynamics.com"

$token = Get-MsalToken -ClientId $clientId -TenantId $tenantId -Scopes "$envUrl/.default"
$headers = @{
    Authorization      = "Bearer $($token.AccessToken)"
    "OData-MaxVersion" = "4.0"
    "OData-Version"    = "4.0"
    "Content-Type"     = "application/json; charset=utf-8"
    "MSCRM.SolutionUniqueName" = "CommercialAccounting"
}
$api = "$envUrl/api/data/v9.2"

# --- Type map: CSV text -> @{ v = choice value; mode = asis|swap|sym } ----------
$typeMap = @{
    "Director Of"       = @{ v = 764820001; mode = "asis" }
    "Director"          = @{ v = 764820001; mode = "swap" }
    "Beneficiary Of"    = @{ v = 764820009; mode = "asis" }
    "Beneficiary"       = @{ v = 764820009; mode = "swap" }
    "Shareholder Of"    = @{ v = 764820002; mode = "asis" }
    "Shareholder"       = @{ v = 764820002; mode = "swap" }
    "Trustee Of"        = @{ v = 764820000; mode = "asis" }
    "Trustee"           = @{ v = 764820000; mode = "swap" }
    "Partner Of"        = @{ v = 764820004; mode = "asis" }
    "Partner"           = @{ v = 764820004; mode = "swap" }
    "Public Officer Of" = @{ v = 764820007; mode = "asis" }
    "Public Officer"    = @{ v = 764820007; mode = "swap" }
    "Secretary Of"      = @{ v = 764820008; mode = "asis" }
    "Secretary"         = @{ v = 764820008; mode = "swap" }
    "Member Of"         = @{ v = 764820003; mode = "asis" }
    "Member"            = @{ v = 764820003; mode = "swap" }
    "Child Of"          = @{ v = 764820011; mode = "asis" }
    "Parent Of"         = @{ v = 764820011; mode = "swap" }   # canonicalised to Child of
    "Spouse"            = @{ v = 764820010; mode = "sym" }
    "Associated With"   = @{ v = 764820013; mode = "sym" }
    "Other"             = @{ v = 764820014; mode = "asis" }
}
$typeLabel = @{
    764820000="Trustee of"; 764820001="Director of"; 764820002="Shareholder of"
    764820003="Member of";  764820004="Partner of";  764820007="Public Office of"
    764820008="Secretary of"; 764820009="Beneficiary of"; 764820010="Spouse of"
    764820011="Child of"; 764820013="Associated with"; 764820014="Other"
}

function Parse-RelDate([string]$s) {
    if ([string]::IsNullOrWhiteSpace($s)) { return $null }
    foreach ($fmt in "dd/MM/yyyy","yyyy-MM-dd","d/MM/yyyy","dd/MM/yy") {
        try { return [datetime]::ParseExact($s.Trim(), $fmt, $null).ToString("yyyy-MM-dd") } catch {}
    }
    return "UNPARSED"
}

# --- Load CSV + assert -----------------------------------------------------------
$rels = Import-Csv .\data\rels-clean.csv
if ($rels.Count -lt 300) { throw "Expected ~310 rows, got $($rels.Count)." }
Write-Host "rels-clean.csv: $($rels.Count) rows." -ForegroundColor Green

# --- Assert every type text is mapped BEFORE any write ---------------------------
$unknown = $rels | Where-Object { -not $typeMap.ContainsKey($_.'Relationship Type'.Trim()) } |
    Group-Object { $_.'Relationship Type' }
if ($unknown) {
    Write-Host "UNMAPPED TYPE TEXT - halting before any write:" -ForegroundColor Red
    $unknown | ForEach-Object { Write-Host ("  {0,4}  '{1}'" -f $_.Count, $_.Name) -ForegroundColor Red }
    exit 1
}

# --- Resolve ALL entities once: clientcode -> id ---------------------------------
$codeToId = @{}
$url = "$api/cap_entities?`$select=cap_clientcode,cap_entityid"
do {
    $page = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
    foreach ($e in $page.value) { if ($e.cap_clientcode) { $codeToId[$e.cap_clientcode] = $e.cap_entityid } }
    $url = $page.'@odata.nextLink'
} while ($url)
Write-Host "Entities resolvable by clientcode: $($codeToId.Count)" -ForegroundColor Cyan

# --- Existing edges (rerun-safe key = cap_name sentence) -------------------------
$existing = @{}
$url = "$api/cap_entityrelationships?`$select=cap_name"
do {
    $page = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
    foreach ($r in $page.value) { if ($r.cap_name) { $existing[$r.cap_name] = $true } }
    $url = $page.'@odata.nextLink'
} while ($url)
Write-Host "Existing relationship rows: $($existing.Count)" -ForegroundColor Cyan

# --- Normalise: build canonical edge set in memory -------------------------------
$edges = @{}   # key "FROM|TO|TYPE" -> edge object (first occurrence wins dates)
$findings = New-Object System.Collections.Generic.List[object]
foreach ($r in $rels) {
    $t = $typeMap[$r.'Relationship Type'.Trim()]
    $from = $r.Code.Trim(); $to = $r.'Related Client Code'.Trim()
    if ([string]::IsNullOrWhiteSpace($from) -or [string]::IsNullOrWhiteSpace($to)) {
        $findings.Add([pscustomobject]@{ Row="$($r.Code)/$($r.'Related Client Code')"; Issue="Blank end - skipped" }); continue
    }
    switch ($t.mode) {
        "swap" { $tmp = $from; $from = $to; $to = $tmp }
        "sym"  { if ($from -gt $to) { $tmp = $from; $from = $to; $to = $tmp } }
    }
    $key = "$from|$to|$($t.v)"
    if (-not $edges.ContainsKey($key)) {
        $edges[$key] = [pscustomobject]@{
            From = $from; To = $to; TypeV = $t.v
            Start = Parse-RelDate $r.'Relationship Start Date'
            End   = Parse-RelDate $r.'Relationship End Date'
        }
    }
}
Write-Host "Normalised: $($rels.Count) rows -> $($edges.Count) true edges." -ForegroundColor Green

# --- THE LOAD --------------------------------------------------------------------
$created = 0; $skipped = 0
foreach ($e in $edges.Values) {
    $label = $typeLabel[$e.TypeV]
    $name = "$($e.From) $label $($e.To)"
    if ($existing.ContainsKey($name)) { $skipped++; continue }
    if (-not $codeToId.ContainsKey($e.From)) {
        $findings.Add([pscustomobject]@{ Row=$name; Issue="FROM code '$($e.From)' not in cap_entity - skipped for retry" }); continue
    }
    if (-not $codeToId.ContainsKey($e.To)) {
        $findings.Add([pscustomobject]@{ Row=$name; Issue="TO code '$($e.To)' not in cap_entity - skipped for retry" }); continue
    }
    $body = @{
        cap_name                      = $name
        cap_relationshiptype          = $e.TypeV
        "cap_fromentityid@odata.bind" = "/cap_entities($($codeToId[$e.From]))"
        "cap_toentityid@odata.bind"   = "/cap_entities($($codeToId[$e.To]))"
    }
    if ($e.Start -and $e.Start -ne "UNPARSED") { $body.cap_startdate = $e.Start }
    if ($e.End   -and $e.End   -ne "UNPARSED") { $body.cap_enddate   = $e.End }
    if ($e.Start -eq "UNPARSED" -or $e.End -eq "UNPARSED") {
        $findings.Add([pscustomobject]@{ Row=$name; Issue="Date unparsed - loaded without date; check format" })
    }
    try {
        Invoke-RestMethod -Uri "$api/cap_entityrelationships" -Headers $headers -Method Post -Body ($body | ConvertTo-Json) | Out-Null
        $created++
    }
    catch {
        $msg = $_.ErrorDetails.Message ?? $_.Exception.Message
        Write-Host "POST FAILED on $name : $msg" -ForegroundColor Red
        $findings.Add([pscustomobject]@{ Row=$name; Issue="POST failed: $msg" })
    }
    if ($created % 25 -eq 0 -and $created -gt 0) { Write-Host "  ...$created created" -ForegroundColor DarkGray }
}
Write-Host "Created: $created  Skipped(existing): $skipped" -ForegroundColor Green

# --- FINDINGS ---------------------------------------------------------------------
if ($findings.Count -gt 0) {
    Write-Host "`nFINDINGS ($($findings.Count)):" -ForegroundColor Red
    $findings | ForEach-Object { Write-Host ("  {0}  {1}" -f $_.Row, $_.Issue) -ForegroundColor Yellow }
}

# --- VERIFY: count by type from the database --------------------------------------
$counts = @{}; $total = 0
$url = "$api/cap_entityrelationships?`$select=cap_relationshiptype"
do {
    $page = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
    foreach ($r in $page.value) {
        $key = if ($null -eq $r.cap_relationshiptype) { "(none)" } else { [string]$r.cap_relationshiptype }
        $counts[$key] = ($counts[$key] ?? 0) + 1; $total++
    }
    $url = $page.'@odata.nextLink'
} while ($url)
Write-Host "`nRelationship rows by type:" -ForegroundColor Cyan
$counts.GetEnumerator() | Sort-Object Key | ForEach-Object {
    $lbl = if ($typeLabel.ContainsKey([int]$_.Key)) { $typeLabel[[int]$_.Key] } else { $_.Key }
    Write-Host ("  {0,-18} {1}" -f $lbl, $_.Value)
}
Write-Host "TOTAL: $total" -ForegroundColor Green

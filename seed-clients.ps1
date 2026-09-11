# seed-clients.ps1 — the practice arrives: 307 LodgeIT identities (DATA)
#
# IDENTITY ONLY, by structure and doctrine: name, TFN, ABN, ACN, type,
# status, clientcode, country. LodgeIT's addresses/emails/birthdays have no
# cap_entity home and stay in LodgeIT until argued one.
#
# MAPPINGS (probed, never assumed):
#   Type:     Company->764820001  Individual->764820000  Partnership->764820003
#             Superfund->764820004 (SMSF)  Trust->764820002
#   Archived: Y -> cap_status 764820003 (Former = TOMBSTONE)
#             N -> cap_status 764820000 (Active)
#   Code -> cap_clientcode (the LodgeIT sync key; ALSO the rerun-safe key -
#           codes are unique, ampersand-free, URL-safe. Names are neither.)
#   TFN/ABN/ACN -> strings, set only when non-blank (TFN alternate key is
#           conditionally unique; blanks must stay absent, not empty)
#   Country -> AU for all (LodgeIT is Australian; internationals arrive later)
#
# DUPLICATE-TFN DOCTRINE (ratified 11 Sep 2026):
#   LodgeIT does not enforce TFN uniqueness; CAP does (alternate key).
#   Pre-scan groups duplicate TFNs. SURVIVOR keeps the TFN: Active beats
#   Former, tie broken by first-in-file. Non-survivors load WITHOUT TFN -
#   identity and clientcode intact so relationship edges never lose an end.
#   Belt-and-braces: any POST that still violates the key (partial-state
#   case: a non-survivor loaded in an earlier run already holds the TFN)
#   reports a RED finding and retries without TFN. Findings table at exit
#   = the LodgeIT clean-up list.
#
# VERIFY NOTE: hashtables reject $null as a KEY (the ?? guard only covers
#   the value). Harborne has no cap_status, so the verify coalesces the key
#   to "(none)" before indexing.
#
# PARSE ASSERTION before any write: property names visible-length, count 307.

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

# --- Load + ASSERT the parse --------------------------------------------------
$clientsFile = Get-ChildItem .\data\Clients*.csv | Select-Object -First 1
$rows = Import-Csv $clientsFile
$nameLen = ($rows[0].PSObject.Properties.Name | Where-Object { $_ -eq "Code" }).Length
if ($rows.Count -lt 300 -or $nameLen -ne 4) {
    throw "Parse assertion failed: count=$($rows.Count), 'Code' len=$nameLen (want 4). Encoding suspect - clean like rels."
}
Write-Host "Parse asserted: $($rows.Count) rows, headers clean." -ForegroundColor Green

# --- Duplicate-TFN pre-scan: pick survivors, suppress the rest ------------------
$suppressTfn = @{}     # Code -> TFN it would have carried (suppressed)
$dupGroups = $rows | Where-Object { -not [string]::IsNullOrWhiteSpace($_.TFN) } |
    Group-Object { $_.TFN.Trim() } | Where-Object { $_.Count -gt 1 }
foreach ($g in $dupGroups) {
    $survivor = ($g.Group | Where-Object { $_.Archived -eq "N" } | Select-Object -First 1)
    if (-not $survivor) { $survivor = $g.Group[0] }   # all Former: first-in-file
    foreach ($m in $g.Group) {
        if ($m.Code -ne $survivor.Code) { $suppressTfn[$m.Code] = $g.Name }
    }
    Write-Host ("Dup TFN {0}: survivor {1} keeps it; suppressed on {2}" -f `
        $g.Name, $survivor.Code, (($g.Group | Where-Object { $_.Code -ne $survivor.Code } | ForEach-Object { $_.Code }) -join ", ")) -ForegroundColor Yellow
}

# --- Mapping tables -------------------------------------------------------------
$typeMap = @{
    "Company"     = 764820001
    "Individual"  = 764820000
    "Partnership" = 764820003
    "Superfund"   = 764820004
    "Trust"       = 764820002
}
$statusActive = 764820000
$statusFormer = 764820003

# --- Resolve AU country once ----------------------------------------------------
$au = (Invoke-RestMethod -Uri "$api/cap_countries?`$select=cap_countryid&`$filter=cap_isoalpha2 eq 'AU'" -Headers $headers -Method Get).value
$auId = $au[0].cap_countryid

# --- Existing clientcodes (ONE query; the rerun-safe key) -----------------------
$existing = @()
$url = "$api/cap_entities?`$select=cap_clientcode"
do {
    $page = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
    $existing += $page.value.cap_clientcode
    $url = $page.'@odata.nextLink'
} while ($url)
Write-Host "Existing entities with clientcodes: $(($existing | Where-Object { $_ }).Count)" -ForegroundColor Cyan

# --- THE LOAD -------------------------------------------------------------------
$created = 0; $skipped = 0; $unmapped = 0
$findings = New-Object System.Collections.Generic.List[object]
foreach ($r in $rows) {
    if ([string]::IsNullOrWhiteSpace($r.Code)) { continue }
    if ($existing -contains $r.Code) { $skipped++; continue }
    if (-not $typeMap.ContainsKey($r.Type)) {
        Write-Host "UNMAPPED TYPE '$($r.Type)' on $($r.Code) - skipping." -ForegroundColor Red
        $unmapped++; continue
    }
    $body = @{
        cap_entityname             = $r.Name
        cap_clientcode             = $r.Code
        cap_type                   = $typeMap[$r.Type]
        cap_status                 = if ($r.Archived -eq "Y") { $statusFormer } else { $statusActive }
        "cap_countryid@odata.bind" = "/cap_countries($auId)"
    }
    if (-not [string]::IsNullOrWhiteSpace($r.TFN) -and -not $suppressTfn.ContainsKey($r.Code)) {
        $body.cap_tfn = $r.TFN.Trim()
    }
    if ($suppressTfn.ContainsKey($r.Code)) {
        $findings.Add([pscustomobject]@{ Code=$r.Code; Name=$r.Name; Issue="TFN suppressed (dup group $($suppressTfn[$r.Code])); fix in LodgeIT" })
    }
    if (-not [string]::IsNullOrWhiteSpace($r.ABN)) { $body.cap_abn = $r.ABN.Trim() }
    if (-not [string]::IsNullOrWhiteSpace($r.ACN)) { $body.cap_acn = $r.ACN.Trim() }

    try {
        Invoke-RestMethod -Uri "$api/cap_entities" -Headers $headers -Method Post -Body ($body | ConvertTo-Json) | Out-Null
        $created++
    }
    catch {
        $msg = $_.ErrorDetails.Message ?? $_.Exception.Message
        if ($msg -match "0x80060892") {
            # Partial-state case: TFN already held in DB (non-survivor from an earlier run).
            Write-Host "TFN KEY VIOLATION on $($r.Code) $($r.Name) - retrying WITHOUT TFN." -ForegroundColor Red
            $findings.Add([pscustomobject]@{ Code=$r.Code; Name=$r.Name; Issue="TFN already held in Dataverse by another record; loaded without TFN" })
            $body.Remove("cap_tfn")
            Invoke-RestMethod -Uri "$api/cap_entities" -Headers $headers -Method Post -Body ($body | ConvertTo-Json) | Out-Null
            $created++
        }
        else {
            Write-Host "POST FAILED on $($r.Code) $($r.Name): $msg" -ForegroundColor Red
            $findings.Add([pscustomobject]@{ Code=$r.Code; Name=$r.Name; Issue="POST failed: $msg" })
        }
    }
    if ($created % 25 -eq 0 -and $created -gt 0) { Write-Host "  ...$created created" -ForegroundColor DarkGray }
}
Write-Host "Created: $created  Skipped(existing): $skipped  Unmapped: $unmapped" -ForegroundColor Green

# --- FINDINGS TABLE (the LodgeIT clean-up list) ---------------------------------
if ($findings.Count -gt 0) {
    Write-Host "`nFINDINGS ($($findings.Count)) - resolve in LodgeIT:" -ForegroundColor Red
    $findings | ForEach-Object { Write-Host ("  {0}  {1}  {2}" -f $_.Code, $_.Name, $_.Issue) -ForegroundColor Yellow }
}

# --- VERIFY from the database ---------------------------------------------------
$counts = @{}; $total = 0
$url = "$api/cap_entities?`$select=cap_status"
do {
    $page = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
    foreach ($e in $page.value) {
        $key = if ($null -eq $e.cap_status) { "(none)" } else { [string]$e.cap_status }
        $counts[$key] = ($counts[$key] ?? 0) + 1
        $total++
    }
    $url = $page.'@odata.nextLink'
} while ($url)
Write-Host "`nEntity rows by status (764820000=Active, 764820003=Former, (none)=Harborne):" -ForegroundColor Cyan
$counts.GetEnumerator() | Sort-Object Key | ForEach-Object { Write-Host ("  {0}  {1}" -f $_.Key, $_.Value) }
Write-Host "TOTAL: $total" -ForegroundColor Green

Drill: notepad seed-clients.ps1 → Ctrl+A → paste → Ctrl+Home head check (first line is the # seed-clients.ps1 comment) → Ctrl+End tail check (last line is the green TOTAL) → Ctrl+S dot-gone.

Optional but worth the ten seconds: run it once — it should print the three yellow dup lines, skip 307, create 0, print the same 198/109/1/308 verify — proving the patched file is whole and rerun-safety holds end-to-end. Then the commit:

powershell
git add seed-clients.ps1 find-dup-tfns.ps1 verify-entities.ps1 clean-rels.ps1 probe-choices.ps1
git commit -m "Seed 307 LodgeIT identities; duplicate-TFN survivor rule; dup diagnostic; status verify"

Hash, then rel-types-topup.ps1.



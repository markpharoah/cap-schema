# 26-cap-status.ps1 — apply CAP Status rulings (DATA)
# Keep=current; Kill=dup ghost->Former (tombstone, never delete);
# Former/"Not acting"/not-on-program->Former. Former entities: status
# 764820003 AND engagements deactivated (tombstones hold history, not
# promises). Edges remain. Redirect edges re-anchor facts to real records.
# Only Jenkins spouses (JEN0001/JEN0002) stay current of the reviewed set.
# RERUN-SAFE throughout.

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
$FORMER = 764820003

$formerCodes = @(
    "BET0002","BET0003","BOW0002",
    "CAS0003","CAS0004","CAS0005","CAS0006","CAS0007",
    "DEA0002","HAM0005","JEN0003","KNE0001","MCI0004","MCI0005",
    "PHA0003","PHA0006","PHA0007","PHA0008",
    "BIR0002","BUX0001","DIG0001","GAT0001","GUR0001","GUR0002","SAS0001","UND0001",
    "BOW0005","DEA0003","WAT0003"
)

$codeToId = @{}
$url = "$api/cap_entities?`$select=cap_clientcode,cap_entityid,cap_status"
do {
    $page = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
    foreach ($ent in $page.value) { if ($ent.cap_clientcode) { $codeToId[$ent.cap_clientcode] = $ent } }
    $url = $page.'@odata.nextLink'
} while ($url)

$flipped = 0
foreach ($c in $formerCodes) {
    if (-not $codeToId.ContainsKey($c)) { Write-Host "  '$c' not found" -ForegroundColor Red; continue }
    $ent = $codeToId[$c]
    if ([int]($ent.cap_status ?? -1) -eq $FORMER) { Write-Host "  $c already Former - skip." -ForegroundColor Yellow; continue }
    Invoke-RestMethod -Uri "$api/cap_entities($($ent.cap_entityid))" -Headers $headers -Method Patch -Body (@{ cap_status = $FORMER } | ConvertTo-Json) | Out-Null
    Write-Host "  Former: $c" -ForegroundColor Green
    $flipped++
}
Write-Host "Flipped to Former: $flipped" -ForegroundColor Green

Write-Host "Deactivating engagements (one query per entity - allow a quiet minute)..." -ForegroundColor Cyan
$deact = 0
foreach ($c in $formerCodes) {
    if (-not $codeToId.ContainsKey($c)) { continue }
    $eid = $codeToId[$c].cap_entityid
    $engs = (Invoke-RestMethod -Uri "$api/cap_engagements?`$select=cap_engagementid,cap_name&`$filter=_cap_entityid_value eq $eid and statecode eq 0" -Headers $headers -Method Get).value
    foreach ($g in $engs) {
        Invoke-RestMethod -Uri "$api/cap_engagements($($g.cap_engagementid))" -Headers $headers -Method Patch -Body (@{ statecode = 1; statuscode = 2 } | ConvertTo-Json) | Out-Null
        Write-Host "  Deactivated: $($g.cap_name)" -ForegroundColor Green
        $deact++
    }
}
Write-Host "Engagements deactivated: $deact" -ForegroundColor Green

$SPOUSE=764820010; $ASSOC=764820013
$typeLabel = @{ 764820010="Spouse of"; 764820013="Associated with" }
$redirects = @(
    @("PHA0001","PHA0002",$SPOUSE,"Mark and Robin (redirected from dup rows)"),
    @("PHA0002","PHA0010",$ASSOC,"Robin daughter-in-law of John"),
    @("MCI0001","MCI0003",$ASSOC,"Jennifer daughter-in-law of Stuart (redirected from dup)")
)
$existing = @{}
$url = "$api/cap_entityrelationships?`$select=cap_name"
do {
    $page = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
    foreach ($r in $page.value) { if ($r.cap_name) { $existing[$r.cap_name] = $true } }
    $url = $page.'@odata.nextLink'
} while ($url)
$made = 0
foreach ($row in $redirects) {
    $from = $row[0]; $to = $row[1]; $tv = $row[2]; $note = $row[3]
    if ($from -gt $to) { $tmp=$from; $from=$to; $to=$tmp }
    $name = "$from $($typeLabel[$tv]) $to"
    if ($existing.ContainsKey($name)) { Write-Host "  $name exists - skip." -ForegroundColor Yellow; continue }
    $body = @{
        cap_name = $name; cap_relationshiptype = $tv
        cap_notes = "CAP Status ruling 12 Sep 2026: $note"
        "cap_fromentityid@odata.bind" = "/cap_entities($($codeToId[$from].cap_entityid))"
        "cap_toentityid@odata.bind"   = "/cap_entities($($codeToId[$to].cap_entityid))"
    }
    Invoke-RestMethod -Uri "$api/cap_entityrelationships" -Headers $headers -Method Post -Body ($body | ConvertTo-Json) | Out-Null
    Write-Host "  Edge: $name" -ForegroundColor Green
    $made++
}
Write-Host "Redirect edges: $made" -ForegroundColor Green

$sc = @{}
$url = "$api/cap_entities?`$select=cap_status"
do {
    $page = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
    foreach ($ent in $page.value) { $k = if ($null -eq $ent.cap_status) { "(none)" } else { [string]$ent.cap_status }; $sc[$k] = ($sc[$k] ?? 0) + 1 }
    $url = $page.'@odata.nextLink'
} while ($url)
Write-Host "`nEntities by status (764820000 Active / 764820003 Former):" -ForegroundColor Cyan
$sc.GetEnumerator() | Sort-Object Key | ForEach-Object { Write-Host ("  {0}  {1}" -f $_.Key, $_.Value) }

$ec = @{}; $etot = 0
$typeName = @{ 100000000="Annual Accounting"; 100000001="SMSF Audit"; 100000010="Tax Only"; 100000011="Virtual CFO" }
$url = "$api/cap_engagements?`$select=cap_engagementtype&`$filter=statecode eq 0"
do {
    $page = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
    foreach ($g in $page.value) { $k = $typeName[[int]($g.cap_engagementtype ?? -1)] ?? "?"; $ec[$k] = ($ec[$k] ?? 0) + 1; $etot++ }
    $url = $page.'@odata.nextLink'
} while ($url)
Write-Host "`nACTIVE engagements by type:" -ForegroundColor Cyan
$ec.GetEnumerator() | Sort-Object Key | ForEach-Object { Write-Host ("  {0,-24} {1}" -f $_.Key, $_.Value) }
Write-Host "TOTAL active: $etot" -ForegroundColor Green
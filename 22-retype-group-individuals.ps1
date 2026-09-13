# 22-retype-group-individuals.ps1 — Tax Only -> Annual Accounting where the
# family web proves it (DATA)
#
# RULING (12 Sep): the promise is often GROUP-scoped; an individual's return
# rides with the family group's Annual Accounting. The group is a LENS not
# a table (derived connected component; cap_entitygroup waits for the
# portal/billing consumer). Engagements stay entity-anchored; the TYPE
# records the promise scope. This script retypes the 49 individuals whose
# component provably holds AA. The REST of the mislabels are a LodgeIT
# relationship-data gap (spouse links missing - the odd Spouse count was
# the symptom): fixed by recognition in the app - add the edge, the group
# forms, the retype justifies itself. Same analysis (21) re-runs any time.
#
# RERUN-SAFE: only touches engagements currently typed Tax Only.

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

$AA = 100000000; $TAXONLY = 100000010

# --- Entities + edges (same graph as 21) --------------------------------------------
$entities = @{}
$url = "$api/cap_entities?`$select=cap_entityid,cap_entityname,cap_type"
do {
    $page = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
    foreach ($e in $page.value) { $entities[$e.cap_entityid] = $e }
    $url = $page.'@odata.nextLink'
} while ($url)
$edges = @()
$url = "$api/cap_entityrelationships?`$select=_cap_fromentityid_value,_cap_toentityid_value"
do {
    $page = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
    foreach ($r in $page.value) { $edges += ,@($r._cap_fromentityid_value, $r._cap_toentityid_value) }
    $url = $page.'@odata.nextLink'
} while ($url)

$parent = @{}
foreach ($id in $entities.Keys) { $parent[$id] = $id }
function Find($x) { while ($parent[$x] -ne $x) { $parent[$x] = $parent[$parent[$x]]; $x = $parent[$x] }; $x }
foreach ($e in $edges) { $a = Find $e[0]; $b = Find $e[1]; if ($a -ne $b) { $parent[$a] = $b } }

# --- Engagements ---------------------------------------------------------------------
$engs = @()
$url = "$api/cap_engagements?`$select=cap_engagementid,cap_name,cap_engagementtype,_cap_entityid_value"
do {
    $page = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
    $engs += $page.value
    $url = $page.'@odata.nextLink'
} while ($url)

# Components holding AA
$aaRoots = @{}
foreach ($g in $engs | Where-Object { [int]($_.cap_engagementtype ?? -1) -eq $AA }) {
    if ($g._cap_entityid_value) { $aaRoots[(Find $g._cap_entityid_value)] = $true }
}

# --- Retype: Tax Only engagements of individuals in AA components --------------------
$retyped = 0
foreach ($g in $engs | Where-Object { [int]($_.cap_engagementtype ?? -1) -eq $TAXONLY }) {
    $eid = $g._cap_entityid_value
    if (-not $eid) { continue }
    if (-not $aaRoots.ContainsKey((Find $eid))) { continue }
    $newName = $g.cap_name -replace 'Tax Only$', 'Annual Accounting'
    Invoke-RestMethod -Uri "$api/cap_engagements($($g.cap_engagementid))" -Headers $headers -Method Patch -Body (@{ cap_engagementtype = $AA; cap_name = $newName } | ConvertTo-Json) | Out-Null
    Write-Host "  Retyped: $($entities[$eid].cap_entityname)" -ForegroundColor Green
    $retyped++
}
Write-Host "Retyped: $retyped" -ForegroundColor Green

# --- VERIFY --------------------------------------------------------------------------
$counts = @{}; $total = 0
$typeName = @{ 100000000="Annual Accounting"; 100000001="SMSF Audit"; 100000010="Tax Only"; 100000011="Virtual CFO" }
$url = "$api/cap_engagements?`$select=cap_engagementtype"
do {
    $page = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
    foreach ($e in $page.value) {
        $k = $typeName[[int]($e.cap_engagementtype ?? -1)] ?? [string]$e.cap_engagementtype
        $counts[$k] = ($counts[$k] ?? 0) + 1; $total++
    }
    $url = $page.'@odata.nextLink'
} while ($url)
Write-Host "`nEngagements by type:" -ForegroundColor Cyan
$counts.GetEnumerator() | Sort-Object Key | ForEach-Object { Write-Host ("  {0,-24} {1}" -f $_.Key, $_.Value) }
Write-Host "TOTAL: $total" -ForegroundColor Green
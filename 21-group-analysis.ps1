# 21-group-analysis.ps1 — derive family groups from the relationship web (ANALYSIS)
#
# INSIGHT (Mark, 12 Sep): the promise is often GROUP-scoped - an individual's
# return rides with the family group's Annual Accounting, not a standalone
# Tax Only promise. The 166 edges already partition the practice: a family
# group = a CONNECTED COMPONENT of the relationship graph.
# This probe derives the components and answers, per group:
#   - members (count, mix of entity types)
#   - engagement types currently held
#   - individuals typed Tax Only sitting in a group that holds Annual
#     Accounting  -> the retype candidates
#   - true standalones (no edges) -> the genuine Tax Only book
# READ-ONLY. Output informs the group-model argument before any schema.

$ErrorActionPreference = "Stop"

$clientId = "bcf0d51c-81f7-40e0-a485-c75ed82a02e3"
$tenantId = "46bc20d5-9c02-426f-b030-aea373177d31"
$envUrl   = "https://org020f7b5c.crm6.dynamics.com"

$token = Get-MsalToken -ClientId $clientId -TenantId $tenantId -Scopes "$envUrl/.default"
$headers = @{ Authorization = "Bearer $($token.AccessToken)"; "OData-MaxVersion" = "4.0"; "OData-Version" = "4.0" }
$api = "$envUrl/api/data/v9.2"

# --- Load entities -------------------------------------------------------------------
$entities = @{}
$url = "$api/cap_entities?`$select=cap_entityid,cap_entityname,cap_clientcode,cap_type,cap_status"
do {
    $page = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
    foreach ($e in $page.value) { $entities[$e.cap_entityid] = $e }
    $url = $page.'@odata.nextLink'
} while ($url)

# --- Load edges ----------------------------------------------------------------------
$edges = @()
$url = "$api/cap_entityrelationships?`$select=_cap_fromentityid_value,_cap_toentityid_value"
do {
    $page = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
    foreach ($r in $page.value) {
        $edges += ,@($r._cap_fromentityid_value, $r._cap_toentityid_value)
    }
    $url = $page.'@odata.nextLink'
} while ($url)
Write-Host "Entities: $($entities.Count)  Edges: $($edges.Count)" -ForegroundColor Cyan

# --- Load engagements per entity -----------------------------------------------------
$engByEntity = @{}
$url = "$api/cap_engagements?`$select=cap_engagementtype,_cap_entityid_value"
do {
    $page = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
    foreach ($g in $page.value) {
        $eid = $g._cap_entityid_value
        if ($eid) {
            if (-not $engByEntity.ContainsKey($eid)) { $engByEntity[$eid] = @() }
            $engByEntity[$eid] += [int]($g.cap_engagementtype ?? -1)
        }
    }
    $url = $page.'@odata.nextLink'
} while ($url)

# --- Union-Find: connected components ------------------------------------------------
$parent = @{}
foreach ($id in $entities.Keys) { $parent[$id] = $id }
function Find($x) { while ($parent[$x] -ne $x) { $parent[$x] = $parent[$parent[$x]]; $x = $parent[$x] }; $x }
foreach ($e in $edges) {
    $a = Find $e[0]; $b = Find $e[1]
    if ($a -ne $b) { $parent[$a] = $b }
}
$groups = @{}
foreach ($id in $entities.Keys) {
    $root = Find $id
    if (-not $groups.ContainsKey($root)) { $groups[$root] = @() }
    $groups[$root] += $id
}

$typeNames = @{ 764820000="Ind"; 764820001="Co"; 764820002="Trust"; 764820003="P/ship"; 764820004="SMSF" }
$AA = 100000000; $TAXONLY = 100000010

# --- Report: multi-member groups -----------------------------------------------------
$multi = $groups.GetEnumerator() | Where-Object { $_.Value.Count -gt 1 } | Sort-Object { $_.Value.Count } -Descending
$solo  = $groups.GetEnumerator() | Where-Object { $_.Value.Count -eq 1 }
Write-Host "`nGroups: $($multi.Count) multi-member, $($solo.Count) standalone." -ForegroundColor Cyan

$retypeCandidates = 0
Write-Host "`n=== MULTI-MEMBER GROUPS (by size) ===" -ForegroundColor Cyan
foreach ($g in $multi) {
    $members = $g.Value | ForEach-Object { $entities[$_] }
    # Name the group by dominant code prefix (first 3 letters)
    $prefix = ($members | Where-Object { $_.cap_clientcode } |
        Group-Object { $_.cap_clientcode.Substring(0, [Math]::Min(3, $_.cap_clientcode.Length)) } |
        Sort-Object Count -Descending | Select-Object -First 1).Name
    $mix = ($members | Group-Object { $typeNames[[int]($_.cap_type ?? -1)] ?? "?" } |
        ForEach-Object { "$($_.Count)x$($_.Name)" }) -join " "
    $groupHasAA = $false
    foreach ($m in $members) {
        if ($engByEntity.ContainsKey($m.cap_entityid) -and $engByEntity[$m.cap_entityid] -contains $AA) { $groupHasAA = $true; break }
    }
    $groupRetypes = @($members | Where-Object {
        [int]($_.cap_type ?? -1) -eq 764820000 -and
        $engByEntity.ContainsKey($_.cap_entityid) -and
        $engByEntity[$_.cap_entityid] -contains $TAXONLY -and
        $groupHasAA
    })
    $retypeCandidates += $groupRetypes.Count
    $flag = if ($groupHasAA -and $groupRetypes.Count -gt 0) { "  <- $($groupRetypes.Count) Tax Only individual(s) ride with group AA" } else { "" }
    Write-Host ("  [{0}] {1} members  {2}{3}" -f $prefix, $members.Count, $mix, $flag)
}

Write-Host "`n=== THE ANSWER ===" -ForegroundColor Cyan
Write-Host ("Individuals currently Tax Only whose group holds Annual Accounting: {0}" -f $retypeCandidates) -ForegroundColor Yellow
Write-Host ("True standalone entities (no edges - the genuine Tax Only book): {0}" -f $solo.Count) -ForegroundColor Yellow
Write-Host "`nRead-only. No writes. Argue the group model from these numbers." -ForegroundColor Green
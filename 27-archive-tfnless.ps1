# 27-archive-tfnless.ps1 — TFN-less rulings refined (DATA)
# LEI0002 = DUPLICATE of BIR0001 (Birch, Christiana - maiden name, CURRENT,
#   lodged 2025) -> Former + merge register; marriage re-anchored
#   LEI0001 Spouse of BIR0001. AXF0001 Peter Axford: alive, genuine ->
#   STAYS ACTIVE. JUD0001, RUB0001 -> Former. Tombstone doctrine: never delete.
$ErrorActionPreference = "Stop"
$clientId = "bcf0d51c-81f7-40e0-a485-c75ed82a02e3"
$tenantId = "46bc20d5-9c02-426f-b030-aea373177d31"
$envUrl   = "https://org020f7b5c.crm6.dynamics.com"
$token = Get-MsalToken -ClientId $clientId -TenantId $tenantId -Scopes "$envUrl/.default"
$headers = @{
    Authorization = "Bearer $($token.AccessToken)"; "OData-MaxVersion" = "4.0"; "OData-Version" = "4.0"
    "Content-Type" = "application/json; charset=utf-8"; "MSCRM.SolutionUniqueName" = "CommercialAccounting"
}
$api = "$envUrl/api/data/v9.2"
$FORMER = 764820003
$ids = @{}
foreach ($c in @("LEI0001","LEI0002","BIR0001","JUD0001","RUB0001")) {
    $ent = (Invoke-RestMethod -Uri "$api/cap_entities?`$select=cap_entityid,cap_status&`$filter=cap_clientcode eq '$c'" -Headers $headers -Method Get).value
    if ($ent.Count -ge 1) { $ids[$c] = $ent[0] }
}
foreach ($c in @("LEI0002","JUD0001","RUB0001")) {
    if (-not $ids.ContainsKey($c)) { Write-Host "  '$c' not found" -ForegroundColor Red; continue }
    if ([int]($ids[$c].cap_status ?? -1) -eq $FORMER) { Write-Host "  $c already Former - skip." -ForegroundColor Yellow }
    else {
        Invoke-RestMethod -Uri "$api/cap_entities($($ids[$c].cap_entityid))" -Headers $headers -Method Patch -Body (@{ cap_status = $FORMER } | ConvertTo-Json) | Out-Null
        Write-Host "  Former: $c" -ForegroundColor Green
    }
    $engs = (Invoke-RestMethod -Uri "$api/cap_engagements?`$select=cap_engagementid,cap_name&`$filter=_cap_entityid_value eq $($ids[$c].cap_entityid) and statecode eq 0" -Headers $headers -Method Get).value
    foreach ($g in $engs) {
        Invoke-RestMethod -Uri "$api/cap_engagements($($g.cap_engagementid))" -Headers $headers -Method Patch -Body (@{ statecode = 1; statuscode = 2 } | ConvertTo-Json) | Out-Null
        Write-Host "  Deactivated: $($g.cap_name)" -ForegroundColor Green
    }
}
# Re-anchor the Leighton marriage to the real Christiana (BIR0001)
$name = "BIR0001 Spouse of LEI0001"
$hit = (Invoke-RestMethod -Uri "$api/cap_entityrelationships?`$select=cap_entityrelationshipid&`$filter=cap_name eq '$name'" -Headers $headers -Method Get).value
if ($hit.Count -gt 0) { Write-Host "  $name exists - skip." -ForegroundColor Yellow }
else {
    $body = @{
        cap_name = $name; cap_relationshiptype = 764820010
        cap_notes = "Re-anchored 12 Sep 2026: LEI0002 is duplicate of BIR0001 (maiden name)"
        "cap_fromentityid@odata.bind" = "/cap_entities($($ids['BIR0001'].cap_entityid))"
        "cap_toentityid@odata.bind"   = "/cap_entities($($ids['LEI0001'].cap_entityid))"
    }
    Invoke-RestMethod -Uri "$api/cap_entityrelationships" -Headers $headers -Method Post -Body ($body | ConvertTo-Json) | Out-Null
    Write-Host "  Edge: $name" -ForegroundColor Green
}
$n = 0
$url = "$api/cap_engagements?`$select=cap_engagementid&`$filter=statecode eq 0"
do { $page = Invoke-RestMethod -Uri $url -Headers $headers -Method Get; $n += $page.value.Count; $url = $page.'@odata.nextLink' } while ($url)
Write-Host "Active engagements: $n" -ForegroundColor Green
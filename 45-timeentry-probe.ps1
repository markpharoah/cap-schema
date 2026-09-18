# ============================================================================
# 45-timeentry-probe.ps1 — Session 39 Part 1 (read-only)
# cap_timeentry and cap_budgetline were built 12/9 (charge − invoiced = WIP
# grain). Before adding a capture surface, print their true shape: custom
# attributes with types, required levels, and every lookup's navigation
# property. Paste the output back (as probe-output-45.txt); the quick-create
# form spec and any seed follow from reality.
# ============================================================================
$ErrorActionPreference = 'Stop'
$Env = 'https://org020f7b5c.crm6.dynamics.com'
try   { $Token = Get-MsalToken -ClientId 'bcf0d51c-81f7-40e0-a485-c75ed82a02e3' -TenantId '46bc20d5-9c02-426f-b030-aea373177d31' -Scopes "$Env/.default" -Silent }
catch { $Token = Get-MsalToken -ClientId 'bcf0d51c-81f7-40e0-a485-c75ed82a02e3' -TenantId '46bc20d5-9c02-426f-b030-aea373177d31' -Scopes "$Env/.default" -Interactive }
$H  = @{ Authorization = "Bearer $($Token.AccessToken)"; Accept='application/json' }
$HW = $H + @{ 'Content-Type'='application/json' }
$Api = "$Env/api/data/v9.2"
foreach ($t in 'cap_timeentry','cap_budgetline') {
  Write-Host "`n=== $t ===" -ForegroundColor Cyan
  (Invoke-RestMethod -Uri "$Api/EntityDefinitions(LogicalName='$t')/Attributes?`$select=LogicalName,AttributeType,RequiredLevel&`$filter=IsCustomAttribute eq true" -Headers $H).value |
    Sort-Object LogicalName | ForEach-Object { "{0,-40} {1,-12} {2}" -f $_.LogicalName, $_.AttributeType, $_.RequiredLevel.Value }
  Write-Host "  lookups:" -ForegroundColor DarkCyan
  (Invoke-RestMethod -Uri "$Api/EntityDefinitions(LogicalName='$t')/ManyToOneRelationships?`$select=ReferencingAttribute,ReferencedEntity,ReferencingEntityNavigationPropertyName" -Headers $H).value |
    ForEach-Object { "    {0} -> {1}  (nav {2})" -f $_.ReferencingAttribute, $_.ReferencedEntity, $_.ReferencingEntityNavigationPropertyName }
  Write-Host "  quick-create enabled:" ((Invoke-RestMethod -Uri "$Api/EntityDefinitions(LogicalName='$t')?`$select=IsQuickCreateEnabled" -Headers $H).IsQuickCreateEnabled) -ForegroundColor DarkCyan
  Write-Host "  rows:" ((Invoke-RestMethod -Uri "$Api/$(if($t -eq 'cap_timeentry'){'cap_timeentries'}else{$t+'s'})?`$select=${t}id&`$top=1&`$count=true" -Headers ($H + @{ Prefer='odata.include-annotations="*"' })).'@odata.count') -ForegroundColor DarkCyan
}

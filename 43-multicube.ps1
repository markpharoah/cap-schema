# ============================================================================
# 43-multicube.ps1 — Session 38 Part 2
# Creates the one true absentee: MultiCube Stockfeeds as cap_entity + a CFO
# engagement (Monthly fixed rhythm, AS scope No - no lodgement work yet).
# PLAN mode (default) prints the choice options for entity type and engagement
# type so the values are chosen from reality; APPLY takes them as parameters.
#   .\43-multicube.ps1                                   -> plan/probe
#   .\43-multicube.ps1 -Apply -EntityType N -EngagementType N
# Idempotent on cap_clientcode.
# ============================================================================
param([switch]$Apply, [int]$EntityType, [int]$EngagementType,
      [string]$Code='MUL0001', [string]$Name='MultiCube Stockfeeds Pty Ltd', [string]$EngName='MultiCube Stockfeeds - CFO services')
$ErrorActionPreference = 'Stop'
$Env = 'https://org020f7b5c.crm6.dynamics.com'
try   { $Token = Get-MsalToken -ClientId 'bcf0d51c-81f7-40e0-a485-c75ed82a02e3' -TenantId '46bc20d5-9c02-426f-b030-aea373177d31' -Scopes "$Env/.default" -Silent }
catch { $Token = Get-MsalToken -ClientId 'bcf0d51c-81f7-40e0-a485-c75ed82a02e3' -TenantId '46bc20d5-9c02-426f-b030-aea373177d31' -Scopes "$Env/.default" -Interactive }
$H  = @{ Authorization = "Bearer $($Token.AccessToken)"; Accept='application/json' }
$HW = $H + @{ 'Content-Type'='application/json' }
$Api = "$Env/api/data/v9.2"

function Show-Picklists($table) {
  $attrs = (Invoke-RestMethod -Uri "$Api/EntityDefinitions(LogicalName='$table')/Attributes/Microsoft.Dynamics.CRM.PicklistAttributeMetadata?`$select=LogicalName&`$expand=OptionSet(`$select=Options)" -Headers $H).value
  foreach ($a in $attrs) {
    Write-Host "  $($a.LogicalName):" -ForegroundColor Cyan
    foreach ($o in $a.OptionSet.Options) { Write-Host ("    {0}  {1}" -f $o.Value, $o.Label.UserLocalizedLabel.Label) }
  }
  $req = (Invoke-RestMethod -Uri "$Api/EntityDefinitions(LogicalName='$table')/Attributes?`$select=LogicalName,RequiredLevel&`$filter=IsCustomAttribute eq true" -Headers $H).value |
         Where-Object { $_.RequiredLevel.Value -in 'ApplicationRequired','SystemRequired' } | ForEach-Object LogicalName
  Write-Host "  required: $($req -join ', ')" -ForegroundColor DarkCyan
}
Write-Host "cap_entity picklists:" -ForegroundColor Cyan; Show-Picklists 'cap_entity'
Write-Host "`ncap_engagement picklists:" -ForegroundColor Cyan; Show-Picklists 'cap_engagement'

$ex = (Invoke-RestMethod -Uri "$Api/cap_entities?`$filter=cap_clientcode eq '$Code'&`$select=cap_entityid,cap_entityname" -Headers $H).value
if ($ex) { Write-Host "`nEntity $Code already exists: $($ex[0].cap_entityname)" -ForegroundColor Yellow }
if (-not $Apply) { Write-Host "`nPLAN only. Pick the entity-type and engagement-type values above, then:`n  .\43-multicube.ps1 -Apply -EntityType <n> -EngagementType <n>" -ForegroundColor Cyan; return }
if (-not $EntityType -or -not $EngagementType) { throw 'Apply needs -EntityType and -EngagementType values (see plan output).' }

# entity-type attribute name discovered from the picklist list (first cap_ picklist on cap_entity containing 'type')
$etAttr = ((Invoke-RestMethod -Uri "$Api/EntityDefinitions(LogicalName='cap_entity')/Attributes/Microsoft.Dynamics.CRM.PicklistAttributeMetadata?`$select=LogicalName" -Headers $H).value | Where-Object LogicalName -match 'type' | Select-Object -First 1).LogicalName
if (-not $etAttr) { throw 'Could not find an entity-type picklist on cap_entity' }
if ($ex) { $eid = $ex[0].cap_entityid }
else {
  $body = @{ cap_entityname=$Name; cap_clientcode=$Code; $etAttr=$EntityType; cap_status=764820000 }   # Active
  $r = Invoke-RestMethod -Method Post -Uri "$Api/cap_entities" -Headers ($HW + @{ Prefer='return=representation' }) -Body ($body | ConvertTo-Json)
  $eid = $r.cap_entityid; Write-Host "Entity created: $Name [$Code]" -ForegroundColor Green
}
$nav = ((Invoke-RestMethod -Uri "$Api/EntityDefinitions(LogicalName='cap_engagement')/ManyToOneRelationships?`$select=ReferencingEntityNavigationPropertyName,ReferencedEntity" -Headers $H).value | Where-Object ReferencedEntity -eq 'cap_entity').ReferencingEntityNavigationPropertyName
$eng = (Invoke-RestMethod -Uri "$Api/cap_engagements?`$filter=_cap_entityid_value eq $eid&`$select=cap_engagementid" -Headers $H).value
if ($eng) { Write-Host "Engagement already exists for $Code - skipping" -ForegroundColor Yellow }
else {
  $body = @{ cap_name=$EngName; cap_engagementtype=$EngagementType; cap_billingrhythm=764820001; cap_asscope=$false; "$nav@odata.bind"="/cap_entities($eid)" }
  Invoke-RestMethod -Method Post -Uri "$Api/cap_engagements" -Headers $HW -Body ($body | ConvertTo-Json) | Out-Null
  Write-Host "Engagement created: $EngName (Monthly fixed, AS scope No)" -ForegroundColor Green
}
Write-Host "43 complete." -ForegroundColor Green

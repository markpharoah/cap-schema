# ============================================================================
# 38-templates-seed.ps1 — Session 37 Part 2 (seed half; probe ran 15/9)
# Seeds three templates beside "Annual Accounting - Year End":
#   Tax Only Return (4 tasks/4 stages), Activity Statement (3 tasks),
#   Amendment (2 tasks). Weights sum 100 each; final task anchors 100%
#   (annual-on-completion billing moment); courts pinned 764820000 Practice /
#   764820001 Customer; showcustomer true per house default.
# Idempotent at BOTH grains: template found-or-created by name, tasks skipped
# by name within template. 0x80047013 "already exists" reported yellow (skip,
# not conflict — 15/9 lesson: stale metadata 404 + honest write side).
# ============================================================================
$ErrorActionPreference = 'Stop'
$Env = 'https://org020f7b5c.crm6.dynamics.com'
try   { $Token = Get-MsalToken -ClientId 'bcf0d51c-81f7-40e0-a485-c75ed82a02e3' -TenantId '46bc20d5-9c02-426f-b030-aea373177d31' -Scopes "$Env/.default" -Silent }
catch { $Token = Get-MsalToken -ClientId 'bcf0d51c-81f7-40e0-a485-c75ed82a02e3' -TenantId '46bc20d5-9c02-426f-b030-aea373177d31' -Scopes "$Env/.default" -Interactive }
$H  = @{ Authorization = "Bearer $($Token.AccessToken)"; 'OData-MaxVersion'='4.0'; 'OData-Version'='4.0'; Accept='application/json' }
$HW = $H + @{ 'Content-Type'='application/json' }
$Api = "$Env/api/data/v9.2"
$Practice = 764820000; $Customer = 764820001

# Navigation property names are case-sensitive and set at relationship
# creation - never assume, ask metadata (15/9 lesson: 0x80048d19).
$NavProp = ((Invoke-RestMethod -Uri "$Api/EntityDefinitions(LogicalName='cap_tasktemplate')/ManyToOneRelationships?`$select=ReferencingEntityNavigationPropertyName,ReferencedEntity" -Headers $H).value |
  Where-Object ReferencedEntity -eq 'cap_jobtemplate').ReferencingEntityNavigationPropertyName
if (-not $NavProp) { throw 'Could not resolve jobtemplate navigation property from metadata' }
Write-Host "Lookup navigation property: $NavProp" -ForegroundColor Cyan

$Templates = @(
  @{ Name='Tax Only Return'
     Desc='Individual/simple return: no accounts, straight to LodgeIT. Final task anchors 100% (bill on completion). Ratified Session 37.'
     Tasks=@(
       @{ n='Receive source data';        st='Receive data';     seq=1; w=10; court=$Customer; ms=$null;           anchor=$null },
       @{ n='Prepare return';             st='Prepare';          seq=2; w=50; court=$Practice; ms=$null;           anchor=$null },
       @{ n='Draft to customer and sign'; st='Approve and sign'; seq=3; w=25; court=$Customer; ms='Return signed'; anchor=$null },
       @{ n='Lodge via LodgeIT';          st='Lodge';            seq=4; w=15; court=$Practice; ms='Completed';     anchor=100 } ) },
  @{ Name='Activity Statement'
     Desc='Single AS obligation (BAS/IAS, any cycle). Quiet by design - ranked by due date, never rings. Ratified Session 37.'
     Tasks=@(
       @{ n='Confirm data for period';    st='Prepare';          seq=1; w=30; court=$Customer; ms=$null;      anchor=$null },
       @{ n='Prepare activity statement'; st='Prepare';          seq=1; w=50; court=$Practice; ms=$null;      anchor=$null },
       @{ n='Lodge via LodgeIT';          st='Lodge';            seq=2; w=20; court=$Practice; ms='Lodged';   anchor=100 } ) },
  @{ Name='Amendment'
     Desc='Amendment to a lodged form - its own small job so completed history stays immutable. Ratified Session 37 (Jeffery/EIV precedent).'
     Tasks=@(
       @{ n='Prepare amendment';          st='Prepare';          seq=1; w=70; court=$Practice; ms=$null;      anchor=$null },
       @{ n='Lodge amendment';            st='Lodge';            seq=2; w=30; court=$Practice; ms='Lodged';   anchor=100 } ) }
)

foreach ($t in $Templates) {
  $found = (Invoke-RestMethod -Uri "$Api/cap_jobtemplates?`$filter=cap_name eq '$($t.Name)'&`$select=cap_jobtemplateid" -Headers $H).value
  if ($found) { $tid = $found[0].cap_jobtemplateid; Write-Host "Template '$($t.Name)' already exists - skipping create" -ForegroundColor Yellow }
  else {
    try {
      $r = Invoke-RestMethod -Method Post -Uri "$Api/cap_jobtemplates" -Headers ($HW + @{ Prefer='return=representation' }) `
           -Body (@{ cap_name=$t.Name; cap_description=$t.Desc } | ConvertTo-Json)
      $tid = $r.cap_jobtemplateid; Write-Host "Template '$($t.Name)' created" -ForegroundColor Green
    } catch {
      if ("$_" -match '0x80047013') { Write-Host "Template '$($t.Name)' already exists (stale-404 family) - re-querying" -ForegroundColor Yellow
        $tid = (Invoke-RestMethod -Uri "$Api/cap_jobtemplates?`$filter=cap_name eq '$($t.Name)'&`$select=cap_jobtemplateid" -Headers $H).value[0].cap_jobtemplateid
      } else { throw } }
  }
  $existing = @((Invoke-RestMethod -Uri "$Api/cap_tasktemplates?`$filter=_cap_jobtemplateid_value eq $tid&`$select=cap_name" -Headers $H).value | ForEach-Object cap_name)
  foreach ($k in $t.Tasks) {
    if ($existing -contains $k.n) { Write-Host "  task '$($k.n)' already exists - skipping" -ForegroundColor Yellow; continue }
    $body = @{ cap_name=$k.n; cap_stagename=$k.st; cap_stagesequence=$k.seq; cap_weight=$k.w
               cap_court=$k.court; cap_showcustomer=$true; "$NavProp@odata.bind"="/cap_jobtemplates($tid)" }
    if ($k.ms)     { $body.cap_ismilestone=$true; $body.cap_milestonename=$k.ms }
    if ($k.anchor) { $body.cap_billinganchorpercent=[decimal]$k.anchor }
    Invoke-RestMethod -Method Post -Uri "$Api/cap_tasktemplates" -Headers $HW -Body ($body | ConvertTo-Json) | Out-Null
    Write-Host "  task '$($k.n)' created (stage $($k.seq) $($k.st), w$($k.w))" -ForegroundColor Green
  }
}
Write-Host "`n38-templates-seed complete. Weights: 10+50+25+15 / 30+50+20 / 70+30 - all 100." -ForegroundColor Green

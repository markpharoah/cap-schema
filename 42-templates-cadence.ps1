# ============================================================================
# 42-templates-cadence.ps1 — Session 38 Part 1
# Three cadence/project templates ratified 17/9 (MultiCube shape):
#   CFO Monthly Cycle (one job per month), Budget & Forecast (quarterly),
#   Project (stamped once, lives until closed).
# Same idempotent seed pattern as 38; nav property resolved from metadata.
# ============================================================================
$ErrorActionPreference = 'Stop'
$Env = 'https://org020f7b5c.crm6.dynamics.com'
try   { $Token = Get-MsalToken -ClientId 'bcf0d51c-81f7-40e0-a485-c75ed82a02e3' -TenantId '46bc20d5-9c02-426f-b030-aea373177d31' -Scopes "$Env/.default" -Silent }
catch { $Token = Get-MsalToken -ClientId 'bcf0d51c-81f7-40e0-a485-c75ed82a02e3' -TenantId '46bc20d5-9c02-426f-b030-aea373177d31' -Scopes "$Env/.default" -Interactive }
$H  = @{ Authorization = "Bearer $($Token.AccessToken)"; 'OData-MaxVersion'='4.0'; 'OData-Version'='4.0'; Accept='application/json' }
$HW = $H + @{ 'Content-Type'='application/json' }
$Api = "$Env/api/data/v9.2"
$P = 764820000; $C = 764820001
$NavProp = ((Invoke-RestMethod -Uri "$Api/EntityDefinitions(LogicalName='cap_tasktemplate')/ManyToOneRelationships?`$select=ReferencingEntityNavigationPropertyName,ReferencedEntity" -Headers $H).value | Where-Object ReferencedEntity -eq 'cap_jobtemplate').ReferencingEntityNavigationPropertyName

$Templates = @(
  @{ Name='CFO Monthly Cycle'; Desc='Retainer heartbeat: one job per month for Monthly-fixed engagements. Weekly KPIs as four tasks so a missed week is visible; management accounts and strategic review are the milestones. Ratified 17/9.'
     Tasks=@(
       @{ n='Receive month-end data';     st='Data';       seq=1; w=10; court=$C; ms=$null },
       @{ n='Weekly KPI - week 1';        st='KPIs';       seq=2; w=5;  court=$P; ms=$null },
       @{ n='Weekly KPI - week 2';        st='KPIs';       seq=2; w=5;  court=$P; ms=$null },
       @{ n='Weekly KPI - week 3';        st='KPIs';       seq=2; w=5;  court=$P; ms=$null },
       @{ n='Weekly KPI - week 4';        st='KPIs';       seq=2; w=5;  court=$P; ms=$null },
       @{ n='Management accounts';        st='Reporting';  seq=3; w=35; court=$P; ms='Management accounts issued' },
       @{ n='Cashflow update';            st='Reporting';  seq=3; w=15; court=$P; ms=$null },
       @{ n='Strategic review with owners'; st='Review';   seq=4; w=20; court=$C; ms='Completed'; anchor=100 } ) },
  @{ Name='Budget & Forecast'; Desc='Quarterly reforecast; the Q4 instance is the annual budget. Stamped four times a year so forecasting is not a permanent nag inside every month. Ratified 17/9.'
     Tasks=@(
       @{ n='Gather assumptions';         st='Inputs';     seq=1; w=20; court=$C; ms=$null },
       @{ n='Build reforecast';           st='Model';      seq=2; w=50; court=$P; ms=$null },
       @{ n='Review with owners';         st='Review';     seq=3; w=30; court=$C; ms='Completed'; anchor=100 } ) },
  @{ Name='Project'; Desc='Non-recurring engagement work (dispute resolution, systems design, restructures). Stamped once, lives until closed; milestones carry the real stages. Ratified 17/9.'
     Tasks=@(
       @{ n='Scope';                      st='Scope';      seq=1; w=15; court=$P; ms='Scoped' },
       @{ n='Work';                       st='Work';       seq=2; w=50; court=$P; ms=$null },
       @{ n='Deliver';                    st='Deliver';    seq=3; w=25; court=$C; ms='Delivered' },
       @{ n='Close';                      st='Close';      seq=4; w=10; court=$P; ms='Completed'; anchor=100 } ) }
)
foreach ($t in $Templates) {
  $found = (Invoke-RestMethod -Uri "$Api/cap_jobtemplates?`$filter=cap_name eq '$($t.Name.Replace("&","%26"))'&`$select=cap_jobtemplateid" -Headers $H).value
  if ($found) { $tid = $found[0].cap_jobtemplateid; Write-Host "Template '$($t.Name)' already exists - skipping create" -ForegroundColor Yellow }
  else { $r = Invoke-RestMethod -Method Post -Uri "$Api/cap_jobtemplates" -Headers ($HW + @{ Prefer='return=representation' }) -Body (@{ cap_name=$t.Name; cap_description=$t.Desc } | ConvertTo-Json)
         $tid = $r.cap_jobtemplateid; Write-Host "Template '$($t.Name)' created" -ForegroundColor Green }
  $existing = @((Invoke-RestMethod -Uri "$Api/cap_tasktemplates?`$filter=_cap_jobtemplateid_value eq $tid&`$select=cap_name" -Headers $H).value | ForEach-Object cap_name)
  foreach ($k in $t.Tasks) {
    if ($existing -contains $k.n) { Write-Host "  task '$($k.n)' exists - skipping" -ForegroundColor Yellow; continue }
    $b = @{ cap_name=$k.n; cap_stagename=$k.st; cap_stagesequence=$k.seq; cap_weight=$k.w; cap_court=$k.court; cap_showcustomer=$true; "$NavProp@odata.bind"="/cap_jobtemplates($tid)" }
    if ($k.ms) { $b.cap_ismilestone=$true; $b.cap_milestonename=$k.ms }
    if ($k.anchor) { $b.cap_billinganchorpercent=[decimal]$k.anchor }
    Invoke-RestMethod -Method Post -Uri "$Api/cap_tasktemplates" -Headers $HW -Body ($b | ConvertTo-Json) | Out-Null
    Write-Host "  task '$($k.n)' created (stage $($k.seq) $($k.st), w$($k.w))" -ForegroundColor Green }
}
Write-Host "`n42 complete. Weights: 10+20+35+15+20 / 20+50+30 / 15+50+25+10 - all 100." -ForegroundColor Green

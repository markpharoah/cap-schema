# ============================================================================
# 44-stamp-cadence.ps1 — Session 38 Part 2: the crank.
# Cadence jobs exist because the engagement says so, not because a form does.
#   Monthly fixed rhythm  -> "CODE · CFO <Mon YYYY>" from 'CFO Monthly Cycle'
#                            for the target month (default: current month)
#   -Forecast             -> also "CODE · Budget & Forecast Q<n> FY<yy>"
#   -Project CODE -ProjectName 'X' -> one "CODE · X" job from 'Project'
# PLAN by default; -Apply stamps. Idempotent on job name. Run on the 1st of
# the month beside the AS sweep; -Month 2026-11 stamps ahead.
# ============================================================================
param([switch]$Apply, [string]$Month, [switch]$Forecast, [string]$Project, [string]$ProjectName)
$ErrorActionPreference = 'Stop'
$Env = 'https://org020f7b5c.crm6.dynamics.com'
try   { $Token = Get-MsalToken -ClientId 'bcf0d51c-81f7-40e0-a485-c75ed82a02e3' -TenantId '46bc20d5-9c02-426f-b030-aea373177d31' -Scopes "$Env/.default" -Silent }
catch { $Token = Get-MsalToken -ClientId 'bcf0d51c-81f7-40e0-a485-c75ed82a02e3' -TenantId '46bc20d5-9c02-426f-b030-aea373177d31' -Scopes "$Env/.default" -Interactive }
$H  = @{ Authorization = "Bearer $($Token.AccessToken)"; Accept='application/json' }
$HW = $H + @{ 'Content-Type'='application/json' }
$Api = "$Env/api/data/v9.2"
$Mode = if ($Apply) { 'APPLY' } else { 'PLAN (no writes)' }; Write-Host "Mode: $Mode`n" -ForegroundColor Cyan

function NavProp($from,$to) { ((Invoke-RestMethod -Uri "$Api/EntityDefinitions(LogicalName='$from')/ManyToOneRelationships?`$select=ReferencingEntityNavigationPropertyName,ReferencedEntity" -Headers $H).value | Where-Object ReferencedEntity -eq $to)[0].ReferencingEntityNavigationPropertyName }
$NavTaskJob = NavProp 'cap_task' 'cap_job'
$JobNav = @{}; foreach ($t in 'cap_engagement','cap_entity','cap_jobtemplate') { try { $JobNav[$t] = NavProp 'cap_job' $t } catch { } }
$templates = @{}; foreach ($t in (Invoke-RestMethod -Uri "$Api/cap_jobtemplates?`$select=cap_jobtemplateid,cap_name" -Headers $H).value) { $templates[$t.cap_name] = $t.cap_jobtemplateid }
$existing = @{}; $url="$Api/cap_jobs?`$select=cap_name"; do { $r=Invoke-RestMethod -Uri $url -Headers $H; foreach($j in $r.value){$existing[$j.cap_name]=1}; $url=$r.'@odata.nextLink' } while ($url)

$m = if ($Month) { [datetime]::ParseExact($Month,'yyyy-MM',$null) } else { Get-Date -Day 1 }
$mStart = $m.Date.AddDays(1-$m.Day); $mEnd = $mStart.AddMonths(1).AddDays(-1)
$fy = if ($mStart.Month -ge 7) { $mStart.Year+1 } else { $mStart.Year }
$q  = [math]::Floor((($mStart.Month + 5) % 12) / 3) + 1
$qStart = $mStart.AddMonths(-(($mStart.Month + 5) % 3)); $qEnd = $qStart.AddMonths(3).AddDays(-1)

function Stamp($name,$tmpl,$ent,$eng,$due,$ps,$pe,$desc) {
  if ($existing.ContainsKey($name)) { Write-Host "SKIP  $name (exists)" -ForegroundColor Yellow; return }
  if (-not $templates.ContainsKey($tmpl)) { Write-Host "FLAG  $name - template '$tmpl' missing" -ForegroundColor Red; return }
  $tasks = (Invoke-RestMethod -Uri "$Api/cap_tasktemplates?`$filter=_cap_jobtemplateid_value eq $($templates[$tmpl])&`$select=cap_name,cap_stagename,cap_stagesequence,cap_weight,cap_court,cap_showcustomer,cap_ismilestone,cap_milestonename,cap_billinganchorpercent" -Headers $H).value | Sort-Object cap_stagesequence
  if (-not $Apply) { Write-Host ("PLAN  {0}  [{1}] {2} tasks, due {3}" -f $name,$tmpl,$tasks.Count,($(if($due){$due.ToString('dd/MM/yyyy')}else{'(open)'}))) -ForegroundColor Green; return }
  $jb = @{ cap_name=$name; cap_description=$desc }
  if ($due) { $jb.cap_duedate=$due.ToString('yyyy-MM-dd') }
  if ($ps)  { $jb.cap_periodstart=$ps.ToString('yyyy-MM-dd'); $jb.cap_periodend=$pe.ToString('yyyy-MM-dd') }
  if ($JobNav['cap_engagement']) { $jb["$($JobNav['cap_engagement'])@odata.bind"]="/cap_engagements($eng)" }
  if ($JobNav['cap_entity'])     { $jb["$($JobNav['cap_entity'])@odata.bind"]="/cap_entities($ent)" }
  if ($JobNav['cap_jobtemplate']){ $jb["$($JobNav['cap_jobtemplate'])@odata.bind"]="/cap_jobtemplates($($templates[$tmpl]))" }
  $r = Invoke-RestMethod -Method Post -Uri "$Api/cap_jobs" -Headers ($HW + @{ Prefer='return=representation' }) -Body ($jb | ConvertTo-Json)
  $maxSeq = ($tasks | Measure-Object cap_stagesequence -Maximum).Maximum
  foreach ($k in $tasks) {
    $tb = @{ cap_name=$k.cap_name; cap_stagename=$k.cap_stagename; cap_stagesequence=$k.cap_stagesequence; cap_weight=$k.cap_weight; cap_court=$k.cap_court; cap_showcustomer=$k.cap_showcustomer; "$NavTaskJob@odata.bind"="/cap_jobs($($r.cap_jobid))" }
    if ($k.cap_ismilestone) { $tb.cap_ismilestone=$true; $tb.cap_milestonename=$k.cap_milestonename }
    if ($k.cap_billinganchorpercent) { $tb.cap_billinganchorpercent=$k.cap_billinganchorpercent }
    if ($due -and $k.cap_stagesequence -eq $maxSeq) { $tb.cap_duedate=$due.ToString('yyyy-MM-dd') }
    Invoke-RestMethod -Method Post -Uri "$Api/cap_tasks" -Headers $HW -Body ($tb | ConvertTo-Json) | Out-Null }
  $existing[$name]=1; Write-Host ("STAMP {0}  [{1}] {2} tasks" -f $name,$tmpl,$tasks.Count) -ForegroundColor Green
}

# --- monthly cadence ---
$monthly = (Invoke-RestMethod -Uri "$Api/cap_engagements?`$filter=cap_billingrhythm eq 764820001 and statecode eq 0&`$select=cap_engagementid,cap_name&`$expand=cap_entityid(`$select=cap_entityid,cap_clientcode,cap_entityname)" -Headers $H).value
Write-Host "Monthly-fixed engagements: $($monthly.Count)  | target month $($mStart.ToString('MMM yyyy'))" -ForegroundColor Cyan
foreach ($e in $monthly) {
  $code = $e.cap_entityid.cap_clientcode; $ent=$e.cap_entityid.cap_entityid
  Stamp "$code · CFO $($mStart.ToString('MMM yyyy'))" 'CFO Monthly Cycle' $ent $e.cap_engagementid $mEnd $mStart $mEnd "Cadence job: monthly CFO cycle for $($e.cap_entityid.cap_entityname), $($mStart.ToString('MMMM yyyy')). Stamped by 44."
  if ($Forecast) { Stamp "$code · Budget & Forecast Q$q FY$($fy.ToString().Substring(2))" 'Budget & Forecast' $ent $e.cap_engagementid $qEnd $qStart $qEnd "Cadence job: quarterly reforecast Q$q FY$fy. Stamped by 44." }
}
# --- project ---
if ($Project) {
  if (-not $ProjectName) { throw '-Project needs -ProjectName' }
  $en = (Invoke-RestMethod -Uri "$Api/cap_entities?`$filter=cap_clientcode eq '$Project'&`$select=cap_entityid,cap_entityname" -Headers $H).value
  if (-not $en) { throw "Entity $Project not found" }
  $eg = (Invoke-RestMethod -Uri "$Api/cap_engagements?`$filter=_cap_entityid_value eq $($en[0].cap_entityid)&`$select=cap_engagementid" -Headers $H).value
  Stamp "$Project · $ProjectName" 'Project' $en[0].cap_entityid $eg[0].cap_engagementid $null $null $null "Project job: $ProjectName for $($en[0].cap_entityname). Lives until closed. Stamped by 44."
}
Write-Host "`n44 $Mode complete." -ForegroundColor Cyan

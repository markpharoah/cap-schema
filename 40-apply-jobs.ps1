# ============================================================================
# 40-apply-jobs.ps1 — Session 37 Part 3 (apply half)
# Reads data\job-proposals.csv, and for every row with Accept ticked
# (x/y/1/yes), stamps a cap_job from its template with the template's tasks.
# TWO MODES:
#   .\40-apply-jobs.ps1          -> PLAN: probes schema, resolves everything,
#                                   prints what WOULD be stamped. No writes.
#   .\40-apply-jobs.ps1 -Apply   -> stamps for real.
# Idempotent on deterministic job name "CODE · Period" — existing names skip.
# Nav properties resolved from metadata (15/9 lesson). Engagement chosen per
# entity: single -> it; multiple -> yellow-flagged, first used in plan for
# review. Due date: written to cap_job duedate if the column exists, else to
# the final-stage tasks; always echoed in plan.
# ============================================================================
param([switch]$Apply)
$ErrorActionPreference = 'Stop'
$Env = 'https://org020f7b5c.crm6.dynamics.com'
try   { $Token = Get-MsalToken -ClientId 'bcf0d51c-81f7-40e0-a485-c75ed82a02e3' -TenantId '46bc20d5-9c02-426f-b030-aea373177d31' -Scopes "$Env/.default" -Silent }
catch { $Token = Get-MsalToken -ClientId 'bcf0d51c-81f7-40e0-a485-c75ed82a02e3' -TenantId '46bc20d5-9c02-426f-b030-aea373177d31' -Scopes "$Env/.default" -Interactive }
$H  = @{ Authorization = "Bearer $($Token.AccessToken)"; Accept='application/json' }
$HW = $H + @{ 'Content-Type'='application/json' }
$Api = "$Env/api/data/v9.2"
$Mode = if ($Apply) { 'APPLY' } else { 'PLAN (no writes - rerun with -Apply to stamp)' }
Write-Host "Mode: $Mode`n" -ForegroundColor Cyan

# --- metadata probes: nav properties + optional job columns ---
function NavProp($from,$to) {
  $r = (Invoke-RestMethod -Uri "$Api/EntityDefinitions(LogicalName='$from')/ManyToOneRelationships?`$select=ReferencingEntityNavigationPropertyName,ReferencedEntity" -Headers $H).value |
       Where-Object ReferencedEntity -eq $to
  if (-not $r) { throw "No $from -> $to relationship found" }
  $r[0].ReferencingEntityNavigationPropertyName
}
$NavTaskJob = NavProp 'cap_task' 'cap_job'
$JobNavs = @{}
foreach ($t in 'cap_engagement','cap_entity','cap_jobtemplate') {
  try { $JobNavs[$t] = NavProp 'cap_job' $t } catch { }
}
$jobAttrs = ((Invoke-RestMethod -Uri "$Api/EntityDefinitions(LogicalName='cap_job')/Attributes?`$select=LogicalName&`$filter=IsCustomAttribute eq true" -Headers $H).value).LogicalName
$taskAttrs = ((Invoke-RestMethod -Uri "$Api/EntityDefinitions(LogicalName='cap_task')/Attributes?`$select=LogicalName&`$filter=IsCustomAttribute eq true" -Headers $H).value).LogicalName
$jobHasDue  = $jobAttrs -contains 'cap_duedate'
$jobHasPeriod = $jobAttrs -contains 'cap_period'
Write-Host "cap_task->cap_job nav: $NavTaskJob" -ForegroundColor Cyan
Write-Host "cap_job navs: $($JobNavs.Keys -join ', ') | duedate on job: $jobHasDue | period on job: $jobHasPeriod" -ForegroundColor Cyan
Write-Host "cap_job custom attrs: $($jobAttrs -join ', ')" -ForegroundColor DarkCyan
Write-Host "cap_task custom attrs: $($taskAttrs -join ', ')`n" -ForegroundColor DarkCyan

# --- load ticked proposals ---
$csv = Import-Csv "$PSScriptRoot\data\job-proposals.csv"
$tick = $csv | Where-Object { "$($_.Accept)".Trim() -match '^(x|y|yes|1)$' }
Write-Host "Proposals: $($csv.Count) rows, $($tick.Count) ticked`n" -ForegroundColor Cyan
if (-not $tick) { Write-Host 'Nothing ticked - tick Accept in data\job-proposals.csv first.' -ForegroundColor Yellow; return }

# --- caches ---
$templates = @{}
foreach ($t in (Invoke-RestMethod -Uri "$Api/cap_jobtemplates?`$select=cap_jobtemplateid,cap_name" -Headers $H).value) { $templates[$t.cap_name] = $t.cap_jobtemplateid }
$taskT = @{}
foreach ($tn in $templates.Keys) {
  $taskT[$tn] = (Invoke-RestMethod -Uri "$Api/cap_tasktemplates?`$filter=_cap_jobtemplateid_value eq $($templates[$tn])&`$select=cap_name,cap_stagename,cap_stagesequence,cap_weight,cap_court,cap_showcustomer,cap_ismilestone,cap_milestonename,cap_billinganchorpercent" -Headers $H).value | Sort-Object cap_stagesequence
}
if (-not $templates.ContainsKey('Year End (SMSF)')) { }  # falls back below

$existingJobs = @{}
foreach ($j in (Invoke-RestMethod -Uri "$Api/cap_jobs?`$select=cap_jobid,cap_name" -Headers $H).value) { $existingJobs[$j.cap_name] = $j.cap_jobid }

$stamped=0; $skipped=0; $flagged=0
foreach ($row in $tick) {
  $jobName = "$($row.ClientCode) · $($row.Period)"
  if ($existingJobs.ContainsKey($jobName)) { Write-Host "SKIP  $jobName (exists)" -ForegroundColor Yellow; $skipped++; continue }
  $tmplName = $row.Template
  if (-not $templates.ContainsKey($tmplName)) {
    if ($tmplName -eq 'Year End (SMSF)' -and $templates.ContainsKey('Year End')) { $tmplName = 'Year End' }
    else { Write-Host "FLAG  $jobName - template '$($row.Template)' not found" -ForegroundColor Red; $flagged++; continue } }
  $ent = (Invoke-RestMethod -Uri "$Api/cap_entities?`$filter=cap_clientcode eq '$($row.ClientCode)'&`$select=cap_entityid,cap_entityname" -Headers $H).value
  if (-not $ent) { Write-Host "FLAG  $jobName - entity not found for $($row.ClientCode)" -ForegroundColor Red; $flagged++; continue }
  $eng = (Invoke-RestMethod -Uri "$Api/cap_engagements?`$filter=_cap_entityid_value eq $($ent[0].cap_entityid)&`$select=cap_engagementid" -Headers $H).value
  $engNote = ''
  if ($eng.Count -gt 1) { $engNote = " [entity has $($eng.Count) engagements - using first; review]"; }
  elseif (-not $eng) { Write-Host "FLAG  $jobName - no engagement for $($row.ClientCode)" -ForegroundColor Red; $flagged++; continue }
  $tasks = $taskT[$tmplName]
  $maxSeq = ($tasks | Measure-Object cap_stagesequence -Maximum).Maximum

  if (-not $Apply) {
    $col = if ($engNote) { 'Yellow' } else { 'Green' }
    Write-Host ("PLAN  {0}  [{1}] {2} tasks, due {3}{4}" -f $jobName,$tmplName,$tasks.Count,($row.DueDate -replace '^$','(none)'),$engNote) -ForegroundColor $col
    if ($engNote) { $flagged++ }
    continue
  }
  # --- APPLY ---
  $jb = @{ cap_name = $jobName; cap_description = "Stamped Session 37 from $((Get-ChildItem "$PSScriptRoot\data\lodgeit-allstatus-*.xlsx" | Sort-Object LastWriteTime -Descending | Select-Object -First 1).Name). $($row.JobClass). Forms: $($row.FormDetail). Key: $($row.Key)$engNote" }
  if ($jobHasPeriod) { $jb.cap_period = $row.Period }
  if ($jobHasDue -and $row.DueDate) { $jb.cap_duedate = [datetime]::ParseExact($row.DueDate,'dd/MM/yyyy',$null).ToString('yyyy-MM-dd') }
  if ($JobNavs['cap_engagement']) { $jb["$($JobNavs['cap_engagement'])@odata.bind"] = "/cap_engagements($($eng[0].cap_engagementid))" }
  if ($JobNavs['cap_entity'])     { $jb["$($JobNavs['cap_entity'])@odata.bind"]     = "/cap_entities($($ent[0].cap_entityid))" }
  if ($JobNavs['cap_jobtemplate']){ $jb["$($JobNavs['cap_jobtemplate'])@odata.bind"]= "/cap_jobtemplates($($templates[$tmplName]))" }
  $r = Invoke-RestMethod -Method Post -Uri "$Api/cap_jobs" -Headers ($HW + @{ Prefer='return=representation' }) -Body ($jb | ConvertTo-Json)
  foreach ($k in $tasks) {
    $tb = @{ cap_name=$k.cap_name; cap_stagename=$k.cap_stagename; cap_stagesequence=$k.cap_stagesequence
             cap_weight=$k.cap_weight; cap_court=$k.cap_court; cap_showcustomer=$k.cap_showcustomer
             "$NavTaskJob@odata.bind"="/cap_jobs($($r.cap_jobid))" }
    if ($k.cap_ismilestone) { $tb.cap_ismilestone=$true; $tb.cap_milestonename=$k.cap_milestonename }
    if ($k.cap_billinganchorpercent) { $tb.cap_billinganchorpercent=$k.cap_billinganchorpercent }
    if ((-not $jobHasDue) -and $row.DueDate -and $k.cap_stagesequence -eq $maxSeq -and ($taskAttrs -contains 'cap_duedate')) {
      $tb.cap_duedate = [datetime]::ParseExact($row.DueDate,'dd/MM/yyyy',$null).ToString('yyyy-MM-dd') }
    Invoke-RestMethod -Method Post -Uri "$Api/cap_tasks" -Headers $HW -Body ($tb | ConvertTo-Json) | Out-Null
  }
  $existingJobs[$jobName] = $r.cap_jobid
  Write-Host ("STAMP {0}  [{1}] {2} tasks, due {3}{4}" -f $jobName,$tmplName,$tasks.Count,$row.DueDate,$engNote) -ForegroundColor Green
  $stamped++
}
Write-Host ("`n{0} complete: {1} stamped, {2} skipped, {3} flagged." -f $Mode,$stamped,$skipped,$flagged) -ForegroundColor Cyan
if (-not $Apply) { Write-Host 'Review the plan (yellow = multi-engagement picks), then rerun with -Apply.' -ForegroundColor Cyan }

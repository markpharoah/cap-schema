# ============================================================================
# 46-stewardship-tasks.ps1 — Session 39 Part 1
# The amended Lewis ruling (15/9): scope limits work, never sight. For every
# engagement with cap_asscope = No, each ACTIVE job of that entity gains one
# standing task "Stewardship review: ATO position incl. out-of-scope AS" —
# court Practice, showcustomer No, weight 0 (informational; never moves
# percent), stage 0 "Stewardship" so it sits first. Description carries the
# stewardship register lines for that client from data\stewardship-register.csv.
# PLAN default; -Apply writes. Idempotent on task name per job.
# ============================================================================
param([switch]$Apply)
$ErrorActionPreference = 'Stop'
$Env = 'https://org020f7b5c.crm6.dynamics.com'
try   { $Token = Get-MsalToken -ClientId 'bcf0d51c-81f7-40e0-a485-c75ed82a02e3' -TenantId '46bc20d5-9c02-426f-b030-aea373177d31' -Scopes "$Env/.default" -Silent }
catch { $Token = Get-MsalToken -ClientId 'bcf0d51c-81f7-40e0-a485-c75ed82a02e3' -TenantId '46bc20d5-9c02-426f-b030-aea373177d31' -Scopes "$Env/.default" -Interactive }
$H  = @{ Authorization = "Bearer $($Token.AccessToken)"; Accept='application/json' }
$HW = $H + @{ 'Content-Type'='application/json' }
$Api = "$Env/api/data/v9.2"
$Practice = 764820000
$NavTaskJob = ((Invoke-RestMethod -Uri "$Api/EntityDefinitions(LogicalName='cap_task')/ManyToOneRelationships?`$select=ReferencingEntityNavigationPropertyName,ReferencedEntity" -Headers $H).value | Where-Object ReferencedEntity -eq 'cap_job')[0].ReferencingEntityNavigationPropertyName
$TaskName = 'Stewardship review: ATO position incl. out-of-scope AS'
$reg = @{}
$regPath = "$PSScriptRoot\data\stewardship-register.csv"
if (Test-Path $regPath) { Import-Csv $regPath | Group-Object ClientCode | ForEach-Object { $reg[$_.Name] = $_.Group } }
$eng = (Invoke-RestMethod -Uri "$Api/cap_engagements?`$filter=cap_asscope eq false and statecode eq 0&`$select=cap_engagementid&`$expand=cap_entityid(`$select=cap_entityid,cap_clientcode,cap_entityname)" -Headers $H).value
Write-Host "Mode: $(if($Apply){'APPLY'}else{'PLAN (no writes)'}) | AS-scope-No engagements: $($eng.Count)`n" -ForegroundColor Cyan
$added=0; $skipped=0
foreach ($e in $eng) {
  $code = $e.cap_entityid.cap_clientcode; $eid = $e.cap_entityid.cap_entityid
  $jobs = (Invoke-RestMethod -Uri "$Api/cap_jobs?`$filter=_cap_entityid_value eq $eid and statecode eq 0&`$select=cap_jobid,cap_name" -Headers $H).value
  $lines = if ($reg[$code]) { ($reg[$code] | ForEach-Object { "  $($_.Obligation) $($_.PeriodStart)–$($_.PeriodEnd) due $($_.DueDate)" }) -join "`n" } else { '  (no out-of-scope obligations at last sweep)' }
  $asAt = if ($reg[$code]) { $reg[$code][0].AsAtSweep } else { 'n/a' }
  $n = ($reg[$code] | Measure-Object).Count
  if ($n -eq 0) { Write-Host "SKIP  $code - AS scope No but no out-of-scope obligations (no-lodgement engagement, not stewardship)" -ForegroundColor DarkYellow; continue }
  foreach ($j in $jobs) {
    $has = (Invoke-RestMethod -Uri "$Api/cap_tasks?`$filter=_cap_jobid_value eq $($j.cap_jobid) and cap_name eq '$($TaskName.Replace("'","''"))'&`$select=cap_taskid" -Headers $H).value
    if ($has) { Write-Host "SKIP  $($j.cap_name) (task exists)" -ForegroundColor Yellow; $skipped++; continue }
    if (-not $Apply) { Write-Host "PLAN  $($j.cap_name)  <- $($TaskName) [$n obligations]" -ForegroundColor Green; continue }
    # task is lean (cap_task has no description column); the register lines go on the JOB description
    $body = @{ cap_name=$TaskName; cap_stagename='Stewardship'; cap_stagesequence=0; cap_weight=0; cap_court=$Practice; cap_showcustomer=$false
      "$NavTaskJob@odata.bind"="/cap_jobs($($j.cap_jobid))" }
    Invoke-RestMethod -Method Post -Uri "$Api/cap_tasks" -Headers $HW -Body ($body | ConvertTo-Json) | Out-Null
    $jd = (Invoke-RestMethod -Uri "$Api/cap_jobs($($j.cap_jobid))?`$select=cap_description" -Headers $H).cap_description
    if ("$jd" -notmatch 'STEWARDSHIP') {
      $jd = "$jd`n`nSTEWARDSHIP (as at sweep $asAt) - AS scope No: we do not prepare these, we advise on them:`n$lines"
      Invoke-RestMethod -Method Patch -Uri "$Api/cap_jobs($($j.cap_jobid))" -Headers $HW -Body (@{ cap_description=$jd } | ConvertTo-Json) | Out-Null }
    Write-Host "ADD   $($j.cap_name)  <- $($TaskName) ($n obligations noted on job)" -ForegroundColor Green; $added++
  }
}
Write-Host "`n46 complete: $added added, $skipped skipped." -ForegroundColor Cyan

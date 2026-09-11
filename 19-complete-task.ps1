# 19-complete-task.ps1 — complete task(s) on a job, then derive (DATA/TOOL)
#
# DOCTRINE: bulk-complete, never override. Completing = deactivating the
# task row (statecode 1, statuscode 2) - the platform dates and attributes
# it. The % is never touched; it derives. This script IS the future app
# "complete" verb, prototyped: name one task, or -Stage N for the
# stage-level bulk, or -All for complete-all-remaining.
#
# USAGE:
#   .\19-complete-task.ps1                                    (demo: stage 1 of Harborne FY2026)
#   .\19-complete-task.ps1 -Task "Process CAP"
#   .\19-complete-task.ps1 -Stage 2
#   .\19-complete-task.ps1 -All
#   (add -Job "..." for any other job when they exist)

param(
    [string]$Job   = "Harborne - Annual Accounting - FY2026",
    [string]$Task  = "",
    [int]$Stage    = 0,
    [switch]$All
)
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

# --- Resolve job ----------------------------------------------------------------------
$j = (Invoke-RestMethod -Uri "$api/cap_jobs?`$select=cap_jobid&`$filter=cap_name eq '$Job'" -Headers $headers -Method Get).value
if ($j.Count -lt 1) { Write-Host "Job not found: $Job" -ForegroundColor Red; exit 1 }
$jobId = $j[0].cap_jobid

# --- Pick targets ----------------------------------------------------------------------
$open = (Invoke-RestMethod -Uri "$api/cap_tasks?`$select=cap_taskid,cap_name,cap_stagesequence&`$filter=_cap_jobid_value eq $jobId and statecode eq 0" -Headers $headers -Method Get).value
if ($open.Count -eq 0) { Write-Host "No open tasks - job is complete." -ForegroundColor Green; $targets = @() }
elseif ($Task)  { $targets = @($open | Where-Object { $_.cap_name -eq $Task });  if ($targets.Count -eq 0) { Write-Host "No open task named '$Task'." -ForegroundColor Red; exit 1 } }
elseif ($All)   { $targets = @($open) }
elseif ($Stage -gt 0) { $targets = @($open | Where-Object { $_.cap_stagesequence -eq $Stage }); if ($targets.Count -eq 0) { Write-Host "No open tasks in stage $Stage." -ForegroundColor Red; exit 1 } }
else {
    # DEMO default: the earliest-incomplete stage's tasks (today: stage 1)
    $seq = ($open | Measure-Object cap_stagesequence -Minimum).Minimum
    $targets = @($open | Where-Object { $_.cap_stagesequence -eq $seq })
    Write-Host "Demo mode: completing earliest-incomplete stage (seq $seq)." -ForegroundColor Cyan
}

# --- Complete (deactivate: platform dates it) -------------------------------------------
foreach ($t in $targets) {
    $body = @{ statecode = 1; statuscode = 2 }
    Invoke-RestMethod -Uri "$api/cap_tasks($($t.cap_taskid))" -Headers $headers -Method Patch -Body ($body | ConvertTo-Json) | Out-Null
    Write-Host "  Completed: $($t.cap_name)" -ForegroundColor Green
}

# --- DERIVE (identical logic to 18; the portal read) -------------------------------------
$tasks = (Invoke-RestMethod -Uri "$api/cap_tasks?`$select=cap_name,cap_weight,cap_stagesequence,cap_stagename,cap_court,cap_showcustomer,statecode&`$filter=_cap_jobid_value eq $jobId" -Headers $headers -Method Get).value
$wTotal = ($tasks | Measure-Object cap_weight -Sum).Sum
$done   = $tasks | Where-Object { $_.statecode -ne 0 }
$wDone  = if ($done) { ($done | Measure-Object cap_weight -Sum).Sum } else { 0 }
$pct    = if ($wTotal -gt 0) { [math]::Round(100 * $wDone / $wTotal) } else { 0 }
$openT  = $tasks | Where-Object { $_.statecode -eq 0 }
$courtNames = @{ 764820000 = "Practice"; 764820001 = "Customer"; 764820002 = "Third party" }

Write-Host "`n=== PORTAL DERIVATIONS ===" -ForegroundColor Cyan
Write-Host ("Job:        {0}" -f $Job)
Write-Host ("Progress:   {0}%  ({1} of {2} weight complete)" -f $pct, $wDone, $wTotal)
if ($openT.Count -eq 0) {
    Write-Host "Stage:      COMPLETE - all tasks done." -ForegroundColor Green
} else {
    $curSeq = ($openT | Measure-Object cap_stagesequence -Minimum).Minimum
    $curStage = ($openT | Where-Object { $_.cap_stagesequence -eq $curSeq } | Select-Object -First 1).cap_stagename
    $courts = $openT | Where-Object { $_.cap_stagesequence -eq $curSeq } |
        ForEach-Object { $courtNames[[int]$_.cap_court] } | Sort-Object -Unique
    $askable = $openT | Where-Object { $_.cap_stagesequence -eq $curSeq -and [int]$_.cap_court -eq 764820001 -and $_.cap_showcustomer }
    Write-Host ("Stage:      {0} (earliest incomplete, seq {1})" -f $curStage, $curSeq)
    Write-Host ("Court:      {0}" -f ($courts -join " + "))
    if ($askable) {
        Write-Host "Waiting on customer for:" -ForegroundColor Yellow
        $askable | ForEach-Object { Write-Host "  - $($_.cap_name)" -ForegroundColor Yellow }
    }
}
# 18-harborne-job.ps1 — the first job: Harborne FY2026, stamped + derived (DATA)
#
# PROOF RUN for the jobs spine. Exercises every doctrine as data:
#   - Engagement: Established basis (Harborne is "long-standing"), waiting
#     rule shown.
#   - Job: entity + engagement + period FY2026, thin.
#   - Stamp: all 12 template tasks copied - weight, stage, court, flags,
#     milestone names, anchors (the future app-layer stamp, prototyped).
#   - Derivations printed from raw reads (nothing stored): job % (weighted),
#     stage (earliest-incomplete), court scorecard (visible customer-court
#     tasks in the current stage).
#
# LESSON (undeclared property 'cap_EntityId'): cap_engagement predates this
# week's naming convention. PRE-WEEK TABLES (02-12) may name lookups
# differently; never assume a bind name on them - PROBE the relationship
# metadata for ReferencingEntityNavigationPropertyName (the authoritative
# bind name) and use what comes back. Week-13+ tables are ours and known.
#
# Rerun-safe on engagement name and job name; tasks keyed per name.

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

# --- 0) PROBE: the engagement->entity bind name (pre-week table, never assume) ------
$rels = (Invoke-RestMethod -Uri "$api/EntityDefinitions(LogicalName='cap_engagement')/ManyToOneRelationships?`$select=ReferencedEntity,ReferencingEntityNavigationPropertyName" -Headers $headers -Method Get).value
$entRel = $rels | Where-Object { $_.ReferencedEntity -eq "cap_entity" } | Select-Object -First 1
if (-not $entRel) { Write-Host "No cap_engagement->cap_entity relationship found - inspect manually." -ForegroundColor Red; exit 1 }
$engEntityNav = $entRel.ReferencingEntityNavigationPropertyName
Write-Host "Probed bind name: cap_engagement -> cap_entity = '$engEntityNav'" -ForegroundColor Cyan

# --- 1) Find Harborne ---------------------------------------------------------------
$ent = (Invoke-RestMethod -Uri "$api/cap_entities?`$select=cap_entityid,cap_entityname&`$filter=contains(cap_entityname,'Harborne')" -Headers $headers -Method Get).value
if ($ent.Count -lt 1) { Write-Host "No Harborne entity found." -ForegroundColor Red; exit 1 }
$harborne = $ent[0]
Write-Host "Entity: $($harborne.cap_entityname)" -ForegroundColor Cyan

# --- 2) Engagement (Established, waiting rule shown) --------------------------------
$engName = "Harborne - Annual Accounting"
$eng = (Invoke-RestMethod -Uri "$api/cap_engagements?`$select=cap_engagementid&`$filter=cap_name eq '$engName'" -Headers $headers -Method Get).value
if ($eng.Count -gt 0) {
    $engId = $eng[0].cap_engagementid
    Write-Host "Engagement exists - reusing." -ForegroundColor Yellow
} else {
    $body = @{
        cap_name             = $engName
        cap_evidencebasis    = 764820000   # Established
        cap_waitingruleshown = $true
        "$engEntityNav@odata.bind" = "/cap_entities($($harborne.cap_entityid))"
    }
    Invoke-RestMethod -Uri "$api/cap_engagements" -Headers $headers -Method Post -Body ($body | ConvertTo-Json) | Out-Null
    $engId = ((Invoke-RestMethod -Uri "$api/cap_engagements?`$select=cap_engagementid&`$filter=cap_name eq '$engName'" -Headers $headers -Method Get).value)[0].cap_engagementid
    Write-Host "Engagement created (Established basis)." -ForegroundColor Green
}

# --- 3) The job (week-13 table: bind names are ours and known) -----------------------
$jobName = "Harborne - Annual Accounting - FY2026"
$job = (Invoke-RestMethod -Uri "$api/cap_jobs?`$select=cap_jobid&`$filter=cap_name eq '$jobName'" -Headers $headers -Method Get).value
if ($job.Count -gt 0) {
    $jobId = $job[0].cap_jobid
    Write-Host "Job exists - reusing." -ForegroundColor Yellow
} else {
    $tpl = ((Invoke-RestMethod -Uri "$api/cap_jobtemplates?`$select=cap_jobtemplateid&`$filter=cap_name eq 'Annual Accounting - Year End'" -Headers $headers -Method Get).value)[0]
    $body = @{
        cap_name                        = $jobName
        cap_periodstart                 = "2025-07-01"
        cap_periodend                   = "2026-06-30"
        "cap_EntityId@odata.bind"       = "/cap_entities($($harborne.cap_entityid))"
        "cap_EngagementId@odata.bind"   = "/cap_engagements($engId)"
        "cap_JobTemplateId@odata.bind"  = "/cap_jobtemplates($($tpl.cap_jobtemplateid))"
    }
    Invoke-RestMethod -Uri "$api/cap_jobs" -Headers $headers -Method Post -Body ($body | ConvertTo-Json) | Out-Null
    $jobId = ((Invoke-RestMethod -Uri "$api/cap_jobs?`$select=cap_jobid&`$filter=cap_name eq '$jobName'" -Headers $headers -Method Get).value)[0].cap_jobid
    Write-Host "Job created: $jobName" -ForegroundColor Green
}

# --- 4) THE STAMP: template tasks -> job tasks ---------------------------------------
$tpl = ((Invoke-RestMethod -Uri "$api/cap_jobtemplates?`$select=cap_jobtemplateid&`$filter=cap_name eq 'Annual Accounting - Year End'" -Headers $headers -Method Get).value)[0]
$ttRows = (Invoke-RestMethod -Uri "$api/cap_tasktemplates?`$select=cap_name,cap_weight,cap_stagesequence,cap_stagename,cap_court,cap_showcustomer,cap_ismilestone,cap_milestonename,cap_billinganchorpercent&`$filter=_cap_jobtemplateid_value eq $($tpl.cap_jobtemplateid)" -Headers $headers -Method Get).value
$existing = (Invoke-RestMethod -Uri "$api/cap_tasks?`$select=cap_name&`$filter=_cap_jobid_value eq $jobId" -Headers $headers -Method Get).value | ForEach-Object { $_.cap_name }
$stamped = 0
foreach ($t in $ttRows) {
    if ($existing -contains $t.cap_name) { continue }
    $body = @{
        cap_name          = $t.cap_name
        cap_weight        = $t.cap_weight
        cap_stagesequence = $t.cap_stagesequence
        cap_stagename     = $t.cap_stagename
        cap_court         = $t.cap_court
        cap_showcustomer  = $t.cap_showcustomer
        cap_ismilestone   = $t.cap_ismilestone
        "cap_JobId@odata.bind" = "/cap_jobs($jobId)"
    }
    if ($t.cap_milestonename) { $body.cap_milestonename = $t.cap_milestonename }
    if ($null -ne $t.cap_billinganchorpercent) { $body.cap_billinganchorpercent = $t.cap_billinganchorpercent }
    Invoke-RestMethod -Uri "$api/cap_tasks" -Headers $headers -Method Post -Body ($body | ConvertTo-Json) | Out-Null
    $stamped++
}
Write-Host "Stamped: $stamped task(s)." -ForegroundColor Green

# --- 5) THE DERIVATIONS (what the portal will render; nothing stored) ---------------
$tasks = (Invoke-RestMethod -Uri "$api/cap_tasks?`$select=cap_name,cap_weight,cap_stagesequence,cap_stagename,cap_court,cap_showcustomer,statecode&`$filter=_cap_jobid_value eq $jobId" -Headers $headers -Method Get).value
$wTotal = ($tasks | Measure-Object cap_weight -Sum).Sum
$done   = $tasks | Where-Object { $_.statecode -ne 0 }   # 0 = Active/open
$wDone  = if ($done) { ($done | Measure-Object cap_weight -Sum).Sum } else { 0 }
$pct    = if ($wTotal -gt 0) { [math]::Round(100 * $wDone / $wTotal) } else { 0 }
$openTasks = $tasks | Where-Object { $_.statecode -eq 0 }
$curSeq = ($openTasks | Measure-Object cap_stagesequence -Minimum).Minimum
$curStage = ($openTasks | Where-Object { $_.cap_stagesequence -eq $curSeq } | Select-Object -First 1).cap_stagename
$courtNames = @{ 764820000 = "Practice"; 764820001 = "Customer"; 764820002 = "Third party" }
$courts = $openTasks | Where-Object { $_.cap_stagesequence -eq $curSeq } |
    ForEach-Object { $courtNames[$_.cap_court] } | Sort-Object -Unique
$askable = $openTasks | Where-Object { $_.cap_stagesequence -eq $curSeq -and $_.cap_court -eq 764820001 -and $_.cap_showcustomer }

Write-Host "`n=== PORTAL DERIVATIONS (computed, never stored) ===" -ForegroundColor Cyan
Write-Host ("Job:        {0}" -f $jobName)
Write-Host ("Progress:   {0}%  ({1} of {2} weight complete)" -f $pct, $wDone, $wTotal)
Write-Host ("Stage:      {0} (earliest incomplete, seq {1})" -f $curStage, $curSeq)
Write-Host ("Court:      {0}" -f ($courts -join " + "))
if ($askable) {
    Write-Host "Waiting on customer for:" -ForegroundColor Yellow
    $askable | ForEach-Object { Write-Host "  - $($_.cap_name)" -ForegroundColor Yellow }
}
if ($tasks.Count -ne 12) { Write-Host "EXPECTED 12 tasks on the job." -ForegroundColor Red; exit 1 }
Write-Host "`n12 tasks on the job - spine proof complete." -ForegroundColor Green
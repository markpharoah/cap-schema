# ============================================================================
# 41-job-duedate.ps1 — Session 38 Part 1
# Honours the ruling "due dates live on jobs":
#   1. adds cap_duedate (date only) to cap_job
#   2. backfills every job's cap_duedate = latest cap_duedate of its tasks
#   3. backfills cap_periodstart / cap_periodend from the Key stamped in each
#      job's description (code|type|yyyyMMdd|yyyyMMdd|amend, or ARREARS|year)
# Rerun-safe: column create skips if present; rows already populated skip.
# ============================================================================
$ErrorActionPreference = 'Stop'
$Env = 'https://org020f7b5c.crm6.dynamics.com'
try   { $Token = Get-MsalToken -ClientId 'bcf0d51c-81f7-40e0-a485-c75ed82a02e3' -TenantId '46bc20d5-9c02-426f-b030-aea373177d31' -Scopes "$Env/.default" -Silent }
catch { $Token = Get-MsalToken -ClientId 'bcf0d51c-81f7-40e0-a485-c75ed82a02e3' -TenantId '46bc20d5-9c02-426f-b030-aea373177d31' -Scopes "$Env/.default" -Interactive }
$H  = @{ Authorization = "Bearer $($Token.AccessToken)"; 'OData-MaxVersion'='4.0'; 'OData-Version'='4.0'; Accept='application/json' }
$HW = $H + @{ 'Content-Type'='application/json'; 'MSCRM.SolutionUniqueName'='CommercialAccounting' }
$Api = "$Env/api/data/v9.2"

# --- 1. column ---
$exists = $null; try { $exists = Invoke-RestMethod -Uri "$Api/EntityDefinitions(LogicalName='cap_job')/Attributes(LogicalName='cap_duedate')" -Headers $H } catch { }
if ($exists) { Write-Host 'cap_duedate already on cap_job - skipping' -ForegroundColor Yellow }
else {
  $body = @{ '@odata.type'='Microsoft.Dynamics.CRM.DateTimeAttributeMetadata'; SchemaName='cap_DueDate'; LogicalName='cap_duedate'
    DisplayName=@{ LocalizedLabels=@(@{ Label='Due Date'; LanguageCode=1033 }) }
    Description=@{ LocalizedLabels=@(@{ Label='When this job is due (from the obligation). Ratified Session 37: due dates live on jobs.'; LanguageCode=1033 }) }
    RequiredLevel=@{ Value='None' }; Format='DateOnly'; DateTimeBehavior=@{ Value='DateOnly' } } | ConvertTo-Json -Depth 8
  try { Invoke-RestMethod -Method Post -Uri "$Api/EntityDefinitions(LogicalName='cap_job')/Attributes" -Headers $HW -Body $body | Out-Null; Write-Host 'cap_duedate created' -ForegroundColor Green }
  catch { if ("$_" -match '0x80047013') { Write-Host 'cap_duedate exists (stale-404 family) - skipping' -ForegroundColor Yellow } else { throw } }
  Write-Host 'Pausing 60s for metadata cache before backfill...' -ForegroundColor Cyan; Start-Sleep 60
}

# --- 2/3. backfill ---
$jobs = @(); $url = "$Api/cap_jobs?`$select=cap_jobid,cap_name,cap_description,cap_duedate,cap_periodstart,cap_periodend&`$filter=statecode eq 0"
do { $r = Invoke-RestMethod -Uri $url -Headers $H; $jobs += $r.value; $url = $r.'@odata.nextLink' } while ($url)
Write-Host "Active jobs: $($jobs.Count)" -ForegroundColor Cyan
$set=0; $skip=0
foreach ($j in $jobs) {
  $patch = @{}
  if (-not $j.cap_duedate) {
    $t = (Invoke-RestMethod -Uri "$Api/cap_tasks?`$filter=_cap_jobid_value eq $($j.cap_jobid) and cap_duedate ne null&`$select=cap_duedate&`$orderby=cap_duedate desc&`$top=1" -Headers $H).value
    if ($t) { $patch.cap_duedate = ([datetime]$t[0].cap_duedate).ToString('yyyy-MM-dd') }
  }
  if (-not $j.cap_periodstart -and $j.cap_description -match 'Key: ([^\s]+)') {
    $k = $Matches[1].Split('|')
    if ($k[1] -eq 'ARREARS') { $y=[int]$k[2]; $patch.cap_periodstart="$($y-1)-07-01"; $patch.cap_periodend="$y-06-30" }
    elseif ($k[2] -match '^\d{8}$') { $patch.cap_periodstart=$k[2].Insert(4,'-').Insert(7,'-'); $patch.cap_periodend=$k[3].Insert(4,'-').Insert(7,'-') }
  }
  if ($patch.Count) {
    Invoke-RestMethod -Method Patch -Uri "$Api/cap_jobs($($j.cap_jobid))" -Headers ($H + @{'Content-Type'='application/json'}) -Body ($patch | ConvertTo-Json) | Out-Null
    $set++; if ($set % 25 -eq 0) { Write-Host "  ...$set updated" -ForegroundColor DarkGreen }
  } else { $skip++ }
}
Write-Host "41 complete: $set jobs updated, $skip already populated." -ForegroundColor Green

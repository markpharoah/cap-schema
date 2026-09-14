# ============================================================================
# 39-propose-jobs.ps1 — Session 37 Part 3 (proposer; READ-ONLY on Dataverse)
# Reads the newest LodgeIT all-status export from data\, classifies every open
# form under the ratified grain, and writes two CSVs beside it:
#   job-proposals.csv       — the tick-list 40-apply-jobs.ps1 will consume
#   stewardship-register.csv — out-of-scope AS obligations (scope limits work,
#                              never sight - the Lewis ruling as amended 15/9)
# AS scope comes LIVE from Dataverse (cap_engagement.cap_asscope = No), not a
# hardcoded list - the flag set in 37 is already load-bearing.
# Composite key: clientcode|type|periodstart|periodend|amendment.
# Truth test: first run should match job-proposal-candidates-v2 (212 jobs).
# ============================================================================
$ErrorActionPreference = 'Stop'
if (-not (Get-Module -ListAvailable ImportExcel)) {
  Write-Host 'Installing ImportExcel module (one-time, CurrentUser)...' -ForegroundColor Cyan
  Install-Module ImportExcel -Scope CurrentUser -Force
}
Import-Module ImportExcel

$Env = 'https://org020f7b5c.crm6.dynamics.com'
try   { $Token = Get-MsalToken -ClientId 'bcf0d51c-81f7-40e0-a485-c75ed82a02e3' -TenantId '46bc20d5-9c02-426f-b030-aea373177d31' -Scopes "$Env/.default" -Silent }
catch { $Token = Get-MsalToken -ClientId 'bcf0d51c-81f7-40e0-a485-c75ed82a02e3' -TenantId '46bc20d5-9c02-426f-b030-aea373177d31' -Scopes "$Env/.default" -Interactive }
$H = @{ Authorization = "Bearer $($Token.AccessToken)"; Accept='application/json' }
$Api = "$Env/api/data/v9.2"

# --- live AS-scope suppression list from Dataverse ---
$noAS = @()
$eng = (Invoke-RestMethod -Uri "$Api/cap_engagements?`$filter=cap_asscope eq false&`$select=cap_engagementid&`$expand=cap_entityid(`$select=cap_clientcode,cap_entityname)" -Headers $H).value
foreach ($e in $eng) { if ($e.cap_entityid.cap_clientcode) { $noAS += $e.cap_entityid.cap_clientcode
  Write-Host "AS scope = No: $($e.cap_entityid.cap_clientcode) $($e.cap_entityid.cap_entityname)" -ForegroundColor Cyan } }
$noAS = $noAS | Select-Object -Unique

# --- newest all-status export ---
$file = Get-ChildItem "$PSScriptRoot\data\lodgeit-allstatus-*.xlsx" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $file) { throw "No 'lodgeit-allstatus-*.xlsx' found in $PSScriptRoot\data" }
Write-Host "Reading $($file.Name) ($('{0:dd/MM/yyyy HH:mm}' -f $file.LastWriteTime))" -ForegroundColor Cyan
$rows = Import-Excel $file.FullName
$today = (Get-Date).Date
$RET = 'ITR','CTR','TRT','PTR','SMSFAR'
$tmplMap = @{ ITR='Tax Only Return'; CTR='Year End'; TRT='Year End'; PTR='Year End'; SMSFAR='Year End (SMSF)' }

$AU = [System.Globalization.CultureInfo]::GetCultureInfo('en-AU')
function P($v) {
  if ($v -is [datetime]) { return $v.Date }
  if (-not $v) { return $null }
  [datetime]::ParseExact("$v", [string[]]@('d/M/yyyy','dd/MM/yyyy','d/MM/yyyy','dd/M/yyyy'), $AU, 'None').Date
}

$open = @(); $steward = @()
foreach ($r in $rows) {
  if ($r.Status -notin 'New','Draft') { continue }
  $due = P $r.'Due date'; $amend = [int]($r.'Amendment number' ?? 0)
  $o = [pscustomobject]@{ Code=$r.'Client code'; Name=$r.Name; EType=$r.'Entity type'; Type=$r.Type; Sub=$r.Subtype
        Year=[int]$r.Year; Start=P $r.'Start date'; End=P $r.'End date'; Due=$due; Status=$r.Status
        Amend=$amend; Overdue=($due -and $due -lt $today) }
  if ($o.Type -eq 'AS' -and $noAS -contains $o.Code) {
    $steward += [pscustomobject]@{ ClientCode=$o.Code; ClientName=$o.Name; Obligation="AS/$($o.Sub)"
        PeriodStart=('{0:dd/MM/yyyy}' -f $o.Start); PeriodEnd=('{0:dd/MM/yyyy}' -f $o.End)
        DueDate=('{0:dd/MM/yyyy}' -f $o.Due); Class='Out of scope - known (stewardship)'; AsAtSweep=('{0:dd/MM/yyyy}' -f $today) }
    continue }
  $open += $o
}

$props = [System.Collections.Generic.List[object]]::new()
function Add-Prop($class,$tmpl,$o,$period,$due,$folded,$detail) {
  $ks = if ($o.Start) { $o.Start.ToString('yyyyMMdd') } else { '' }
  $ke = if ($o.End)   { $o.End.ToString('yyyyMMdd') }   else { '' }
  $key = "$($o.Code)|$($o.Type)|$ks|$ke|$($o.Amend)"
  $props.Add([pscustomobject]@{ Accept=''; JobClass=$class; Template=$tmpl; ClientCode=$o.Code; ClientName=$o.Name
    EntityType=$o.EType; Period=$period; DueDate=$due; FormsFolded=$folded; FormDetail=$detail
    Key=$key }) }

foreach ($o in ($open | Where-Object { $_.Amend -gt 0 -and -not $_.Overdue })) {
  Add-Prop 'Amendment' 'Amendment' $o "$($o.Type)/$($o.Sub) $($o.Year) amendment $($o.Amend)" '' 1 "$($o.Type)/$($o.Sub) $($o.Year) [$($o.Status)] amendment" }

$od = $open | Where-Object Overdue
foreach ($g in ($od | Group-Object Code,Year | Sort-Object Name)) {
  $f = $g.Group | Sort-Object Due
  $tmpl = if ($f.Type | Where-Object { $_ -in 'CTR','TRT','PTR','SMSFAR' }) { 'Year End' } else { 'Tax Only Return' }
  $detail = ($f | ForEach-Object { "$($_.Type)$(if($_.Sub){"/$($_.Sub)"})$(if($_.Amend){' amd'})" }) -join ' + '
  $o = $f[0]
  $dd = $o.Due.ToString('dd/MM/yyyy')
  $props.Add([pscustomobject]@{ Accept=''; JobClass='Arrears catch-up'; Template=$tmpl; ClientCode=$o.Code; ClientName=$o.Name
    EntityType=$o.EType; Period="FY$($o.Year)"; DueDate=$dd; FormsFolded=$f.Count; FormDetail=$detail
    Key="$($o.Code)|ARREARS|$($o.Year)||0" }) }

foreach ($o in ($open | Where-Object { -not $_.Overdue -and $_.Amend -eq 0 -and $_.Type -in $RET } | Sort-Object Due,Name)) {
  Add-Prop 'Current return' $tmplMap[$o.Type] $o "$($o.Type) FY$($o.Year)" ('{0:dd/MM/yyyy}' -f $o.Due) 1 "$($o.Type) $($o.Year) [$($o.Status)]" }

foreach ($o in ($open | Where-Object { -not $_.Overdue -and $_.Amend -eq 0 -and $_.Type -eq 'AS' } | Sort-Object Due,Name)) {
  Add-Prop 'Activity statement' 'Activity Statement' $o ("AS/$($o.Sub) {0:dd/MM/yy}-{1:dd/MM/yy}" -f $o.Start,$o.End) ('{0:dd/MM/yyyy}' -f $o.Due) 1 "AS/$($o.Sub) [$($o.Status)]" }

$props | Export-Csv "$PSScriptRoot\data\job-proposals.csv" -NoTypeInformation
$steward | Export-Csv "$PSScriptRoot\data\stewardship-register.csv" -NoTypeInformation
$props | Group-Object JobClass | ForEach-Object { Write-Host ("{0,-20} {1,4}" -f $_.Name,$_.Count) -ForegroundColor Green }
Write-Host ("{0,-20} {1,4}   ({2} forms)" -f 'TOTAL',$props.Count,(($props | Measure-Object FormsFolded -Sum).Sum)) -ForegroundColor Green
Write-Host ("Stewardship register: {0} out-of-scope obligations" -f $steward.Count) -ForegroundColor Cyan
Write-Host "`nTick Accept (x) in data\job-proposals.csv, then 40-apply-jobs.ps1." -ForegroundColor Cyan


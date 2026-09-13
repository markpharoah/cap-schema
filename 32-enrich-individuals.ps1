# 32-enrich-individuals.ps1 — DOB/death-date enrichment + kinship plausibility gate
# ---------------------------------------------------------------------------
# Sources cap_dateofbirth / cap_dateofdeath from the LodgeIT client export.
# Then runs the PLAUSIBILITY SWEEP over every active kinship edge — the
# permanent gate born of the 2026-09-13 ruling: heuristics propose, Mark
# ratifies, an applier applies. Every future import lands through this gate.
#
#   PREVIEW (default):  .\32-enrich-individuals.ps1
#   APPLY:              .\32-enrich-individuals.ps1 -Apply
#
# Rules:
#   - LodgeIT is source for DOB/DOD scalars. CAP blank -> set. CAP holds a
#     DIFFERENT value -> CONFLICT report, never silently overwritten.
#   - Entities with Client Status = Merged are skipped (victims).
#   - Sweep heuristics: Child of => child >=16y younger; Sibling/Spouse
#     gap > 20y => flag. Missing DOB on an active individual => data gap.
# Run AFTER 31-knit-ingestion. Depends on cap_dateofdeath (31 creates it);
# creates cap_dateofbirth here if missing.
# ---------------------------------------------------------------------------

param(
    [switch]$Apply,
    [string]$ClientsCsv = "C:\CAP\schema\data\Clients Commercial Accounting 1.csv"
)

. "$PSScriptRoot\_connect.ps1"     # standard block -> $base, $H
$ErrorActionPreference = "Stop"
function Get-All($url) { $o=@(); $u=$url; while($u){ $r=Invoke-RestMethod -Uri $u -Headers $H; $o+=$r.value; $u=$r.'@odata.nextLink' }; $o }
function Say($m,$c="Gray"){ Write-Host $m -ForegroundColor $c }
$mode = if ($Apply) { "APPLY" } else { "PREVIEW" }
Say "=== 32-enrich-individuals [$mode] ===" Cyan

# --- schema: cap_dateofbirth ------------------------------------------------
foreach ($col in @(
    @{ ln='cap_dateofbirth'; sn='cap_DateOfBirth'; disp='Date of Birth'; desc='Sourced from LodgeIT Birth Date. Drives age profiling, birthday comms, kinship plausibility gate.' })) {
    $exists = $true
    try { Invoke-RestMethod -Headers $H -Uri "$base/EntityDefinitions(LogicalName='cap_entity')/Attributes(LogicalName='$($col.ln)')?`$select=LogicalName" | Out-Null }
    catch { $exists = $false }
    if (-not $exists) {
        Say "$($col.ln) missing -> $(if($Apply){'CREATE'}else{'would create'})" Yellow
        if ($Apply) {
            $attr = @{ '@odata.type'='Microsoft.Dynamics.CRM.DateTimeAttributeMetadata'; SchemaName=$col.sn;
                Format='DateOnly'; DateTimeBehavior=@{Value='DateOnly'}; RequiredLevel=@{Value='None'}
                DisplayName=@{LocalizedLabels=@(@{Label=$col.disp;LanguageCode=1033})}
                Description=@{LocalizedLabels=@(@{Label=$col.desc;LanguageCode=1033})} } | ConvertTo-Json -Depth 6
            Invoke-RestMethod -Headers $H -Method Post -Body $attr -ContentType "application/json" `
                -Uri "$base/EntityDefinitions(LogicalName='cap_entity')/Attributes" | Out-Null
            Invoke-RestMethod -Headers $H -Method Post -Uri "$base/PublishAllXml" -ContentType "application/json" -Body "{}" | Out-Null
        }
    }
}

# --- load source (UTF-8 BOM; dates d/M/yyyy) ---------------------------------
$src = Import-Csv $ClientsCsv -Encoding UTF8
function ParseAU($s) { if (-not $s) { return $null }
    [datetime]::ParseExact($s.Trim(), [string[]]@('d/M/yyyy'),
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::None).ToString('yyyy-MM-dd') }
Say ("Source rows: " + $src.Count + " (individuals: " + (@($src | Where-Object Type -eq 'Individual')).Count + ")")

# --- load CAP entities -------------------------------------------------------
$statusOpts = (Invoke-RestMethod -Headers $H -Uri "$base/GlobalOptionSetDefinitions(Name='cap_entitystatus')").Options
$mergedVal = ($statusOpts | Where-Object { $_.Label.UserLocalizedLabel.Label -eq 'Merged' }).Value
$optCols = @('cap_dateofbirth','cap_dateofdeath') | Where-Object {
    $c=$_; try { Invoke-RestMethod -Headers $H -Uri "$base/EntityDefinitions(LogicalName='cap_entity')/Attributes(LogicalName='$c')?`$select=LogicalName" | Out-Null; $true } catch { $false } }
$sel = (@('cap_entityid','cap_clientcode','cap_entityname','cap_status','statecode') + $optCols) -join ','
$ents = Get-All "$base/cap_entities?`$select=$sel"
$byCode = @{}; foreach ($e in $ents) { if ($e.cap_clientcode) { $byCode[$e.cap_clientcode.Trim()] = $e } }

$r = [ordered]@{ dobset=0; dodset=0; conflicts=0; skippedmerged=0; notincap=0 }
Say "`n-- ENRICH --" Cyan
foreach ($s in ($src | Where-Object Type -eq 'Individual')) {
    $code = $s.Code.Trim(); $e = $byCode[$code]
    if (-not $e) { Say "  !! $code $($s.Name) not in CAP" Red; $r.notincap++; continue }
    if ($mergedVal -and $e.cap_status -eq $mergedVal) { $r.skippedmerged++; continue }
    $body = @{}
    foreach ($m in @(@{src='Birth Date';fld='cap_dateofbirth';k='dobset'},
                     @{src='Death Date';fld='cap_dateofdeath';k='dodset'})) {
        $v = ParseAU $s.($m.src); if (-not $v) { continue }
        $cur = $e.($m.fld)
        if (-not $cur) { $body[$m.fld] = $v; $r[$m.k]++ ; Say "  $code $($m.fld) = $v" }
        elseif (([datetime]$cur).ToString('yyyy-MM-dd') -ne $v) {
            Say "  ** CONFLICT $code $($m.fld): CAP=$cur LodgeIT=$v — not overwritten" Red; $r.conflicts++ }
    }
    if ($body.Count -and $Apply) {
        Invoke-RestMethod -Headers $H -Method Patch -Uri "$base/cap_entities($($e.cap_entityid))" `
            -Body ($body | ConvertTo-Json) -ContentType "application/json" | Out-Null }
    if ($body.Count) { foreach ($k in $body.Keys) { $e | Add-Member -NotePropertyName $k -NotePropertyValue $body[$k] -Force } }
}

# --- PLAUSIBILITY SWEEP ------------------------------------------------------
Say "`n-- KINSHIP PLAUSIBILITY GATE --" Cyan
$relOpts = (Invoke-RestMethod -Headers $H -Uri "$base/GlobalOptionSetDefinitions(Name='cap_relationshiptype')").Options
$relLbl = @{}; foreach ($o in $relOpts) { $relLbl[$o.Value] = $o.Label.UserLocalizedLabel.Label }
$edges = Get-All ("$base/cap_entityrelationships?`$select=_cap_fromentityid_value,_cap_toentityid_value,cap_relationshiptype,statecode&`$filter=statecode eq 0")
$byId = @{}; foreach ($e in $ents) { $byId[$e.cap_entityid] = $e }
function AgeGap($a,$b) {  # years b is younger than a; $null if either DOB missing
    if (-not $a.cap_dateofbirth -or -not $b.cap_dateofbirth) { return $null }
    [math]::Round((([datetime]$b.cap_dateofbirth) - ([datetime]$a.cap_dateofbirth)).TotalDays / 365.25, 1) }
$flags = 0
foreach ($ed in $edges) {
    $t = $relLbl[$ed.cap_relationshiptype]
    if ($t -notin 'Spouse of','Sibling of','Child of','Parent of') { continue }
    $f = $byId[$ed._cap_fromentityid_value]; $to = $byId[$ed._cap_toentityid_value]
    if (-not $f -or -not $to) { continue }
    $g = AgeGap $to $f      # positive => FROM younger than TO
    if ($null -eq $g) { continue }
    $bad = $null
    if ($t -eq 'Child of'  -and $g -lt 16)          { $bad = "child only $g y younger than parent" }
    if ($t -eq 'Parent of' -and (-$g) -lt 16)       { $bad = "parent only $(-$g) y older than child" }
    if ($t -in 'Spouse of','Sibling of' -and [math]::Abs($g) -gt 20) { $bad = "$t gap $([math]::Abs($g))y" }
    if ($bad) { Say "  ?? $($f.cap_clientcode) $($f.cap_entityname) [$t] $($to.cap_clientcode) $($to.cap_entityname): $bad" Yellow; $flags++ }
}
Say "  plausibility flags: $flags"
Say "`n-- DATA GAPS: active individuals without DOB --" Cyan
foreach ($e in ($ents | Where-Object { $_.statecode -eq 0 -and $_.cap_clientcode -and -not $_.cap_dateofbirth -and $_.cap_status -ne $mergedVal })) {
    # individuals only — matched against the source's Individual rows; codeless entities (Harborne) exempt
    if (@($src | Where-Object { $_.Code.Trim() -eq $e.cap_clientcode -and $_.Type -eq 'Individual' }).Count) {
        Say "  gap: $($e.cap_clientcode) $($e.cap_entityname)" DarkYellow }
}

Say "`n=== SUMMARY [$mode] ===" Cyan
$r.GetEnumerator() | ForEach-Object { Say ("  {0,-14} {1}" -f $_.Key, $_.Value) }
if (-not $Apply) { Say "`nPreview only. Re-run with -Apply." Green }

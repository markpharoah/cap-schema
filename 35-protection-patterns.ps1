# 35-protection-patterns.ps1 — the Knight's instrument panel, v1
# ---------------------------------------------------------------------------
# Three ratified patterns over the graph + the ELDER REGISTER, emitted as a
# branded, PRACTICE-EYES-ONLY Protection Report (HTML) and console summary.
#
#   (a) CONCENTRATION  — living person >= -ElderThreshold whose operative
#       authority rests on a SOLE holder who is also their only/dominant
#       living kin contact. Co-holders dilute: >1 operative holder = no flag.
#   (b) STRANGER AUTHORITY — holder with NO kinship path to the principal
#       and no 'professional' marker in the edge note.
#   (c) ORPHANED AUTHORITY — holder deceased (red) / Merged (data error) /
#       Former (review); plus principal deceased with authority still active.
#   (+) ELDER REGISTER — every living individual >= threshold, instruments
#       on file vs NONE ON FILE (the conversation list).
#
#   .\35-protection-patterns.ps1                      # threshold 75
#   .\35-protection-patterns.ps1 -ElderThreshold 80 -OutDir C:\CAP\output
#
# Read-only: this script never writes to the graph. Default-deny doctrine on
# the report itself. DRAFT instruments counted but flagged.
# ---------------------------------------------------------------------------
param(
    [int]$ElderThreshold = 75,
    [string]$OutDir = "C:\CAP\output"
)
. "$PSScriptRoot\_connect.ps1"
$ErrorActionPreference = "Stop"
function Get-All($u){ $o=@(); while($u){ $r=Invoke-RestMethod -Uri $u -Headers $H; $o+=$r.value; $u=$r.'@odata.nextLink'}; $o }
function Say($m,$c="Gray"){ Write-Host $m -ForegroundColor $c }
function Esc($s){ if($null -eq $s){return ''}; [System.Net.WebUtility]::HtmlEncode([string]$s) }
Say "=== 35-protection-patterns [threshold $ElderThreshold] ===" Cyan

function Labels($n){ $m=@{}; foreach($o in (Invoke-RestMethod -Headers $H -Uri "$base/GlobalOptionSetDefinitions(Name='$n')").Options){ $m[$o.Value]=$o.Label.UserLocalizedLabel.Label }; $m }
$relLbl = Labels 'cap_relationshiptype'
$stLbl  = Labels 'cap_entitystatus'
$ents = Get-All "$base/cap_entities?`$select=cap_entityid,cap_clientcode,cap_entityname,cap_status,cap_dateofbirth,cap_dateofdeath,statecode"
$byId=@{}; foreach($e in $ents){ $byId[$e.cap_entityid]=$e }
$hasNotes = $true
try { Invoke-RestMethod -Headers $H -Uri "$base/EntityDefinitions(LogicalName='cap_entityrelationship')/Attributes(LogicalName='cap_notes')?`$select=LogicalName" | Out-Null } catch { $hasNotes=$false }
$edges = Get-All ("$base/cap_entityrelationships?`$select=_cap_fromentityid_value,_cap_toentityid_value,cap_relationshiptype" + $(if($hasNotes){",cap_notes"}) + "&`$filter=statecode eq 0")

$KIN  = @('Spouse of','Child of','Parent of','Sibling of','Relative of')
$AUTH = @('Attorney for (EPOA)','Guardian of','Executor for','Authorised contact for','Medical decision maker for')

# --- kinship adjacency + components ------------------------------------------
$adj=@{}
function AddTo([hashtable]$h,$k,$v){ if(-not $h.ContainsKey($k)){ $h[$k]=New-Object System.Collections.Generic.HashSet[string] }; [void]$h[$k].Add($v) }
foreach($ed in $edges){
    if($KIN -contains $relLbl[$ed.cap_relationshiptype]){
        AddTo $adj $ed._cap_fromentityid_value $ed._cap_toentityid_value
        AddTo $adj $ed._cap_toentityid_value $ed._cap_fromentityid_value } }
function SetOf([hashtable]$h,$k){ if($h.ContainsKey($k)){ $h[$k] } else { @() } }
$comp=@{}; $cix=0
foreach($e in $ents){
    $id=$e.cap_entityid; if($comp.ContainsKey($id)){ continue }
    $cix++; $q=New-Object System.Collections.Queue; $q.Enqueue($id); $comp[$id]=$cix
    while($q.Count){ $x=$q.Dequeue(); foreach($n in (SetOf $adj $x)){ if(-not $comp.ContainsKey($n)){ $comp[$n]=$cix; $q.Enqueue($n) } } } }

function AgeOf($e){ if(-not $e.cap_dateofbirth){ return $null }
    $end = if($e.cap_dateofdeath){ [datetime]$e.cap_dateofdeath } else { Get-Date }
    [math]::Floor(($end - [datetime]$e.cap_dateofbirth).TotalDays/365.25) }
function Alive($e){ -not $e.cap_dateofdeath -and $e.statecode -eq 0 }
function StLabel($e){ if($null -ne $e.cap_status -and $stLbl.ContainsKey([int]$e.cap_status)){ $stLbl[[int]$e.cap_status] } else { '' } }

# --- authority edges parsed ---------------------------------------------------
function Bits($n){
    [pscustomobject]@{
        role  = if($n -match 'PRIMARY'){'PRIMARY'} elseif($n -match 'ALTERNATIVE'){'ALTERNATIVE'} elseif($n -match 'SUBSTITUTE'){'SUBSTITUTE'} else {''}
        state = if($n -match 'operative immediately'){'OPERATIVE'} elseif($n -match '(dormant|springing)'){'DORMANT'} elseif($n -match 'PRIMARY'){'OPERATIVE'} else {'OPERATIVE'}  # unannotated authority assumed live
        draft = [bool]($n -match 'DRAFT')
        prof  = [bool]($n -match '(?i)professional')
    } }
$authEdges=@()
foreach($ed in $edges){
    $t=$relLbl[$ed.cap_relationshiptype]
    if($AUTH -notcontains $t){ continue }
    $n = if($hasNotes){ [string]$ed.cap_notes } else { '' }
    $authEdges += [pscustomobject]@{ holder=$ed._cap_fromentityid_value; principal=$ed._cap_toentityid_value; type=$t; note=$n; bits=(Bits $n) }
}
Say ("Graph: " + $ents.Count + " entities, " + $edges.Count + " active edges, authority edges: " + $authEdges.Count)

$findA=@(); $findB=@(); $findC=@(); $elders=@()

# --- ELDER REGISTER + pattern (a) --------------------------------------------
foreach($e in ($ents | Where-Object { (Alive $_) -and $_.cap_dateofbirth })){
    $age = AgeOf $e
    if($age -lt $ElderThreshold){ continue }
    $mine = @($authEdges | Where-Object principal -eq $e.cap_entityid)
    $types = @($mine | ForEach-Object type | Sort-Object -Unique)
    $kinIds = @((SetOf $adj $e.cap_entityid) | Where-Object { $byId[$_] -and (Alive $byId[$_]) })
    $elders += [pscustomobject]@{ e=$e; age=$age; st=(StLabel $e); types=$types; nInstr=$types.Count; kin=$kinIds.Count; draft=@($mine | Where-Object { $_.bits.draft }).Count -gt 0 }
    # (a) concentration per type: sole operative holder who is only/dominant kin
    foreach($ty in $types){
        $ops = @($mine | Where-Object { $_.type -eq $ty -and $_.bits.state -eq 'OPERATIVE' })
        if($ops.Count -ne 1){ continue }               # co-held or all dormant -> diluted
        $h = $ops[0].holder
        $otherKin = @($kinIds | Where-Object { $_ -ne $h })
        if($otherKin.Count -le 1){
            $findA += [pscustomobject]@{ p=$e; age=$age; h=$byId[$h]; type=$ty; otherKin=$otherKin.Count; draft=$ops[0].bits.draft }
        }
    }
}

# --- pattern (b) stranger authority ------------------------------------------
foreach($a in $authEdges){
    $p=$byId[$a.principal]; $h=$byId[$a.holder]
    if(-not $p -or -not $h){ continue }
    $kinPath = ($comp[$a.principal] -eq $comp[$a.holder]) -and ((SetOf $adj $a.principal).Count -gt 0)
    if(-not $kinPath -and -not $a.bits.prof){
        $findB += [pscustomobject]@{ p=$p; h=$h; type=$a.type; draft=$a.bits.draft }
    }
}

# --- pattern (c) orphaned authority ------------------------------------------
foreach($a in $authEdges){
    $p=$byId[$a.principal]; $h=$byId[$a.holder]
    if(-not $p -or -not $h){ continue }
    $sev=$null; $why=$null
    if($h.cap_dateofdeath){ $sev='RED'; $why="holder deceased $(([datetime]$h.cap_dateofdeath).ToString('d/M/yyyy'))" }
    elseif((StLabel $h) -eq 'Merged'){ $sev='DATA'; $why='holder is a Merged duplicate — repoint' }
    elseif((StLabel $h) -eq 'Former'){ $sev='REVIEW'; $why='holder is a Former client — confirm still appropriate/locatable' }
    if($p.cap_dateofdeath){ $sev = if($sev){$sev}else{'REVIEW'}; $why = (@($why,"principal deceased — instruments should be closed out") | Where-Object { $_ }) -join '; ' }
    if($sev){ $findC += [pscustomobject]@{ p=$p; h=$h; type=$a.type; sev=$sev; why=$why; draft=$a.bits.draft } }
}

# --- console summary ----------------------------------------------------------
Say "`n-- ELDER REGISTER (>= $ElderThreshold) --" Cyan
foreach($el in ($elders | Sort-Object { -$_.age })){
    $instr = if($el.nInstr){ ($el.types -join ', ') + $(if($el.draft){ '  [DRAFT]' }) } else { 'NONE ON FILE' }
    $col = if($el.nInstr){ 'Gray' } else { 'Yellow' }
    Say ("  {0,3}  {1,-8} {2,-26} {3,-8} kin:{4}  {5}" -f $el.age, $el.e.cap_clientcode, $el.e.cap_entityname, $el.st, $el.kin, $instr) $col }
Say "`n-- (a) CONCENTRATION --" Cyan
if($findA.Count){ foreach($f in $findA){ Say ("  !! {0} ({1}) — sole operative {2}: {3}; other living kin: {4}{5}" -f $f.p.cap_entityname,$f.age,$f.type,$f.h.cap_entityname,$f.otherKin,$(if($f.draft){' [DRAFT]'})) Yellow } } else { Say "  clear" Green }
Say "-- (b) STRANGER AUTHORITY --" Cyan
if($findB.Count){ foreach($f in $findB){ Say ("  !! {0} holds {1} over {2} — no kinship path, no professional marker{3}" -f $f.h.cap_entityname,$f.type,$f.p.cap_entityname,$(if($f.draft){' [DRAFT]'})) Yellow } } else { Say "  clear" Green }
Say "-- (c) ORPHANED AUTHORITY --" Cyan
if($findC.Count){ foreach($f in $findC){ Say ("  [{0}] {1} -> {2} ({3}): {4}" -f $f.sev,$f.h.cap_entityname,$f.p.cap_entityname,$f.type,$f.why) $(if($f.sev -eq 'RED'){'Red'}else{'Yellow'}) } } else { Say "  clear" Green }

# --- branded HTML report -------------------------------------------------------
function Row($cells){ "<tr>" + (($cells | ForEach-Object { "<td>$_</td>" }) -join '') + "</tr>" }
$eldRows = ($elders | Sort-Object { -$_.age } | ForEach-Object {
    $instr = if($_.nInstr){ (Esc ($_.types -join ', ')) + $(if($_.draft){ " <span class='draftflag'>DRAFT</span>" }) } else { "<span class='nonef'>NONE ON FILE</span>" }
    Row @($_.age, (Esc $_.e.cap_clientcode), (Esc $_.e.cap_entityname), (Esc $_.st), $_.kin, $instr) }) -join "`n"
$aRows = if($findA.Count){ ($findA | ForEach-Object { Row @((Esc $_.p.cap_entityname), $_.age, (Esc $_.type), (Esc $_.h.cap_entityname), $_.otherKin, $(if($_.draft){"<span class='draftflag'>DRAFT</span>"}else{''})) }) -join "`n" } else { "<tr><td colspan='6' class='clear'>Clear — no concentration findings at threshold $ElderThreshold.</td></tr>" }
$bRows = if($findB.Count){ ($findB | ForEach-Object { Row @((Esc $_.h.cap_entityname), (Esc $_.type), (Esc $_.p.cap_entityname), $(if($_.draft){"<span class='draftflag'>DRAFT</span>"}else{''})) }) -join "`n" } else { "<tr><td colspan='4' class='clear'>Clear — every authority holder is kin or professionally marked.</td></tr>" }
$cRows = if($findC.Count){ ($findC | ForEach-Object { Row @("<b class='$(if($_.sev -eq 'RED'){'red'}else{'amber'})'>$($_.sev)</b>", (Esc $_.h.cap_entityname), (Esc $_.type), (Esc $_.p.cap_entityname), (Esc $_.why)) }) -join "`n" } else { "<tr><td colspan='5' class='clear'>Clear — no orphaned authority.</td></tr>" }
$today = Get-Date -Format 'd MMMM yyyy'
$html = @"
<!doctype html><html><head><meta charset="utf-8"><title>Protection Report — $today</title>
<style>
:root{--red:#FA0217;--ink:#3A3A3A;--grey:#666666;--caption:#909090;--green:#1F7A4A;--link:#215B9E;--highlight:#FFE36E;--panel:#F7F7F8;--hair:#D8DADD}
*{box-sizing:border-box} body{font-family:"Helvetica Neue",Helvetica,Arial,sans-serif;color:var(--ink);background:#fff;margin:0;padding:28px 34px}
.wordmark{font-size:15px;font-weight:bold}.wordmark .dot{color:var(--red)}
.eyebrow{font-size:8.5px;font-weight:bold;letter-spacing:1.6px;text-transform:uppercase;color:var(--caption);margin-top:2px}
h1{font-size:22px;margin:14px 0 2px}.meta{color:var(--caption);font-size:8px;margin-bottom:14px}
.note{background:var(--panel);border-left:4px solid var(--green);padding:8px 12px;font-size:9px;color:var(--grey);margin:10px 0 18px}
.banner{background:var(--panel);border-left:4.5px solid var(--red);border-top:1px solid var(--red);border-bottom:1px solid var(--hair);padding:6px 10px;font-size:11px;font-weight:bold;letter-spacing:.6px;text-transform:uppercase;margin:22px 0 10px}
table{border-collapse:collapse;width:100%;font-size:8.5px;border:1px solid var(--hair);border-top:none;margin-bottom:6px}
th{background:var(--panel);border-top:2px solid var(--red);border-bottom:1px solid var(--hair);padding:5px 8px;text-align:left;font-size:8px;letter-spacing:1px;text-transform:uppercase;color:var(--grey)}
td{border-bottom:1px solid var(--hair);padding:6px 8px;vertical-align:top}
tr:nth-child(even) td{background:var(--panel)}
.draftflag{display:inline-block;background:var(--highlight);border:1px solid var(--red);padding:1px 6px;font-size:7.3px;font-weight:bold}
.nonef{color:var(--red);font-weight:bold}
.clear{color:var(--green);font-weight:bold}
.red{color:var(--red)}.amber{color:#9a6a00}
footer{margin-top:26px;color:var(--caption);font-size:7.3px;border-top:1px solid var(--hair);padding-top:8px}
</style></head><body>
<div class="wordmark">commercial <span class="dot">●</span> ACCOUNTING</div>
<div class="eyebrow">Protection Report — CAP panel</div>
<h1>Protection patterns &amp; elder register</h1>
<div class="meta">Generated $today · elder threshold $ElderThreshold · $($ents.Count) entities · $($authEdges.Count) authority edges · read-only</div>
<div class="note"><b>PRACTICE EYES ONLY.</b> Default-deny doctrine: partner discretion/approval gates every disclosure. This report informs the partner's judgment; it never automates disclosure or action. Draft instruments are counted but flagged.</div>
<div class="banner">Elder register (&ge; $ElderThreshold)</div>
<table><thead><tr><th>Age</th><th>Code</th><th>Name</th><th>Status</th><th>Living kin links</th><th>Instruments on file</th></tr></thead><tbody>
$eldRows
</tbody></table>
<div class="banner">(a) Concentration</div>
<table><thead><tr><th>Principal</th><th>Age</th><th>Instrument</th><th>Sole operative holder</th><th>Other living kin</th><th></th></tr></thead><tbody>
$aRows
</tbody></table>
<div class="banner">(b) Stranger authority</div>
<table><thead><tr><th>Holder</th><th>Instrument</th><th>Principal</th><th></th></tr></thead><tbody>
$bRows
</tbody></table>
<div class="banner">(c) Orphaned authority</div>
<table><thead><tr><th>Severity</th><th>Holder</th><th>Instrument</th><th>Principal</th><th>Why</th></tr></thead><tbody>
$cRows
</tbody></table>
<footer>Commercial Accounting · CAP protection panel · patterns computed from the graph at run time; nothing stored. Logo is the typographic stand-in (brand_logo.png pending).</footer>
</body></html>
"@
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$out = Join-Path $OutDir ("Protection_Report_" + (Get-Date -Format yyyy-MM-dd) + ".html")
Set-Content -Path $out -Value $html -Encoding UTF8
Say "`nWritten: $out" Green
Start-Process $out

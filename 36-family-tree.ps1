# 36-family-tree.ps1 — walker consumer 2: the Family Tree & Protection view
# ---------------------------------------------------------------------------
# Generates a Commercial Accounting-branded single-file HTML for the family
# cluster around a focal person: generations, spouse-grouped cards, derived
# relations, dates, and the AUTHORITY & PROTECTION panel per principal
# (role, state OPERATIVE/DORMANT + trigger, DRAFT flag, evidence basis).
#
#   .\36-family-tree.ps1 -FocusCode PHA0009
#   .\36-family-tree.ps1 -FocusCode PHA0009 -OutDir C:\CAP\output
#
# PRACTICE-EYES ONLY by doctrine (default-deny; partner discretion gates
# every disclosure). Cluster = kinship-connected component; authority edges
# rendered among cluster members. Brand: commercial-accounting-brand tokens.
# ---------------------------------------------------------------------------
param(
    [Parameter(Mandatory=$true)][string]$FocusCode,
    [string]$OutDir = "C:\CAP\output"
)
. "$PSScriptRoot\_connect.ps1"
$ErrorActionPreference = "Stop"
function Get-All($u){ $o=@(); while($u){ $r=Invoke-RestMethod -Uri $u -Headers $H; $o+=$r.value; $u=$r.'@odata.nextLink'}; $o }
function Say($m,$c="Gray"){ Write-Host $m -ForegroundColor $c }
function Esc($s){ if($null -eq $s){return ''}; [System.Net.WebUtility]::HtmlEncode([string]$s) }

# --- load graph --------------------------------------------------------------
function Labels($n){ $m=@{}; foreach($o in (Invoke-RestMethod -Headers $H -Uri "$base/GlobalOptionSetDefinitions(Name='$n')").Options){ $m[$o.Value]=$o.Label.UserLocalizedLabel.Label }; $m }
$relLbl = Labels 'cap_relationshiptype'
$stLbl  = Labels 'cap_entitystatus'
$ents = Get-All "$base/cap_entities?`$select=cap_entityid,cap_clientcode,cap_entityname,cap_status,cap_dateofbirth,cap_dateofdeath,statecode"
$byId=@{}; $byCode=@{}
foreach($e in $ents){ $byId[$e.cap_entityid]=$e; if($e.cap_clientcode){ $byCode[$e.cap_clientcode.Trim()]=$e } }
$focus = $byCode[$FocusCode]; if(-not $focus){ throw "Focus code $FocusCode not found." }
$hasNotes = $true
try { Invoke-RestMethod -Headers $H -Uri "$base/EntityDefinitions(LogicalName='cap_entityrelationship')/Attributes(LogicalName='cap_notes')?`$select=LogicalName" | Out-Null } catch { $hasNotes=$false }
$edges = Get-All ("$base/cap_entityrelationships?`$select=_cap_fromentityid_value,_cap_toentityid_value,cap_relationshiptype" + $(if($hasNotes){",cap_notes"}) + "&`$filter=statecode eq 0")

$KIN = @('Spouse of','Child of','Parent of','Sibling of','Former spouse of')
$AUTH = @('Attorney for (EPOA)','Guardian of','Executor for','Authorised contact for','Medical decision maker for')

# --- kinship spine + cluster BFS --------------------------------------------
$parents=@{}; $children=@{}; $spouses=@{}; $exsp=@{}; $sibsX=@{}; $adj=@{}
function AddTo([hashtable]$h,$k,$v){ if(-not $h.ContainsKey($k)){ $h[$k]=New-Object System.Collections.Generic.HashSet[string] }; [void]$h[$k].Add($v) }
foreach($ed in $edges){
    $f=$ed._cap_fromentityid_value; $t=$ed._cap_toentityid_value
    switch($relLbl[$ed.cap_relationshiptype]){
        'Child of'   { AddTo $parents $f $t; AddTo $children $t $f; AddTo $adj $f $t; AddTo $adj $t $f }
        'Parent of'  { AddTo $parents $t $f; AddTo $children $f $t; AddTo $adj $f $t; AddTo $adj $t $f }
        'Spouse of'  { AddTo $spouses $f $t; AddTo $spouses $t $f; AddTo $adj $f $t; AddTo $adj $t $f }
        'Former spouse of' { AddTo $exsp $f $t; AddTo $exsp $t $f; AddTo $adj $f $t; AddTo $adj $t $f }
        'Sibling of' { AddTo $sibsX $f $t;  AddTo $sibsX $t $f;  AddTo $adj $f $t; AddTo $adj $t $f }
    }
}
function SetOf([hashtable]$h,$k){ if($h.ContainsKey($k)){ $h[$k] } else { @() } }
function Sibs($x){ $s=New-Object System.Collections.Generic.HashSet[string]
    foreach($v in (SetOf $sibsX $x)){ [void]$s.Add($v) }
    foreach($p in (SetOf $parents $x)){ foreach($c in (SetOf $children $p)){ if($c -ne $x){ [void]$s.Add($c) } } }
    $s }
$cluster=New-Object System.Collections.Generic.HashSet[string]
$q=New-Object System.Collections.Queue; $q.Enqueue($focus.cap_entityid); [void]$cluster.Add($focus.cap_entityid)
while($q.Count){ $x=$q.Dequeue(); foreach($n in (SetOf $adj $x)){ if($cluster.Add($n)){ $q.Enqueue($n) } } }
Say ("Cluster around $FocusCode $($focus.cap_entityname): " + $cluster.Count + " people")

# --- relation-to-focal label -------------------------------------------------
function RelTo($a){   # what is A to FOCUS
    $b=$focus.cap_entityid
    if($a -eq $b){ return 'focal person' }
    if((SetOf $spouses $b) -contains $a){ return 'spouse' }
    if((SetOf $exsp $b) -contains $a){ return 'former spouse' }
    if((SetOf $children $b) -contains $a){ return 'child' }
    if((SetOf $parents $b) -contains $a){ return 'parent' }
    if((Sibs $b) -contains $a){ return 'sibling' }
    foreach($c in (SetOf $children $b)){ if((SetOf $children $c) -contains $a){ return 'grandchild' } }
    foreach($p in (SetOf $parents $b)){ if((SetOf $parents $p) -contains $a){ return 'grandparent' } }
    foreach($c in (SetOf $children $b)){ if((SetOf $spouses $c) -contains $a){ return 'child-in-law' } }
    foreach($s in (Sibs $b)){ if((SetOf $spouses $s) -contains $a){ return 'sibling-in-law' } }
    foreach($sp in (SetOf $spouses $b)){ if((Sibs $sp) -contains $a){ return 'sibling-in-law' }
        if((SetOf $parents $sp) -contains $a){ return 'parent-in-law' }
        if(((SetOf $children $sp) -contains $a) -and -not ((SetOf $children $b) -contains $a)){ return 'step-child' } }
    foreach($xp in (SetOf $exsp $b)){ if(((SetOf $children $xp) -contains $a) -and -not ((SetOf $children $b) -contains $a)){ return 'step-child' } }
    foreach($p in (SetOf $parents $b)){ foreach($ps in (Sibs $p)){ if($ps -eq $a){ return 'aunt/uncle' }
        foreach($c in (SetOf $children $ps)){ if($c -eq $a){ return 'cousin' } } } }
    foreach($s in (Sibs $b)){ foreach($c in (SetOf $children $s)){ if($c -eq $a){ return 'niece/nephew' } } }
    return 'relative'
}

# --- generations (levels): parents up, children down, spouses/siblings flat --
$level=@{}; $level[$focus.cap_entityid]=0
$q=New-Object System.Collections.Queue; $q.Enqueue($focus.cap_entityid)
while($q.Count){ $x=$q.Dequeue(); $lx=$level[$x]
    foreach($p in (SetOf $parents $x)){ if(-not $level.ContainsKey($p)){ $level[$p]=$lx-1; $q.Enqueue($p) } }
    foreach($c in (SetOf $children $x)){ if(-not $level.ContainsKey($c)){ $level[$c]=$lx+1; $q.Enqueue($c) } }
    foreach($s in (SetOf $spouses $x)){ if(-not $level.ContainsKey($s)){ $level[$s]=$lx; $q.Enqueue($s) } }
    foreach($s in (SetOf $exsp $x)){ if(-not $level.ContainsKey($s)){ $level[$s]=$lx; $q.Enqueue($s) } }
    foreach($s in (Sibs $x)){ if(-not $level.ContainsKey($s)){ $level[$s]=$lx; $q.Enqueue($s) } } }
foreach($id in $cluster){ if(-not $level.ContainsKey($id)){ $level[$id]=9 } }

$RINGSX = "<svg viewBox='0 0 26 14' width='22' height='12' role='img' aria-label='Former spouse'><circle cx='9' cy='7' r='5' fill='none' stroke='#909090' stroke-width='1.5' stroke-dasharray='3 2'/><circle cx='17' cy='7' r='5' fill='none' stroke='#909090' stroke-width='1.5' stroke-dasharray='3 2'/></svg>"
$RINGS = "<svg viewBox='0 0 26 14' width='22' height='12' role='img' aria-label='Spouse'><circle cx='9' cy='7' r='5' fill='none' stroke='#666666' stroke-width='1.5'/><circle cx='17' cy='7' r='5' fill='none' stroke='#666666' stroke-width='1.5'/></svg>"

# --- person card -------------------------------------------------------------
function Card($id){
    $e=$byId[$id]; $nm=Esc $e.cap_entityname; $cd=Esc $e.cap_clientcode
    $st = if($null -ne $e.cap_status -and $stLbl.ContainsKey($e.cap_status)){ $stLbl[$e.cap_status] } else { '' }
    $dead = [bool]$e.cap_dateofdeath
    $dob = if($e.cap_dateofbirth){ ([datetime]$e.cap_dateofbirth).ToString('d MMM yyyy') } else { $null }
    $dod = if($dead){ ([datetime]$e.cap_dateofdeath).ToString('d MMM yyyy') } else { $null }
    $dates = if($dob -and $dod){ "b. $dob &nbsp;·&nbsp; † d. $dod" } elseif($dod){ "† d. $dod" } elseif($dob){ "b. $dob" } else { "&nbsp;" }
    $rel = Esc (RelTo $id)
    $focalCls = if($id -eq $focus.cap_entityid){ ' focal' } else { '' }
    $deadCls  = if($dead){ ' deceased' } else { '' }
@"
<div class="person$focalCls$deadCls">
  <div class="pname">$nm</div>
  <div class="pmeta"><span class="code">$cd</span> <span class="chip">$(Esc $st)</span></div>
  <div class="pdates">$dates</div>
  <div class="prel">$rel</div>
</div>
"@ }

# --- generations html: couples grouped ---------------------------------------
$genHtml=""
foreach($lv in ($cluster | ForEach-Object { $level[$_] } | Sort-Object -Unique)){
    $ids = @($cluster | Where-Object { $level[$_] -eq $lv } | Sort-Object { $byId[$_].cap_entityname })
    $done=New-Object System.Collections.Generic.HashSet[string]; $units=@()
    foreach($id in $ids){
        if($done.Contains($id)){ continue }
        $sp = @((SetOf $spouses $id) | Where-Object { $ids -contains $_ -and -not $done.Contains($_) }) | Select-Object -First 1
        if($sp){ [void]$done.Add($id); [void]$done.Add($sp)
            $a=$id; $b=$sp; if($b -eq $focus.cap_entityid){ $a=$sp; $b=$id }
            $units += [pscustomobject]@{ f=($a -eq $focus.cap_entityid); h="<div class='couple'>$(Card $a)<div class='knot' title='Spouse'>$RINGS</div>$(Card $b)</div>" } }
        else { [void]$done.Add($id); $units += [pscustomobject]@{ f=($id -eq $focus.cap_entityid); h=(Card $id) } }
    }
    $lbl = switch([int]$lv){ {$_ -lt 0}{"Generation up $(-$lv)"} 0{"Focal generation"} 9{"Connected"} default{"Generation down $lv"} }
    $genHtml += "<div class='genlabel'>$lbl</div><div class='genrow'>$((($units | Sort-Object { -[int]$_.f }) | ForEach-Object h) -join '')</div>"
}

# --- focal (left-anchored) view: columns by kinship distance ------------------
$DIST = @{ 'spouse'=1;'child'=1;'parent'=1;'sibling'=1;
           'former spouse'=1;'grandchild'=2;'grandparent'=2;'child-in-law'=2;'parent-in-law'=2;'sibling-in-law'=2;'step-child'=2;'aunt/uncle'=2;'niece/nephew'=2;
           'cousin'=3;'relative'=3 }
$fGiven = (($focus.cap_entityname -split ',\s*')[-1]).Trim(); if(-not $fGiven){ $fGiven = $focus.cap_entityname }
$fSp = @((SetOf $spouses $focus.cap_entityid) | Where-Object { $cluster.Contains($_) })
$fEx = @((SetOf $exsp $focus.cap_entityid) | Where-Object { $cluster.Contains($_) })
$cols=@{1=@();2=@();3=@()}
$cdone=New-Object System.Collections.Generic.HashSet[string]
foreach($id in ($cluster | Where-Object { $_ -ne $focus.cap_entityid -and $fSp -notcontains $_ -and $fEx -notcontains $_ } | Sort-Object { $byId[$_].cap_entityname })){
    if($cdone.Contains($id)){ continue }
    $d = $DIST[(RelTo $id)]; if(-not $d){ $d = 3 }
    $sp = @((SetOf $spouses $id) | Where-Object { $cluster.Contains($_) -and $_ -ne $focus.cap_entityid -and $fSp -notcontains $_ -and -not $cdone.Contains($_) }) | Select-Object -First 1
    if($sp){
        $ds = $DIST[(RelTo $sp)]; if(-not $ds){ $ds = 3 }
        $top=$id; $bot=$sp; if($ds -lt $d){ $top=$sp; $bot=$id; $d=$ds }
        [void]$cdone.Add($top); [void]$cdone.Add($bot)
        $cols[$d] += "<div class='cstack'>$(Card $top)<div class='knot' title='Spouse'>$RINGS</div>$(Card $bot)</div>"
    } else { [void]$cdone.Add($id); $cols[$d] += (Card $id) }
}
$colLbl = @{1='Immediate';2='Close';3='Extended'}
$focalCols = ""
foreach($d in 1,2,3){ if($cols[$d].Count){
    $focalCols += "<div class='fcol'><div class='genlabel'>$($colLbl[$d])</div>$($cols[$d] -join '')</div>" } }
$spStack = ($fSp | ForEach-Object { "<div class='klink' title='Spouse'>$RINGS<span>spouse of $fGiven</span></div>" + (Card $_) }) -join ''
$spStack += ($fEx | ForEach-Object { "<div class='klink' title='Former spouse'>$RINGSX<span>former spouse of $fGiven</span></div>" + (Card $_) }) -join ''
$focalHtml = "<div class='focalwrap'><div class='fcol fanchor'><div class='genlabel'>Focal</div>$(Card $focus.cap_entityid)$spStack</div>$focalCols</div>"

# --- authority panel ---------------------------------------------------------
function NoteBits($n){
    $role = if($n -match 'PRIMARY'){'PRIMARY'} elseif($n -match 'ALTERNATIVE'){'ALTERNATIVE'} elseif($n -match 'SUBSTITUTE'){'SUBSTITUTE'} else {''}
    $ord  = if($n -match 'order (\d+) of (\d+)'){ "order $($Matches[1])/$($Matches[2])" } else { '' }
    $state= if($n -match 'operative immediately'){ 'OPERATIVE' } elseif($n -match '(dormant|springing)'){ 'DORMANT' } elseif($role -eq 'PRIMARY'){ 'OPERATIVE' } else { '' }
    $trig = if($n -match 'springing on ([^.]+)'){ $Matches[1].Trim() } else { '' }
    $draft= $n -match 'DRAFT'
    $cert = $n -match 'certified'
    [pscustomobject]@{ role=$role; ord=$ord; state=$state; trig=$trig; draft=$draft; cert=$cert }
}
$authEdges = @($edges | Where-Object { $AUTH -contains $relLbl[$_.cap_relationshiptype] -and $cluster.Contains($_._cap_toentityid_value) })
$authHtml=""
foreach($grp in ($authEdges | Group-Object _cap_toentityid_value)){
    $p=$byId[$grp.Name]
    $rows=""
    foreach($ed in ($grp.Group | Sort-Object { $relLbl[$_.cap_relationshiptype] }, { $_.cap_notes })){
        $h=$byId[$ed._cap_fromentityid_value]; $t=Esc $relLbl[$ed.cap_relationshiptype]
        $n = if($hasNotes){ [string]$ed.cap_notes } else { '' }
        $b = NoteBits $n
        $stateHtml = switch($b.state){ 'OPERATIVE'{"<span class='op'>OPERATIVE</span>"} 'DORMANT'{"<span class='dorm'>DORMANT</span>"} default{''} }
        if($b.trig){ $stateHtml += "<div class='trig'>springs: $(Esc $b.trig)</div>" }
        $roleTxt = (@($b.role,$b.ord) | Where-Object { $_ }) -join ' · '
        $flags = ""
        if($b.draft){ $flags += "<span class='draftflag'>DRAFT — not to be relied upon</span>" }
        if($b.cert){  $flags += "<span class='tick'>✓ capacity certified 03/09/2026</span>" }
        $rows += "<tr><td>$(Esc $h.cap_entityname)<div class='sub'>$(Esc $h.cap_clientcode)</div></td><td>$t</td><td>$(Esc $roleTxt)</td><td>$stateHtml</td><td>$flags</td></tr>"
    }
    $authHtml += "<div class='banner'>Authority over $(Esc $p.cap_entityname)</div>
<table class='auth'><thead><tr><th>Holder</th><th>Instrument</th><th>Role</th><th>State</th><th>Flags &amp; evidence</th></tr></thead><tbody>$rows</tbody></table>"
}
if(-not $authHtml){ $authHtml = "<div class='note'>No authority edges recorded within this family.</div>" }

# --- assemble ----------------------------------------------------------------
$today = Get-Date -Format 'd MMMM yyyy'
$html = @"
<!doctype html><html><head><meta charset="utf-8"><title>Family Tree — $(Esc $focus.cap_entityname)</title>
<style>
:root{--red:#FA0217;--ink:#3A3A3A;--grey:#666666;--caption:#909090;--green:#1F7A4A;--link:#215B9E;--highlight:#FFE36E;--panel:#F7F7F8;--hair:#D8DADD}
*{box-sizing:border-box} body{font-family:"Helvetica Neue",Helvetica,Arial,sans-serif;color:var(--ink);background:#fff;margin:0;padding:28px 34px}
.wordmark{font-size:15px;font-weight:bold;letter-spacing:.3px}.wordmark .dot{color:var(--red)}
.eyebrow{font-size:8.5px;font-weight:bold;letter-spacing:1.6px;text-transform:uppercase;color:var(--caption);margin-top:2px}
h1{font-size:22px;margin:14px 0 2px}.sub{color:var(--grey);font-size:9px}
.meta{color:var(--caption);font-size:8px;margin-bottom:14px}
.note{background:var(--panel);border-left:4px solid var(--green);padding:8px 12px;font-size:9px;color:var(--grey);margin:10px 0 18px}
.banner{background:var(--panel);border-left:4.5px solid var(--red);border-top:1px solid var(--red);border-bottom:1px solid var(--hair);padding:6px 10px;font-size:11px;font-weight:bold;letter-spacing:.6px;text-transform:uppercase;margin:22px 0 10px}
.genlabel{font-size:8.5px;font-weight:bold;letter-spacing:1.4px;text-transform:uppercase;color:var(--caption);margin:14px 0 6px}
.genrow{display:flex;flex-wrap:wrap;gap:12px;align-items:stretch}
.couple{display:flex;align-items:center;gap:6px;border:1px solid var(--hair);border-radius:4px;padding:6px;background:#fff}
.cstack{display:flex;flex-direction:column;gap:2px;border:1px solid var(--hair);border-radius:4px;padding:6px;background:#fff}
.knot{color:var(--grey);line-height:0;text-align:center;padding:1px 2px;cursor:default}
.cstack .knot svg{transform:rotate(90deg)}
.cstack .knot{padding:5px 0}
.klink{display:flex;align-items:center;justify-content:center;gap:6px;color:var(--caption);font-size:7.5px;font-weight:bold;letter-spacing:1.2px;text-transform:uppercase;padding:5px 0}
.person{border:1px solid var(--hair);border-left:4px solid var(--hair);border-radius:3px;background:#fff;padding:8px 10px;min-width:172px}
.person.focal{border-left-color:var(--red)}
.person.deceased .pname{color:var(--grey)}
.pname{font-weight:bold;font-size:11px}
.pmeta{margin-top:2px}.code{color:var(--caption);font-size:8px}
.chip{display:inline-block;background:var(--panel);border:1px solid var(--hair);border-radius:8px;padding:0 7px;font-size:7.3px;color:var(--grey);margin-left:4px}
.pdates{font-size:8px;color:var(--grey);margin-top:3px}
.prel{font-size:8px;color:var(--link);margin-top:2px}
table.auth{border-collapse:collapse;width:100%;font-size:8.5px;border:1px solid var(--hair);border-top:none}
table.auth th{background:var(--panel);border-top:2px solid var(--red);border-bottom:1px solid var(--hair);padding:5px 8px;text-align:left;font-size:8px;letter-spacing:1px;text-transform:uppercase;color:var(--grey)}
table.auth td{border-bottom:1px solid var(--hair);padding:6px 8px;vertical-align:top}
table.auth tr:nth-child(even) td{background:var(--panel)}
.op{color:var(--green);font-weight:bold}.dorm{color:var(--grey);font-weight:bold}
.trig{font-size:7.5px;color:var(--caption);margin-top:2px}
.draftflag{display:inline-block;background:var(--highlight);border:1px solid var(--red);padding:1px 6px;font-size:7.3px;font-weight:bold;margin:1px 4px 1px 0}
.tick{display:inline-block;color:var(--green);font-family:"DejaVu Sans",sans-serif;font-size:8px;font-weight:bold;margin:1px 0}
.viewtoggle{float:right;margin-top:-34px}
.viewtoggle button{background:var(--panel);border:1px solid var(--red);color:var(--ink);font-weight:bold;font-size:8.5px;letter-spacing:.6px;padding:4px 12px;border-radius:2px;min-width:110px;cursor:pointer;font-family:inherit}
.viewtoggle button:focus{outline:none;box-shadow:0 0 0 2px rgba(250,2,23,.12)}
.viewtoggle button.on{color:var(--red)}
.focalwrap{display:flex;gap:18px;align-items:flex-start}
.fcol{display:flex;flex-direction:column;gap:10px;min-width:190px;border-left:1px solid var(--hair);padding-left:14px}
.fcol.fanchor{border-left:none;padding-left:0}
.fanchor .person{border-left:4px solid var(--red);min-width:200px}
#view-dynasty{display:none}
footer{margin-top:26px;color:var(--caption);font-size:7.3px;border-top:1px solid var(--hair);padding-top:8px}
</style></head><body>
<div class="wordmark">commercial <span class="dot">●</span> ACCOUNTING</div>
<div class="eyebrow">Family Tree &amp; Protection View</div>
<h1>$(Esc $focus.cap_entityname) — family</h1>
<div class="meta">Focal: $(Esc $FocusCode) · generated $today · $($cluster.Count) people · walker consumer 2</div>
<div class="note"><b>PRACTICE EYES ONLY.</b> Default-deny doctrine: partner discretion/approval gates every disclosure. This view informs the partner's judgment; it never automates disclosure or action. Draft instruments are flagged and not to be relied upon.</div>
<div class="banner">Family web</div>
<div class="viewtoggle">
  <button id="btn-focal" class="on" onclick="setView('focal')">FOCAL VIEW</button>
  <button id="btn-dynasty" onclick="setView('dynasty')">DYNASTY VIEW</button>
</div>
<div id="view-focal">$focalHtml</div>
<div id="view-dynasty">$genHtml</div>
<script>
function setView(v){
  document.getElementById('view-focal').style.display   = v==='focal'   ? 'block' : 'none';
  document.getElementById('view-dynasty').style.display = v==='dynasty' ? 'block' : 'none';
  document.getElementById('btn-focal').classList.toggle('on', v==='focal');
  document.getElementById('btn-dynasty').classList.toggle('on', v==='dynasty');
}
</script>
$authHtml
<footer>Commercial Accounting · CAP protection panel · derived relations computed from the primary spine at generation time — nothing stored twice. Logo is the typographic stand-in (brand_logo.png pending).</footer>
</body></html>
"@
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$out = Join-Path $OutDir ("FamilyTree_" + $FocusCode + "_" + (Get-Date -Format yyyy-MM-dd) + ".html")
Set-Content -Path $out -Value $html -Encoding UTF8
Say "Written: $out" Green
Start-Process $out

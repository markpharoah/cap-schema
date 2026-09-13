# 34-authority-and-derivation.ps1 — protection panel, first stone
# ---------------------------------------------------------------------------
# RATIFIED 2026-09-13 (night): authority lives in the graph as edges, not a
# side table. cap_relationshiptype grows:
#   Attorney for (EPOA) · Guardian of · Executor for · Authorised contact for
# Authority edges are ASSERTIONS: evidence basis belongs in notes
# (sighted / advised / assumed) until document management exists.
#
# Also ships the WALKER (consumer 1 of 3): derives kinship from the primary
# spine (Spouse / Parent-Child / Sibling) and audits every stored
# "Relative of" edge:
#   DERIVABLE  -> retirement candidate (assertion now proven by primaries)
#   UNDERIVABLE-> data gap (a primary edge is missing — or the assertion is wrong)
#
#   PREVIEW/report (default):  .\34-authority-and-derivation.ps1
#   Vocab insert + report:     .\34-authority-and-derivation.ps1 -Apply
#   Also retire derivable:     .\34-authority-and-derivation.ps1 -Apply -Retire
# Retire = DEACTIVATE with audit note; never delete (assertion stays as
# inactive evidence). Run -Retire only after eyeballing the report.
# ---------------------------------------------------------------------------
param(
    [switch]$Apply,
    [switch]$Retire
)
. "$PSScriptRoot\_connect.ps1"
$ErrorActionPreference = "Stop"
function Get-All($u){ $o=@(); while($u){ $r=Invoke-RestMethod -Uri $u -Headers $H; $o+=$r.value; $u=$r.'@odata.nextLink'}; $o }
function Say($m,$c="Gray"){ Write-Host $m -ForegroundColor $c }
$mode = if ($Apply) {"APPLY"} else {"PREVIEW"}
Say "=== 34-authority-and-derivation [$mode$(if($Retire){' +RETIRE'})] ===" Cyan

# --- 1. AUTHORITY VOCABULARY -------------------------------------------------
function Get-OptionMap($n){ $m=@{}; foreach($o in (Invoke-RestMethod -Headers $H -Uri "$base/GlobalOptionSetDefinitions(Name='$n')").Options){ $m[$o.Label.UserLocalizedLabel.Label]=$o.Value }; $m }
$relMap = Get-OptionMap 'cap_relationshiptype'
foreach($label in 'Attorney for (EPOA)','Guardian of','Executor for','Authorised contact for'){
    if($relMap.ContainsKey($label)){ Say "  '$label' already present" DarkGray; continue }
    Say "  option '$label' -> $(if($Apply){'INSERT'}else{'would insert'})" Yellow
    if($Apply){
        $body=@{ OptionSetName='cap_relationshiptype'; Label=@{LocalizedLabels=@(@{Label=$label;LanguageCode=1033})} } | ConvertTo-Json -Depth 6
        $r=Invoke-RestMethod -Headers $H -Method Post -Uri "$base/InsertOptionValue" -Body $body -ContentType "application/json"
        $relMap[$label]=$r.NewOptionValue
    }
}

# --- 2. LOAD GRAPH -----------------------------------------------------------
$ents = Get-All "$base/cap_entities?`$select=cap_entityid,cap_clientcode,cap_entityname,cap_status,statecode"
$name=@{}; foreach($e in $ents){ $name[$e.cap_entityid]="$($e.cap_clientcode) $($e.cap_entityname)".Trim() }
$edges = Get-All ("$base/cap_entityrelationships?`$select=cap_entityrelationshipid,_cap_fromentityid_value,_cap_toentityid_value,cap_relationshiptype" + $(if((Get-All "$base/EntityDefinitions(LogicalName='cap_entityrelationship')/Attributes?`$select=LogicalName&`$filter=LogicalName eq 'cap_notes'").Count){",cap_notes"}) + "&`$filter=statecode eq 0")
$lbl=@{}; foreach($k in $relMap.Keys){ $lbl[$relMap[$k]]=$k }
Say ("Graph: " + $ents.Count + " entities, " + $edges.Count + " active edges")

# --- 3. BUILD PRIMARY SPINE --------------------------------------------------
# Convention: edge reads FROM <type> TO. "Child of": FROM is child, TO parent.
$parents=@{}; $children=@{}; $spouses=@{}; $sibsX=@{}   # explicit sibling
function AddTo([hashtable]$h,$k,$v){ if(-not $h.ContainsKey($k)){ $h[$k]=New-Object System.Collections.Generic.HashSet[string] }; [void]$h[$k].Add($v) }
foreach($ed in $edges){
    $f=$ed._cap_fromentityid_value; $t=$ed._cap_toentityid_value
    switch($lbl[$ed.cap_relationshiptype]){
        'Child of'   { AddTo $parents $f $t; AddTo $children $t $f }
        'Parent of'  { AddTo $parents $t $f; AddTo $children $f $t }
        'Spouse of'  { AddTo $spouses $f $t; AddTo $spouses $t $f }
        'Sibling of' { AddTo $sibsX $f $t;  AddTo $sibsX $t $f }
    }
}
function SetOf([hashtable]$h,$k){ if($h.ContainsKey($k)){ $h[$k] } else { @() } }
function Sibs($x){   # explicit ∪ shared-parent (excluding self)
    $s=New-Object System.Collections.Generic.HashSet[string]
    foreach($v in (SetOf $sibsX $x)){ [void]$s.Add($v) }
    foreach($p in (SetOf $parents $x)){ foreach($c in (SetOf $children $p)){ if($c -ne $x){ [void]$s.Add($c) } } }
    $s
}

# --- 4. DERIVE RELATION FOR A PAIR ------------------------------------------
# DeriveClean($a,$b) answers "what is B to A" from the primary spine only.
# The audit calls both directions, so inverse labels come free.
function DeriveClean($a,$b){
    if((SetOf $spouses $a) -contains $b){ return 'spouse (primary)' }
    if((SetOf $parents $a) -contains $b){ return 'parent (primary)' }
    if((SetOf $children $a) -contains $b){ return 'child (primary)' }
    if((Sibs $a) -contains $b){ return 'sibling' }
    foreach($p in (SetOf $parents $a)){ if((SetOf $parents $p) -contains $b){ return 'grandparent' } }
    foreach($c in (SetOf $children $a)){ if((SetOf $children $c) -contains $b){ return 'grandchild' } }
    foreach($p in (SetOf $parents $a)){ foreach($ps in (Sibs $p)){
        if($ps -eq $b){ return 'aunt/uncle' }
        if((SetOf $spouses $ps) -contains $b){ return 'aunt/uncle (by marriage)' } } }
    foreach($s in (Sibs $a)){
        foreach($c in (SetOf $children $s)){ if($c -eq $b){ return 'niece/nephew' } }
        foreach($sp in (SetOf $spouses $s)){
            if($sp -eq $b){ return 'sibling-in-law' }
            foreach($c in (SetOf $children $sp)){ if($c -eq $b){ return 'niece/nephew (by marriage)' } } } }
    foreach($p in (SetOf $parents $a)){ foreach($ps in (Sibs $p)){ foreach($c in (SetOf $children $ps)){ if($c -eq $b){ return 'cousin' } } } }
    foreach($sp in (SetOf $spouses $a)){
        if((SetOf $parents $sp) -contains $b){ return 'parent-in-law' }
        foreach($s in (Sibs $sp)){ if($s -eq $b){ return 'sibling-in-law' }
            if((SetOf $spouses $s) -contains $b){ return 'sibling-in-law (spouse)' } } }
    foreach($c in (SetOf $children $a)){ if((SetOf $spouses $c) -contains $b){ return 'child-in-law' } }
    foreach($p in (SetOf $parents $a)){ foreach($sp in (SetOf $spouses $p)){
        if($sp -eq $b -and -not ((SetOf $parents $a) -contains $b)){ return 'step-parent' } } }
    foreach($c in (SetOf $children $a)){ foreach($cp in (SetOf $parents $c)){
        if($cp -ne $a -and -not ((SetOf $spouses $a) -contains $cp)){ } } }  # reserved: blended-family v2
    $null
}

# --- 5. AUDIT STORED RELATIVE-OF EDGES ---------------------------------------
Say "`n-- RELATIVE-OF AUDIT (walker consumer 1) --" Cyan
$relOfVal = $relMap['Relative of']
$retireList=@(); $gaps=0; $derivable=0
foreach($ed in ($edges | Where-Object cap_relationshiptype -eq $relOfVal)){
    $f=$ed._cap_fromentityid_value; $t=$ed._cap_toentityid_value
    $d1 = DeriveClean $f $t; $d2 = DeriveClean $t $f
    $note = if($ed.PSObject.Properties['cap_notes']){ $ed.cap_notes } else { '' }
    if($d1 -or $d2){
        $derivable++
        Say ("  DERIVABLE: {0} ~ {1}  [note: {2}]  => {3}" -f $name[$f],$name[$t],$note,($(if($d2){$d2}else{$d1}))) Green
        $retireList += $ed
    } else {
        $gaps++
        Say ("  DATA GAP : {0} ~ {1}  [note: {2}]  — no primary path; a spine edge is missing or the assertion is wrong" -f $name[$f],$name[$t],$note) Yellow
    }
}
Say "  derivable: $derivable   gaps: $gaps"

# --- 6. RETIRE (only on explicit switch, only after eyeballing) --------------
if($Retire -and $Apply -and $retireList.Count){
    Say "`n-- RETIRING $($retireList.Count) derivable Relative-of edges (deactivate, never delete) --" Cyan
    foreach($ed in $retireList){
        Invoke-RestMethod -Headers $H -Method Patch -Uri "$base/cap_entityrelationships($($ed.cap_entityrelationshipid))" `
            -Body (@{ statecode=1; statuscode=2 } | ConvertTo-Json) -ContentType "application/json" | Out-Null
        Say "  retired: $($name[$ed._cap_fromentityid_value]) ~ $($name[$ed._cap_toentityid_value])" DarkYellow
    }
} elseif($Retire){ Say "`n-Retire requires -Apply; nothing retired." Yellow }
else { Say "`nReport only — rerun with -Apply -Retire after eyeballing to retire derivable edges." Green }

# 30-resync-names.ps1 — derived names, never hand-edited
# ---------------------------------------------------------------------------
# RULING (2026-09-13): names that embed other fields are DERIVED data and are
# resynced by script after any retype/merge — never hand-edited (40 names is
# how fiction starts). Two rules:
#   cap_engagement:          "{Entity Name} - {Engagement Type label}"
#   cap_entityrelationship:  "{From Name} {Type label} {To Name}"
# Fixes both naming eras (code-sentences from the 12th, name-sentences from
# 31) into one convention. Rerun-safe: only rows whose name differs are
# touched. PREVIEW default; -Apply to write.
# ---------------------------------------------------------------------------
param([switch]$Apply)
. "$PSScriptRoot\_connect.ps1"
$ErrorActionPreference = "Stop"
function Get-All($u){ $o=@(); while($u){ $r=Invoke-RestMethod -Uri $u -Headers $H; $o+=$r.value; $u=$r.'@odata.nextLink'}; $o }
function Say($m,$c="Gray"){ Write-Host $m -ForegroundColor $c }
$mode = if ($Apply) {"APPLY"} else {"PREVIEW"}
Say "=== 30-resync-names [$mode] ===" Cyan

# option label maps
function Labels($n){ $m=@{}; foreach($o in (Invoke-RestMethod -Headers $H -Uri "$base/GlobalOptionSetDefinitions(Name='$n')").Options){ $m[$o.Value]=$o.Label.UserLocalizedLabel.Label }; $m }
$typeLbl = Labels 'cap_engagementtype'
$relLbl  = Labels 'cap_relationshiptype'

# entities by id
$ents = Get-All "$base/cap_entities?`$select=cap_entityid,cap_entityname"
$eName = @{}; foreach($e in $ents){ $eName[$e.cap_entityid]=$e.cap_entityname }

# probe engagement->entity lookup (Block 4 lesson: never assume)
$m2o = (Invoke-RestMethod -Headers $H -Uri "$base/EntityDefinitions(LogicalName='cap_engagement')/ManyToOneRelationships?`$select=ReferencedEntity,ReferencingAttribute").value
$engEntAttr = ($m2o | Where-Object ReferencedEntity -eq 'cap_entity' | Select-Object -First 1).ReferencingAttribute
Say "cap_engagement entity lookup attribute: $engEntAttr"

$r=[ordered]@{ engRenamed=0; edgeRenamed=0; engSkipped=0; edgeSkipped=0; unresolved=0 }

Say "`n-- ENGAGEMENTS: '{Entity} - {Type}' --" Cyan
$engs = Get-All "$base/cap_engagements?`$select=cap_engagementid,cap_name,cap_engagementtype,_$($engEntAttr)_value&`$filter=statecode eq 0"
foreach($g in $engs){
    $en = $eName[$g."_$($engEntAttr)_value"]; $ty = $typeLbl[$g.cap_engagementtype]
    if(-not $en -or -not $ty){ $r.unresolved++; continue }
    $want = "$en - $ty"
    if($g.cap_name -ceq $want){ $r.engSkipped++; continue }
    Say "  '$($g.cap_name)' -> '$want'"
    if($Apply){ Invoke-RestMethod -Headers $H -Method Patch -Uri "$base/cap_engagements($($g.cap_engagementid))" -Body (@{cap_name=$want}|ConvertTo-Json) -ContentType "application/json" | Out-Null }
    $r.engRenamed++
}

Say "`n-- EDGES: '{From} {Type} {To}' --" Cyan
$nameAttr = (Invoke-RestMethod -Headers $H -Uri "$base/EntityDefinitions(LogicalName='cap_entityrelationship')?`$select=PrimaryNameAttribute").PrimaryNameAttribute
$edges = Get-All "$base/cap_entityrelationships?`$select=cap_entityrelationshipid,$nameAttr,_cap_fromentityid_value,_cap_toentityid_value,cap_relationshiptype&`$filter=statecode eq 0"
foreach($ed in $edges){
    $f=$eName[$ed._cap_fromentityid_value]; $t=$eName[$ed._cap_toentityid_value]; $ty=$relLbl[$ed.cap_relationshiptype]
    if(-not $f -or -not $t -or -not $ty){ $r.unresolved++; continue }
    $want = "$f $ty $t"
    if($ed.$nameAttr -ceq $want){ $r.edgeSkipped++; continue }
    Say "  '$($ed.$nameAttr)' -> '$want'"
    if($Apply){ Invoke-RestMethod -Headers $H -Method Patch -Uri "$base/cap_entityrelationships($($ed.cap_entityrelationshipid))" -Body (@{$nameAttr=$want}|ConvertTo-Json) -ContentType "application/json" | Out-Null }
    $r.edgeRenamed++
}

Say "`n=== SUMMARY [$mode] ===" Cyan
$r.GetEnumerator() | ForEach-Object { Say ("  {0,-12} {1}" -f $_.Key,$_.Value) }
if(-not $Apply){ Say "`nPreview only. Re-run with -Apply." Green }

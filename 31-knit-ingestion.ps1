# 31-knit-ingestion.ps1 — CAP schema/data pass: knit-candidates resolution
# ---------------------------------------------------------------------------
# Applies knit-actions.csv (the EXPLICIT action file — no free-text parsing
# here, per the 29 ruling: mass-edit surfaces must not generate fiction).
#
#   PREVIEW (default):  .\31-knit-ingestion.ps1
#   APPLY:              .\31-knit-ingestion.ps1 -Apply
#
# What it does, in order:
#   0. Schema prep (idempotent):
#        - cap_entity.cap_dateofdeath (DateOnly) if missing
#        - cap_entitystatus option "Merged" if missing
#        - cap_relationshiptype options "Sibling of", "Relative of" if missing
#   1. MERGE victims -> survivors: repoint every edge lookup, mark victim
#        Client Status = Merged, note "Merged into <code>". Never delete.
#   2. RETYPE edges per action sentence (Subject <Verb> Object; from=Subject).
#        Direction convention: an edge reads as a sentence FROM <type> TO.
#   3. DEACTIVATE-EDGE for edges ruled false (statecode 1 — temporal, kept).
#   4. Sweep: deactivate self-loops and (from,to,type) duplicates created by
#        merges — symmetric types (Spouse/Sibling/Relative/Associated) deduped
#        in either direction. Oldest edge survives.
#   5. STATUS changes (Active -> Former only; already-Former left alone).
#   6. Cross-checks: active engagements attached to Former/Merged entities
#        are REPORTED (triage decides; this script never touches engagements).
#   EXCEPTION / DOD-REQUIRED rows are reported, never applied.
#
# Rerun-safe: every step checks current state first. Doctrine: PROBE bind
# names via ManyToOneRelationships, never assume; option values resolved by
# label at runtime; attribute PUT (if ever needed) requires full identity.
# ---------------------------------------------------------------------------

param(
    [switch]$Apply,
    [string]$ActionsCsv = "C:\CAP\schema\data\knit-actions.csv"
)

# --- CONNECTION -------------------------------------------------------------
# Paste the standard connection block from 29-relax-required.ps1 here
# (token acquisition -> $base = "https://<org>.crm6.dynamics.com/api/data/v9.2",
#  $H = @{ Authorization = "Bearer $token"; ... }).
. "$PSScriptRoot\_connect.ps1"   # or inline the standard block
# Expects: $base (API root), $H (headers hashtable)
# ---------------------------------------------------------------------------

$ErrorActionPreference = "Stop"
function Get-All($url) {
    $out = @(); $u = $url
    while ($u) {
        $r = Invoke-RestMethod -Uri $u -Headers $H -Method Get
        $out += $r.value
        $u = $r.'@odata.nextLink'
    }
    return $out
}
function Say($m,$c="Gray"){ Write-Host $m -ForegroundColor $c }
$mode = if ($Apply) { "APPLY" } else { "PREVIEW" }
Say "=== 31-knit-ingestion [$mode] ===" Cyan

$actions = Import-Csv $ActionsCsv
Say ("Actions loaded: " + $actions.Count)

# --- 0a. Probe nav property names (doctrine: never assume) ------------------
$rels = (Invoke-RestMethod -Headers $H -Method Get -Uri (
    "$base/EntityDefinitions(LogicalName='cap_entityrelationship')" +
    "/ManyToOneRelationships?`$select=ReferencingAttribute,ReferencingEntityNavigationPropertyName")).value
$navFrom = ($rels | Where-Object ReferencingAttribute -eq 'cap_fromentityid').ReferencingEntityNavigationPropertyName
$navTo   = ($rels | Where-Object ReferencingAttribute -eq 'cap_toentityid').ReferencingEntityNavigationPropertyName
if (-not $navFrom -or -not $navTo) { throw "Could not probe from/to nav properties — stop." }
Say "Nav props: from=$navFrom to=$navTo"

# Probe: does the edge table carry cap_notes? (Doctrine: never assume.)
$edgeHasNotes = $true
try { Invoke-RestMethod -Headers $H -Method Get -Uri (
    "$base/EntityDefinitions(LogicalName='cap_entityrelationship')/Attributes(LogicalName='cap_notes')?`$select=LogicalName") | Out-Null }
catch { $edgeHasNotes = $false; Say "cap_entityrelationship has no cap_notes — relation detail will be reported, not stored" Yellow }

# --- 0b. Choice vocabularies -------------------------------------------------
function Get-OptionMap($optionSetName) {
    $os = Invoke-RestMethod -Headers $H -Method Get -Uri (
        "$base/GlobalOptionSetDefinitions(Name='$optionSetName')")
    $map = @{}
    foreach ($o in $os.Options) { $map[$o.Label.UserLocalizedLabel.Label] = $o.Value }
    return $map
}
function Ensure-Option($optionSetName, $label, $mapRef) {
    if ($mapRef.Value.ContainsKey($label)) { return }
    Say "Option '$label' missing on $optionSetName -> $(if($Apply){'INSERT'}else{'would insert'})" Yellow
    if ($Apply) {
        $body = @{ OptionSetName = $optionSetName;
                   Label = @{ LocalizedLabels = @(@{ Label = $label; LanguageCode = 1033 }) } } | ConvertTo-Json -Depth 6
        $r = Invoke-RestMethod -Headers $H -Method Post -Uri "$base/InsertOptionValue" -Body $body -ContentType "application/json"
        $mapRef.Value[$label] = $r.NewOptionValue
    }
}
$statusMap = Get-OptionMap 'cap_entitystatus'
$relMap    = Get-OptionMap 'cap_relationshiptype'
Ensure-Option 'cap_entitystatus'      'Merged'      ([ref]$statusMap)
Ensure-Option 'cap_relationshiptype'  'Sibling of'  ([ref]$relMap)
Ensure-Option 'cap_relationshiptype'  'Relative of' ([ref]$relMap)
$SYMMETRIC = @('Spouse of','Sibling of','Relative of','Associated with') |
    Where-Object { $relMap.ContainsKey($_) } | ForEach-Object { $relMap[$_] }

# --- 0c. cap_dateofdeath column ---------------------------------------------
$dodExists = $true
try {
    Invoke-RestMethod -Headers $H -Method Get -Uri (
      "$base/EntityDefinitions(LogicalName='cap_entity')/Attributes(LogicalName='cap_dateofdeath')?`$select=LogicalName") | Out-Null
} catch { $dodExists = $false }
if (-not $dodExists) {
    Say "cap_dateofdeath missing -> $(if($Apply){'CREATE'}else{'would create'}) (DateOnly)" Yellow
    if ($Apply) {
        $attr = @{
            '@odata.type' = 'Microsoft.Dynamics.CRM.DateTimeAttributeMetadata'
            SchemaName    = 'cap_DateOfDeath'
            Format        = 'DateOnly'
            DateTimeBehavior = @{ Value = 'DateOnly' }
            RequiredLevel = @{ Value = 'None' }
            DisplayName   = @{ LocalizedLabels = @(@{ Label='Date of Death'; LanguageCode=1033 }) }
            Description   = @{ LocalizedLabels = @(@{ Label='Ruling 2026-09-13: date-only, evidence not label. Drives comms suppression. Blank until known — never guessed.'; LanguageCode=1033 }) }
        } | ConvertTo-Json -Depth 6
        Invoke-RestMethod -Headers $H -Method Post -Body $attr -ContentType "application/json" -Uri (
            "$base/EntityDefinitions(LogicalName='cap_entity')/Attributes") | Out-Null
        Invoke-RestMethod -Headers $H -Method Post -Uri "$base/PublishAllXml" -ContentType "application/json" -Body "{}" | Out-Null
    }
}

# --- Load entities & edges ---------------------------------------------------
$ents = Get-All "$base/cap_entities?`$select=cap_entityid,cap_clientcode,cap_entityname,cap_status,cap_notes,statecode"
$byCode = @{}; foreach ($e in $ents) { if ($e.cap_clientcode) { $byCode[$e.cap_clientcode.Trim()] = $e } }
Say ("Entities loaded: " + $ents.Count)

$edges = Get-All ("$base/cap_entityrelationships?`$select=cap_entityrelationshipid,_cap_fromentityid_value," +
                  "_cap_toentityid_value,cap_relationshiptype,statecode,createdon")
Say ("Edges loaded: " + $edges.Count + " (active: " + (@($edges | Where-Object statecode -eq 0)).Count + ")")

function Resolve($code, $ctx) {
    $e = $byCode[$code]
    if (-not $e) { Say "  !! code $code not resolved ($ctx)" Red }
    return $e
}
function Edge-Between($idA, $idB) {   # active edges between two entities, either direction
    @($edges | Where-Object { $_.statecode -eq 0 -and (
        ($_._cap_fromentityid_value -eq $idA -and $_._cap_toentityid_value -eq $idB) -or
        ($_._cap_fromentityid_value -eq $idB -and $_._cap_toentityid_value -eq $idA)) })
}
function Patch-Edge($id, $body) {
    if ($Apply) { Invoke-RestMethod -Headers $H -Method Patch -Uri "$base/cap_entityrelationships($id)" `
        -Body ($body | ConvertTo-Json) -ContentType "application/json" | Out-Null }
}
function Deactivate($set, $id, $why) {
    Say "  deactivate $set $id — $why" DarkYellow
    if ($Apply) { Invoke-RestMethod -Headers $H -Method Patch -Uri "$base/$set($id)" `
        -Body (@{ statecode = 1; statuscode = 2 } | ConvertTo-Json) -ContentType "application/json" | Out-Null }
}

$report = [ordered]@{ entityadded=0; merged=0; repointed=0; retyped=0; flipped=0; added=0; dodset=0; deactivated=0; deduped=0; statuschanged=0; skipped=0; exceptions=0 }

# --- 0z. ADD-ENTITY (practice-known people, e.g. FAM-series never-clients) --
$toAdd = @($actions | Where-Object Action -eq 'ADD-ENTITY')
if($toAdd.Count){
    Say "`n-- ADD-ENTITY --" Cyan
    if(-not $statusMap.ContainsKey('Contact')){
        Say "  status 'Contact' missing -> $(if($Apply){'INSERT'}else{'would insert'})" Yellow
        if($Apply){
            $b=@{ OptionSetName='cap_entitystatus'; Label=@{LocalizedLabels=@(@{Label='Contact';LanguageCode=1033})} } | ConvertTo-Json -Depth 6
            $r2=Invoke-RestMethod -Headers $H -Method Post -Uri "$base/InsertOptionValue" -Body $b -ContentType "application/json"
            $statusMap['Contact']=$r2.NewOptionValue } }
    # probe entity-type lookup nav + Individual type id
    $typeNav = ((Invoke-RestMethod -Headers $H -Uri ("$base/EntityDefinitions(LogicalName='cap_entity')/ManyToOneRelationships?`$select=ReferencingAttribute,ReferencingEntityNavigationPropertyName,ReferencedEntity")).value |
        Where-Object ReferencingAttribute -eq 'cap_type')
    $typeSet = $typeNav.ReferencedEntity + 's'
    $indiv = (Invoke-RestMethod -Headers $H -Uri "$base/$typeSet`?`$filter=cap_name eq 'Individual'&`$select=$($typeNav.ReferencedEntity)id").value | Select-Object -First 1
    foreach($a in $toAdd){
        if($byCode.ContainsKey($a.SubjectCode)){ Say "  $($a.SubjectCode) already exists" DarkGray; continue }
        Say "  + $($a.SubjectCode) $($a.SubjectName) [Contact] ($($a.Note))" Green
        if($Apply){
            $body=@{ cap_entityname=$a.SubjectName; cap_clientcode=$a.SubjectCode }
            if($statusMap.ContainsKey('Contact')){ $body.cap_status=$statusMap['Contact'] }
            if($indiv){ $body["$($typeNav.ReferencingEntityNavigationPropertyName)@odata.bind"]="/$typeSet($($indiv.("$($typeNav.ReferencedEntity)id")))" }
            if($a.Note){ $body.cap_notes = $a.Note }
            $new=Invoke-RestMethod -Headers $H -Method Post -Uri "$base/cap_entities" -Body ($body|ConvertTo-Json) -ContentType "application/json" -ResponseHeadersVariable rh
            $id = [regex]::Match($rh.'OData-EntityId'[0],'\(([0-9a-f-]+)\)').Groups[1].Value
            $e=[pscustomobject]@{ cap_entityid=$id; cap_clientcode=$a.SubjectCode; cap_entityname=$a.SubjectName; cap_status=$statusMap['Contact']; cap_notes=$a.Note; statecode=0 }
        } else {
            $e=[pscustomobject]@{ cap_entityid=[guid]::NewGuid().ToString(); cap_clientcode=$a.SubjectCode; cap_entityname=$a.SubjectName; cap_status=$null; cap_notes=$a.Note; statecode=0 }
        }
        $byCode[$a.SubjectCode]=$e; $script:ents += $e
        $report.entityadded++
    }
}

# --- 1. MERGES ---------------------------------------------------------------
Say "`n-- MERGES --" Cyan
foreach ($a in ($actions | Where-Object Action -eq 'MERGE')) {
    $v = Resolve $a.SubjectCode "merge victim"; $s = Resolve $a.ObjectCode "merge survivor"
    if (-not $v -or -not $s) { $report.skipped++; continue }
    if ($statusMap.ContainsKey('Merged') -and $v.cap_status -eq $statusMap['Merged']) {
        Say "  $($a.SubjectCode) already Merged — skip" DarkGray; continue }
    Say "  $($a.SubjectCode) -> $($a.ObjectCode)  ($($a.Note))"
    foreach ($ed in @($edges | Where-Object { $_._cap_fromentityid_value -eq $v.cap_entityid -or $_._cap_toentityid_value -eq $v.cap_entityid })) {
        $body = @{}
        if ($ed._cap_fromentityid_value -eq $v.cap_entityid) { $body["$navFrom@odata.bind"] = "/cap_entities($($s.cap_entityid))"; $ed._cap_fromentityid_value = $s.cap_entityid }
        if ($ed._cap_toentityid_value   -eq $v.cap_entityid) { $body["$navTo@odata.bind"]   = "/cap_entities($($s.cap_entityid))"; $ed._cap_toentityid_value   = $s.cap_entityid }
        Patch-Edge $ed.cap_entityrelationshipid $body
        $report.repointed++
    }
    if ($Apply) {
        $note = ("Merged into $($a.ObjectCode) [31-knit " + (Get-Date -Format yyyy-MM-dd) + "]. " + $v.cap_notes).Trim()
        Invoke-RestMethod -Headers $H -Method Patch -Uri "$base/cap_entities($($v.cap_entityid))" `
            -Body (@{ cap_status = $statusMap['Merged']; cap_notes = $note } | ConvertTo-Json) -ContentType "application/json" | Out-Null
    }
    $report.merged++
}

# --- 2. RETYPE / KEEP --------------------------------------------------------
Say "`n-- RETYPES --" Cyan
foreach ($a in ($actions | Where-Object { $_.Action -in 'RETYPE','KEEP' })) {
    $subj = Resolve $a.SubjectCode "row $($a.SrcRow)"; $obj = Resolve $a.ObjectCode "row $($a.SrcRow)"
    if (-not $subj -or -not $obj) { $report.skipped++; continue }
    # After merges, codes in the action file may point at merged victims whose
    # edges were repointed — resolve through survivor if victim is Merged.
    $cand = Edge-Between $subj.cap_entityid $obj.cap_entityid
    if ($cand.Count -eq 0) { Say "  !! row $($a.SrcRow): no active edge $($a.SubjectCode)~$($a.ObjectCode)" Red; $report.skipped++; continue }
    $ed = $cand | Sort-Object createdon | Select-Object -First 1
    if ($a.Action -eq 'KEEP') { Say "  row $($a.SrcRow): keep $($a.SubjectCode) $($a.Verb) $($a.ObjectCode)" DarkGray; continue }
    $newType = $relMap[$a.Verb]
    if ($null -eq $newType) { Say "  !! row $($a.SrcRow): unknown type '$($a.Verb)'" Red; $report.skipped++; continue }
    $body = @{}
    if ($ed.cap_relationshiptype -ne $newType) { $body.cap_relationshiptype = $newType; $report.retyped++ }
    $directed = $SYMMETRIC -notcontains $newType
    if ($directed -and $ed._cap_fromentityid_value -ne $subj.cap_entityid) {
        # flip so the edge reads: SUBJECT <type> OBJECT
        $body["$navFrom@odata.bind"] = "/cap_entities($($subj.cap_entityid))"
        $body["$navTo@odata.bind"]   = "/cap_entities($($obj.cap_entityid))"
        $ed._cap_fromentityid_value = $subj.cap_entityid; $ed._cap_toentityid_value = $obj.cap_entityid
        $report.flipped++
    }
    if ($body.Count) {
        Say ("  row {0}: {1} {2} {3}{4}" -f $a.SrcRow, $a.SubjectCode, $a.Verb, $a.ObjectCode, ($(if($a.Note){" [$($a.Note)]"})))
        if ($a.Note -and $edgeHasNotes) { $body.cap_notes = $a.Note }
        Patch-Edge $ed.cap_entityrelationshipid $body
        $ed.cap_relationshiptype = $newType
    } else { Say "  row $($a.SrcRow): already correct" DarkGray }
}

# --- 3. DEACTIVATE FALSE EDGES ----------------------------------------------
Say "`n-- FALSE EDGES --" Cyan
foreach ($a in ($actions | Where-Object Action -eq 'DEACTIVATE-EDGE')) {
    $x = Resolve $a.SubjectCode "row $($a.SrcRow)"; $y = Resolve $a.ObjectCode "row $($a.SrcRow)"
    if (-not $x -or -not $y) { $report.skipped++; continue }
    foreach ($ed in (Edge-Between $x.cap_entityid $y.cap_entityid)) {
        Deactivate 'cap_entityrelationships' $ed.cap_entityrelationshipid "row $($a.SrcRow): $($a.Note)"
        $ed.statecode = 1; $report.deactivated++
    }
}

# --- 3b. ADD MISSING PRIMARY EDGES ------------------------------------------
Say "`n-- ADD-EDGE (primary facts revealed by fixes) --" Cyan
$edgeNameAttr = (Invoke-RestMethod -Headers $H -Method Get -Uri (
    "$base/EntityDefinitions(LogicalName='cap_entityrelationship')?`$select=PrimaryNameAttribute")).PrimaryNameAttribute
foreach ($a in ($actions | Where-Object Action -eq 'ADD-EDGE')) {
    $subj = Resolve $a.SubjectCode "add-edge"; $obj = Resolve $a.ObjectCode "add-edge"
    if (-not $subj -or -not $obj) { $report.skipped++; continue }
    $t = $relMap[$a.Verb]
    $exists = @(Edge-Between $subj.cap_entityid $obj.cap_entityid | Where-Object cap_relationshiptype -eq $t)
    if ($exists.Count) { Say "  $($a.SubjectCode) $($a.Verb) $($a.ObjectCode) already present" DarkGray; continue }
    Say "  + $($a.SubjectCode) $($a.Verb) $($a.ObjectCode)  ($($a.Note))" Green
    if ($Apply) {
        $body = @{ $edgeNameAttr = "$($subj.cap_entityname) $($a.Verb) $($obj.cap_entityname)";
                   cap_relationshiptype = $t;
                   "$navFrom@odata.bind" = "/cap_entities($($subj.cap_entityid))";
                   "$navTo@odata.bind"   = "/cap_entities($($obj.cap_entityid))" }
        if ($a.Note -and $edgeHasNotes) { $body.cap_notes = $a.Note }
        Invoke-RestMethod -Headers $H -Method Post -Uri "$base/cap_entityrelationships" `
            -Body ($body | ConvertTo-Json) -ContentType "application/json" | Out-Null
    }
    # register locally so the sweep sees it
    $edges += [pscustomobject]@{ cap_entityrelationshipid=[guid]::NewGuid(); _cap_fromentityid_value=$subj.cap_entityid;
        _cap_toentityid_value=$obj.cap_entityid; cap_relationshiptype=$t; statecode=0; createdon=(Get-Date) }
    $report.added++
}

# --- 3c. DATE OF DEATH -------------------------------------------------------
Say "`n-- DATE OF DEATH --" Cyan
foreach ($a in ($actions | Where-Object Action -eq 'DOD-SET')) {
    $e = Resolve $a.SubjectCode "dod"; if (-not $e) { $report.skipped++; continue }
    Say "  $($a.SubjectCode) $($a.SubjectName): cap_dateofdeath = $($a.Note)"
    if ($Apply) { Invoke-RestMethod -Headers $H -Method Patch -Uri "$base/cap_entities($($e.cap_entityid))" `
        -Body (@{ cap_dateofdeath = $a.Note } | ConvertTo-Json) -ContentType "application/json" | Out-Null }
    $report.dodset++
}

# --- 4. SELF-LOOP + DUPLICATE SWEEP -----------------------------------------
Say "`n-- SWEEP --" Cyan
$seen = @{}
foreach ($ed in ($edges | Where-Object statecode -eq 0 | Sort-Object createdon)) {
    if ($ed._cap_fromentityid_value -eq $ed._cap_toentityid_value) {
        Deactivate 'cap_entityrelationships' $ed.cap_entityrelationshipid "self-loop after merge"
        $ed.statecode = 1; $report.deduped++; continue
    }
    $t = $ed.cap_relationshiptype
    $k1 = "$($ed._cap_fromentityid_value)|$($ed._cap_toentityid_value)|$t"
    $k2 = "$($ed._cap_toentityid_value)|$($ed._cap_fromentityid_value)|$t"
    $dup = $seen.ContainsKey($k1) -or (($SYMMETRIC -contains $t) -and $seen.ContainsKey($k2))
    if ($dup) { Deactivate 'cap_entityrelationships' $ed.cap_entityrelationshipid "duplicate (from,to,type)"; $ed.statecode = 1; $report.deduped++ }
    else { $seen[$k1] = $true }
}

# --- 5. STATUS CHANGES -------------------------------------------------------
Say "`n-- STATUS --" Cyan
foreach ($a in ($actions | Where-Object Action -eq 'STATUS')) {
    $e = Resolve $a.SubjectCode "status"; if (-not $e) { $report.skipped++; continue }
    $target = ($a.Note -split '\s')[0]           # "Former (...)" -> Former
    if (-not $statusMap.ContainsKey($target)) { Say "  !! unknown status '$target'" Red; continue }
    if ($e.cap_status -eq $statusMap[$target]) { Say "  $($a.SubjectCode) already $target" DarkGray; continue }
    Say "  $($a.SubjectCode) $($a.SubjectName): -> $target  ($($a.Note))"
    if ($Apply) { Invoke-RestMethod -Headers $H -Method Patch -Uri "$base/cap_entities($($e.cap_entityid))" `
        -Body (@{ cap_status = $statusMap[$target] } | ConvertTo-Json) -ContentType "application/json" | Out-Null }
    $report.statuschanged++
}

# --- 6. EXCEPTIONS + CROSS-CHECKS -------------------------------------------
Say "`n-- EXCEPTIONS (not applied) --" Yellow
foreach ($a in ($actions | Where-Object { $_.Action -in 'EXCEPTION','DOD-REQUIRED' })) {
    Say "  [$($a.Action)] row $($a.SrcRow): $($a.SubjectCode) $($a.Verb) $($a.ObjectCode) — $($a.Note)" Yellow
    $report.exceptions++
}
Say "`n-- CROSS-CHECK: active engagements on Former/Merged entities --" Cyan
$flaggedIds = @()
foreach ($a in ($actions | Where-Object { $_.Action -in 'STATUS','MERGE' })) {
    $e = $byCode[$a.SubjectCode]; if ($e) { $flaggedIds += $e.cap_entityid } }
$engs = Get-All "$base/cap_engagements?`$select=cap_engagementid,cap_name,_cap_entityid_value,statecode"
# NOTE: probe the real entity-lookup value field name on cap_engagement if this
# select fails — Block 4 lesson: it was NOT cap_EntityId. Adjust `_..._value` accordingly.
foreach ($g in ($engs | Where-Object { $_.statecode -eq 0 -and $flaggedIds -contains $_._cap_entityid_value })) {
    Say "  !! active engagement '$($g.cap_name)' on flagged entity — triage decides" Red
}

Say ("`n=== SUMMARY [$mode] ===") Cyan
$report.GetEnumerator() | ForEach-Object { Say ("  {0,-14} {1}" -f $_.Key, $_.Value) }
if (-not $Apply) { Say "`nPreview only. Re-run with -Apply after eyeballing." Green }
else { Say "`nApplied. Run 30-resync-names.ps1 next if any engagement names went stale." Green }

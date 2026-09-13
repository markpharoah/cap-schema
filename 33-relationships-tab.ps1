# 33-relationships-tab.ps1 — the whole web on one screen
# ---------------------------------------------------------------------------
# THE REAL FIX for the two-coin-toss "Entity Relationships" menu entries:
#   1. Adds a "Relationships" tab to the cap_entity main form with BOTH
#      subgrids stacked — "This entity is ..." (from-side / subject) above
#      "Others, to this entity ..." (to-side / object). One click, whole web.
#   2. Renames the two associated-menu labels so Related-menu spelunking,
#      when it still happens, isn't a coin toss:
#         from-side -> "Relationships — as subject"
#         to-side   -> "Relationships — as object"
# FormXml surgery in the 28-forms craft. Rerun-safe: skips if the tab id is
# already in the form. PREVIEW default; -Apply to write. PublishAllXml at end.
# DOCTRINE: kinship views carry NO client-status filter (edges outlast
# engagements) — the default relationship view is used untouched.
# ---------------------------------------------------------------------------
param([switch]$Apply)
. "$PSScriptRoot\_connect.ps1"
$ErrorActionPreference = "Stop"
function Say($m,$c="Gray"){ Write-Host $m -ForegroundColor $c }
$mode = if ($Apply) {"APPLY"} else {"PREVIEW"}
Say "=== 33-relationships-tab [$mode] ===" Cyan
$TABID = "{a3d1e9c0-31aa-4f33-9d13-0000c0ffee01}"   # stable marker for rerun-safety (valid GUID)

# --- probe the two 1:N relationships entity -> entityrelationship -----------
$o2m = (Invoke-RestMethod -Headers $H -Uri ("$base/EntityDefinitions(LogicalName='cap_entity')/OneToManyRelationships" +
    "?`$filter=ReferencingEntity eq 'cap_entityrelationship'" +
    "&`$select=SchemaName,ReferencingAttribute,MetadataId")).value
$relFrom = $o2m | Where-Object ReferencingAttribute -eq 'cap_fromentityid'
$relTo   = $o2m | Where-Object ReferencingAttribute -eq 'cap_toentityid'
if(-not $relFrom -or -not $relTo){ throw "Could not probe from/to 1:N relationships — stop." }
Say "from-rel: $($relFrom.SchemaName)   to-rel: $($relTo.SchemaName)"

# --- default public view for the edge table ----------------------------------
$view = (Invoke-RestMethod -Headers $H -Uri ("$base/savedqueries?`$select=savedqueryid,name" +
    "&`$filter=returnedtypecode eq 'cap_entityrelationship' and querytype eq 0 and isdefault eq true")).value | Select-Object -First 1
if(-not $view){ throw "No default public view for cap_entityrelationship — stop." }
Say "subgrid view: $($view.name) ($($view.savedqueryid))"

# --- main form for cap_entity -------------------------------------------------
$form = (Invoke-RestMethod -Headers $H -Uri ("$base/systemforms?`$select=formid,name,formxml" +
    "&`$filter=objecttypecode eq 'cap_entity' and type eq 2")).value | Select-Object -First 1
if(-not $form){ throw "No main form for cap_entity — stop." }
Say "form: $($form.name) ($($form.formid))"

if($form.formxml -like "*$TABID*"){
    Say "Relationships tab already present — form untouched." DarkGray
} else {
    function Cell($ctlId,$secGuid,$cellGuid,$relSchema,$label){
@"
<section showlabel="true" showbar="false" id="$secGuid" columns="1" labelwidth="115" celllabelalignment="Left" celllabelposition="Left">
  <labels><label description="$label" languagecode="1033" /></labels>
  <rows><row>
    <cell id="$cellGuid" rowspan="6" colspan="1" auto="false" showlabel="false">
      <labels><label description="$label" languagecode="1033" /></labels>
      <control id="$ctlId" classid="{E7A81278-8635-4D9E-8D4D-59480B391C5B}" indicationOfSubgrid="true">
        <parameters>
          <TargetEntityType>cap_entityrelationship</TargetEntityType>
          <RelationshipName>$relSchema</RelationshipName>
          <ViewId>{$($view.savedqueryid)}</ViewId>
          <EnableViewPicker>false</EnableViewPicker>
          <RecordsPerPage>10</RecordsPerPage>
          <AutoExpand>Fixed</AutoExpand>
        </parameters>
      </control>
    </cell>
  </row></rows>
</section>
"@ }
    $tabXml = @"
<tab name="tab_relationships" id="$TABID" IsUserDefined="1" showlabel="true" expanded="true" verticallayout="true">
  <labels><label description="Relationships" languagecode="1033" /></labels>
  <columns><column width="100%"><sections>
$(Cell 'sg_rel_subject' '{a3d1e9c0-31aa-4f33-9d13-0000c0ffee02}' '{a3d1e9c0-31aa-4f33-9d13-0000c0ffee03}' $relFrom.SchemaName 'This entity is ...')
$(Cell 'sg_rel_object' '{a3d1e9c0-31aa-4f33-9d13-0000c0ffee04}' '{a3d1e9c0-31aa-4f33-9d13-0000c0ffee05}' $relTo.SchemaName 'Others, to this entity ...')
  </sections></column></columns>
</tab>
"@
    $newXml = $form.formxml -replace '</tabs>', "$tabXml</tabs>"
    Say "Tab 'Relationships' with 2 stacked subgrids -> $(if($Apply){'WRITE'}else{'would write'})" Yellow
    if($Apply){
        Invoke-RestMethod -Headers $H -Method Patch -Uri "$base/systemforms($($form.formid))" `
            -Body (@{ formxml = $newXml } | ConvertTo-Json -Depth 4) -ContentType "application/json" | Out-Null
    }
}

# --- rename the associated-menu labels ---------------------------------------
foreach($r in @(@{rel=$relFrom;label='Relationships — as subject'},
                @{rel=$relTo;  label='Relationships — as object'})){
    Say "menu label $($r.rel.SchemaName) -> '$($r.label)' $(if($Apply){'(PUT)'}else{'(would PUT)'})" Yellow
    if($Apply){
        try{
            $md = Invoke-RestMethod -Headers $H -Uri "$base/RelationshipDefinitions(SchemaName='$($r.rel.SchemaName)')"
            $md.AssociatedMenuConfiguration = @{
                Behavior='UseLabel'; Group='Details'; Order=10000
                Label=@{ LocalizedLabels=@(@{Label=$r.label;LanguageCode=1033;IsManaged=$false}); LanguageCode=1033 } }
            $hdr = $H.Clone(); $hdr['MSCRM.MergeLabels']='true'; $hdr['Content-Type']='application/json'
            Invoke-RestMethod -Headers $hdr -Method Put -Uri "$base/RelationshipDefinitions(SchemaName='$($r.rel.SchemaName)')" `
                -Body ($md | ConvertTo-Json -Depth 12) | Out-Null
        } catch { Say "  label rename failed (cosmetic — tab still works): $($_.Exception.Message)" Red }
    }
}

if($Apply){
    Say "PublishAllXml ..." Cyan
    Invoke-RestMethod -Headers $H -Method Post -Uri "$base/PublishAllXml" -ContentType "application/json" -Body "{}" | Out-Null
    Say "Done. F5 the app; open any entity -> Relationships tab." Green
} else { Say "`nPreview only. Re-run with -Apply." Green }

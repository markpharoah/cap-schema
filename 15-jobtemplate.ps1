# 15-jobtemplate.ps1 — cap_jobtemplate + cap_tasktemplate + year-end seed (SCHEMA+DATA)
#
# DOCTRINE: templates are the FIRM spine; per-job free-form tasks are the
# agility. Template tasks carry calibrated weights (stages are not equal),
# pre-set courts, visibility defaults, milestone flags and DEFAULT percent
# anchors (amounts vary per customer; proportions travel). Stamping a job
# from a template copies rows cap_tasktemplate -> cap_task (the stamp
# function is app-layer, later; schema first).
#
# YEAR-END TEMPLATE (CAP stages a-e per mission, weights sum to 100):
#   1 Assess source data . Receive source data (Cust,5) / Review for
#     abnormalities (Prac,10)
#   2 Customer queries ... Raise & track queries (Prac,5) / Respond to
#     queries (Cust,5)
#   3 Accept data ........ Accept with workpapers (Prac,10) [MILESTONE
#     "Source data accepted"]
#   4 Process CAP ........ Process CAP (Prac,40) / Internal review
#     (Prac,10,HIDDEN - the weighted+hidden combo)
#   5 Approve ............ Draft accounts to customer (Prac,5) [MILESTONE
#     "Draft accounts to you", anchor 50%] / Customer approval (Cust,5)
#   6 Publish & lodge .... Lodge via LodgeIT (Prac,3) / Signed documents
#     returned (Cust,1) / Publish final package (Prac,1) [MILESTONE
#     "Completed", anchor 100%]
#
# RERUN-SAFE: table/attr/relationship existence checks; seed keyed on
# template name + task name. 0x80041102 = cache lag, wait, rerun.

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

function Test-Table($logical) {
    try { Invoke-RestMethod -Uri "$api/EntityDefinitions(LogicalName='$logical')?`$select=LogicalName" -Headers $headers -Method Get | Out-Null; $true }
    catch { $false }
}
function Test-Attr($table, $logical) {
    try { Invoke-RestMethod -Uri "$api/EntityDefinitions(LogicalName='$table')/Attributes(LogicalName='$logical')?`$select=LogicalName" -Headers $headers -Method Get | Out-Null; $true }
    catch { $false }
}
function Label($text) {
    @{ LocalizedLabels = @(@{ Label = $text; LanguageCode = 1033 }) }
}

$court = Invoke-RestMethod -Uri "$api/GlobalOptionSetDefinitions(Name='cap_courttype')" -Headers $headers -Method Get
$courtBind = "/GlobalOptionSetDefinitions($($court.MetadataId))"

# --- 1) cap_jobtemplate -------------------------------------------------------------
if (Test-Table "cap_jobtemplate") {
    Write-Host "cap_jobtemplate already exists - skip." -ForegroundColor Yellow
} else {
    $body = @{
        "@odata.type"          = "Microsoft.Dynamics.CRM.EntityMetadata"
        SchemaName             = "cap_JobTemplate"
        DisplayName            = Label "Job Template"
        DisplayCollectionName  = Label "Job Templates"
        Description            = Label "The firm spine for a job type. Stamping a job copies its task templates."
        OwnershipType          = "UserOwned"
        HasActivities          = $false
        HasNotes               = $true
        Attributes             = @(
            @{
                "@odata.type" = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
                SchemaName    = "cap_Name"
                DisplayName   = Label "Template Name"
                IsPrimaryName = $true
                MaxLength     = 250
                RequiredLevel = @{ Value = "ApplicationRequired" }
            }
        )
    }
    Invoke-RestMethod -Uri "$api/EntityDefinitions" -Headers $headers -Method Post -Body ($body | ConvertTo-Json -Depth 12) | Out-Null
    Write-Host "cap_jobtemplate created." -ForegroundColor Green
}
if (-not (Test-Attr "cap_jobtemplate" "cap_description")) {
    $c = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.MemoAttributeMetadata"
        SchemaName    = "cap_Description"
        DisplayName   = Label "Description"
        MaxLength     = 10000
        RequiredLevel = @{ Value = "None" }
    }
    Invoke-RestMethod -Uri "$api/EntityDefinitions(LogicalName='cap_jobtemplate')/Attributes" -Headers $headers -Method Post -Body ($c | ConvertTo-Json -Depth 12) | Out-Null
    Write-Host "  cap_description created." -ForegroundColor Green
} else { Write-Host "  cap_description already exists - skip." -ForegroundColor Yellow }

# --- 2) cap_tasktemplate (mirrors cap_task minus job-instance fields) ---------------
if (Test-Table "cap_tasktemplate") {
    Write-Host "cap_tasktemplate already exists - skip." -ForegroundColor Yellow
} else {
    $body = @{
        "@odata.type"          = "Microsoft.Dynamics.CRM.EntityMetadata"
        SchemaName             = "cap_TaskTemplate"
        DisplayName            = Label "Task Template"
        DisplayCollectionName  = Label "Task Templates"
        Description            = Label "One step in a job template. Copied to cap_task when a job is stamped."
        OwnershipType          = "UserOwned"
        HasActivities          = $false
        HasNotes               = $true
        Attributes             = @(
            @{
                "@odata.type" = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
                SchemaName    = "cap_Name"
                DisplayName   = Label "Task Name"
                IsPrimaryName = $true
                MaxLength     = 250
                RequiredLevel = @{ Value = "ApplicationRequired" }
            }
        )
    }
    Invoke-RestMethod -Uri "$api/EntityDefinitions" -Headers $headers -Method Post -Body ($body | ConvertTo-Json -Depth 12) | Out-Null
    Write-Host "cap_tasktemplate created." -ForegroundColor Green
}

$ttCols = @(
    @{ "@odata.type"="Microsoft.Dynamics.CRM.IntegerAttributeMetadata"; SchemaName="cap_Weight";        DisplayName=Label "Weight";         MinValue=0; MaxValue=1000; RequiredLevel=@{Value="ApplicationRequired"} },
    @{ "@odata.type"="Microsoft.Dynamics.CRM.IntegerAttributeMetadata"; SchemaName="cap_StageSequence"; DisplayName=Label "Stage Sequence"; MinValue=0; MaxValue=1000; RequiredLevel=@{Value="ApplicationRequired"} },
    @{ "@odata.type"="Microsoft.Dynamics.CRM.StringAttributeMetadata";  SchemaName="cap_StageName";     DisplayName=Label "Stage Name";     MaxLength=100; RequiredLevel=@{Value="ApplicationRequired"} },
    @{ "@odata.type"="Microsoft.Dynamics.CRM.PicklistAttributeMetadata"; SchemaName="cap_Court";        DisplayName=Label "Court";          RequiredLevel=@{Value="ApplicationRequired"}; "GlobalOptionSet@odata.bind"=$courtBind },
    @{ "@odata.type"="Microsoft.Dynamics.CRM.BooleanAttributeMetadata"; SchemaName="cap_ShowCustomer";  DisplayName=Label "Show Customer";  OptionSet=@{ "@odata.type"="Microsoft.Dynamics.CRM.BooleanOptionSetMetadata"; TrueOption=@{Value=1;Label=Label "Show"}; FalseOption=@{Value=0;Label=Label "Hide"} }; RequiredLevel=@{Value="ApplicationRequired"} },
    @{ "@odata.type"="Microsoft.Dynamics.CRM.BooleanAttributeMetadata"; SchemaName="cap_IsMilestone";   DisplayName=Label "Is Milestone";   OptionSet=@{ "@odata.type"="Microsoft.Dynamics.CRM.BooleanOptionSetMetadata"; TrueOption=@{Value=1;Label=Label "Milestone"}; FalseOption=@{Value=0;Label=Label "Task"} }; RequiredLevel=@{Value="ApplicationRequired"} },
    @{ "@odata.type"="Microsoft.Dynamics.CRM.StringAttributeMetadata";  SchemaName="cap_MilestoneName"; DisplayName=Label "Milestone Name"; MaxLength=250; RequiredLevel=@{Value="None"} },
    @{ "@odata.type"="Microsoft.Dynamics.CRM.MoneyAttributeMetadata";   SchemaName="cap_BillingAnchorAmount";  DisplayName=Label "Billing Anchor Amount";  RequiredLevel=@{Value="None"} },
    @{ "@odata.type"="Microsoft.Dynamics.CRM.DecimalAttributeMetadata"; SchemaName="cap_BillingAnchorPercent"; DisplayName=Label "Billing Anchor Percent"; MinValue=0; MaxValue=100; Precision=2; RequiredLevel=@{Value="None"} }
)
foreach ($c in $ttCols) {
    $logical = $c.SchemaName.ToLower()
    if (Test-Attr "cap_tasktemplate" $logical) {
        Write-Host "  $logical already exists - skip." -ForegroundColor Yellow
    } else {
        Invoke-RestMethod -Uri "$api/EntityDefinitions(LogicalName='cap_tasktemplate')/Attributes" -Headers $headers -Method Post -Body ($c | ConvertTo-Json -Depth 12) | Out-Null
        Write-Host "  $logical created." -ForegroundColor Green
    }
}

# --- 3) Lookups: tasktemplate->jobtemplate, job->jobtemplate ------------------------
$rels = @(
    @{ Schema="cap_jobtemplate_cap_tasktemplate_Template"; Referenced="cap_jobtemplate"; Referencing="cap_tasktemplate"; LookupSchema="cap_JobTemplateId"; LookupLabel="Job Template"; Req="ApplicationRequired" },
    @{ Schema="cap_jobtemplate_cap_job_Template";          Referenced="cap_jobtemplate"; Referencing="cap_job";          LookupSchema="cap_JobTemplateId"; LookupLabel="Job Template"; Req="None" }
)
foreach ($r in $rels) {
    $lookupLogical = $r.LookupSchema.ToLower()
    if (Test-Attr $r.Referencing $lookupLogical) {
        Write-Host "  $($r.Referencing).$lookupLogical already exists - skip." -ForegroundColor Yellow
        continue
    }
    $body = @{
        "@odata.type"      = "Microsoft.Dynamics.CRM.OneToManyRelationshipMetadata"
        SchemaName         = $r.Schema
        ReferencedEntity   = $r.Referenced
        ReferencingEntity  = $r.Referencing
        Lookup             = @{
            "@odata.type" = "Microsoft.Dynamics.CRM.LookupAttributeMetadata"
            SchemaName    = $r.LookupSchema
            DisplayName   = Label $r.LookupLabel
            RequiredLevel = @{ Value = $r.Req }
        }
    }
    Invoke-RestMethod -Uri "$api/RelationshipDefinitions" -Headers $headers -Method Post -Body ($body | ConvertTo-Json -Depth 12) | Out-Null
    Write-Host "  $($r.Referencing).$lookupLogical created." -ForegroundColor Green
}

# --- 4) SEED: Annual Accounting - Year End ------------------------------------------
$tplName = "Annual Accounting - Year End"
$hit = (Invoke-RestMethod -Uri "$api/cap_jobtemplates?`$select=cap_jobtemplateid&`$filter=cap_name eq '$tplName'" -Headers $headers -Method Get).value
if ($hit.Count -gt 0) {
    $tplId = $hit[0].cap_jobtemplateid
    Write-Host "Template '$tplName' already exists - reusing." -ForegroundColor Yellow
} else {
    $body = @{ cap_name = $tplName; cap_description = "CAP standard year-end. Stages a-e per mission. Weights sum to 100. Anchors: 50% draft, 100% completed (defaults; override per job)." }
    Invoke-RestMethod -Uri "$api/cap_jobtemplates" -Headers $headers -Method Post -Body ($body | ConvertTo-Json) | Out-Null
    $tplId = ((Invoke-RestMethod -Uri "$api/cap_jobtemplates?`$select=cap_jobtemplateid&`$filter=cap_name eq '$tplName'" -Headers $headers -Method Get).value)[0].cap_jobtemplateid
    Write-Host "Template '$tplName' created." -ForegroundColor Green
}

$P = 764820000; $C = 764820001   # court values
$tasks = @(
    @{ n="Receive source data";           st=1; sn="Assess source data"; w=5;  court=$C; show=$true;  ms=$false },
    @{ n="Review for abnormalities";      st=1; sn="Assess source data"; w=10; court=$P; show=$true;  ms=$false },
    @{ n="Raise and track queries";       st=2; sn="Customer queries";   w=5;  court=$P; show=$true;  ms=$false },
    @{ n="Respond to queries";            st=2; sn="Customer queries";   w=5;  court=$C; show=$true;  ms=$false },
    @{ n="Accept data with workpapers";   st=3; sn="Accept data";        w=10; court=$P; show=$true;  ms=$true;  msn="Source data accepted" },
    @{ n="Process CAP";                   st=4; sn="Process CAP";        w=40; court=$P; show=$true;  ms=$false },
    @{ n="Internal review";               st=4; sn="Process CAP";        w=10; court=$P; show=$false; ms=$false },
    @{ n="Draft accounts to customer";    st=5; sn="Approve";            w=5;  court=$P; show=$true;  ms=$true;  msn="Draft accounts to you"; pct=50 },
    @{ n="Customer approval";             st=5; sn="Approve";            w=5;  court=$C; show=$true;  ms=$false },
    @{ n="Lodge via LodgeIT";             st=6; sn="Publish and lodge";  w=3;  court=$P; show=$true;  ms=$false },
    @{ n="Signed documents returned";     st=6; sn="Publish and lodge";  w=1;  court=$C; show=$true;  ms=$false },
    @{ n="Publish final package";         st=6; sn="Publish and lodge";  w=1;  court=$P; show=$true;  ms=$true;  msn="Completed"; pct=100 }
)
$existing = (Invoke-RestMethod -Uri "$api/cap_tasktemplates?`$select=cap_name&`$filter=_cap_jobtemplateid_value eq $tplId" -Headers $headers -Method Get).value | ForEach-Object { $_.cap_name }
$seeded = 0
foreach ($t in $tasks) {
    if ($existing -contains $t.n) { Write-Host "  '$($t.n)' already seeded - skip." -ForegroundColor Yellow; continue }
    $body = @{
        cap_name          = $t.n
        cap_weight        = $t.w
        cap_stagesequence = $t.st
        cap_stagename     = $t.sn
        cap_court         = $t.court
        cap_showcustomer  = $t.show
        cap_ismilestone   = $t.ms
        "cap_JobTemplateId@odata.bind" = "/cap_jobtemplates($tplId)"
    }
    if ($t.ms) { $body.cap_milestonename = $t.msn }
    if ($t.ContainsKey("pct")) { $body.cap_billinganchorpercent = $t.pct }
    Invoke-RestMethod -Uri "$api/cap_tasktemplates" -Headers $headers -Method Post -Body ($body | ConvertTo-Json) | Out-Null
    Write-Host "  '$($t.n)' seeded (stage $($t.st), w$($t.w))." -ForegroundColor Green
    $seeded++
}
Write-Host "Seeded: $seeded" -ForegroundColor Green

# --- VERIFY --------------------------------------------------------------------------
$rows = (Invoke-RestMethod -Uri "$api/cap_tasktemplates?`$select=cap_name,cap_weight,cap_stagesequence&`$filter=_cap_jobtemplateid_value eq $tplId" -Headers $headers -Method Get).value
$wsum = ($rows | Measure-Object cap_weight -Sum).Sum
Write-Host "`nTemplate '$tplName': $($rows.Count) tasks, weights sum $wsum." -ForegroundColor Cyan
if ($rows.Count -ne 12 -or $wsum -ne 100) { Write-Host "EXPECTED 12 tasks / weight 100." -ForegroundColor Red; exit 1 }
Write-Host "12 tasks, weight 100 - correct." -ForegroundColor Green
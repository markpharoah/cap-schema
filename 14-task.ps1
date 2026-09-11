# 14-task.ps1 — cap_task: the load-bearing step + cap_courttype choice (SCHEMA)
#
# DOCTRINE (Jobs Spine record):
#   Weight: whole number, default 1; 0 = doesn't move the %.
#   Court: whose court is it in - Practice/Customer/Third party (global
#     choice cap_courttype, pinned). Scorecard/eligibility derive from this.
#   ShowCustomer: portal visibility. Weight x Show = 4 meaningful combos
#     (weighted+hidden = real work customer shouldn't watch; 0+hidden =
#     note-to-self; 0+shown = FYI/milestone marker).
#   Stage: cap_stagesequence (int) + cap_stagename (string) stamped from
#     template - NO stage table. Earliest-incomplete = MIN(seq) incomplete.
#   Milestone: flag + customer-visible name + billing anchor (amount OR
#     percent-of-budget; at-most-one enforced at app layer, schema dumb).
#   Completion: built-in statecode (platform dates it). Due date optional.
#   Lookup: cap_jobid required. Template lookup arrives with 15.
#
# LESSON (0x80048403, six identical hits): a nested GlobalOptionSet object on
#   the attribute-create endpoint reads as "create a NEW option set inline",
#   which is only allowed for Local. Binding to an EXISTING global choice
#   uses "GlobalOptionSet@odata.bind" -> /GlobalOptionSetDefinitions(MetadataId).
#   Deterministic error, not cache lag - same input, same wall, every pass.
#
# RERUN-SAFE throughout; 0x80041102 = cache lag, wait a minute, rerun.

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
function Test-Choice($name) {
    try { Invoke-RestMethod -Uri "$api/GlobalOptionSetDefinitions(Name='$name')" -Headers $headers -Method Get | Out-Null; $true }
    catch { $false }
}
function Label($text) {
    @{ LocalizedLabels = @(@{ Label = $text; LanguageCode = 1033 }) }
}

# --- 1) cap_courttype global choice (pinned) --------------------------------------
if (Test-Choice "cap_courttype") {
    Write-Host "cap_courttype already exists - skip." -ForegroundColor Yellow
} else {
    $body = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.OptionSetMetadata"
        Name          = "cap_courttype"
        DisplayName   = Label "Court Type"
        Description   = Label "Whose court a task is in. Scorecard and waiting-rule eligibility derive from this."
        IsGlobal      = $true
        OptionSetType = "Picklist"
        Options       = @(
            @{ Value = 764820000; Label = Label "Practice" },
            @{ Value = 764820001; Label = Label "Customer" },
            @{ Value = 764820002; Label = Label "Third party" }
        )
    }
    Invoke-RestMethod -Uri "$api/GlobalOptionSetDefinitions" -Headers $headers -Method Post -Body ($body | ConvertTo-Json -Depth 12) | Out-Null
    Write-Host "cap_courttype created (764820000 Practice / ...001 Customer / ...002 Third party)." -ForegroundColor Green
}

# --- 2) Resolve the choice's MetadataId (the bind target) -------------------------
$court = Invoke-RestMethod -Uri "$api/GlobalOptionSetDefinitions(Name='cap_courttype')" -Headers $headers -Method Get
Write-Host "cap_courttype MetadataId: $($court.MetadataId)" -ForegroundColor Cyan

# --- 3) The table ------------------------------------------------------------------
if (Test-Table "cap_task") {
    Write-Host "cap_task already exists - skipping table create." -ForegroundColor Yellow
} else {
    $body = @{
        "@odata.type"          = "Microsoft.Dynamics.CRM.EntityMetadata"
        SchemaName             = "cap_Task"
        DisplayName            = Label "Task"
        DisplayCollectionName  = Label "Tasks"
        Description            = Label "A step within a job. Weight drives the derived percent; court drives the scorecard; showcustomer drives the portal."
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
    Write-Host "cap_task created." -ForegroundColor Green
}

# --- 4) Scalar columns --------------------------------------------------------------
$cols = @(
    @{
        "@odata.type" = "Microsoft.Dynamics.CRM.IntegerAttributeMetadata"
        SchemaName    = "cap_Weight"
        DisplayName   = Label "Weight"
        Description   = Label "Contribution to job percent. Default 1; 0 = does not move the number."
        MinValue      = 0
        MaxValue      = 1000
        RequiredLevel = @{ Value = "ApplicationRequired" }
    },
    @{
        "@odata.type" = "Microsoft.Dynamics.CRM.IntegerAttributeMetadata"
        SchemaName    = "cap_StageSequence"
        DisplayName   = Label "Stage Sequence"
        Description   = Label "Ordering of the stage this task belongs to. Job stage = earliest incomplete."
        MinValue      = 0
        MaxValue      = 1000
        RequiredLevel = @{ Value = "ApplicationRequired" }
    },
    @{
        "@odata.type" = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
        SchemaName    = "cap_StageName"
        DisplayName   = Label "Stage Name"
        Description   = Label "Stage label, stamped from template. Per-job-type vocabulary, no stage table."
        MaxLength     = 100
        RequiredLevel = @{ Value = "ApplicationRequired" }
    },
    @{
        "@odata.type" = "Microsoft.Dynamics.CRM.PicklistAttributeMetadata"
        SchemaName    = "cap_Court"
        DisplayName   = Label "Court"
        Description   = Label "Whose court this task is in."
        RequiredLevel = @{ Value = "ApplicationRequired" }
        "GlobalOptionSet@odata.bind" = "/GlobalOptionSetDefinitions($($court.MetadataId))"
    },
    @{
        "@odata.type" = "Microsoft.Dynamics.CRM.BooleanAttributeMetadata"
        SchemaName    = "cap_ShowCustomer"
        DisplayName   = Label "Show Customer"
        Description   = Label "Renders on the portal. Hidden customer-court tasks never reach the scorecard."
        OptionSet     = @{
            "@odata.type" = "Microsoft.Dynamics.CRM.BooleanOptionSetMetadata"
            TrueOption  = @{ Value = 1; Label = Label "Show" }
            FalseOption = @{ Value = 0; Label = Label "Hide" }
        }
        RequiredLevel = @{ Value = "ApplicationRequired" }
    },
    @{
        "@odata.type" = "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata"
        SchemaName    = "cap_DueDate"
        DisplayName   = Label "Due Date"
        Description   = Label "Optional. Feeds the future manager-notification overlay; no automation fires at the customer."
        Format        = "DateOnly"
        RequiredLevel = @{ Value = "None" }
    },
    @{
        "@odata.type" = "Microsoft.Dynamics.CRM.BooleanAttributeMetadata"
        SchemaName    = "cap_IsMilestone"
        DisplayName   = Label "Is Milestone"
        Description   = Label "Customer-visible marker; completing one may create a billing entitlement."
        OptionSet     = @{
            "@odata.type" = "Microsoft.Dynamics.CRM.BooleanOptionSetMetadata"
            TrueOption  = @{ Value = 1; Label = Label "Milestone" }
            FalseOption = @{ Value = 0; Label = Label "Task" }
        }
        RequiredLevel = @{ Value = "ApplicationRequired" }
    },
    @{
        "@odata.type" = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
        SchemaName    = "cap_MilestoneName"
        DisplayName   = Label "Milestone Name"
        Description   = Label "Customer-facing name shown on the portal (e.g. 'Draft accounts to you')."
        MaxLength     = 250
        RequiredLevel = @{ Value = "None" }
    },
    @{
        "@odata.type" = "Microsoft.Dynamics.CRM.MoneyAttributeMetadata"
        SchemaName    = "cap_BillingAnchorAmount"
        DisplayName   = Label "Billing Anchor Amount"
        Description   = Label "CHARGE-side amount billable at this milestone. At most one of amount/percent (app-enforced)."
        RequiredLevel = @{ Value = "None" }
    },
    @{
        "@odata.type" = "Microsoft.Dynamics.CRM.DecimalAttributeMetadata"
        SchemaName    = "cap_BillingAnchorPercent"
        DisplayName   = Label "Billing Anchor Percent"
        Description   = Label "Percent-of-budget billable at this milestone. At most one of amount/percent (app-enforced)."
        MinValue      = 0
        MaxValue      = 100
        Precision     = 2
        RequiredLevel = @{ Value = "None" }
    }
)
foreach ($c in $cols) {
    $logical = $c.SchemaName.ToLower()
    if (Test-Attr "cap_task" $logical) {
        Write-Host "  $logical already exists - skip." -ForegroundColor Yellow
    } else {
        Invoke-RestMethod -Uri "$api/EntityDefinitions(LogicalName='cap_task')/Attributes" -Headers $headers -Method Post -Body ($c | ConvertTo-Json -Depth 12) | Out-Null
        Write-Host "  $logical created." -ForegroundColor Green
    }
}

# --- 5) Lookup: job -----------------------------------------------------------------
if (Test-Attr "cap_task" "cap_jobid") {
    Write-Host "  cap_jobid already exists - skip." -ForegroundColor Yellow
} else {
    $body = @{
        "@odata.type"      = "Microsoft.Dynamics.CRM.OneToManyRelationshipMetadata"
        SchemaName         = "cap_job_cap_task_Job"
        ReferencedEntity   = "cap_job"
        ReferencingEntity  = "cap_task"
        Lookup             = @{
            "@odata.type" = "Microsoft.Dynamics.CRM.LookupAttributeMetadata"
            SchemaName    = "cap_JobId"
            DisplayName   = Label "Job"
            Description   = Label "The job this task belongs to. Required."
            RequiredLevel = @{ Value = "ApplicationRequired" }
        }
    }
    Invoke-RestMethod -Uri "$api/RelationshipDefinitions" -Headers $headers -Method Post -Body ($body | ConvertTo-Json -Depth 12) | Out-Null
    Write-Host "  cap_jobid created." -ForegroundColor Green
}

# --- VERIFY --------------------------------------------------------------------------
$attrs = (Invoke-RestMethod -Uri "$api/EntityDefinitions(LogicalName='cap_task')/Attributes?`$select=LogicalName,AttributeType" -Headers $headers -Method Get).value
Write-Host "`ncap_task cap_* columns:" -ForegroundColor Cyan
$attrs | Where-Object { $_.LogicalName -like "cap_*" } | Sort-Object LogicalName | ForEach-Object {
    Write-Host ("  {0}  [{1}]" -f $_.LogicalName, $_.AttributeType)
}
$need = @("cap_name","cap_weight","cap_stagesequence","cap_stagename","cap_court","cap_showcustomer",
          "cap_duedate","cap_ismilestone","cap_milestonename","cap_billinganchoramount",
          "cap_billinganchorpercent","cap_jobid")
$have = ($attrs | ForEach-Object { $_.LogicalName })
$missing = $need | Where-Object { $_ -notin $have }
if ($missing) { Write-Host "MISSING: $($missing -join ', ')" -ForegroundColor Red; exit 1 }
Write-Host "All 12 expected columns present." -ForegroundColor Green
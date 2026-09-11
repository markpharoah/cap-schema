# 16-time-budget.ps1 — cap_timeentry + cap_budgetline: the WIP grain (SCHEMA)
#
# DOCTRINE: budget MIRRORS actual - same grain both sides: hours + cost
# rate + charge rate. Time entries: day grain (ledger doctrine), task-
# anchored, chargeable flag; OWNER IS THE PERSON whose time it is (KISS,
# same as ownerid-is-manager on cap_job). Budget lines: task lookup (fine)
# OR job lookup (coarse) - at-least-one app-enforced, schema dumb.
# Time at charge rates minus invoiced = WIP; invoicing reads this later.
# COST-SIDE FIELDS NEVER RENDER PORTAL-SIDE (money wall - structural).
#
# RERUN-SAFE; cache lag rules: 0x80041102 or "undeclared property" on a
# just-created nav property = wait, rerun.

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
function New-CapTable($schemaName, $display, $plural, $desc) {
    $logical = $schemaName.ToLower()
    if (Test-Table $logical) {
        Write-Host "$logical already exists - skip." -ForegroundColor Yellow
        return
    }
    $body = @{
        "@odata.type"          = "Microsoft.Dynamics.CRM.EntityMetadata"
        SchemaName             = $schemaName
        DisplayName            = Label $display
        DisplayCollectionName  = Label $plural
        Description            = Label $desc
        OwnershipType          = "UserOwned"
        HasActivities          = $false
        HasNotes               = $true
        Attributes             = @(
            @{
                "@odata.type" = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
                SchemaName    = "cap_Name"
                DisplayName   = Label "Name"
                IsPrimaryName = $true
                MaxLength     = 250
                RequiredLevel = @{ Value = "ApplicationRequired" }
            }
        )
    }
    Invoke-RestMethod -Uri "$api/EntityDefinitions" -Headers $headers -Method Post -Body ($body | ConvertTo-Json -Depth 12) | Out-Null
    Write-Host "$logical created." -ForegroundColor Green
}
function Add-CapColumn($table, $col) {
    $logical = $col.SchemaName.ToLower()
    if (Test-Attr $table $logical) {
        Write-Host "  $table.$logical already exists - skip." -ForegroundColor Yellow
    } else {
        Invoke-RestMethod -Uri "$api/EntityDefinitions(LogicalName='$table')/Attributes" -Headers $headers -Method Post -Body ($col | ConvertTo-Json -Depth 12) | Out-Null
        Write-Host "  $table.$logical created." -ForegroundColor Green
    }
}
function Add-CapLookup($schemaRel, $referenced, $referencing, $lookupSchema, $label, $req) {
    $logical = $lookupSchema.ToLower()
    if (Test-Attr $referencing $logical) {
        Write-Host "  $referencing.$logical already exists - skip." -ForegroundColor Yellow
        return
    }
    $body = @{
        "@odata.type"      = "Microsoft.Dynamics.CRM.OneToManyRelationshipMetadata"
        SchemaName         = $schemaRel
        ReferencedEntity   = $referenced
        ReferencingEntity  = $referencing
        Lookup             = @{
            "@odata.type" = "Microsoft.Dynamics.CRM.LookupAttributeMetadata"
            SchemaName    = $lookupSchema
            DisplayName   = Label $label
            RequiredLevel = @{ Value = $req }
        }
    }
    Invoke-RestMethod -Uri "$api/RelationshipDefinitions" -Headers $headers -Method Post -Body ($body | ConvertTo-Json -Depth 12) | Out-Null
    Write-Host "  $referencing.$logical created." -ForegroundColor Green
}

# --- 1) cap_timeentry ---------------------------------------------------------------
New-CapTable "cap_TimeEntry" "Time Entry" "Time Entries" "Day-grain time against a task. Owner is the person whose time it is. Charge minus invoiced = WIP."

Add-CapColumn "cap_timeentry" @{
    "@odata.type" = "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata"
    SchemaName    = "cap_Date"
    DisplayName   = Label "Date"
    Description   = Label "Day grain, per ledger doctrine."
    Format        = "DateOnly"
    RequiredLevel = @{ Value = "ApplicationRequired" }
}
Add-CapColumn "cap_timeentry" @{
    "@odata.type" = "Microsoft.Dynamics.CRM.DecimalAttributeMetadata"
    SchemaName    = "cap_Hours"
    DisplayName   = Label "Hours"
    MinValue      = 0
    MaxValue      = 24
    Precision     = 2
    RequiredLevel = @{ Value = "ApplicationRequired" }
}
Add-CapColumn "cap_timeentry" @{
    "@odata.type" = "Microsoft.Dynamics.CRM.MoneyAttributeMetadata"
    SchemaName    = "cap_CostRate"
    DisplayName   = Label "Cost Rate"
    Description   = Label "Per hour. NEVER portal-side (money wall)."
    RequiredLevel = @{ Value = "None" }
}
Add-CapColumn "cap_timeentry" @{
    "@odata.type" = "Microsoft.Dynamics.CRM.MoneyAttributeMetadata"
    SchemaName    = "cap_ChargeRate"
    DisplayName   = Label "Charge Rate"
    Description   = Label "Per hour. Charge side; drives WIP."
    RequiredLevel = @{ Value = "None" }
}
Add-CapColumn "cap_timeentry" @{
    "@odata.type" = "Microsoft.Dynamics.CRM.BooleanAttributeMetadata"
    SchemaName    = "cap_Chargeable"
    DisplayName   = Label "Chargeable"
    OptionSet     = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.BooleanOptionSetMetadata"
        TrueOption  = @{ Value = 1; Label = Label "Chargeable" }
        FalseOption = @{ Value = 0; Label = Label "Non-chargeable" }
    }
    RequiredLevel = @{ Value = "ApplicationRequired" }
}
Add-CapLookup "cap_task_cap_timeentry_Task" "cap_task" "cap_timeentry" "cap_TaskId" "Task" "ApplicationRequired"

# --- 2) cap_budgetline --------------------------------------------------------------
New-CapTable "cap_BudgetLine" "Budget Line" "Budget Lines" "Budget at the same grain as time: hours + cost rate + charge rate. Task lookup (fine) or job lookup (coarse); at-least-one app-enforced."

Add-CapColumn "cap_budgetline" @{
    "@odata.type" = "Microsoft.Dynamics.CRM.DecimalAttributeMetadata"
    SchemaName    = "cap_Hours"
    DisplayName   = Label "Hours"
    MinValue      = 0
    MaxValue      = 10000
    Precision     = 2
    RequiredLevel = @{ Value = "ApplicationRequired" }
}
Add-CapColumn "cap_budgetline" @{
    "@odata.type" = "Microsoft.Dynamics.CRM.MoneyAttributeMetadata"
    SchemaName    = "cap_CostRate"
    DisplayName   = Label "Cost Rate"
    Description   = Label "Per hour. NEVER portal-side (money wall)."
    RequiredLevel = @{ Value = "None" }
}
Add-CapColumn "cap_budgetline" @{
    "@odata.type" = "Microsoft.Dynamics.CRM.MoneyAttributeMetadata"
    SchemaName    = "cap_ChargeRate"
    DisplayName   = Label "Charge Rate"
    Description   = Label "Per hour. Charge side."
    RequiredLevel = @{ Value = "None" }
}
Add-CapLookup "cap_task_cap_budgetline_Task" "cap_task" "cap_budgetline" "cap_TaskId" "Task" "None"
Add-CapLookup "cap_job_cap_budgetline_Job"   "cap_job"  "cap_budgetline" "cap_JobId"  "Job"  "None"

# --- VERIFY --------------------------------------------------------------------------
foreach ($t in @(
    @{ tbl="cap_timeentry";  need=@("cap_name","cap_date","cap_hours","cap_costrate","cap_chargerate","cap_chargeable","cap_taskid") },
    @{ tbl="cap_budgetline"; need=@("cap_name","cap_hours","cap_costrate","cap_chargerate","cap_taskid","cap_jobid") }
)) {
    $attrs = (Invoke-RestMethod -Uri "$api/EntityDefinitions(LogicalName='$($t.tbl)')/Attributes?`$select=LogicalName" -Headers $headers -Method Get).value | ForEach-Object { $_.LogicalName }
    $missing = $t.need | Where-Object { $_ -notin $attrs }
    if ($missing) { Write-Host "$($t.tbl) MISSING: $($missing -join ', ')" -ForegroundColor Red; exit 1 }
    Write-Host "$($t.tbl): all $($t.need.Count) expected columns present." -ForegroundColor Green
}
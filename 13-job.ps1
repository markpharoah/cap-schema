# 13-job.ps1 — cap_job: one deliverable instance under an engagement (SCHEMA)
#
# DOCTRINE (Jobs Spine record, 11 Sep): Engagement = promise, Job = instance,
# Task = step. The job is deliberately THIN:
#   - NO stage column (stage = earliest-incomplete, derived from tasks)
#   - NO percent column (derived from weighted tasks; never stored-editable)
#   - NO manager column (user-owned table: built-in ownerid IS the manager -
#     assignment, views, security for free)
#   - Period optional (ad-hoc jobs have none): cap_periodstart/cap_periodend
#   - Template lookup added in 15-jobtemplate.ps1 (table must exist first)
#   - Deemed-billing action columns deferred to the billing consumer
# Lookups: cap_entityid (required end), cap_engagementid (the promise).
# statecode/statuscode built-ins carry Open/Closed lifecycle, dated by platform.
#
# RERUN-SAFE: existence checks on table, each attribute, each relationship.
# 0x80041102 after create = metadata cache lag: wait a minute, rerun.

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

# --- 1) The table (with primary name column) ------------------------------------
if (Test-Table "cap_job") {
    Write-Host "cap_job already exists - skipping table create." -ForegroundColor Yellow
} else {
    $body = @{
        "@odata.type"          = "Microsoft.Dynamics.CRM.EntityMetadata"
        SchemaName             = "cap_Job"
        DisplayName            = Label "Job"
        DisplayCollectionName  = Label "Jobs"
        Description            = Label "One deliverable instance under an engagement. Stage and percent derive from tasks; owner is the manager."
        OwnershipType          = "UserOwned"
        HasActivities          = $false
        HasNotes               = $true
        Attributes             = @(
            @{
                "@odata.type" = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
                SchemaName    = "cap_Name"
                DisplayName   = Label "Job Name"
                IsPrimaryName = $true
                MaxLength     = 250
                RequiredLevel = @{ Value = "ApplicationRequired" }
            }
        )
    }
    Invoke-RestMethod -Uri "$api/EntityDefinitions" -Headers $headers -Method Post -Body ($body | ConvertTo-Json -Depth 12) | Out-Null
    Write-Host "cap_job created." -ForegroundColor Green
}

# --- 2) Scalar columns ------------------------------------------------------------
$cols = @(
    @{
        "@odata.type" = "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata"
        SchemaName    = "cap_PeriodStart"
        DisplayName   = Label "Period Start"
        Description   = Label "Optional. Blank for ad-hoc jobs."
        Format        = "DateOnly"
        RequiredLevel = @{ Value = "None" }
    },
    @{
        "@odata.type" = "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata"
        SchemaName    = "cap_PeriodEnd"
        DisplayName   = Label "Period End"
        Description   = Label "Optional. Blank for ad-hoc jobs."
        Format        = "DateOnly"
        RequiredLevel = @{ Value = "None" }
    },
    @{
        "@odata.type" = "Microsoft.Dynamics.CRM.MemoAttributeMetadata"
        SchemaName    = "cap_Description"
        DisplayName   = Label "Description"
        Description   = Label "Scope notes. For once-off jobs the template is the scope; write extensions here."
        MaxLength     = 10000
        RequiredLevel = @{ Value = "None" }
    }
)
foreach ($c in $cols) {
    $logical = $c.SchemaName.ToLower()
    if (Test-Attr "cap_job" $logical) {
        Write-Host "  $logical already exists - skip." -ForegroundColor Yellow
    } else {
        Invoke-RestMethod -Uri "$api/EntityDefinitions(LogicalName='cap_job')/Attributes" -Headers $headers -Method Post -Body ($c | ConvertTo-Json -Depth 12) | Out-Null
        Write-Host "  $logical created." -ForegroundColor Green
    }
}

# --- 3) Lookups (OneToMany POSTs; lookup nested) ----------------------------------
$rels = @(
    @{
        SchemaName        = "cap_entity_cap_job_Entity"
        ReferencedEntity  = "cap_entity"
        LookupSchema      = "cap_EntityId"
        LookupLabel       = "Entity"
        LookupDesc        = "The customer entity this job is for. Required."
        Required          = "ApplicationRequired"
    },
    @{
        SchemaName        = "cap_engagement_cap_job_Engagement"
        ReferencedEntity  = "cap_engagement"
        LookupSchema      = "cap_EngagementId"
        LookupLabel       = "Engagement"
        LookupDesc        = "The standing promise this job is an instance of."
        Required          = "None"
    }
)
foreach ($r in $rels) {
    $lookupLogical = $r.LookupSchema.ToLower()
    if (Test-Attr "cap_job" $lookupLogical) {
        Write-Host "  $lookupLogical already exists - skip." -ForegroundColor Yellow
        continue
    }
    $body = @{
        "@odata.type"      = "Microsoft.Dynamics.CRM.OneToManyRelationshipMetadata"
        SchemaName         = $r.SchemaName
        ReferencedEntity   = $r.ReferencedEntity
        ReferencingEntity  = "cap_job"
        Lookup             = @{
            "@odata.type" = "Microsoft.Dynamics.CRM.LookupAttributeMetadata"
            SchemaName    = $r.LookupSchema
            DisplayName   = Label $r.LookupLabel
            Description   = Label $r.LookupDesc
            RequiredLevel = @{ Value = $r.Required }
        }
    }
    Invoke-RestMethod -Uri "$api/RelationshipDefinitions" -Headers $headers -Method Post -Body ($body | ConvertTo-Json -Depth 12) | Out-Null
    Write-Host "  $lookupLogical created." -ForegroundColor Green
}

# --- VERIFY from metadata ----------------------------------------------------------
$attrs = (Invoke-RestMethod -Uri "$api/EntityDefinitions(LogicalName='cap_job')/Attributes?`$select=LogicalName,AttributeType" -Headers $headers -Method Get).value
Write-Host "`ncap_job cap_* columns:" -ForegroundColor Cyan
$attrs | Where-Object { $_.LogicalName -like "cap_*" } | Sort-Object LogicalName | ForEach-Object {
    Write-Host ("  {0}  [{1}]" -f $_.LogicalName, $_.AttributeType)
}
$need = @("cap_name","cap_periodstart","cap_periodend","cap_description","cap_entityid","cap_engagementid")
$have = ($attrs | ForEach-Object { $_.LogicalName })
$missing = $need | Where-Object { $_ -notin $have }
if ($missing) { Write-Host "MISSING: $($missing -join ', ')" -ForegroundColor Red; exit 1 }
Write-Host "All 6 expected columns present." -ForegroundColor Green
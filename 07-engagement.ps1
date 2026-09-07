# 07-engagement.ps1 — cap_engagement: the practice's promise ledger
#
# DESIGN (ratified this session):
#   - An engagement = what we were engaged to do, from when, to when, open = null end.
#   - cap_engagementtype: ONE rich descriptive list (what we're doing). SMSF Audit
#     is a type here — the old "work type" axis is derivable, column deleted (KISS).
#   - cap_regulatorycapacity: which regulatory hat the engagement engages (whose
#     rulebook applies). SINGLE choice, not multi-select: capacities combine at
#     practice level as MULTIPLE CONCURRENT ROWS, one capacity per promise.
#     A customer can sack us as ASIC agent and keep us as tax agent.
#   - Auditor independence (auditor row excludes all other open rows for the same
#     entity) is a cross-row temporal constraint — deferred-rules list, not schema.
#   - Classification flags fine, temporal flags banned: no flags here at all;
#     time is the start/end pair, house style.
#   - Option values pinned explicitly — deterministic values survive export.
#
# House style: ErrorActionPreference Stop; ${var} braces before ? in strings.

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

function New-Label { param($Text) @{ LocalizedLabels = @(@{ Label = $Text; LanguageCode = 1033 }) } }

# ---------------------------------------------------------------------------
# 1. GLOBAL CHOICES — created before the table that binds them
# ---------------------------------------------------------------------------
$gosAll = (Invoke-RestMethod -Uri "$api/GlobalOptionSetDefinitions" -Headers $headers -Method Get).value.Name

function New-CapGlobalChoice {
    param($Name, $Display, $Options)   # $Options = ordered array of @{v=..; l=..}
    if ($gosAll -contains $Name) {
        Write-Host "Global choice $Name already exists - skipping." -ForegroundColor Yellow
        return
    }
    $body = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.OptionSetMetadata"
        Name          = $Name
        DisplayName   = New-Label $Display
        IsGlobal      = $true
        OptionSetType = "Picklist"
        Options       = @($Options | ForEach-Object { @{ Value = $_.v; Label = New-Label $_.l } })
    } | ConvertTo-Json -Depth 12
    Invoke-RestMethod -Uri "$api/GlobalOptionSetDefinitions" -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host "Created global choice $Name." -ForegroundColor Green
}

# Engagement types: rich, descriptive, cheap to extend
New-CapGlobalChoice -Name "cap_engagementtype" -Display "Engagement Type" -Options @(
    @{ v = 100000000; l = "Annual Accounting" }
    @{ v = 100000001; l = "SMSF Audit" }
    @{ v = 100000002; l = "BAS Agent Services" }
    @{ v = 100000003; l = "ASIC Agent Services" }
    @{ v = 100000004; l = "Company Formation" }
    @{ v = 100000005; l = "Commercial Negotiation" }
    @{ v = 100000006; l = "Information Systems Review" }
    @{ v = 100000007; l = "Information Systems Design" }
    @{ v = 100000008; l = "Information Systems Implementation" }
    @{ v = 100000009; l = "Other" }
)

# Regulatory capacity: whose rulebook this engagement engages
New-CapGlobalChoice -Name "cap_regulatorycapacity" -Display "Regulatory Capacity" -Options @(
    @{ v = 100000000; l = "Tax Agent (TASA)" }
    @{ v = 100000001; l = "ASIC Agent" }
    @{ v = 100000002; l = "SMSF Auditor" }
    @{ v = 100000003; l = "Registered Company Auditor" }
    @{ v = 100000004; l = "Financial Adviser (AFSL)" }
    @{ v = 100000005; l = "None" }
)

# ---------------------------------------------------------------------------
# 2. TABLE — cap_engagement
# ---------------------------------------------------------------------------
$tables = (Invoke-RestMethod -Uri "$api/EntityDefinitions?`$select=LogicalName" -Headers $headers -Method Get).value.LogicalName
if ($tables -contains "cap_engagement") {
    Write-Host "Table cap_engagement already exists - skipping." -ForegroundColor Yellow
} else {
    $body = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.EntityMetadata"
        SchemaName    = "cap_engagement"
        DisplayName   = New-Label "Engagement"
        DisplayCollectionName = New-Label "Engagements"
        Description   = New-Label "Temporal register of what the practice was engaged to do. Null end date means the engagement is open."
        OwnershipType = "UserOwned"
        HasNotes      = $false
        HasActivities = $false
        Attributes    = @(
            @{
                "@odata.type" = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
                SchemaName    = "cap_name"
                IsPrimaryName = $true
                MaxLength     = 300
                RequiredLevel = @{ Value = "ApplicationRequired" }
                DisplayName   = New-Label "Engagement"
            }
        )
    } | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Uri "$api/EntityDefinitions" -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host "Created table cap_engagement." -ForegroundColor Green
    Write-Host "  (If the next call fails with 'does not exist' - metadata cache lag. Wait 60s, rerun.)" -ForegroundColor DarkGray
}

# ---------------------------------------------------------------------------
# 3. COLUMNS
# ---------------------------------------------------------------------------
$attrUri  = "$api/EntityDefinitions(LogicalName='cap_engagement')/Attributes"
$existing = (Invoke-RestMethod -Uri "${attrUri}?`$select=LogicalName" -Headers $headers -Method Get).value.LogicalName

function New-CapChoiceColumn {
    param($Schema, $Display, $GlobalName)
    if ($existing -contains $Schema) {
        Write-Host "$Schema already exists - skipping." -ForegroundColor Yellow
        return
    }
    $gos = (Invoke-RestMethod -Uri "$api/GlobalOptionSetDefinitions" -Headers $headers -Method Get).value |
           Where-Object { $_.Name -eq $GlobalName }
    $body = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.PicklistAttributeMetadata"
        SchemaName    = $Schema
        RequiredLevel = @{ Value = "ApplicationRequired" }
        DisplayName   = New-Label $Display
        "GlobalOptionSet@odata.bind" = "/GlobalOptionSetDefinitions($($gos.MetadataId))"
    } | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Uri $attrUri -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host "Created $Schema (bound to $GlobalName)." -ForegroundColor Green
}

New-CapChoiceColumn -Schema "cap_engagementtype"     -Display "Engagement Type"     -GlobalName "cap_engagementtype"
New-CapChoiceColumn -Schema "cap_regulatorycapacity" -Display "Regulatory Capacity" -GlobalName "cap_regulatorycapacity"

# -- cap_startdate: DateOnly, REQUIRED --------------------------------------
if ($existing -contains "cap_startdate") {
    Write-Host "cap_startdate already exists - skipping." -ForegroundColor Yellow
} else {
    $body = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata"
        SchemaName    = "cap_startdate"
        Format        = "DateOnly"
        DateTimeBehavior = @{ Value = "DateOnly" }
        RequiredLevel = @{ Value = "ApplicationRequired" }
        DisplayName   = New-Label "Start Date"
    } | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Uri $attrUri -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host "Created cap_startdate (DateOnly, required)." -ForegroundColor Green
}

# -- cap_enddate: DateOnly, OPTIONAL — null means open ----------------------
if ($existing -contains "cap_enddate") {
    Write-Host "cap_enddate already exists - skipping." -ForegroundColor Yellow
} else {
    $body = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata"
        SchemaName    = "cap_enddate"
        Format        = "DateOnly"
        DateTimeBehavior = @{ Value = "DateOnly" }
        RequiredLevel = @{ Value = "None" }
        Description   = New-Label "Blank means the engagement is open."
        DisplayName   = New-Label "End Date"
    } | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Uri $attrUri -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host "Created cap_enddate (DateOnly, optional = open)." -ForegroundColor Green
}

# -- cap_notes ---------------------------------------------------------------
if ($existing -contains "cap_notes") {
    Write-Host "cap_notes already exists - skipping." -ForegroundColor Yellow
} else {
    $body = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.MemoAttributeMetadata"
        SchemaName    = "cap_notes"
        MaxLength     = 10000
        RequiredLevel = @{ Value = "None" }
        DisplayName   = New-Label "Notes"
    } | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Uri $attrUri -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host "Created cap_notes." -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# 4. LOOKUP — cap_entityid into cap_entity
# ---------------------------------------------------------------------------
$rels = (Invoke-RestMethod -Uri "$api/RelationshipDefinitions?`$select=SchemaName" -Headers $headers -Method Get).value.SchemaName
if ($rels -contains "cap_entity_cap_engagement") {
    Write-Host "cap_entity_cap_engagement already exists - skipping." -ForegroundColor Yellow
} else {
    $body = @{
        "@odata.type"     = "Microsoft.Dynamics.CRM.OneToManyRelationshipMetadata"
        SchemaName        = "cap_entity_cap_engagement"
        ReferencedEntity  = "cap_entity"
        ReferencingEntity = "cap_engagement"
        Lookup            = @{
            SchemaName    = "cap_entityid"
            RequiredLevel = @{ Value = "ApplicationRequired" }
            DisplayName   = New-Label "Entity"
        }
    } | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Uri "$api/RelationshipDefinitions" -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host "Created cap_entity_cap_engagement (cap_entityid)." -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# 5. VERIFY — choices + columns
# ---------------------------------------------------------------------------
$gosAfter = (Invoke-RestMethod -Uri "$api/GlobalOptionSetDefinitions" -Headers $headers -Method Get).value.Name |
            Where-Object { $_ -like "cap_*" } | Sort-Object
Write-Host "`nGlobal cap_ choices now ($($gosAfter.Count)):" -ForegroundColor Cyan
$gosAfter | ForEach-Object { Write-Host "  $_" }

$after = (Invoke-RestMethod -Uri "${attrUri}?`$select=LogicalName" -Headers $headers -Method Get).value.LogicalName |
         Where-Object { $_ -like "cap_*" } | Sort-Object
Write-Host "`ncap_engagement cap_ columns now ($($after.Count)):" -ForegroundColor Cyan
$after | ForEach-Object { Write-Host "  $_" }

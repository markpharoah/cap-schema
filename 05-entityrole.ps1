# 05-entityrole.ps1 — cap_entityrole: the person <-> entity junction
#
# DESIGN (ratified this session): temporal, append-only. No "continuing" flag —
# cap_startdate required, cap_enddate optional, NULL end-date MEANS continuing.
# cap_ownershippercentage supports the AML/CTF >=25% beneficial ownership test.
#
# v2 LESSONS BAKED IN:
#   - PS7 parses "$var?..." as variable named "var?" — ALWAYS brace ${var} when
#     a ? follows a variable inside a double-quoted string.
#   - $ErrorActionPreference = "Stop": script halts at first failure, so a green
#     "Created" can never print after a failed call. Rerun-safety absorbs halts.

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

# ---------------------------------------------------------------------------
# 1. TABLE — cap_entityrole
# ---------------------------------------------------------------------------
$tables = (Invoke-RestMethod -Uri "$api/EntityDefinitions?`$select=LogicalName" -Headers $headers -Method Get).value.LogicalName
if ($tables -contains "cap_entityrole") {
    Write-Host "Table cap_entityrole already exists - skipping." -ForegroundColor Yellow
} else {
    $body = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.EntityMetadata"
        SchemaName    = "cap_entityrole"
        DisplayName   = @{ LocalizedLabels = @(@{ Label = "Entity Role"; LanguageCode = 1033 }) }
        DisplayCollectionName = @{ LocalizedLabels = @(@{ Label = "Entity Roles"; LanguageCode = 1033 }) }
        Description   = @{ LocalizedLabels = @(@{ Label = "Temporal person-to-entity roles. Null end date means continuing."; LanguageCode = 1033 }) }
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
                DisplayName   = @{ LocalizedLabels = @(@{ Label = "Role"; LanguageCode = 1033 }) }
            }
        )
    } | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Uri "$api/EntityDefinitions" -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host "Created table cap_entityrole." -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# 2. COLUMNS on cap_entityrole
# ---------------------------------------------------------------------------
$attrUri  = "$api/EntityDefinitions(LogicalName='cap_entityrole')/Attributes"
$existing = (Invoke-RestMethod -Uri "${attrUri}?`$select=LogicalName" -Headers $headers -Method Get).value.LogicalName

# -- cap_roletype: bound to the GLOBAL choice cap_roletype ------------------
if ($existing -contains "cap_roletype") {
    Write-Host "cap_roletype already exists - skipping." -ForegroundColor Yellow
} else {
    $gos = (Invoke-RestMethod -Uri "$api/GlobalOptionSetDefinitions" -Headers $headers -Method Get).value |
           Where-Object { $_.Name -eq "cap_roletype" }
    $body = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.PicklistAttributeMetadata"
        SchemaName    = "cap_roletype"
        RequiredLevel = @{ Value = "ApplicationRequired" }
        DisplayName   = @{ LocalizedLabels = @(@{ Label = "Role Type"; LanguageCode = 1033 }) }
        "GlobalOptionSet@odata.bind" = "/GlobalOptionSetDefinitions($($gos.MetadataId))"
    } | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Uri $attrUri -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host "Created cap_roletype (bound to global choice)." -ForegroundColor Green
}

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
        DisplayName   = @{ LocalizedLabels = @(@{ Label = "Start Date"; LanguageCode = 1033 }) }
    } | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Uri $attrUri -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host "Created cap_startdate (DateOnly, required)." -ForegroundColor Green
}

# -- cap_enddate: DateOnly, OPTIONAL — null means continuing ----------------
if ($existing -contains "cap_enddate") {
    Write-Host "cap_enddate already exists - skipping." -ForegroundColor Yellow
} else {
    $body = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata"
        SchemaName    = "cap_enddate"
        Format        = "DateOnly"
        DateTimeBehavior = @{ Value = "DateOnly" }
        RequiredLevel = @{ Value = "None" }
        Description   = @{ LocalizedLabels = @(@{ Label = "Blank means the role is continuing."; LanguageCode = 1033 }) }
        DisplayName   = @{ LocalizedLabels = @(@{ Label = "End Date"; LanguageCode = 1033 }) }
    } | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Uri $attrUri -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host "Created cap_enddate (DateOnly, optional = continuing)." -ForegroundColor Green
}

# -- cap_ownershippercentage: Decimal 0-100, 2dp ----------------------------
if ($existing -contains "cap_ownershippercentage") {
    Write-Host "cap_ownershippercentage already exists - skipping." -ForegroundColor Yellow
} else {
    $body = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.DecimalAttributeMetadata"
        SchemaName    = "cap_ownershippercentage"
        MinValue      = 0
        MaxValue      = 100
        Precision     = 2
        RequiredLevel = @{ Value = "None" }
        Description   = @{ LocalizedLabels = @(@{ Label = "Ownership % where the role carries ownership. Supports the 25% beneficial ownership test."; LanguageCode = 1033 }) }
        DisplayName   = @{ LocalizedLabels = @(@{ Label = "Ownership %"; LanguageCode = 1033 }) }
    } | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Uri $attrUri -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host "Created cap_ownershippercentage (Decimal 0-100, 2dp)." -ForegroundColor Green
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
        DisplayName   = @{ LocalizedLabels = @(@{ Label = "Notes"; LanguageCode = 1033 }) }
    } | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Uri $attrUri -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host "Created cap_notes." -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# 3. LOOKUPS — 1:N relationships with the Lookup nested inside
# ---------------------------------------------------------------------------
$rels = (Invoke-RestMethod -Uri "$api/RelationshipDefinitions?`$select=SchemaName" -Headers $headers -Method Get).value.SchemaName

function New-CapLookup {
    param($RelName, $ReferencedTable, $LookupSchema, $LookupLabel)
    if ($rels -contains $RelName) {
        Write-Host "$RelName already exists - skipping." -ForegroundColor Yellow
        return
    }
    $body = @{
        "@odata.type"     = "Microsoft.Dynamics.CRM.OneToManyRelationshipMetadata"
        SchemaName        = $RelName
        ReferencedEntity  = $ReferencedTable
        ReferencingEntity = "cap_entityrole"
        Lookup            = @{
            SchemaName    = $LookupSchema
            RequiredLevel = @{ Value = "ApplicationRequired" }
            DisplayName   = @{ LocalizedLabels = @(@{ Label = $LookupLabel; LanguageCode = 1033 }) }
        }
    } | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Uri "$api/RelationshipDefinitions" -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host "Created $RelName ($LookupSchema)." -ForegroundColor Green
}

New-CapLookup -RelName "cap_person_cap_entityrole" -ReferencedTable "cap_person" -LookupSchema "cap_personid" -LookupLabel "Person"
New-CapLookup -RelName "cap_entity_cap_entityrole" -ReferencedTable "cap_entity" -LookupSchema "cap_entityid" -LookupLabel "Entity"

# ---------------------------------------------------------------------------
# 4. VERIFY
# ---------------------------------------------------------------------------
$after = (Invoke-RestMethod -Uri "${attrUri}?`$select=LogicalName" -Headers $headers -Method Get).value.LogicalName |
         Where-Object { $_ -like "cap_*" } | Sort-Object
Write-Host "`ncap_entityrole cap_ columns now ($($after.Count)):" -ForegroundColor Cyan
$after | ForEach-Object { Write-Host "  $_" }
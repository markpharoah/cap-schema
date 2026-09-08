# 10-sourcetransaction.ps1 — cap_sourcetransaction: customer evidence
#                          + the drill-path lookup on cap_journalline
#
# DESIGN (ratified, closes Block 3):
#   - EVIDENCE, VERBATIM, SINGLE-SIDED. The customer's cashbook rows exactly
#     as their software exported them: their date, their account TEXT, their
#     signed amount, their description/reference. Completeness (the double
#     entry) is the JOURNAL'S job when day-grain posting asserts it —
#     evidence just records what they said.
#   - NEVER edited, NEVER reported from. Read-only is a process rule (like
#     the opening-balance lock); the schema makes rows identifiable.
#   - NO account lookup on purpose: mapping their text to OUR cap_account is
#     an assertion, and assertions live on journal lines. Their account name
#     is a string here (cap_sourceaccount).
#   - cap_importbatch (string, backstage): which import brought the row in —
#     a botched import is identifiable and supersedable wholesale.
#   - DRILL PATH: cap_sourcetransactionid lookup added to cap_journalline
#     (optional — filled on Source Import lines, empty on adjustments).
#     Statement figure -> journal lines -> source transactions -> image.
#
# House style: Stop; ${var} braces; rerun-safe.

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
# 1. TABLE — cap_sourcetransaction
# ---------------------------------------------------------------------------
$tables = (Invoke-RestMethod -Uri "$api/EntityDefinitions?`$select=LogicalName" -Headers $headers -Method Get).value.LogicalName
if ($tables -contains "cap_sourcetransaction") {
    Write-Host "Table cap_sourcetransaction already exists - skipping." -ForegroundColor Yellow
} else {
    $body = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.EntityMetadata"
        SchemaName    = "cap_sourcetransaction"
        DisplayName   = New-Label "Source Transaction"
        DisplayCollectionName = New-Label "Source Transactions"
        Description   = New-Label "Customer evidence, verbatim and single-sided: their cashbook rows exactly as exported. Never edited, never reported from. The drill path terminates here (and at the image)."
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
                DisplayName   = New-Label "Source Transaction"
            }
        )
    } | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Uri "$api/EntityDefinitions" -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host "Created table cap_sourcetransaction." -ForegroundColor Green
    Write-Host "  (Cache lag on next call is normal - wait 60s, rerun.)" -ForegroundColor DarkGray
}

# ---------------------------------------------------------------------------
# 2. COLUMNS
# ---------------------------------------------------------------------------
$sAttrUri  = "$api/EntityDefinitions(LogicalName='cap_sourcetransaction')/Attributes"
$sExisting = (Invoke-RestMethod -Uri "${sAttrUri}?`$select=LogicalName" -Headers $headers -Method Get).value.LogicalName

# cap_transactiondate: their date, verbatim
if ($sExisting -contains "cap_transactiondate") {
    Write-Host "cap_transactiondate already exists - skipping." -ForegroundColor Yellow
} else {
    $body = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata"
        SchemaName    = "cap_transactiondate"
        Format        = "DateOnly"
        DateTimeBehavior = @{ Value = "DateOnly" }
        RequiredLevel = @{ Value = "ApplicationRequired" }
        DisplayName   = New-Label "Transaction Date"
    } | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Uri $sAttrUri -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host "Created cap_transactiondate (DateOnly, required)." -ForegroundColor Green
}

# cap_amount: their amount, signed, verbatim
if ($sExisting -contains "cap_amount") {
    Write-Host "cap_amount already exists - skipping." -ForegroundColor Yellow
} else {
    $body = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.DecimalAttributeMetadata"
        SchemaName    = "cap_amount"
        MinValue      = -100000000000
        MaxValue      = 100000000000
        Precision     = 2
        RequiredLevel = @{ Value = "ApplicationRequired" }
        Description   = New-Label "Their amount as exported, signed. Evidence - never reported from."
        DisplayName   = New-Label "Amount"
    } | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Uri $sAttrUri -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host "Created cap_amount (signed Decimal, required)." -ForegroundColor Green
}

# cap_sourceaccount: their account TEXT (no lookup - mapping is an assertion)
if ($sExisting -contains "cap_sourceaccount") {
    Write-Host "cap_sourceaccount already exists - skipping." -ForegroundColor Yellow
} else {
    $body = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
        SchemaName    = "cap_sourceaccount"
        MaxLength     = 300
        RequiredLevel = @{ Value = "None" }
        Description   = New-Label "Their account name/code as exported. Text on purpose - mapping to cap_account is an assertion and lives on journal lines."
        DisplayName   = New-Label "Source Account"
    } | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Uri $sAttrUri -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host "Created cap_sourceaccount (their text, verbatim)." -ForegroundColor Green
}

# cap_reference: their description/reference/payee text
if ($sExisting -contains "cap_reference") {
    Write-Host "cap_reference already exists - skipping." -ForegroundColor Yellow
} else {
    $body = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
        SchemaName    = "cap_reference"
        MaxLength     = 850
        RequiredLevel = @{ Value = "None" }
        DisplayName   = New-Label "Reference"
    } | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Uri $sAttrUri -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host "Created cap_reference." -ForegroundColor Green
}

# cap_importbatch: which import brought this row (backstage)
if ($sExisting -contains "cap_importbatch") {
    Write-Host "cap_importbatch already exists - skipping." -ForegroundColor Yellow
} else {
    $body = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
        SchemaName    = "cap_importbatch"
        MaxLength     = 100
        RequiredLevel = @{ Value = "None" }
        Description   = New-Label "Import batch identifier. Backstage - lets a botched import be identified and superseded wholesale."
        DisplayName   = New-Label "Import Batch"
    } | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Uri $sAttrUri -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host "Created cap_importbatch (backstage)." -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# 3. LOOKUPS
# ---------------------------------------------------------------------------
$rels = (Invoke-RestMethod -Uri "$api/RelationshipDefinitions?`$select=SchemaName" -Headers $headers -Method Get).value.SchemaName

# Entity (required) on cap_sourcetransaction
if ($rels -contains "cap_entity_cap_sourcetransaction") {
    Write-Host "cap_entity_cap_sourcetransaction already exists - skipping." -ForegroundColor Yellow
} else {
    $body = @{
        "@odata.type"     = "Microsoft.Dynamics.CRM.OneToManyRelationshipMetadata"
        SchemaName        = "cap_entity_cap_sourcetransaction"
        ReferencedEntity  = "cap_entity"
        ReferencingEntity = "cap_sourcetransaction"
        Lookup            = @{
            SchemaName    = "cap_entityid"
            RequiredLevel = @{ Value = "ApplicationRequired" }
            DisplayName   = New-Label "Entity"
        }
    } | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Uri "$api/RelationshipDefinitions" -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host "Created cap_entity_cap_sourcetransaction (cap_entityid)." -ForegroundColor Green
}

# THE DRILL PATH: cap_sourcetransactionid on cap_journalline (optional)
if ($rels -contains "cap_sourcetransaction_cap_journalline") {
    Write-Host "cap_sourcetransaction_cap_journalline already exists - skipping." -ForegroundColor Yellow
} else {
    $body = @{
        "@odata.type"     = "Microsoft.Dynamics.CRM.OneToManyRelationshipMetadata"
        SchemaName        = "cap_sourcetransaction_cap_journalline"
        ReferencedEntity  = "cap_sourcetransaction"
        ReferencingEntity = "cap_journalline"
        Lookup            = @{
            SchemaName    = "cap_sourcetransactionid"
            RequiredLevel = @{ Value = "None" }
            Description   = New-Label "The evidence this posting was asserted from. Filled on Source Import lines; empty on adjustments. The drill path: figure -> lines -> source -> image."
            DisplayName   = New-Label "Source Transaction"
        }
    } | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Uri "$api/RelationshipDefinitions" -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host "Created cap_sourcetransaction_cap_journalline (cap_sourcetransactionid)." -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# 4. VERIFY — sourcetransaction + the enriched journalline
# ---------------------------------------------------------------------------
$after1 = (Invoke-RestMethod -Uri "${sAttrUri}?`$select=LogicalName" -Headers $headers -Method Get).value.LogicalName |
          Where-Object { $_ -like "cap_*" } | Sort-Object
Write-Host "`ncap_sourcetransaction cap_ columns now ($($after1.Count)):" -ForegroundColor Cyan
$after1 | ForEach-Object { Write-Host "  $_" }

$lAttrUri = "$api/EntityDefinitions(LogicalName='cap_journalline')/Attributes"
$after2 = (Invoke-RestMethod -Uri "${lAttrUri}?`$select=LogicalName" -Headers $headers -Method Get).value.LogicalName |
          Where-Object { $_ -like "cap_*" } | Sort-Object
Write-Host "`ncap_journalline cap_ columns now ($($after2.Count)):" -ForegroundColor Cyan
$after2 | ForEach-Object { Write-Host "  $_" }
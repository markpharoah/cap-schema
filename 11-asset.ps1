# 11-asset.ps1 — cap_asset + cap_assetevent: the dual-book register
#
# DESIGN (ratified this morning, Block 4):
#   - TWO BOOKS, ONE OBJECT. Every asset fact is a dated EVENT stamped with a
#     book (Accounting | Tax). WDV in either book = sum of that book's events
#     — derived, never stored ("no data representing data").
#   - Accounting events ADDITIONALLY spawn journals (Depreciation journal type
#     gets its producer); tax events live only in the register and surface in
#     the return. The optional cap_journalid on an event is that hook — and the
#     system-generated supersede pattern: a regenerated period finds its own
#     events' journals via this link.
#   - ASSET ROW IS LEAN: identity, not state. Cost, WDV, status — all derived
#     from events. The row is the thing you point at; the events are what
#     happened to it.
#   - POOL ENTRY is an event type: it ends the asset's INDIVIDUAL tax life and
#     doubles as the pool's addition (hybrid ruling — the pool derives its
#     additions from these events; its own statutory events come in script 12).
#   - Event amounts are SIGNED, same convention as the ledger: cost/increase
#     positive, depreciation/decline/disposal proceeds negative in the book
#     they diminish. One convention everywhere.
#
# House style: Stop; ${var} braces; pinned option values; rerun-safe.

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
# 1. GLOBAL CHOICES — cap_assetbook, cap_asseteventtype
# ---------------------------------------------------------------------------
$gosAll = (Invoke-RestMethod -Uri "$api/GlobalOptionSetDefinitions" -Headers $headers -Method Get).value.Name

if ($gosAll -contains "cap_assetbook") {
    Write-Host "Global choice cap_assetbook already exists - skipping." -ForegroundColor Yellow
} else {
    $body = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.OptionSetMetadata"
        Name          = "cap_assetbook"
        DisplayName   = New-Label "Asset Book"
        IsGlobal      = $true
        OptionSetType = "Picklist"
        Options       = @(
            @{ Value = 100000000; Label = New-Label "Accounting" }
            @{ Value = 100000001; Label = New-Label "Tax" }
        )
    } | ConvertTo-Json -Depth 12
    Invoke-RestMethod -Uri "$api/GlobalOptionSetDefinitions" -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host "Created global choice cap_assetbook (2 books)." -ForegroundColor Green
}

if ($gosAll -contains "cap_asseteventtype") {
    Write-Host "Global choice cap_asseteventtype already exists - skipping." -ForegroundColor Yellow
} else {
    $body = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.OptionSetMetadata"
        Name          = "cap_asseteventtype"
        DisplayName   = New-Label "Asset Event Type"
        IsGlobal      = $true
        OptionSetType = "Picklist"
        Options       = @(
            @{ Value = 100000000; Label = New-Label "Acquisition" }
            @{ Value = 100000001; Label = New-Label "Depreciation" }
            @{ Value = 100000002; Label = New-Label "Revaluation" }
            @{ Value = 100000003; Label = New-Label "Disposal" }
            @{ Value = 100000004; Label = New-Label "Write-off" }
            @{ Value = 100000005; Label = New-Label "Pool Entry" }
        )
    } | ConvertTo-Json -Depth 12
    Invoke-RestMethod -Uri "$api/GlobalOptionSetDefinitions" -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host "Created global choice cap_asseteventtype (6 types)." -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# 2. TABLE — cap_asset (lean: identity, not state)
# ---------------------------------------------------------------------------
$tables = (Invoke-RestMethod -Uri "$api/EntityDefinitions?`$select=LogicalName" -Headers $headers -Method Get).value.LogicalName
if ($tables -contains "cap_asset") {
    Write-Host "Table cap_asset already exists - skipping." -ForegroundColor Yellow
} else {
    $body = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.EntityMetadata"
        SchemaName    = "cap_asset"
        DisplayName   = New-Label "Asset"
        DisplayCollectionName = New-Label "Assets"
        Description   = New-Label "Fixed asset identity. Deliberately lean: cost, WDV, and status are derived from asset events, never stored here."
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
                DisplayName   = New-Label "Asset"
            }
        )
    } | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Uri "$api/EntityDefinitions" -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host "Created table cap_asset." -ForegroundColor Green
    Write-Host "  (Cache lag on next call is normal - wait 60s, rerun.)" -ForegroundColor DarkGray
}

# --- cap_asset columns ------------------------------------------------------
$aAttrUri  = "$api/EntityDefinitions(LogicalName='cap_asset')/Attributes"
$aExisting = (Invoke-RestMethod -Uri "${aAttrUri}?`$select=LogicalName" -Headers $headers -Method Get).value.LogicalName

# cap_serialnumber: the physical identifier (rego, serial, VIN) - identity, not state
if ($aExisting -contains "cap_serialnumber") {
    Write-Host "cap_serialnumber already exists - skipping." -ForegroundColor Yellow
} else {
    $body = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
        SchemaName    = "cap_serialnumber"
        MaxLength     = 100
        RequiredLevel = @{ Value = "None" }
        Description   = New-Label "Physical identifier - rego, serial, VIN. Identity, so it lives on the row."
        DisplayName   = New-Label "Serial / Rego"
    } | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Uri $aAttrUri -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host "Created cap_serialnumber." -ForegroundColor Green
}

# cap_notes
if ($aExisting -contains "cap_notes") {
    Write-Host "cap_notes already exists - skipping." -ForegroundColor Yellow
} else {
    $body = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.MemoAttributeMetadata"
        SchemaName    = "cap_notes"
        MaxLength     = 10000
        RequiredLevel = @{ Value = "None" }
        DisplayName   = New-Label "Notes"
    } | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Uri $aAttrUri -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host "Created cap_notes on cap_asset." -ForegroundColor Green
}

# --- cap_asset lookup: entity (required) ------------------------------------
$rels = (Invoke-RestMethod -Uri "$api/RelationshipDefinitions?`$select=SchemaName" -Headers $headers -Method Get).value.SchemaName
if ($rels -contains "cap_entity_cap_asset") {
    Write-Host "cap_entity_cap_asset already exists - skipping." -ForegroundColor Yellow
} else {
    $body = @{
        "@odata.type"     = "Microsoft.Dynamics.CRM.OneToManyRelationshipMetadata"
        SchemaName        = "cap_entity_cap_asset"
        ReferencedEntity  = "cap_entity"
        ReferencingEntity = "cap_asset"
        Lookup            = @{
            SchemaName    = "cap_entityid"
            RequiredLevel = @{ Value = "ApplicationRequired" }
            DisplayName   = New-Label "Entity"
        }
    } | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Uri "$api/RelationshipDefinitions" -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host "Created cap_entity_cap_asset (cap_entityid)." -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# 3. TABLE — cap_assetevent (the dual-book temporal stream)
# ---------------------------------------------------------------------------
$tables2 = (Invoke-RestMethod -Uri "$api/EntityDefinitions?`$select=LogicalName" -Headers $headers -Method Get).value.LogicalName
if ($tables2 -contains "cap_assetevent") {
    Write-Host "Table cap_assetevent already exists - skipping." -ForegroundColor Yellow
} else {
    $body = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.EntityMetadata"
        SchemaName    = "cap_assetevent"
        DisplayName   = New-Label "Asset Event"
        DisplayCollectionName = New-Label "Asset Events"
        Description   = New-Label "Dated, append-only asset facts stamped with a book (Accounting or Tax). WDV per book is the sum of that book's events. Accounting events link to the journal they spawned; Pool Entry ends the asset's individual tax life and is the pool's addition."
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
                DisplayName   = New-Label "Event"
            }
        )
    } | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Uri "$api/EntityDefinitions" -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host "Created table cap_assetevent." -ForegroundColor Green
    Write-Host "  (Cache lag on next call is normal - wait 60s, rerun.)" -ForegroundColor DarkGray
}

# --- cap_assetevent columns --------------------------------------------------
$eAttrUri  = "$api/EntityDefinitions(LogicalName='cap_assetevent')/Attributes"
$eExisting = (Invoke-RestMethod -Uri "${eAttrUri}?`$select=LogicalName" -Headers $headers -Method Get).value.LogicalName

# cap_assetbook (required)
if ($eExisting -contains "cap_assetbook") {
    Write-Host "cap_assetbook column already exists - skipping." -ForegroundColor Yellow
} else {
    $gos = (Invoke-RestMethod -Uri "$api/GlobalOptionSetDefinitions" -Headers $headers -Method Get).value |
           Where-Object { $_.Name -eq "cap_assetbook" }
    $body = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.PicklistAttributeMetadata"
        SchemaName    = "cap_assetbook"
        RequiredLevel = @{ Value = "ApplicationRequired" }
        DisplayName   = New-Label "Book"
        "GlobalOptionSet@odata.bind" = "/GlobalOptionSetDefinitions($($gos.MetadataId))"
    } | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Uri $eAttrUri -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host "Created cap_assetbook column (required)." -ForegroundColor Green
}

# cap_asseteventtype (required)
if ($eExisting -contains "cap_asseteventtype") {
    Write-Host "cap_asseteventtype column already exists - skipping." -ForegroundColor Yellow
} else {
    $gos = (Invoke-RestMethod -Uri "$api/GlobalOptionSetDefinitions" -Headers $headers -Method Get).value |
           Where-Object { $_.Name -eq "cap_asseteventtype" }
    $body = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.PicklistAttributeMetadata"
        SchemaName    = "cap_asseteventtype"
        RequiredLevel = @{ Value = "ApplicationRequired" }
        DisplayName   = New-Label "Event Type"
        "GlobalOptionSet@odata.bind" = "/GlobalOptionSetDefinitions($($gos.MetadataId))"
    } | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Uri $eAttrUri -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host "Created cap_asseteventtype column (required)." -ForegroundColor Green
}

# cap_eventdate (DateOnly, required)
if ($eExisting -contains "cap_eventdate") {
    Write-Host "cap_eventdate already exists - skipping." -ForegroundColor Yellow
} else {
    $body = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata"
        SchemaName    = "cap_eventdate"
        Format        = "DateOnly"
        DateTimeBehavior = @{ Value = "DateOnly" }
        RequiredLevel = @{ Value = "ApplicationRequired" }
        DisplayName   = New-Label "Event Date"
    } | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Uri $eAttrUri -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host "Created cap_eventdate (DateOnly, required)." -ForegroundColor Green
}

# cap_amount (signed Decimal, required)
if ($eExisting -contains "cap_amount") {
    Write-Host "cap_amount already exists - skipping." -ForegroundColor Yellow
} else {
    $body = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.DecimalAttributeMetadata"
        SchemaName    = "cap_amount"
        MinValue      = -100000000000
        MaxValue      = 100000000000
        Precision     = 2
        RequiredLevel = @{ Value = "ApplicationRequired" }
        Description   = New-Label "Signed, ledger convention: cost/increase positive; depreciation, decline and disposal proceeds negative in the book they diminish. WDV per book = sum of that book's events."
        DisplayName   = New-Label "Amount"
    } | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Uri $eAttrUri -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host "Created cap_amount (signed Decimal, required)." -ForegroundColor Green
}

# cap_notes
if ($eExisting -contains "cap_notes") {
    Write-Host "cap_notes already exists on event - skipping." -ForegroundColor Yellow
} else {
    $body = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.MemoAttributeMetadata"
        SchemaName    = "cap_notes"
        MaxLength     = 10000
        RequiredLevel = @{ Value = "None" }
        DisplayName   = New-Label "Notes"
    } | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Uri $eAttrUri -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host "Created cap_notes on cap_assetevent." -ForegroundColor Green
}

# --- cap_assetevent lookups ---------------------------------------------------
$rels2 = (Invoke-RestMethod -Uri "$api/RelationshipDefinitions?`$select=SchemaName" -Headers $headers -Method Get).value.SchemaName

# Asset (required)
if ($rels2 -contains "cap_asset_cap_assetevent") {
    Write-Host "cap_asset_cap_assetevent already exists - skipping." -ForegroundColor Yellow
} else {
    $body = @{
        "@odata.type"     = "Microsoft.Dynamics.CRM.OneToManyRelationshipMetadata"
        SchemaName        = "cap_asset_cap_assetevent"
        ReferencedEntity  = "cap_asset"
        ReferencingEntity = "cap_assetevent"
        Lookup            = @{
            SchemaName    = "cap_assetid"
            RequiredLevel = @{ Value = "ApplicationRequired" }
            DisplayName   = New-Label "Asset"
        }
    } | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Uri "$api/RelationshipDefinitions" -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host "Created cap_asset_cap_assetevent (cap_assetid)." -ForegroundColor Green
}

# Journal (optional): the journal an ACCOUNTING event spawned
if ($rels2 -contains "cap_journal_cap_assetevent") {
    Write-Host "cap_journal_cap_assetevent already exists - skipping." -ForegroundColor Yellow
} else {
    $body = @{
        "@odata.type"     = "Microsoft.Dynamics.CRM.OneToManyRelationshipMetadata"
        SchemaName        = "cap_journal_cap_assetevent"
        ReferencedEntity  = "cap_journal"
        ReferencingEntity = "cap_assetevent"
        Lookup            = @{
            SchemaName    = "cap_journalid"
            RequiredLevel = @{ Value = "None" }
            Description   = New-Label "The journal this ACCOUNTING event spawned. Empty on tax events. The system-generated supersede hook: a regenerated period finds its own journals here."
            DisplayName   = New-Label "Journal"
        }
    } | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Uri "$api/RelationshipDefinitions" -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host "Created cap_journal_cap_assetevent (cap_journalid)." -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# 4. VERIFY — both tables
# ---------------------------------------------------------------------------
$after1 = (Invoke-RestMethod -Uri "${aAttrUri}?`$select=LogicalName" -Headers $headers -Method Get).value.LogicalName |
          Where-Object { $_ -like "cap_*" } | Sort-Object
Write-Host "`ncap_asset cap_ columns now ($($after1.Count)):" -ForegroundColor Cyan
$after1 | ForEach-Object { Write-Host "  $_" }

$after2 = (Invoke-RestMethod -Uri "${eAttrUri}?`$select=LogicalName" -Headers $headers -Method Get).value.LogicalName |
          Where-Object { $_ -like "cap_*" } | Sort-Object
Write-Host "`ncap_assetevent cap_ columns now ($($after2.Count)):" -ForegroundColor Cyan
$after2 | ForEach-Object { Write-Host "  $_" }
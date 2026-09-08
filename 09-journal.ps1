# 09-journal.ps1 — cap_journal + cap_journalline: the practice assertion layer
#
# DESIGN (ratified this morning, Block 3):
#   - Reporting reads cap_journalline DIRECTLY. No cap_ledgertransaction, ever.
#     "Why would you create another bit of data to represent data?" (Mark).
#   - JOURNAL = the document (who asserted, when raised, why - the type).
#     LINE = the posting (day-grain date, account, signed amount).
#   - Dates live ON LINES. One import journal can carry a month of day-grain
#     lines; any date-range report is a filter on line dates.
#   - SIGNED AMOUNTS: debits positive, credits negative. One cap_amount,
#     plain Decimal (house rule: never Currency type for AUD-only).
#     Invariant: every journal sums to zero. Dr/Cr is a PROJECTION at the
#     presentation layer (Dr = amount if +ve, Cr = -amount if -ve) - one
#     expression per row, no queries-within-queries, costs nothing.
#     GOLDEN RULES: raw negatives never reach a user; contra items present
#     as reductions (revenue 100,000 less credit notes (2,000)).
#   - REVERSALS ARE LINEAGE, NOT SIGNS: cap_reversesjournalid (optional
#     self-lookup). A reversal is a NEW journal pointing at what it reverses
#     - append-only, never edit. Presentation narrates "Reversal of CN-0042"
#     from structure, never by guessing at signs.
#   - cap_journaltype (7, born not retrofitted):
#       Opening Balance   - the locked starting position (lock = process rule:
#                           never edited, only superseded; type makes rows
#                           identifiable and protectable)
#       Source Import     - day-grain posting of customer cashbook (drill path)
#       Adjustment        - human assertions (year-end/period journals)
#       Tax Reconciliation- LodgeIT round-trip journals
#       Reclassification  - layer-2 corrections (future, born with a home)
#       Depreciation      - system-generated from the asset register (Block 4)
#       Finance Charge    - system-generated from financing contracts (CHP
#                           interest per lender actuarial schedule; leases too)
#     System-generated types let a regenerating register find and supersede
#     ITS OWN journals without touching human ones.
#   - cap_sourcetransactionid lookup on lines DEFERRED to 10-sourcetransaction
#     (that table doesn't exist yet; lookup added there).
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
# 1. GLOBAL CHOICE — cap_journaltype
# ---------------------------------------------------------------------------
$gosAll = (Invoke-RestMethod -Uri "$api/GlobalOptionSetDefinitions" -Headers $headers -Method Get).value.Name
if ($gosAll -contains "cap_journaltype") {
    Write-Host "Global choice cap_journaltype already exists - skipping." -ForegroundColor Yellow
} else {
    $options = @(
        @{ v = 100000000; l = "Opening Balance" }
        @{ v = 100000001; l = "Source Import" }
        @{ v = 100000002; l = "Adjustment" }
        @{ v = 100000003; l = "Tax Reconciliation" }
        @{ v = 100000004; l = "Reclassification" }
        @{ v = 100000005; l = "Depreciation" }
        @{ v = 100000006; l = "Finance Charge" }
    )
    $body = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.OptionSetMetadata"
        Name          = "cap_journaltype"
        DisplayName   = New-Label "Journal Type"
        IsGlobal      = $true
        OptionSetType = "Picklist"
        Options       = @($options | ForEach-Object { @{ Value = $_.v; Label = New-Label $_.l } })
    } | ConvertTo-Json -Depth 12
    Invoke-RestMethod -Uri "$api/GlobalOptionSetDefinitions" -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host "Created global choice cap_journaltype (7 types)." -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# 2. TABLE — cap_journal (the document)
# ---------------------------------------------------------------------------
$tables = (Invoke-RestMethod -Uri "$api/EntityDefinitions?`$select=LogicalName" -Headers $headers -Method Get).value.LogicalName
if ($tables -contains "cap_journal") {
    Write-Host "Table cap_journal already exists - skipping." -ForegroundColor Yellow
} else {
    $body = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.EntityMetadata"
        SchemaName    = "cap_journal"
        DisplayName   = New-Label "Journal"
        DisplayCollectionName = New-Label "Journals"
        Description   = New-Label "The practice assertion document: who asserted what, when, why. Lines carry the postings. Append-only; reversals are new journals linked via Reverses Journal."
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
                DisplayName   = New-Label "Journal"
            }
        )
    } | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Uri "$api/EntityDefinitions" -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host "Created table cap_journal." -ForegroundColor Green
    Write-Host "  (Cache lag on next call is normal - wait 60s, rerun.)" -ForegroundColor DarkGray
}

# --- cap_journal columns ----------------------------------------------------
$jAttrUri  = "$api/EntityDefinitions(LogicalName='cap_journal')/Attributes"
$jExisting = (Invoke-RestMethod -Uri "${jAttrUri}?`$select=LogicalName" -Headers $headers -Method Get).value.LogicalName

# cap_journaltype (required)
if ($jExisting -contains "cap_journaltype") {
    Write-Host "cap_journaltype column already exists - skipping." -ForegroundColor Yellow
} else {
    $gos = (Invoke-RestMethod -Uri "$api/GlobalOptionSetDefinitions" -Headers $headers -Method Get).value |
           Where-Object { $_.Name -eq "cap_journaltype" }
    $body = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.PicklistAttributeMetadata"
        SchemaName    = "cap_journaltype"
        RequiredLevel = @{ Value = "ApplicationRequired" }
        DisplayName   = New-Label "Journal Type"
        "GlobalOptionSet@odata.bind" = "/GlobalOptionSetDefinitions($($gos.MetadataId))"
    } | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Uri $jAttrUri -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host "Created cap_journaltype column (required)." -ForegroundColor Green
}

# cap_journaldate: the date the DOCUMENT was raised (reporting reads LINE dates)
if ($jExisting -contains "cap_journaldate") {
    Write-Host "cap_journaldate already exists - skipping." -ForegroundColor Yellow
} else {
    $body = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata"
        SchemaName    = "cap_journaldate"
        Format        = "DateOnly"
        DateTimeBehavior = @{ Value = "DateOnly" }
        RequiredLevel = @{ Value = "ApplicationRequired" }
        Description   = New-Label "Date the journal document was raised. Reporting reads line dates, not this."
        DisplayName   = New-Label "Journal Date"
    } | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Uri $jAttrUri -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host "Created cap_journaldate (DateOnly, required)." -ForegroundColor Green
}

# cap_description
if ($jExisting -contains "cap_description") {
    Write-Host "cap_description already exists - skipping." -ForegroundColor Yellow
} else {
    $body = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.MemoAttributeMetadata"
        SchemaName    = "cap_description"
        MaxLength     = 10000
        RequiredLevel = @{ Value = "None" }
        DisplayName   = New-Label "Description"
    } | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Uri $jAttrUri -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host "Created cap_description on cap_journal." -ForegroundColor Green
}

# --- cap_journal lookups ----------------------------------------------------
$rels = (Invoke-RestMethod -Uri "$api/RelationshipDefinitions?`$select=SchemaName" -Headers $headers -Method Get).value.SchemaName

# Entity (required): whose books this assertion belongs to
if ($rels -contains "cap_entity_cap_journal") {
    Write-Host "cap_entity_cap_journal already exists - skipping." -ForegroundColor Yellow
} else {
    $body = @{
        "@odata.type"     = "Microsoft.Dynamics.CRM.OneToManyRelationshipMetadata"
        SchemaName        = "cap_entity_cap_journal"
        ReferencedEntity  = "cap_entity"
        ReferencingEntity = "cap_journal"
        Lookup            = @{
            SchemaName    = "cap_entityid"
            RequiredLevel = @{ Value = "ApplicationRequired" }
            DisplayName   = New-Label "Entity"
        }
    } | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Uri "$api/RelationshipDefinitions" -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host "Created cap_entity_cap_journal (cap_entityid)." -ForegroundColor Green
}

# Reverses Journal (optional self-lookup): lineage, not signs
if ($rels -contains "cap_journal_cap_journal_reverses") {
    Write-Host "cap_journal_cap_journal_reverses already exists - skipping." -ForegroundColor Yellow
} else {
    $body = @{
        "@odata.type"     = "Microsoft.Dynamics.CRM.OneToManyRelationshipMetadata"
        SchemaName        = "cap_journal_cap_journal_reverses"
        ReferencedEntity  = "cap_journal"
        ReferencingEntity = "cap_journal"
        Lookup            = @{
            SchemaName    = "cap_reversesjournalid"
            RequiredLevel = @{ Value = "None" }
            Description   = New-Label "The journal this journal reverses. A reversal is a new journal - append-only, never an edit. Presentation narrates from this lineage, never from signs."
            DisplayName   = New-Label "Reverses Journal"
        }
    } | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Uri "$api/RelationshipDefinitions" -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host "Created cap_journal_cap_journal_reverses (cap_reversesjournalid)." -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# 3. TABLE — cap_journalline (the posting; THE reporting source)
# ---------------------------------------------------------------------------
$tables2 = (Invoke-RestMethod -Uri "$api/EntityDefinitions?`$select=LogicalName" -Headers $headers -Method Get).value.LogicalName
if ($tables2 -contains "cap_journalline") {
    Write-Host "Table cap_journalline already exists - skipping." -ForegroundColor Yellow
} else {
    $body = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.EntityMetadata"
        SchemaName    = "cap_journalline"
        DisplayName   = New-Label "Journal Line"
        DisplayCollectionName = New-Label "Journal Lines"
        Description   = New-Label "The posting: day-grain date, account, signed amount (debits positive, credits negative; every journal sums to zero). THE sole reporting source. Dr/Cr is a presentation projection."
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
                DisplayName   = New-Label "Line"
            }
        )
    } | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Uri "$api/EntityDefinitions" -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host "Created table cap_journalline." -ForegroundColor Green
    Write-Host "  (Cache lag on next call is normal - wait 60s, rerun.)" -ForegroundColor DarkGray
}

# --- cap_journalline columns ------------------------------------------------
$lAttrUri  = "$api/EntityDefinitions(LogicalName='cap_journalline')/Attributes"
$lExisting = (Invoke-RestMethod -Uri "${lAttrUri}?`$select=LogicalName" -Headers $headers -Method Get).value.LogicalName

# cap_linedate: THE reporting date (day-grain)
if ($lExisting -contains "cap_linedate") {
    Write-Host "cap_linedate already exists - skipping." -ForegroundColor Yellow
} else {
    $body = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata"
        SchemaName    = "cap_linedate"
        Format        = "DateOnly"
        DateTimeBehavior = @{ Value = "DateOnly" }
        RequiredLevel = @{ Value = "ApplicationRequired" }
        Description   = New-Label "The posting date. Day-grain. Every report is a filter on this."
        DisplayName   = New-Label "Line Date"
    } | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Uri $lAttrUri -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host "Created cap_linedate (DateOnly, required)." -ForegroundColor Green
}

# cap_amount: signed Decimal - debits positive, credits negative
if ($lExisting -contains "cap_amount") {
    Write-Host "cap_amount already exists - skipping." -ForegroundColor Yellow
} else {
    $body = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.DecimalAttributeMetadata"
        SchemaName    = "cap_amount"
        MinValue      = -100000000000
        MaxValue      = 100000000000
        Precision     = 2
        RequiredLevel = @{ Value = "ApplicationRequired" }
        Description   = New-Label "Signed: debits positive, credits negative. Every journal sums to zero. Never shown raw to users - Dr/Cr is a presentation projection."
        DisplayName   = New-Label "Amount"
    } | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Uri $lAttrUri -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host "Created cap_amount (signed Decimal, required)." -ForegroundColor Green
}

# cap_description (line narration)
if ($lExisting -contains "cap_description") {
    Write-Host "cap_description already exists on line - skipping." -ForegroundColor Yellow
} else {
    $body = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.MemoAttributeMetadata"
        SchemaName    = "cap_description"
        MaxLength     = 10000
        RequiredLevel = @{ Value = "None" }
        DisplayName   = New-Label "Description"
    } | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Uri $lAttrUri -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host "Created cap_description on cap_journalline." -ForegroundColor Green
}

# --- cap_journalline lookups ------------------------------------------------
$rels2 = (Invoke-RestMethod -Uri "$api/RelationshipDefinitions?`$select=SchemaName" -Headers $headers -Method Get).value.SchemaName

# Journal (required): the document this posting belongs to
if ($rels2 -contains "cap_journal_cap_journalline") {
    Write-Host "cap_journal_cap_journalline already exists - skipping." -ForegroundColor Yellow
} else {
    $body = @{
        "@odata.type"     = "Microsoft.Dynamics.CRM.OneToManyRelationshipMetadata"
        SchemaName        = "cap_journal_cap_journalline"
        ReferencedEntity  = "cap_journal"
        ReferencingEntity = "cap_journalline"
        Lookup            = @{
            SchemaName    = "cap_journalid"
            RequiredLevel = @{ Value = "ApplicationRequired" }
            DisplayName   = New-Label "Journal"
        }
    } | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Uri "$api/RelationshipDefinitions" -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host "Created cap_journal_cap_journalline (cap_journalid)." -ForegroundColor Green
}

# Account (required): what the posting hits
if ($rels2 -contains "cap_account_cap_journalline") {
    Write-Host "cap_account_cap_journalline already exists - skipping." -ForegroundColor Yellow
} else {
    $body = @{
        "@odata.type"     = "Microsoft.Dynamics.CRM.OneToManyRelationshipMetadata"
        SchemaName        = "cap_account_cap_journalline"
        ReferencedEntity  = "cap_account"
        ReferencingEntity = "cap_journalline"
        Lookup            = @{
            SchemaName    = "cap_accountid"
            RequiredLevel = @{ Value = "ApplicationRequired" }
            DisplayName   = New-Label "Account"
        }
    } | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Uri "$api/RelationshipDefinitions" -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host "Created cap_account_cap_journalline (cap_accountid)." -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# 4. VERIFY — both tables
# ---------------------------------------------------------------------------
$after1 = (Invoke-RestMethod -Uri "${jAttrUri}?`$select=LogicalName" -Headers $headers -Method Get).value.LogicalName |
          Where-Object { $_ -like "cap_*" } | Sort-Object
Write-Host "`ncap_journal cap_ columns now ($($after1.Count)):" -ForegroundColor Cyan
$after1 | ForEach-Object { Write-Host "  $_" }

$after2 = (Invoke-RestMethod -Uri "${lAttrUri}?`$select=LogicalName" -Headers $headers -Method Get).value.LogicalName |
          Where-Object { $_ -like "cap_*" } | Sort-Object
Write-Host "`ncap_journalline cap_ columns now ($($after2.Count)):" -ForegroundColor Cyan
$after2 | ForEach-Object { Write-Host "  $_" }
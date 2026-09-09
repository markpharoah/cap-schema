# 12-pool-finance.ps1 — cap_pool + cap_poolevent + cap_financecontract + cap_financescheduleline
#
# DESIGN (ratified this morning):
#   POOL (hybrid ruling):
#   - cap_pool = identity + statutory event history. Balance at date =
#     (sum of asset Pool Entry events to date)  <- DERIVED, additions never duplicated
#     + (sum of cap_poolevent amounts to date)  <- STORED, the statutory trail
#   - cap_poolevent stores only where THE LAW ACTS ON THE POOL: annual decline
#     (15% first-year / 30% thereafter - a calculation OUTCOME with rate, base
#     and year in notes: auditable assertion, not re-executable law),
#     termination-value subtractions, low-pool-value write-off, adjustments.
#   FINANCE (evidence -> assertion, the sourcetransaction pattern in a suit):
#   - The lender's scanned schedule is EVIDENCE - lives in SharePoint (document
#     layer per Block 1 architecture); cap_documenturl on the contract is the
#     reference. Drill: Finance Charge figure -> journal -> schedule line ->
#     the bank's actual document.
#   - cap_financescheduleline rows are OUR assertions: extracted from the image
#     and ACTUARIALLY VERIFIED (VCFO checks the bank's arithmetic). They feed
#     Finance Charge journals; optional journal hook = supersede pattern.
#   - Interest and principal as SEPARATE signed amounts per period - the split
#     IS the point (GST/deduction treatment differs; the split must be the
#     lender's actuarial one, verified, never straight-line).
#
# House style: Stop; ${var} braces; pinned values; rerun-safe.

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
# 1. GLOBAL CHOICES
# ---------------------------------------------------------------------------
$gosAll = (Invoke-RestMethod -Uri "$api/GlobalOptionSetDefinitions" -Headers $headers -Method Get).value.Name

if ($gosAll -contains "cap_pooleventtype") {
    Write-Host "Global choice cap_pooleventtype already exists - skipping." -ForegroundColor Yellow
} else {
    $body = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.OptionSetMetadata"
        Name          = "cap_pooleventtype"
        DisplayName   = New-Label "Pool Event Type"
        IsGlobal      = $true
        OptionSetType = "Picklist"
        Options       = @(
            @{ Value = 100000000; Label = New-Label "Decline 15%" }
            @{ Value = 100000001; Label = New-Label "Decline 30%" }
            @{ Value = 100000002; Label = New-Label "Termination Value" }
            @{ Value = 100000003; Label = New-Label "Low Pool Value Write-off" }
            @{ Value = 100000004; Label = New-Label "Adjustment" }
        )
    } | ConvertTo-Json -Depth 12
    Invoke-RestMethod -Uri "$api/GlobalOptionSetDefinitions" -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host "Created global choice cap_pooleventtype (5 types)." -ForegroundColor Green
}

if ($gosAll -contains "cap_financecontracttype") {
    Write-Host "Global choice cap_financecontracttype already exists - skipping." -ForegroundColor Yellow
} else {
    $body = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.OptionSetMetadata"
        Name          = "cap_financecontracttype"
        DisplayName   = New-Label "Finance Contract Type"
        IsGlobal      = $true
        OptionSetType = "Picklist"
        Options       = @(
            @{ Value = 100000000; Label = New-Label "Chattel Mortgage" }
            @{ Value = 100000001; Label = New-Label "Commercial Hire Purchase" }
            @{ Value = 100000002; Label = New-Label "Finance Lease" }
            @{ Value = 100000003; Label = New-Label "Operating Lease" }
        )
    } | ConvertTo-Json -Depth 12
    Invoke-RestMethod -Uri "$api/GlobalOptionSetDefinitions" -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host "Created global choice cap_financecontracttype (4 types)." -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# Helper for simple tables (primary name only at create)
# ---------------------------------------------------------------------------
function New-CapTable {
    param($Schema, $Display, $Collection, $Desc, $NameLabel)
    $tables = (Invoke-RestMethod -Uri "$api/EntityDefinitions?`$select=LogicalName" -Headers $headers -Method Get).value.LogicalName
    if ($tables -contains $Schema) {
        Write-Host "Table $Schema already exists - skipping." -ForegroundColor Yellow
        return
    }
    $body = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.EntityMetadata"
        SchemaName    = $Schema
        DisplayName   = New-Label $Display
        DisplayCollectionName = New-Label $Collection
        Description   = New-Label $Desc
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
                DisplayName   = New-Label $NameLabel
            }
        )
    } | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Uri "$api/EntityDefinitions" -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host "Created table $Schema." -ForegroundColor Green
    Write-Host "  (Cache lag on next call is normal - wait 60s, rerun.)" -ForegroundColor DarkGray
}

# Helpers for columns (each rerun-safe against a fresh existence list)
function Get-Existing { param($Table)
    (Invoke-RestMethod -Uri "$api/EntityDefinitions(LogicalName='$Table')/Attributes?`$select=LogicalName" -Headers $headers -Method Get).value.LogicalName
}
function New-CapChoiceCol { param($Table, $Schema, $Display, $GlobalName, $Existing)
    if ($Existing -contains $Schema) { Write-Host "$Schema already exists on $Table - skipping." -ForegroundColor Yellow; return }
    $gos = (Invoke-RestMethod -Uri "$api/GlobalOptionSetDefinitions" -Headers $headers -Method Get).value |
           Where-Object { $_.Name -eq $GlobalName }
    $body = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.PicklistAttributeMetadata"
        SchemaName    = $Schema
        RequiredLevel = @{ Value = "ApplicationRequired" }
        DisplayName   = New-Label $Display
        "GlobalOptionSet@odata.bind" = "/GlobalOptionSetDefinitions($($gos.MetadataId))"
    } | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Uri "$api/EntityDefinitions(LogicalName='$Table')/Attributes" -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host "Created $Schema on $Table." -ForegroundColor Green
}
function New-CapDateCol { param($Table, $Schema, $Display, $Required, $Existing, $Desc = $null)
    if ($Existing -contains $Schema) { Write-Host "$Schema already exists on $Table - skipping." -ForegroundColor Yellow; return }
    $attr = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata"
        SchemaName    = $Schema
        Format        = "DateOnly"
        DateTimeBehavior = @{ Value = "DateOnly" }
        RequiredLevel = @{ Value = $Required }
        DisplayName   = New-Label $Display
    }
    if ($Desc) { $attr.Description = New-Label $Desc }
    $body = $attr | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Uri "$api/EntityDefinitions(LogicalName='$Table')/Attributes" -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host "Created $Schema on $Table." -ForegroundColor Green
}
function New-CapDecimalCol { param($Table, $Schema, $Display, $Required, $Existing, $Desc = $null)
    if ($Existing -contains $Schema) { Write-Host "$Schema already exists on $Table - skipping." -ForegroundColor Yellow; return }
    $attr = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.DecimalAttributeMetadata"
        SchemaName    = $Schema
        MinValue      = -100000000000
        MaxValue      = 100000000000
        Precision     = 2
        RequiredLevel = @{ Value = $Required }
        DisplayName   = New-Label $Display
    }
    if ($Desc) { $attr.Description = New-Label $Desc }
    $body = $attr | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Uri "$api/EntityDefinitions(LogicalName='$Table')/Attributes" -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host "Created $Schema on $Table." -ForegroundColor Green
}
function New-CapStringCol { param($Table, $Schema, $Display, $Max, $Existing, $Desc = $null)
    if ($Existing -contains $Schema) { Write-Host "$Schema already exists on $Table - skipping." -ForegroundColor Yellow; return }
    $attr = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
        SchemaName    = $Schema
        MaxLength     = $Max
        RequiredLevel = @{ Value = "None" }
        DisplayName   = New-Label $Display
    }
    if ($Desc) { $attr.Description = New-Label $Desc }
    $body = $attr | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Uri "$api/EntityDefinitions(LogicalName='$Table')/Attributes" -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host "Created $Schema on $Table." -ForegroundColor Green
}
function New-CapMemoCol { param($Table, $Existing)
    if ($Existing -contains "cap_notes") { Write-Host "cap_notes already exists on $Table - skipping." -ForegroundColor Yellow; return }
    $body = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.MemoAttributeMetadata"
        SchemaName    = "cap_notes"
        MaxLength     = 10000
        RequiredLevel = @{ Value = "None" }
        DisplayName   = New-Label "Notes"
    } | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Uri "$api/EntityDefinitions(LogicalName='$Table')/Attributes" -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host "Created cap_notes on $Table." -ForegroundColor Green
}
function New-CapLookup { param($RelName, $Referenced, $Referencing, $Schema, $Label, $Required, $Desc = $null)
    $rels = (Invoke-RestMethod -Uri "$api/RelationshipDefinitions?`$select=SchemaName" -Headers $headers -Method Get).value.SchemaName
    if ($rels -contains $RelName) { Write-Host "$RelName already exists - skipping." -ForegroundColor Yellow; return }
    $lookup = @{
        SchemaName    = $Schema
        RequiredLevel = @{ Value = $Required }
        DisplayName   = New-Label $Label
    }
    if ($Desc) { $lookup.Description = New-Label $Desc }
    $body = @{
        "@odata.type"     = "Microsoft.Dynamics.CRM.OneToManyRelationshipMetadata"
        SchemaName        = $RelName
        ReferencedEntity  = $Referenced
        ReferencingEntity = $Referencing
        Lookup            = $lookup
    } | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Uri "$api/RelationshipDefinitions" -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host "Created $RelName ($Schema)." -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# 2. cap_pool — identity + statutory history home
# ---------------------------------------------------------------------------
New-CapTable -Schema "cap_pool" -Display "Pool" -Collection "Pools" `
    -Desc "Small business general pool (Division 328): identity plus statutory event history. Balance = derived asset Pool Entry additions + stored pool events. Additions are never duplicated here." `
    -NameLabel "Pool"

$pExisting = Get-Existing "cap_pool"
New-CapMemoCol -Table "cap_pool" -Existing $pExisting
New-CapLookup -RelName "cap_entity_cap_pool" -Referenced "cap_entity" -Referencing "cap_pool" `
    -Schema "cap_entityid" -Label "Entity" -Required "ApplicationRequired"

# ---------------------------------------------------------------------------
# 3. cap_poolevent — where the law acts on the pool
# ---------------------------------------------------------------------------
New-CapTable -Schema "cap_poolevent" -Display "Pool Event" -Collection "Pool Events" `
    -Desc "Statutory pool events only: declines (rate/base/year in notes - auditable assertions), termination values, low-pool-value write-off, adjustments. Additions derive from asset Pool Entry events and are never stored here." `
    -NameLabel "Event"

$peExisting = Get-Existing "cap_poolevent"
New-CapChoiceCol  -Table "cap_poolevent" -Schema "cap_pooleventtype" -Display "Event Type" -GlobalName "cap_pooleventtype" -Existing $peExisting
New-CapDateCol    -Table "cap_poolevent" -Schema "cap_eventdate" -Display "Event Date" -Required "ApplicationRequired" -Existing $peExisting
New-CapDecimalCol -Table "cap_poolevent" -Schema "cap_amount" -Display "Amount" -Required "ApplicationRequired" -Existing $peExisting `
    -Desc "Signed, ledger convention: declines and write-offs negative; adjustments as signed. Notes carry rate, base and year for the audit trail."
New-CapMemoCol    -Table "cap_poolevent" -Existing $peExisting
New-CapLookup -RelName "cap_pool_cap_poolevent" -Referenced "cap_pool" -Referencing "cap_poolevent" `
    -Schema "cap_poolid" -Label "Pool" -Required "ApplicationRequired"

# ---------------------------------------------------------------------------
# 4. cap_financecontract — the funding register
# ---------------------------------------------------------------------------
New-CapTable -Schema "cap_financecontract" -Display "Finance Contract" -Collection "Finance Contracts" `
    -Desc "CHP / chattel mortgage / lease register. The lender's scanned schedule is evidence in SharePoint (cap_documenturl is the reference); schedule lines are the practice's actuarially verified assertions." `
    -NameLabel "Contract"

$fcExisting = Get-Existing "cap_financecontract"
New-CapChoiceCol  -Table "cap_financecontract" -Schema "cap_financecontracttype" -Display "Contract Type" -GlobalName "cap_financecontracttype" -Existing $fcExisting
New-CapStringCol  -Table "cap_financecontract" -Schema "cap_lender" -Display "Lender" -Max 200 -Existing $fcExisting
New-CapDateCol    -Table "cap_financecontract" -Schema "cap_startdate" -Display "Start Date" -Required "ApplicationRequired" -Existing $fcExisting
New-CapDateCol    -Table "cap_financecontract" -Schema "cap_enddate" -Display "End Date" -Required "None" -Existing $fcExisting `
    -Desc "Blank means the contract is on foot."
New-CapDecimalCol -Table "cap_financecontract" -Schema "cap_amountfinanced" -Display "Amount Financed" -Required "ApplicationRequired" -Existing $fcExisting
New-CapDecimalCol -Table "cap_financecontract" -Schema "cap_totalinterest" -Display "Total Interest" -Required "None" -Existing $fcExisting `
    -Desc "Per the lender's actuarial schedule. Verified against the sum of schedule line interest - the bank-arithmetic check."
New-CapStringCol  -Table "cap_financecontract" -Schema "cap_documenturl" -Display "Document" -Max 850 -Existing $fcExisting `
    -Desc "SharePoint URL of the lender's scanned schedule - the evidence this contract's lines were extracted from. The drill path's final leg."
New-CapMemoCol    -Table "cap_financecontract" -Existing $fcExisting
New-CapLookup -RelName "cap_entity_cap_financecontract" -Referenced "cap_entity" -Referencing "cap_financecontract" `
    -Schema "cap_entityid" -Label "Entity" -Required "ApplicationRequired"
New-CapLookup -RelName "cap_asset_cap_financecontract" -Referenced "cap_asset" -Referencing "cap_financecontract" `
    -Schema "cap_assetid" -Label "Asset" -Required "None" `
    -Desc "The asset this contract funds. Optional: some facilities are not asset-specific."

# ---------------------------------------------------------------------------
# 5. cap_financescheduleline — the verified actuarial split
# ---------------------------------------------------------------------------
New-CapTable -Schema "cap_financescheduleline" -Display "Finance Schedule Line" -Collection "Finance Schedule Lines" `
    -Desc "One period of the lender's actuarial schedule, extracted from the evidence document and verified. Interest and principal separate - the split IS the point. Feeds Finance Charge journals." `
    -NameLabel "Line"

$flExisting = Get-Existing "cap_financescheduleline"
New-CapDateCol    -Table "cap_financescheduleline" -Schema "cap_perioddate" -Display "Period Date" -Required "ApplicationRequired" -Existing $flExisting
New-CapDecimalCol -Table "cap_financescheduleline" -Schema "cap_interestamount" -Display "Interest" -Required "ApplicationRequired" -Existing $flExisting `
    -Desc "The period's interest per the lender's actuarial schedule, verified. Feeds the Finance Charge journal."
New-CapDecimalCol -Table "cap_financescheduleline" -Schema "cap_principalamount" -Display "Principal" -Required "ApplicationRequired" -Existing $flExisting
New-CapMemoCol    -Table "cap_financescheduleline" -Existing $flExisting
New-CapLookup -RelName "cap_financecontract_cap_fsl" -Referenced "cap_financecontract" -Referencing "cap_financescheduleline" `
    -Schema "cap_financecontractid" -Label "Finance Contract" -Required "ApplicationRequired"
New-CapLookup -RelName "cap_journal_cap_fsl" -Referenced "cap_journal" -Referencing "cap_financescheduleline" `
    -Schema "cap_journalid" -Label "Journal" -Required "None" `
    -Desc "The Finance Charge journal this line fed. The supersede hook."

# ---------------------------------------------------------------------------
# 6. VERIFY — all four
# ---------------------------------------------------------------------------
foreach ($t in @("cap_pool","cap_poolevent","cap_financecontract")) {
    $after = (Invoke-RestMethod -Uri "$api/EntityDefinitions(LogicalName='$t')/Attributes?`$select=LogicalName" -Headers $headers -Method Get).value.LogicalName |
             Where-Object { $_ -like "cap_*" } | Sort-Object
    Write-Host "`n$t cap_ columns now ($($after.Count)):" -ForegroundColor Cyan
    $after | ForEach-Object { Write-Host "  $_" }
}
$after4 = (Invoke-RestMethod -Uri "$api/EntityDefinitions(LogicalName='cap_financescheduleline')/Attributes?`$select=LogicalName" -Headers $headers -Method Get).value.LogicalName |
          Where-Object { $_ -like "cap_*" } | Sort-Object
Write-Host "`ncap_financescheduleline cap_ columns now ($($after4.Count)):" -ForegroundColor Cyan
$after4 | ForEach-Object { Write-Host "  $_" }
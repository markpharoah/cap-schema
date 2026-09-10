# 08-account.ps1 — cap_account: the per-entity chart of accounts
#
# DESIGN (ratified this morning):
#   - THEIR NAMES, OUR CLASSIFICATIONS. cap_name holds the customer's account
#     name verbatim as imported (it makes sense to THEM; queries reference it).
#     cap_accountclass is the practice's assertion — which of OUR locked
#     statement subtotals this account belongs to. That classification is what
#     makes every set of financials come out in the branded shape regardless
#     of which software fed it.
#   - Accounts BELONG TO AN ENTITY (cap_entityid required). No universal master
#     chart — Harborne Nominees' "MV Expenses" is their account, not a shared one.
#   - cap_sourcecode = their account number/code from the export. Plumbing,
#     backstage, never navigation (house law: codes never surface in UI).
#   - cap_accountclass values ARE the locked statement structure:
#     P&L: Revenue -> COS -> [Gross profit] -> Operating Expenses -> [EBITDA]
#          -> Other Income -> Other Expenses -> Depreciation -> Interest
#          -> [PBT] -> Income Tax Expense -> [PAT]
#     (Subtotals in brackets are COMPUTED, not classes — only postable
#     classifications get a value.)
#     BS:  Current/Non-current Assets, Current/Non-current Liabilities, Equity.
#   - Reclassification history = rules-layer/audit concern, deferred; not a
#     schema fork today.
#
# House style: Stop; ${var} braces before ?; option values pinned.

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
# 1. GLOBAL CHOICE — cap_accountclass (the locked statement structure)
# ---------------------------------------------------------------------------
$gosAll = (Invoke-RestMethod -Uri "$api/GlobalOptionSetDefinitions" -Headers $headers -Method Get).value.Name

if ($gosAll -contains "cap_accountclass") {
    Write-Host "Global choice cap_accountclass already exists - skipping." -ForegroundColor Yellow
} else {
    $options = @(
        # --- P&L, in statement order ---
        @{ v = 100000000; l = "Revenue" }
        @{ v = 100000001; l = "Cost of Sales" }
        @{ v = 100000002; l = "Operating Expenses" }
        @{ v = 100000003; l = "Other Income" }
        @{ v = 100000004; l = "Other Expenses" }
        @{ v = 100000005; l = "Depreciation" }
        @{ v = 100000006; l = "Interest" }
        @{ v = 100000007; l = "Income Tax Expense" }
        # --- Balance sheet ---
        @{ v = 100000008; l = "Current Assets" }
        @{ v = 100000009; l = "Non-current Assets" }
        @{ v = 100000010; l = "Current Liabilities" }
        @{ v = 100000011; l = "Non-current Liabilities" }
        @{ v = 100000012; l = "Equity" }
    )
    $body = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.OptionSetMetadata"
        Name          = "cap_accountclass"
        DisplayName   = New-Label "Account Class"
        IsGlobal      = $true
        OptionSetType = "Picklist"
        Options       = @($options | ForEach-Object { @{ Value = $_.v; Label = New-Label $_.l } })
    } | ConvertTo-Json -Depth 12
    Invoke-RestMethod -Uri "$api/GlobalOptionSetDefinitions" -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host "Created global choice cap_accountclass (13 classes)." -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# 2. TABLE — cap_account
# ---------------------------------------------------------------------------
$tables = (Invoke-RestMethod -Uri "$api/EntityDefinitions?`$select=LogicalName" -Headers $headers -Method Get).value.LogicalName
if ($tables -contains "cap_account") {
    Write-Host "Table cap_account already exists - skipping." -ForegroundColor Yellow
} else {
    $body = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.EntityMetadata"
        SchemaName    = "cap_account"
        DisplayName   = New-Label "Account"
        DisplayCollectionName = New-Label "Accounts"
        Description   = New-Label "Per-entity chart of accounts. Customer's account name verbatim; classification into the practice's locked statement structure is the practice's assertion."
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
                DisplayName   = New-Label "Account Name"
            }
        )
    } | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Uri "$api/EntityDefinitions" -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host "Created table cap_account." -ForegroundColor Green
    Write-Host "  (If the next call fails with 'does not exist' - cache lag. Wait 60s, rerun.)" -ForegroundColor DarkGray
}

# ---------------------------------------------------------------------------
# 3. COLUMNS
# ---------------------------------------------------------------------------
$attrUri  = "$api/EntityDefinitions(LogicalName='cap_account')/Attributes"
$existing = (Invoke-RestMethod -Uri "${attrUri}?`$select=LogicalName" -Headers $headers -Method Get).value.LogicalName

# -- cap_accountclass: bound to the global choice, REQUIRED ------------------
if ($existing -contains "cap_accountclass") {
    Write-Host "cap_accountclass already exists - skipping." -ForegroundColor Yellow
} else {
    $gos = (Invoke-RestMethod -Uri "$api/GlobalOptionSetDefinitions" -Headers $headers -Method Get).value |
           Where-Object { $_.Name -eq "cap_accountclass" }
    $body = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.PicklistAttributeMetadata"
        SchemaName    = "cap_accountclass"
        RequiredLevel = @{ Value = "ApplicationRequired" }
        DisplayName   = New-Label "Account Class"
        "GlobalOptionSet@odata.bind" = "/GlobalOptionSetDefinitions($($gos.MetadataId))"
    } | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Uri $attrUri -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host "Created cap_accountclass (bound to global choice, required)." -ForegroundColor Green
}

# -- cap_sourcecode: their account number/code — plumbing, backstage ---------
if ($existing -contains "cap_sourcecode") {
    Write-Host "cap_sourcecode already exists - skipping." -ForegroundColor Yellow
} else {
    $body = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
        SchemaName    = "cap_sourcecode"
        MaxLength     = 50
        RequiredLevel = @{ Value = "None" }
        Description   = New-Label "The customer's own account number/code from their software. Plumbing only - never navigation."
        DisplayName   = New-Label "Source Code"
    } | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Uri $attrUri -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host "Created cap_sourcecode (their code, backstage)." -ForegroundColor Green
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
# 4. LOOKUP — cap_entityid into cap_entity (REQUIRED: accounts belong to entities)
# ---------------------------------------------------------------------------
$rels = (Invoke-RestMethod -Uri "$api/RelationshipDefinitions?`$select=SchemaName" -Headers $headers -Method Get).value.SchemaName
if ($rels -contains "cap_entity_cap_account") {
    Write-Host "cap_entity_cap_account already exists - skipping." -ForegroundColor Yellow
} else {
    $body = @{
        "@odata.type"     = "Microsoft.Dynamics.CRM.OneToManyRelationshipMetadata"
        SchemaName        = "cap_entity_cap_account"
        ReferencedEntity  = "cap_entity"
        ReferencingEntity = "cap_account"
        Lookup            = @{
            SchemaName    = "cap_entityid"
            RequiredLevel = @{ Value = "ApplicationRequired" }
            DisplayName   = New-Label "Entity"
        }
    } | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Uri "$api/RelationshipDefinitions" -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host "Created cap_entity_cap_account (cap_entityid)." -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# 5. VERIFY
# ---------------------------------------------------------------------------
$after = (Invoke-RestMethod -Uri "${attrUri}?`$select=LogicalName" -Headers $headers -Method Get).value.LogicalName |
         Where-Object { $_ -like "cap_*" } | Sort-Object
Write-Host "`ncap_account cap_ columns now ($($after.Count)):" -ForegroundColor Cyan
$after | ForEach-Object { Write-Host "  $_" }
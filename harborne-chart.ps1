# harborne-chart.ps1 — Harborne Nominees chart of accounts (DATA)
#
# THEIR NAMES, OUR CLASSIFICATIONS made real: 15 accounts as a plausible SMB
# trading company would name them, each classified into the locked statement
# structure. Class values are the PINNED 100000000+ set (cap_accountclass was
# built Block 3, post-convention - unlike Block 1's platform-prefixed
# cap_entitytype, so no probe needed; the values are ours).
#
# Pattern: entity GUID resolved by name (fetch, never assume); rerun-safe per
# account on entity+name; sourcecode carries a fake "their software" code.
#
# Class reference (from 08/08a/08b):
#   100000000 Revenue            100000005 Depreciation & Amortisation
#   100000001 Cost of Sales      100000006 Interest
#   100000002 Operating Expenses 100000007 Income Tax Expense
#   100000008 Current Assets     100000010 Current Liabilities
#   100000009 Non-current Assets 100000011 Non-current Liabilities
#   100000012 Equity             (100000013 Intangible Assets - none in this chart yet)

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

# --- Resolve Harborne Nominees (GUID by name, never assumed) -----------------
$ent = (Invoke-RestMethod -Uri "$api/cap_entities?`$select=cap_entityid,cap_entityname&`$filter=cap_entityname eq 'Harborne Nominees Pty Ltd'" -Headers $headers -Method Get).value
if (-not $ent) { throw "Harborne Nominees Pty Ltd not found - run harborne-entity.ps1 first." }
$entId = $ent[0].cap_entityid
Write-Host "Resolved entity: $($ent[0].cap_entityname) ($entId)" -ForegroundColor Cyan

# --- The chart: their names, our classifications -----------------------------
$chart = @(
    @{ name = "Sales";                     class = 100000000; code = "4-1000" }
    @{ name = "Purchases";                 class = 100000001; code = "5-1000" }
    @{ name = "Wages & Salaries";          class = 100000002; code = "6-1000" }
    @{ name = "Superannuation";            class = 100000002; code = "6-1100" }
    @{ name = "Rent";                      class = 100000002; code = "6-2000" }
    @{ name = "MV Expenses";               class = 100000002; code = "6-3000" }
    @{ name = "Depreciation";              class = 100000005; code = "6-9000" }
    @{ name = "Business Bank Account";     class = 100000008; code = "1-1100" }
    @{ name = "Trade Debtors";             class = 100000008; code = "1-1200" }
    @{ name = "Plant & Equipment";         class = 100000009; code = "1-2100" }
    @{ name = "Accum Depn - Plant";        class = 100000009; code = "1-2150" }
    @{ name = "Trade Creditors";           class = 100000010; code = "2-1100" }
    @{ name = "GST Clearing";              class = 100000010; code = "2-1200" }
    @{ name = "Retained Earnings";         class = 100000012; code = "3-8000" }
    @{ name = "Share Capital";             class = 100000012; code = "3-1000" }
)

# --- Existing accounts for this entity (rerun safety) ------------------------
$existing = (Invoke-RestMethod -Uri "$api/cap_accounts?`$select=cap_name&`$filter=_cap_entityid_value eq $entId" -Headers $headers -Method Get).value.cap_name

foreach ($a in $chart) {
    if ($existing -contains $a.name) {
        Write-Host "$($a.name) already exists - skipping." -ForegroundColor Yellow
        continue
    }
    $body = @{
        cap_name                   = $a.name
        cap_accountclass           = $a.class
        cap_sourcecode             = $a.code
        "cap_entityid@odata.bind"  = "/cap_entities($entId)"
    } | ConvertTo-Json
    Invoke-RestMethod -Uri "$api/cap_accounts" -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host "Created $($a.name) ($($a.code))." -ForegroundColor Green
}

# --- Verify -------------------------------------------------------------------
$rows = (Invoke-RestMethod -Uri "$api/cap_accounts?`$select=cap_name,cap_accountclass,cap_sourcecode&`$filter=_cap_entityid_value eq $entId&`$orderby=cap_sourcecode" -Headers $headers -Method Get).value
Write-Host "`nHarborne chart ($($rows.Count) accounts):" -ForegroundColor Cyan
$rows | Format-Table cap_sourcecode, cap_name, cap_accountclass -AutoSize

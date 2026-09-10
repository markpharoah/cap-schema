# harborne-opening.ps1 — the first journal: locked opening balances (DATA)
#
# THE MOMENT THE BUILD AIMED AT: the first practice assertion. Opening Balance
# type (100000000 - ours, pinned, Block 3). Locked = doctrine: never edited,
# only superseded; the type makes the rows identifiable and protectable.
#
# SIGNED STORAGE ON DISPLAY: debits positive, credits negative. The script
# COMPUTES AND ASSERTS THE ZERO before posting anything - an opening journal
# that doesn't balance refuses to be born. Sum here: +133,500 - 133,500 = 0.
#
# Figures: plausible small trading company at 1 July 2025 (all fictitious,
# Harborne convention). Line date = 2025-07-01 on every line - day-grain;
# the journal's own date is the document date (today's assertion).
#
# Rerun-safe on journal name per entity. Binds lowercase (the $30K lesson's
# cheap cousin, learned at harborne-chart).

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

$journalName = "Opening Balances 1 July 2025 - Harborne Nominees Pty Ltd"
$obDate      = "2025-07-01"

# --- The opening position: signed (Dr +, Cr -) -------------------------------
$lines = @(
    @{ acct = "Business Bank Account"; amount =  45000.00 }
    @{ acct = "Trade Debtors";         amount =  28500.00 }
    @{ acct = "Plant & Equipment";     amount =  60000.00 }
    @{ acct = "Accum Depn - Plant";    amount = -22500.00 }
    @{ acct = "Trade Creditors";       amount = -19300.00 }
    @{ acct = "GST Clearing";          amount =  -4200.00 }
    @{ acct = "Share Capital";         amount =   -100.00 }
    @{ acct = "Retained Earnings";     amount = -87400.00 }
)

# --- THE ZERO-SUM ASSERTION (before anything touches the API) ----------------
$sum = ($lines | Measure-Object -Property amount -Sum).Sum
if ([math]::Abs($sum) -gt 0.005) {
    throw "Opening journal does not balance: sum = $sum. Refusing to post."
}
Write-Host "Zero-sum assertion passed: lines sum to $sum." -ForegroundColor Green

# --- Resolve entity -----------------------------------------------------------
$ent = (Invoke-RestMethod -Uri "$api/cap_entities?`$select=cap_entityid&`$filter=cap_entityname eq 'Harborne Nominees Pty Ltd'" -Headers $headers -Method Get).value
if (-not $ent) { throw "Harborne Nominees Pty Ltd not found - run harborne-entity.ps1 first." }
$entId = $ent[0].cap_entityid
Write-Host "Resolved entity: $entId" -ForegroundColor Cyan

# --- Resolve every account GUID by name (fetch, never assume) ----------------
$accts = (Invoke-RestMethod -Uri "$api/cap_accounts?`$select=cap_accountid,cap_name&`$filter=_cap_entityid_value eq $entId" -Headers $headers -Method Get).value
$acctMap = @{}
foreach ($a in $accts) { $acctMap[$a.cap_name] = $a.cap_accountid }
foreach ($l in $lines) {
    if (-not $acctMap.ContainsKey($l.acct)) { throw "Account '$($l.acct)' not found for entity - run harborne-chart.ps1 first." }
}
Write-Host "Resolved $($acctMap.Count) accounts; all 8 journal accounts present." -ForegroundColor Cyan

# --- Rerun safety: does the journal already exist? ---------------------------
$existing = (Invoke-RestMethod -Uri "$api/cap_journals?`$select=cap_journalid&`$filter=cap_name eq '$journalName'" -Headers $headers -Method Get).value
if ($existing) {
    $jId = $existing[0].cap_journalid
    Write-Host "Journal already exists - skipping create." -ForegroundColor Yellow
} else {
    $jBody = @{
        cap_name                    = $journalName
        cap_journaltype             = 100000000      # Opening Balance (ours, pinned)
        cap_journaldate             = (Get-Date -Format "yyyy-MM-dd")
        cap_description             = "Locked opening position at 1 July 2025. Opening Balance doctrine: never edited, only superseded."
        "cap_entityid@odata.bind"   = "/cap_entities($entId)"
    } | ConvertTo-Json
    $j = Invoke-RestMethod -Uri "$api/cap_journals" -Headers $headers -Method Post -Body $jBody
    # POST returns no body by default; re-fetch for the id
    $jId = ((Invoke-RestMethod -Uri "$api/cap_journals?`$select=cap_journalid&`$filter=cap_name eq '$journalName'" -Headers $headers -Method Get).value)[0].cap_journalid
    Write-Host "Created journal: $journalName" -ForegroundColor Green
}

# --- Lines: rerun-safe on line name within the journal ------------------------
$existingLines = (Invoke-RestMethod -Uri "$api/cap_journallines?`$select=cap_name&`$filter=_cap_journalid_value eq $jId" -Headers $headers -Method Get).value.cap_name

foreach ($l in $lines) {
    $lineName = "OB - $($l.acct)"
    if ($existingLines -contains $lineName) {
        Write-Host "$lineName already exists - skipping." -ForegroundColor Yellow
        continue
    }
    $lBody = @{
        cap_name                        = $lineName
        cap_linedate                    = $obDate
        cap_amount                      = $l.amount
        "cap_journalid@odata.bind"      = "/cap_journals($jId)"
        "cap_accountid@odata.bind"      = "/cap_accounts($($acctMap[$l.acct]))"
    } | ConvertTo-Json
    Invoke-RestMethod -Uri "$api/cap_journallines" -Headers $headers -Method Post -Body $lBody | Out-Null
    Write-Host ("Posted {0}  {1,12:N2}" -f $lineName, $l.amount) -ForegroundColor Green
}

# --- Verify: read the lines back and PROVE the zero from the database --------
$posted = (Invoke-RestMethod -Uri "$api/cap_journallines?`$select=cap_name,cap_amount,cap_linedate&`$filter=_cap_journalid_value eq $jId&`$orderby=cap_amount desc" -Headers $headers -Method Get).value
$dbSum = ($posted | Measure-Object -Property cap_amount -Sum).Sum
Write-Host "`nJournal lines as stored ($($posted.Count) lines, DB sum = $dbSum):" -ForegroundColor Cyan
$posted | Format-Table cap_name, cap_amount, cap_linedate -AutoSize
# harborne-asset.ps1 — the register generates: July depreciation (DATA)
#
# THE LAST UNPROVEN DOCTRINE: system-generated journals. This script is the
# Depreciation journal type's PRODUCER running for the first time:
#   1. Asset row (lean identity): "Plant & Equipment - General" for Harborne.
#   2. ACCOUNTING-book asset event: July depreciation, computed 20% DV
#      monthly on opening WDV: (60,000 - 22,500) x 20% / 12 = 625.00.
#      Event amount NEGATIVE (diminishes the book, ledger convention).
#   3. System journal (type Depreciation, 100000005): Dr Depreciation 625,
#      Cr Accum Depn - Plant 625. Zero-sum by construction.
#   4. THE SUPERSEDE HOOK: the event's cap_journalid points at the journal
#      it spawned. A future regeneration finds ITS OWN journal via this link
#      and supersedes it without touching human assertions. Proven today by
#      existing.
#
# Note the boundary: the EVENT stores the computed outcome (rate/base/period
# in notes - auditable assertion); the JOURNAL carries it into the ledger.
# Tax-book events (pool decline etc) would post NO journal - not run today.

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

$assetName   = "Plant & Equipment - General"
$assetNameQ  = [uri]::EscapeDataString($assetName)
$journalName = "Depreciation Jul 2025 - Harborne Nominees Pty Ltd"
$eventName   = "Depn Jul 2025 - Accounting"
$depnDate    = "2025-07-31"
$charge      = 625.00    # (60,000 - 22,500) x 20% DV / 12

# --- Resolve entity + the two ledger accounts --------------------------------
$ent = (Invoke-RestMethod -Uri "$api/cap_entities?`$select=cap_entityid&`$filter=cap_entityname eq 'Harborne Nominees Pty Ltd'" -Headers $headers -Method Get).value
$entId = $ent[0].cap_entityid
$accts = (Invoke-RestMethod -Uri "$api/cap_accounts?`$select=cap_accountid,cap_name&`$filter=_cap_entityid_value eq $entId" -Headers $headers -Method Get).value
$acctMap = @{}
foreach ($a in $accts) { $acctMap[$a.cap_name] = $a.cap_accountid }
Write-Host "Resolved entity + $($acctMap.Count) accounts." -ForegroundColor Cyan

# --- 1. Asset row (rerun-safe on name + entity) -------------------------------
$asset = (Invoke-RestMethod -Uri "$api/cap_assets?`$select=cap_assetid&`$filter=_cap_entityid_value eq $entId and cap_name eq '$assetNameQ'" -Headers $headers -Method Get).value
if ($asset) {
    $assetId = $asset[0].cap_assetid
    Write-Host "Asset already exists - skipping create." -ForegroundColor Yellow
} else {
    $body = @{
        cap_name                  = $assetName
        cap_notes                 = "Demonstration asset backing the 1-2100/1-2150 ledger balances. Accounting book: 20% DV."
        "cap_entityid@odata.bind" = "/cap_entities($entId)"
    } | ConvertTo-Json
    Invoke-RestMethod -Uri "$api/cap_assets" -Headers $headers -Method Post -Body $body | Out-Null
    $assetId = ((Invoke-RestMethod -Uri "$api/cap_assets?`$select=cap_assetid&`$filter=_cap_entityid_value eq $entId and cap_name eq '$assetNameQ'" -Headers $headers -Method Get).value)[0].cap_assetid
    Write-Host "Created asset: $assetName" -ForegroundColor Green
}

# --- 2. The system journal (rerun-safe on name) -------------------------------
$existing = (Invoke-RestMethod -Uri "$api/cap_journals?`$select=cap_journalid&`$filter=cap_name eq '$journalName'" -Headers $headers -Method Get).value
if ($existing) {
    $jId = $existing[0].cap_journalid
    Write-Host "Journal already exists - skipping create." -ForegroundColor Yellow
} else {
    $jBody = @{
        cap_name                  = $journalName
        cap_journaltype           = 100000005    # Depreciation (system-generated)
        cap_journaldate           = (Get-Date -Format "yyyy-MM-dd")
        cap_description           = "SYSTEM-GENERATED from the asset register. 20% DV monthly on opening WDV 37,500 = 625.00. Superseded only via the register."
        "cap_entityid@odata.bind" = "/cap_entities($entId)"
    } | ConvertTo-Json
    Invoke-RestMethod -Uri "$api/cap_journals" -Headers $headers -Method Post -Body $jBody | Out-Null
    $jId = ((Invoke-RestMethod -Uri "$api/cap_journals?`$select=cap_journalid&`$filter=cap_name eq '$journalName'" -Headers $headers -Method Get).value)[0].cap_journalid
    Write-Host "Created system journal: $journalName" -ForegroundColor Green
}

# --- Journal lines (zero-sum pair, rerun-safe) --------------------------------
$existingLines = (Invoke-RestMethod -Uri "$api/cap_journallines?`$select=cap_name&`$filter=_cap_journalid_value eq $jId" -Headers $headers -Method Get).value.cap_name

$pairs = @(
    @{ name = "DEPN-Jul25-expense"; acct = "Depreciation";      amt =  $charge }
    @{ name = "DEPN-Jul25-accum";   acct = "Accum Depn - Plant"; amt = -$charge }
)
foreach ($p in $pairs) {
    if ($existingLines -contains $p.name) {
        Write-Host "$($p.name) already exists - skipping." -ForegroundColor Yellow
        continue
    }
    $lBody = @{
        cap_name                    = $p.name
        cap_linedate                = $depnDate
        cap_amount                  = $p.amt
        "cap_journalid@odata.bind"  = "/cap_journals($jId)"
        "cap_accountid@odata.bind"  = "/cap_accounts($($acctMap[$p.acct]))"
    } | ConvertTo-Json
    Invoke-RestMethod -Uri "$api/cap_journallines" -Headers $headers -Method Post -Body $lBody | Out-Null
    Write-Host ("Posted {0,-20} {1,10:N2}  {2}" -f $p.name, $p.amt, $p.acct) -ForegroundColor Green
}

# --- 3. The register event, journal-linked (THE SUPERSEDE HOOK) ---------------
$existingEv = (Invoke-RestMethod -Uri "$api/cap_assetevents?`$select=cap_asseteventid&`$filter=_cap_assetid_value eq $assetId and cap_name eq '$eventName'" -Headers $headers -Method Get).value
if ($existingEv) {
    Write-Host "Asset event already exists - skipping." -ForegroundColor Yellow
} else {
    $eBody = @{
        cap_name                    = $eventName
        cap_assetbook               = 100000000    # Accounting
        cap_asseteventtype          = 100000001    # Depreciation
        cap_eventdate               = $depnDate
        cap_amount                  = -$charge
        cap_notes                   = "20% DV monthly. Base: opening WDV 37,500 (cost 60,000 less accum 22,500). Period: Jul 2025. Charge 625.00."
        "cap_assetid@odata.bind"    = "/cap_assets($assetId)"
        "cap_journalid@odata.bind"  = "/cap_journals($jId)"
    } | ConvertTo-Json
    Invoke-RestMethod -Uri "$api/cap_assetevents" -Headers $headers -Method Post -Body $eBody | Out-Null
    Write-Host "Created register event, LINKED to its journal (supersede hook live)." -ForegroundColor Green
}

# --- Verify: journal zero-sum + the linkage -----------------------------------
$posted = (Invoke-RestMethod -Uri "$api/cap_journallines?`$select=cap_amount&`$filter=_cap_journalid_value eq $jId" -Headers $headers -Method Get).value
$dbSum = ($posted | Measure-Object -Property cap_amount -Sum).Sum
$ev = (Invoke-RestMethod -Uri "$api/cap_assetevents?`$select=cap_name,cap_amount,_cap_journalid_value&`$filter=_cap_assetid_value eq $assetId" -Headers $headers -Method Get).value
Write-Host "`nRegister events for asset:" -ForegroundColor Cyan
$ev | ForEach-Object { Write-Host ("  {0}  {1,10:N2}  journal-linked: {2}" -f $_.cap_name, $_.cap_amount, [bool]$_._cap_journalid_value) }
Write-Host "System journal holds $($posted.Count) lines. DB sum = $dbSum" -ForegroundColor $(if ([math]::Abs($dbSum) -lt 0.005) { "Green" } else { "Red" })

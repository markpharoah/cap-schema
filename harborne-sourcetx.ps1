# harborne-sourcetx.ps1 — July cashbook evidence (DATA, verbatim, single-sided)
#
# EVIDENCE DOCTRINE ON DISPLAY:
#   - Rows are the customer's cashbook AS EXPORTED: their dates, their signed
#     amounts (money in +, money out -), their account TEXT with their
#     abbreviations ("Sls Deposits", "M/V Fuel") - deliberately NOT our chart
#     names. Mapping to cap_account is an ASSERTION and happens at posting.
#   - Single-sided: the bank side is implied, as cashbook exports are.
#     Completeness is the journal's job.
#   - cap_importbatch = "HARB-2025-07" tags the load: a botched import is
#     identifiable and supersedable wholesale.
#   - Rerun-safe on (entity + batch + name): rows are named by their position
#     in the export, which is how a real import would key them.

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

$batch = "HARB-2025-07"

# --- July's cashbook, as "their software" exported it ------------------------
# (their text, their signs: receipts +, payments -)
$rows = @(
    @{ n="001"; d="2025-07-02"; amt =  8250.00; acct="Sls Deposits"; ref="EFT sales w/e 28 Jun" }
    @{ n="002"; d="2025-07-03"; amt = -3300.00; acct="Stock Purchases"; ref="Acme Wholesale inv 8841" }
    @{ n="003"; d="2025-07-04"; amt = -1650.00; acct="Rent"; ref="July rent - Bayside Realty" }
    @{ n="004"; d="2025-07-07"; amt =  9460.00; acct="Sls Deposits"; ref="EFT sales w/e 5 Jul" }
    @{ n="005"; d="2025-07-08"; amt = -4180.00; acct="Wages"; ref="Payroll PPE 6 Jul" }
    @{ n="006"; d="2025-07-10"; amt =  -462.00; acct="M/V Fuel"; ref="Shell card statement" }
    @{ n="007"; d="2025-07-14"; amt = 10120.00; acct="Sls Deposits"; ref="EFT sales w/e 12 Jul" }
    @{ n="008"; d="2025-07-15"; amt = -3300.00; acct="Stock Purchases"; ref="Acme Wholesale inv 8902" }
    @{ n="009"; d="2025-07-16"; amt =  -517.00; acct="Super"; ref="Super clearing house Q4 topup" }
    @{ n="010"; d="2025-07-21"; amt =  8890.00; acct="Sls Deposits"; ref="EFT sales w/e 19 Jul" }
    @{ n="011"; d="2025-07-22"; amt = -4180.00; acct="Wages"; ref="Payroll PPE 20 Jul" }
    @{ n="012"; d="2025-07-24"; amt =  -385.00; acct="M/V Fuel"; ref="Shell card statement" }
    @{ n="013"; d="2025-07-28"; amt =  9670.00; acct="Sls Deposits"; ref="EFT sales w/e 26 Jul" }
    @{ n="014"; d="2025-07-29"; amt = -3960.00; acct="Stock Purchases"; ref="Acme Wholesale inv 8967" }
    @{ n="015"; d="2025-07-31"; amt = -2750.00; acct="GST July inst"; ref="ATO EFT - activity stmt" }
)

# --- Resolve entity -----------------------------------------------------------
$ent = (Invoke-RestMethod -Uri "$api/cap_entities?`$select=cap_entityid&`$filter=cap_entityname eq 'Harborne Nominees Pty Ltd'" -Headers $headers -Method Get).value
$entId = $ent[0].cap_entityid
Write-Host "Resolved entity: $entId" -ForegroundColor Cyan

# --- Rerun safety: existing rows in this batch --------------------------------
$existing = (Invoke-RestMethod -Uri "$api/cap_sourcetransactions?`$select=cap_name&`$filter=_cap_entityid_value eq $entId and cap_importbatch eq '$batch'" -Headers $headers -Method Get).value.cap_name

foreach ($r in $rows) {
    $rowName = "$batch-$($r.n)"
    if ($existing -contains $rowName) {
        Write-Host "$rowName already exists - skipping." -ForegroundColor Yellow
        continue
    }
    $body = @{
        cap_name                    = $rowName
        cap_transactiondate         = $r.d
        cap_amount                  = $r.amt
        cap_sourceaccount           = $r.acct
        cap_reference               = $r.ref
        cap_importbatch             = $batch
        "cap_entityid@odata.bind"   = "/cap_entities($entId)"
    } | ConvertTo-Json
    Invoke-RestMethod -Uri "$api/cap_sourcetransactions" -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host ("Loaded {0}  {1}  {2,10:N2}  {3}" -f $rowName, $r.d, $r.amt, $r.acct) -ForegroundColor Green
}

# --- Verify -------------------------------------------------------------------
$loaded = (Invoke-RestMethod -Uri "$api/cap_sourcetransactions?`$select=cap_name,cap_transactiondate,cap_amount,cap_sourceaccount,cap_reference&`$filter=_cap_entityid_value eq $entId and cap_importbatch eq '$batch'&`$orderby=cap_name" -Headers $headers -Method Get).value
$net = ($loaded | Measure-Object -Property cap_amount -Sum).Sum
Write-Host "`nBatch $batch : $($loaded.Count) rows, net movement $("{0:N2}" -f $net) (their bank's July story):" -ForegroundColor Cyan
$loaded | Format-Table cap_name, cap_transactiondate, cap_amount, cap_sourceaccount, cap_reference -AutoSize
# harborne-trialbalance.ps1 — the first report (READ ONLY)
#
# THE REPORTING DOCTRINE, LIVE FOR THE FIRST TIME:
#   - Reads cap_journalline DIRECTLY (the sole reporting source - no posted
#     layer, no data representing data).
#   - Sums signed amounts by account: balance = SUM(amount). That's it.
#   - Dr/Cr is a PROJECTION, computed per row at presentation:
#       Dr = balance if positive; Cr = -balance if negative.
#     One expression. No queries-within-queries. The 80s debate, resolved
#     in two lines of Format-Table.
#   - Date filter: lines to 2025-07-01 - this is "trial balance AS AT",
#     the day-grain promise (any date works; change $asAt and rerun).
#   - GOLDEN RULE HONOURED: no raw negative reaches the screen. Signs live
#     in storage; the report shows Dr and Cr columns like an accountant breathes.

$ErrorActionPreference = "Stop"

$clientId = "bcf0d51c-81f7-40e0-a485-c75ed82a02e3"
$tenantId = "46bc20d5-9c02-426f-b030-aea373177d31"
$envUrl   = "https://org020f7b5c.crm6.dynamics.com"

$token = Get-MsalToken -ClientId $clientId -TenantId $tenantId -Scopes "$envUrl/.default"
$headers = @{ Authorization = "Bearer $($token.AccessToken)"; "OData-MaxVersion"="4.0"; "OData-Version"="4.0" }
$api = "$envUrl/api/data/v9.2"

$asAt = "2025-07-01"

# --- Resolve entity -----------------------------------------------------------
$ent = (Invoke-RestMethod -Uri "$api/cap_entities?`$select=cap_entityid,cap_entityname&`$filter=cap_entityname eq 'Harborne Nominees Pty Ltd'" -Headers $headers -Method Get).value
$entId = $ent[0].cap_entityid

# --- Accounts (names + codes for presentation) --------------------------------
$accts = (Invoke-RestMethod -Uri "$api/cap_accounts?`$select=cap_accountid,cap_name,cap_sourcecode&`$filter=_cap_entityid_value eq $entId" -Headers $headers -Method Get).value
$acctById = @{}
foreach ($a in $accts) { $acctById[$a.cap_accountid] = $a }

# --- THE REPORTING QUERY: lines to date, for this entity's journals -----------
# (journal filter via the journal's entity; expand keeps it one round trip)
$journals = (Invoke-RestMethod -Uri "$api/cap_journals?`$select=cap_journalid&`$filter=_cap_entityid_value eq $entId" -Headers $headers -Method Get).value.cap_journalid
$balances = @{}
foreach ($jId in $journals) {
    $lines = (Invoke-RestMethod -Uri "$api/cap_journallines?`$select=cap_amount,_cap_accountid_value&`$filter=_cap_journalid_value eq $jId and cap_linedate le $asAt" -Headers $headers -Method Get).value
    foreach ($l in $lines) {
        $balances[$l._cap_accountid_value] = ($balances[$l._cap_accountid_value] ?? 0) + $l.cap_amount
    }
}

# --- PRESENT: the Dr/Cr projection --------------------------------------------
Write-Host "`nTRIAL BALANCE - Harborne Nominees Pty Ltd - as at $asAt" -ForegroundColor Cyan
Write-Host ("{0,-8} {1,-28} {2,14} {3,14}" -f "Code","Account","Dr","Cr") -ForegroundColor Cyan
Write-Host ("-" * 68)

$totalDr = 0.0; $totalCr = 0.0
foreach ($id in ($balances.Keys | Sort-Object { $acctById[$_].cap_sourcecode })) {
    $bal = $balances[$id]
    if ([math]::Abs($bal) -lt 0.005) { continue }        # zero balances rest
    $a = $acctById[$id]
    $dr = if ($bal -gt 0) { $bal } else { $null }        # THE projection:
    $cr = if ($bal -lt 0) { -$bal } else { $null }       # one expression each
    if ($dr) { $totalDr += $dr }; if ($cr) { $totalCr += $cr }
    Write-Host ("{0,-8} {1,-28} {2,14} {3,14}" -f $a.cap_sourcecode, $a.cap_name,
        $(if ($dr) { "{0:N2}" -f $dr } else { "" }),
        $(if ($cr) { "{0:N2}" -f $cr } else { "" }))
}

Write-Host ("-" * 68)
Write-Host ("{0,-8} {1,-28} {2,14} {3,14}" -f "", "TOTALS", ("{0:N2}" -f $totalDr), ("{0:N2}" -f $totalCr)) -ForegroundColor $(if ([math]::Abs($totalDr - $totalCr) -lt 0.005) { "Green" } else { "Red" })
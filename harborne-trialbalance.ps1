# harborne-trialbalance.ps1 — trial balance at ANY date (READ ONLY) - v2
#
# v2: -AsAt parameter (defaults 2025-07-01). The day-grain promise as a
# command line: any date, one filter, no rebuild. Run at 07-01 the opening
# stands alone; at 07-31 July's trading appears; at 07-15 you get mid-month
# truth - date-to-date reporting is now a fact, not a design goal.
#
# Doctrine unchanged: reads cap_journalline ONLY; balance = SUM(signed);
# Dr/Cr projected per row; raw negatives never reach the screen.

param(
    [string]$AsAt = "2025-07-01"
)

$ErrorActionPreference = "Stop"

$clientId = "bcf0d51c-81f7-40e0-a485-c75ed82a02e3"
$tenantId = "46bc20d5-9c02-426f-b030-aea373177d31"
$envUrl   = "https://org020f7b5c.crm6.dynamics.com"

$token = Get-MsalToken -ClientId $clientId -TenantId $tenantId -Scopes "$envUrl/.default"
$headers = @{ Authorization = "Bearer $($token.AccessToken)"; "OData-MaxVersion"="4.0"; "OData-Version"="4.0" }
$api = "$envUrl/api/data/v9.2"

# --- Resolve entity -----------------------------------------------------------
$ent = (Invoke-RestMethod -Uri "$api/cap_entities?`$select=cap_entityid,cap_entityname&`$filter=cap_entityname eq 'Harborne Nominees Pty Ltd'" -Headers $headers -Method Get).value
$entId = $ent[0].cap_entityid

# --- Accounts -----------------------------------------------------------------
$accts = (Invoke-RestMethod -Uri "$api/cap_accounts?`$select=cap_accountid,cap_name,cap_sourcecode&`$filter=_cap_entityid_value eq $entId" -Headers $headers -Method Get).value
$acctById = @{}
foreach ($a in $accts) { $acctById[$a.cap_accountid] = $a }

# --- Lines to date, per journal ------------------------------------------------
$journals = (Invoke-RestMethod -Uri "$api/cap_journals?`$select=cap_journalid&`$filter=_cap_entityid_value eq $entId" -Headers $headers -Method Get).value.cap_journalid
$balances = @{}
foreach ($jId in $journals) {
    $lines = (Invoke-RestMethod -Uri "$api/cap_journallines?`$select=cap_amount,_cap_accountid_value&`$filter=_cap_journalid_value eq $jId and cap_linedate le $AsAt" -Headers $headers -Method Get).value
    foreach ($l in $lines) {
        $balances[$l._cap_accountid_value] = ($balances[$l._cap_accountid_value] ?? 0) + $l.cap_amount
    }
}

# --- Present: Dr/Cr projection --------------------------------------------------
Write-Host "`nTRIAL BALANCE - Harborne Nominees Pty Ltd - as at $AsAt" -ForegroundColor Cyan
Write-Host ("{0,-8} {1,-28} {2,14} {3,14}" -f "Code","Account","Dr","Cr") -ForegroundColor Cyan
Write-Host ("-" * 68)

$totalDr = 0.0; $totalCr = 0.0
foreach ($id in ($balances.Keys | Sort-Object { $acctById[$_].cap_sourcecode })) {
    $bal = $balances[$id]
    if ([math]::Abs($bal) -lt 0.005) { continue }
    $a = $acctById[$id]
    $dr = if ($bal -gt 0) { $bal } else { $null }
    $cr = if ($bal -lt 0) { -$bal } else { $null }
    if ($dr) { $totalDr += $dr }; if ($cr) { $totalCr += $cr }
    Write-Host ("{0,-8} {1,-28} {2,14} {3,14}" -f $a.cap_sourcecode, $a.cap_name,
        $(if ($dr) { "{0:N2}" -f $dr } else { "" }),
        $(if ($cr) { "{0:N2}" -f $cr } else { "" }))
}

Write-Host ("-" * 68)
Write-Host ("{0,-8} {1,-28} {2,14} {3,14}" -f "", "TOTALS", ("{0:N2}" -f $totalDr), ("{0:N2}" -f $totalCr)) -ForegroundColor $(if ([math]::Abs($totalDr - $totalCr) -lt 0.005) { "Green" } else { "Red" })
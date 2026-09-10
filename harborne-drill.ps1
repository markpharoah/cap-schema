# harborne-drill.ps1 — THE DRILL WALK (READ ONLY): a figure finds its evidence
#
# The mission sentence, executed: "Every bit of data needs to be able to be
# drilled to a source." Start from the Sales balance on the July TB; walk
# backwards: balance -> the journal lines that compose it -> the evidence
# row each line was asserted from (cap_sourcetransactionid) -> the customer's
# own words (their account text, their reference).
#
# When imports carry document images, one more hop lands on the scan. The
# chain is structural - no matching, no guessing, just lookups.

param(
    [string]$Account = "Sales",
    [string]$AsAt    = "2025-07-31"
)

$ErrorActionPreference = "Stop"

$clientId = "bcf0d51c-81f7-40e0-a485-c75ed82a02e3"
$tenantId = "46bc20d5-9c02-426f-b030-aea373177d31"
$envUrl   = "https://org020f7b5c.crm6.dynamics.com"

$token = Get-MsalToken -ClientId $clientId -TenantId $tenantId -Scopes "$envUrl/.default"
$headers = @{ Authorization = "Bearer $($token.AccessToken)"; "OData-MaxVersion"="4.0"; "OData-Version"="4.0" }
$api = "$envUrl/api/data/v9.2"

# --- Resolve entity + account -------------------------------------------------
$ent = (Invoke-RestMethod -Uri "$api/cap_entities?`$select=cap_entityid&`$filter=cap_entityname eq 'Harborne Nominees Pty Ltd'" -Headers $headers -Method Get).value
$entId = $ent[0].cap_entityid
$acct = (Invoke-RestMethod -Uri "$api/cap_accounts?`$select=cap_accountid,cap_name,cap_sourcecode&`$filter=_cap_entityid_value eq $entId and cap_name eq '$Account'" -Headers $headers -Method Get).value
if (-not $acct) { throw "Account '$Account' not found for entity." }
$acctId = $acct[0].cap_accountid

# --- Level 1: the figure -------------------------------------------------------
$journals = (Invoke-RestMethod -Uri "$api/cap_journals?`$select=cap_journalid,cap_name&`$filter=_cap_entityid_value eq $entId" -Headers $headers -Method Get).value
$jNames = @{}; foreach ($j in $journals) { $jNames[$j.cap_journalid] = $j.cap_name }

$allLines = @()
foreach ($j in $journals) {
    $ls = (Invoke-RestMethod -Uri "$api/cap_journallines?`$select=cap_name,cap_amount,cap_linedate,_cap_journalid_value,_cap_sourcetransactionid_value&`$filter=_cap_journalid_value eq $($j.cap_journalid) and _cap_accountid_value eq $acctId and cap_linedate le $AsAt" -Headers $headers -Method Get).value
    $allLines += $ls
}
$bal = ($allLines | Measure-Object -Property cap_amount -Sum).Sum
$shown = if ($bal -lt 0) { "{0:N2} Cr" -f (-$bal) } else { "{0:N2} Dr" -f $bal }

Write-Host "`n=== DRILL: $($acct[0].cap_sourcecode) $Account as at $AsAt ===" -ForegroundColor Cyan
Write-Host "LEVEL 1 - THE FIGURE:  $shown" -ForegroundColor White

# --- Level 2: the assertions ---------------------------------------------------
Write-Host "`nLEVEL 2 - THE ASSERTIONS ($($allLines.Count) journal lines):" -ForegroundColor White
foreach ($l in ($allLines | Sort-Object cap_linedate)) {
    Write-Host ("  {0}  {1,-18} {2,12:N2}   [{3}]" -f ($l.cap_linedate -split "T")[0], $l.cap_name, $l.cap_amount, $jNames[$l._cap_journalid_value])
}

# --- Level 3: the evidence -----------------------------------------------------
Write-Host "`nLEVEL 3 - THE EVIDENCE (what the customer's own records say):" -ForegroundColor White
foreach ($l in ($allLines | Sort-Object cap_linedate)) {
    if ($l._cap_sourcetransactionid_value) {
        $s = Invoke-RestMethod -Uri "$api/cap_sourcetransactions($($l._cap_sourcetransactionid_value))?`$select=cap_name,cap_transactiondate,cap_amount,cap_sourceaccount,cap_reference,cap_importbatch" -Headers $headers -Method Get
        Write-Host ("  {0} <- {1}  {2}  {3,10:N2}  ""{4}"" / ""{5}""" -f $l.cap_name, $s.cap_name, ($s.cap_transactiondate -split "T")[0], $s.cap_amount, $s.cap_sourceaccount, $s.cap_reference) -ForegroundColor Green
    } else {
        Write-Host ("  {0} <- (no evidence link: {1} - an assertion without imported source, e.g. opening balance)" -f $l.cap_name, $jNames[$l._cap_journalid_value]) -ForegroundColor Yellow
    }
}

Write-Host "`nChain complete: figure -> lines -> customer evidence. When imports carry" -ForegroundColor Cyan
Write-Host "document images, one more hop lands on the scan. Nothing is unexplained." -ForegroundColor Cyan
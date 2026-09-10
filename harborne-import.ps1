# harborne-import.ps1 — THE POSTING: July evidence becomes assertion (DATA)
#
# THE CRUX OF THE MISSION. One Source Import journal (type 100000001) turns
# batch HARB-2025-07 into day-grain journal lines:
#
#   - MAPPING IS THE ASSERTION: their text -> our accounts, declared in the
#     table below. "Sls Deposits" -> Sales is us asserting what their money
#     means. Evidence stays verbatim next door; this is our statement.
#   - GST CARVED OUT: their cashbook is GST-inclusive; our ledger is net +
#     GST Clearing. gst = round(amount/11, 2), net = amount - gst, per row.
#     Wages, super, and the GST instalment itself carry no GST (flagged no).
#   - ZERO-SUM BY CONSTRUCTION, not luck: every source row becomes
#       bank line   = row amount           (their bank movement, verbatim)
#       net line    = -(amount - gst)      (the P&L/BS assertion)
#       gst line    = -gst                 (GST Clearing)   [when GST applies]
#     which sums to zero for every row, therefore for the journal.
#   - DRILL PATH FILLED: every line carries cap_sourcetransactionid back to
#     the evidence row it was asserted from. Figure -> line -> evidence.
#   - Day-grain: line date = the transaction's date. July lives day by day.
#
# Rerun-safe on line names within the journal (SI-<rownum>-<leg>).

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

$batch       = "HARB-2025-07"
$journalName = "Source Import $batch - Harborne Nominees Pty Ltd"

# --- THE MAPPING: their text -> our account, GST treatment -------------------
$map = @{
    "Sls Deposits"    = @{ acct = "Sales";                 gst = $true  }
    "Stock Purchases" = @{ acct = "Purchases";             gst = $true  }
    "Rent"            = @{ acct = "Rent";                  gst = $true  }
    "Wages"           = @{ acct = "Wages & Salaries";      gst = $false }
    "Super"           = @{ acct = "Superannuation";        gst = $false }
    "M/V Fuel"        = @{ acct = "MV Expenses";           gst = $true  }
    "GST July inst"   = @{ acct = "GST Clearing";          gst = $false }
}
$bankAcct = "Business Bank Account"
$gstAcct  = "GST Clearing"

# --- Resolve entity, accounts, evidence --------------------------------------
$ent = (Invoke-RestMethod -Uri "$api/cap_entities?`$select=cap_entityid&`$filter=cap_entityname eq 'Harborne Nominees Pty Ltd'" -Headers $headers -Method Get).value
$entId = $ent[0].cap_entityid

$accts = (Invoke-RestMethod -Uri "$api/cap_accounts?`$select=cap_accountid,cap_name&`$filter=_cap_entityid_value eq $entId" -Headers $headers -Method Get).value
$acctMap = @{}
foreach ($a in $accts) { $acctMap[$a.cap_name] = $a.cap_accountid }

$srcRows = (Invoke-RestMethod -Uri "$api/cap_sourcetransactions?`$select=cap_sourcetransactionid,cap_name,cap_transactiondate,cap_amount,cap_sourceaccount&`$filter=_cap_entityid_value eq $entId and cap_importbatch eq '$batch'&`$orderby=cap_name" -Headers $headers -Method Get).value
if (-not $srcRows) { throw "No evidence rows for batch $batch - run harborne-sourcetx.ps1 first." }
Write-Host "Resolved entity, $($acctMap.Count) accounts, $($srcRows.Count) evidence rows." -ForegroundColor Cyan

# --- Journal (rerun-safe) -----------------------------------------------------
$existing = (Invoke-RestMethod -Uri "$api/cap_journals?`$select=cap_journalid&`$filter=cap_name eq '$journalName'" -Headers $headers -Method Get).value
if ($existing) {
    $jId = $existing[0].cap_journalid
    Write-Host "Journal already exists - skipping create." -ForegroundColor Yellow
} else {
    $jBody = @{
        cap_name                  = $journalName
        cap_journaltype           = 100000001    # Source Import
        cap_journaldate           = (Get-Date -Format "yyyy-MM-dd")
        cap_description           = "Day-grain posting of customer cashbook batch $batch. Mapping and GST treatment are the practice's assertions; evidence linked per line."
        "cap_entityid@odata.bind" = "/cap_entities($entId)"
    } | ConvertTo-Json
    Invoke-RestMethod -Uri "$api/cap_journals" -Headers $headers -Method Post -Body $jBody | Out-Null
    $jId = ((Invoke-RestMethod -Uri "$api/cap_journals?`$select=cap_journalid&`$filter=cap_name eq '$journalName'" -Headers $headers -Method Get).value)[0].cap_journalid
    Write-Host "Created journal: $journalName" -ForegroundColor Green
}

$existingLines = (Invoke-RestMethod -Uri "$api/cap_journallines?`$select=cap_name&`$filter=_cap_journalid_value eq $jId" -Headers $headers -Method Get).value.cap_name

function Post-Line {
    param($Name, $Date, $Amount, $AcctName, $SrcId)
    if ($existingLines -contains $Name) {
        Write-Host "$Name already exists - skipping." -ForegroundColor Yellow
        return
    }
    $body = @{
        cap_name                              = $Name
        cap_linedate                          = $Date
        cap_amount                            = $Amount
        "cap_journalid@odata.bind"            = "/cap_journals($jId)"
        "cap_accountid@odata.bind"            = "/cap_accounts($($acctMap[$AcctName]))"
        "cap_sourcetransactionid@odata.bind"  = "/cap_sourcetransactions($SrcId)"
    } | ConvertTo-Json
    Invoke-RestMethod -Uri "$api/cap_journallines" -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host ("Posted {0,-22} {1,10:N2}  {2}" -f $Name, $Amount, $AcctName) -ForegroundColor Green
}

# --- THE POSTING LOOP ----------------------------------------------------------
foreach ($s in $srcRows) {
    $m = $map[$s.cap_sourceaccount]
    if (-not $m) { throw "No mapping for source account text '$($s.cap_sourceaccount)' - mapping table incomplete." }
    $rowN = $s.cap_name -replace "^$batch-", ""
    $amt  = [decimal]$s.cap_amount
    $d    = ($s.cap_transactiondate -split "T")[0]
    $sid  = $s.cap_sourcetransactionid

    $gst = if ($m.gst) { [math]::Round($amt / 11, 2) } else { 0 }
    $net = $amt - $gst

    # bank leg: their movement verbatim
    Post-Line -Name "SI-$rowN-bank" -Date $d -Amount $amt -AcctName $bankAcct -SrcId $sid
    # net leg: the assertion (opposite sign)
    Post-Line -Name "SI-$rowN-net"  -Date $d -Amount (-$net) -AcctName $m.acct -SrcId $sid
    # gst leg where applicable
    if ($m.gst) {
        Post-Line -Name "SI-$rowN-gst" -Date $d -Amount (-$gst) -AcctName $gstAcct -SrcId $sid
    }
}

# --- Verify: DB zero-sum + line count -----------------------------------------
$posted = (Invoke-RestMethod -Uri "$api/cap_journallines?`$select=cap_amount&`$filter=_cap_journalid_value eq $jId" -Headers $headers -Method Get).value
$dbSum = ($posted | Measure-Object -Property cap_amount -Sum).Sum
$verdict = if ([math]::Abs($dbSum) -lt 0.005) { "Green" } else { "Red" }
Write-Host "`nJournal now holds $($posted.Count) lines. DB sum = $dbSum" -ForegroundColor $verdict
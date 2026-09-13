# 25-taxonly-review.ps1 — the 64 Tax Only: who is actually current? (ANALYSIS)
#
# All 64 are Active by LodgeIT's archive flag - but "current" is a
# LODGEMENT question. Join to the ATO ITR export (data\report*.csv,
# TFN + per-year statuses + Last Year Lodged) and classify:
#   CURRENT  = Last Year Lodged >= 2024
#   LAPSED   = lodged before 2024 (on program, gone quiet)
#   NOT ON PROGRAM = no TFN match in the ATO export (or TFN suppressed)
# Output: console + data\taxonly-review.csv for margin notes.
# READ-ONLY against Dataverse.

$ErrorActionPreference = "Stop"

$clientId = "bcf0d51c-81f7-40e0-a485-c75ed82a02e3"
$tenantId = "46bc20d5-9c02-426f-b030-aea373177d31"
$envUrl   = "https://org020f7b5c.crm6.dynamics.com"

$token = Get-MsalToken -ClientId $clientId -TenantId $tenantId -Scopes "$envUrl/.default"
$headers = @{ Authorization = "Bearer $($token.AccessToken)"; "OData-MaxVersion" = "4.0"; "OData-Version" = "4.0" }
$api = "$envUrl/api/data/v9.2"

# --- The 64: Tax Only engagements -> their entities ---------------------------------
$TAXONLY = 100000010
$rows = New-Object System.Collections.Generic.List[object]
$url = "$api/cap_engagements?`$select=cap_name&`$filter=cap_engagementtype eq $TAXONLY&`$expand=cap_entityid(`$select=cap_clientcode,cap_entityname,cap_tfn)"
do {
    $page = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
    foreach ($g in $page.value) {
        $ent = $g.cap_entityid
        $rows.Add([pscustomobject]@{ Code=$ent.cap_clientcode; Name=$ent.cap_entityname; TFN=$ent.cap_tfn })
    }
    $url = $page.'@odata.nextLink'
} while ($url)
Write-Host "Tax Only engagements: $($rows.Count)" -ForegroundColor Cyan

# --- ATO ITR export (TFN, statuses, Last Year Lodged) -------------------------------
$itrFile = Get-ChildItem .\data\report*.csv | Sort-Object Length -Descending | Select-Object -First 1
Write-Host "ATO export: $($itrFile.Name)" -ForegroundColor Cyan
$itr = Import-Csv $itrFile.FullName
$byTfn = @{}
foreach ($r in $itr) { if ($r.TFN) { $byTfn[$r.TFN.Trim()] = $r } }

# --- Classify ------------------------------------------------------------------------
$out = foreach ($r in $rows) {
    $cls = "NOT ON PROGRAM"; $lyl = ""; $s26 = ""
    if ($r.TFN -and $byTfn.ContainsKey($r.TFN.Trim())) {
        $m = $byTfn[$r.TFN.Trim()]
        $lyl = $m.'Last Year Lodged'
        $s26 = $m.'2026 Status'
        $cls = if ([int]($lyl ?? 0) -ge 2024) { "CURRENT" } else { "LAPSED" }
    } elseif (-not $r.TFN) { $cls = "NO TFN (dup-suppressed?)" }
    [pscustomobject]@{ Class=$cls; Code=$r.Code; Name=$r.Name; LastLodged=$lyl; Status2026=$s26 }
}
$out | Sort-Object Class, Name | Format-Table -AutoSize
$out | Sort-Object Class, Name | Export-Csv .\data\taxonly-review.csv -NoTypeInformation
Write-Host "`nSummary:" -ForegroundColor Cyan
$out | Group-Object Class | Sort-Object Count -Descending | ForEach-Object { Write-Host ("  {0,-24} {1}" -f $_.Name, $_.Count) }
Write-Host "Written: data\taxonly-review.csv" -ForegroundColor Green
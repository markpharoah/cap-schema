# 00-verify.ps1 — CAP schema baseline assertion (v2, end of Block 4)
#
# v1 LISTED the schema; v2 ASSERTS it. The expected baseline below is the
# truth as committed across Blocks 1-4 (17 tables, 13 global choices, column
# counts per the session records). Any drift prints RED and the script exits
# nonzero. Run at every session open; extend the table when schema grows.
#
# READ-ONLY. Unnumbered would be tradition for probes, but 00 keeps its
# session-open name: this IS the session-open drill.

$ErrorActionPreference = "Stop"

$clientId = "bcf0d51c-81f7-40e0-a485-c75ed82a02e3"
$tenantId = "46bc20d5-9c02-426f-b030-aea373177d31"
$envUrl   = "https://org020f7b5c.crm6.dynamics.com"

$token = Get-MsalToken -ClientId $clientId -TenantId $tenantId -Scopes "$envUrl/.default"
$headers = @{ Authorization = "Bearer $($token.AccessToken)"; "OData-MaxVersion"="4.0"; "OData-Version"="4.0" }
$api = "$envUrl/api/data/v9.2"

$fail = 0

# --- Expected baseline (end of Block 4) -------------------------------------
$expectedChoices = @(
    "cap_accountclass","cap_assetbook","cap_asseteventtype","cap_engagementtype",
    "cap_entitystatus","cap_entitytype","cap_financecontracttype","cap_groupstatus",
    "cap_journaltype","cap_pooleventtype","cap_regulatorycapacity",
    "cap_relationshiptype","cap_roletype"
)

$expectedTables = [ordered]@{
    "cap_account"             = 8
    "cap_asset"               = 6
    "cap_assetevent"          = 13
    "cap_country"             = 6
    "cap_engagement"          = 11
    "cap_entity"              = 15
    "cap_entityrelationship"  = 11
    "cap_entityrole"          = 12
    "cap_financecontract"     = 15
    "cap_financescheduleline" = 10
    "cap_group"               = 5
    "cap_journal"             = 10
    "cap_journalline"         = 11
    "cap_person"              = 9
    "cap_pool"                = 5
    "cap_poolevent"           = 9
    "cap_sourcetransaction"   = 9
}

# --- Choices -----------------------------------------------------------------
Write-Host "`n--- Global choices (expect $($expectedChoices.Count)) ---" -ForegroundColor Cyan
$gos = (Invoke-RestMethod -Uri "$api/GlobalOptionSetDefinitions" -Headers $headers -Method Get).value.Name |
       Where-Object { $_ -like "cap_*" }
foreach ($c in $expectedChoices) {
    if ($gos -contains $c) {
        Write-Host "  OK  $c" -ForegroundColor Green
    } else {
        Write-Host "  MISSING  $c" -ForegroundColor Red; $fail++
    }
}
$unexpectedChoices = $gos | Where-Object { $expectedChoices -notcontains $_ }
foreach ($u in $unexpectedChoices) {
    Write-Host "  UNEXPECTED  $u (not in baseline - schema drift or baseline needs updating)" -ForegroundColor Red; $fail++
}

# --- Tables ------------------------------------------------------------------
Write-Host "`n--- Tables (expect $($expectedTables.Count)) ---" -ForegroundColor Cyan
$allTables = (Invoke-RestMethod -Uri "$api/EntityDefinitions?`$select=LogicalName" -Headers $headers -Method Get).value.LogicalName |
             Where-Object { $_ -like "cap_*" }
foreach ($t in $expectedTables.Keys) {
    if ($allTables -notcontains $t) {
        Write-Host "  MISSING  $t" -ForegroundColor Red; $fail++
        continue
    }
    $cols = (Invoke-RestMethod -Uri "$api/EntityDefinitions(LogicalName='$t')/Attributes?`$select=LogicalName" -Headers $headers -Method Get).value.LogicalName |
            Where-Object { $_ -like "cap_*" }
    $n = ($cols | Measure-Object).Count
    $want = $expectedTables[$t]
    if ($n -eq $want) {
        Write-Host ("  OK  {0}  ({1} cap_ columns)" -f $t, $n) -ForegroundColor Green
    } else {
        Write-Host ("  DRIFT  {0}  expected {1} cap_ columns, found {2}" -f $t, $want, $n) -ForegroundColor Red; $fail++
    }
}
$unexpectedTables = $allTables | Where-Object { $expectedTables.Keys -notcontains $_ }
foreach ($u in $unexpectedTables) {
    Write-Host "  UNEXPECTED  $u (not in baseline)" -ForegroundColor Red; $fail++
}

# --- Verdict -----------------------------------------------------------------
if ($fail -eq 0) {
    Write-Host "`nBASELINE HOLDS: 17 tables, 13 choices, all column counts match." -ForegroundColor Green
} else {
    Write-Host "`nBASELINE BROKEN: $fail issue(s) above. Do not build until explained." -ForegroundColor Red
    exit 1 }
# 08b-intangibles-class.ps1 — add "Intangible Assets" to cap_accountclass
#
# WHY (Mark's argument, conceded on the second pass): intangibles behave
# differently on statements — they amortise not depreciate, they never enter
# the fixed asset register (cap_asset = physical, effective-life assets), and
# conventional presentation groups them separately within non-current assets.
# If the class can't tell goodwill from a motor vehicle, the statement engine
# must inspect account NAMES to group the balance sheet — exactly the chaos
# classification exists to prevent. Class test refined: a class is needed when
# the statement GROUPS it separately, not only when it subtotals separately.
#
# API pattern: add an option to an existing global choice via the
# InsertOptionValue ACTION. Value pinned: 100000013.

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

# --- Check current options ---------------------------------------------------
$gos  = (Invoke-RestMethod -Uri "$api/GlobalOptionSetDefinitions" -Headers $headers -Method Get).value |
        Where-Object { $_.Name -eq "cap_accountclass" }
$full = Invoke-RestMethod -Uri "$api/GlobalOptionSetDefinitions($($gos.MetadataId))" -Headers $headers -Method Get
$values = $full.Options.Value

if ($values -contains 100000013) {
    Write-Host "Option 100000013 already exists - skipping." -ForegroundColor Yellow
} else {
    $body = @{
        OptionSetName = "cap_accountclass"
        Value         = 100000013
        Label         = @{ LocalizedLabels = @(@{ Label = "Intangible Assets"; LanguageCode = 1033 }) }
    } | ConvertTo-Json -Depth 8
    Invoke-RestMethod -Uri "$api/InsertOptionValue" -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host "Added 'Intangible Assets' (100000013) to cap_accountclass." -ForegroundColor Green
}

# --- Verify: full class list -------------------------------------------------
$full2 = Invoke-RestMethod -Uri "$api/GlobalOptionSetDefinitions($($gos.MetadataId))" -Headers $headers -Method Get
Write-Host "`ncap_accountclass options now ($($full2.Options.Count)):" -ForegroundColor Cyan
$full2.Options | ForEach-Object { Write-Host ("  {0}  {1}" -f $_.Value, $_.Label.UserLocalizedLabel.Label) }
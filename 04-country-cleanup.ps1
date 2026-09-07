# 04-country-cleanup.ps1 — remove the double-prefix fossil from cap_country
#
# WHY: cap_country carries cap_cap_currencycode — a column created with "cap_"
# already typed into the schema name, so the publisher prefix stacked twice.
# It duplicates cap_defaultcurrencycode. Table has zero rows, so deletion is
# free today; left alone it becomes a permanent "which currency field is real?"
# trap for every future reader.
#
# Rerun-safe: checks the column exists before deleting; yellow skip if already gone.

$clientId = "bcf0d51c-81f7-40e0-a485-c75ed82a02e3"
$tenantId = "46bc20d5-9c02-426f-b030-aea373177d31"
$envUrl   = "https://org020f7b5c.crm6.dynamics.com"

$token = Get-MsalToken -ClientId $clientId -TenantId $tenantId -Scopes "$envUrl/.default"
$headers = @{ Authorization = "Bearer $($token.AccessToken)"; "OData-MaxVersion"="4.0"; "OData-Version"="4.0" }

# --- Existence check (client-side filter; startswith unsupported on metadata) ---
$uri = "$envUrl/api/data/v9.2/EntityDefinitions(LogicalName='cap_country')/Attributes?`$select=LogicalName"
$existing = (Invoke-RestMethod -Uri $uri -Headers $headers -Method Get).value.LogicalName

if ($existing -contains "cap_cap_currencycode") {
    $delUri = "$envUrl/api/data/v9.2/EntityDefinitions(LogicalName='cap_country')/Attributes(LogicalName='cap_cap_currencycode')"
    Invoke-RestMethod -Uri $delUri -Headers $headers -Method Delete | Out-Null
    Write-Host "Deleted cap_cap_currencycode from cap_country." -ForegroundColor Green
} else {
    Write-Host "cap_cap_currencycode not found - already gone, skipping." -ForegroundColor Yellow
}

# --- Verify: list remaining cap_ columns ---
$after = (Invoke-RestMethod -Uri $uri -Headers $headers -Method Get).value.LogicalName |
         Where-Object { $_ -like "cap_*" } | Sort-Object
Write-Host "`ncap_country columns now:" -ForegroundColor Cyan
$after | ForEach-Object { Write-Host "  $_" }
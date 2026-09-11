# probe-rels.ps1 — read-only probe before the relationship seed.
# 1) cap_entityrelationship column names (lookups bind by logical name - never guess)
# 2) rels-clean.csv headers (we name the type column by eye, not by regex)
$ErrorActionPreference = "Stop"

$clientId = "bcf0d51c-81f7-40e0-a485-c75ed82a02e3"
$tenantId = "46bc20d5-9c02-426f-b030-aea373177d31"
$envUrl   = "https://org020f7b5c.crm6.dynamics.com"

$token = Get-MsalToken -ClientId $clientId -TenantId $tenantId -Scopes "$envUrl/.default"
$headers = @{ Authorization = "Bearer $($token.AccessToken)"; "OData-MaxVersion" = "4.0"; "OData-Version" = "4.0" }
$api = "$envUrl/api/data/v9.2"

# --- 1) Dataverse columns -------------------------------------------------------
$attrs = (Invoke-RestMethod -Uri "$api/EntityDefinitions(LogicalName='cap_entityrelationship')/Attributes" -Headers $headers -Method Get).value
Write-Host "cap_entityrelationship columns (cap_* only):" -ForegroundColor Cyan
$attrs | Where-Object { $_.LogicalName -like "cap_*" } | Sort-Object LogicalName | ForEach-Object {
    Write-Host ("  {0}  [{1}]" -f $_.LogicalName, $_.AttributeType)
}

# --- 2) CSV headers --------------------------------------------------------------
$rels = Import-Csv .\data\rels-clean.csv
Write-Host "`nrels-clean.csv: $($rels.Count) rows. Headers:" -ForegroundColor Cyan
$rels[0].PSObject.Properties.Name | ForEach-Object { Write-Host "  $_" }
Write-Host "`nTell Claude the header names above; the type column gets named explicitly in the seed." -ForegroundColor Yellow
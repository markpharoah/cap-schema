# probe-country.ps1 — READ ONLY
# Purpose: list cap_country's actual cap_ columns so the seed script
# uses real schema names, not guesses. No writes; not numbered; no commit needed.
# v2: $select trimmed to LogicalName + AttributeType only — MaxLength lives
# on StringAttributeMetadata, not the base type, and $select on /Attributes
# may only name properties shared by every attribute type (0x80060888 taught us that).

$clientId = "bcf0d51c-81f7-40e0-a485-c75ed82a02e3"
$tenantId = "46bc20d5-9c02-426f-b030-aea373177d31"
$envUrl   = "https://org020f7b5c.crm6.dynamics.com"

$token = Get-MsalToken -ClientId $clientId -TenantId $tenantId -Scopes "$envUrl/.default"
$headers = @{ Authorization = "Bearer $($token.AccessToken)"; "OData-MaxVersion"="4.0"; "OData-Version"="4.0" }

# All attributes of cap_country; filter client-side (startswith unsupported on metadata)
$uri = "$envUrl/api/data/v9.2/EntityDefinitions(LogicalName='cap_country')/Attributes" +
       "?`$select=LogicalName,AttributeType"
$attrs = (Invoke-RestMethod -Uri $uri -Headers $headers -Method Get).value |
         Where-Object { $_.LogicalName -like "cap_*" }

Write-Host "`n--- cap_country columns ---" -ForegroundColor Cyan
$attrs | Sort-Object LogicalName | Format-Table LogicalName, AttributeType -AutoSize
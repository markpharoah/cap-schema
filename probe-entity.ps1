# probe-entity.ps1 — READ ONLY
# WHY: harborne-entity.ps1 assumed cap_entity's primary name is cap_name.
# The API says no such property. cap_entity is Block 1 vintage - built before
# the cap_name convention settled. List its real columns; while we're at it,
# print the entitytype choice values so THAT assumption gets checked too.

$ErrorActionPreference = "Stop"

$clientId = "bcf0d51c-81f7-40e0-a485-c75ed82a02e3"
$tenantId = "46bc20d5-9c02-426f-b030-aea373177d31"
$envUrl   = "https://org020f7b5c.crm6.dynamics.com"

$token = Get-MsalToken -ClientId $clientId -TenantId $tenantId -Scopes "$envUrl/.default"
$headers = @{ Authorization = "Bearer $($token.AccessToken)"; "OData-MaxVersion"="4.0"; "OData-Version"="4.0" }
$api = "$envUrl/api/data/v9.2"

# --- Real columns on cap_entity ---------------------------------------------
$attrs = (Invoke-RestMethod -Uri "$api/EntityDefinitions(LogicalName='cap_entity')/Attributes?`$select=LogicalName,AttributeType" -Headers $headers -Method Get).value |
         Where-Object { $_.LogicalName -like "cap_*" }
Write-Host "`n--- cap_entity columns ---" -ForegroundColor Cyan
$attrs | Sort-Object LogicalName | Format-Table LogicalName, AttributeType -AutoSize

# --- Which one is the primary name? ------------------------------------------
$meta = Invoke-RestMethod -Uri "$api/EntityDefinitions(LogicalName='cap_entity')?`$select=PrimaryNameAttribute" -Headers $headers -Method Get
Write-Host "Primary name attribute: $($meta.PrimaryNameAttribute)" -ForegroundColor Green

# --- cap_entitytype choice values (check the 100000001=Company assumption) ---
$gos  = (Invoke-RestMethod -Uri "$api/GlobalOptionSetDefinitions" -Headers $headers -Method Get).value |
        Where-Object { $_.Name -eq "cap_entitytype" }
$full = Invoke-RestMethod -Uri "$api/GlobalOptionSetDefinitions($($gos.MetadataId))" -Headers $headers -Method Get
Write-Host "`ncap_entitytype options:" -ForegroundColor Cyan
$full.Options | ForEach-Object { Write-Host ("  {0}  {1}" -f $_.Value, $_.Label.UserLocalizedLabel.Label) }


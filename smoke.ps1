$ClientId = "bcf0d51c-81f7-40e0-a485-c75ed82a02e3"
$EnvUrl   = "https://org020f7b5c.crm6.dynamics.com"
$TenantId = "46bc20d5-9c02-426f-b030-aea373177d31"

[Environment]::SetEnvironmentVariable("PNPPOWERSHELL_CLIENTID", $ClientId, "User")

Import-Module MSAL.PS

$token = Get-MsalToken -ClientId $ClientId -TenantId $TenantId -Scopes "$EnvUrl/user_impersonation" -Interactive
$hdr = @{ Authorization = "Bearer $($token.AccessToken)"; Accept = "application/json" }

$r = Invoke-RestMethod -Uri "$EnvUrl/api/data/v9.2/EntityDefinitions?`$select=SchemaName,LogicalName" -Headers $hdr

Write-Host "Connected. cap_ tables visible:" -ForegroundColor Green
$r.value | Where-Object { $_.LogicalName -like "cap_*" } | ForEach-Object { Write-Host "  $($_.SchemaName)" }
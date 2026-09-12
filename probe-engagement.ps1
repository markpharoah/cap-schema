# probe-engagement.ps1 — read-only: existing cap_engagementtype options +
# cap_engagement columns. Pre-week choice found at designer values (100000000+);
# adopt reality, never renumber. Probe before assuming - now formally
# extended from tables to CHOICES.
$ErrorActionPreference = "Stop"

$clientId = "bcf0d51c-81f7-40e0-a485-c75ed82a02e3"
$tenantId = "46bc20d5-9c02-426f-b030-aea373177d31"
$envUrl   = "https://org020f7b5c.crm6.dynamics.com"

$token = Get-MsalToken -ClientId $clientId -TenantId $tenantId -Scopes "$envUrl/.default"
$headers = @{ Authorization = "Bearer $($token.AccessToken)"; "OData-MaxVersion" = "4.0"; "OData-Version" = "4.0" }
$api = "$envUrl/api/data/v9.2"

$set = Invoke-RestMethod -Uri "$api/GlobalOptionSetDefinitions(Name='cap_engagementtype')" -Headers $headers -Method Get
Write-Host "cap_engagementtype options ($($set.Options.Count)):" -ForegroundColor Cyan
$set.Options | Sort-Object Value | ForEach-Object {
    Write-Host ("  {0}  {1}" -f $_.Value, $_.Label.UserLocalizedLabel.Label)
}

Write-Host "`ncap_engagement cap_* columns:" -ForegroundColor Cyan
$attrs = (Invoke-RestMethod -Uri "$api/EntityDefinitions(LogicalName='cap_engagement')/Attributes?`$select=LogicalName,AttributeType" -Headers $headers -Method Get).value
$attrs | Where-Object { $_.LogicalName -like "cap_*" } | Sort-Object LogicalName | ForEach-Object {
    Write-Host ("  {0}  [{1}]" -f $_.LogicalName, $_.AttributeType)
}
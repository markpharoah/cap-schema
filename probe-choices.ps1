# probe-choices.ps1 — READ ONLY
# WHY: the seed loaders need cap_entitystatus (tombstone marker home) and
# cap_relationshiptype (vocabulary to extend for LodgeIT's edge types).
# Both are Block 1 vintage: platform-prefixed values, contents unknown.
# Probe before write - two vendors taught us encodings; Block 1 taught us
# values.

$ErrorActionPreference = "Stop"

$clientId = "bcf0d51c-81f7-40e0-a485-c75ed82a02e3"
$tenantId = "46bc20d5-9c02-426f-b030-aea373177d31"
$envUrl   = "https://org020f7b5c.crm6.dynamics.com"

$token = Get-MsalToken -ClientId $clientId -TenantId $tenantId -Scopes "$envUrl/.default"
$headers = @{ Authorization = "Bearer $($token.AccessToken)"; "OData-MaxVersion"="4.0"; "OData-Version"="4.0" }
$api = "$envUrl/api/data/v9.2"

foreach ($name in @("cap_entitystatus","cap_relationshiptype")) {
    $gos  = (Invoke-RestMethod -Uri "$api/GlobalOptionSetDefinitions" -Headers $headers -Method Get).value |
            Where-Object { $_.Name -eq $name }
    $full = Invoke-RestMethod -Uri "$api/GlobalOptionSetDefinitions($($gos.MetadataId))" -Headers $headers -Method Get
    Write-Host "`n$name options ($($full.Options.Count)):" -ForegroundColor Cyan
    $full.Options | ForEach-Object { Write-Host ("  {0}  {1}" -f $_.Value, $_.Label.UserLocalizedLabel.Label) }
}
# verify-entities.ps1 — count entity rows by status. Read-only.
# Null-key fix: coalesce the KEY before indexing (hashtables reject $null keys).
$ErrorActionPreference = "Stop"

$clientId = "bcf0d51c-81f7-40e0-a485-c75ed82a02e3"
$tenantId = "46bc20d5-9c02-426f-b030-aea373177d31"
$envUrl   = "https://org020f7b5c.crm6.dynamics.com"

$token = Get-MsalToken -ClientId $clientId -TenantId $tenantId -Scopes "$envUrl/.default"
$headers = @{
    Authorization      = "Bearer $($token.AccessToken)"
    "OData-MaxVersion" = "4.0"
    "OData-Version"    = "4.0"
}
$api = "$envUrl/api/data/v9.2"

$counts = @{}; $total = 0
$url = "$api/cap_entities?`$select=cap_status"
do {
    $page = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
    foreach ($e in $page.value) {
        $key = if ($null -eq $e.cap_status) { "(none)" } else { [string]$e.cap_status }
        $counts[$key] = ($counts[$key] ?? 0) + 1
        $total++
    }
    $url = $page.'@odata.nextLink'
} while ($url)

Write-Host "Entity rows by status (764820000=Active, 764820003=Former, (none)=Harborne):" -ForegroundColor Cyan
$counts.GetEnumerator() | Sort-Object Key | ForEach-Object { Write-Host ("  {0}  {1}" -f $_.Key, $_.Value) }
Write-Host "TOTAL: $total" -ForegroundColor Green
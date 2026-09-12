# probe-forms.ps1 — read-only: main form contents for engagement + entity.
# Form layout lives in systemform.formxml; we read field lists before
# touching anything (first form-metadata work - probe, never assume).
$ErrorActionPreference = "Stop"
$clientId = "bcf0d51c-81f7-40e0-a485-c75ed82a02e3"
$tenantId = "46bc20d5-9c02-426f-b030-aea373177d31"
$envUrl   = "https://org020f7b5c.crm6.dynamics.com"
$token = Get-MsalToken -ClientId $clientId -TenantId $tenantId -Scopes "$envUrl/.default"
$headers = @{ Authorization = "Bearer $($token.AccessToken)"; "OData-MaxVersion" = "4.0"; "OData-Version" = "4.0" }
$api = "$envUrl/api/data/v9.2"

foreach ($tbl in @("cap_engagement","cap_entity","cap_job","cap_task")) {
    $forms = (Invoke-RestMethod -Uri "$api/systemforms?`$select=name,type,formid&`$filter=objecttypecode eq '$tbl' and type eq 2" -Headers $headers -Method Get).value
    foreach ($f in $forms) {
        $xml = [xml]((Invoke-RestMethod -Uri "$api/systemforms($($f.formid))?`$select=formxml" -Headers $headers -Method Get).formxml)
        $fields = $xml.SelectNodes("//control[@datafieldname]") | ForEach-Object { $_.datafieldname } | Sort-Object -Unique
        Write-Host "`n$tbl / '$($f.name)' (main form):" -ForegroundColor Cyan
        $fields | ForEach-Object { Write-Host "  $_" }
    }
}
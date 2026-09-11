# seed-practice-entity.ps1 — the practice's own trust as a NORMAL entity (DATA)
# LodgeIT holds it as special head record #CAS; CAP holds it as entity row like
# any other. clientcode = CAS (faithful LodgeIT sync key; legacy shape accepted).
# After this, rerun seed-relationships.ps1 - the two skipped edges land via retry.
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

# Rerun-safe: existence check on clientcode CAS
$hit = (Invoke-RestMethod -Uri "$api/cap_entities?`$select=cap_entityid&`$filter=cap_clientcode eq 'CAS'" -Headers $headers -Method Get).value
if ($hit.Count -gt 0) { Write-Host "CAS already exists - nothing to do." -ForegroundColor Yellow; exit 0 }

$au = (Invoke-RestMethod -Uri "$api/cap_countries?`$select=cap_countryid&`$filter=cap_isoalpha2 eq 'AU'" -Headers $headers -Method Get).value
$body = @{
    cap_entityname             = "Commercial Accounting"   # LodgeIT's name for the trust
    cap_clientcode             = "CAS"
    cap_type                   = 764820002                  # Trust
    cap_status                 = 764820000                  # Active
    cap_tfn                    = "70791924"
    cap_abn                    = "86079712975"
    "cap_countryid@odata.bind" = "/cap_countries($($au[0].cap_countryid))"
}
Invoke-RestMethod -Uri "$api/cap_entities" -Headers $headers -Method Post -Body ($body | ConvertTo-Json) | Out-Null

# VERIFY (silence after writes is not success)
$hit = (Invoke-RestMethod -Uri "$api/cap_entities?`$select=cap_entityname,cap_clientcode&`$filter=cap_clientcode eq 'CAS'" -Headers $headers -Method Get).value
if ($hit.Count -eq 1) { Write-Host "Created: $($hit[0].cap_entityname) [CAS]" -ForegroundColor Green }
else { Write-Host "VERIFY FAILED - CAS not found after create." -ForegroundColor Red; exit 1 }
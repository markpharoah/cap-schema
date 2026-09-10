# harborne-entity.ps1 — first demonstration entity (DATA, not schema) - v2
#
# v2 CORRECTIONS (probe-entity told the Block 1 truth):
#   - Primary name is cap_entityname, NOT cap_name (that convention arrived Block 2)
#   - Type column is cap_type; Block 1 choice values are PLATFORM-prefixed
#     (764820000+), not pinned 100000000+. Company = 764820001.
#   - Lookup bind casing is FETCHED, not assumed: the nav property name equals
#     the lookup attribute's SchemaName, so we read it and build the bind from
#     truth. Assumption count in this script: zero.
#
# Pattern: rerun-safe on natural key (name); TFN left null (alternate key
# ignores nulls; fictitious TFNs are asking for trouble); GUIDs fetched.

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

$entityName = "Harborne Nominees Pty Ltd"

# --- Fetch the country lookup's REAL SchemaName (bind casing from truth) ----
$luMeta = Invoke-RestMethod -Uri "$api/EntityDefinitions(LogicalName='cap_entity')/Attributes(LogicalName='cap_countryid')?`$select=SchemaName" -Headers $headers -Method Get
$bindProp = "$($luMeta.SchemaName)@odata.bind"
Write-Host "Country lookup SchemaName: $($luMeta.SchemaName)  (bind: $bindProp)" -ForegroundColor Cyan

# --- Resolve the Australia country row --------------------------------------
$au = (Invoke-RestMethod -Uri "$api/cap_countries?`$select=cap_countryid,cap_country&`$filter=cap_isoalpha2 eq 'AU'" -Headers $headers -Method Get).value
if (-not $au) { throw "Australia row not found in cap_country - run seed-country.ps1 first." }
$auId = $au[0].cap_countryid
Write-Host "Resolved country: $($au[0].cap_country) ($auId)" -ForegroundColor Cyan

# --- Existence check on the natural key --------------------------------------
$existing = (Invoke-RestMethod -Uri "$api/cap_entities?`$select=cap_entityname&`$filter=cap_entityname eq '$entityName'" -Headers $headers -Method Get).value
if ($existing) {
    Write-Host "$entityName already exists - skipping." -ForegroundColor Yellow
} else {
    $body = @{
        cap_entityname = $entityName
        cap_type       = 764820001    # Company (Block 1 platform-prefixed values, per probe)
        $bindProp      = "/cap_countries($auId)"
    } | ConvertTo-Json
    Invoke-RestMethod -Uri "$api/cap_entities" -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host "Created $entityName." -ForegroundColor Green
}

# --- Verify -------------------------------------------------------------------
$rows = (Invoke-RestMethod -Uri "$api/cap_entities?`$select=cap_entityname,cap_type,_cap_countryid_value&`$filter=cap_entityname eq '$entityName'" -Headers $headers -Method Get).value
Write-Host "`nEntity row:" -ForegroundColor Cyan
$rows | Format-Table cap_entityname, cap_type, '_cap_countryid_value' -AutoSize

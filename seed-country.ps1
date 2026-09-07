# seed-country.ps1 — seed cap_country with the practice working set
#
# WHY a working set, not all 249 ISO countries: KISS — seed what the practice
# touches. Rerun-safe design means adding a country later is one line in the
# array below and a rerun. Singapore and Ireland earn rows because they appear
# in Australian SMB structures often enough.
#
# DATA not schema, so unnumbered. Rerun-safe: existence check on cap_isoalpha2
# before each create; yellow "already exists - skipping" per country present.
#
# cap_taxidlabel = what the local tax identifier is CALLED, so UI and documents
# can say "IRD number" to a NZ entity instead of "TFN".

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

# --- The working set -----------------------------------------------------
$countries = @(
    @{ name="Australia";      a2="AU"; a3="AUS"; ccy="AUD"; taxlabel="TFN" }
    @{ name="New Zealand";    a2="NZ"; a3="NZL"; ccy="NZD"; taxlabel="IRD number" }
    @{ name="United Kingdom"; a2="GB"; a3="GBR"; ccy="GBP"; taxlabel="UTR" }
    @{ name="United States";  a2="US"; a3="USA"; ccy="USD"; taxlabel="EIN/TIN" }
    @{ name="Singapore";      a2="SG"; a3="SGP"; ccy="SGD"; taxlabel="UEN" }
    @{ name="Ireland";        a2="IE"; a3="IRL"; ccy="EUR"; taxlabel="TRN" }
)

# --- Existing rows by alpha-2 (data query, not metadata - startswith is fine
#     here, but a straight pull of 6-249 rows is simpler) --------------------
$q = "$envUrl/api/data/v9.2/cap_countries?`$select=cap_isoalpha2"
$existing = @()
try { $existing = (Invoke-RestMethod -Uri $q -Headers $headers -Method Get).value.cap_isoalpha2 } catch { }

foreach ($c in $countries) {
    if ($existing -contains $c.a2) {
        Write-Host "$($c.name) ($($c.a2)) already exists - skipping." -ForegroundColor Yellow
        continue
    }
    $body = @{
        cap_country             = $c.name
        cap_isoalpha2           = $c.a2
        cap_isoalpha3           = $c.a3
        cap_defaultcurrencycode = $c.ccy
        cap_taxidlabel          = $c.taxlabel
    } | ConvertTo-Json
    Invoke-RestMethod -Uri "$envUrl/api/data/v9.2/cap_countries" -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host "Created $($c.name) ($($c.a2))." -ForegroundColor Green
}

# --- Verify ---------------------------------------------------------------
$rows = (Invoke-RestMethod -Uri "$envUrl/api/data/v9.2/cap_countries?`$select=cap_country,cap_isoalpha2,cap_defaultcurrencycode,cap_taxidlabel&`$orderby=cap_country" -Headers $headers -Method Get).value
Write-Host "`ncap_country rows now: $($rows.Count)" -ForegroundColor Cyan
$rows | Format-Table cap_country, cap_isoalpha2, cap_defaultcurrencycode, cap_taxidlabel -AutoSize
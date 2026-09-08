# 08a-accountclass-rename.ps1 — "Depreciation" -> "Depreciation & Amortisation"
#
# WHY: amortisation of intangibles is the same nature as depreciation (non-cash
# consumption of capital; EBITDA excludes both), so it shares the class. Rename
# the label rather than add a class — classes are SUBTOTALS, not line items.
# Intangible assets themselves classify as Non-current Assets; the accounts
# are the line items.
#
# API pattern: existing option labels change via the UpdateOptionValue ACTION
# (POST to /UpdateOptionValue), not a POST to the option set. MergeLabels true.
# Rerun-safe: reads the current label first; skips if already renamed.

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

$target = "Depreciation & Amortisation"

# --- Read current label of option 100000005 on cap_accountclass -------------
$gos = (Invoke-RestMethod -Uri "$api/GlobalOptionSetDefinitions" -Headers $headers -Method Get).value |
       Where-Object { $_.Name -eq "cap_accountclass" }
$full = Invoke-RestMethod -Uri "$api/GlobalOptionSetDefinitions($($gos.MetadataId))" -Headers $headers -Method Get
$opt  = $full.Options | Where-Object { $_.Value -eq 100000005 }
$currentLabel = $opt.Label.UserLocalizedLabel.Label

if ($currentLabel -eq $target) {
    Write-Host "Option 100000005 already reads '$target' - skipping." -ForegroundColor Yellow
} else {
    Write-Host "Current label: '$currentLabel' - renaming..." -ForegroundColor Cyan
    $body = @{
        OptionSetName = "cap_accountclass"
        Value         = 100000005
        Label         = @{ LocalizedLabels = @(@{ Label = $target; LanguageCode = 1033 }) }
        MergeLabels   = $true
    } | ConvertTo-Json -Depth 8
    Invoke-RestMethod -Uri "$api/UpdateOptionValue" -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host "Renamed option 100000005 to '$target'." -ForegroundColor Green
}

# --- Verify ------------------------------------------------------------------
$full2 = Invoke-RestMethod -Uri "$api/GlobalOptionSetDefinitions($($gos.MetadataId))" -Headers $headers -Method Get
$opt2  = ($full2.Options | Where-Object { $_.Value -eq 100000005 }).Label.UserLocalizedLabel.Label
Write-Host "`nOption 100000005 now reads: '$opt2'" -ForegroundColor Cyan
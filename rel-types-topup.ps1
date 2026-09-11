# rel-types-topup.ps1 — six missing relationship types onto cap_relationshiptype
#
# PINNED VALUES (continue the platform range; the relationship seed maps
# text -> these exact numbers, so they are asserted, never server-assigned):
#   764820009 Beneficiary of      764820012 Parent of
#   764820010 Spouse of           764820013 Associated with
#   764820011 Child of            764820014 Other
# Existing nine (probed): 764820000 Trustee of ... 764820008 Secretary of.
#
# RERUN-SAFE: probes current options; inserts only the missing; asserts any
# present label sits at its pinned value (drift = red halt).

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

$wanted = [ordered]@{
    "Beneficiary of"  = 764820009
    "Spouse of"       = 764820010
    "Child of"        = 764820011
    "Parent of"       = 764820012
    "Associated with" = 764820013
    "Other"           = 764820014
}

# --- Probe current options ------------------------------------------------------
$set = Invoke-RestMethod -Uri "$api/GlobalOptionSetDefinitions(Name='cap_relationshiptype')" -Headers $headers -Method Get
$current = @{}
foreach ($o in $set.Options) {
    $label = $o.Label.UserLocalizedLabel.Label
    $current[$label] = $o.Value
}
Write-Host "cap_relationshiptype currently has $($current.Count) options." -ForegroundColor Cyan

# --- Assert no drift on already-present labels ----------------------------------
foreach ($k in $wanted.Keys) {
    if ($current.ContainsKey($k) -and $current[$k] -ne $wanted[$k]) {
        Write-Host "DRIFT: '$k' exists at $($current[$k]), pinned $($wanted[$k]). Resolve before seeding relationships." -ForegroundColor Red
        exit 1
    }
}

# --- Insert the missing ----------------------------------------------------------
$inserted = 0
foreach ($k in $wanted.Keys) {
    if ($current.ContainsKey($k)) {
        Write-Host "  '$k' already present at $($current[$k]) - skip." -ForegroundColor Yellow
        continue
    }
    $body = @{
        OptionSetName = "cap_relationshiptype"
        Value         = $wanted[$k]
        Label         = @{ LocalizedLabels = @(@{ Label = $k; LanguageCode = 1033 }) }
        SolutionUniqueName = "CommercialAccounting"
    }
    Invoke-RestMethod -Uri "$api/InsertOptionValue" -Headers $headers -Method Post -Body ($body | ConvertTo-Json -Depth 6) | Out-Null
    Write-Host "  Inserted '$k' = $($wanted[$k])" -ForegroundColor Green
    $inserted++
}
Write-Host "Inserted: $inserted" -ForegroundColor Green

# --- VERIFY from metadata (silence after writes is not success) ------------------
$set = Invoke-RestMethod -Uri "$api/GlobalOptionSetDefinitions(Name='cap_relationshiptype')" -Headers $headers -Method Get
Write-Host "`ncap_relationshiptype options ($($set.Options.Count)):" -ForegroundColor Cyan
$set.Options | Sort-Object Value | ForEach-Object {
    Write-Host ("  {0}  {1}" -f $_.Value, $_.Label.UserLocalizedLabel.Label)
}
if ($set.Options.Count -ne 15) { Write-Host "EXPECTED 15 options." -ForegroundColor Red; exit 1 } else { Write-Host "15 options - correct." -ForegroundColor Green }
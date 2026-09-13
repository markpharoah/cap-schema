# 17-engagement-evidence.ps1 — evidence basis + waiting rule on cap_engagement (SCHEMA)
#
# DOCTRINE (Jobs Spine record, item 2): the engagement is the PROMISE; the
# letter is EVIDENCE of it. Established = long-standing, tacit (pre-CAP
# relationships load as this; 32-year customers are never asked to sign).
# Documented = letter attached via signing machinery (required for NEW
# customers - enforced at app layer, schema records the fact).
# cap_waitingruleshown: whether the waiting-rule notice renders on this
# engagement's portal view (manager discretion, doctrine 6; default Yes,
# manager can suppress per relationship).
# Choice is LOCAL (single-table use; global only when shared - KISS).
#
# RERUN-SAFE; local optionset nests inline on the attribute create -
# that IS the allowed shape for Local (the 0x80048403 lesson inverted).

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

function Test-Attr($table, $logical) {
    try { Invoke-RestMethod -Uri "$api/EntityDefinitions(LogicalName='$table')/Attributes(LogicalName='$logical')?`$select=LogicalName" -Headers $headers -Method Get | Out-Null; $true }
    catch { $false }
}
function Label($text) {
    @{ LocalizedLabels = @(@{ Label = $text; LanguageCode = 1033 }) }
}

# --- 1) cap_evidencebasis (LOCAL choice, nested inline) ---------------------------
if (Test-Attr "cap_engagement" "cap_evidencebasis") {
    Write-Host "cap_evidencebasis already exists - skip." -ForegroundColor Yellow
} else {
    $c = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.PicklistAttributeMetadata"
        SchemaName    = "cap_EvidenceBasis"
        DisplayName   = Label "Evidence Basis"
        Description   = Label "How the engagement is evidenced. Established = long-standing tacit; Documented = letter attached. New customers require Documented (app-enforced)."
        RequiredLevel = @{ Value = "None" }
        OptionSet     = @{
            "@odata.type" = "Microsoft.Dynamics.CRM.OptionSetMetadata"
            IsGlobal      = $false
            OptionSetType = "Picklist"
            Options       = @(
                @{ Value = 764820000; Label = Label "Established" },
                @{ Value = 764820001; Label = Label "Documented" }
            )
        }
    }
    Invoke-RestMethod -Uri "$api/EntityDefinitions(LogicalName='cap_engagement')/Attributes" -Headers $headers -Method Post -Body ($c | ConvertTo-Json -Depth 12) | Out-Null
    Write-Host "cap_evidencebasis created (764820000 Established / ...001 Documented)." -ForegroundColor Green
}

# --- 2) cap_waitingruleshown -------------------------------------------------------
if (Test-Attr "cap_engagement" "cap_waitingruleshown") {
    Write-Host "cap_waitingruleshown already exists - skip." -ForegroundColor Yellow
} else {
    $c = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.BooleanAttributeMetadata"
        SchemaName    = "cap_WaitingRuleShown"
        DisplayName   = Label "Waiting Rule Shown"
        Description   = Label "Whether the waiting-rule notice renders on this engagement's portal view. Manager discretion per doctrine 6."
        OptionSet     = @{
            "@odata.type" = "Microsoft.Dynamics.CRM.BooleanOptionSetMetadata"
            TrueOption  = @{ Value = 1; Label = Label "Shown" }
            FalseOption = @{ Value = 0; Label = Label "Suppressed" }
        }
        RequiredLevel = @{ Value = "None" }
    }
    Invoke-RestMethod -Uri "$api/EntityDefinitions(LogicalName='cap_engagement')/Attributes" -Headers $headers -Method Post -Body ($c | ConvertTo-Json -Depth 12) | Out-Null
    Write-Host "cap_waitingruleshown created." -ForegroundColor Green
}

# --- VERIFY --------------------------------------------------------------------------
$need = @("cap_evidencebasis","cap_waitingruleshown")
$attrs = (Invoke-RestMethod -Uri "$api/EntityDefinitions(LogicalName='cap_engagement')/Attributes?`$select=LogicalName" -Headers $headers -Method Get).value | ForEach-Object { $_.LogicalName }
$missing = $need | Where-Object { $_ -notin $attrs }
if ($missing) { Write-Host "MISSING: $($missing -join ', ')" -ForegroundColor Red; exit 1 }
Write-Host "Both evidence columns present on cap_engagement." -ForegroundColor Green
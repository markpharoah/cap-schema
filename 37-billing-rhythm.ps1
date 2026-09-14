# ============================================================================
# 37-billing-rhythm.ps1 — Session 37 Part 1
# cap_engagement gains two columns ratified 14-15/9:
#   cap_billingrhythm  (Local choice: Annual on completion / Monthly fixed /
#                       Quarterly fixed; default Annual) — WIP behaviour + quiet
#                       flight-deck for the retainer clients
#   cap_asscope        (Boolean "CA does BAS/IAS", default Yes) — No suppresses
#                       AS job proposals AND AS deviations (the Lewis ruling)
# Then the data pass: five retainer exceptions + Lewis AS scope = No.
# Rerun-safe: every create checks existence first (yellow skip).
# Local choice NESTS inline (only Global must @odata.bind — lesson 12/9).
# ============================================================================
$ErrorActionPreference = 'Stop'

# --- auth (house standard; swap this block if your current scripts differ) ---
$Env    = 'https://org020f7b5c.crm6.dynamics.com'
$Token  = (Get-MsalToken -ClientId 'bcf0d51c-81f7-40e0-a485-c75ed82a02e3' `
          -TenantId '46bc20d5-9c02-426f-b030-aea373177d31' `
          -Scopes "$Env/.default" -Interactive:$false -Silent -ErrorAction SilentlyContinue) 
if (-not $Token) { $Token = Get-MsalToken -ClientId 'bcf0d51c-81f7-40e0-a485-c75ed82a02e3' -TenantId '46bc20d5-9c02-426f-b030-aea373177d31' -Scopes "$Env/.default" -Interactive }
$H  = @{ Authorization = "Bearer $($Token.AccessToken)"; 'OData-MaxVersion'='4.0'; 'OData-Version'='4.0'; Accept='application/json' }
$HW = $H + @{ 'Content-Type'='application/json'; 'MSCRM.SolutionUniqueName'='CommercialAccounting' }
$Api = "$Env/api/data/v9.2"

function Get-Attr($table,$logical) {
  try { Invoke-RestMethod -Uri "$Api/EntityDefinitions(LogicalName='$table')/Attributes(LogicalName='$logical')" -Headers $H } catch { $null }
}

# --- 1. cap_billingrhythm (Local choice, pinned values) ---
if (Get-Attr 'cap_engagement' 'cap_billingrhythm') {
  Write-Host 'cap_billingrhythm already exists - skipping' -ForegroundColor Yellow
} else {
  $body = @{
    '@odata.type' = 'Microsoft.Dynamics.CRM.PicklistAttributeMetadata'
    SchemaName    = 'cap_BillingRhythm'
    LogicalName   = 'cap_billingrhythm'
    DisplayName   = @{ LocalizedLabels = @(@{ Label='Billing Rhythm'; LanguageCode=1033 }) }
    Description   = @{ LocalizedLabels = @(@{ Label='How this engagement bills: annual on job completion (default), or fixed monthly/quarterly retainer. Drives WIP conversion and flight-deck weighting.'; LanguageCode=1033 }) }
    RequiredLevel = @{ Value='None' }
    DefaultFormValue = 764820000
    OptionSet     = @{
      '@odata.type'='Microsoft.Dynamics.CRM.OptionSetMetadata'
      IsGlobal=$false; OptionSetType='Picklist'
      Options=@(
        @{ Value=764820000; Label=@{ LocalizedLabels=@(@{ Label='Annual on completion'; LanguageCode=1033 }) } },
        @{ Value=764820001; Label=@{ LocalizedLabels=@(@{ Label='Monthly fixed'; LanguageCode=1033 }) } },
        @{ Value=764820002; Label=@{ LocalizedLabels=@(@{ Label='Quarterly fixed'; LanguageCode=1033 }) } })
    }
  } | ConvertTo-Json -Depth 12
  Invoke-RestMethod -Method Post -Uri "$Api/EntityDefinitions(LogicalName='cap_engagement')/Attributes" -Headers $HW -Body $body | Out-Null
  Write-Host 'cap_billingrhythm created' -ForegroundColor Green
}

# --- 2. cap_asscope (Boolean, default Yes) ---
if (Get-Attr 'cap_engagement' 'cap_asscope') {
  Write-Host 'cap_asscope already exists - skipping' -ForegroundColor Yellow
} else {
  $body = @{
    '@odata.type'='Microsoft.Dynamics.CRM.BooleanAttributeMetadata'
    SchemaName='cap_ASScope'; LogicalName='cap_asscope'
    DisplayName=@{ LocalizedLabels=@(@{ Label='AS scope (CA does BAS/IAS)'; LanguageCode=1033 }) }
    Description=@{ LocalizedLabels=@(@{ Label='No = practice does not generate AS work for this client. Obligations stay visible for stewardship - scope limits work, never sight. Ratified 15/9, amended same day (Lewis ruling).'; LanguageCode=1033 }) }
    RequiredLevel=@{ Value='None' }; DefaultValue=$true
    OptionSet=@{ '@odata.type'='Microsoft.Dynamics.CRM.BooleanOptionSetMetadata'
      TrueOption =@{ Value=1; Label=@{ LocalizedLabels=@(@{ Label='Yes'; LanguageCode=1033 }) } }
      FalseOption=@{ Value=0; Label=@{ LocalizedLabels=@(@{ Label='No';  LanguageCode=1033 }) } } }
  } | ConvertTo-Json -Depth 12
  Invoke-RestMethod -Method Post -Uri "$Api/EntityDefinitions(LogicalName='cap_engagement')/Attributes" -Headers $HW -Body $body | Out-Null
  Write-Host 'cap_asscope created' -ForegroundColor Green
}

Write-Host "`nIf either column was just created, give the validation range a moment (cache-lag family) before the data pass below reruns cleanly.`n" -ForegroundColor Cyan

# --- 3. Data pass -----------------------------------------------------------
# Retainers by cap_clientcode where LodgeIT knows them; by name-probe where not.
# CONFIRM the Marbec row: rhythm rides the engagement you actually bill.
$RhythmByCode = @{ 'ELE0001'=764820001; 'CEL0001'=764820001; 'TRU0001'=764820002 }  # EIV, Celmec monthly; Marbec trust quarterly
$RhythmByName = @{ 'MultiCube'=764820001; 'Institute of Electrical'=764820001 }      # no LodgeIT code — probe cap_entity by name
$NoAS = @('LEW0003','LEW0005')                                                       # Bill Lewis + W E Lewis & Associates

function Get-EntityByCode($code) {
  (Invoke-RestMethod -Uri "$Api/cap_entities?`$filter=cap_clientcode eq '$code'&`$select=cap_entityid,cap_entityname" -Headers $H).value
}
function Get-EntityByName($pat) {
  (Invoke-RestMethod -Uri "$Api/cap_entities?`$filter=contains(cap_entityname,'$pat')&`$select=cap_entityid,cap_entityname,cap_clientcode" -Headers $H).value
}
function Get-Engagements($entityId) {
  (Invoke-RestMethod -Uri "$Api/cap_engagements?`$filter=_cap_entityid_value eq $entityId&`$select=cap_engagementid,cap_engagementtype,cap_billingrhythm,cap_asscope" -Headers $H).value
}
function Set-Engagement($id,$props) {
  Invoke-RestMethod -Method Patch -Uri "$Api/cap_engagements($id)" -Headers ($H + @{'Content-Type'='application/json'}) -Body ($props | ConvertTo-Json) | Out-Null
}

foreach ($code in $RhythmByCode.Keys) {
  $e = Get-EntityByCode $code
  if (-not $e) { Write-Host "RHYTHM: $code NOT FOUND in cap_entity - investigate" -ForegroundColor Yellow; continue }
  foreach ($en in $e) { foreach ($g in (Get-Engagements $en.cap_entityid)) {
    if ($g.cap_billingrhythm -eq $RhythmByCode[$code]) { Write-Host "RHYTHM: $code $($en.cap_entityname) already set - skipping" -ForegroundColor Yellow }
    else { Set-Engagement $g.cap_engagementid @{ cap_billingrhythm = $RhythmByCode[$code] }
           Write-Host "RHYTHM: $code $($en.cap_entityname) -> $($RhythmByCode[$code])" -ForegroundColor Green } } }
}
foreach ($pat in $RhythmByName.Keys) {
  $e = Get-EntityByName $pat
  if (-not $e) { Write-Host "RHYTHM: name probe '$pat' found nothing - entity may not exist yet" -ForegroundColor Yellow; continue }
  foreach ($en in $e) {
    Write-Host "RHYTHM: name probe '$pat' matched $($en.cap_entityname) [$($en.cap_clientcode)]" -ForegroundColor Cyan
    foreach ($g in (Get-Engagements $en.cap_entityid)) {
      if ($g.cap_billingrhythm -eq $RhythmByName[$pat]) { Write-Host "  already set - skipping" -ForegroundColor Yellow }
      else { Set-Engagement $g.cap_engagementid @{ cap_billingrhythm = $RhythmByName[$pat] }; Write-Host "  -> $($RhythmByName[$pat])" -ForegroundColor Green } } }
}
foreach ($code in $NoAS) {
  $e = Get-EntityByCode $code
  if (-not $e) { Write-Host "ASSCOPE: $code NOT FOUND - investigate" -ForegroundColor Yellow; continue }
  foreach ($en in $e) { foreach ($g in (Get-Engagements $en.cap_entityid)) {
    if ($g.cap_asscope -eq $false) { Write-Host "ASSCOPE: $code already No - skipping" -ForegroundColor Yellow }
    else { Set-Engagement $g.cap_engagementid @{ cap_asscope = $false }
           Write-Host "ASSCOPE: $code $($en.cap_entityname) -> No (CA does not do BAS)" -ForegroundColor Green } } }
}
Write-Host "`n37-billing-rhythm complete." -ForegroundColor Green

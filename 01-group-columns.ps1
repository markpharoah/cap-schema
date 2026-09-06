$ClientId = "bcf0d51c-81f7-40e0-a485-c75ed82a02e3"
$EnvUrl   = "https://org020f7b5c.crm6.dynamics.com"
$TenantId = "46bc20d5-9c02-426f-b030-aea373177d31"

Import-Module MSAL.PS
$token = Get-MsalToken -ClientId $ClientId -TenantId $TenantId -Scopes "$EnvUrl/user_impersonation" -Interactive
$hdr = @{
  Authorization = "Bearer $($token.AccessToken)"
  "Content-Type" = "application/json"
  "MSCRM.SolutionUniqueName" = "CommercialAccounting"
}

# Existing columns on cap_group
$existing = (Invoke-RestMethod -Uri "$EnvUrl/api/data/v9.2/EntityDefinitions(LogicalName='cap_group')/Attributes?`$select=LogicalName" -Headers $hdr).value.LogicalName

# --- Status: local column bound to global choice cap_groupstatus ---
if ($existing -contains "cap_status") {
  Write-Host "cap_status already exists - skipping" -ForegroundColor Yellow
} else {
  $gc = Invoke-RestMethod -Uri "$EnvUrl/api/data/v9.2/GlobalOptionSetDefinitions" -Headers $hdr
  $gs = $gc.value | Where-Object { $_.Name -eq "cap_groupstatus" }
  $body = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.PicklistAttributeMetadata"
    SchemaName = "cap_status"
    DisplayName = @{ LocalizedLabels = @(@{ Label = "Status"; LanguageCode = 1033 }) }
    RequiredLevel = @{ Value = "ApplicationRequired" }
    "GlobalOptionSet@odata.bind" = "/GlobalOptionSetDefinitions($($gs.MetadataId))"
  } | ConvertTo-Json -Depth 10
  Invoke-RestMethod -Method Post -Uri "$EnvUrl/api/data/v9.2/EntityDefinitions(LogicalName='cap_group')/Attributes" -Headers $hdr -Body $body | Out-Null
  Write-Host "cap_status created" -ForegroundColor Green
}

# --- Notes: multiline plain text ---
if ($existing -contains "cap_notes") {
  Write-Host "cap_notes already exists - skipping" -ForegroundColor Yellow
} else {
  $body = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.MemoAttributeMetadata"
    SchemaName = "cap_notes"
    DisplayName = @{ LocalizedLabels = @(@{ Label = "Notes"; LanguageCode = 1033 }) }
    RequiredLevel = @{ Value = "None" }
    MaxLength = 10000
  } | ConvertTo-Json -Depth 10
  Invoke-RestMethod -Method Post -Uri "$EnvUrl/api/data/v9.2/EntityDefinitions(LogicalName='cap_group')/Attributes" -Headers $hdr -Body $body | Out-Null
  Write-Host "cap_notes created" -ForegroundColor Green
}

Write-Host "`ncap_group columns verified." -ForegroundColor Green
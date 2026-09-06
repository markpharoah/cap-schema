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

# --- cap_person table with primary column cap_fullname ---
$tbl = @{
  "@odata.type" = "Microsoft.Dynamics.CRM.EntityMetadata"
  SchemaName = "cap_person"
  DisplayName = @{ LocalizedLabels = @(@{ Label = "Person"; LanguageCode = 1033 }) }
  DisplayCollectionName = @{ LocalizedLabels = @(@{ Label = "People"; LanguageCode = 1033 }) }
  OwnershipType = "UserOwned"
  HasNotes = $false
  HasActivities = $false
  Attributes = @(
    @{
      "@odata.type" = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
      SchemaName = "cap_fullname"
      IsPrimaryName = $true
      RequiredLevel = @{ Value = "ApplicationRequired" }
      MaxLength = 200
      DisplayName = @{ LocalizedLabels = @(@{ Label = "Full Name"; LanguageCode = 1033 }) }
    }
  )
} | ConvertTo-Json -Depth 15

Invoke-RestMethod -Method Post -Uri "$EnvUrl/api/data/v9.2/EntityDefinitions" -Headers $hdr -Body $tbl
Write-Host "cap_person table created" -ForegroundColor Green

# --- helper for adding columns ---
function Add-Col($json) {
  Invoke-RestMethod -Method Post -Uri "$EnvUrl/api/data/v9.2/EntityDefinitions(LogicalName='cap_person')/Attributes" -Headers $hdr -Body $json | Out-Null
}

# Given name / family name / preferred name
@(
  @{ s="cap_givenname";     l="Given Name";     max=100 },
  @{ s="cap_familyname";    l="Family Name";    max=100 },
  @{ s="cap_preferredname"; l="Preferred Name"; max=100 }
) | ForEach-Object {
  Add-Col (@{
    "@odata.type" = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
    SchemaName = $_.s
    RequiredLevel = @{ Value = "None" }
    MaxLength = $_.max
    DisplayName = @{ LocalizedLabels = @(@{ Label = $_.l; LanguageCode = 1033 }) }
  } | ConvertTo-Json -Depth 10)
  Write-Host "$($_.s) created" -ForegroundColor Green
}

# Email / mobile
Add-Col (@{
  "@odata.type" = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
  SchemaName = "cap_email"
  RequiredLevel = @{ Value = "None" }
  MaxLength = 200
  FormatName = @{ Value = "Email" }
  DisplayName = @{ LocalizedLabels = @(@{ Label = "Email"; LanguageCode = 1033 }) }
} | ConvertTo-Json -Depth 10)
Write-Host "cap_email created" -ForegroundColor Green

Add-Col (@{
  "@odata.type" = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
  SchemaName = "cap_mobile"
  RequiredLevel = @{ Value = "None" }
  MaxLength = 50
  FormatName = @{ Value = "Phone" }
  DisplayName = @{ LocalizedLabels = @(@{ Label = "Mobile"; LanguageCode = 1033 }) }
} | ConvertTo-Json -Depth 10)
Write-Host "cap_mobile created" -ForegroundColor Green

# Date of birth (date only)
Add-Col (@{
  "@odata.type" = "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata"
  SchemaName = "cap_dateofbirth"
  RequiredLevel = @{ Value = "None" }
  Format = "DateOnly"
  DisplayName = @{ LocalizedLabels = @(@{ Label = "Date of Birth"; LanguageCode = 1033 }) }
} | ConvertTo-Json -Depth 10)
Write-Host "cap_dateofbirth created" -ForegroundColor Green

# Notes
Add-Col (@{
  "@odata.type" = "Microsoft.Dynamics.CRM.MemoAttributeMetadata"
  SchemaName = "cap_notes"
  RequiredLevel = @{ Value = "None" }
  MaxLength = 10000
  DisplayName = @{ LocalizedLabels = @(@{ Label = "Notes"; LanguageCode = 1033 }) }
} | ConvertTo-Json -Depth 10)
Write-Host "cap_notes created" -ForegroundColor Green

Write-Host "`ncap_person complete." -ForegroundColor Green
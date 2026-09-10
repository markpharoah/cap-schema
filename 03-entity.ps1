# ============================================================
# 03-entity.ps1 - cap_entity: the customer master
#
# WHY THIS TABLE: one row per legal entity the practice deals
# with - companies, trusts, SMSFs, partnerships, AND individuals
# in their capacity as taxpayers. A person (cap_person) is a
# human; an entity is a party to obligations. Robert Harborne
# the human appears once in cap_person; Robert Harborne the
# taxpayer is a cap_entity row. TFN therefore lives HERE.
#
# IDENTITY MODEL (ratified 8/9):
#   - cap_entityid GUID = true identity, invisible, backstage
#   - TFN = alternate key: uniqueness enforced ONLY when present
#     (nulls don't participate). Import upserts key on it.
#   - cap_clientcode = LodgeIT sync key, indexed, backstage,
#     never surfaced in UI except external-sync contexts.
#   - Navigation is by NAME. Codes are plumbing.
#
# TFN AS STRING, NOT NUMBER: leading zeros are significant,
# no arithmetic is ever valid on a TFN, and casting to int is
# the classic corruption bug (see house rule: dtype=str).
# ============================================================
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

# ---- 1. Table (skip if exists) ------------------------------
$tables = (Invoke-RestMethod -Uri "$EnvUrl/api/data/v9.2/EntityDefinitions?`$select=LogicalName" -Headers $hdr).value.LogicalName
if ($tables -contains "cap_entity") {
  Write-Host "cap_entity table already exists - skipping create" -ForegroundColor Yellow
} else {
  $tbl = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.EntityMetadata"
    SchemaName = "cap_entity"
    DisplayName = @{ LocalizedLabels = @(@{ Label = "Entity"; LanguageCode = 1033 }) }
    DisplayCollectionName = @{ LocalizedLabels = @(@{ Label = "Entities"; LanguageCode = 1033 }) }
    OwnershipType = "UserOwned"
    HasNotes = $false
    HasActivities = $false
    Attributes = @(@{
      "@odata.type" = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
      SchemaName = "cap_entityname"
      IsPrimaryName = $true
      RequiredLevel = @{ Value = "ApplicationRequired" }
      MaxLength = 300   # long legal names: trustee-for structures
      DisplayName = @{ LocalizedLabels = @(@{ Label = "Entity Name"; LanguageCode = 1033 }) }
    })
  } | ConvertTo-Json -Depth 15
  Invoke-RestMethod -Method Post -Uri "$EnvUrl/api/data/v9.2/EntityDefinitions" -Headers $hdr -Body $tbl | Out-Null
  Write-Host "cap_entity table created" -ForegroundColor Green
}

$existing = (Invoke-RestMethod -Uri "$EnvUrl/api/data/v9.2/EntityDefinitions(LogicalName='cap_entity')/Attributes?`$select=LogicalName" -Headers $hdr).value.LogicalName

function Add-Col($json, $name) {
  if ($existing -contains $name) {
    Write-Host "$name already exists - skipping" -ForegroundColor Yellow
  } else {
    Invoke-RestMethod -Method Post -Uri "$EnvUrl/api/data/v9.2/EntityDefinitions(LogicalName='cap_entity')/Attributes" -Headers $hdr -Body $json | Out-Null
    Write-Host "$name created" -ForegroundColor Green
  }
}

# ---- 2. Identifier strings ----------------------------------
# TFN 8-9 digits but stored loose (11) - never validated by
# length at schema level; format checks belong in import logic.
Add-Col (@{
  "@odata.type" = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
  SchemaName = "cap_tfn"; MaxLength = 11
  RequiredLevel = @{ Value = "None" }   # None: prospects/non-lodgers have no TFN
  DisplayName = @{ LocalizedLabels = @(@{ Label = "TFN"; LanguageCode = 1033 }) }
} | ConvertTo-Json -Depth 10) "cap_tfn"

Add-Col (@{
  "@odata.type" = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
  SchemaName = "cap_abn"; MaxLength = 14   # 11 digits + optional spacing
  RequiredLevel = @{ Value = "None" }
  DisplayName = @{ LocalizedLabels = @(@{ Label = "ABN"; LanguageCode = 1033 }) }
} | ConvertTo-Json -Depth 10) "cap_abn"

Add-Col (@{
  "@odata.type" = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
  SchemaName = "cap_acn"; MaxLength = 12
  RequiredLevel = @{ Value = "None" }
  DisplayName = @{ LocalizedLabels = @(@{ Label = "ACN"; LanguageCode = 1033 }) }
} | ConvertTo-Json -Depth 10) "cap_acn"

# LodgeIT sync key. Backstage by convention: it will be kept
# off forms/views when we build the UI. Schema can't hide it;
# the navigation principle does.
Add-Col (@{
  "@odata.type" = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
  SchemaName = "cap_clientcode"; MaxLength = 50
  RequiredLevel = @{ Value = "None" }
  DisplayName = @{ LocalizedLabels = @(@{ Label = "Client Code"; LanguageCode = 1033 }) }
} | ConvertTo-Json -Depth 10) "cap_clientcode"

# ---- 3. Choice columns bound to global choices --------------
$gc = Invoke-RestMethod -Uri "$EnvUrl/api/data/v9.2/GlobalOptionSetDefinitions" -Headers $hdr
$typeSet   = $gc.value | Where-Object { $_.Name -eq "cap_entitytype" }
$statusSet = $gc.value | Where-Object { $_.Name -eq "cap_entitystatus" }

Add-Col (@{
  "@odata.type" = "Microsoft.Dynamics.CRM.PicklistAttributeMetadata"
  SchemaName = "cap_type"
  RequiredLevel = @{ Value = "ApplicationRequired" }  # an entity without a type is meaningless
  DisplayName = @{ LocalizedLabels = @(@{ Label = "Entity Type"; LanguageCode = 1033 }) }
  "GlobalOptionSet@odata.bind" = "/GlobalOptionSetDefinitions($($typeSet.MetadataId))"
} | ConvertTo-Json -Depth 10) "cap_type"

Add-Col (@{
  "@odata.type" = "Microsoft.Dynamics.CRM.PicklistAttributeMetadata"
  SchemaName = "cap_status"
  RequiredLevel = @{ Value = "ApplicationRequired" }
  DisplayName = @{ LocalizedLabels = @(@{ Label = "Status"; LanguageCode = 1033 }) }
  "GlobalOptionSet@odata.bind" = "/GlobalOptionSetDefinitions($($statusSet.MetadataId))"
} | ConvertTo-Json -Depth 10) "cap_status"

Add-Col (@{
  "@odata.type" = "Microsoft.Dynamics.CRM.MemoAttributeMetadata"
  SchemaName = "cap_notes"; MaxLength = 10000
  RequiredLevel = @{ Value = "None" }
  DisplayName = @{ LocalizedLabels = @(@{ Label = "Notes"; LanguageCode = 1033 }) }
} | ConvertTo-Json -Depth 10) "cap_notes"

# ---- 4. Lookups: created as RELATIONSHIPS, not columns ------
# A lookup is the child half of a 1:N relationship; the API
# wants the relationship defined and the lookup rides inside.
# cap_group 1:N cap_entity  = "one group per entity" (KISS,
# ratified: no M:M; cross-group edges live in
# cap_entityrelationship instead).
$rels = (Invoke-RestMethod -Uri "$EnvUrl/api/data/v9.2/RelationshipDefinitions?`$select=SchemaName" -Headers $hdr).value.SchemaName

function Add-Lookup($relSchema, $refdTable, $lookupSchema, $label) {
  if ($rels -contains $relSchema) {
    Write-Host "$relSchema already exists - skipping" -ForegroundColor Yellow
  } else {
    $body = @{
      "@odata.type" = "Microsoft.Dynamics.CRM.OneToManyRelationshipMetadata"
      SchemaName = $relSchema
      ReferencedEntity = $refdTable
      ReferencingEntity = "cap_entity"
      Lookup = @{
        SchemaName = $lookupSchema
        RequiredLevel = @{ Value = "None" }   # group/country optional at birth; tighten later if earned
        DisplayName = @{ LocalizedLabels = @(@{ Label = $label; LanguageCode = 1033 }) }
      }
    } | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Method Post -Uri "$EnvUrl/api/data/v9.2/RelationshipDefinitions" -Headers $hdr -Body $body | Out-Null
    Write-Host "$relSchema + lookup $lookupSchema created" -ForegroundColor Green
  }
}

Add-Lookup "cap_group_cap_entity"   "cap_group"   "cap_groupid"   "Group"
Add-Lookup "cap_country_cap_entity" "cap_country" "cap_countryid" "Country"

# ---- 5. Alternate key on TFN --------------------------------
# Uniqueness enforced only for non-null TFNs (ratified 8/9).
# NOTE: key activation is ASYNC - a system job builds the index.
# Status may read Pending for a minute; that's normal.
$keys = (Invoke-RestMethod -Uri "$EnvUrl/api/data/v9.2/EntityDefinitions(LogicalName='cap_entity')/Keys?`$select=SchemaName" -Headers $hdr).value.SchemaName
if ($keys -contains "cap_key_tfn") {
  Write-Host "cap_key_tfn already exists - skipping" -ForegroundColor Yellow
} else {
  $key = @{
    SchemaName = "cap_key_tfn"
    DisplayName = @{ LocalizedLabels = @(@{ Label = "TFN Key"; LanguageCode = 1033 }) }
    KeyAttributes = @("cap_tfn")
  } | ConvertTo-Json -Depth 10
  Invoke-RestMethod -Method Post -Uri "$EnvUrl/api/data/v9.2/EntityDefinitions(LogicalName='cap_entity')/Keys" -Headers $hdr -Body $key | Out-Null
  Write-Host "cap_key_tfn created (index builds async)" -ForegroundColor Green
}

Write-Host "`ncap_entity complete." -ForegroundColor Green
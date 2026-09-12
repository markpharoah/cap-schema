# 29-relax-required.ps1 — engagement required-levels to None (SCHEMA)
# RULING (13 Sep): required fields on a mass-edit surface generate fiction -
# guessed dates are worse than blanks. cap_regulatorycapacity and
# cap_startdate -> None for the triage era; re-arm later selectively
# (Documented engagements demand dates; Established don't - app-layer).
# cap_entityid and cap_engagementtype STAY required: meaningless without.
# LESSON APPLIED: attribute PUT carries full identity + @odata.type per
# actual attribute class; MSCRM.MergeLabels header.
$ErrorActionPreference = "Stop"
$clientId = "bcf0d51c-81f7-40e0-a485-c75ed82a02e3"
$tenantId = "46bc20d5-9c02-426f-b030-aea373177d31"
$envUrl   = "https://org020f7b5c.crm6.dynamics.com"
$token = Get-MsalToken -ClientId $clientId -TenantId $tenantId -Scopes "$envUrl/.default"
$headers = @{
    Authorization = "Bearer $($token.AccessToken)"; "OData-MaxVersion" = "4.0"; "OData-Version" = "4.0"
    "Content-Type" = "application/json; charset=utf-8"; "MSCRM.SolutionUniqueName" = "CommercialAccounting"
    "MSCRM.MergeLabels" = "true"
}
$api = "$envUrl/api/data/v9.2"
$typeName = @{ "Picklist" = "Microsoft.Dynamics.CRM.PicklistAttributeMetadata"; "DateTime" = "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata" }
foreach ($col in @("cap_regulatorycapacity","cap_startdate")) {
    $a = Invoke-RestMethod -Uri "$api/EntityDefinitions(LogicalName='cap_engagement')/Attributes(LogicalName='$col')" -Headers $headers -Method Get
    if ($a.RequiredLevel.Value -eq "None") { Write-Host "$col already optional - skip." -ForegroundColor Yellow; continue }
    $body = @{
        "@odata.type" = $typeName[[string]$a.AttributeType]
        LogicalName   = $col
        SchemaName    = $a.SchemaName
        RequiredLevel = @{ Value = "None"; CanBeChanged = $true; ManagedPropertyLogicalName = "canmodifyrequirementlevelsettings" }
    }
    Invoke-RestMethod -Uri "$api/EntityDefinitions(LogicalName='cap_engagement')/Attributes(LogicalName='$col')" -Headers $headers -Method Put -Body ($body | ConvertTo-Json -Depth 8) | Out-Null
    Write-Host "$col -> optional." -ForegroundColor Green
}
Invoke-RestMethod -Uri "$api/PublishAllXml" -Headers $headers -Method Post | Out-Null
Write-Host "Published. F5 the app - asterisks gone." -ForegroundColor Green
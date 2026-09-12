# 28-forms.ps1 — feed the starving forms + cure display-name collisions (SCHEMA/UI)
#
# PROBED: all four main forms hold only name + ownerid. This script:
#   1) Renames cap_entity.cap_status DisplayName -> "Client Status"
#      LESSON (0x80040203): attribute PUT requires the FULL identity -
#      LogicalName + SchemaName in the body, not just the changed label.
#   2) Injects missing fields into each main 'Information' form (FormXml
#      surgery; classid mapped from probed AttributeType; skip if present).
#   3) PublishAllXml.
# TFN goes ON the entity form (edit surface); grids keep excluding it.
# RERUN-SAFE: presence checks; rename idempotent.

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
function Label($text) { @{ LocalizedLabels = @(@{ Label = $text; LanguageCode = 1033 }) } }

# --- 1) Rename cap_status -> "Client Status" (full identity in body) ----------------
$attr = Invoke-RestMethod -Uri "$api/EntityDefinitions(LogicalName='cap_entity')/Attributes(LogicalName='cap_status')" -Headers $headers -Method Get
$curLabel = $attr.DisplayName.UserLocalizedLabel.Label
if ($curLabel -eq "Client Status") {
    Write-Host "cap_status already 'Client Status' - skip." -ForegroundColor Yellow
} else {
    $body = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.PicklistAttributeMetadata"
        LogicalName   = "cap_status"
        SchemaName    = $attr.SchemaName
        DisplayName   = Label "Client Status"
    }
    $h2 = @{}
    foreach ($k in $headers.Keys) { $h2[$k] = $headers[$k] }
    $h2["MSCRM.MergeLabels"] = "true"
    Invoke-RestMethod -Uri "$api/EntityDefinitions(LogicalName='cap_entity')/Attributes(LogicalName='cap_status')" -Headers $h2 -Method Put -Body ($body | ConvertTo-Json -Depth 8) | Out-Null
    Write-Host "cap_status renamed 'Client Status'." -ForegroundColor Green
}

# --- 2) Form surgery -----------------------------------------------------------------
$classMap = @{
    "String"   = "{4273EDBD-AC1D-40D3-9FB2-095C621B552D}"
    "Memo"     = "{E0DECE4B-6FC8-4A8F-A065-082708572369}"
    "Lookup"   = "{270BD3DB-D9AF-4782-9025-509E298DEC0A}"
    "Picklist" = "{3EF39988-22BB-4F0B-BBBE-64B5A3748AEE}"
    "Boolean"  = "{B0C6723A-8503-4FD7-BB28-C8A06AC933C2}"
    "DateTime" = "{5B773807-9FB2-42DB-97C3-7A91EFF8ADFF}"
    "Money"    = "{533B9E00-756B-4312-95A0-DC888637AC78}"
    "Decimal"  = "{C3EFE0C3-0EC6-42BE-8349-CBD9079DFD8E}"
    "Integer"  = "{C6D124CA-7EDA-4A60-AEA9-7FB8D318B68F}"
}
$plan = @{
    "cap_engagement" = @("cap_entityid","cap_engagementtype","cap_evidencebasis","cap_waitingruleshown","cap_regulatorycapacity","cap_startdate","cap_enddate","cap_notes")
    "cap_entity"     = @("cap_clientcode","cap_type","cap_status","cap_abn","cap_acn","cap_tfn","cap_countryid","cap_notes")
    "cap_job"        = @("cap_entityid","cap_engagementid","cap_jobtemplateid","cap_periodstart","cap_periodend","cap_description")
    "cap_task"       = @("cap_jobid","cap_stagesequence","cap_stagename","cap_weight","cap_court","cap_showcustomer","cap_duedate","cap_ismilestone","cap_milestonename","cap_billinganchoramount","cap_billinganchorpercent")
}

foreach ($tbl in $plan.Keys) {
    $attrs = (Invoke-RestMethod -Uri "$api/EntityDefinitions(LogicalName='$tbl')/Attributes?`$select=LogicalName,AttributeType,DisplayName" -Headers $headers -Method Get).value
    $attrInfo = @{}
    foreach ($a in $attrs) {
        $lbl = $a.DisplayName.UserLocalizedLabel.Label ?? $a.LogicalName
        $attrInfo[$a.LogicalName] = @{ Type = [string]$a.AttributeType; Label = $lbl }
    }
    $form = ((Invoke-RestMethod -Uri "$api/systemforms?`$select=formid&`$filter=objecttypecode eq '$tbl' and type eq 2 and name eq 'Information'" -Headers $headers -Method Get).value)[0]
    $fx = (Invoke-RestMethod -Uri "$api/systemforms($($form.formid))?`$select=formxml" -Headers $headers -Method Get).formxml
    $xml = [xml]$fx
    $present = @($xml.SelectNodes("//control[@datafieldname]") | ForEach-Object { $_.datafieldname })
    $rowsNode = $xml.SelectSingleNode("//tab//section//rows")
    if (-not $rowsNode) { Write-Host "$tbl : no rows node found - skipping (inspect manually)." -ForegroundColor Red; continue }
    $added = 0
    foreach ($f in $plan[$tbl]) {
        if ($present -contains $f) { Write-Host "  $tbl.$f already on form - skip." -ForegroundColor Yellow; continue }
        if (-not $attrInfo.ContainsKey($f)) { Write-Host "  $tbl.$f NOT FOUND in metadata" -ForegroundColor Red; continue }
        $t = $attrInfo[$f].Type
        if ($t -eq "Virtual") { continue }
        $classid = $classMap[$t] ?? $classMap["String"]
        $cellId = "{" + [guid]::NewGuid().ToString().ToUpper() + "}"
        $row = $xml.CreateElement("row")
        $cell = $xml.CreateElement("cell"); $cell.SetAttribute("id", $cellId)
        $labels = $xml.CreateElement("labels")
        $label = $xml.CreateElement("label")
        $label.SetAttribute("description", $attrInfo[$f].Label)
        $label.SetAttribute("languagecode", "1033")
        $labels.AppendChild($label) | Out-Null
        $ctrl = $xml.CreateElement("control")
        $ctrl.SetAttribute("id", $f); $ctrl.SetAttribute("classid", $classid); $ctrl.SetAttribute("datafieldname", $f)
        $cell.AppendChild($labels) | Out-Null
        $cell.AppendChild($ctrl) | Out-Null
        $row.AppendChild($cell) | Out-Null
        $rowsNode.AppendChild($row) | Out-Null
        $added++
    }
    if ($added -gt 0) {
        $body = @{ formxml = $xml.OuterXml }
        Invoke-RestMethod -Uri "$api/systemforms($($form.formid))" -Headers $headers -Method Patch -Body ($body | ConvertTo-Json -Depth 4) | Out-Null
        Write-Host "$tbl : $added field(s) added to main form." -ForegroundColor Green
    } else {
        Write-Host "$tbl : nothing to add." -ForegroundColor Yellow
    }
}

# --- 3) Publish -----------------------------------------------------------------------
Write-Host "Publishing all customizations (allow a minute)..." -ForegroundColor Cyan
Invoke-RestMethod -Uri "$api/PublishAllXml" -Headers $headers -Method Post | Out-Null
Write-Host "Published." -ForegroundColor Green
Write-Host "Refresh the app (F5); forms now carry their fields." -ForegroundColor Cyan
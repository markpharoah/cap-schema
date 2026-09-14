# ============================================================================
# 38-templates-probe.ps1 — Session 37 Part 2, PROBE HALF (read-only)
# Before seeding three new templates (Tax Only Return / Activity Statement /
# Amendment) we print the exact shape of the template pair as built on 12/9:
#   1. every attribute on cap_jobtemplate and cap_tasktemplate
#   2. the Year End template row + its task rows, full JSON
# Paste the output back; the seed half (38-templates-seed.ps1) gets cut to
# match reality instead of memory. Probe-before-assume — house doctrine.
# ============================================================================
$ErrorActionPreference = 'Stop'
$Env    = 'https://org020f7b5c.crm6.dynamics.com'
$Token  = (Get-MsalToken -ClientId 'bcf0d51c-81f7-40e0-a485-c75ed82a02e3' `
          -TenantId '46bc20d5-9c02-426f-b030-aea373177d31' `
          -Scopes "$Env/.default" -Interactive:$false -Silent -ErrorAction SilentlyContinue)
if (-not $Token) { $Token = Get-MsalToken -ClientId 'bcf0d51c-81f7-40e0-a485-c75ed82a02e3' -TenantId '46bc20d5-9c02-426f-b030-aea373177d31' -Scopes "$Env/.default" -Interactive }
$H = @{ Authorization = "Bearer $($Token.AccessToken)"; Accept='application/json' }
$Api = "$Env/api/data/v9.2"

foreach ($t in 'cap_jobtemplate','cap_tasktemplate') {
  Write-Host "`n=== $t attributes ===" -ForegroundColor Cyan
  (Invoke-RestMethod -Uri "$Api/EntityDefinitions(LogicalName='$t')/Attributes?`$select=LogicalName,AttributeType&`$filter=IsCustomAttribute eq true" -Headers $H).value |
    Sort-Object LogicalName | Format-Table LogicalName,AttributeType -AutoSize
}
Write-Host "`n=== cap_jobtemplate rows ===" -ForegroundColor Cyan
$jt = (Invoke-RestMethod -Uri "$Api/cap_jobtemplates" -Headers $H).value
$jt | ConvertTo-Json -Depth 6
Write-Host "`n=== cap_tasktemplate rows (Year End) ===" -ForegroundColor Cyan
(Invoke-RestMethod -Uri "$Api/cap_tasktemplates" -Headers $H).value | ConvertTo-Json -Depth 6

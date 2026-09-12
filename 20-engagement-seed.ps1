# 20-engagement-seed.ps1 — adopt existing vocabulary + seed ~199 promises (DATA)
#
# ARCHAEOLOGY (probed 12 Sep): cap_engagementtype EXISTS from Block 2 with
# TEN options at designer values 100000000-009 (Annual Accounting, SMSF
# Audit, BAS Agent Services, ASIC Agent Services, Company Formation,
# Commercial Negotiation, Information Systems Review/Design/Implementation,
# Other). cap_engagement already carries cap_engagementtype, startdate/
# enddate, regulatorycapacity. ADOPT REALITY: existing values kept as-is
# (pinning = asserted+deterministic, never renumbered); the two ratified
# types missing get APPENDED at the range's next values:
#   100000010 Tax Only        100000011 Virtual CFO
# Probe-before-assume now formally covers pre-week CHOICES, not just tables.
#
# SEED (option 1, ratified): every ACTIVE entity gets one typed promise:
#   Individual -> Tax Only (100000010)
#   Superfund  -> SMSF Audit (100000001)
#   Company/Trust/Partnership -> Annual Accounting (100000000)
# Established basis, waiting rule shown, Former entities get nothing.
# Harborne's untyped engagement (from 18) is TYPED IN PLACE, not duplicated.
# Corrections happen on screen in the app (option 2 = the app's first workout).
#
# RERUN-SAFE: option appends by existence+drift assert; engagements keyed
# entity+type; untyped-fix idempotent.

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

# --- 1) Append the two missing types (adopt the existing range) ---------------------
$wantedNew = [ordered]@{ "Tax Only" = 100000010; "Virtual CFO" = 100000011 }
$set = Invoke-RestMethod -Uri "$api/GlobalOptionSetDefinitions(Name='cap_engagementtype')" -Headers $headers -Method Get
$current = @{}
foreach ($o in $set.Options) { $current[$o.Label.UserLocalizedLabel.Label] = $o.Value }
foreach ($k in $wantedNew.Keys) {
    if ($current.ContainsKey($k)) {
        if ($current[$k] -ne $wantedNew[$k]) { Write-Host "DRIFT: '$k' at $($current[$k]), pinned $($wantedNew[$k])." -ForegroundColor Red; exit 1 }
        Write-Host "'$k' already present at $($current[$k]) - skip." -ForegroundColor Yellow
        continue
    }
    $body = @{
        OptionSetName = "cap_engagementtype"
        Value         = $wantedNew[$k]
        Label         = Label $k
        SolutionUniqueName = "CommercialAccounting"
    }
    Invoke-RestMethod -Uri "$api/InsertOptionValue" -Headers $headers -Method Post -Body ($body | ConvertTo-Json -Depth 6) | Out-Null
    Write-Host "Appended '$k' = $($wantedNew[$k])" -ForegroundColor Green
}

# --- 2) PROBE the engagement->entity bind name --------------------------------------
$rels = (Invoke-RestMethod -Uri "$api/EntityDefinitions(LogicalName='cap_engagement')/ManyToOneRelationships?`$select=ReferencedEntity,ReferencingEntityNavigationPropertyName" -Headers $headers -Method Get).value
$entRel = $rels | Where-Object { $_.ReferencedEntity -eq "cap_entity" } | Select-Object -First 1
if (-not $entRel) { Write-Host "No engagement->entity relationship found." -ForegroundColor Red; exit 1 }
$nav = $entRel.ReferencingEntityNavigationPropertyName
Write-Host "Probed bind name: '$nav'" -ForegroundColor Cyan

# --- 3) Fix untyped engagements (Harborne from 18): type = Annual Accounting --------
$untyped = (Invoke-RestMethod -Uri "$api/cap_engagements?`$select=cap_engagementid,cap_name&`$filter=cap_engagementtype eq null" -Headers $headers -Method Get).value
foreach ($u in $untyped) {
    Invoke-RestMethod -Uri "$api/cap_engagements($($u.cap_engagementid))" -Headers $headers -Method Patch -Body (@{ cap_engagementtype = 100000000 } | ConvertTo-Json) | Out-Null
    Write-Host "Typed in place: $($u.cap_name) -> Annual Accounting" -ForegroundColor Green
}

# --- 4) Load ACTIVE entities; map entity type -> engagement type --------------------
$mapType = @{
    764820000 = 100000010   # Individual   -> Tax Only
    764820001 = 100000000   # Company      -> Annual Accounting
    764820002 = 100000000   # Trust        -> Annual Accounting
    764820003 = 100000000   # Partnership  -> Annual Accounting
    764820004 = 100000001   # Superfund    -> SMSF Audit
}
$typeName = @{}
$set = Invoke-RestMethod -Uri "$api/GlobalOptionSetDefinitions(Name='cap_engagementtype')" -Headers $headers -Method Get
foreach ($o in $set.Options) { $typeName[[int]$o.Value] = $o.Label.UserLocalizedLabel.Label }

$entities = @()
$url = "$api/cap_entities?`$select=cap_entityid,cap_entityname,cap_type,cap_status"
do {
    $page = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
    $entities += $page.value
    $url = $page.'@odata.nextLink'
} while ($url)
$active = $entities | Where-Object { $null -eq $_.cap_status -or [int]$_.cap_status -eq 764820000 }
Write-Host "Active entities (incl. Harborne null-status): $($active.Count)" -ForegroundColor Cyan

# --- 5) Existing engagements keyed entity+type (raw FK read) ------------------------
$fkCol = "_" + $nav.ToLower() + "_value"
$existing = @{}
$url = "$api/cap_engagements?`$select=cap_engagementtype,$fkCol"
do {
    $page = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
    foreach ($e in $page.value) {
        $eid = $e.$fkCol
        if ($eid) { $existing["$eid|$([int]($e.cap_engagementtype ?? -1))"] = $true }
    }
    $url = $page.'@odata.nextLink'
} while ($url)
Write-Host "Existing engagement keys: $($existing.Count)" -ForegroundColor Cyan

# --- 6) THE SEED ---------------------------------------------------------------------
$created = 0; $skipped = 0; $unmapped = 0
foreach ($e in $active) {
    $engType = if ($null -eq $e.cap_type) { 100000000 }   # Harborne demo-era: Annual Accounting
               elseif ($mapType.ContainsKey([int]$e.cap_type)) { $mapType[[int]$e.cap_type] }
               else { Write-Host "UNMAPPED entity type $($e.cap_type) on $($e.cap_entityname) - skip." -ForegroundColor Red; $unmapped++; continue }
    $key = "$($e.cap_entityid)|$engType"
    if ($existing.ContainsKey($key)) { $skipped++; continue }
    $body = @{
        cap_name             = "$($e.cap_entityname) - $($typeName[$engType])"
        cap_engagementtype   = $engType
        cap_evidencebasis    = 764820000   # Established
        cap_waitingruleshown = $true
        "$nav@odata.bind"    = "/cap_entities($($e.cap_entityid))"
    }
    Invoke-RestMethod -Uri "$api/cap_engagements" -Headers $headers -Method Post -Body ($body | ConvertTo-Json) | Out-Null
    $created++
    if ($created % 25 -eq 0) { Write-Host "  ...$created created" -ForegroundColor DarkGray }
}
Write-Host "Created: $created  Skipped(existing): $skipped  Unmapped: $unmapped" -ForegroundColor Green

# --- VERIFY: counts by type ----------------------------------------------------------
$counts = @{}; $total = 0
$url = "$api/cap_engagements?`$select=cap_engagementtype"
do {
    $page = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
    foreach ($e in $page.value) {
        $k = if ($null -eq $e.cap_engagementtype) { "(untyped)" } else { $typeName[[int]$e.cap_engagementtype] }
        $counts[$k] = ($counts[$k] ?? 0) + 1; $total++
    }
    $url = $page.'@odata.nextLink'
} while ($url)
Write-Host "`nEngagements by type:" -ForegroundColor Cyan
$counts.GetEnumerator() | Sort-Object Key | ForEach-Object { Write-Host ("  {0,-24} {1}" -f $_.Key, $_.Value) }
Write-Host "TOTAL: $total" -ForegroundColor Green
if ($counts.ContainsKey("(untyped)")) { Write-Host "Untyped rows remain - investigate." -ForegroundColor Red; exit 1 }
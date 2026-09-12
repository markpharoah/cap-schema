# 23-knit-candidates.ps1 — propose missing family edges by surname (ANALYSIS -> CSV)
#
# CONTEXT (Mark, 12 Sep): LodgeIT grouping was clunky, served little purpose,
# and was left slack - so the web is missing links (odd Spouse count was the
# symptom; 151 "standalones" is the consequence). The knit loop:
#   23 proposes candidates (same surname, NOT already in the same component)
#   -> Mark reviews data\knit-candidates.csv (Accept: Y / blank, fix Type)
#   -> 24 loads confirmed edges -> rerun 21+22: groups form, retypes cascade.
#
# CSV columns: Accept (Y to load), Type (default "Spouse of"; also valid:
#   "Child of" = Code1 is child of Code2; "Associated with"), Code1, Name1,
#   Code2, Name2, SameGroupAlready (info only - excluded anyway).
# OUTPUT GOES TO data\ (real names - NEVER committed; repo holds scripts).
# Read-only against Dataverse. Active entities only; tombstones excluded.

$ErrorActionPreference = "Stop"

$clientId = "bcf0d51c-81f7-40e0-a485-c75ed82a02e3"
$tenantId = "46bc20d5-9c02-426f-b030-aea373177d31"
$envUrl   = "https://org020f7b5c.crm6.dynamics.com"

$token = Get-MsalToken -ClientId $clientId -TenantId $tenantId -Scopes "$envUrl/.default"
$headers = @{ Authorization = "Bearer $($token.AccessToken)"; "OData-MaxVersion" = "4.0"; "OData-Version" = "4.0" }
$api = "$envUrl/api/data/v9.2"

# --- Entities (Active + Harborne only; Individuals for pairing) ---------------------
$entities = @{}
$url = "$api/cap_entities?`$select=cap_entityid,cap_entityname,cap_clientcode,cap_type,cap_status"
do {
    $page = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
    foreach ($e in $page.value) {
        if ($null -eq $e.cap_status -or [int]$e.cap_status -eq 764820000) { $entities[$e.cap_entityid] = $e }
    }
    $url = $page.'@odata.nextLink'
} while ($url)

# --- Edges + components (Active graph) ----------------------------------------------
$edges = @()
$url = "$api/cap_entityrelationships?`$select=_cap_fromentityid_value,_cap_toentityid_value"
do {
    $page = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
    foreach ($r in $page.value) {
        if ($entities.ContainsKey($r._cap_fromentityid_value) -and $entities.ContainsKey($r._cap_toentityid_value)) {
            $edges += ,@($r._cap_fromentityid_value, $r._cap_toentityid_value)
        }
    }
    $url = $page.'@odata.nextLink'
} while ($url)
$parent = @{}
foreach ($id in $entities.Keys) { $parent[$id] = $id }
function Find($x) { while ($parent[$x] -ne $x) { $parent[$x] = $parent[$parent[$x]]; $x = $parent[$x] }; $x }
foreach ($e in $edges) { $a = Find $e[0]; $b = Find $e[1]; if ($a -ne $b) { $parent[$a] = $b } }

# --- Individuals by surname ("Surname, First" convention) ---------------------------
$individuals = $entities.Values | Where-Object { [int]($_.cap_type ?? -1) -eq 764820000 -and $_.cap_entityname -match "," }
$bySurname = $individuals | Group-Object { ($_.cap_entityname -split ",")[0].Trim().ToUpper() }

# --- Candidates: same surname, different component ----------------------------------
$rows = New-Object System.Collections.Generic.List[object]
foreach ($g in $bySurname | Where-Object { $_.Count -gt 1 }) {
    $m = @($g.Group | Sort-Object cap_clientcode)
    for ($i = 0; $i -lt $m.Count; $i++) {
        for ($j = $i + 1; $j -lt $m.Count; $j++) {
            if ((Find $m[$i].cap_entityid) -eq (Find $m[$j].cap_entityid)) { continue }  # already knitted
            $rows.Add([pscustomobject]@{
                Accept = ""
                Type   = "Spouse of"
                Code1  = $m[$i].cap_clientcode
                Name1  = $m[$i].cap_entityname
                Code2  = $m[$j].cap_clientcode
                Name2  = $m[$j].cap_entityname
            })
        }
    }
}
if (-not (Test-Path .\data)) { New-Item -ItemType Directory .\data | Out-Null }
$rows | Export-Csv .\data\knit-candidates.csv -NoTypeInformation
Write-Host "Candidates written: $($rows.Count) -> data\knit-candidates.csv" -ForegroundColor Green
Write-Host "Review: Accept=Y to load; fix Type where it isn't Spouse of" -ForegroundColor Yellow
Write-Host "  ('Child of' = Code1 is child of Code2; 'Associated with' for the rest)." -ForegroundColor Yellow
Write-Host "Same-surname-different-family pairs: leave Accept blank." -ForegroundColor Yellow
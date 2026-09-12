# 24-knit-edges.ps1 — load the confirmed family edges + retype cascade (DATA)
#
# SOURCE: data\knit-candidates.csv, "Pog's Fix" column (Mark, 12 Sep) -
# translated to an EXPLICIT edge list, one line per stated fact, Mark's
# words carried as annotation AND into cap_notes (provenance).
# BOWEY RULING (Mark): Stuart (dec.) was Catherine's husband; Samuel and
# Jessica are their children - edges load; history is true (tombstone
# doctrine). BOW0002 -> Former status: separate ruling pending.
# LESSON (this file, first run): POWERSHELL VARIABLES ARE CASE-INSENSITIVE.
# $E (edge list) and $e (loop var) are the SAME variable - the resolve loop
# silently destroyed the list. Renamed $edgeList / $row. Zero edges loaded
# on run 1; rerun-safety made the retry free.
# DUPLICATE REGISTER (LodgeIT merges): BET0003; MCI0005; PHA0003/0006/0008
# (Mark); PHA0007 (Robin). No edges to duplicates.
# RERUN-SAFE: option append drift-asserted; edges keyed on cap_name sentence.

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

# --- 1) Append 'Sibling of' = 764820015 (drift-asserted) ----------------------------
$set = Invoke-RestMethod -Uri "$api/GlobalOptionSetDefinitions(Name='cap_relationshiptype')" -Headers $headers -Method Get
$cur = @{}
foreach ($o in $set.Options) { $cur[$o.Label.UserLocalizedLabel.Label] = $o.Value }
if ($cur.ContainsKey("Sibling of")) {
    if ($cur["Sibling of"] -ne 764820015) { Write-Host "DRIFT: 'Sibling of' at $($cur['Sibling of'])." -ForegroundColor Red; exit 1 }
    Write-Host "'Sibling of' already present - skip." -ForegroundColor Yellow
} else {
    $body = @{ OptionSetName = "cap_relationshiptype"; Value = 764820015; Label = Label "Sibling of"; SolutionUniqueName = "CommercialAccounting" }
    Invoke-RestMethod -Uri "$api/InsertOptionValue" -Headers $headers -Method Post -Body ($body | ConvertTo-Json -Depth 6) | Out-Null
    Write-Host "Appended 'Sibling of' = 764820015" -ForegroundColor Green
}

# --- 2) THE EDGE LIST ----------------------------------------------------------------
$CHILD=764820011; $SPOUSE=764820010; $SIB=764820015; $ASSOC=764820013
$edgeList = @(
    @("AXF0002","AXF0001",$CHILD,"Thomas child of Peter"),
    @("BET0002","BET0001",$CHILD,"Aaron child of Steven"),
    @("SAM0001","BOW0001",$CHILD,"Samuel child of Catherine"),
    @("BOW0005","BOW0001",$CHILD,"Jessica child of Catherine"),
    @("BOW0002","BOW0001",$SPOUSE,"Stuart and Catherine (Stuart deceased)"),
    @("SAM0001","BOW0002",$CHILD,"Samuel child of Stuart"),
    @("BOW0005","BOW0002",$CHILD,"Jessica child of Stuart"),
    @("BRA0002","BRA0001",$CHILD,"Elise child of Jeanette"),
    @("CAS0003","CAS0002",$CHILD,"Christopher child of Damien"),
    @("CAS0004","CAS0002",$CHILD,"Peter child of Damien"),
    @("CAS0005","CAS0002",$CHILD,"Michael child of Damien"),
    @("CAS0006","CAS0002",$CHILD,"Isabella child of Damien"),
    @("CAS0007","CAS0002",$CHILD,"Louis child of Damien"),
    @("CAS0003","WAL0001",$CHILD,"Christopher child of Kathleen"),
    @("CAS0004","WAL0001",$CHILD,"Peter child of Kathleen"),
    @("CAS0005","WAL0001",$CHILD,"Michael child of Kathleen"),
    @("CAS0006","WAL0001",$CHILD,"Isabella child of Kathleen"),
    @("CAS0007","WAL0001",$CHILD,"Louis child of Kathleen"),
    @("DEA0001","DEA0002",$CHILD,"Jack child of Amanda"),
    @("JEF0003","JEF0001",$CHILD,"Dylan child of Dyan"),
    @("JEF0003","JEF0002",$CHILD,"Dylan child of Wayne"),
    @("KRU0003","KRU0001",$CHILD,"Samantha child of Stephen"),
    @("KRU0004","KRU0001",$CHILD,"Stephanie child of Stephen"),
    @("KRU0003","KRU0002",$CHILD,"Samantha child of Melinda"),
    @("KRU0004","KRU0002",$CHILD,"Stephanie child of Melinda"),
    @("MAT0003","MAT0001",$CHILD,"Aidan child of Iain"),
    @("MAT0003","MAT0002",$CHILD,"Aidan child of Tracey"),
    @("MCI0004","MCI0001",$CHILD,"Lachlan child of Stuart"),
    @("MUN0001","MUN0002",$CHILD,"Rebecca child of Frederick"),
    @("MUN0007","MUN0002",$CHILD,"David child of Frederick"),
    @("PHA0001","PHA0009",$CHILD,"Mark child of Barbara"),
    @("PHA0001","PHA0010",$CHILD,"Mark child of John"),
    @("EMI0001","SCH0002",$CHILD,"Emily child of Thomas"),
    @("EMI0001","SCH0007",$CHILD,"Emily child of Michele"),
    @("SCH0006","SCH0005",$CHILD,"Christopher child of Jacek"),
    @("SCH0006","SCH0008",$CHILD,"Christopher child of Cheryl"),
    @("DEA0001","DEA0003",$SPOUSE,"Jack and Alexandra"),
    @("LEI0001","LEI0002",$SPOUSE,"Jeremy and Christiana"),
    @("CAS0003","CAS0004",$SIB,"De Castella siblings"),
    @("CAS0003","CAS0005",$SIB,"De Castella siblings"),
    @("CAS0003","CAS0006",$SIB,"De Castella siblings"),
    @("CAS0003","CAS0007",$SIB,"De Castella siblings"),
    @("CAS0004","CAS0005",$SIB,"De Castella siblings"),
    @("CAS0004","CAS0006",$SIB,"De Castella siblings"),
    @("CAS0004","CAS0007",$SIB,"De Castella siblings"),
    @("CAS0005","CAS0006",$SIB,"De Castella siblings"),
    @("CAS0005","CAS0007",$SIB,"De Castella siblings"),
    @("CAS0006","CAS0007",$SIB,"De Castella siblings"),
    @("HAM0004","HAM0005",$SIB,"Brylie and Maddilyne"),
    @("JEN0001","JEN0003",$SIB,"Mitchell and Bradley"),
    @("KRU0003","KRU0004",$SIB,"Samantha and Stephanie"),
    @("MUN0001","MUN0007",$SIB,"Rebecca and David"),
    @("EMI0001","SCH0001",$SIB,"Emily and Timothy"),
    @("EMI0001","SCH0003",$SIB,"Emily and Jennifer"),
    @("WAT0001","WAT0002",$SIB,"Lesley and Ross"),
    @("DEA0002","DEA0003",$ASSOC,"Amanda mother-in-law of Alexandra"),
    @("JEN0001","KNE0001",$ASSOC,"Erika sister-in-law"),
    @("JEN0002","JEN0003",$ASSOC,"Bradley brother-in-law"),
    @("JEN0002","KNE0001",$ASSOC,"Sisters-in-law"),
    @("MCI0003","MCI0004",$ASSOC,"Step relation"),
    @("PHA0002","PHA0009",$ASSOC,"Robin daughter-in-law of Barbara"),
    @("EMI0001","SCH0005",$ASSOC,"Jacek uncle"),
    @("EMI0001","SCH0006",$ASSOC,"Cousins"),
    @("EMI0001","SCH0008",$ASSOC,"Emily niece of Cheryl"),
    @("SCH0001","SCH0006",$ASSOC,"Cousins"),
    @("SCH0002","SCH0006",$ASSOC,"Christopher nephew of Thomas"),
    @("SCH0003","SCH0006",$ASSOC,"Cousins"),
    @("SCH0006","SCH0007",$ASSOC,"Christopher nephew of Michele"),
    @("ONE0001","WAT0001",$ASSOC,"Sisters-in-law")
)

# --- 3) Resolve codes + existing sentences ------------------------------------------
$codeToId = @{}
$url = "$api/cap_entities?`$select=cap_clientcode,cap_entityid"
do {
    $page = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
    foreach ($ent in $page.value) { if ($ent.cap_clientcode) { $codeToId[$ent.cap_clientcode] = $ent.cap_entityid } }
    $url = $page.'@odata.nextLink'
} while ($url)
$existing = @{}
$url = "$api/cap_entityrelationships?`$select=cap_name"
do {
    $page = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
    foreach ($r in $page.value) { if ($r.cap_name) { $existing[$r.cap_name] = $true } }
    $url = $page.'@odata.nextLink'
} while ($url)

$typeLabel = @{ 764820010="Spouse of"; 764820011="Child of"; 764820013="Associated with"; 764820015="Sibling of" }
$sym = @(764820010, 764820013, 764820015)

# --- 4) LOAD -------------------------------------------------------------------------
$created = 0; $skipped = 0
$findings = New-Object System.Collections.Generic.List[string]
foreach ($row in $edgeList) {
    $from = $row[0]; $to = $row[1]; $tv = $row[2]; $note = $row[3]
    if ($sym -contains $tv -and $from -gt $to) { $tmp=$from; $from=$to; $to=$tmp }
    if (-not $codeToId.ContainsKey($from)) { $findings.Add("FROM '$from' not found ($note)"); continue }
    if (-not $codeToId.ContainsKey($to))   { $findings.Add("TO '$to' not found ($note)"); continue }
    $name = "$from $($typeLabel[$tv]) $to"
    if ($existing.ContainsKey($name)) { $skipped++; continue }
    $body = @{
        cap_name                      = $name
        cap_relationshiptype          = $tv
        cap_notes                     = "Knit 12 Sep 2026 (Pog's Fix): $note"
        "cap_fromentityid@odata.bind" = "/cap_entities($($codeToId[$from]))"
        "cap_toentityid@odata.bind"   = "/cap_entities($($codeToId[$to]))"
    }
    Invoke-RestMethod -Uri "$api/cap_entityrelationships" -Headers $headers -Method Post -Body ($body | ConvertTo-Json) | Out-Null
    $created++
}
Write-Host "Edges created: $created  Skipped(existing): $skipped" -ForegroundColor Green
if ($findings.Count) { $findings | ForEach-Object { Write-Host "  $_" -ForegroundColor Red } }
Write-Host "Duplicate register (LodgeIT merges): BET0003; MCI0005; PHA0003/0006/0008 (Mark); PHA0007 (Robin)" -ForegroundColor Yellow

# --- 5) RETYPE CASCADE ---------------------------------------------------------------
$AA = 100000000; $TAXONLY = 100000010
$entNames = @{}
$url = "$api/cap_entities?`$select=cap_entityid,cap_entityname"
do { $page = Invoke-RestMethod -Uri $url -Headers $headers -Method Get; foreach ($ent in $page.value) { $entNames[$ent.cap_entityid] = $ent.cap_entityname }; $url = $page.'@odata.nextLink' } while ($url)
$graphEdges = @()
$url = "$api/cap_entityrelationships?`$select=_cap_fromentityid_value,_cap_toentityid_value"
do { $page = Invoke-RestMethod -Uri $url -Headers $headers -Method Get; foreach ($r in $page.value) { $graphEdges += ,@($r._cap_fromentityid_value, $r._cap_toentityid_value) }; $url = $page.'@odata.nextLink' } while ($url)
$parent = @{}
foreach ($id in $entNames.Keys) { $parent[$id] = $id }
function Find($x) { while ($parent[$x] -ne $x) { $parent[$x] = $parent[$parent[$x]]; $x = $parent[$x] }; $x }
foreach ($g in $graphEdges) { $a = Find $g[0]; $b = Find $g[1]; if ($a -ne $b) { $parent[$a] = $b } }
$engs = @()
$url = "$api/cap_engagements?`$select=cap_engagementid,cap_name,cap_engagementtype,_cap_entityid_value"
do { $page = Invoke-RestMethod -Uri $url -Headers $headers -Method Get; $engs += $page.value; $url = $page.'@odata.nextLink' } while ($url)
$aaRoots = @{}
foreach ($g in $engs | Where-Object { [int]($_.cap_engagementtype ?? -1) -eq $AA }) {
    if ($g._cap_entityid_value) { $aaRoots[(Find $g._cap_entityid_value)] = $true }
}
$retyped = 0
foreach ($g in $engs | Where-Object { [int]($_.cap_engagementtype ?? -1) -eq $TAXONLY }) {
    $eid = $g._cap_entityid_value
    if (-not $eid -or -not $aaRoots.ContainsKey((Find $eid))) { continue }
    $newName = $g.cap_name -replace 'Tax Only$', 'Annual Accounting'
    Invoke-RestMethod -Uri "$api/cap_engagements($($g.cap_engagementid))" -Headers $headers -Method Patch -Body (@{ cap_engagementtype = $AA; cap_name = $newName } | ConvertTo-Json) | Out-Null
    Write-Host "  Retyped: $($entNames[$eid])" -ForegroundColor Green
    $retyped++
}
Write-Host "Cascade retyped: $retyped" -ForegroundColor Green

# --- VERIFY --------------------------------------------------------------------------
$counts = @{}; $total = 0
$typeName = @{ 100000000="Annual Accounting"; 100000001="SMSF Audit"; 100000010="Tax Only"; 100000011="Virtual CFO" }
$url = "$api/cap_engagements?`$select=cap_engagementtype"
do {
    $page = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
    foreach ($g in $page.value) { $k = $typeName[[int]($g.cap_engagementtype ?? -1)] ?? "?"; $counts[$k] = ($counts[$k] ?? 0) + 1; $total++ }
    $url = $page.'@odata.nextLink'
} while ($url)
Write-Host "`nEngagements by type:" -ForegroundColor Cyan
$counts.GetEnumerator() | Sort-Object Key | ForEach-Object { Write-Host ("  {0,-24} {1}" -f $_.Key, $_.Value) }
Write-Host "TOTAL: $total" -ForegroundColor Green
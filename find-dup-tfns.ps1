# find-dup-tfns.ps1 — report every duplicate TFN in the LodgeIT client export.
# Read-only diagnostic. No Dataverse calls. Prints Code + Name + Archived per offender.
$ErrorActionPreference = "Stop"

# Locate the export by pattern; assert exactly one match so we never scan the wrong file.
$files = @(Get-ChildItem "data\Clients*.csv")
if ($files.Count -ne 1) { Write-Host "Expected 1 clients CSV, found $($files.Count)" -ForegroundColor Red; exit 1 }
$rows = Import-Csv $files[0].FullName

# Header assertion — probe before trusting.
$need = @("Code","Name","TFN","Archived")
$have = $rows[0].PSObject.Properties.Name
$missing = $need | Where-Object { $_ -notin $have }
if ($missing) {
    Write-Host "Missing headers: $($missing -join ', ')" -ForegroundColor Red
    Write-Host "Actual headers: $($have -join ' | ')" -ForegroundColor Yellow
    exit 1
}

# Group non-blank TFNs; any group >1 is an alternate-key casualty.
$dupes = $rows | Where-Object { $_.TFN -and $_.TFN.Trim() -ne "" } |
    Group-Object { $_.TFN.Trim() } | Where-Object { $_.Count -gt 1 }

if (-not $dupes) { Write-Host "No duplicate TFNs found. ($($rows.Count) rows scanned)" -ForegroundColor Green; exit 0 }

Write-Host "DUPLICATE TFN FINDINGS ($($dupes.Count) TFN value(s) shared):" -ForegroundColor Red
foreach ($g in $dupes) {
    Write-Host ""
    Write-Host "  TFN $($g.Name) shared by $($g.Count) records:" -ForegroundColor Red
    $g.Group | ForEach-Object {
        Write-Host ("    {0}  {1}  Archived={2}" -f $_.Code, $_.Name, $_.Archived)
    }
}
Write-Host ""
Write-Host "Resolve in LodgeIT, or rule: later duplicates load WITHOUT TFN." -ForegroundColor Yellow
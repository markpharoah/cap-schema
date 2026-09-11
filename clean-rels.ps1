# clean-rels.ps1 — pre-parse the LodgeIT relationships export (data-prep) - v2
#
# v2 DIAGNOSIS: the export is UTF-16 (Unicode) WITHOUT a BOM. Read as UTF-8,
# every character grows a null twin (property name lengths ~doubled: Code
# visible 4, len 9), CRLF halves masquerade as blank lines (the ghosts), and
# the vocabulary groups under one empty name. Fix: read with -Encoding
# Unicode; belt-and-braces strip any surviving [char]0; then blank-strip,
# write clean UTF-8, parse, TEST.
#
# WORKING NOTE (2 vendors, 2 dialects): ATO exports = utf-8-sig; LodgeIT
# exports = UTF-16 no BOM. Never trust an export's encoding - probe it.

$ErrorActionPreference = "Stop"

$rels = Get-ChildItem .\data\Client*Relationships*.csv | Select-Object -First 1

# Read with the RIGHT encoding; strip stray nulls; drop blank lines
$lines = Get-Content $rels -Encoding Unicode |
         ForEach-Object { $_ -replace [char]0, '' -replace [char]0x00A0, ' ' } |
         Where-Object { $_.Trim().Length -gt 0 }

Write-Host "Lines kept: $($lines.Count) (incl header)" -ForegroundColor Cyan
$lines | Set-Content .\data\rels-clean.csv -Encoding UTF8

# --- TEST 1: property names must be visible-length only ----------------------
$parsed = Import-Csv .\data\rels-clean.csv
$badNames = $parsed[0].PSObject.Properties.Name | Where-Object { $_ -match "`0" }
$typeLen = ($parsed[0].PSObject.Properties.Name | Where-Object { $_ -like "*Type*" }).Length
Write-Host "Parsed records: $($parsed.Count); 'Relationship Type' name length: $typeLen (want 17)" -ForegroundColor $(if ($typeLen -eq 17) { "Green" } else { "Red" })
if ($badNames) { Write-Host "NULLS SURVIVE in property names!" -ForegroundColor Red }

# --- TEST 2: record 1 must parse whole (comma'd name intact) ------------------
Write-Host "`nFirst record:" -ForegroundColor Cyan
$parsed[0] | Format-List

# --- THE VOCABULARY -----------------------------------------------------------
Write-Host "Relationship types:" -ForegroundColor Cyan
$parsed | Group-Object 'Relationship Type' | Select-Object Name, Count | Sort-Object Count -Descending | Format-Table -AutoSize
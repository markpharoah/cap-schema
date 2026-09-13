# _connect.ps1 — standard CAP connection block. Dot-sourced by 31+ scripts.
# Defines: $base (API root), $H (auth headers). Device-code sign-in on first
# run; silent refresh afterwards via token cache in %LOCALAPPDATA%\CAP.

$orgUrl   = "https://org020f7b5c.crm6.dynamics.com"
$base     = "$orgUrl/api/data/v9.2"
$clientId = "51f81489-12ee-4a9e-aaae-a2591f45987d"   # Microsoft public sample client for Dataverse dev
$tokenUri = "https://login.microsoftonline.com/organizations/oauth2/v2.0/token"
$scope    = "$orgUrl/.default offline_access"
$cache    = Join-Path $env:LOCALAPPDATA "CAP\token-cache.json"

function Save-Tok($t) {
    New-Item -ItemType Directory -Force -Path (Split-Path $cache) | Out-Null
    $t | ConvertTo-Json | Set-Content $cache
}

$tok = $null
if (Test-Path $cache) {
    $c = Get-Content $cache -Raw | ConvertFrom-Json
    try {
        $tok = Invoke-RestMethod -Method Post -Uri $tokenUri -Body @{
            client_id = $clientId; grant_type = "refresh_token"
            refresh_token = $c.refresh_token; scope = $scope }
        Save-Tok $tok
    } catch { $tok = $null }
}

if (-not $tok) {
    $dc = Invoke-RestMethod -Method Post `
        -Uri "https://login.microsoftonline.com/organizations/oauth2/v2.0/devicecode" `
        -Body @{ client_id = $clientId; scope = $scope }
    Write-Host $dc.message -ForegroundColor Yellow   # go to the URL, enter the code
    while (-not $tok) {
        Start-Sleep -Seconds $dc.interval
        try {
            $tok = Invoke-RestMethod -Method Post -Uri $tokenUri -Body @{
                client_id = $clientId
                grant_type = "urn:ietf:params:oauth:grant-type:device_code"
                device_code = $dc.device_code }
        } catch {
            $e = ($_.ErrorDetails.Message | ConvertFrom-Json).error
            if ($e -ne "authorization_pending") { throw "Sign-in failed: $e" }
        }
    }
    Save-Tok $tok
}

$H = @{ Authorization = "Bearer $($tok.access_token)"
        "OData-MaxVersion" = "4.0"; "OData-Version" = "4.0"
        Accept = "application/json" }

# sanity ping — fails loudly here rather than mid-script
$who = Invoke-RestMethod -Uri "$base/WhoAmI" -Headers $H
Write-Host "Connected: $orgUrl (user $($who.UserId))" -ForegroundColor Green
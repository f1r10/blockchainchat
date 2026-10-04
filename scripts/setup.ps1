#!/usr/bin/env pwsh
# setup.ps1 — BlockchainChat local test environment setup
# 
# İstifadə: .\scripts\setup.ps1 -ServerIP 192.168.1.100
# ServerIP: bu kompüterin LAN IP-si (telefon/digər maşınlar buna qoşulacaq)

param(
    [Parameter(Mandatory=$false)]
    [string]$ServerIP = ""
)

$ErrorActionPreference = "Stop"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  BlockchainChat — Local Setup" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# ── 1. Server IP tapımı ──────────────────────────────────────
if ($ServerIP -eq "") {
    Write-Host "Detecting server IP..." -ForegroundColor Yellow
    $ServerIP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {
        $_.IPAddress -notlike "127.*" -and
        $_.IPAddress -notlike "169.*" -and
        $_.PrefixOrigin -eq "Dhcp" -or $_.PrefixOrigin -eq "Manual"
    } | Select-Object -First 1).IPAddress

    if (-not $ServerIP) {
        Write-Host "Could not detect IP. Please provide -ServerIP parameter." -ForegroundColor Red
        exit 1
    }
}

Write-Host "Server IP: $ServerIP" -ForegroundColor Green

# ── 2. Flutter app config yenilə ─────────────────────────────
Write-Host "`nUpdating Flutter app config..." -ForegroundColor Yellow

$configPath = ".\client\assets\config\app_config.json"
$config = Get-Content $configPath | ConvertFrom-Json

$config.serverHost = $ServerIP
$config.discoveryUrl = "http://${ServerIP}/api"
$config.blockchainRpc = "http://${ServerIP}/rpc"
$config.relays = @(
    "http://${ServerIP}/relay1",
    "http://${ServerIP}/relay2",
    "http://${ServerIP}/relay3"
)
$config.mailboxes = @(
    "http://${ServerIP}/mailbox1",
    "http://${ServerIP}/mailbox2",
    "http://${ServerIP}/mailbox3",
    "http://${ServerIP}/mailbox4",
    "http://${ServerIP}/mailbox5"
)

$config | ConvertTo-Json -Depth 5 | Set-Content $configPath
Write-Host "App config updated with IP: $ServerIP" -ForegroundColor Green

# ── 3. Docker build & start ───────────────────────────────────
Write-Host "`nBuilding Docker services..." -ForegroundColor Yellow
docker-compose build --no-cache

Write-Host "`nStarting services..." -ForegroundColor Yellow
docker-compose up -d

# ── 4. Servislerin hazır olmasını gözlə ──────────────────────
Write-Host "`nWaiting for services to be ready..." -ForegroundColor Yellow
Start-Sleep -Seconds 15

# Health check
$maxRetries = 10
$retries = 0
while ($retries -lt $maxRetries) {
    try {
        $response = Invoke-RestMethod "http://localhost/health" -TimeoutSec 3
        Write-Host "Server is up!" -ForegroundColor Green
        break
    } catch {
        $retries++
        Write-Host "Waiting... ($retries/$maxRetries)" -ForegroundColor Gray
        Start-Sleep -Seconds 3
    }
}

# ── 5. Smart contract deploy ──────────────────────────────────
Write-Host "`nDeploying smart contract..." -ForegroundColor Yellow
Start-Sleep -Seconds 5  # blockchain hazır olsun

try {
    docker exec chat_blockchain npx hardhat run scripts/deploy.js --network localhost
    Write-Host "Contract deployed!" -ForegroundColor Green
} catch {
    Write-Host "Contract deploy failed (non-critical for prototype)" -ForegroundColor Yellow
}

# ── 6. Flutter web build ──────────────────────────────────────
Write-Host "`nBuilding Flutter web app..." -ForegroundColor Yellow
Push-Location .\client
    flutter pub get
    flutter build web --release --base-href /
Pop-Location

# Build fayllarını nginx qovluğuna kopyala
New-Item -ItemType Directory -Force -Path ".\client\build\web" | Out-Null
Write-Host "Flutter web build complete!" -ForegroundColor Green

# ── 7. Nginx reload ───────────────────────────────────────────
docker exec chat_nginx nginx -s reload 2>$null

# ── 8. Nəticə ─────────────────────────────────────────────────
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Setup Complete!" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Web App:    http://${ServerIP}" -ForegroundColor Green
Write-Host "Discovery:  http://${ServerIP}/api/config" -ForegroundColor Green
Write-Host "Blockchain: http://${ServerIP}:8545" -ForegroundColor Green
Write-Host ""
Write-Host "For APK build:" -ForegroundColor Yellow
Write-Host "  .\scripts\build_apk.ps1 -ServerIP $ServerIP" -ForegroundColor White
Write-Host ""
Write-Host "Other devices on the same network can access:" -ForegroundColor Yellow
Write-Host "  http://${ServerIP}" -ForegroundColor White
Write-Host ""

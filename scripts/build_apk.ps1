#!/usr/bin/env pwsh
# build_apk.ps1 — Flutter APK build
#
# İstifadə: .\scripts\build_apk.ps1 -ServerIP 192.168.1.100

param(
    [Parameter(Mandatory=$true)]
    [string]$ServerIP
)

Write-Host "`nBuilding APK for server: $ServerIP`n" -ForegroundColor Cyan

# Config yenilə
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

Push-Location .\client
    flutter pub get
    
    # Gradle Java versiyası düzəltmə
    $gradleProps = ".\android\gradle.properties"
    if (-not (Test-Path $gradleProps)) {
        "org.gradle.jvmargs=-Xmx4g" | Set-Content $gradleProps
    }
    
    flutter build apk --release
    
    $apkPath = ".\build\app\outputs\flutter-apk\app-release.apk"
    if (Test-Path $apkPath) {
        $destPath = "..\blockchainchat-${ServerIP}.apk"
        Copy-Item $apkPath $destPath -Force
        Write-Host "`nAPK ready: $destPath" -ForegroundColor Green
        Write-Host "Install on Android: adb install $destPath" -ForegroundColor Yellow
    }
Pop-Location

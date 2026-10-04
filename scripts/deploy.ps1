param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("blockchain", "relay", "mailbox", "web", "apk")]
    [string]$Role,

    [Parameter(Mandatory=$false)]
    [string]$BlockchainRpc = "http://127.0.0.1:8545",

    [Parameter(Mandatory=$false)]
    [string]$ContractAddress = "",

    [Parameter(Mandatory=$false)]
    [int]$Port = 0
)

$ErrorActionPreference = "Stop"

# Get Local LAN IP
$LocalIP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {
    $_.IPAddress -notlike "127.*" -and
    $_.IPAddress -notlike "169.*" -and
    ($_.PrefixOrigin -eq "Dhcp" -or $_.PrefixOrigin -eq "Manual")
} | Select-Object -First 1).IPAddress

if (-not $LocalIP) { $LocalIP = "127.0.0.1" }

Write-Host ""
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "  BlockchainChat Decentralized Node Deployment" -ForegroundColor Cyan
Write-Host "  Role: $Role | Local IP: $LocalIP" -ForegroundColor Yellow
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ""

switch ($Role) {
    "blockchain" {
        Write-Host "[*] Starting Hardhat Blockchain RPC Node..." -ForegroundColor Green
        Push-Location "$PSScriptRoot\..\server\blockchain"
            cmd.exe /c npm install
            Write-Host "[*] Compiling contracts..." -ForegroundColor Yellow
            cmd.exe /c npx hardhat compile
            
            Write-Host "[*] Starting Hardhat node on 0.0.0.0:8545..." -ForegroundColor Yellow
            Start-Process -FilePath "cmd.exe" -ArgumentList "/c npx hardhat node --hostname 0.0.0.0" -PassThru
            
            Start-Sleep -Seconds 5
            Write-Host "[*] Deploying NodeAndUserRegistry contract..." -ForegroundColor Yellow
            cmd.exe /c npx hardhat run scripts/deploy.js --network localhost

            if (Test-Path "deployed.json") {
                $deployJson = Get-Content "deployed.json" | ConvertFrom-Json
                Write-Host ""
                Write-Host "[+] Smart Contract Deployed Successfully!" -ForegroundColor Green
                Write-Host "====================================================" -ForegroundColor Cyan
                Write-Host "Settings for other machines:" -ForegroundColor White
                Write-Host "BlockchainRpc:   http://${LocalIP}:8545" -ForegroundColor Yellow
                Write-Host "ContractAddress: $($deployJson.contractAddress)" -ForegroundColor Yellow
                Write-Host "====================================================" -ForegroundColor Cyan
                Write-Host ""
            }
        Pop-Location
    }

    "relay" {
        if ($Port -eq 0) { $Port = 3001 }
        if (-not $ContractAddress) {
            Write-Host "[-] Error: -ContractAddress is required for Relay!" -ForegroundColor Red
            exit 1
        }
        Write-Host "[*] Starting Mix/Relay Node on Port $Port..." -ForegroundColor Green
        Push-Location "$PSScriptRoot\..\server\relay"
            cmd.exe /c npm install
            $env:NODE_PORT = "$Port"
            $env:MY_IP = "$LocalIP"
            $env:BLOCKCHAIN_RPC = "$BlockchainRpc"
            $env:CONTRACT_ADDRESS = "$ContractAddress"
            node index.js
        Pop-Location
    }

    "mailbox" {
        if ($Port -eq 0) { $Port = 4001 }
        if (-not $ContractAddress) {
            Write-Host "[-] Error: -ContractAddress is required for Mailbox!" -ForegroundColor Red
            exit 1
        }
        Write-Host "[*] Starting Anonymous Mailbox Node on Port $Port..." -ForegroundColor Green
        Push-Location "$PSScriptRoot\..\server\mailbox"
            cmd.exe /c npm install
            $env:MAILBOX_PORT = "$Port"
            $env:MY_IP = "$LocalIP"
            $env:BLOCKCHAIN_RPC = "$BlockchainRpc"
            $env:CONTRACT_ADDRESS = "$ContractAddress"
            node index.js
        Pop-Location
    }

    "web" {
        if (-not $ContractAddress) {
            Write-Host "[-] Error: -ContractAddress is required for Web!" -ForegroundColor Red
            exit 1
        }
        Write-Host "[*] Configuring Flutter Web..." -ForegroundColor Yellow
        $cfgPath = "$PSScriptRoot\..\client\assets\config\app_config.json"
        $cfg = Get-Content $cfgPath | ConvertFrom-Json
        $cfg.blockchainRpc = $BlockchainRpc
        $cfg.contractAddress = $ContractAddress
        $cfg | ConvertTo-Json -Depth 5 | Set-Content $cfgPath

        Push-Location "$PSScriptRoot\..\client"
            flutter pub get
            flutter build web --release
        Pop-Location

        Write-Host "[+] Web build ready in client\build\web" -ForegroundColor Green
        Write-Host "Serve it with: npx serve .\client\build\web -p 80" -ForegroundColor Cyan
    }

    "apk" {
        if (-not $ContractAddress) {
            Write-Host "[-] Error: -ContractAddress is required for APK!" -ForegroundColor Red
            exit 1
        }
        Write-Host "[*] Building Android APK..." -ForegroundColor Yellow
        $cfgPath = "$PSScriptRoot\..\client\assets\config\app_config.json"
        $cfg = Get-Content $cfgPath | ConvertFrom-Json
        $cfg.blockchainRpc = $BlockchainRpc
        $cfg.contractAddress = $ContractAddress
        $cfg | ConvertTo-Json -Depth 5 | Set-Content $cfgPath

        Push-Location "$PSScriptRoot\..\client"
            flutter pub get
            flutter build apk --release
            $apk = ".\build\app\outputs\flutter-apk\app-release.apk"
            if (Test-Path $apk) {
                Copy-Item $apk "..\BlockchainChat.apk" -Force
                Write-Host ""
                Write-Host "[+] APK ready: ..\BlockchainChat.apk" -ForegroundColor Green
                Write-Host "Install this APK on Android devices." -ForegroundColor White
            }
        Pop-Location
    }
}

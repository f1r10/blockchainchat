#!/usr/bin/env pwsh
# status.ps1 — Bütün servislərin statusunu yoxla

Write-Host "`n=== BlockchainChat Service Status ===`n" -ForegroundColor Cyan

$services = @(
    @{ Name = "Blockchain"; Url = "http://localhost:8545" },
    @{ Name = "Discovery"; Url = "http://localhost:5000/health" },
    @{ Name = "Relay 1"; Url = "http://localhost:3001/health" },
    @{ Name = "Relay 2"; Url = "http://localhost:3002/health" },
    @{ Name = "Relay 3"; Url = "http://localhost:3003/health" },
    @{ Name = "Mailbox 1"; Url = "http://localhost:4001/health" },
    @{ Name = "Mailbox 2"; Url = "http://localhost:4002/health" },
    @{ Name = "Mailbox 3"; Url = "http://localhost:4003/health" },
    @{ Name = "Mailbox 4"; Url = "http://localhost:4004/health" },
    @{ Name = "Mailbox 5"; Url = "http://localhost:4005/health" },
    @{ Name = "Nginx/Web"; Url = "http://localhost/status" }
)

foreach ($svc in $services) {
    try {
        $resp = Invoke-RestMethod $svc.Url -TimeoutSec 3
        Write-Host "  ✅ $($svc.Name)" -ForegroundColor Green
    } catch {
        Write-Host "  ❌ $($svc.Name)" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "Docker containers:" -ForegroundColor Yellow
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
Write-Host ""

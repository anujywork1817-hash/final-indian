# ============================================
# keep-tunnel.ps1 — hold the adb reverse tunnel open
# ============================================
#
# Run this in a SECOND terminal alongside `flutter run`:
#
#     .\keep-tunnel.ps1
#
# Why this exists: `adb reverse` is not durable. It is dropped
# whenever the adb server restarts, the device reconnects, or
# `flutter run` attaches — which happens on every launch and
# every hot restart that reinstalls. When the tunnel is gone the
# phone's localhost:18090 has nothing listening, and every API
# call fails with "Connection refused".
#
# This script re-applies the tunnel on a short interval, so the
# app keeps working across relaunches without you remembering.
#
# Ctrl+C to stop.

param(
    [int]$Port = 18090,
    [int]$IntervalSeconds = 3
)

$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
if (-not (Test-Path $adb)) {
    $found = Get-Command adb -ErrorAction SilentlyContinue
    if ($found) { $adb = $found.Source } else { throw "adb.exe not found" }
}

Write-Host "Holding adb reverse tcp:$Port -> tcp:$Port (Ctrl+C to stop)" -ForegroundColor Cyan
Write-Host "Backend must be running: .\..\kumbh_backend\run-local.ps1" -ForegroundColor DarkGray
Write-Host ""

$lastState = ""

while ($true) {
    $devices = & $adb devices 2>$null | Select-String -Pattern "\sdevice$"

    if (-not $devices) {
        if ($lastState -ne "nodevice") {
            Write-Host ("[" + (Get-Date -Format "HH:mm:ss") + "] no device attached - waiting") -ForegroundColor Yellow
            $lastState = "nodevice"
        }
    } else {
        $list = & $adb reverse --list 2>$null | Out-String

        if ($list -notmatch "tcp:$Port") {
            # Tunnel is missing or was just dropped — restore it.
            & $adb reverse "tcp:$Port" "tcp:$Port" 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Host ("[" + (Get-Date -Format "HH:mm:ss") + "] tunnel (re)established on $Port") -ForegroundColor Green
            } else {
                Write-Host ("[" + (Get-Date -Format "HH:mm:ss") + "] failed to create tunnel") -ForegroundColor Red
            }
            $lastState = "restored"
        } elseif ($lastState -ne "ok") {
            Write-Host ("[" + (Get-Date -Format "HH:mm:ss") + "] tunnel active on $Port") -ForegroundColor Green
            $lastState = "ok"
        }
    }

    Start-Sleep -Seconds $IntervalSeconds
}

# ============================================
# run-local.ps1 — start the whole backend on localhost
# ============================================
#
#   .\run-local.ps1            build (if needed) and start all 5 services
#   .\run-local.ps1 -Rebuild   force a rebuild first
#   .\run-local.ps1 -Stop      stop everything
#
# Requires a local PostgreSQL with the kumbh_tent database
# already migrated (schema.sql + migrations/001 + 002).
#
# Config note: these values are exported into the environment
# BEFORE each service starts. godotenv.Load() never overrides
# an already-set variable, so this cleanly overrides the
# docker-compose-oriented .env (which points DATABASE_URL at
# the container hostname "postgres" and the service URLs at
# container DNS names — neither resolves when running natively).

param(
    [switch]$Rebuild,
    [switch]$Stop
)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$bin  = Join-Path $root "bin"
$logs = Join-Path $root "logs"

# Gateway is on 18090, well away from the usual 8080/8090 range.
# Two separate things fight for those ports on this machine:
#   * 8080 - Desktop\kumbh-backend-update\kumbh-local.exe, an
#            unrelated project. It also answers /health with 200,
#            so a naive check reports "up" while our gateway has
#            actually died with a bind error.
#   * 8090 - com.docker.backend grabs it opportunistically when
#            Docker Desktop starts, if nothing else holds it.
# 18090 is outside Windows' reserved Hyper-V/WSL ranges (check
# with: netsh int ipv4 show excludedportrange protocol=tcp).
$services = @(
    @{ Name = "auth-service";    Port = 8081 },
    @{ Name = "tent-service";    Port = 8082 },
    @{ Name = "booking-service"; Port = 8083 },
    @{ Name = "payment-service"; Port = 8084 },
    @{ Name = "api-gateway";     Port = 18090 }
)

# ── Stop ────────────────────────────────────────────────
function Stop-All {
    $stopped = 0
    foreach ($s in $services) {
        $procs = Get-Process -Name $s.Name -ErrorAction SilentlyContinue
        foreach ($p in $procs) {
            Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
            $stopped++
        }
    }
    Write-Host "Stopped $stopped service process(es)." -ForegroundColor Yellow
}

if ($Stop) { Stop-All; exit 0 }

# ── Local environment ───────────────────────────────────
$env:DATABASE_URL = "postgres://postgres:root@localhost:5432/kumbh_tent?sslmode=disable"
$env:JWT_SECRET   = "kumbh2027localdevsecret"

$env:API_GATEWAY_PORT     = "18090"
$env:AUTH_SERVICE_PORT    = "8081"
$env:TENT_SERVICE_PORT    = "8082"
$env:BOOKING_SERVICE_PORT = "8083"
$env:PAYMENT_SERVICE_PORT = "8084"

# Gateway talks to the other services over loopback, not
# container DNS.
$env:AUTH_SERVICE_URL    = "http://localhost:8081"
$env:TENT_SERVICE_URL    = "http://localhost:8082"
$env:BOOKING_SERVICE_URL = "http://localhost:8083"
$env:PAYMENT_SERVICE_URL = "http://localhost:8084"

# Razorpay test keys. Order creation and refunds call the real
# Razorpay API and will fail without valid credentials — that
# is expected locally and does not stop the rest of the app.
if (-not $env:RAZORPAY_KEY_ID)     { $env:RAZORPAY_KEY_ID     = "rzp_test_SqpASBdCN2DXd0" }
if (-not $env:RAZORPAY_KEY_SECRET) { $env:RAZORPAY_KEY_SECRET = "0CA01F0L5t325WgA1FcQQKth" }

# Refund policy: full refund, no fee (the shipped default).
$env:REFUND_ENABLED                = "true"
# Cancellations create a refund REQUEST that staff approve in the
# admin panel; nothing reaches Razorpay until then.
$env:REFUND_REQUIRE_APPROVAL       = "true"
$env:REFUND_TIERS                  = ""
$env:REFUND_FEE_PERCENT            = "0"
$env:REFUND_SETTLEMENT_DAYS        = "3-4"
$env:REFUND_MAX_ATTEMPTS           = "6"
$env:REFUND_RETRY_INTERVAL_MINUTES = "15"

# ── Build ───────────────────────────────────────────────
if (-not (Test-Path $bin)) { New-Item -ItemType Directory -Path $bin | Out-Null }
if (-not (Test-Path $logs)) { New-Item -ItemType Directory -Path $logs | Out-Null }

$needBuild = $Rebuild
if (-not $needBuild) {
    foreach ($s in $services) {
        if (-not (Test-Path (Join-Path $bin ($s.Name + ".exe")))) { $needBuild = $true }
    }
}

if ($needBuild) {
    Write-Host "Building services..." -ForegroundColor Cyan
    Push-Location $root
    foreach ($s in $services) {
        & go build -o (Join-Path $bin ($s.Name + ".exe")) ("./" + $s.Name)
        if ($LASTEXITCODE -ne 0) { Pop-Location; throw ("build failed: " + $s.Name) }
        Write-Host ("  built " + $s.Name) -ForegroundColor DarkGray
    }
    Pop-Location
}

# ── Start ───────────────────────────────────────────────
Stop-All
Write-Host ""
Write-Host "Starting services..." -ForegroundColor Cyan

foreach ($s in $services) {
    $exe    = Join-Path $bin ($s.Name + ".exe")
    $stdout = Join-Path $logs ($s.Name + ".log")
    $stderr = Join-Path $logs ($s.Name + ".err.log")

    # Working directory is bin\, which has no .env file, so the
    # environment above is the single source of configuration.
    Start-Process -FilePath $exe -WorkingDirectory $bin `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr `
        -WindowStyle Hidden | Out-Null

    Write-Host ("  " + $s.Name.PadRight(16) + " :" + $s.Port) -ForegroundColor DarkGray
}

# ── Health check ────────────────────────────────────────
Write-Host ""
Write-Host "Waiting for health checks..." -ForegroundColor Cyan

$deadline = (Get-Date).AddSeconds(30)
$healthy  = @{}
$conflict = @{}

while ((Get-Date) -lt $deadline -and $healthy.Count -lt $services.Count) {
    foreach ($s in $services) {
        if ($healthy.ContainsKey($s.Name)) { continue }
        try {
            $r = Invoke-WebRequest -Uri ("http://localhost:" + $s.Port + "/health") `
                    -TimeoutSec 2 -UseBasicParsing
            # HTTP 200 alone is NOT proof our service is there —
            # an unrelated app on the same port answers 200 too.
            # Require the health body to name this exact service.
            if ($r.StatusCode -eq 200) {
                $body = $r.Content | ConvertFrom-Json
                if ($body.service -eq $s.Name) {
                    $healthy[$s.Name] = $true
                } else {
                    # Port is held by a different application.
                    $conflict[$s.Name] = $body.service
                }
            }
        } catch { }
    }
    if ($healthy.Count -lt $services.Count) { Start-Sleep -Milliseconds 500 }
}

Write-Host ""
foreach ($s in $services) {
    if ($healthy.ContainsKey($s.Name)) {
        Write-Host ("  [OK]   " + $s.Name.PadRight(16) + " http://localhost:" + $s.Port) -ForegroundColor Green
    } elseif ($conflict.ContainsKey($s.Name)) {
        Write-Host ("  [PORT] " + $s.Name.PadRight(16) + " :" + $s.Port + " is held by '" + $conflict[$s.Name] + "' - change the port") -ForegroundColor Red
    } else {
        Write-Host ("  [FAIL] " + $s.Name.PadRight(16) + " see logs\" + $s.Name + ".err.log") -ForegroundColor Red
    }
}

Write-Host ""
if ($healthy.Count -eq $services.Count) {
    $gwPort = ($services | Where-Object { $_.Name -eq "api-gateway" }).Port
    Write-Host ("All services up. API base: http://localhost:" + $gwPort + "/api/v1") -ForegroundColor Green
    Write-Host "Stop with: .\run-local.ps1 -Stop" -ForegroundColor DarkGray
} else {
    Write-Host "Some services failed to start. Check the logs\ directory." -ForegroundColor Red
    exit 1
}

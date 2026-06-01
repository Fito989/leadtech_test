<#
.SYNOPSIS
  One-command runner for the CV Screener: (optionally) generate CVs + build the
  index, start the Dart Frog backend, then launch the Flutter web app.

.EXAMPLE
  ./scripts/run_all.ps1
  ./scripts/run_all.ps1 -Count 6          # generate fewer CVs (faster / less quota)
  ./scripts/run_all.ps1 -SkipGenerate -SkipIngest   # data already prepared
#>
param(
  [switch]$SkipGenerate,
  [switch]$SkipIngest,
  [int]$Count = 0,
  [string]$Device = "chrome",                 # e.g. chrome | emulator-5554
  [string]$BackendUrl = "http://localhost:8080"
)

# From inside an Android emulator, the host's localhost is 10.0.2.2.
$appUrl = if ($Device -match "emulator|android") { "http://10.0.2.2:8080" } else { $BackendUrl }

$ErrorActionPreference = "Stop"
$root    = Split-Path -Parent $PSScriptRoot
$backend = Join-Path $root "backend"
$app     = Join-Path $root "app"
$frog    = "dart pub global run dart_frog_cli:dart_frog"

# Kill any process still listening on a TCP port (frees a stale backend).
function Clear-Port {
  param([int]$Port)
  $conns = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
  foreach ($procId in ($conns.OwningProcess | Sort-Object -Unique)) {
    try {
      Stop-Process -Id $procId -Force -ErrorAction Stop
      Write-Host "    freed port $Port (stopped PID $procId)" -ForegroundColor DarkGray
    } catch {}
  }
}

# 1. Secrets check ----------------------------------------------------------
if (-not (Test-Path (Join-Path $backend ".env"))) {
  Write-Error "backend/.env not found. Run: Copy-Item backend/.env.example backend/.env  then add your GEMINI_API_KEY."
}

# 2. Generate CVs (only if none exist) -------------------------------------
$cvDir = Join-Path $backend "data/cvs"
$haveCvs = (Test-Path $cvDir) -and ((Get-ChildItem $cvDir -Filter *.pdf -ErrorAction SilentlyContinue).Count -gt 0)
if (-not $SkipGenerate -and -not $haveCvs) {
  Write-Host "==> Generating CVs..." -ForegroundColor Cyan
  Push-Location $backend
  try {
    if ($Count -gt 0) { dart run tools/generate_cvs.dart --count $Count }
    else { dart run tools/generate_cvs.dart }
  } finally { Pop-Location }
} else {
  Write-Host "==> Skipping CV generation (use without -SkipGenerate to force when empty)." -ForegroundColor DarkGray
}

# 3. Build the vector index (only if missing) ------------------------------
$index = Join-Path $backend "data/index/embeddings.json"
if (-not $SkipIngest -and -not (Test-Path $index)) {
  Write-Host "==> Ingesting CVs -> vector index..." -ForegroundColor Cyan
  Push-Location $backend
  try { dart run tools/ingest.dart } finally { Pop-Location }
} else {
  Write-Host "==> Skipping ingest." -ForegroundColor DarkGray
}

# Clear a stale backend so the port is free.
$port = ([uri]$BackendUrl).Port
Write-Host "==> Clearing anything on port $port ..." -ForegroundColor Cyan
Clear-Port -Port $port

# 4. Start the backend in a new window -------------------------------------
Write-Host "==> Starting backend in a new window ($BackendUrl)..." -ForegroundColor Cyan
Start-Process powershell -ArgumentList "-NoExit", "-Command", "Set-Location '$backend'; $frog dev"

# 5. Wait for the backend to report healthy --------------------------------
Write-Host "==> Waiting for backend health..." -ForegroundColor Cyan
$healthy = $false
for ($i = 0; $i -lt 30; $i++) {
  try {
    $r = Invoke-WebRequest "$BackendUrl/health" -UseBasicParsing -TimeoutSec 3
    if ($r.StatusCode -eq 200) { $healthy = $true; break }
  } catch { Start-Sleep -Seconds 2 }
}
if ($healthy) { Write-Host "    backend is up." -ForegroundColor Green }
else { Write-Warning "Backend not healthy yet; launching the app anyway." }

# 6. Launch the Flutter app -------------------------------------------------
Write-Host "==> Launching Flutter app on '$Device' (backend $appUrl)..." -ForegroundColor Cyan
Push-Location $app
try { flutter run -d $Device --dart-define=BACKEND_BASE_URL=$appUrl }
finally { Pop-Location }

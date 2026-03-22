param(
    [string]$ServiceName = "nanobot-gateway",
    [string]$RepoPath = "D:\storage\nanobot",
    [string]$ConfigPath = "C:\Users\admin\.nanobot\config.json",
    [switch]$SkipServiceRestart
)

$ErrorActionPreference = "Stop"
$BuildDir = Join-Path $env:TEMP "nanobot-private-network-build"

function Write-Step($msg) {
    Write-Host "`n==> $msg" -ForegroundColor Cyan
}

function Test-CommandExists($name) {
    return $null -ne (Get-Command $name -ErrorAction SilentlyContinue)
}

Write-Step "Checking prerequisites"
if (-not (Test-Path $RepoPath)) {
    throw "Repo path not found: $RepoPath"
}
if (-not (Test-Path (Join-Path $RepoPath "pyproject.toml"))) {
    throw "pyproject.toml not found under repo path: $RepoPath"
}
if (-not (Test-Path $ConfigPath)) {
    throw "Config file not found: $ConfigPath"
}
if (-not (Test-CommandExists "uv")) {
    throw "uv command not found in PATH"
}
if (-not (Test-CommandExists "sc.exe")) {
    throw "sc.exe not found"
}

Write-Step "Stopping service if it exists"
$service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($service) {
    if ($service.Status -ne 'Stopped') {
        Stop-Service -Name $ServiceName -Force
        $service.WaitForStatus('Stopped', '00:00:20')
    }
} else {
    Write-Host "Service not found, continuing: $ServiceName" -ForegroundColor Yellow
}

Write-Step "Checking current nanobot version"
$existingNanobot = Get-Command nanobot -ErrorAction SilentlyContinue
if ($existingNanobot) {
    Write-Host "Current nanobot command: $($existingNanobot.Source)"
    & $existingNanobot.Source --version
} else {
    Write-Host "nanobot command not currently found in PATH" -ForegroundColor Yellow
}

Write-Step "Building wheel from local source"
if (Test-Path $BuildDir) {
    Remove-Item -Recurse -Force $BuildDir
}
New-Item -ItemType Directory -Path $BuildDir | Out-Null
uv build --wheel --out-dir $BuildDir $RepoPath
$wheel = Get-ChildItem -Path $BuildDir -Filter "nanobot_ai-*.whl" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $wheel) {
    throw "Wheel build did not produce a nanobot wheel under: $BuildDir"
}
Write-Host "Built wheel: $($wheel.FullName)"

Write-Step "Uninstalling current uv tool install of nanobot-ai"
uv tool uninstall nanobot-ai

Write-Step "Installing nanobot-ai from built wheel"
uv tool install $wheel.FullName

Write-Step "Verifying local installation"
$nanobotCmd = (Get-Command nanobot -ErrorAction Stop).Source
Write-Host "New nanobot command: $nanobotCmd"
& $nanobotCmd --version

Write-Step "Running direct gateway smoke test with explicit config"
$smoke = Start-Process -FilePath $nanobotCmd -ArgumentList @('gateway', '--config', $ConfigPath) -PassThru -WindowStyle Hidden
Start-Sleep -Seconds 8
if ($smoke.HasExited) {
    throw "Smoke test failed: nanobot gateway exited early with code $($smoke.ExitCode)"
}
Stop-Process -Id $smoke.Id -Force
Start-Sleep -Seconds 2

if (-not $SkipServiceRestart) {
    Write-Step "Restarting service"
    Start-Service -Name $ServiceName
    Start-Sleep -Seconds 6

    Write-Step "Checking service status"
    $svc = Get-Service -Name $ServiceName -ErrorAction Stop
    Write-Host "Service status: $($svc.Status)"
    if ($svc.Status -ne 'Running') {
        throw "Service did not reach Running state"
    }
}

Write-Step "Done"
$finalService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($finalService) {
    Write-Host "Final service status: $($finalService.Status)"
} else {
    Write-Host "Final service status: service not found" -ForegroundColor Yellow
}
Write-Host "Local source installation completed successfully." -ForegroundColor Green
Write-Host "Repo: $RepoPath"
Write-Host "Config: $ConfigPath"

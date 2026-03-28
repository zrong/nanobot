param(
    [string]$TaskName = "nanobot-gateway",
    [string]$RepoPath = "D:\storage\nanobot",
    [string]$ConfigPath = "C:\Users\admin\.nanobot\config.json",
    [string]$NanobotPath = "C:\Users\admin\.local\bin\nanobot.exe",
    [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"

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

# Step 1: Build wheel from local source
if (-not $SkipBuild) {
    Write-Step "Building wheel from local source"
    $BuildDir = Join-Path $env:TEMP "nanobot-private-network-build"
    if (Test-Path $BuildDir) {
        Remove-Item -Recurse -Force $BuildDir
    }
    New-Item -ItemType Directory -Path $BuildDir | Out-Null
    uv build --wheel --out-dir $BuildDir $RepoPath
    $wheel = Get-ChildItem -Path $BuildDir -Filter "nanobot_ai-*.whl" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $wheel) {
        throw "Wheel build failed: no nanobot wheel found under: $BuildDir"
    }
    Write-Host "Built wheel: $($wheel.FullName)"

    Write-Step "Uninstalling current uv tool install of nanobot-ai"
    uv tool uninstall nanobot-ai

    Write-Step "Installing nanobot-ai from built wheel"
    uv tool install $wheel.FullName
} else {
    Write-Step "Skipping build (SkipBuild set), using existing nanobot installation"
}

Write-Step "Verifying nanobot installation"
$nanobotCmd = Get-Command nanobot -ErrorAction SilentlyContinue
if (-not $nanobotCmd) {
    throw "nanobot command not found in PATH after installation"
}
Write-Host "nanobot command: $($nanobotCmd.Source)"
& $nanobotCmd.Source --version

# Step 2: Register / update Task Scheduler task
Write-Step "Registering Task Scheduler task: $TaskName"
$taskExists = $null -ne (schtasks /query /tn $TaskName 2>$null)
$action = "$NanobotPath gateway --config $ConfigPath"

if ($taskExists) {
    Write-Host "Task already exists, updating..."
    schtasks /change /tn $TaskName /tr "`"$action`"" /enable | Out-Null
} else {
    Write-Host "Creating new task..."
    schtasks /create /tn $TaskName /tr "`"$action`"" /sc onlogon /rl limited /f
}

Write-Step "Verifying task"
$task = schtasks /query /tn $TaskName /fo list 2>$null | Out-String
if ($task) {
    Write-Host $task
} else {
    throw "Task registration failed: could not query $TaskName"
}

Write-Step "Done"
Write-Host ""
Write-Host "Task Scheduler setup completed successfully." -ForegroundColor Green
Write-Host "Task '$TaskName' will run nanobot gateway on every login." -ForegroundColor Green
Write-Host "Repo: $RepoPath"
Write-Host "Config: $ConfigPath"
Write-Host ""
Write-Host "To trigger manually now:" -ForegroundColor Yellow
Write-Host "  schtasks /run /tn `"$TaskName`"" -ForegroundColor Yellow

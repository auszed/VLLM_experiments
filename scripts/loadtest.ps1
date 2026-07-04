# Run the load test against VLLM_BASE_URL, then log results to MLflow.
# One command = one comparable experiment run.
#
#   ./scripts/loadtest.ps1                       # default local ramp
#   ./scripts/loadtest.ps1 -Concurrency "1,4,16,64,128,256" -GpuCount 2 -GpuType H100-80G

param(
    [string]$Concurrency = "32,64,96,128,160",
    [int]$Requests = 160,
    [int]$MaxTokens = 64,
    [double]$SloMs = 15000,
    [string]$GpuType = "GTX-1660Ti",
    [int]$GpuCount = 1,
    [string]$Experiment = "",
    [switch]$NewExperiment
)

# -NewExperiment logs to a fresh timestamped experiment (isolated per run).
if ($NewExperiment) {
    $Experiment = "vllm-loadtest-" + (Get-Date -Format "yyyyMMdd-HHmmss")
}

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent

# Load .env into the process
Get-Content "$root\.env" | Where-Object { $_ -match '^\s*[^#].+=' } | ForEach-Object {
    $name, $value = $_ -split '=', 2
    [Environment]::SetEnvironmentVariable($name.Trim(), $value.Trim(), "Process")
}

# Build the Go load tester. Find go.exe robustly: 32-bit make sets
# %ProgramFiles% to the x86 path, so also check ProgramW6432 (real 64-bit dir).
$go = (Get-Command go -ErrorAction SilentlyContinue).Source
if (-not $go) {
    $go = @(
        "$env:ProgramW6432\Go\bin\go.exe",
        "$env:ProgramFiles\Go\bin\go.exe",
        "C:\Program Files\Go\bin\go.exe",
        "$env:LOCALAPPDATA\Programs\Go\bin\go.exe"
    ) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
}
if (-not $go) { throw "go.exe not found. Install Go or add it to PATH." }
$lt = Join-Path $root "loadtest"
Push-Location $lt
& $go build -o loadtest.exe .

# Run it against the configured endpoint
.\loadtest.exe -url $env:VLLM_BASE_URL -key $env:VLLM_API_KEY `
    -concurrency $Concurrency -requests $Requests -max-tokens $MaxTokens `
    -slo-ms $SloMs -out results.json
Pop-Location

# Log the run to MLflow (fresh experiment if -Experiment/-NewExperiment given)
Push-Location (Join-Path $root "test")
$expArg = if ($Experiment) { @("--experiment", $Experiment) } else { @() }
uv run python log_to_mlflow.py "$lt\results.json" --gpu-type $GpuType --gpu-count $GpuCount @expArg
Pop-Location

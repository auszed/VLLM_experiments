# Run the load test against VLLM_BASE_URL, then log results to MLflow.
# One command = one comparable experiment run.
#
#   ./scripts/loadtest.ps1                       # default local ramp
#   ./scripts/loadtest.ps1 -Concurrency "1,4,16,64,128,256" -GpuCount 2 -GpuType H100-80G

param(
    [string]$Concurrency = "32,64,96,128,160",
    [int]$Requests = 160,
    [double]$Temperature = 0,
    [int]$MaxTokens = 64,
    [double]$SloMs = 15000,
    [string]$GpuType = "GTX-1660Ti",
    [int]$GpuCount = 1,
    [bool]$TraceCalls = $true,
    [int]$MaxTraces = 0,
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

# .env values apply unless the value was passed explicitly on the CLI (CLI wins).
# Must run here: .env is loaded above, after PowerShell binds the param defaults.
if (-not $PSBoundParameters.ContainsKey('Concurrency') -and $env:LOADTEST_CONCURRENCY) { $Concurrency = $env:LOADTEST_CONCURRENCY }
if (-not $PSBoundParameters.ContainsKey('Requests')    -and $env:LOADTEST_REQUESTS)    { $Requests    = [int]$env:LOADTEST_REQUESTS }
if (-not $PSBoundParameters.ContainsKey('Temperature') -and $env:LOADTEST_TEMPERATURE) { $Temperature = [double]$env:LOADTEST_TEMPERATURE }

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

# Run it against the configured endpoint. -trace captures every request/response into
# results.json so each call can be logged as a per-call MLflow trace afterward.
# Pass the bool as -trace=true/false (single arg): a `@("-trace")` splat gets
# character-split to "- t r a c e" by a direct native call in Windows PowerShell 5.1.
$traceFlag = "-trace=" + $TraceCalls.ToString().ToLower()
.\loadtest.exe -url $env:VLLM_BASE_URL -key $env:VLLM_API_KEY `
    -concurrency $Concurrency -requests $Requests -max-tokens $MaxTokens `
    -temperature $Temperature -slo-ms $SloMs $traceFlag -out results.json
Pop-Location

# Log throughput metrics to MLflow (fresh experiment if -Experiment/-NewExperiment given).
# With -TraceCalls, also log one trace per request (Traces tab) with its own latency/tokens.
# Answer quality (distinct questions) is checked separately by scripts/eval.ps1 (make eval).
Push-Location (Join-Path $root "test")
$expArg = if ($Experiment) { @("--experiment", $Experiment) } else { @() }
$traceArg = if ($TraceCalls) { @("--trace-calls", "--max-traces", "$MaxTraces") } else { @() }
uv run python log_to_mlflow.py "$lt\results.json" --gpu-type $GpuType --gpu-count $GpuCount `
    @traceArg @expArg
Pop-Location

# Stop (or terminate) the RunPod pod to end GPU billing.
# Runs on your Windows PC. Uses the RunPod REST API.
#
# Needs in .env:
#   RUNPOD_API_KEY   your RunPod ACCOUNT api key (Settings -> API Keys)
#                    NOTE: this is different from VLLM_API_KEY.
#   RUNPOD_POD_ID    the pod id (from the pod's page / URL)
#
#   ./scripts/stop_runpod.ps1              # stop: releases GPU, keeps /workspace
#   ./scripts/stop_runpod.ps1 -Terminate   # terminate: delete the pod entirely

param(
    [switch]$Terminate
)

$ErrorActionPreference = "Stop"

# Load .env from project root
$root = Split-Path $PSScriptRoot -Parent
Get-Content "$root\.env" | Where-Object { $_ -match '^\s*[^#].+=' } | ForEach-Object {
    $name, $value = $_ -split '=', 2
    [Environment]::SetEnvironmentVariable($name.Trim(), $value.Trim(), "Process")
}

$apiKey = $env:RUNPOD_API_KEY
$podId  = $env:RUNPOD_POD_ID

if (-not $apiKey) { throw "Set RUNPOD_API_KEY in .env (your RunPod account API key)." }
if (-not $podId)  { throw "Set RUNPOD_POD_ID in .env (the pod id)." }

$headers = @{ Authorization = "Bearer $apiKey" }

if ($Terminate) {
    Write-Host "Terminating pod $podId (deletes everything not on a network volume)..."
    Invoke-RestMethod -Method Delete -Uri "https://rest.runpod.io/v1/pods/$podId" -Headers $headers
    Write-Host "Terminated. No further charges for this pod."
} else {
    Write-Host "Stopping pod $podId (releases the GPU, keeps /workspace)..."
    Invoke-RestMethod -Method Post -Uri "https://rest.runpod.io/v1/pods/$podId/stop" -Headers $headers
    Write-Host "Stopped. GPU billing ended; you may still pay for volume storage."
}

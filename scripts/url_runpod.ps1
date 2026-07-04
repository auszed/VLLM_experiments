# Print the pod's public vLLM URL to paste into .env as VLLM_BASE_URL.
# Builds it from RUNPOD_POD_ID in .env. Runs on your Windows PC.
#
#   ./scripts/url_runpod.ps1

$ErrorActionPreference = "Stop"

# Load .env from project root
$root = Split-Path $PSScriptRoot -Parent
Get-Content "$root\.env" | Where-Object { $_ -match '^\s*[^#].+=' } | ForEach-Object {
    $name, $value = $_ -split '=', 2
    [Environment]::SetEnvironmentVariable($name.Trim(), $value.Trim(), "Process")
}

$podId = $env:RUNPOD_POD_ID
if (-not $podId) { throw "Set RUNPOD_POD_ID in .env (the pod id from its page/URL)." }

$url = "https://$podId-8000.proxy.runpod.net/v1"
Write-Host "Paste this into .env:"
Write-Host "VLLM_BASE_URL=$url"

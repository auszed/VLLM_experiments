# Send a chat request to the vLLM server and print the answer.
# Runs on your Windows PC (PowerShell). Targets VLLM_BASE_URL from .env, so it
# hits the RunPod pod once you point VLLM_BASE_URL at the pod's public URL.
#
#   ./scripts/client_runpod.ps1
#   ./scripts/client_runpod.ps1 -Prompt "Write a Python function to reverse a list"
#   ./scripts/client_runpod.ps1 -Prompt "..." -MaxTokens 512

param(
    [string]$Prompt = "Write a Python function that returns the nth Fibonacci number.",
    [int]$MaxTokens = 256
)

$ErrorActionPreference = "Stop"

# Load .env from project root
$root = Split-Path $PSScriptRoot -Parent
Get-Content "$root\.env" | Where-Object { $_ -match '^\s*[^#].+=' } | ForEach-Object {
    $name, $value = $_ -split '=', 2
    [Environment]::SetEnvironmentVariable($name.Trim(), $value.Trim(), "Process")
}

$base  = $env:VLLM_BASE_URL
$key   = $env:VLLM_API_KEY
$model = $env:VLLM_MODEL

Write-Host "POST $base/chat/completions"
Write-Host "Model: $model"
Write-Host "Prompt: $Prompt`n"

$body = @{
    model    = $model
    messages = @(@{ role = "user"; content = $Prompt })
    max_tokens = $MaxTokens
} | ConvertTo-Json -Depth 5

$resp = Invoke-RestMethod -Method Post -Uri "$base/chat/completions" `
    -Headers @{ Authorization = "Bearer $key" } `
    -ContentType "application/json" `
    -Body $body

Write-Host "--- Answer ---"
Write-Host $resp.choices[0].message.content
Write-Host "`n--- Usage ---"
Write-Host "prompt: $($resp.usage.prompt_tokens)  completion: $($resp.usage.completion_tokens)  total: $($resp.usage.total_tokens)"

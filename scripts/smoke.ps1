# Run the endpoint smoke tests against the running vLLM server.
# Targets VLLM_BASE_URL from .env (local by default, RunPod when pointed there).

$ErrorActionPreference = "Stop"
$test = Join-Path (Split-Path $PSScriptRoot -Parent) "test"
Set-Location $test
uv run pytest -v

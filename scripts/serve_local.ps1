# Run vLLM locally with the tiny model to validate the endpoint contract.
# Uses the official vllm/vllm-openai image on the local GPU.
# First run downloads the image and the model into the hf-cache volume.

$ErrorActionPreference = "Stop"

# Load .env from project root
$root = Split-Path $PSScriptRoot -Parent
Get-Content "$root\.env" | Where-Object { $_ -match '^\s*[^#].+=' } | ForEach-Object {
    $name, $value = $_ -split '=', 2
    [Environment]::SetEnvironmentVariable($name.Trim(), $value.Trim(), "Process")
}

$model = $env:VLLM_MODEL_LOCAL
$key   = $env:VLLM_API_KEY

Write-Host "Starting vLLM with $model on the local GPU (dtype=half for Turing)..."

# --dtype half: GTX 1660 Ti (Turing) has no bfloat16
# --max-model-len 2048 + gpu-memory-utilization 0.70: only ~5 GB of the 6 GB is free
docker run --rm --name vllm-local --gpus all --ipc=host `
  -p 8000:8000 `
  -v hf-cache:/root/.cache/huggingface `
  -e VLLM_WSL2_ENABLE_PIN_MEMORY=1 `
  vllm/vllm-openai:latest `
  $model `
  --tensor-parallel-size 1 `
  --dtype half `
  --max-model-len 2048 `
  --gpu-memory-utilization 0.70 `
  --enforce-eager `
  --api-key $key

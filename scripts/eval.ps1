# Run the question dataset through the chat endpoint and record one MLflow trace per
# question, so you can read the model's answers and judge correctness.
#
#   ./scripts/eval.ps1                 # all questions in test/questions.jsonl
#   ./scripts/eval.ps1 -Num 5          # first 5 questions
#   ./scripts/eval.ps1 -NewExperiment  # isolated timestamped experiment

param(
    [int]$Num = 0,
    [string]$DatasetName = "vllm-questions",
    [int]$MaxTokens = 512,
    [string]$Experiment = "vllm-eval",
    [switch]$NewExperiment
)

# -NewExperiment isolates this pass in a fresh timestamped experiment.
if ($NewExperiment) {
    $Experiment = "vllm-eval-" + (Get-Date -Format "yyyyMMdd-HHmmss")
}

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent

# Load .env into the process (VLLM_BASE_URL, VLLM_API_KEY, MLFLOW_TRACKING_URI)
Get-Content "$root\.env" | Where-Object { $_ -match '^\s*[^#].+=' } | ForEach-Object {
    $name, $value = $_ -split '=', 2
    [Environment]::SetEnvironmentVariable($name.Trim(), $value.Trim(), "Process")
}

Push-Location (Join-Path $root "test")
uv run python eval_dataset.py --num $Num --dataset-name $DatasetName `
    --max-tokens $MaxTokens --experiment $Experiment
Pop-Location

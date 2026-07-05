# Endpoint smoke tests

Fast checks that the vLLM OpenAI-compatible endpoint is up and honoring the
contract clients depend on: health, model listing, and chat completions
(non-streaming and streaming).

## Prerequisites

- A vLLM server running (local via `scripts/serve_local.ps1`, or RunPod).
- `uv` installed. Dependencies (`openai`, `pytest`) are already in `pyproject.toml`.

## Run

From the project root:

```powershell
./scripts/smoke.ps1
```

Or directly from this folder:

```powershell
uv run pytest -v
```

Run a single test:

```powershell
uv run pytest -v -k test_chat_streaming
```

## What it targets

Configuration comes from the project-root `.env` (loaded automatically by
`conftest.py`):

| Variable | Meaning |
|----------|---------|
| `VLLM_BASE_URL` | Endpoint to test, e.g. `http://localhost:8000/v1` |
| `VLLM_API_KEY`  | Bearer token sent with every request |

The served model id is read from `GET /v1/models` at runtime, not hardcoded.
So the **same suite validates both** the local tiny model and the RunPod 70B:
point `VLLM_BASE_URL` at the RunPod URL (`.../v1`) and re-run.

## The tests (`test_endpoints.py`)

| Test | Asserts |
|------|---------|
| `test_health` | `GET /health` returns 200 |
| `test_models_lists_a_model` | `/v1/models` reports a model id |
| `test_chat_non_streaming` | a completion returns non-empty content |
| `test_chat_streaming` | `stream=True` yields content across multiple chunks |

## Files

- `conftest.py` — loads `.env`, builds the `OpenAI` client, exposes fixtures
  (`base_url`, `root_url`, `api_key`, `client`, `served_model`).
- `test_endpoints.py` — the four smoke tests.
- `log_to_mlflow.py` — logs the load test's throughput metrics to MLflow (one run). With
  `--trace-calls` (default via `scripts/loadtest.ps1`), also logs **one trace per request**
  (Traces tab) whose execution time is that request's real end-to-end latency, so you can
  inspect per-request performance behind the p50/p95 aggregates. Cap with `--max-traces N`.
- `questions.jsonl` — editable question bank, one `{"question": "..."}` per line.
- `eval_dataset.py` — registers `questions.jsonl` as a managed MLflow evaluation dataset
  (Datasets tab) and runs `mlflow.genai.evaluate` against the chat endpoint, producing
  **one trace per question** (Traces tab) in an Eval run under the `vllm-eval` experiment.
  This is how you check answer quality (distinct questions, real answers), separate from
  the throughput test. Run with `make eval` / `make eval-new`, or
  `uv run python eval_dataset.py [--num N]`.
- `trace_answers.py` — standalone chat probe writing `../loadtest/traces.jsonl` (no
  MLflow), for a quick local eyeball: `uv run python trace_answers.py [--prompts f]`.

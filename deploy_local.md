# Local deploy — run the whole stack in containers and test it

Everything (vLLM, MLflow, frontend) runs in containers via one compose file,
using the tiny model to prove the pipeline. Everything is driven by `make`
targets, run from the project root (`D:\Code_Code\AI_DEEPLEARNING_DATASCIENCE\012_VLLM`).

## Prerequisites

- Docker Desktop running, with your NVIDIA GPU available.
- `make` installed (Git Bash / WSL / `choco install make`).
- `uv` and Go installed (for the smoke test and load tester run from the host).

## 1. Config (once)

```powershell
Copy-Item .env.example .env
```

Open `.env` and set `VLLM_API_KEY` to any string you like (default is `change-me`).
Leave the rest as-is for local.

## 2. Start the whole stack (one command)

```powershell
make up
```

This starts three containers:

| Service | URL | Notes |
|---------|-----|-------|
| `vllm` | http://localhost:8000 | tiny model on the GPU |
| `mlflow` | http://localhost:5000 | tracking UI |
| `frontend` | http://localhost:3000/chat | chat UI (waits for vLLM to be healthy) |

- First run downloads the vLLM image (~9 GB) + tiny model and builds the frontend
  image — be patient.
- Watch progress: `make logs` (follows the vLLM container).
- The frontend only starts once vLLM reports healthy (that can take ~1-2 min).
- Under the hood every target wraps
  `docker compose --env-file .env -f docker-compose.local.yml`. Run `make help` for the full list.

## 3. Smoke test the endpoint (from the host)

```powershell
make smoke
```

Expect `4 passed` (health, model listed, chat, streaming chat).

## 4. Load test + log to MLflow

```powershell
# shared experiment (all runs land in vllm-loadtest, easy to compare)
make loadtest

# OR a fresh, isolated run in its own timestamped experiment
make loadtest-new

# OR fully in a container (writes loadtest/results.json, no MLflow, no host Go)
make loadtest-docker
```

Then open http://localhost:5000:
- `make loadtest` -> experiment `vllm-loadtest`.
- `make loadtest-new` -> experiment `vllm-loadtest-<yyyyMMdd-HHmmss>` (one per run).

Each run has metric-vs-concurrency charts and the attached `results.json`. To customize the
ramp, call the script directly, e.g.
`./scripts/loadtest.ps1 -Concurrency "1,8,32,64" -Requests 60 -NewExperiment`.

## 5. Chat UI

Already running at http://localhost:3000/chat — send a prompt, watch the tokens
stream and the TTFT / tokens-per-sec readout.

## Stop everything

```powershell
make down
```

Other handy targets: `make health` (are the 3 services up?), `make urls` (print service URLs),
`make gpu` (GPU memory), `make clean` (down + remove built images and volumes).

## Notes for this machine (GTX 1660 Ti, 6 GB) — important

- The GPU is shared with the Windows desktop. vLLM needs a couple of GB free.
  If apps like browsers are using the GPU, only ~1.8 GB may be free, and vLLM
  will fail with "No available memory for the cache blocks". The compose config
  is tuned small for this (`--gpu-memory-utilization 0.28`, `--enforce-eager`).
  Context length comes from `MAX_MODEL_LEN` in `.env` (`--max-model-len ${MAX_MODEL_LEN}`,
  currently 8192); the tiny model's KV cache for 8192 tokens still fits the ~1.4 GB budget.
  If it still fails, **close GPU-heavy apps** (browsers, NVIDIA Share) and check free
  memory with `nvidia-smi`.
- `--dtype half` because Turing GPUs have no bfloat16; `--enforce-eager` skips
  CUDA-graph capture (which alone wanted ~5.5 GB).
- Turing can't use FlashAttention, so batched requests are slow here. Expected —
  the local run only proves the pipeline. Real capacity numbers come from RunPod
  (see `deploy_runpod.md`).

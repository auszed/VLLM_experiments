# vLLM on RunPod — experiment

Serve a large open model with [vLLM](https://vllm.ai/), test it locally, deploy
it to RunPod GPUs, and measure how many concurrent requests it can handle —
tracked in MLflow.

- **Model:** `Qwen/Qwen3-Coder-30B-A3B-Instruct` on RunPod (2x48GB), a tiny
  `SmolLM2-135M` locally to prove the plumbing first.
- **Docs:** [`PLAN.md`](PLAN.md) (the spec) · [`planning.md`](planning.md)
  (build steps) · [`deploy_runpod.md`](deploy_runpod.md) (cloud runbook).

## Architecture

One server, several clients. **vLLM** exposes an OpenAI-compatible HTTP API; every
client reads `VLLM_BASE_URL` + `VLLM_API_KEY` from `.env`, so the same tools work
whether vLLM runs locally or on RunPod — you only change one URL.

```
                    Your PC  (Windows - PowerShell + make)
  +------------------------------------------------------------------+
  |  Chat UI (Next.js :3000) --+                                      |
  |  Go load tester            +--> VLLM_BASE_URL + VLLM_API_KEY -----+---> vLLM  (OpenAI API :8000)
  |  pytest smoke tests        |        (both from .env)              |       /v1/chat/completions
  |  client_runpod.ps1       --+                                      |       /v1/completions
  |                                                                   |       /v1/models  /health
  |  results.json --> log_to_mlflow.py --> MLflow (:5000, tracking)   |
  +------------------------------------------------------------------+
                                   |
              stop / kill_runpod   |  RUNPOD_API_KEY
                                   v
                          RunPod REST API   (create/stop/terminate the pod)

  vLLM runs in ONE of two places (identical API, switch via VLLM_BASE_URL):
   - Local : SmolLM2-135M on your GPU       http://localhost:8000/v1
   - RunPod: Qwen3-Coder-30B on 2x48GB      https://<pod-id>-8000.proxy.runpod.net/v1
```

**Components**

- **vLLM** — the model server (PagedAttention, continuous batching). Local: tiny
  model via `scripts/serve_local.ps1` or docker-compose. Cloud: `serve_runpod.sh`
  on the pod. Auth = `VLLM_API_KEY` on every request.
- **Frontend** (`frontend/`) — Next.js chat UI at `/chat`, calls the vLLM API.
- **Load tester** (`loadtest/main.go`) — ramps concurrency, streams completions
  with `ignore_eos` for fixed work per request, reports throughput + TTFT/e2e
  percentiles, writes `results.json`.
- **MLflow** (`mlflow/`, `:5000`) — tracking server. `test/log_to_mlflow.py` turns
  each `results.json` into one comparable run. Always local; RunPod never sees it.
- **Orchestration** — `Makefile` + `scripts/*.ps1` (your PC) and
  `docker-compose.local.yml` (full local stack in containers).

**Load-test flow:** `loadtest.ps1` builds + runs the Go tester against
`VLLM_BASE_URL` -> `results.json` -> `log_to_mlflow.py` -> compare runs at
http://localhost:5000. Going to RunPod changes only the URL (step in
[`deploy_runpod.md`](deploy_runpod.md)).

## Quick start (local)

```powershell
# 0. Config
Copy-Item .env.example .env      # then set VLLM_API_KEY

# 1. Serve the tiny model on the local GPU (:8000)
./scripts/serve_local.ps1

# 2. Check the endpoint is healthy and answering
./scripts/smoke.ps1

# 3. Start MLflow tracking (:5000)
docker compose --env-file .env -f docker-compose.local.yml up -d mlflow

# 4. Load test + log the run to MLflow
./scripts/loadtest.ps1

# 5. (optional) Manual chat UI (:3000) -> open /chat
cd frontend; npm install; npm run dev
```

Then browse runs at http://localhost:5000 and chat at http://localhost:3000/chat.

## Why vLLM is fast: PagedAttention

Each request keeps a growing KV cache (the attention keys/values for every token
so far). Naively that needs one big contiguous block per request, sized to the
worst case — most of it sits reserved and unused, so few requests fit on the GPU.

PagedAttention borrows the OS idea of virtual memory: it splits the KV cache into
fixed-size **blocks** (pages) and hands them out on demand, like memory pages.
Requests only use the blocks they actually need, blocks from finished requests are
reclaimed immediately, and identical prefixes can **share** the same blocks. The
result is far less wasted memory, so many more requests run concurrently — which
is exactly the throughput this experiment measures.

Two flags control it (already set in `scripts/serve_runpod.sh`):

- `--block-size` — tokens per KV block (page). Default `16`; rarely worth changing.
- `--enable-prefix-caching` — reuse cached blocks across requests that share a
  prefix (e.g. the same system prompt or code context), skipping recompute.

Related knob: `--max-num-seqs` caps how many sequences vLLM batches at once
(default `1024`). It's an **upper bound, not guaranteed concurrency** — the KV
cache is the real limit, so a huge value only helps if the memory backs it, and
set too high it causes preemption and worse latency. It's an opt-in
`MAX_NUM_SEQS` env knob (empty = vLLM default) for load-test experiments.

## Going to RunPod

Everything reads `VLLM_BASE_URL` from `.env`. Deploy Qwen3-Coder on a pod
(see [`runpod/README.md`](runpod/README.md)), point `VLLM_BASE_URL` at the pod,
and the same tests, frontend, and load tester work unchanged.

## Requirements

- Docker Desktop, an NVIDIA GPU (local), `uv`, Node, Go.
- A RunPod account for the cloud step. Qwen3-Coder is Apache-2.0, so no Hugging
  Face token is required.

# vLLM on RunPod — experiment

Serve a large open model with [vLLM](https://vllm.ai/), test it locally, deploy
it to RunPod GPUs, and measure how many concurrent requests it can handle —
tracked in MLflow.

- **Model:** `meta-llama/Llama-3.3-70B-Instruct` on RunPod (2x80GB), a tiny
  `Qwen2.5-0.5B` locally to prove the plumbing first.
- **Docs:** [`PLAN.md`](PLAN.md) (the spec) · [`planning.md`](planning.md)
  (build steps) · [`STRUCTURE.md`](STRUCTURE.md) (what every file does).

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

## Going to RunPod

Everything reads `VLLM_BASE_URL` from `.env`. Deploy the 70B on a pod
(see [`runpod/README.md`](runpod/README.md)), point `VLLM_BASE_URL` at the pod,
and the same tests, frontend, and load tester work unchanged.

## Requirements

- Docker Desktop, an NVIDIA GPU (local), `uv`, Node, Go.
- A RunPod account + a Hugging Face token (Llama-3.3 is gated) for the cloud step.

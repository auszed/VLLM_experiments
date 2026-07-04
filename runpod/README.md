# Deploying the 70B on RunPod

Runbook for serving `meta-llama/Llama-3.3-70B-Instruct` with vLLM on a RunPod
pod, then calling it from your PC. MLflow stays on your PC — the pod only runs
vLLM.

## Before you start

- A RunPod account with credit.
- A Hugging Face token with access to Llama-3.3-70B (accept the license on the
  [model page](https://huggingface.co/meta-llama/Llama-3.3-70B-Instruct) first).
- Pick an `VLLM_API_KEY` (any string) that clients will send.

## 1. Create the pod

- **GPU:** 2 x 80GB (A100-80G or H100-80G). The 70B needs ~140GB at fp16,
  which is why it spans two cards.
- **Image:** `vllm/vllm-openai:latest`
- **Expose HTTP port:** `8000`
- **Container disk / volume:** enough for the model weights (~140GB) plus cache.

## 2. Set environment variables on the pod

| Variable | Value |
|----------|-------|
| `VLLM_MODEL` | `meta-llama/Llama-3.3-70B-Instruct` |
| `TENSOR_PARALLEL_SIZE` | `2` |
| `GPU_MEMORY_UTILIZATION` | `0.90` |
| `MAX_MODEL_LEN` | `8192` |
| `VLLM_API_KEY` | your chosen key |
| `HF_TOKEN` | your Hugging Face token (for the gated weights) |
| `PORT` | `8000` |

## 3. Start vLLM

The `vllm/vllm-openai` image's entrypoint is already `vllm serve`, so set the
pod's **container start command / arguments** to the model plus flags:

```
meta-llama/Llama-3.3-70B-Instruct --tensor-parallel-size 2 --gpu-memory-utilization 0.90 --max-model-len 8192 --api-key YOUR_KEY --port 8000
```

Or, from a pod terminal, run the helper script (same flags, reads env vars):

```bash
bash scripts/serve_runpod.sh
```

First start downloads ~140GB of weights — expect several minutes.

## 4. Get the public URL

RunPod exposes port 8000 at `https://<pod-id>-8000.proxy.runpod.net`. On your
PC, set in `.env`:

```
VLLM_BASE_URL=https://<pod-id>-8000.proxy.runpod.net/v1
```

## 5. Validate from your PC

```powershell
./scripts/smoke.ps1        # same tests, now against the pod
```

Point the frontend at the pod too by editing `frontend/.env.local`.

## 6. Capacity test (Phase 8)

Run the load test against the pod and log to your local MLflow:

```powershell
# 2-GPU run
./scripts/loadtest.ps1 -Concurrency "1,4,16,64,128,256" -Requests 256 -GpuCount 2 -GpuType H100-80G

# 1-GPU run (for comparison; use a 1-GPU pod or tensor-parallel-size 1)
./scripts/loadtest.ps1 -Concurrency "1,4,16,64,128,256" -Requests 256 -GpuCount 1 -GpuType H100-80G
```

Then compare the two runs in the MLflow UI (http://localhost:5000).

## Findings (fill in after running)

| Config | Peak req/s | Peak tok/s | Saturation concurrency | Notes |
|--------|-----------|-----------|------------------------|-------|
| 2 GPU  |           |           |                        |       |
| 1 GPU  |           |           |                        |       |

## Remember to stop the pod

RunPod bills while the pod runs. Stop or terminate it when done — your MLflow
results are safe on your PC.

# Deploying Qwen3-Coder on RunPod

Runbook for serving `Qwen/Qwen3-Coder-30B-A3B-Instruct` with vLLM on a RunPod
pod, then calling it from your PC. MLflow stays on your PC — the pod only runs
vLLM.

## Before you start

- A RunPod account with credit.
- Pick a `VLLM_API_KEY` (any string) that clients will send.

Qwen3-Coder is Apache-2.0 and not gated, so no Hugging Face license or token is
required (a token only helps avoid download rate limits).

## Model options

| Model | Precision | Weights | GPUs | `TENSOR_PARALLEL_SIZE` |
|-------|-----------|---------|------|------------------------|
| `Qwen/Qwen3-Coder-30B-A3B-Instruct` | bf16 | ~61 GB | **2 x 48GB** | `2` (default) |
| `Qwen/Qwen3-Coder-30B-A3B-Instruct` | bf16 | ~61 GB | 1 x 80GB | `1` |
| `Qwen/Qwen3-Coder-30B-A3B-Instruct-FP8` | FP8 | ~32 GB | 1 x 48GB | `1` |
| `Qwen/Qwen3-Coder-480B-A35B-Instruct-FP8` | FP8 | ~120 GB+ | 4-8 x 80GB | `4`-`8` |

All are the same MoE family (~3.3B active). The runbook below uses the default
(first row); to switch, change `VLLM_MODEL` + `TENSOR_PARALLEL_SIZE` only.

## 1. Create the pod

- **GPU:** 2 x 48GB (A6000, L40S, or A40). The 30B MoE is ~61GB at bf16, which
  splits cleanly across two 48GB cards.
- **Image:** `vllm/vllm-openai:latest`
- **Expose HTTP port:** `8000`
- **Container disk / volume:** enough for the model weights (~70GB) plus cache.

## 2. Set environment variables on the pod

| Variable | Value |
|----------|-------|
| `VLLM_MODEL` | `Qwen/Qwen3-Coder-30B-A3B-Instruct` |
| `TENSOR_PARALLEL_SIZE` | `2` |
| `GPU_MEMORY_UTILIZATION` | `0.90` |
| `MAX_MODEL_LEN` | `32768` (native supports up to 262144) |
| `VLLM_API_KEY` | your chosen key |
| `PORT` | `8000` |
| `MAX_NUM_SEQS` | optional — cap on batched sequences (empty = vLLM default 1024) |
| `HF_TOKEN` | optional — only to dodge download rate limits |

## 3. Start vLLM

The `vllm/vllm-openai` image's entrypoint is already `vllm serve`, so set the
pod's **container start command / arguments** to the model plus flags:

```
Qwen/Qwen3-Coder-30B-A3B-Instruct --host 0.0.0.0 --tensor-parallel-size 2 --gpu-memory-utilization 0.90 --max-model-len 32768 --block-size 16 --enable-prefix-caching --api-key YOUR_KEY --port 8000
```

`--host 0.0.0.0` is required so RunPod's proxy can reach the server.
`--block-size` / `--enable-prefix-caching` tune PagedAttention (see the main
[`README.md`](../README.md)). Optionally append `--max-num-seqs <N>` to raise the
batch cap for load-test experiments — an upper bound, still limited by KV cache.

Or, from a pod terminal, run the helper script (same flags, reads env vars):

```bash
bash scripts/serve_runpod.sh
```

First start downloads ~61GB of weights — expect a few minutes.

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
./scripts/loadtest.ps1 -Concurrency "1,4,16,64,128,256" -Requests 256 -GpuCount 2 -GpuType L40S-48G

# 1-GPU run (for comparison; use a 1-GPU pod or tensor-parallel-size 1)
./scripts/loadtest.ps1 -Concurrency "1,4,16,64,128,256" -Requests 256 -GpuCount 1 -GpuType L40S-48G
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

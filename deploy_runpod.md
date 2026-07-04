# RunPod deploy — serve the 70B and test it

Serve `meta-llama/Llama-3.3-70B-Instruct` on a RunPod pod, then drive it from
your PC. MLflow stays local; the pod only runs vLLM.

Two places you run commands:
- **On the pod** (Linux terminal, in the RunPod web console).
- **On your PC** (PowerShell, from the project root).

## Prerequisites

- RunPod account with credit.
- Hugging Face token with Llama-3.3 access — accept the license first at
  https://huggingface.co/meta-llama/Llama-3.3-70B-Instruct
- The local MLflow server running on your PC (from `local_deploy.md` step 3),
  so you can log capacity results.

## 1. Create the pod (RunPod web console)

- **GPU:** 2 x 80GB (A100-80G or H100-80G).
- **Image:** `vllm/vllm-openai:latest`
- **Expose HTTP port:** `8000`
- **Disk:** room for ~140 GB of weights + cache.

## 2. Set env vars on the pod

| Variable | Value |
|----------|-------|
| `VLLM_MODEL` | `meta-llama/Llama-3.3-70B-Instruct` |
| `TENSOR_PARALLEL_SIZE` | `2` |
| `GPU_MEMORY_UTILIZATION` | `0.90` |
| `MAX_MODEL_LEN` | `8192` |
| `VLLM_API_KEY` | your chosen key (same one you'll put in your PC `.env`) |
| `HF_TOKEN` | your Hugging Face token |
| `PORT` | `8000` |

## 3. Start vLLM on the pod

The `vllm/vllm-openai` entrypoint is already `vllm serve`, so set the pod's
**container start command / arguments** to:

```
meta-llama/Llama-3.3-70B-Instruct --tensor-parallel-size 2 --gpu-memory-utilization 0.90 --max-model-len 8192 --api-key YOUR_KEY --port 8000
```

Or, from a pod terminal, run the helper (reads the env vars above):

```bash
bash scripts/serve_runpod.sh
```

First start downloads ~140 GB of weights — expect several minutes. Wait until the
log shows the server is ready.

## 4. Point your PC at the pod

RunPod gives a public URL like `https://<pod-id>-8000.proxy.runpod.net`.
On your PC, edit `.env`:

```
VLLM_BASE_URL=https://<pod-id>-8000.proxy.runpod.net/v1
VLLM_API_KEY=YOUR_KEY        # must match the pod
```

## 5. Validate from your PC (PowerShell)

```powershell
./scripts/smoke.ps1
```

Same 4 tests, now hitting the pod. To also use the chat UI against the pod, set
the same `VLLM_BASE_URL` in `frontend/.env.local` and `npm run dev`.

## 6. Capacity test (the real numbers)

```powershell
# 2-GPU run
./scripts/loadtest.ps1 -Concurrency "1,4,16,64,128,256" -Requests 256 -GpuCount 2 -GpuType H100-80G
```

For the 1-GPU comparison, start a second pod with 1 GPU (or
`--tensor-parallel-size 1`), repoint `VLLM_BASE_URL`, then:

```powershell
./scripts/loadtest.ps1 -Concurrency "1,4,16,64,128,256" -Requests 256 -GpuCount 1 -GpuType H100-80G
```

Compare both runs in the MLflow UI (http://localhost:5000): peak req/s, tokens/s,
TTFT, and where latency crosses the SLO.

## 7. Stop the pod

RunPod bills while the pod runs. **Stop or terminate it when done.** Your MLflow
results are safe on your PC.

---

More detail and a findings table: `runpod/README.md`.

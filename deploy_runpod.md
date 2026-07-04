# RunPod deploy — serve Qwen3-Coder and load-test it

Serve **`Qwen/Qwen3-Coder-30B-A3B-Instruct`** on a RunPod pod, then drive and
load-test it from your PC. MLflow stays local; the pod only runs vLLM.

Qwen3-Coder is Apache-2.0 and **not gated** — no Hugging Face license or token
needed (a token only helps avoid download rate limits).

Two places you run commands:
- **On the pod** — Linux terminal in the RunPod web console (bash script).
- **On your PC** — PowerShell, from the project root (`.ps1` scripts + `make`).

## Command cheat sheet (all from your PC)

| Command | What it does |
|---------|--------------|
| `make serve-runpod` | Prints the exact command to start vLLM on the pod |
| `make url-runpod` | Prints the pod URL to paste into `.env` as `VLLM_BASE_URL` |
| `make client-runpod` | Sends one chat request to the pod, prints the answer |
| `make loadtest-runpod` | Go load test against the pod, logs to MLflow |
| `make stop-runpod` | Stops the pod (releases GPU, keeps `/workspace`) |
| `make kill-runpod` | Terminates the pod (deletes it, zero further cost) |

Every command reads `VLLM_BASE_URL` / `VLLM_API_KEY` from `.env`, so pointing at
the pod is a one-line change (step 4).

## How connecting works (there is no cluster login)

RunPod is not a persistent cluster you `login` to like AWS. There are three
separate connections, and the simplest path never opens a shell on the pod:

1. **Start the server** — preferred: paste the vLLM args into the pod's
   **Container Start Command** when you create it (step 3), so vLLM auto-starts on
   boot. No pod shell needed. Only if you want to start/debug by hand do you open a
   terminal on the pod: the **Connect -> Web Terminal** button (browser), or SSH
   (`ssh <pod-id>@ssh.runpod.io -i ~/.ssh/id_ed25519`, shown in the Connect tab).
2. **Use it from your PC** — `make client-runpod` / `make loadtest-runpod` are just
   HTTPS calls to the pod's public URL. **No login step.** Auth is the
   `VLLM_API_KEY` header, which the scripts send automatically.
3. **Stop it** — `make stop-runpod` / `make kill-runpod` authenticate with your
   RunPod **account API key** (`RUNPOD_API_KEY`), passed as a header. That key is
   the closest thing to `aws login`, but there is no interactive login.

**The URL rule:** the pod is reached at
`https://<pod-id>-8000.proxy.runpod.net/v1` — always **https** (port 443), the
vLLM port `8000` lives in the **hostname** (`<pod-id>-8000`), not the path, and you
keep the `/v1` suffix. `http://localhost:8000/v1` only works when vLLM runs on your
own PC.

## Prerequisites

- RunPod account with credit; your RunPod **account API key** (Settings -> API
  Keys) for `stop`/`kill`.
- Pick a `VLLM_API_KEY` (any string) that clients send to vLLM.
- Go installed on your PC (the load tester builds from source).
- Local MLflow running (from `deploy_local.md`) to log capacity results.

## Model possibilities

Default is the **first row** (30B-A3B bf16 on 2 x 48GB). Same MoE family
(~3.3B active), so throughput is similar; VRAM and cost differ.

| Model | Precision | Weights | GPUs | `TENSOR_PARALLEL_SIZE` | Notes |
|-------|-----------|---------|------|------------------------|-------|
| `Qwen/Qwen3-Coder-30B-A3B-Instruct` | bf16 | ~61 GB | **2 x 48GB** (A6000 / L40S / A40) | `2` | **Default.** Full precision across two 48GB cards. |
| `Qwen/Qwen3-Coder-30B-A3B-Instruct` | bf16 | ~61 GB | 1 x 80GB (A100 / H100) | `1` | Same quality, single card. |
| `Qwen/Qwen3-Coder-30B-A3B-Instruct-FP8` | FP8 | ~32 GB | 1 x 48GB | `1` | Cheapest. Needs Ada/Hopper (L40S/H100). |
| `Qwen/Qwen3-Coder-480B-A35B-Instruct-FP8` | FP8 | ~120 GB+ | 4-8 x 80GB | `4`-`8` | Flagship coding quality, much higher cost. |

To switch, change `VLLM_MODEL` + `TENSOR_PARALLEL_SIZE` (steps 2-3) — nothing
else changes.

## 1. Create the pod (RunPod web console)

- **GPU:** 2 x 48GB (A6000, L40S, or A40).
- **Image:** `vllm/vllm-openai:latest`
- **Expose HTTP port:** `8000`
- **Disk:** room for ~70 GB of weights + cache.

Copy the **pod id** — you'll need it for `stop`/`kill`.

## 2. Set env vars on the pod

| Variable | Value |
|----------|-------|
| `VLLM_MODEL` | `Qwen/Qwen3-Coder-30B-A3B-Instruct` |
| `TENSOR_PARALLEL_SIZE` | `2` |
| `GPU_MEMORY_UTILIZATION` | `0.90` |
| `MAX_MODEL_LEN` | `32768` (native supports up to 262144) |
| `VLLM_API_KEY` | your chosen key (same one in your PC `.env`) |
| `PORT` | `8000` |
| `MAX_NUM_SEQS` | optional — cap on batched sequences (empty = vLLM default 1024) |
| `HF_TOKEN` | optional — only to dodge download rate limits |

## 3. Start vLLM on the pod

`make serve-runpod` on your PC prints the command. Either paste these args into
RunPod's **container start command** (this is the no-shell path — vLLM auto-starts
on boot):

```
Qwen/Qwen3-Coder-30B-A3B-Instruct --host 0.0.0.0 --tensor-parallel-size 2 --gpu-memory-utilization 0.90 --max-model-len 32768 --block-size 16 --enable-prefix-caching --api-key YOUR_KEY --port 8000
```

`--host 0.0.0.0` is required so RunPod's proxy can reach the server.
`--block-size` / `--enable-prefix-caching` tune PagedAttention (see the main
[`README.md`](README.md)). Optionally append `--max-num-seqs <N>` (e.g. `2000`) to
raise the batch cap for load-test experiments — it's an upper bound, still limited
by KV-cache memory.

or, from a pod terminal, run the helper (reads the env vars above):

```bash
bash scripts/serve_runpod.sh
```

First start downloads ~61 GB of weights — a few minutes. Wait for
`Application startup complete`.

## 4. Point your PC at the pod

Put the pod id in `.env` as `RUNPOD_POD_ID`, then run `make url-runpod` to get the
exact `VLLM_BASE_URL` line (or build it by hand per the URL rule above). Edit
`.env`:

```
VLLM_BASE_URL=https://<pod-id>-8000.proxy.runpod.net/v1   # from `make url-runpod`
VLLM_API_KEY=YOUR_KEY        # must match the pod
RUNPOD_API_KEY=...           # your RunPod account key (for stop/kill)
RUNPOD_POD_ID=...            # the pod id from step 1
```

## 5. Smoke test from your PC

```powershell
make client-runpod                 # one chat request, prints the answer
# or the full pytest suite:
make smoke
```

To use the chat UI against the pod, set the same `VLLM_BASE_URL` in
`frontend/.env.local` and `npm run dev`.

## 6. Load test (the real numbers) — Go tester

The load tester is a Go program (`loadtest/main.go`). It ramps concurrency,
streams completions with `ignore_eos` so every request does exactly `max_tokens`
of work, and reports per-step throughput and latency percentiles (TTFT / e2e
p50/p95/p99). It finds the **saturation concurrency** (where p95 crosses the SLO)
and the **max sustained req/s**, writes `results.json`, and logs the run to your
local MLflow. `make loadtest-runpod` builds and runs it in one shot:

```powershell
# 2-GPU pod run (default ramp 1..256, 256 req/step)
make loadtest-runpod
```

Under the hood that is:

```powershell
./scripts/loadtest.ps1 -Concurrency "1,4,16,64,128,256" -Requests 256 -GpuType L40S-48G -GpuCount 2
```

Tune it by calling the script directly, e.g. longer generations or a different
GPU label:

```powershell
./scripts/loadtest.ps1 -Concurrency "1,8,32,128,256" -Requests 256 -MaxTokens 256 -SloMs 15000 -GpuType A6000-48G -GpuCount 2
```

For a 1-GPU comparison, start a second pod with 1 GPU (or
`--tensor-parallel-size 1`), repoint `VLLM_BASE_URL`, then:

```powershell
./scripts/loadtest.ps1 -Concurrency "1,4,16,64,128,256" -Requests 256 -GpuType L40S-48G -GpuCount 1
```

Compare both runs in the MLflow UI (http://localhost:5000): peak req/s, tokens/s,
TTFT, and where latency crosses the SLO.

## 7. Bring the pod down (stop billing)

Do this the moment you're done — RunPod bills while the pod runs.

```powershell
make stop-runpod    # release the GPU, keep the weights on /workspace (fast restart, small storage cost)
make kill-runpod    # terminate the pod entirely (zero further cost, re-downloads weights next time)
```

Both read `RUNPOD_API_KEY` + `RUNPOD_POD_ID` from `.env`. For short test
sessions, `make kill-runpod` when fully done is the cheapest. Your MLflow results
are safe on your PC either way.

---

More detail and a findings table: `runpod/README.md`.

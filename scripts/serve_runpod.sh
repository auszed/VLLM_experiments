#!/usr/bin/env bash
# Serve the real model with vLLM. Runs ON the RunPod pod (Linux terminal), not
# on your Windows PC. Either paste the flags into RunPod's container start
# command, or run this script from a pod terminal. Reads env vars set on the pod.
set -euo pipefail

MODEL="${VLLM_MODEL:?set VLLM_MODEL, e.g. Qwen/Qwen3-Coder-30B-A3B-Instruct}"

echo "Serving ${MODEL} with tensor-parallel=${TENSOR_PARALLEL_SIZE:-2}, max-model-len=${MAX_MODEL_LEN:-32768}"

# Optional: only cap batched sequences when MAX_NUM_SEQS is set (empty = vLLM default).
EXTRA=()
if [ -n "${MAX_NUM_SEQS:-}" ]; then
  EXTRA+=(--max-num-seqs "${MAX_NUM_SEQS}")
  echo "Capping max-num-seqs at ${MAX_NUM_SEQS} (upper bound; real limit is KV cache)"
fi

vllm serve "${MODEL}" \
  --host 0.0.0.0 \
  --tensor-parallel-size "${TENSOR_PARALLEL_SIZE:-2}" \
  --gpu-memory-utilization "${GPU_MEMORY_UTILIZATION:-0.90}" \
  --max-model-len "${MAX_MODEL_LEN:-32768}" \
  --block-size "${BLOCK_SIZE:-16}" \
  --enable-prefix-caching \
  "${EXTRA[@]+"${EXTRA[@]}"}" \
  --api-key "${VLLM_API_KEY:?set VLLM_API_KEY (must match your PC .env)}" \
  --port "${PORT:-8000}"

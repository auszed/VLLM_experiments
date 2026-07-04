#!/usr/bin/env bash
# Serve the real model with vLLM inside a RunPod pod (2 GPUs, tensor-parallel).
# Run this in the pod terminal, or paste the flags into RunPod's container
# start command. Reads env vars set on the pod.
set -euo pipefail

vllm serve "${VLLM_MODEL:?set VLLM_MODEL, e.g. meta-llama/Llama-3.3-70B-Instruct}" \
  --tensor-parallel-size "${TENSOR_PARALLEL_SIZE:-2}" \
  --gpu-memory-utilization "${GPU_MEMORY_UTILIZATION:-0.90}" \
  --max-model-len "${MAX_MODEL_LEN:-8192}" \
  --api-key "${VLLM_API_KEY:?set VLLM_API_KEY}" \
  --port "${PORT:-8000}"

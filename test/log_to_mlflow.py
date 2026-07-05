"""Log a load-test results.json as one MLflow run.

Per-step metrics are logged with step=concurrency, so the MLflow UI plots
throughput / latency against concurrency. Run:

    uv run python log_to_mlflow.py ../loadtest/results.json --gpu-type GTX-1660Ti --gpu-count 1
"""

import argparse
import json
import os
import sys
import time
from pathlib import Path

import mlflow
from mlflow.client import MlflowClient

# MLflow prints an emoji in the run URL; Windows console defaults to cp1252.
sys.stdout.reconfigure(encoding="utf-8", errors="replace")


def load_env():
    env_path = Path(__file__).resolve().parent.parent / ".env"
    if not env_path.exists():
        return
    for line in env_path.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            key, value = line.split("=", 1)
            os.environ.setdefault(key.strip(), value.strip())


STEP_METRICS = [
    "requests_per_sec",
    "tokens_per_sec",
    "success_rate",
    "ttft_p50_ms",
    "ttft_p95_ms",
    "ttft_p99_ms",
    "e2e_p50_ms",
    "e2e_p95_ms",
    "e2e_p99_ms",
]


def main():
    load_env()
    parser = argparse.ArgumentParser()
    parser.add_argument("results", nargs="?", default="../loadtest/results.json")
    parser.add_argument("--experiment", default=os.environ.get("MLFLOW_EXPERIMENT", "vllm-loadtest"))
    parser.add_argument("--run-name", default=None)
    parser.add_argument("--gpu-type", default="unknown")
    parser.add_argument("--gpu-count", type=int, default=1)
    parser.add_argument("--trace-calls", action="store_true",
                        help="log every captured call (results.json 'calls') as an MLflow trace")
    parser.add_argument("--max-traces", type=int, default=0,
                        help="cap traces logged (0 = all captured calls)")
    args = parser.parse_args()

    report = json.loads(Path(args.results).read_text())
    endpoint = "local" if "localhost" in report["url"] else "runpod"

    mlflow.set_tracking_uri(os.environ.get("MLFLOW_TRACKING_URI", "http://localhost:5000"))
    mlflow.set_experiment(args.experiment)

    run_name = args.run_name or f"{endpoint}-{args.gpu_count}gpu-{report['model'].split('/')[-1]}"
    with mlflow.start_run(run_name=run_name) as run:
        mlflow.log_params({
            "model": report["model"],
            "endpoint": endpoint,
            "url": report["url"],
            "max_tokens": report["max_tokens"],
            "temperature": report.get("temperature", 0),
            "slo_ms": report["slo_ms"],
            "gpu_type": args.gpu_type,
            "gpu_count": args.gpu_count,
            "ramp": ",".join(str(s["concurrency"]) for s in report["steps"]),
        })

        for step in report["steps"]:
            c = step["concurrency"]
            for metric in STEP_METRICS:
                mlflow.log_metric(metric, step[metric], step=c)

        mlflow.log_metric("saturation_concurrency", report["saturation_concurrency"])
        mlflow.log_metric("max_sustained_rps", report["max_sustained_rps"])
        mlflow.log_artifact(args.results)

        if args.trace_calls:
            log_call_traces(report, run.info.run_id, run.info.experiment_id, run_name, args.max_traces)

        print(f"logged run '{run_name}' to experiment '{args.experiment}'")


def log_call_traces(report: dict, run_id: str, experiment_id: str, run_name: str, max_traces: int):
    """Create one MLflow trace per captured load-test call (from results.json 'calls').
    Each trace's start/end timestamps are set to the request's real end-to-end latency, so
    the Traces tab 'Execution time' column shows actual per-request performance. Built here
    (post-run), so it does not affect the measured timings."""
    calls = report.get("calls", [])
    if not calls:
        print("no 'calls' captured; run the load test with -trace to enable per-call traces")
        return
    if max_traces > 0:
        calls = calls[:max_traces]

    client = MlflowClient()
    prompt = report.get("prompt", "")
    base = time.time_ns()
    for i, c in enumerate(calls):
        start_ns = base + i * 1_000_000  # 1ms apart to keep a stable order
        end_ns = start_ns + int(c["e2e_ms"] * 1_000_000)
        span = client.start_trace(
            name="loadtest_call",
            inputs={"prompt": prompt},
            attributes={
                "concurrency": str(c["concurrency"]),
                "ok": str(c["ok"]),
                "tokens": str(c["tokens"]),
                "finish_reason": c["finish_reason"] or "",
                "ttft_ms": str(c["ttft_ms"]),
                "e2e_ms": str(c["e2e_ms"]),
            },
            tags={"run_name": run_name, "concurrency": str(c["concurrency"]), "ok": str(c["ok"])},
            experiment_id=experiment_id,
            start_time_ns=start_ns,
            run_id=run_id,
        )
        client.end_trace(span.trace_id, outputs={"response": c["response"]}, end_time_ns=end_ns)
        if (i + 1) % 100 == 0:
            print(f"  logged {i + 1}/{len(calls)} call traces...")
    print(f"logged {len(calls)} per-call traces (execution time = real request latency)")


if __name__ == "__main__":
    main()

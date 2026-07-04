"""Log a load-test results.json as one MLflow run.

Per-step metrics are logged with step=concurrency, so the MLflow UI plots
throughput / latency against concurrency. Run:

    uv run python log_to_mlflow.py ../loadtest/results.json --gpu-type GTX-1660Ti --gpu-count 1
"""

import argparse
import json
import os
import sys
from pathlib import Path

import mlflow

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
    args = parser.parse_args()

    report = json.loads(Path(args.results).read_text())
    endpoint = "local" if "localhost" in report["url"] else "runpod"

    mlflow.set_tracking_uri(os.environ.get("MLFLOW_TRACKING_URI", "http://localhost:5000"))
    mlflow.set_experiment(args.experiment)

    run_name = args.run_name or f"{endpoint}-{args.gpu_count}gpu-{report['model'].split('/')[-1]}"
    with mlflow.start_run(run_name=run_name):
        mlflow.log_params({
            "model": report["model"],
            "endpoint": endpoint,
            "url": report["url"],
            "max_tokens": report["max_tokens"],
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

        print(f"logged run '{run_name}' to experiment '{args.experiment}'")


if __name__ == "__main__":
    main()

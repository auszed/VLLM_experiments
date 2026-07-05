"""Send a set of prompts through the chat endpoint and record each answer.

Unlike the load test (which forces max_tokens and discards output), this pass
lets the model stop naturally so you can read what it actually answered and judge
correctness. Writes traces.jsonl; log_to_mlflow.py logs it as a table + artifact.

    uv run python trace_answers.py [--prompts f] [--max-tokens 256] [--out path]
"""

import argparse
import json
import os
import sys
import time
from pathlib import Path

from openai import OpenAI

# MLflow/console on Windows defaults to cp1252; responses may contain unicode.
sys.stdout.reconfigure(encoding="utf-8", errors="replace")

DEFAULT_PROMPTS = [
    "Write a Python function that returns the nth Fibonacci number.",
    "What does this Go code print? fmt.Println(len(\"héllo\"))",
    "Reverse a singly linked list in Python.",
    "What is 17 * 23? Answer with just the number.",
    "Explain what a mutex is in one short paragraph.",
]


def load_env():
    env_path = Path(__file__).resolve().parent.parent / ".env"
    if not env_path.exists():
        return
    for line in env_path.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            key, value = line.split("=", 1)
            os.environ.setdefault(key.strip(), value.strip())


def read_prompts(path: str | None) -> list[str]:
    if not path:
        return DEFAULT_PROMPTS
    lines = Path(path).read_text(encoding="utf-8").splitlines()
    return [ln.strip() for ln in lines if ln.strip() and not ln.strip().startswith("#")]


def build_client() -> OpenAI:
    base_url = os.environ.get("VLLM_BASE_URL", "http://localhost:8000/v1")
    api_key = os.environ.get("VLLM_API_KEY", "change-me")
    return OpenAI(base_url=base_url, api_key=api_key)


def trace_one(client: OpenAI, model: str, prompt: str, max_tokens: int) -> dict:
    start = time.perf_counter()
    resp = client.chat.completions.create(
        model=model,
        messages=[{"role": "user", "content": prompt}],
        max_tokens=max_tokens,
        temperature=0,
    )
    latency_ms = (time.perf_counter() - start) * 1000
    choice = resp.choices[0]
    return {
        "model": model,
        "prompt": prompt,
        "response": choice.message.content or "",
        "finish_reason": choice.finish_reason,
        "prompt_tokens": resp.usage.prompt_tokens,
        "completion_tokens": resp.usage.completion_tokens,
        "latency_ms": round(latency_ms, 1),
    }


def main():
    load_env()
    parser = argparse.ArgumentParser()
    parser.add_argument("--prompts", default=None, help="file with one prompt per line")
    parser.add_argument("--max-tokens", type=int, default=256)
    parser.add_argument("--out", default="../loadtest/traces.jsonl")
    args = parser.parse_args()

    client = build_client()
    model = client.models.list().data[0].id

    prompts = read_prompts(args.prompts)
    print(f"Tracing {len(prompts)} prompts against {client.base_url}  model={model}")

    traces = [trace_one(client, model, p, args.max_tokens) for p in prompts]

    out_path = Path(args.out)
    with out_path.open("w", encoding="utf-8") as f:
        for t in traces:
            f.write(json.dumps(t, ensure_ascii=False) + "\n")

    truncated = [t for t in traces if t["finish_reason"] != "stop"]
    print(f"wrote {len(traces)} traces to {out_path}")
    if truncated:
        print(f"warning: {len(truncated)} response(s) did not stop naturally "
              f"(finish_reason != stop); consider raising --max-tokens")


if __name__ == "__main__":
    main()

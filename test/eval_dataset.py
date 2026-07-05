"""Run a question dataset through the chat endpoint and record one MLflow trace per
question, so you can read what the model answered and judge correctness.

Questions live in an editable questions.jsonl (one {"question": ...} per line). They are
registered as a managed MLflow evaluation dataset (Datasets tab) and run with
mlflow.genai.evaluate, which produces one trace per question (Traces tab) in an Eval run.

    uv run python eval_dataset.py [--num 5] [--questions questions.jsonl]
"""

import argparse
import json
import os
import sys
from pathlib import Path

import mlflow
import mlflow.openai
from mlflow.genai import evaluate
from mlflow.genai.datasets import create_dataset, search_datasets
from mlflow.genai.scorers import scorer

from trace_answers import build_client

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


def read_questions(path: str) -> list[str]:
    lines = Path(path).read_text(encoding="utf-8").splitlines()
    return [json.loads(ln)["question"] for ln in lines if ln.strip()]


def get_or_create_dataset(name: str, experiment_id: str):
    for ds in search_datasets(experiment_ids=[experiment_id]):
        if ds.name == name:
            return ds
    return create_dataset(name=name, experiment_id=experiment_id)


@scorer
def answer_length(outputs) -> int:
    """Judge-free metric: characters in the answer. Also satisfies evaluate's need for a
    scorer, so every question still produces a trace without an LLM judge."""
    return len(outputs or "")


def main():
    load_env()
    parser = argparse.ArgumentParser()
    parser.add_argument("--questions", default="questions.jsonl")
    parser.add_argument("--dataset-name", default="vllm-questions")
    parser.add_argument("--num", type=int, default=0, help="questions per pass (0 = all)")
    parser.add_argument("--experiment", default="vllm-eval",
                        help="dedicated eval experiment (kept separate from load-test runs)")
    parser.add_argument("--max-tokens", type=int, default=512)
    args = parser.parse_args()

    mlflow.set_tracking_uri(os.environ.get("MLFLOW_TRACKING_URI", "http://localhost:5000"))
    experiment_id = mlflow.set_experiment(args.experiment).experiment_id

    questions = read_questions(args.questions)
    if args.num > 0:
        questions = questions[: args.num]
    records = [{"inputs": {"question": q}} for q in questions]

    dataset = get_or_create_dataset(args.dataset_name, experiment_id)
    dataset.merge_records(records)

    client = build_client()
    model = client.models.list().data[0].id
    mlflow.openai.autolog()

    def answer(question: str) -> str:
        resp = client.chat.completions.create(
            model=model,
            messages=[{"role": "user", "content": question}],
            max_tokens=args.max_tokens,
            temperature=0,
        )
        return resp.choices[0].message.content or ""

    print(f"Evaluating {len(records)} questions against {client.base_url}  model={model}")
    evaluate(data=records, scorers=[answer_length], predict_fn=answer)
    print(f"done. See experiment '{args.experiment}' -> Traces (one per question) and "
          f"Datasets -> '{args.dataset_name}'.")


if __name__ == "__main__":
    main()

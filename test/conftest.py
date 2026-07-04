"""Shared fixtures. Loads the project-root .env and exposes an OpenAI client
pointed at the running vLLM server (local or RunPod)."""

import os
from pathlib import Path

import pytest
from openai import OpenAI


def _load_env():
    """Load KEY=VALUE lines from the project-root .env into os.environ."""
    env_path = Path(__file__).resolve().parent.parent / ".env"
    if not env_path.exists():
        return
    for line in env_path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip())


_load_env()


@pytest.fixture(scope="session")
def base_url() -> str:
    return os.environ.get("VLLM_BASE_URL", "http://localhost:8000/v1")


@pytest.fixture(scope="session")
def root_url(base_url) -> str:
    """Server root (for /health), i.e. base_url without the trailing /v1."""
    return base_url.rsplit("/v1", 1)[0]


@pytest.fixture(scope="session")
def api_key() -> str:
    return os.environ.get("VLLM_API_KEY", "change-me")


@pytest.fixture(scope="session")
def client(base_url, api_key) -> OpenAI:
    return OpenAI(base_url=base_url, api_key=api_key)


@pytest.fixture(scope="session")
def served_model(client) -> str:
    """The model id the server currently reports."""
    return client.models.list().data[0].id

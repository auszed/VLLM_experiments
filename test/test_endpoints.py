"""Smoke tests for the vLLM OpenAI-compatible endpoint.

Asserts the contract that clients, the frontend, and the load tester depend on:
health, model listing, and both non-streaming and streaming chat completions.
Runs against VLLM_BASE_URL (local tiny model or the RunPod 70B)."""

import httpx


def test_health(root_url, api_key):
    r = httpx.get(f"{root_url}/health", headers={"Authorization": f"Bearer {api_key}"})
    assert r.status_code == 200


def test_models_lists_a_model(served_model):
    assert served_model


def test_chat_non_streaming(client, served_model):
    resp = client.chat.completions.create(
        model=served_model,
        messages=[{"role": "user", "content": "Say hello in one short sentence."}],
        max_tokens=32,
        temperature=0,
    )
    assert resp.choices[0].message.content.strip()


def test_chat_streaming(client, served_model):
    stream = client.chat.completions.create(
        model=served_model,
        messages=[{"role": "user", "content": "Count from 1 to 5."}],
        max_tokens=32,
        temperature=0,
        stream=True,
    )
    chunks = [c.choices[0].delta.content or "" for c in stream]
    assert len([c for c in chunks if c]) > 1  # streamed in multiple pieces
    assert "".join(chunks).strip()

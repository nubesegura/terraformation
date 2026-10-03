"""Natural-language summary of a diff with Amazon Bedrock (optional, off by default)."""

from __future__ import annotations

import json
from typing import Any

from terraformation.models import StateDiff

MAX_RESOURCES = 60
MAX_VALUE = 80


def diff_digest(diff: StateDiff) -> dict[str, Any]:
    """Compact digest of the diff: only addresses, keys and already masked/truncated values."""

    def cut(v: str | None) -> str | None:
        return None if v is None else v[:MAX_VALUE]

    return {
        "from": {"version": diff.from_.version_id, "serial": diff.from_.serial},
        "to": {"version": diff.to.version_id, "serial": diff.to.serial},
        "summary": diff.summary.model_dump(),
        "added": [r.address for r in diff.added[:MAX_RESOURCES]],
        "removed": [r.address for r in diff.removed[:MAX_RESOURCES]],
        "modified": [
            {
                "address": m.address,
                "changes": [
                    {"key": c.key, "kind": c.kind, "old": cut(c.old), "new": cut(c.new)}
                    for c in m.changes[:10]
                ],
                "sensitive_changed": m.sensitive_changed,
            }
            for m in diff.modified[:MAX_RESOURCES]
        ],
        "outputs": [{"name": o.name, "kind": o.kind} for o in diff.outputs],
    }


_LANGUAGE_NAMES = {"en": "English", "es": "Spanish"}


_LANGUAGE_NAMES = {"en": "English", "es": "Spanish"}


def summarize_diff(client: Any, model_id: str, diff: StateDiff, language: str = "en") -> str:
    prompt = (
        f"Summarize in {_LANGUAGE_NAMES.get(language, language)} the changes between two "
        "versions of a Terraform state. "
        "Be concise (at most 8 bullets), group by risk and point out potentially "
        "destructive changes. Do not invent data. Data (JSON):\n"
        + json.dumps(diff_digest(diff), ensure_ascii=False)
    )
    resp = client.converse(
        modelId=model_id,
        messages=[{"role": "user", "content": [{"text": prompt}]}],
        inferenceConfig={"maxTokens": 700, "temperature": 0.2},
    )
    parts = resp["output"]["message"]["content"]
    return "".join(p.get("text", "") for p in parts).strip()

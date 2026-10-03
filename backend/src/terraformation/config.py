"""Configuración por variables de entorno."""

from __future__ import annotations

import os

from pydantic import BaseModel


class Settings(BaseModel):
    table_name: str = ""
    state_bucket: str = ""
    lock_alert_minutes: int = 30
    max_state_bytes: int = 40 * 1024 * 1024
    enable_plans_api: bool = False
    enable_bedrock: bool = False
    bedrock_model_id: str = ""
    deadline_margin_s: int = 60

    @classmethod
    def from_env(cls) -> Settings:
        env = os.environ
        return cls(
            table_name=env.get("TABLE_NAME", ""),
            state_bucket=env.get("STATE_BUCKET", ""),
            lock_alert_minutes=int(env.get("LOCK_ALERT_MINUTES", "30")),
            max_state_bytes=int(env.get("MAX_STATE_BYTES", str(40 * 1024 * 1024))),
            enable_plans_api=env.get("ENABLE_PLANS_API", "false").lower() == "true",
            enable_bedrock=env.get("ENABLE_BEDROCK", "false").lower() == "true",
            bedrock_model_id=env.get("BEDROCK_MODEL_ID", ""),
        )

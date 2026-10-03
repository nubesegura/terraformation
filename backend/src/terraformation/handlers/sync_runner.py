"""Shared backfill/reconcile execution with self-reinvocation."""

from __future__ import annotations

import json
import time
from typing import Any

import boto3
from aws_lambda_powertools import Logger
from aws_lambda_powertools.utilities.typing import LambdaContext

from terraformation.runtime import get_ctx, get_settings
from terraformation.sync import sync_bucket

logger = Logger(child=True)


def run(event: dict[str, Any], context: LambdaContext, *, resync_current: bool) -> dict[str, Any]:
    settings = get_settings()
    remaining_s = context.get_remaining_time_in_millis() / 1000
    deadline = time.monotonic() + max(remaining_s - settings.deadline_margin_s, 5)
    cursor = str(event.get("cursor", "")) if isinstance(event, dict) else ""
    result = sync_bucket(get_ctx(), cursor=cursor, deadline=deadline, resync_current=resync_current)
    logger.info("sync chunk", **result)
    if not result["done"]:
        boto3.client("lambda").invoke(
            FunctionName=context.function_name,
            InvocationType="Event",
            Payload=json.dumps({"cursor": result["cursor"]}).encode(),
        )
        logger.info("continuation scheduled", cursor=result["cursor"])
    return result

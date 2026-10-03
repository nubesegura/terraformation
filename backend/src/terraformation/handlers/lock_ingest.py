"""Locks Lambda: Object Created/Deleted events of the .tflock files."""

from __future__ import annotations

from typing import Any

from aws_lambda_powertools import Logger, Tracer
from aws_lambda_powertools.utilities.typing import LambdaContext

from terraformation.locks import process_lock_event
from terraformation.runtime import get_ctx

logger = Logger(service="lock-ingest")
tracer = Tracer(service="lock-ingest")


@logger.inject_lambda_context(clear_state=True)
@tracer.capture_lambda_handler
def handler(event: dict[str, Any], context: LambdaContext) -> dict[str, str]:
    result = process_lock_event(get_ctx(), event)
    logger.info("processed", result=result)
    return {"result": result}

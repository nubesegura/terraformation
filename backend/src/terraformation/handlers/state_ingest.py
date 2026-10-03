"""Lambda de ingesta: eventos Object Created/Deleted de los .tfstate."""

from __future__ import annotations

from typing import Any

from aws_lambda_powertools import Logger, Tracer
from aws_lambda_powertools.utilities.typing import LambdaContext

from terraformation.ingest import process_state_event
from terraformation.runtime import get_ctx

logger = Logger(service="state-ingest")
tracer = Tracer(service="state-ingest")


@logger.inject_lambda_context(clear_state=True)
@tracer.capture_lambda_handler
def handler(event: dict[str, Any], context: LambdaContext) -> dict[str, str]:
    result = process_state_event(get_ctx(), event)
    logger.info("processed", result=result)
    return {"result": result}

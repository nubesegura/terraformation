"""Reconciliación semanal (red de seguridad): rellena huecos y realinea el estado vigente."""

from __future__ import annotations

from typing import Any

from aws_lambda_powertools import Logger, Tracer
from aws_lambda_powertools.utilities.typing import LambdaContext

from terraformation.handlers.sync_runner import run

logger = Logger(service="reconcile")
tracer = Tracer(service="reconcile")


@logger.inject_lambda_context(clear_state=True)
@tracer.capture_lambda_handler
def handler(event: dict[str, Any], context: LambdaContext) -> dict[str, Any]:
    return run(event, context, resync_current=True)

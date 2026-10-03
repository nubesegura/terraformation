"""Lambda de escritura de planes (POST /api/plans) detrás de API Gateway HTTP API."""

from __future__ import annotations

from typing import Any

from aws_lambda_powertools import Logger, Tracer
from aws_lambda_powertools.utilities.typing import LambdaContext
from mangum import Mangum

from terraformation.api.app import create_app, set_services
from terraformation.runtime import get_services

logger = Logger(service="plans")
tracer = Tracer(service="plans")

app = create_app("plans")
_adapter = Mangum(app, lifespan="off")


@logger.inject_lambda_context(clear_state=True)
@tracer.capture_lambda_handler
def handler(event: dict[str, Any], context: LambdaContext) -> dict[str, Any]:
    set_services(get_services())
    return _adapter(event, context)  # type: ignore[arg-type]

"""CloudFormation custom resource: enables EventBridge while preserving the existing config.

PutBucketNotificationConfiguration *replaces* the whole configuration, so the current one
is read and sent back intact, adding only ``EventBridgeConfiguration``.
"""

from __future__ import annotations

import json
import urllib.request
from typing import Any

import boto3

PRESERVED = (
    "TopicConfigurations",
    "QueueConfigurations",
    "LambdaFunctionConfigurations",
)


def merge_configuration(current: dict[str, Any], enable: bool = True) -> dict[str, Any]:
    """Returns the configuration to send: the current one (without metadata) with/without EventBridge."""
    merged: dict[str, Any] = {k: current[k] for k in PRESERVED if current.get(k)}
    if enable:
        merged["EventBridgeConfiguration"] = {}
    return merged


def _respond(event: dict[str, Any], status: str, reason: str, physical_id: str) -> None:
    body = json.dumps(
        {
            "Status": status,
            "Reason": reason[:1000],
            "PhysicalResourceId": physical_id,
            "StackId": event["StackId"],
            "RequestId": event["RequestId"],
            "LogicalResourceId": event["LogicalResourceId"],
            "Data": {},
        }
    ).encode()
    req = urllib.request.Request(  # noqa: S310 - URL prefirmada de CloudFormation
        event["ResponseURL"], data=body, method="PUT", headers={"Content-Type": ""}
    )
    urllib.request.urlopen(req, timeout=10)  # noqa: S310


def handle(event: dict[str, Any], s3: Any) -> str:
    props = event["ResourceProperties"]
    bucket = props["BucketName"]
    request_type = event["RequestType"]
    if request_type == "Delete":
        if str(props.get("DisableOnDelete", "false")).lower() != "true":
            return "kept"
        enable = False
    else:
        enable = True
    current = s3.get_bucket_notification_configuration(Bucket=bucket)
    current.pop("ResponseMetadata", None)
    new_config = merge_configuration(current, enable)
    if request_type != "Delete" and "EventBridgeConfiguration" in current:
        return "already-enabled"
    s3.put_bucket_notification_configuration(Bucket=bucket, NotificationConfiguration=new_config)
    return "enabled" if enable else "disabled"


def handler(event: dict[str, Any], context: Any) -> None:
    physical_id = (
        event.get("PhysicalResourceId") or f"eventbridge-{event['ResourceProperties']['BucketName']}"
    )
    try:
        result = handle(event, boto3.client("s3"))
        _respond(event, "SUCCESS", result, physical_id)
    except Exception as exc:
        _respond(event, "FAILED", f"{type(exc).__name__}: {exc}", physical_id)

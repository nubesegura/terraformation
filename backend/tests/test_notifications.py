from unittest.mock import MagicMock

from terraformation.handlers.bucket_notifications import handle, merge_configuration

CURRENT = {
    "ResponseMetadata": {"HTTPStatusCode": 200},
    "TopicConfigurations": [
        {"Id": "t", "TopicArn": "arn:aws:sns:us-east-1:000000000000:t", "Events": ["s3:ObjectCreated:*"]}
    ],
    "QueueConfigurations": [
        {"Id": "q", "QueueArn": "arn:aws:sqs:us-east-1:000000000000:q", "Events": ["s3:ObjectRemoved:*"]}
    ],
    "LambdaFunctionConfigurations": [
        {
            "Id": "l",
            "LambdaFunctionArn": "arn:aws:lambda:us-east-1:000000000000:function:f",
            "Events": ["s3:ObjectCreated:Put"],
            "Filter": {"Key": {"FilterRules": [{"Name": "prefix", "Value": "x/"}]}},
        }
    ],
}


def event(kind="Create", **props):
    return {"RequestType": kind, "ResourceProperties": {"BucketName": "b", **props}}


def test_merge_preserves_everything_and_adds_eventbridge():
    cfg = {k: v for k, v in CURRENT.items() if k != "ResponseMetadata"}
    merged = merge_configuration(cfg)
    assert merged["EventBridgeConfiguration"] == {}
    for k in ("TopicConfigurations", "QueueConfigurations", "LambdaFunctionConfigurations"):
        assert merged[k] == cfg[k]


def test_create_puts_merged_config():
    s3 = MagicMock()
    s3.get_bucket_notification_configuration.return_value = dict(CURRENT)
    assert handle(event(), s3) == "enabled"
    sent = s3.put_bucket_notification_configuration.call_args.kwargs["NotificationConfiguration"]
    assert "ResponseMetadata" not in sent and sent["EventBridgeConfiguration"] == {}
    assert sent["QueueConfigurations"] == CURRENT["QueueConfigurations"]


def test_already_enabled_is_noop():
    s3 = MagicMock()
    s3.get_bucket_notification_configuration.return_value = {**CURRENT, "EventBridgeConfiguration": {}}
    assert handle(event("Update"), s3) == "already-enabled"
    s3.put_bucket_notification_configuration.assert_not_called()


def test_delete_keeps_by_default_and_can_disable():
    s3 = MagicMock()
    assert handle(event("Delete"), s3) == "kept"
    s3.put_bucket_notification_configuration.assert_not_called()
    s3.get_bucket_notification_configuration.return_value = {**CURRENT, "EventBridgeConfiguration": {}}
    assert handle(event("Delete", DisableOnDelete="true"), s3) == "disabled"
    sent = s3.put_bucket_notification_configuration.call_args.kwargs["NotificationConfiguration"]
    assert "EventBridgeConfiguration" not in sent and sent["TopicConfigurations"]

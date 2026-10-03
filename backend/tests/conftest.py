import json
from pathlib import Path

import pytest

FIXTURES = Path(__file__).parent / "fixtures"


@pytest.fixture
def fixture_bytes():
    def load(name: str) -> bytes:
        return (FIXTURES / name).read_bytes()

    return load


@pytest.fixture
def fixture_json():
    def load(name: str):
        return json.loads((FIXTURES / name).read_text())

    return load


# ---- AWS simulado (moto) ------------------------------------------------------------------
import os  # noqa: E402

os.environ.setdefault("AWS_DEFAULT_REGION", "us-east-1")
os.environ.setdefault("AWS_ACCESS_KEY_ID", "testing")
os.environ.setdefault("AWS_SECRET_ACCESS_KEY", "testing")
os.environ["POWERTOOLS_TRACE_DISABLED"] = "true"
os.environ["POWERTOOLS_SERVICE_NAME"] = "test"
os.environ["POWERTOOLS_LOG_LEVEL"] = "WARNING"

import boto3  # noqa: E402
from moto import mock_aws  # noqa: E402

from terraformation.config import Settings  # noqa: E402
from terraformation.ingest import Ctx  # noqa: E402
from terraformation.s3io import S3Reader  # noqa: E402
from terraformation.store import Store  # noqa: E402

BUCKET = "example-states"
TABLE = "terraformation-test"


def create_table(ddb):
    ddb.create_table(
        TableName=TABLE,
        BillingMode="PAY_PER_REQUEST",
        AttributeDefinitions=[
            {"AttributeName": n, "AttributeType": "S"}
            for n in ("PK", "SK", "GSI1PK", "GSI1SK", "GSI2PK", "GSI2SK")
        ],
        KeySchema=[
            {"AttributeName": "PK", "KeyType": "HASH"},
            {"AttributeName": "SK", "KeyType": "RANGE"},
        ],
        GlobalSecondaryIndexes=[
            {
                "IndexName": name,
                "KeySchema": [
                    {"AttributeName": f"{name}PK", "KeyType": "HASH"},
                    {"AttributeName": f"{name}SK", "KeyType": "RANGE"},
                ],
                "Projection": {"ProjectionType": "ALL"},
            }
            for name in ("GSI1", "GSI2")
        ],
    )


@pytest.fixture
def aws():
    with mock_aws():
        s3 = boto3.client("s3")
        s3.create_bucket(Bucket=BUCKET)
        s3.put_bucket_versioning(Bucket=BUCKET, VersioningConfiguration={"Status": "Enabled"})
        ddb = boto3.resource("dynamodb")
        create_table(ddb)
        yield {"s3": s3, "ddb": ddb, "table": ddb.Table(TABLE)}


@pytest.fixture
def settings():
    return Settings(table_name=TABLE, state_bucket=BUCKET)


@pytest.fixture
def ctx(aws, settings):
    return Ctx(settings=settings, store=Store(aws["table"]), s3=S3Reader(aws["s3"], BUCKET))


@pytest.fixture
def new_ctx(aws, settings):
    """Creates a new Ctx (empty cache), as in a new invocation."""
    return lambda: Ctx(settings=settings, store=Store(aws["table"]), s3=S3Reader(aws["s3"], BUCKET))


def s3_event(detail_type, key, version_id, **extra):
    detail = {"bucket": {"name": BUCKET}, "object": {"key": key, "version-id": version_id}}
    detail.update(extra)
    return {
        "version": "0",
        "source": "aws.s3",
        "detail-type": detail_type,
        "time": "2026-01-15T10:00:05Z",
        "detail": detail,
    }

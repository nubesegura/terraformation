"""Lazy construction of clients and context shared by the Lambdas."""

from __future__ import annotations

from functools import lru_cache

import boto3

from terraformation.api.services import Services
from terraformation.config import Settings
from terraformation.ingest import Ctx
from terraformation.s3io import S3Reader
from terraformation.store import Store


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings.from_env()


@lru_cache(maxsize=1)
def get_store() -> Store:
    return Store(boto3.resource("dynamodb").Table(get_settings().table_name))


@lru_cache(maxsize=1)
def get_s3() -> S3Reader:
    return S3Reader(boto3.client("s3"), get_settings().state_bucket)


def get_ctx() -> Ctx:
    # Ctx carries a per-invocation cache, so it is created anew each time.
    return Ctx(settings=get_settings(), store=get_store(), s3=get_s3())


@lru_cache(maxsize=1)
def get_services() -> Services:
    settings = get_settings()
    bedrock = boto3.client("bedrock-runtime") if settings.enable_bedrock else None
    return Services(settings, get_store(), get_s3(), bedrock)

"""Prueba de humo end-to-end local (sin AWS): FastAPI + moto + build de Flutter en Chromium.

    python scripts/e2e_smoke.py [--shots DIR]

Requiere `make web-build`, `pip install playwright uvicorn` y Chromium (PLAYWRIGHT_BROWSERS_PATH).
"""

from __future__ import annotations

import json
import os
import sys
import threading
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "backend"))
FIX = ROOT / "backend" / "tests" / "fixtures"
WEB = ROOT / "frontend" / "build" / "web"
PORT = 8765


def seed() -> object:
    os.environ.update(
        AWS_DEFAULT_REGION="us-east-1", AWS_ACCESS_KEY_ID="x", AWS_SECRET_ACCESS_KEY="x"
    )
    os.environ["POWERTOOLS_TRACE_DISABLED"] = "true"
    import boto3
    from terraformation.api.services import Services
    from terraformation.config import Settings
    from terraformation.ingest import Ctx, ingest_version
    from terraformation.keys import parse_key
    from terraformation.locks import process_lock_event
    from terraformation.s3io import S3Reader
    from terraformation.store import Store
    from tests.conftest import BUCKET, TABLE, create_table, s3_event

    s3 = boto3.client("s3")
    s3.create_bucket(Bucket=BUCKET)
    s3.put_bucket_versioning(
        Bucket=BUCKET, VersioningConfiguration={"Status": "Enabled"}
    )
    ddb = boto3.resource("dynamodb")
    create_table(ddb)
    settings = Settings(table_name=TABLE, state_bucket=BUCKET, lock_alert_minutes=30)
    ctx = Ctx(settings, Store(ddb.Table(TABLE)), S3Reader(s3, BUCKET))

    def put(key: str, name: str, lm: str) -> None:
        vid = s3.put_object(Bucket=BUCKET, Key=key, Body=(FIX / name).read_bytes())[
            "VersionId"
        ]
        ref = parse_key(key)
        assert ref is not None
        ingest_version(ctx, ref, key, vid, lm, 1000)

    put("network/terraform.tfstate", "tf-1.5.7-serial8.tfstate", "2026-09-01T10:00:00Z")
    put("network/terraform.tfstate", "tf-1.5.7-serial9.tfstate", "2026-09-20T10:00:00Z")
    put("database/terraform.tfstate", "tf-0.15.5.tfstate", "2026-09-25T10:00:00Z")
    put("legacy/terraform.tfstate", "tf-0.12.31.tfstate", "2026-08-01T10:00:00Z")
    put(
        "platform/terraform.tfstate",
        "opentofu-1.8-tf-1.9.8.tfstate",
        "2026-09-28T10:00:00Z",
    )
    lock = json.loads((FIX / "lock.tflock.json").read_text())
    lock["Created"] = "2026-09-30T08:00:00Z"
    vid = s3.put_object(
        Bucket=BUCKET,
        Key="database/terraform.tfstate.tflock",
        Body=json.dumps(lock).encode(),
    )["VersionId"]
    process_lock_event(
        ctx, s3_event("Object Created", "database/terraform.tfstate.tflock", vid)
    )
    return Services(settings, ctx.store, ctx.s3)


def main() -> int:
    from moto import mock_aws

    shots = (
        Path(sys.argv[sys.argv.index("--shots") + 1]) if "--shots" in sys.argv else None
    )
    if shots:
        shots.mkdir(parents=True, exist_ok=True)
    with mock_aws():
        svc = seed()
        import uvicorn
        from fastapi.staticfiles import StaticFiles
        from terraformation.api.app import create_app, set_services

        set_services(svc)  # type: ignore[arg-type]
        app = create_app("all")
        (WEB / "config.json").write_text(
            json.dumps(
                {
                    "apiBaseUrl": f"http://127.0.0.1:{PORT}",
                    "cognitoDomain": "https://login.invalid",
                    "clientId": "local",
                    "redirectUri": f"http://127.0.0.1:{PORT}/",
                }
            )
        )
        app.mount("/", StaticFiles(directory=str(WEB), html=True), name="web")
        server = uvicorn.Server(uvicorn.Config(app, port=PORT, log_level="warning"))
        threading.Thread(target=server.run, daemon=True).start()
        time.sleep(1.5)

        from playwright.sync_api import sync_playwright

        errors: list[str] = []
        with sync_playwright() as pw:
            browser = pw.chromium.launch(
                executable_path=os.environ.get("CHROMIUM_PATH") or None,
                args=["--no-sandbox"],
            )
            page = browser.new_page(viewport={"width": 1400, "height": 900})
            page.on("pageerror", lambda e: errors.append(str(e)))
            page.on("console", lambda m: m.type == "error" and errors.append(m.text))
            exp = int(time.time() * 1000) + 3_600_000
            page.add_init_script(
                f"sessionStorage.setItem('tf.access','t');sessionStorage.setItem('tf.expires','{exp}');"
            )
            base = f"http://127.0.0.1:{PORT}/"

            def go(frag: str, name: str, wait_ms: int = 2500) -> None:
                page.goto(base + "#" + frag)
                page.wait_for_timeout(wait_ms)
                if shots:
                    page.screenshot(path=str(shots / f"{name}.png"))

            go("/", "01-dashboard", 4000)
            go("/projects", "02-projects")
            go("/projects/network?workspace=default&tab=timeline", "03-timeline")
            go("/projects/network?workspace=default&tab=state", "04-state")
            go("/projects/network?workspace=default&tab=graph", "05-graph", 3500)
            go("/projects/database?workspace=default&tab=locks", "06-locks")
            go("/locks", "07-active-locks")
            go("/search", "08-search")
            versions = svc.store.list_versions(
                __import__("terraformation.keys", fromlist=["x"]).StateRef(
                    "network", "default"
                )
            )  # type: ignore[attr-defined]
            old, new = versions[0]["version_id"], versions[1]["version_id"]
            go(
                f"/projects/network/diff?workspace=default&from={old}&to={new}",
                "09-diff",
                3500,
            )
            browser.close()
        server.should_exit = True
        # Se ignoran avisos de recursos (favicon, fuentes) que no afectan la prueba
        real = [
            e
            for e in errors
            if "favicon" not in e and "Failed to load resource" not in e
        ]
        if real:
            print("Errores en consola:\n" + "\n".join(real))
            return 1
        print("e2e OK", f"(capturas en {shots})" if shots else "")
        return 0


if __name__ == "__main__":
    sys.exit(main())

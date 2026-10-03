import importlib.util
from pathlib import Path

spec = importlib.util.spec_from_file_location(
    "check_dart_models", Path(__file__).resolve().parents[2] / "scripts" / "check_dart_models.py"
)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


def test_dart_models_match_openapi_contract():
    assert mod.check() == []

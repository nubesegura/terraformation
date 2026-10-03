#!/usr/bin/env bash
# Construye el paquete único de las Lambdas (Python 3.13, arm64) en backend/build/package.
set -euo pipefail
cd "$(dirname "$0")/../backend"
rm -rf build/package && mkdir -p build/package
if command -v uv >/dev/null 2>&1; then
  uv pip install --quiet --target build/package \
    --python-platform aarch64-manylinux2014 --python-version 3.13 --only-binary :all: \
    -r requirements.txt
else
  python -m pip install --quiet --target build/package \
    --platform manylinux2014_aarch64 --platform manylinux_2_28_aarch64 \
    --implementation cp --python-version 3.13 --only-binary=:all: \
    --upgrade -r requirements.txt
fi
cp -r src/terraformation build/package/
find build/package -name '__pycache__' -type d -prune -exec rm -rf {} +
find build/package -name '*.dist-info' -type d -prune -exec rm -rf {} +
# boto3/botocore y sus dependencias ya vienen en el runtime de Lambda
rm -rf build/package/bin build/package/botocore build/package/boto3 build/package/jmespath \
  build/package/dateutil build/package/six.py build/package/urllib3 build/package/s3transfer
du -sh build/package

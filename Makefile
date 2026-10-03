# Terraformation - tareas de desarrollo y comandos de despliegue PREPARADOS.
# Ningún target de desarrollo toca AWS. Los targets de la sección "Despliegue" los ejecutas TÚ.

SHELL := /bin/bash
VENV ?= .venv
PY := $(VENV)/bin/python
BIN := $(VENV)/bin
FLUTTER ?= flutter
SAM ?= $(BIN)/sam

# ---- parámetros de despliegue (sobrescribe: make deploy ENV=prod STATE_BUCKET=...) ----
APP_NAME        ?= terraformation
ENV             ?= dev
REGION          ?= us-east-1
STATE_BUCKET    ?=
# Bucket de artefactos: si no se indica, se deriva del estandar de nombres
# bckt-<region>-<contexto>-artifacts-<cuenta>-<env-type> y se crea si no existe.
ARTIFACT_BUCKET ?=
CONTEXT         ?= terraformation
ENV_TYPE        := $(ENV)
AWS_PROFILE_ARG := $(if $(PROFILE),--profile $(PROFILE),)
STACK           ?= $(APP_NAME)-$(ENV)
EXTRA_PARAMS    ?=
AWS             := aws --region $(REGION) $(AWS_PROFILE_ARG)
ACCOUNT_ID       = $(shell $(AWS) sts get-caller-identity --query Account --output text)
ARTIFACT_BUCKET_NAME = $(or $(ARTIFACT_BUCKET),bckt-$(subst -,,$(REGION))-$(CONTEXT)-artifacts-$(ACCOUNT_ID)-$(ENV_TYPE))

.DEFAULT_GOAL := help
.PHONY: help
help: ## Muestra esta ayuda
	@grep -E '^[a-zA-Z0-9_.-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-22s\033[0m %s\n",$$1,$$2}'

# ----------------------------------------------------------------------------- desarrollo
.PHONY: install
install: ## Crea el venv (Python 3.13) e instala dependencias de desarrollo
	uv venv --python 3.13 $(VENV)
	uv pip install --python $(PY) -e "backend[dev]" cfn-lint checkov aws-sam-cli

.PHONY: lint
lint: ## ruff (lint + formato) y mypy
	$(BIN)/ruff check backend scripts
	$(BIN)/ruff format --check backend scripts
	cd backend && ../$(BIN)/mypy src

.PHONY: fmt
fmt: ## Formatea el código Python
	$(BIN)/ruff check --fix backend scripts
	$(BIN)/ruff format backend scripts

.PHONY: test
test: ## Pruebas del backend (moto, sin AWS real)
	cd backend && ../$(BIN)/pytest --cov=terraformation --cov-report=term-missing:skip-covered

.PHONY: openapi
openapi: ## Regenera docs/openapi.yaml desde FastAPI
	$(PY) scripts/export_openapi.py

.PHONY: cfn-lint
cfn-lint: ## Valida las plantillas con cfn-lint (W3002: rutas locales de `sam package`; W1028: falso positivo con !If dentro de recursos condicionales)
	$(BIN)/cfn-lint infra/template.yaml infra/nested/*.yaml --ignore-checks W3002 W1028

.PHONY: aws-map-check
aws-map-check: ## Verifica el mapa Terraform -> recursos AWS (docs/AWS_MAP.md)
	$(PY) scripts/check_aws_map.py

.PHONY: sam-validate
sam-validate: ## Valida las plantillas con SAM CLI (traduce el Transform; no toca AWS)
	for t in infra/template.yaml infra/nested/*.yaml; do \
	  AWS_DEFAULT_REGION=$(REGION) AWS_ACCESS_KEY_ID=x AWS_SECRET_ACCESS_KEY=x $(SAM) validate -t $$t || exit 1; \
	done

.PHONY: checkov
checkov: ## Revisa las plantillas con checkov (sin descargas externas)
	$(BIN)/checkov -d infra --framework cloudformation --compact --quiet --skip-download

.PHONY: guard
guard: ## Revisa las plantillas con cfn-guard (requiere el binario cfn-guard)
	for f in infra/nested/*.yaml; do cfn-guard validate -d $$f -r infra/guard/terraformation.guard --show-summary fail || exit 1; done

.PHONY: web-analyze web-test web-build
web-analyze: ## flutter analyze
	cd frontend && $(FLUTTER) pub get && $(FLUTTER) analyze
web-test: ## flutter test
	cd frontend && $(FLUTTER) test
web-build: ## Compila Flutter web (recursos locales, sin CDN)
	cd frontend && $(FLUTTER) build web --release --no-web-resources-cdn

.PHONY: check
check: lint test openapi cfn-lint sam-validate aws-map-check checkov ## Todo lo verificable en local (backend + plantillas)
	git diff --exit-code docs/openapi.yaml

.PHONY: build-backend
build-backend: ## Construye el paquete Lambda (arm64) en backend/build/package
	./scripts/build_lambda.sh

# ----------------------------------------------------------------------------- despliegue (lo ejecutas tú)
.PHONY: require-deploy-vars
require-deploy-vars:
	@test -n "$(STATE_BUCKET)" || (echo "Falta STATE_BUCKET=<bucket de states>"; exit 1)

.PHONY: ensure-artifact-bucket
ensure-artifact-bucket: require-deploy-vars ## Crea el bucket de artefactos (nombre derivado del estándar) si no existe
	bash scripts/ensure-artifact-bucket.sh $(ARTIFACT_BUCKET_NAME) $(REGION) $(ENV_TYPE) $(AWS_PROFILE_ARG)

.PHONY: package
package: ensure-artifact-bucket build-backend ## Empaqueta y sube el código/plantillas anidadas al bucket de artefactos
	$(SAM) package --template-file infra/template.yaml \
	  --s3-bucket $(ARTIFACT_BUCKET_NAME) --s3-prefix $(STACK) \
	  --output-template-file infra/packaged-$(ENV).yaml --region $(REGION) $(AWS_PROFILE_ARG)

.PHONY: deploy
deploy: package ## Crea/actualiza el stack (ManageBucketNotifications=true habilita EventBridge en el bucket)
	$(SAM) deploy --template-file infra/packaged-$(ENV).yaml --stack-name $(STACK) \
	  --s3-bucket $(ARTIFACT_BUCKET_NAME) --s3-prefix $(STACK) --region $(REGION) $(AWS_PROFILE_ARG) \
	  --capabilities CAPABILITY_IAM CAPABILITY_AUTO_EXPAND --no-fail-on-empty-changeset --no-confirm-changeset \
	  --parameter-overrides AppName=$(APP_NAME) Environment=$(ENV) StateBucketName=$(STATE_BUCKET) \
	    StateBucketRegion=$(REGION) $(EXTRA_PARAMS)

.PHONY: changeset
changeset: package ## Solo crea un change set para revisarlo (no aplica cambios)
	$(SAM) deploy --template-file infra/packaged-$(ENV).yaml --stack-name $(STACK) \
	  --s3-bucket $(ARTIFACT_BUCKET_NAME) --s3-prefix $(STACK) --region $(REGION) $(AWS_PROFILE_ARG) \
	  --capabilities CAPABILITY_IAM CAPABILITY_AUTO_EXPAND --no-execute-changeset --no-confirm-changeset \
	  --parameter-overrides AppName=$(APP_NAME) Environment=$(ENV) StateBucketName=$(STATE_BUCKET) \
	    StateBucketRegion=$(REGION) $(EXTRA_PARAMS)

define stack_output
$$($(AWS) cloudformation describe-stacks --stack-name $(STACK) --query "Stacks[0].Outputs[?OutputKey=='$(1)'].OutputValue" --output text)
endef

.PHONY: backfill
backfill: ## Lanza el backfill inicial (asíncrono; se auto-reinvoca hasta terminar)
	$(AWS) lambda invoke --function-name $(call stack_output,BackfillFunctionName) \
	  --invocation-type Event --cli-binary-format raw-in-base64-out --payload '{}' /dev/stdout

.PHONY: reconcile-now
reconcile-now: ## Ejecuta la reconciliación manualmente
	$(AWS) lambda invoke --function-name $(call stack_output,ReconcileFunctionName) \
	  --invocation-type Event --cli-binary-format raw-in-base64-out --payload '{}' /dev/stdout

.PHONY: enable-eventbridge-manual
enable-eventbridge-manual: ## (ManageBucketNotifications=false) muestra la config a aplicar; añade APPLY=1 para aplicarla
	./scripts/enable-eventbridge.sh $(STATE_BUCKET) $(if $(APPLY),--apply,) $(AWS_PROFILE_ARG)

.PHONY: lifecycle-rules
lifecycle-rules: ## Genera reglas de lifecycle (JSON) para expirar versiones no actuales de .tflock (DAYS=30)
	@$(AWS) s3api list-objects-v2 --bucket $(STATE_BUCKET) --query 'Contents[].Key' --output text \
	  | tr '\t' '\n' | $(PY) scripts/lifecycle_tflock.py --days $(or $(DAYS),30)

.PHONY: create-user
create-user: ## Crea un usuario de Cognito: make create-user EMAIL=ana@example.com
	@test -n "$(EMAIL)" || (echo "Falta EMAIL="; exit 1)
	$(AWS) cognito-idp admin-create-user --user-pool-id $(call stack_output,UserPoolId) \
	  --username $(EMAIL) --user-attributes Name=email,Value=$(EMAIL) Name=email_verified,Value=true \
	  --desired-delivery-mediums EMAIL

.PHONY: web-config
web-config: ## Genera frontend/build/web/config.json con los outputs del stack
	@mkdir -p frontend/build/web
	@printf '{"apiBaseUrl":"%s","cognitoDomain":"%s","clientId":"%s","redirectUri":"%s/"}\n' \
	  "$(call stack_output,ApiUrl)" "$(call stack_output,CognitoDomain)" \
	  "$(call stack_output,SpaClientId)" "$(call stack_output,WebUrl)" > frontend/build/web/config.json
	@cat frontend/build/web/config.json

.PHONY: web-deploy
web-deploy: web-build web-config ## Sube el frontend al bucket privado e invalida CloudFront
	$(AWS) s3 sync frontend/build/web s3://$(call stack_output,WebBucketName) --delete \
	  --exclude index.html --exclude config.json --exclude flutter_bootstrap.js --exclude 'main.dart.js' --exclude flutter_service_worker.js \
	  --cache-control "public,max-age=31536000,immutable"
	$(AWS) s3 cp frontend/build/web s3://$(call stack_output,WebBucketName) --recursive \
	  --exclude '*' --include index.html --include config.json --include flutter_bootstrap.js --include main.dart.js --include flutter_service_worker.js \
	  --cache-control "no-cache"
	$(AWS) cloudfront create-invalidation --distribution-id $(call stack_output,DistributionId) --paths '/*'

.PHONY: dlq-peek
dlq-peek: ## Lee (sin borrar) los mensajes de la DLQ
	$(AWS) sqs receive-message --queue-url $(call stack_output,DlqUrl) --max-number-of-messages 10 \
	  --visibility-timeout 0 --attribute-names All --message-attribute-names All

.PHONY: clean
clean: ## Limpia artefactos locales
	rm -rf backend/build infra/packaged-*.yaml .pytest_cache .mypy_cache .ruff_cache

# beyla-validation — operator entry point.
# Every workflow goes through `make`. No undocumented scripts.

SHELL          := /bin/bash
.SHELLFLAGS    := -eu -o pipefail -c
.DEFAULT_GOAL  := help

ENV            ?= canary
NAMESPACE      ?= alloy
TARGET_NS      ?= demo
RELEASE        ?= alloy
HELM_DIR       := deploy/helm/beyla
ALLOY_VALUES   := alloy/values.yaml
ALLOY_ENV      := alloy/values-$(ENV).yaml
VALUES         := $(HELM_DIR)/values.yaml
ENV_VALUES     := $(HELM_DIR)/values-$(ENV).yaml
REPORTS        := reports/$(ENV)/$(shell date -u +%Y%m%dT%H%M%SZ)
KUBECTL        ?= kubectl
HELM           ?= helm

# -------------------------------------------------------------------------
.PHONY: help
help: ## show this help
	@awk 'BEGIN {FS = ":.*##"; printf "Targets:\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-26s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

# =========================================================================
# Preflight & lint
# =========================================================================
.PHONY: preflight
preflight: ## kernel/k8s/runtime compatibility check (run before any install)
	@bash compatibility/kernel-probe-test.sh
	@bash scripts/preflight.sh

.PHONY: lint
lint: ## helm + yaml + dashboard JSON + alloy syntax lint
	@$(HELM) lint $(HELM_DIR)
	@bash scripts/lint-yaml.sh
	@bash scripts/lint-dashboards.sh
	@bash scripts/lint-alloy.sh

# =========================================================================
# Alloy mode (recommended): Beyla embedded as an Alloy component.
# =========================================================================
.PHONY: alloy-install
alloy-install: preflight lint ## install Alloy + Beyla pipeline for $(ENV)
	@$(HELM) repo add grafana https://grafana.github.io/helm-charts >/dev/null 2>&1 || true
	@$(HELM) repo update >/dev/null
	@$(KUBECTL) create namespace $(NAMESPACE) --dry-run=client -o yaml | $(KUBECTL) apply -f -
	@$(KUBECTL) create configmap alloy-config-beyla -n $(NAMESPACE) \
		--from-file=config.alloy=alloy/config.alloy \
		--dry-run=client -o yaml | $(KUBECTL) apply -f -
	@$(HELM) upgrade --install $(RELEASE) grafana/alloy \
		-n $(NAMESPACE) \
		-f $(ALLOY_VALUES) -f $(ALLOY_ENV) \
		--atomic --timeout 5m
	@$(KUBECTL) rollout status ds/$(RELEASE) -n $(NAMESPACE) --timeout=5m

.PHONY: alloy-config-reload
alloy-config-reload: ## push the latest config.alloy and trigger a rolling restart
	@$(KUBECTL) create configmap alloy-config-beyla -n $(NAMESPACE) \
		--from-file=config.alloy=alloy/config.alloy \
		--dry-run=client -o yaml | $(KUBECTL) apply -f -
	@$(KUBECTL) rollout restart ds/$(RELEASE) -n $(NAMESPACE)
	@$(KUBECTL) rollout status  ds/$(RELEASE) -n $(NAMESPACE) --timeout=5m

.PHONY: alloy-debug
alloy-debug: ## port-forward Alloy live debug UI at http://localhost:12345
	@$(KUBECTL) port-forward -n $(NAMESPACE) ds/$(RELEASE) 12345:12345

.PHONY: alloy-uninstall
alloy-uninstall: ## remove Alloy (verified by validation/13-rollback.sh logic)
	@$(HELM) uninstall $(RELEASE) -n $(NAMESPACE) --wait
	@$(KUBECTL) delete cm alloy-config-beyla -n $(NAMESPACE) --ignore-not-found
	@bash validation/13-rollback.sh $(NAMESPACE) $(RELEASE)

# =========================================================================
# Direct-mode Beyla DaemonSet (alternative; no Alloy).
# Use one or the other — not both.
# =========================================================================
.PHONY: install
install: preflight lint ## install raw Beyla DaemonSet for $(ENV) (no Alloy)
	@$(KUBECTL) create namespace beyla-system --dry-run=client -o yaml | $(KUBECTL) apply -f -
	@$(HELM) upgrade --install beyla $(HELM_DIR) \
		-f $(VALUES) -f $(ENV_VALUES) \
		--namespace beyla-system \
		--atomic --timeout 5m
	@$(KUBECTL) rollout status ds/beyla -n beyla-system --timeout=5m

.PHONY: rollback
rollback: ## safe disablement of whichever mode is installed
	@if $(KUBECTL) get ds alloy -n $(NAMESPACE) >/dev/null 2>&1; then \
	   echo "Alloy mode detected — running alloy-uninstall"; \
	   $(MAKE) alloy-uninstall; \
	else \
	   echo "Direct Beyla mode detected — running rollback"; \
	   bash validation/13-rollback.sh beyla-system beyla; \
	fi

# =========================================================================
# Validation suite (15 layers + Alloy)
# =========================================================================
.PHONY: validate
validate: ## run full validation suite and write reports
	@mkdir -p $(REPORTS)
	@bash validation/00-alloy-pipeline.sh $(NAMESPACE)  $(REPORTS)
	@bash validation/run-all.sh           $(NAMESPACE) $(TARGET_NS) $(REPORTS)

.PHONY: validate-quick
validate-quick: ## smoke: alloy + app + kernel + telemetry layers
	@mkdir -p $(REPORTS)
	@bash validation/00-alloy-pipeline.sh  $(NAMESPACE) $(REPORTS)
	@bash validation/01-application-layer.sh $(TARGET_NS) $(REPORTS)
	@bash validation/02-kernel-ebpf.sh       $(NAMESPACE) $(REPORTS)
	@bash validation/03-telemetry-accuracy.sh $(TARGET_NS) $(REPORTS)

# =========================================================================
# Playwright E2E
# =========================================================================
.PHONY: e2e
e2e: ## run Playwright E2E suite headless (auto-brings-up docker-compose)
	@cd e2e && npm install --silent && npx playwright install --with-deps chromium && npm test

.PHONY: e2e-headed
e2e-headed: ## same, but watch the browser
	@cd e2e && npm install --silent && npx playwright install --with-deps chromium && npm run test:headed

.PHONY: e2e-ui
e2e-ui: ## Playwright UI mode
	@cd e2e && npm run test:ui

.PHONY: e2e-cluster
e2e-cluster: ## run E2E against a real cluster (set GRAFANA_URL + GRAFANA_TOKEN)
	@: $${GRAFANA_URL:?set GRAFANA_URL}
	@: $${GRAFANA_TOKEN:?set GRAFANA_TOKEN}
	@cd e2e && SKIP_WEBSERVER=1 npm test

.PHONY: e2e-report
e2e-report: ## open the latest Playwright HTML report
	@cd e2e && npm run test:report

.PHONY: e2e-docker
e2e-docker: ## run E2E inside a Playwright container
	@docker build -t beyla-validation/e2e -f e2e/Dockerfile e2e/
	@docker run --rm --network host \
		-e GRAFANA_URL=http://localhost:3000 \
		-e SKIP_WEBSERVER=1 \
		-v $(PWD)/e2e/reports:/work/reports \
		-v $(PWD)/e2e/screenshots:/work/screenshots \
		beyla-validation/e2e

# =========================================================================
# Scorecard & promotion
# =========================================================================
.PHONY: scorecard
scorecard: ## compute GO/NO-GO score from latest reports
	@python3 scorecard/scorecard.py --reports $(shell ls -td reports/$(ENV)/* | head -1) \
		--thresholds scorecard/thresholds.yaml --env $(ENV) \
		--out reports/$(ENV)/latest-scorecard.md
	@cat reports/$(ENV)/latest-scorecard.md

.PHONY: promote
promote: ## promote canary→staging or staging→prod (requires scorecard PASS)
	@bash scripts/promote.sh $(ENV)

# =========================================================================
# Chaos & cost
# =========================================================================
.PHONY: chaos
chaos: ## run all chaos experiments sequentially
	@for f in chaos/*.yaml; do echo "▶ $$f"; $(KUBECTL) apply -f $$f -n $(NAMESPACE); sleep 60; $(KUBECTL) delete -f $$f -n $(NAMESPACE) || true; done

.PHONY: cost
cost: ## project storage/CPU/network cost for $(ENV)
	@python3 cost/cost-model.py --inputs cost/cost-model-inputs.yaml --env $(ENV)

# =========================================================================
# Local dev (docker-compose: Alloy + LGTM)
# =========================================================================
.PHONY: dev-up
dev-up: ## bring up local Alloy + LGTM stack
	@docker compose up -d
	@bash e2e/scripts/wait-for-grafana.sh
	@echo ""
	@echo "→ Grafana:   http://localhost:3000  (anon admin)"
	@echo "→ Alloy UI:  http://localhost:12345"
	@echo "→ Prometheus: http://localhost:9090"
	@echo "→ Tempo:     http://localhost:3200"
	@echo "→ Pyroscope: http://localhost:4040"

.PHONY: dev-down
dev-down: ## tear down local stack + volumes
	@docker compose down -v

.PHONY: dev-logs
dev-logs: ## tail Alloy logs from the local stack
	@docker compose logs -f alloy

# =========================================================================
# Dashboards & alerts
# =========================================================================
.PHONY: apply-dashboards
apply-dashboards: ## upload dashboards to Grafana via API (GRAFANA_URL + GRAFANA_TOKEN)
	@bash scripts/upload-dashboards.sh

.PHONY: apply-alerts
apply-alerts: ## apply PrometheusRule CRs
	@$(KUBECTL) apply -f alerts/ -n monitoring

.PHONY: help env up up-bi up-all down nuke logs ps dbt-build dbt-test edr-report start start-all stop

AIRBYTE_NODE := airbyte-abctl-control-plane
AIRBYTE_HEALTH := http://localhost:8000/api/v1/health
DAG_ID := indec_elt_diario

help:            ## Lista los comandos
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-12s %s\n", $$1, $$2}'

env:             ## Crea .env a partir del ejemplo
	@test -f .env || cp .env.example .env && echo ".env listo, completalo"

up:              ## Levanta el core (Postgres + Airflow)
	docker compose up -d --build

up-bi:           ## Core + Metabase
	docker compose --profile bi up -d --build

up-all:          ## Todo (core + Metabase + monitoreo)
	docker compose --profile bi --profile monitoring up -d --build

down:            ## Baja todo (conserva datos)
	docker compose --profile bi --profile monitoring down

nuke:            ## Baja todo y BORRA volúmenes
	docker compose --profile bi --profile monitoring down -v

logs:            ## Logs de Airflow
	docker compose logs -f airflow-scheduler airflow-apiserver

ps:              ## Estado de los contenedores
	docker compose --profile bi --profile monitoring ps

dbt-build:       ## dbt build dentro del contenedor
	docker compose exec airflow-scheduler bash -c 'cd $$DBT_PROJECT_DIR && $$DBT_EXECUTABLE build'

dbt-test:        ## Solo tests de dbt
	docker compose exec airflow-scheduler bash -c 'cd $$DBT_PROJECT_DIR && $$DBT_EXECUTABLE test'

edr-report:      ## Genera el reporte de Elementary
	docker compose exec airflow-scheduler bash -c 'cd $$DBT_PROJECT_DIR && /opt/dbt_venv/bin/edr report'

# --- Encender / apagar el stack completo (incluye Airbyte) -------------------
# Uso: make start | make start-all | make stop  (make stop FORCE=1 salta el chequeo)

define wait_airbyte
	@echo "Esperando a Airbyte (puede tardar 1-3 min)..."
	@for i in $$(seq 1 60); do \
		curl -sf $(AIRBYTE_HEALTH) >/dev/null 2>&1 && echo "Airbyte listo." && exit 0; \
		sleep 5; \
	done; \
	echo "Airbyte no respondió en 5 min. Revisá: docker logs $(AIRBYTE_NODE)"; exit 1
endef

start:           ## Prende Airbyte, espera a que responda y levanta el core
	docker start $(AIRBYTE_NODE)
	$(wait_airbyte)
	docker compose up -d
	@echo "Listo. Airflow en http://localhost:8080 (despausá el DAG si lo pausaste)."

start-all:       ## Igual que start, pero con Metabase y monitoreo
	docker start $(AIRBYTE_NODE)
	$(wait_airbyte)
	docker compose --profile bi --profile monitoring up -d
	@echo "Listo. Airflow :8080, Metabase :3000, Grafana :3001."

stop:            ## Baja todo y frena Airbyte (conserva datos)
	@if [ "$(FORCE)" != "1" ] && docker compose ps -q airflow-scheduler 2>/dev/null | grep -q .; then \
		if docker compose exec -T airflow-scheduler airflow dags list-runs $(DAG_ID) --state running -o plain 2>/dev/null | grep -q running; then \
			echo "Hay un run de $(DAG_ID) en curso. Esperá a que termine o usá: make stop FORCE=1"; exit 1; \
		fi; \
	fi
	docker compose --profile bi --profile monitoring down
	-docker stop $(AIRBYTE_NODE)
	@echo "Stack apagado. Si no vas a usar Docker, cerrá Docker Desktop para liberar la RAM."

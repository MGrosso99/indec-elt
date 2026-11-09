.PHONY: help env up up-bi up-all down nuke logs ps dbt-build dbt-test edr-report

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

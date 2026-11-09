#!/bin/bash
# -----------------------------------------------------------------------------
# Se ejecuta UNA sola vez, la primera vez que se crea el volumen de Postgres.
# Si cambiás algo acá: `docker compose down -v` (borra los datos) y volvé a subir.
#
# Crea:
#   - base + usuario para Airflow (metadata)
#   - base + usuario para el warehouse (lo usan Airbyte y dbt)
#   - base + usuario para Metabase (metadata de la app)
#   - rol de solo lectura "metabase_reader" sobre el warehouse
#   - schemas del warehouse por capa
# -----------------------------------------------------------------------------
set -euo pipefail

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres <<-EOSQL
  CREATE USER ${AIRFLOW_DB_USER}   WITH PASSWORD '${AIRFLOW_DB_PASSWORD}';
  CREATE USER ${WAREHOUSE_DB_USER} WITH PASSWORD '${WAREHOUSE_DB_PASSWORD}';
  CREATE USER ${METABASE_DB_USER}  WITH PASSWORD '${METABASE_DB_PASSWORD}';
  CREATE USER metabase_reader      WITH PASSWORD '${METABASE_READER_PASSWORD}';

  CREATE DATABASE ${AIRFLOW_DB_NAME}   OWNER ${AIRFLOW_DB_USER};
  CREATE DATABASE ${WAREHOUSE_DB_NAME} OWNER ${WAREHOUSE_DB_USER};
  CREATE DATABASE ${METABASE_DB_NAME}  OWNER ${METABASE_DB_USER};
EOSQL

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$WAREHOUSE_DB_NAME" <<-EOSQL
  -- Capas del warehouse (dbt crea dev_* / prod_* según el target)
  CREATE SCHEMA IF NOT EXISTS raw       AUTHORIZATION ${WAREHOUSE_DB_USER};  -- Airbyte escribe acá
  CREATE SCHEMA IF NOT EXISTS snapshots AUTHORIZATION ${WAREHOUSE_DB_USER};  -- historial de revisiones

  -- Metabase solo se conecta; los permisos de lectura sobre los marts los
  -- otorga dbt (config "grants" + hook on-run-end, ver la documentación)
  GRANT CONNECT ON DATABASE ${WAREHOUSE_DB_NAME} TO metabase_reader;
EOSQL

echo "Bases inicializadas: ${AIRFLOW_DB_NAME}, ${WAREHOUSE_DB_NAME}, ${METABASE_DB_NAME}"

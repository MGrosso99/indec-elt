ARG AIRFLOW_VERSION=3.1.0
FROM apache/airflow:${AIRFLOW_VERSION}

# --- Providers de Airflow (mismo entorno que Airflow) -------------------------
COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir \
      "apache-airflow==${AIRFLOW_VERSION}" \
      -r /tmp/requirements.txt

# --- dbt en un virtualenv separado -------------------------------------------
# dbt y Airflow suelen chocar en dependencias; Cosmos lo invoca por ruta
# (DBT_EXECUTABLE=/opt/dbt_venv/bin/dbt).
COPY dbt-requirements.txt /tmp/dbt-requirements.txt
RUN python -m venv /opt/dbt_venv \
 && /opt/dbt_venv/bin/pip install --no-cache-dir -r /tmp/dbt-requirements.txt

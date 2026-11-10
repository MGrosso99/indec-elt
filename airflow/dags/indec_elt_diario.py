from datetime import datetime, timedelta

from airflow.sdk import dag
from airflow.providers.airbyte.operators.airbyte import AirbyteTriggerSyncOperator
from cosmos import DbtTaskGroup, ExecutionConfig, ProfileConfig, ProjectConfig, RenderConfig

DBT_DIR = "/opt/airflow/dbt"


@dag(
    schedule="@daily",
    start_date=datetime(2026, 11, 1),
    catchup=False,          # no corre solo los días pasados
    max_active_runs=1,      # nunca dos corridas a la vez
    default_args={
        "retries": 2,
        "retry_delay": timedelta(minutes=5),
        "retry_exponential_backoff": True,
    },
    tags=["indec", "elt"],
)
def indec_elt_diario():
    sync = AirbyteTriggerSyncOperator(
        task_id="airbyte_sync",
        airbyte_conn_id="airbyte_default",
        connection_id="b4b46f3d-befa-4159-bdce-29fbdc18ac9b",
        asynchronous=False,  # espera a que el sync termine
        timeout=3600,
    )

    transform = DbtTaskGroup(
        group_id="dbt",
        project_config=ProjectConfig(DBT_DIR),
        profile_config=ProfileConfig(
            profile_name="indec",
            target_name="prod",
            profiles_yml_filepath=f"{DBT_DIR}/profiles.yml",
        ),
        execution_config=ExecutionConfig(dbt_executable_path="/opt/dbt_venv/bin/dbt"),
        render_config=RenderConfig(exclude=["package:elementary"]),
    )

    sync >> transform   # primero Airbyte, después dbt


indec_elt_diario()
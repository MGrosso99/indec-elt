from datetime import datetime, timedelta
from airflow.sdk import dag
from airflow.providers.airbyte.operators.airbyte import AirbyteTriggerSyncOperator
from cosmos import DbtTaskGroup, ExecutionConfig, ProfileConfig, ProjectConfig, RenderConfig
from airflow.providers.slack.notifications.slack_webhook import send_slack_webhook_notification
from airflow.providers.standard.operators.bash import BashOperator

alerta = send_slack_webhook_notification(
    slack_webhook_conn_id="slack_alerts",
    text=":red_circle: Falló {{ ti.task_id }} en {{ dag.dag_id }} ({{ ds }})",
)

DBT_DIR = "/opt/airflow/dbt"


@dag(
    schedule="@daily",
    start_date=datetime(2026, 11, 1),
    catchup=False,          # no corre solo los días pasados
    max_active_runs=1,      # nunca dos corridas a la vez
    default_args={
        "retries": 3,
        "retry_delay": timedelta(minutes=10),
        "retry_exponential_backoff": True,
        "on_failure_callback": alerta,
    },
    tags=["indec", "elt"],
)
def indec_elt_diario():
    sync = AirbyteTriggerSyncOperator(
        task_id="airbyte_sync",
        airbyte_conn_id="airbyte_default",
        connection_id="9330ccea-3f5c-455c-9777-8abbb94a6129",
        asynchronous=False,
        timeout=1800,                              # espera hasta 30 min por el sync
        execution_timeout=timedelta(minutes=40),   # corte duro de la task
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
        operator_args={"retries": 0},   # un test que falla no se arregla reintentando
    )

    monitor = BashOperator(
        task_id="elementary_monitor",
        bash_command=(
            "/opt/dbt_venv/bin/edr monitor "
            "--project-dir /opt/airflow/dbt --profiles-dir /opt/airflow/dbt "
            "--slack-webhook $SLACK_WEBHOOK_URL"
        ),
        trigger_rule="all_done",   # corre aunque dbt haya fallado, para reportarlo
    )

    sync >> transform >> monitor 

indec_elt_diario()
from airflow.models import DagBag

DAGS = "/opt/airflow/src/dags"


def test_dags_importan_sin_errores():
    dagbag = DagBag(dag_folder=DAGS, include_examples=False)
    assert dagbag.import_errors == {}, dagbag.import_errors


def test_existe_el_dag_diario():
    dagbag = DagBag(dag_folder=DAGS, include_examples=False)
    assert "indec_elt_diario" in dagbag.dags
# INDEC ELT

Pipeline ELT diario, open source y gratuito, que extrae series estadísticas de la
[API del INDEC](https://api.indec.gob.ar), las carga en un warehouse Postgres, las
modela con dbt y las publica en Metabase. Todo orquestado con Airflow y levantado
con Docker.

Proyecto de práctica de **Data Engineering y DataOps**: ingesta, modelado, calidad
de datos, observabilidad, orquestación y CI/CD de punta a punta.

> Fuente de los datos: INDEC — Catálogo API-INDEC.

- 📄 Documentación de los modelos (dbt docs): https://mgrosso99.github.io/indec-elt/
- 🗺️ Diagrama de arquitectura: [`docs/arquitectura.html`](docs/arquitectura.html)

---

## Arquitectura

```
API INDEC ──GET──▶ Airbyte ──carga──▶ Postgres (raw) ──dbt──▶ staging ──▶ marts ──▶ Metabase
                      ▲                                    │
                      └──────── Airflow (DAG diario) ──────┘
                                       │
                 Elementary · Prometheus + Grafana ──▶ Slack
```

**Corrida diaria:**

1. Airflow dispara el sync de Airbyte (Full refresh → Overwrite de `raw`).
2. Cosmos ejecuta `dbt build`: staging, snapshot y marts, cada modelo con sus tests.
3. `edr monitor` (Elementary) revisa los resultados y alerta a Slack si algún test falló.
4. Metabase lee los marts con un usuario de solo lectura.

---

## Stack

| Capa | Herramienta | Por qué |
| --- | --- | --- |
| Fuente | API del INDEC (beta, REST + JSON) | API oficial nueva, estilo PostgREST |
| Extracción y carga | Airbyte + Connector Builder (`abctl`) | Conector low-code, versionado como YAML |
| Warehouse | Postgres 16 | Simple, estándar, suficiente para el volumen |
| Transformación | dbt-core 1.12 + dbt-postgres | SQL testeable, documentación y lineage |
| Orquestación | Airflow 3 + Astronomer Cosmos | Cada modelo de dbt es una task visible |
| Calidad de datos | Tests de dbt + dbt-expectations | Reglas declarativas por modelo |
| Observabilidad de datos | Elementary | Tests, freshness, anomalías; alertas a Slack |
| Observabilidad de infra | Prometheus + Grafana | Métricas de Airflow (StatsD) y Postgres (postgres-exporter)* |
| Alertas | Slack (Incoming Webhooks) | `#alertas-datos` y `#alertas-infra` |
| BI | Metabase | Dashboard sobre los marts |
| CI/CD | GitHub Actions + GHCR + GitHub Pages | Lint, tests y `dbt build` en cada PR; imagen y docs en cada merge |
| Calidad de código | ruff, SQLFluff, pre-commit | Los mismos chequeos del CI, antes de cada commit |

\* cAdvisor (métricas por contenedor) se quitó: en Docker Desktop para Mac no reporta datos. Ver problema 13.

---

## Modelo de datos

| Capa | Schema | Materialización | Contenido |
| --- | --- | --- | --- |
| Raw | `raw` | Tabla (Airbyte) | Respuesta de la API tal cual, sin modificar |
| Staging | `prod_staging` | **Tabla** | Tipado, renombres, fecha real desde `periodo` |
| Snapshots | `snapshots` | Snapshot | Historial de revisiones de cada valor |
| Marts | `prod_marts` | Tabla | `fct_ipi_manufacturero`, `dim_actividades` |

**IPI manufacturero**

- Clave primaria del INDEC (7 columnas): `periodo`, `indicador`, `cuadro_web`,
  `codigo_CLaNAE_2004`, `descripcion`, `serie`, `tipo_de_indicador`.
- `dim_actividades`: una fila por actividad o producto, con clave subrogada
  `actividad_id` = código CLaNAE + descripción, y su `nivel` en la clasificación:

| Nivel | Ejemplo | Qué representa |
| --- | --- | --- |
| Sección | `D` | Industria manufacturera total |
| División | `15` | Alimentos y bebidas |
| Subclase | `15111` | Carne vacuna |
| Producto | `23200` + `Naftas` | Varias series que comparten código |

---

## Dashboard

Las consultas de cada gráfico están versionadas en [`bi/queries/`](bi/queries/):

| Gráfico | Consulta |
| --- | --- |
| Evolución de la industria (serie desestacionalizada) | `ipi_desestacionalizado.sql` |
| Variación interanual del nivel general | `ipi_interanual.sql` |
| Ranking de ramas en el último mes | `sectores_interanual.sql` |


---

## Alertas

| Qué falla | Quién avisa | Canal |
| --- | --- | --- |
| `airbyte_sync` (después de 3 reintentos) | Airflow (`on_failure_callback`) | `#alertas-datos` |
| Una task de dbt (sin reintentos) | Airflow (`on_failure_callback`) | `#alertas-datos` |
| Un test de datos | Elementary (`edr monitor`) | `#alertas-datos` |
| Postgres caído o scheduler sin latido | Grafana | `#alertas-infra` |

Las URLs de los webhooks viven solo en `.env`.

---

## CI/CD

| Workflow | Cuándo | Qué hace |
| --- | --- | --- |
| [`ci.yml`](.github/workflows/ci.yml) | Cada pull request | `ruff` y `sqlfluff`; test de que los DAGs cargan; `dbt build` contra un Postgres efímero con datos de ejemplo (seed) |
| [`cd.yml`](.github/workflows/cd.yml) | Cada merge a `main` | Publica la imagen de Airflow en GHCR (`latest` + SHA del commit) y la documentación de dbt en GitHub Pages |

`main` está protegida: solo se modifica por pull request, con los tres checks del CI en verde.

---

## Cómo levantarlo

**Requisitos:** Docker Desktop (10 GB de RAM asignados), `make`, `abctl` y un
token gratuito de [api.indec.gob.ar](https://api.indec.gob.ar).

```bash
# 1. Variables de entorno
make env                 # crea .env desde .env.example; completalo

# 2. Postgres + Airflow
make up                  # http://localhost:8080

# 3. Airbyte (aparte, en su propio cluster)
abctl local install      # http://localhost:8000
# Importar airbyte/indec_source.yaml en el Connector Builder

# 4. dbt: tablas de Elementary (una vez por ambiente)
docker compose exec airflow-scheduler bash -c \
  'cd /opt/airflow/dbt && /opt/dbt_venv/bin/dbt deps && /opt/dbt_venv/bin/dbt run --select elementary --target prod'

# 5. BI y monitoreo (opcionales)
make up-bi               # Metabase en http://localhost:3000
make up-all              # + Prometheus (:9090) y Grafana (:3001)
```

| Comando | Qué hace |
| --- | --- |
| `make up` / `make down` | Levanta / apaga el core (conserva datos) |
| `make ps` | Estado de los contenedores |
| `make logs` | Logs de Airflow |
| `make dbt-build` | `dbt build` dentro del contenedor |
| `make nuke` | Apaga todo y **borra los datos** |

**Entorno de desarrollo (Python 3.12):**

```bash
python3.12 -m venv .venv && source .venv/bin/activate
pip install ruff sqlfluff pre-commit
pre-commit install       # ruff + SQLFluff antes de cada commit
```

---

## Estructura

```
indec-elt/
├── .github/workflows/            # ci.yml, cd.yml
├── airbyte/indec_source.yaml     # Conector exportado del Builder
├── airflow/
│   ├── Dockerfile                # Airflow 3 + providers + venv aislado de dbt
│   ├── dags/indec_elt_diario.py  # DAG diario: Airbyte → dbt → Elementary
│   └── tests/                    # Test de carga de DAGs
├── dbt/
│   ├── models/staging/           # stg_indec__ipi_manufacturero
│   ├── models/marts/             # fct_ipi_manufacturero, dim_actividades
│   ├── snapshots/                # historial de revisiones
│   ├── seeds/                    # muestra de datos para el CI
│   └── sqlfluff_libs/            # imitación de macros para el lint
├── infra/                        # init de Postgres, Prometheus, Grafana
├── bi/queries/                   # SQL de las preguntas de Metabase
├── docs/                         # arquitectura y capturas
├── docker-compose.yml
└── Makefile
```

---

## Decisiones de diseño

1. **Warehouse primero, lakehouse después.** El volumen (~42.000 filas) no
   justifica un data lake en la v1. MinIO + dbt-duckdb quedan para la v2.
2. **Una instancia de Postgres, tres bases** (`airflow`, `warehouse`,
   `metabase`), cada una con su usuario. Metabase lee con un usuario de solo lectura.
3. **Full refresh en lugar de incremental.** El INDEC revisa los meses recientes;
   un incremental por fecha perdería esas correcciones. El historial de cambios lo
   guarda el snapshot de dbt.
4. **Staging como tabla, no como vista.** El Full refresh borra y recrea `raw`;
   una vista sobre `raw` bloquearía esa operación.
5. **Clave subrogada en `dim_actividades`.** Un código CLaNAE puede tener varias
   series (productos), así que el código solo no identifica una actividad.
6. **Reintentos solo donde ayudan.** `airbyte_sync` reintenta 3 veces (las fallas
   de red o de la fuente pueden ser pasajeras); las tasks de dbt y Elementary no
   reintentan (un test que falla por los datos va a seguir fallando). El sync tiene
   además un corte duro de 40 minutos.
7. **El CI reproduce producción.** Seeds con los mismos tipos que `raw`, el mismo
   rol de solo lectura y la misma versión de Python (3.12).
8. **dbt en un virtualenv aislado** dentro de la imagen de Airflow, para evitar
   conflictos de dependencias.
9. **Credenciales fuera del repo.** Todo vive en `.env` (ignorado por git);
   `profiles.yml` lee con `env_var()`.
10. **Monorepo.** Un cambio que toca conector, modelo y DAG va en un solo PR.

---

## Problemas encontrados y cómo se resolvieron

| # | Síntoma | Causa | Solución | Lección |
| --- | --- | --- | --- | --- |
| 1 | Publicar el conector en Airbyte: `internalServerError` | El `cron` de Airbyte recibía `403` de Docker Hub y nunca registró la imagen para la versión 7 del manifiesto | Diagnóstico con logs de `kubectl`; registro manual de la versión en `declarative_manifest_image_version` | Ante un error genérico, ir a los logs del componente: el mensaje real estaba dos capas más abajo |
| 2 | Check del destination: `password is an empty string` | El campo de contraseña quedó vacío al guardar | Volver a cargar la contraseña | Los campos secretos se ocultan al editar y pueden guardarse vacíos |
| 3 | Airbyte cargó 41.667 filas, pero el cliente SQL no mostraba ninguna tabla | Estaba conectado a la base `postgres`, no a `warehouse` | Corregir la base en la conexión; verificar con `select current_database()` | Confirmar dónde estás conectado antes de buscar datos |
| 4 | dbt: `column "codigo_clanae_2004" does not exist` | Airbyte respetó las mayúsculas y Postgres pasa a minúsculas lo que no va entre comillas | `"codigo_CLaNAE_2004" as codigo_clanae` en staging | Normalizar nombres en la primera capa |
| 5 | Falla `unique` en `dim_actividades` | El código `23200` tiene cuatro productos (asfaltos, fueloil, gasoil, naftas) | Clave subrogada = código + descripción | Los tests atrapan supuestos falsos sobre los datos antes de que lleguen al dashboard |
| 6 | Airflow: `Request URL is missing an 'http://' protocol` | La conexión a Airbyte en formato URI dejaba el host sin protocolo | Definir la conexión en formato JSON | Probar las credenciales con `curl` antes de cargarlas |
| 7 | Sync: `cannot drop table ... because other objects depend on it` | Vistas de dbt leyendo de una tabla que el Full refresh reemplaza | Staging materializado como tabla | La materialización depende de cómo carga la capa anterior |
| 8 | El Graph de Airflow mostraba ~30 tasks extra | Cosmos incluía los modelos internos de Elementary | `RenderConfig(exclude=["package:elementary"])` | Los paquetes de dbt son parte del proyecto para las herramientas que lo leen |
| 9 | `409: A sync is already running`, en todos los reintentos | Un timeout del lado de Airflow al crear el job: Airbyte sí lo creó, quedó huérfano y bloqueó los siguientes | Cancelar el job colgado; más reintentos con mayor espera; `execution_timeout` en la task | Un timeout del cliente no garantiza que la operación no se haya ejecutado en el servidor |
| 10 | Syncs colgados y `504 Gateway timeout` incluso con `limit=1` | Caída de la API del INDEC (en beta) | Pausar el DAG y esperar | Como `airbyte_sync` falló, dbt no corrió: los marts siguieron con los últimos datos buenos en lugar de datos rotos |
| 11 | Con la API ya funcionando, el `409` seguía en cada intento | El proceso de la connection en Temporal (el motor de workflows interno de Airbyte) quedó trabado en "sincronizando". Ni cancelar por API, ni reiniciar los pods, ni marcar el job `cancelled` en la base lo destrabó | Recrear la connection (los datos de `raw` se conservan) y actualizar el `connection_id` del DAG | El estado real no siempre está donde parece: la tabla `jobs` era solo un registro; la decisión la tomaba Temporal |
| 12 | Con la connection nueva, Airflow recibía `400 Bad Request` (el Sync now desde Airbyte andaba) | El UUID copiado en el DAG tenía un carácter de más | Corregir el `connection_id` | `409` = conflicto de estado; `400` = pedido mal formado. Que el recurso funcione desde otro lado acota el problema a la llamada |
| 13 | El dashboard de cAdvisor en Grafana no muestra datos | Docker Desktop corre los contenedores en una máquina virtual: cAdvisor no ve sus carpetas reales, ni siquiera con el socket de Docker montado | Se quitó cAdvisor del stack (además corría `privileged` y con el socket de Docker); CPU y memoria por contenedor con `docker stats` | No todas las herramientas se comportan igual en Mac que en Linux |
| 14 | Un test forzado (`select 1`) no hizo fallar el DAG | Cosmos corre cada test junto con su modelo; un test sin `ref()` no queda asociado a ninguno y no se ejecuta | El test referencia el modelo: `select * from {{ ref('fct_ipi_manufacturero') }}` | La herramienta que orquesta decide qué se corre: un test que existe no es un test que se ejecuta |
| 15 | La alerta de un test fallido iba a tardar más de una hora | Los 3 reintentos del DAG con backoff aplicaban también a las tasks de dbt | `operator_args={"retries": 0}` en el `DbtTaskGroup` | Reintentar sirve para fallas transitorias, no para datos incorrectos |
| 16 | `elementary_monitor` falla con `No such option '--orchestrator'` | Se usaron opciones de `edr monitor` que no existen en la versión instalada (0.26.1) | Volver al comando anterior y `retries=0` en la task | Antes de agregar opciones a un CLI, verificarlas con `--help` en la versión instalada |
| 17 | El primer CI falló en los tres jobs | Imports desordenados (ruff `I001`), archivo de tests vacío y con un nombre que pytest no reconoce (`tests_` en lugar de `test_`), y dos claves de YAML en la misma línea | `ruff check --fix`, renombrar a `test_dags.py` con sus tests, separar las líneas de `sources.yml` | Correr localmente lo mismo que corre el CI (`ruff`, `sqlfluff`, `dbt parse`) antes de pushear |
| 18 | En CI: `function to_date(integer, unknown) does not exist` | dbt dedujo los tipos del CSV del seed y cargó `periodo` como número, mientras que en producción es texto | `+column_types` en el seed, con los mismos tipos que la tabla de `raw` | Los datos de prueba tienen que respetar el contrato de la fuente |
| 19 | En CI, el test de DAGs falla: `no such table: variable` | El contenedor del CI no tiene base de metadatos de Airflow, y Cosmos usa Variables de Airflow como caché | `airflow db migrate` antes de los tests y `AIRFLOW__COSMOS__ENABLE_CACHE=False` | Un test que carga código de Airflow necesita un mínimo de Airflow funcionando |
| 20 | En CI: `role "metabase_reader" does not exist` | Los marts otorgan lectura a un rol que existe en el Postgres local pero no en el del CI | Paso en el CI (y el CD) que crea el rol antes de `dbt build` | El CI tiene que reproducir los supuestos de producción: usuarios, schemas y tipos, no solo el código |
| 21 | La protección de `main` se crea pero no se aplica | En el plan gratuito de GitHub, los rulesets (y GitHub Pages) no funcionan en repositorios privados | Hacer público el repo, después de verificar que el historial de git no tuviera secretos | Antes de publicar un repo, revisar todo el historial, no solo el estado actual |
| 22 | `pre-commit` falla al instalar SQLFluff: `requires a different Python: 3.9.6 not in '>=3.10'` | El entorno virtual se creó con el Python 3.9 que trae macOS | Python 3.12 con Homebrew, recrear el `.venv` y fijar `default_language_version` | Fijar la versión de Python del entorno local, igual que el CI fija la suya |

---

## Estado

- [x] Infraestructura base con Docker Compose
- [x] Conector del INDEC en Airbyte (IPI manufacturero)
- [x] Modelos dbt: staging, snapshot, `fct_ipi_manufacturero`, `dim_actividades`
- [x] DAG diario en Airflow con Cosmos, reintentos y timeout
- [x] Backfill e idempotencia verificados
- [x] Recuperación ante caída de la fuente (problemas 10 y 11)
- [x] Dashboard en Metabase
- [x] Alertas a Slack (Airflow + Elementary)
- [x] Monitoreo con Prometheus + Grafana (sin cAdvisor en Mac)
- [x] CI/CD con GitHub Actions, pre-commit y `main` protegida
- [ ] v2: lakehouse con MinIO + dbt-duckdb
- [ ] Más endpoints de la API del INDEC

---

Datos: INDEC. Proyecto open source con fines de aprendizaje.

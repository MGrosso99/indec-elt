with origen as (
    select * from {{ source('indec', 'ipi_manufacturero') }}
)

select
    periodo,
    to_date(periodo, 'YYYYMM')      as fecha,
    cast(anio as integer)           as año,
    cast(mes as integer)            as mes,
    indicador,
    cuadro_web,
    "codigo_CLaNAE_2004"            as codigo_clanae,
    descripcion,
    serie,
    tipo_de_indicador,
    unidad_de_medida,
    cast(valor as numeric)          as valor,
    _airbyte_extracted_at           as cargado_en
from origen
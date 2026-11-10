select
    {{ dbt_utils.generate_surrogate_key(['codigo_clanae', 'descripcion']) }} as actividad_id,
    fecha,
    periodo,
    codigo_clanae,
    descripcion,
    serie,
    tipo_de_indicador,
    unidad_de_medida,
    valor
from {{ ref('stg_indec__ipi_manufacturero') }}
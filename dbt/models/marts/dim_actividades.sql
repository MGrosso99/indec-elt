with actividades as (
    select distinct
        codigo_clanae,
        descripcion
    from {{ ref('stg_indec__ipi_manufacturero') }}
),

con_conteo as (
    select
        *,
        count(*) over (partition by codigo_clanae) as series_por_codigo
    from actividades
)

select
    {{ dbt_utils.generate_surrogate_key(['codigo_clanae', 'descripcion']) }}
        as actividad_id,
    codigo_clanae,
    descripcion,
    case
        when codigo_clanae ~ '^[A-Z]$' then 'Sección'
        when codigo_clanae !~ '^[0-9]+$' then 'Agregado'
        when series_por_codigo > 1 then 'Producto'
        when length(codigo_clanae) = 2 then 'División'
        when length(codigo_clanae) = 3 then 'Grupo'
        when length(codigo_clanae) = 4 then 'Clase'
        when length(codigo_clanae) = 5 then 'Subclase'
        else 'Otro'
    end as nivel,
    case
        when codigo_clanae ~ '^[0-9]{2,}$' then left(codigo_clanae, 2)
    end as codigo_division
from con_conteo

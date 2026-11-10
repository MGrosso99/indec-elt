{% snapshot snp_indec__ipi_manufacturero %}
{{ config(
    target_schema='snapshots',
    unique_key=['periodo', 'indicador', 'cuadro_web', 'codigo_clanae',
                'descripcion', 'serie', 'tipo_de_indicador'],
    strategy='check',
    check_cols=['valor']
) }}
select * from {{ ref('stg_indec__ipi_manufacturero') }}
{% endsnapshot %}
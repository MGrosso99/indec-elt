with ultimo as (
    select max(fecha) as fecha from prod_marts.fct_ipi_manufacturero
)
select d.descripcion as rama, f.valor as variacion_interanual
from prod_marts.fct_ipi_manufacturero f
join prod_marts.dim_actividades d using (actividad_id)
join ultimo u on f.fecha = u.fecha
where d.nivel = 'División'
  and f.serie = 'Serie original'
  and f.tipo_de_indicador = 'Variación interanual'
order by f.valor desc;
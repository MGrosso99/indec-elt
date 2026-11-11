select f.fecha, f.valor
from prod_marts.fct_ipi_manufacturero f
join prod_marts.dim_actividades d using (actividad_id)
where d.nivel = 'Sección'
  and f.serie = 'Serie original'
  and f.tipo_de_indicador = 'Variación interanual'
order by f.fecha;
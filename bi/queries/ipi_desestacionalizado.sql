select f.fecha, f.valor
from prod_marts.fct_ipi_manufacturero f
join prod_marts.dim_actividades d using (actividad_id)
where d.nivel = 'Sección'
  and f.serie = 'Serie desestacionalizada'
  and f.tipo_de_indicador = 'Índice'
order by f.fecha;
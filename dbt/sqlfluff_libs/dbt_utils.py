# Solo para el lint de SQLFluff: imita las macros de dbt_utils que usamos.
def generate_surrogate_key(columns):
    return "md5(" + " || ".join(columns) + ")"
# Módulo 9 · Ejercicio 1
## Micro-partitions, orden físico y pruning: diagnosticar cuánto lee realmente una consulta

### Contexto

RetailNova dispone de una tabla de ventas con diez millones de filas. Los informes suelen filtrar por fecha, pero la tabla se cargó siguiendo el orden de llegada de los eventos, no el orden cronológico.

El equipo ha observado que una consulta que recupera únicamente siete días puede terminar leyendo gran parte de la tabla. Antes de crear una clustering key, activar un servicio adicional o aumentar el warehouse, debes demostrar:

1. Cómo influye el orden natural de carga en las micro-partitions.
2. Cuántas particiones se leen y cuántas se descartan.
3. Qué diferencia existe entre un predicado que puede aplicarse directamente a una columna y otro encapsulado en una expresión que dificulta el pushdown.
4. Cómo utilizar Query History y Query Profile para justificar una optimización.

El flujo del experimento será:

```text
VENTAS_RENDIMIENTO
        │
        ├── Zero-Copy Clone
        │      VENTAS_MP_DESORDENADAS
        │
        └── CTAS ordenado por fecha
               VENTAS_MP_ORDENADAS

Misma consulta selectiva
        ↓
Query History + Query Profile
        ↓
Comparación de pruning
```

---

## Objetivos

Al terminar el ejercicio deberás ser capaz de:

1. Explicar qué es una micro-partition.
2. Relacionar el orden de carga con los rangos `MIN/MAX` almacenados en sus metadatos.
3. Diferenciar una copia Zero-Copy Clone de una copia física mediante CTAS.
4. Crear una tabla con un orden natural favorable a las consultas por fecha.
5. Utilizar `SYSTEM$CLUSTERING_INFORMATION` aunque la tabla no tenga una clustering key.
6. Desactivar la result cache durante un benchmark.
7. Ejecutar pruebas con la caché local del warehouse fría.
8. Comparar `PARTITIONS_SCANNED` y `PARTITIONS_TOTAL`.
9. Calcular un porcentaje aproximado de pruning.
10. Interpretar bytes escaneados, tiempo de ejecución y filas producidas.
11. Abrir Query Profile y localizar el operador `TableScan`.
12. Reconocer cuándo una expresión sobre la columna puede dificultar el pushdown.
13. Diferenciar una mejora de organización física de un cambio de tamaño del warehouse.
14. Elaborar una recomendación antes de activar Automatic Clustering.

---

## Prerrequisito

El ejercicio reutiliza la tabla creada en el módulo anterior:

```text
DB_CURSO.PERFORMANCE.VENTAS_RENDIMIENTO
```

Debe contener:

```text
10.000.000 filas
fechas entre 2025-01-01 y 2025-12-31
```

La solución incluye una sección de recuperación para crearla si no existe.

---

## Convenciones

| Objeto | Nombre |
|---|---|
| Base de datos | `DB_CURSO` |
| Esquema | `PERFORMANCE` |
| Warehouse | `WH_M09_PRUNING` |
| Tabla original | `VENTAS_RENDIMIENTO` |
| Clone desordenado | `VENTAS_MP_DESORDENADAS` |
| Copia ordenada | `VENTAS_MP_ORDENADAS` |
| UDF de control | `FECHA_EN_INTERVALO_SEGURO` |
| Fichero SQL del workspace | `M09_E01_MICROPARTITIONS_PRUNING.sql` |

---

## Condiciones del benchmark

El warehouse debe utilizar:

```text
WAREHOUSE_TYPE = STANDARD
WAREHOUSE_SIZE = XSMALL
GENERATION = 1
MIN_CLUSTER_COUNT = 1
MAX_CLUSTER_COUNT = 1
AUTO_SUSPEND = 60
AUTO_RESUME = TRUE
ENABLE_QUERY_ACCELERATION = FALSE
```

Se utiliza Gen1 para evitar que Snowflake Optima Metadata introduzca una capa adicional de optimización automática en el experimento.

Durante las consultas comparativas:

```text
USE_CACHED_RESULT = FALSE
```

Antes de cada ejecución se suspenderá el warehouse para retirar su caché local.

---

## Consulta de referencia

La consulta de referencia debe ser idéntica en ambas tablas:

```sql
SELECT
    region,
    canal,
    COUNT(*) AS num_ventas,
    SUM(importe - descuento)::NUMBER(20,2) AS importe_neto
FROM <tabla>
WHERE fecha >= '2025-06-01'::DATE
  AND fecha <  '2025-06-08'::DATE
  AND estado = 'COMPLETADA'
GROUP BY region, canal
ORDER BY region, canal;
```

Resultado lógico esperado para el conjunto proporcionado:

```text
15 grupos
150.684 ventas completadas
importe neto agregado = 74.216.999,82
```

Los resultados de las dos tablas deben ser idénticos. Lo que debe cambiar es la cantidad de datos leídos.

---

## Tags de las pruebas

| Prueba | Query tag |
|---|---|
| Tabla desordenada | `M09_E01_DESORDENADA` |
| Tabla ordenada | `M09_E01_ORDENADA` |
| Funciones de fecha | `M09_E01_FUNCIONES_FECHA` |
| UDF segura de control | `M09_E01_UDF_SEGURA` |

---

## Tareas

### Tarea 1. Preparar Workspaces

En **Workspaces**, crea:

```text
M09_E01_MICROPARTITIONS_PRUNING.sql
```

Configura explícitamente:

- Rol.
- Base de datos.
- Esquema.
- Query tag de preparación.

Crea el warehouse `WH_M09_PRUNING` con la configuración indicada.

Comprueba:

- Tamaño.
- Generación.
- Número de clústeres.
- Auto-suspend.
- Auto-resume.
- QAS desactivado.
- Estado inicial suspendido.

> Utiliza Workspaces. No busques el antiguo menú Worksheets.

---

### Tarea 2. Comprobar la tabla de origen

Verifica que `VENTAS_RENDIMIENTO` existe y contiene diez millones de filas.

Comprueba:

- Número de filas.
- Fecha mínima.
- Fecha máxima.
- Número de regiones.
- Número de canales.
- Estados existentes.

No recrees la tabla si ya está disponible.

---

### Tarea 3. Crear una copia Zero-Copy Clone

Crea:

```text
DB_CURSO.PERFORMANCE.VENTAS_MP_DESORDENADAS
```

mediante `CLONE`.

La copia debe:

- Compartir inicialmente las micro-partitions de la tabla fuente.
- Conservar la organización física original.
- No copiar físicamente los diez millones de filas durante la creación.

Comprueba que contiene el mismo número de filas y que no tiene una clustering key explícita.

---

### Tarea 4. Crear una copia físicamente ordenada

Crea:

```text
DB_CURSO.PERFORMANCE.VENTAS_MP_ORDENADAS
```

mediante CTAS:

```text
SELECT ... ORDER BY fecha, id_venta
```

La operación debe crear nuevas micro-partitions con una organización natural más favorable para filtros temporales.

No definas todavía:

```text
CLUSTER BY
```

El objetivo es comparar dos organizaciones naturales antes de introducir Automatic Clustering.

Comprueba que:

- Contiene diez millones de filas.
- Tiene exactamente las mismas columnas.
- No tiene una clustering key explícita.
- Los agregados globales coinciden con la tabla clonada.

---

### Tarea 5. Comparar la organización mediante metadatos

Utiliza:

```text
SYSTEM$CLUSTERING_INFORMATION
```

para analizar ambas tablas respecto a:

```text
(FECHA)
```

Extrae del JSON:

- `total_partition_count`
- `total_constant_partition_count`
- `average_overlaps`
- `average_depth`
- `partition_depth_histogram`
- `notes`

Interpreta:

- Menor profundidad media.
- Menor solapamiento.
- Mayor número de particiones constantes.

No esperes que ambas tablas tengan exactamente el mismo número de micro-partitions.

---

### Tarea 6. Preparar el benchmark

Configura:

```text
USE_CACHED_RESULT = FALSE
```

Comprueba el parámetro en la sesión.

Suspende el warehouse después de las consultas de preparación.

Explica:

- Por qué esta propiedad evita reutilizar el resultado persistido.
- Por qué no desactiva la caché local.
- Por qué suspender el warehouse permite aproximar una ejecución fría.

---

### Tarea 7. Ejecutar la consulta sobre la tabla desordenada

1. Suspende `WH_M09_PRUNING`.
2. Establece:

```text
QUERY_TAG = M09_E01_DESORDENADA
```

3. Ejecuta la consulta de referencia sobre `VENTAS_MP_DESORDENADAS`.
4. Conserva el Query ID.
5. No repitas la consulta antes de analizarla.

Comprueba que devuelve quince grupos.

---

### Tarea 8. Ejecutar la misma consulta sobre la tabla ordenada

1. Vuelve a suspender el warehouse.
2. Establece:

```text
QUERY_TAG = M09_E01_ORDENADA
```

3. Ejecuta exactamente la misma consulta sobre `VENTAS_MP_ORDENADAS`.
4. Conserva el Query ID.

Los resultados de negocio deben coincidir con la consulta anterior.

---

### Tarea 9. Analizar Query History

Crea un informe comparativo con:

- Query ID.
- Query tag.
- Warehouse.
- Tiempo total.
- Tiempo de compilación.
- Tiempo de ejecución.
- Tiempo de aprovisionamiento.
- Bytes escaneados.
- Particiones escaneadas.
- Particiones totales.
- Porcentaje aproximado de particiones leídas.
- Porcentaje aproximado de pruning.
- Porcentaje leído desde la caché local.
- Filas producidas.

Calcula:

```text
porcentaje leído
= partitions_scanned / partitions_total × 100

porcentaje podado
= 100 - porcentaje leído
```

La tabla ordenada debería leer una fracción menor de sus particiones para el rango de siete días.

---

### Tarea 10. Inspeccionar Query Profile

Abre Query Profile para las dos consultas.

En cada una:

1. Localiza el operador `TableScan`.
2. Revisa `Partitions scanned`.
3. Revisa `Partitions total`.
4. Revisa bytes escaneados.
5. Identifica el porcentaje de tiempo del operador.
6. Comprueba si existe un operador `Filter` separado.
7. Compara el tamaño de la entrada y la salida del scan.

Documenta cuál es el operador dominante y por qué.

---

### Tarea 11. Comparar dos formulaciones del predicado

Sobre `VENTAS_MP_ORDENADAS`, ejecuta una tercera consulta equivalente usando:

```sql
YEAR(fecha) = 2025
AND MONTH(fecha) = 6
AND DAYOFMONTH(fecha) BETWEEN 1 AND 7
```

Utiliza el tag:

```text
M09_E01_FUNCIONES_FECHA
```

Antes de ejecutar:

- Suspende el warehouse.
- Mantén desactivada la result cache.

Compara las particiones con el predicado de rango.

No se exige una diferencia fija: el optimizador puede transformar determinadas expresiones. La conclusión debe basarse en el plan ejecutado.

---

### Tarea 12. Crear un control deliberadamente opaco

Crea una **secure SQL UDF** llamada:

```text
FECHA_EN_INTERVALO_SEGURO
```

que reciba:

- Una fecha.
- Un inicio inclusivo.
- Un fin exclusivo.

y devuelva un booleano.

Utilízala para ejecutar la misma consulta de siete días sobre la tabla ordenada.

Tag:

```text
M09_E01_UDF_SEGURA
```

El objetivo es demostrar que impedir determinadas optimizaciones de pushdown puede obligar a leer más datos.

> La UDF segura se utiliza únicamente como control experimental. No debe crearse una UDF segura solo por comodidad, porque Snowflake omite ciertas optimizaciones para proteger la visibilidad de los datos.

---

### Tarea 13. Comparar las cuatro pruebas

Construye una tabla de análisis:

| Tag | Tabla | Formulación | Particiones leídas | Particiones totales | Pruning | Tiempo ejecución |
|---|---|---|---:|---:|---:|---:|
| `DESORDENADA` | Desordenada | Rango directo |  |  |  |  |
| `ORDENADA` | Ordenada | Rango directo |  |  |  |  |
| `FUNCIONES_FECHA` | Ordenada | `YEAR/MONTH/DAY` |  |  |  |  |
| `UDF_SEGURA` | Ordenada | Función opaca |  |  |  |  |

Responde:

1. ¿Qué factor tuvo mayor impacto: la organización física o la sintaxis?
2. ¿El tiempo de ejecución siguió exactamente la proporción de particiones?
3. ¿Qué peso tuvo el aprovisionamiento?
4. ¿Hubo lectura desde la caché local?
5. ¿La consulta con funciones fue reescrita por el optimizador?
6. ¿Por qué la UDF segura puede perjudicar el pruning?

---

### Tarea 14. Consultar el historial de pruning diferido

Prepara consultas para:

```text
SNOWFLAKE.ACCOUNT_USAGE.TABLE_QUERY_PRUNING_HISTORY
SNOWFLAKE.ACCOUNT_USAGE.COLUMN_QUERY_PRUNING_HISTORY
```

Filtra por:

- Base de datos.
- Esquema.
- Tablas del ejercicio.
- Warehouse.
- Intervalo temporal.

No es obligatorio que los datos aparezcan inmediatamente. Estas vistas tienen latencia.

Explica qué aportan que no aparece directamente en una sola fila de Query History.

---

### Tarea 15. Elaborar una recomendación

Redacta una conclusión para RetailNova.

Debe responder:

1. ¿La tabla original está bien organizada para filtros por fecha?
2. ¿Una reconstrucción ordenada mejora el pruning?
3. ¿Sería necesario definir una clustering key?
4. ¿Con qué frecuencia se consulta y se modifica la tabla?
5. ¿La mejora compensa el coste de mantenimiento?
6. ¿Tiene sentido aumentar el warehouse antes de corregir el scan?
7. ¿Qué métricas usarías para justificar la decisión?

No actives Automatic Clustering en este ejercicio. Se estudiará por separado.

---

### Tarea 16. Restaurar la sesión y detener recursos

Al finalizar:

- Elimina la UDF segura.
- Restaura `USE_CACHED_RESULT`.
- Suspende `WH_M09_PRUNING`.
- Conserva las dos tablas para el siguiente ejercicio.

---

## Resultados no completamente deterministas

Los valores exactos pueden variar por:

- Número de micro-partitions creadas durante el CTAS.
- Compresión.
- Optimizaciones del motor.
- Región.
- Aprovisionamiento.
- Variación normal de ejecución.

Se considera correcto cuando:

- Las tablas contienen los mismos datos.
- La tabla ordenada muestra mejor organización respecto a `FECHA`.
- El scan de siete días lee una proporción menor de particiones en la tabla ordenada.
- Query Profile permite explicar la diferencia.

---

## Criterios de finalización

El ejercicio se considera completado cuando puedas demostrar que:

- Existe un clone que conserva la organización original.
- Existe una copia física ordenada.
- Ambas contienen diez millones de filas.
- Se comparó el clustering natural respecto a `FECHA`.
- Se ejecutaron cuatro consultas etiquetadas.
- La result cache estuvo desactivada.
- Las ejecuciones comenzaron con la caché local fría.
- Query History muestra particiones y bytes.
- Query Profile muestra el `TableScan`.
- Puedes explicar el efecto del orden físico y del pushdown.
- El warehouse queda suspendido.

---

## Preguntas de reflexión

1. ¿Por qué Snowflake no necesita que el usuario cree particiones manuales?
2. ¿Qué metadatos permiten descartar micro-partitions?
3. ¿Por qué una tabla ordenada por fecha puede podar mejor?
4. ¿Por qué un clone conserva la organización física de la fuente?
5. ¿Por qué un CTAS ordenado consume más que un clone?
6. ¿Qué diferencia existe entre clustering natural y clustering key?
7. ¿Por qué un buen pruning puede ser más importante que duplicar el tamaño del warehouse?
8. ¿Por qué no basta con medir únicamente el tiempo total?
9. ¿Qué indica un `Filter` que elimina muchas filas después del `TableScan`?
10. ¿Cuándo no recomendarías clustering aunque mejore una consulta?

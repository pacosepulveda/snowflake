# Módulo 9 · Ejercicio 1

## Solución guiada: micro-partitions, orden físico y pruning


---

## 1. Qué vamos a demostrar

Snowflake crea automáticamente micro-partitions utilizando el orden de los datos cuando se insertan o cargan.

Cada micro-partition mantiene metadatos, entre ellos rangos de valores. Cuando un filtro coincide con pocos rangos, Snowflake puede descartar particiones sin leerlas.

El experimento compara:

```text
Tabla A
Fechas intercaladas entre micro-partitions

Tabla B
Filas escritas en orden de fecha
```

La consulta de negocio será la misma.

---

## 2. Preparar Workspaces

Crea:

```text
M09_E01_MICROPARTITIONS_PRUNING.sql
```

Ejecuta:

```sql
USE ROLE SYSADMIN;

CREATE DATABASE IF NOT EXISTS DB_CURSO;
CREATE SCHEMA IF NOT EXISTS DB_CURSO.PERFORMANCE;

USE DATABASE DB_CURSO;
USE SCHEMA PERFORMANCE;

ALTER SESSION SET QUERY_TAG = 'M09_E01_PREPARACION';
```

---

## 3. Crear el warehouse del laboratorio

```sql
CREATE OR REPLACE WAREHOUSE WH_M09_PRUNING
    WAREHOUSE_TYPE = STANDARD
    WAREHOUSE_SIZE = XSMALL
    GENERATION = '1'
    MIN_CLUSTER_COUNT = 1
    MAX_CLUSTER_COUNT = 1
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE
    ENABLE_QUERY_ACCELERATION = FALSE
    COMMENT = 'M09 laboratorio de micro-partitions y pruning';
```

Comprueba:

```sql
SHOW WAREHOUSES LIKE 'WH_M09_PRUNING';
```

```sql
DESC WAREHOUSE WH_M09_PRUNING;
```

### Por qué utilizamos Gen1

Snowflake Optima Metadata está disponible en warehouses Gen2 y puede crear metadatos adicionales cuando detecta patrones de filtros poco eficientes, por ejemplo el uso frecuente de `UPPER` o `LOWER`.

En este laboratorio queremos observar el comportamiento básico de:

```text
orden físico
+
metadatos de micro-partitions
+
predicado
```

Por eso fijamos:

```sql
GENERATION = '1'
```

También desactivamos QAS para que no intervenga cómputo serverless adicional.

---

## 4. Comprobar la tabla de origen

```sql
SHOW TABLES LIKE 'VENTAS_RENDIMIENTO'
IN SCHEMA DB_CURSO.PERFORMANCE;
```

Si existe:

```sql
USE WAREHOUSE WH_M09_PRUNING;
```

```sql
SELECT
    COUNT(*) AS filas,
    MIN(fecha) AS fecha_minima,
    MAX(fecha) AS fecha_maxima,
    COUNT(DISTINCT region) AS regiones,
    COUNT(DISTINCT canal) AS canales,
    COUNT(DISTINCT estado) AS estados
FROM DB_CURSO.PERFORMANCE.VENTAS_RENDIMIENTO;
```

Resultado esperado:

| FILAS | FECHA_MINIMA | FECHA_MAXIMA | REGIONES | CANALES | ESTADOS |
|---:|---|---|---:|---:|---:|
| 10000000 | 2025-01-01 | 2025-12-31 | 5 | 3 | 3 |

---

## 5. Recuperación si la tabla no existe

Ejecuta esta sección únicamente si falta el objeto.

```sql
USE WAREHOUSE WH_M09_PRUNING;
```

```sql
CREATE OR REPLACE TRANSIENT TABLE
    DB_CURSO.PERFORMANCE.VENTAS_RENDIMIENTO
AS
WITH base AS (
    SELECT SEQ8() AS n
    FROM TABLE(
        GENERATOR(ROWCOUNT => 10000000)
    )
)
SELECT
    (n + 1)::NUMBER(18,0)
        AS id_venta,

    DATEADD(
        'day',
        MOD(n, 365),
        '2025-01-01'::DATE
    )::DATE
        AS fecha,

    CASE MOD(n, 5)
        WHEN 0 THEN 'NORTE'
        WHEN 1 THEN 'SUR'
        WHEN 2 THEN 'ESTE'
        WHEN 3 THEN 'OESTE'
        ELSE 'CENTRO'
    END::VARCHAR(10)
        AS region,

    CASE MOD(n, 3)
        WHEN 0 THEN 'WEB'
        WHEN 1 THEN 'TIENDA'
        ELSE 'MARKETPLACE'
    END::VARCHAR(20)
        AS canal,

    (MOD(n * 13, 500000) + 1)::NUMBER(18,0)
        AS id_cliente,

    (MOD(n * 17, 50000) + 1)::NUMBER(18,0)
        AS id_producto,

    (
        5 + MOD(n * 97, 100000) / 100
    )::NUMBER(12,2)
        AS importe,

    (
        MOD(n * 19, 2500) / 100
    )::NUMBER(12,2)
        AS descuento,

    CASE MOD(n, 10)
        WHEN 0 THEN 'CANCELADA'
        WHEN 1 THEN 'PENDIENTE'
        ELSE 'COMPLETADA'
    END::VARCHAR(20)
        AS estado

FROM base;
```

La fecha se calcula mediante:

```sql
MOD(n, 365)
```

Por tanto, fechas sucesivas se repiten de forma cíclica a lo largo de la carga. Esta organización será poco favorable para un filtro temporal estrecho.

---

## 6. Crear el clone desordenado

```sql
CREATE OR REPLACE TRANSIENT TABLE
    DB_CURSO.PERFORMANCE.VENTAS_MP_DESORDENADAS

CLONE
    DB_CURSO.PERFORMANCE.VENTAS_RENDIMIENTO;
```

### Qué hace CLONE

La creación es rápida porque:

- No vuelve a insertar las diez millones de filas.
- Comparte inicialmente las micro-partitions de la fuente.
- Mantiene la organización física existente.
- Solo empieza a generar almacenamiento independiente cuando alguno de los objetos cambia.

Comprueba:

```sql
SELECT COUNT(*) AS filas
FROM DB_CURSO.PERFORMANCE.VENTAS_MP_DESORDENADAS;
```

Resultado:

```text
10000000
```

---

## 7. Crear la copia ordenada

```sql
CREATE OR REPLACE TRANSIENT TABLE
    DB_CURSO.PERFORMANCE.VENTAS_MP_ORDENADAS
AS
SELECT
    id_venta,
    fecha,
    region,
    canal,
    id_cliente,
    id_producto,
    importe,
    descuento,
    estado
FROM DB_CURSO.PERFORMANCE.VENTAS_MP_DESORDENADAS
ORDER BY
    fecha,
    id_venta;
```

### Qué diferencia existe

Este CTAS:

1. Lee todas las filas.
2. Las ordena.
3. Escribe nuevas micro-partitions.
4. Agrupa fechas próximas en un número menor de particiones.

No se ha definido una clustering key. El orden es natural y corresponde al momento de creación.

Nuevas inserciones desordenadas podrían degradarlo con el tiempo.

### Comprobar la igualdad lógica

```sql
SELECT
    'DESORDENADA' AS tabla,
    COUNT(*) AS filas,
    SUM(importe) AS importe,
    SUM(descuento) AS descuento
FROM DB_CURSO.PERFORMANCE.VENTAS_MP_DESORDENADAS

UNION ALL

SELECT
    'ORDENADA',
    COUNT(*),
    SUM(importe),
    SUM(descuento)
FROM DB_CURSO.PERFORMANCE.VENTAS_MP_ORDENADAS;
```

Las métricas deben coincidir.

### Confirmar que no existe clustering key

```sql
SHOW TABLES LIKE 'VENTAS_MP_%'
IN SCHEMA DB_CURSO.PERFORMANCE;
```

Revisa la columna relativa a clustering. No debe existir una clave explícita.

---

## 8. Analizar clustering natural

Ejecuta:

```sql
WITH info AS (
    SELECT
        'DESORDENADA' AS tabla,

        PARSE_JSON(
            SYSTEM$CLUSTERING_INFORMATION(
                'DB_CURSO.PERFORMANCE.VENTAS_MP_DESORDENADAS',
                '(FECHA)'
            )
        ) AS j

    UNION ALL

    SELECT
        'ORDENADA',

        PARSE_JSON(
            SYSTEM$CLUSTERING_INFORMATION(
                'DB_CURSO.PERFORMANCE.VENTAS_MP_ORDENADAS',
                '(FECHA)'
            )
        )
)

SELECT
    tabla,

    j:cluster_by_keys::VARCHAR
        AS expresion_analizada,

    j:total_partition_count::NUMBER
        AS total_particiones,

    j:total_constant_partition_count::NUMBER
        AS particiones_constantes,

    j:average_overlaps::FLOAT
        AS solapamiento_medio,

    j:average_depth::FLOAT
        AS profundidad_media,

    j:notes::VARCHAR
        AS notas,

    j:partition_depth_histogram
        AS histograma

FROM info

ORDER BY tabla;
```

### Interpretación

#### total_partition_count

Número de micro-partitions activas de la tabla.

Las dos tablas pueden tener un número ligeramente distinto porque la compresión y la reescritura no tienen que generar exactamente la misma distribución.

#### total_constant_partition_count

Particiones que ya no se beneficiarían significativamente de más reclustering respecto a la expresión analizada.

Un número elevado suele ser favorable.

#### average_overlaps

Número medio de particiones cuyos rangos de fecha se solapan.

En la tabla cíclica muchas particiones contienen rangos amplios de fechas, por lo que el solapamiento puede ser alto.

#### average_depth

Profundidad media del solapamiento.

Cuanto menor sea, mejor organizada está la tabla respecto a la columna.

La tabla ordenada debería mostrar una profundidad claramente inferior.

---

## 9. Validar el resultado lógico esperado

Antes del benchmark, comprueba el rango:

```sql
SELECT
    COUNT(*) AS ventas_completadas,
    SUM(importe - descuento)::NUMBER(20,2)
        AS importe_neto
FROM DB_CURSO.PERFORMANCE.VENTAS_MP_ORDENADAS
WHERE fecha >= '2025-06-01'::DATE
  AND fecha <  '2025-06-08'::DATE
  AND estado = 'COMPLETADA';
```

Resultado esperado:

| VENTAS_COMPLETADAS | IMPORTE_NETO |
|---:|---:|
| 150684 | 74216999.82 |

Esta consulta ha calentado el warehouse. Suspéndelo antes de las pruebas:

```sql
ALTER WAREHOUSE WH_M09_PRUNING SUSPEND;
```

---

## 10. Desactivar la result cache

```sql
ALTER SESSION SET USE_CACHED_RESULT = FALSE;
```

Comprueba:

```sql
SHOW PARAMETERS LIKE 'USE_CACHED_RESULT'
IN SESSION;
```

Debe aparecer:

```text
FALSE
```

### Qué se ha desactivado

Snowflake no reutilizará un resultado persistido anterior.

### Qué sigue activo

La caché SSD local del warehouse continúa funcionando.

Para aproximar una ejecución fría:

```sql
ALTER WAREHOUSE WH_M09_PRUNING SUSPEND;
```

Suspender destruye el clúster y su caché local.

---

## 11. Consulta sobre la tabla desordenada

Suspende:

```sql
ALTER WAREHOUSE WH_M09_PRUNING SUSPEND;
```

Tag:

```sql
ALTER SESSION SET QUERY_TAG = 'M09_E01_DESORDENADA';
```

Selecciona el warehouse y ejecuta:

```sql
USE WAREHOUSE WH_M09_PRUNING;
```

```sql
SELECT
    region,
    canal,
    COUNT(*) AS num_ventas,
    SUM(importe - descuento)::NUMBER(20,2)
        AS importe_neto

FROM DB_CURSO.PERFORMANCE.VENTAS_MP_DESORDENADAS

WHERE fecha >= '2025-06-01'::DATE
  AND fecha <  '2025-06-08'::DATE
  AND estado = 'COMPLETADA'

GROUP BY
    region,
    canal

ORDER BY
    region,
    canal;
```

No la ejecutes una segunda vez.

---

## 12. Consulta sobre la tabla ordenada

Suspende:

```sql
ALTER WAREHOUSE WH_M09_PRUNING SUSPEND;
```

Tag:

```sql
ALTER SESSION SET QUERY_TAG = 'M09_E01_ORDENADA';
```

Ejecuta:

```sql
USE WAREHOUSE WH_M09_PRUNING;
```

```sql
SELECT
    region,
    canal,
    COUNT(*) AS num_ventas,
    SUM(importe - descuento)::NUMBER(20,2)
        AS importe_neto

FROM DB_CURSO.PERFORMANCE.VENTAS_MP_ORDENADAS

WHERE fecha >= '2025-06-01'::DATE
  AND fecha <  '2025-06-08'::DATE
  AND estado = 'COMPLETADA'

GROUP BY
    region,
    canal

ORDER BY
    region,
    canal;
```

Los quince resultados deben coincidir con la consulta anterior.

---

## 13. Crear el informe inmediato

Cambia el tag:

```sql
ALTER SESSION SET QUERY_TAG = 'M09_E01_ANALISIS';
```

Ejecuta:

```sql
SELECT
    query_id,
    query_tag,
    query_type,
    warehouse_name,
    warehouse_size,
    start_time,

    ROUND(
        total_elapsed_time / 1000,
        3
    ) AS total_segundos,

    ROUND(
        compilation_time / 1000,
        3
    ) AS compilacion_segundos,

    ROUND(
        execution_time / 1000,
        3
    ) AS ejecucion_segundos,

    ROUND(
        queued_provisioning_time / 1000,
        3
    ) AS aprovisionamiento_segundos,

    ROUND(
        bytes_scanned / POWER(1024, 2),
        2
    ) AS mb_escaneados,

    partitions_scanned,
    partitions_total,

    ROUND(
        100.0
        * partitions_scanned
        / NULLIF(partitions_total, 0),
        2
    ) AS porcentaje_particiones_leidas,

    ROUND(
        100.0
        * (partitions_total - partitions_scanned)
        / NULLIF(partitions_total, 0),
        2
    ) AS porcentaje_particiones_podadas,

    ROUND(
        COALESCE(
            percentage_scanned_from_cache,
            0
        ) * 100,
        2
    ) AS porcentaje_cache_local,

    rows_produced

FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY

WHERE warehouse_name = 'WH_M09_PRUNING'

  AND start_time >= DATEADD(
      'hour',
      -2,
      CURRENT_TIMESTAMP()
  )

  AND query_tag IN (
      'M09_E01_DESORDENADA',
      'M09_E01_ORDENADA'
  )

  AND query_type = 'SELECT'

  AND query_text ILIKE '%VENTAS_MP_%'

ORDER BY start_time;
```

INFORMATION_SCHEMA.QUERY_HISTORY_BY_WAREHOUSE() ofrece información reciente casi inmediatamente, pero tiene menos columnas y limita el historial a los últimos siete días.

SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY ofrece métricas más completas y conserva hasta 365 días, pero puede tener hasta 45 minutos de latencia. Por tanto, si acabas de ejecutar las consultas del ejercicio, es posible que todavía no aparezcan.

Para consultar las particiones inmediatamente después de ejecutar cada SELECT, puedes utilizar GET_QUERY_OPERATOR_STATS():

```sql
SELECT
    query_id,
    operator_type,

    operator_attributes:table_name::VARCHAR
        AS tabla,

    operator_statistics:io:bytes_scanned::NUMBER
        AS bytes_escaneados,

    ROUND(
        operator_statistics:io:bytes_scanned::NUMBER
        / POWER(1024, 2),
        2
    ) AS mb_escaneados,

    operator_statistics:pruning:partitions_scanned::NUMBER
        AS particiones_escaneadas,

    operator_statistics:pruning:partitions_total::NUMBER
        AS particiones_totales,

    ROUND(
        100.0
        * operator_statistics:pruning:partitions_scanned::NUMBER
        / NULLIF(
            operator_statistics:pruning:partitions_total::NUMBER,
            0
        ),
        2
    ) AS porcentaje_particiones_leidas,

    ROUND(
        100.0
        * (
            operator_statistics:pruning:partitions_total::NUMBER
            - operator_statistics:pruning:partitions_scanned::NUMBER
        )
        / NULLIF(
            operator_statistics:pruning:partitions_total::NUMBER,
            0
        ),
        2
    ) AS porcentaje_particiones_podadas,

    ROUND(
        COALESCE(
            operator_statistics:io:
                percentage_scanned_from_cache::FLOAT,
            0
        ) * 100,
        2
    ) AS porcentaje_cache_local

FROM TABLE(
    GET_QUERY_OPERATOR_STATS(
        'QUERY_ID_QUE_QUIERES_ANALIZAR'
    )
)

WHERE operator_type = 'TableScan';
```

### Resultado que debes buscar

La tabla ordenada debería presentar:

- Menos particiones leídas.
- Mayor porcentaje podado.
- Menos bytes escaneados.
- Menor tiempo de scan.

El tiempo total puede no reducirse en la misma proporción porque incluye:

- Aprovisionamiento.
- Compilación.
- Coordinación.
- Agregación.
- Entrega del resultado.

---

## 14. Abrir Query Profile

Para cada Query ID:

1. Abre **Query Profile**.

```
Monitoring
└── Query History
    └── Individual Queries
        └── Seleccionar consulta
            └── Query Profile
```
2. Selecciona el operador `TableScan`.
3. Revisa:
   - Partitions scanned.
   - Partitions total.
   - Bytes scanned.
   - Rows produced.
   - Porcentaje del tiempo total.
4. Revisa si existe un operador `Filter`.
5. Compara la cardinalidad antes y después del filtro.

### Diagnóstico esperado

#### Tabla desordenada

Las fechas de cada micro-partition se solapan ampliamente.

Aunque el filtro solo solicita siete días, el metadato `MIN/MAX` de muchas particiones puede encajar con ese rango.

Snowflake debe abrir más particiones.

#### Tabla ordenada

Las fechas de una partición ocupan un rango más estrecho.

Snowflake puede descartar las particiones anteriores y posteriores al intervalo.

---

## 15. Probar funciones de fecha

Suspende:

```sql
ALTER WAREHOUSE WH_M09_PRUNING SUSPEND;
```

Tag:

```sql
ALTER SESSION SET QUERY_TAG = 'M09_E01_FUNCIONES_FECHA';
```

Ejecuta:

```sql
USE WAREHOUSE WH_M09_PRUNING;
```

```sql
SELECT
    region,
    canal,
    COUNT(*) AS num_ventas,
    SUM(importe - descuento)::NUMBER(20,2)
        AS importe_neto

FROM DB_CURSO.PERFORMANCE.VENTAS_MP_ORDENADAS

WHERE YEAR(fecha) = 2025
  AND MONTH(fecha) = 6
  AND DAYOFMONTH(fecha) BETWEEN 1 AND 7
  AND estado = 'COMPLETADA'

GROUP BY
    region,
    canal

ORDER BY
    region,
    canal;
```

### Cómo interpretarlo

La consulta es lógicamente equivalente para este conjunto.

No debes afirmar automáticamente que una función impide siempre el pruning.

Snowflake puede reescribir determinadas expresiones.

Comprueba:

- Partitions scanned.
- Si el filtro aparece dentro del `TableScan`.
- Si aparece un operador `Filter` posterior.
- Si las métricas coinciden con el rango directo.

---

## 16. Crear una secure UDF de control

```sql
CREATE OR REPLACE SECURE FUNCTION
    DB_CURSO.PERFORMANCE.FECHA_EN_INTERVALO_SEGURO(
        valor DATE,
        inicio DATE,
        fin_exclusivo DATE
    )

RETURNS BOOLEAN

LANGUAGE SQL

AS
$$
    valor >= inicio
    AND valor < fin_exclusivo
$$;
```

### Por qué es un control útil

Snowflake evita determinadas optimizaciones sobre una secure UDF para impedir que el pushdown exponga información indirectamente.

Esta propiedad puede reducir el rendimiento.

No se utiliza porque sea una buena forma de escribir el filtro, sino para crear un contraste controlado.

---

## 17. Ejecutar la consulta mediante la UDF segura

Suspende:

```sql
ALTER WAREHOUSE WH_M09_PRUNING SUSPEND;
```

Tag:

```sql
ALTER SESSION SET QUERY_TAG = 'M09_E01_UDF_SEGURA';
```

Ejecuta:

```sql
USE WAREHOUSE WH_M09_PRUNING;
```

```sql
SELECT
    region,
    canal,
    COUNT(*) AS num_ventas,
    SUM(importe - descuento)::NUMBER(20,2)
        AS importe_neto

FROM DB_CURSO.PERFORMANCE.VENTAS_MP_ORDENADAS

WHERE DB_CURSO.PERFORMANCE
        .FECHA_EN_INTERVALO_SEGURO(
            fecha,
            '2025-06-01'::DATE,
            '2025-06-08'::DATE
        )

  AND estado = 'COMPLETADA'

GROUP BY
    region,
    canal

ORDER BY
    region,
    canal;
```

El resultado de negocio debe seguir siendo el mismo.

En Query Profile, el scan puede leer muchas más particiones porque el filtro temporal no se ha podido empujar de la misma forma.

---

## 18. Informe de las cuatro pruebas

```sql
ALTER SESSION SET QUERY_TAG = 'M09_E01_ANALISIS_FINAL';
```

```sql
SELECT
    query_tag,
    query_id,
    start_time,

    CASE
        WHEN query_text ILIKE
            '%VENTAS_MP_DESORDENADAS%'
            THEN 'DESORDENADA'

        WHEN query_text ILIKE
            '%VENTAS_MP_ORDENADAS%'
            THEN 'ORDENADA'

        ELSE 'DESCONOCIDA'
    END AS tabla,

    CASE
        WHEN query_tag IN (
            'M09_E01_DESORDENADA',
            'M09_E01_ORDENADA'
        )
            THEN 'RANGO_DIRECTO'

        WHEN query_tag =
            'M09_E01_FUNCIONES_FECHA'
            THEN 'FUNCIONES_FECHA'

        WHEN query_tag =
            'M09_E01_UDF_SEGURA'
            THEN 'UDF_SEGURA'

        ELSE 'OTRA'
    END AS formulacion,

    ROUND(
        total_elapsed_time / 1000,
        3
    ) AS total_segundos,

    ROUND(
        execution_time / 1000,
        3
    ) AS ejecucion_segundos,

    ROUND(
        queued_provisioning_time / 1000,
        3
    ) AS aprovisionamiento_segundos,

    ROUND(
        bytes_scanned / POWER(1024, 2),
        2
    ) AS mb_escaneados,

    partitions_scanned,
    partitions_total,

    ROUND(
        100.0
        * partitions_scanned
        / NULLIF(partitions_total, 0),
        2
    ) AS porcentaje_leido,

    ROUND(
        100.0
        * (
            partitions_total
            - partitions_scanned
        )
        / NULLIF(partitions_total, 0),
        2
    ) AS porcentaje_podado,

    ROUND(
        COALESCE(
            percentage_scanned_from_cache,
            0
        ) * 100,
        2
    ) AS porcentaje_cache_local

FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY

WHERE warehouse_name = 'WH_M09_PRUNING'

  AND start_time >= DATEADD(
      'hour',
      -3,
      CURRENT_TIMESTAMP()
  )

  AND query_tag IN (
      'M09_E01_DESORDENADA',
      'M09_E01_ORDENADA',
      'M09_E01_FUNCIONES_FECHA',
      'M09_E01_UDF_SEGURA'
  )

  AND query_type = 'SELECT'

  AND (
      query_text ILIKE
          '%VENTAS_MP_DESORDENADAS%'

      OR query_text ILIKE
          '%VENTAS_MP_ORDENADAS%'
  )

ORDER BY start_time;
```

---

## 19. Cómo redactar la interpretación

Una conclusión razonable puede tener esta estructura:

```text
1. La tabla clonada conserva el patrón cíclico de fechas.
2. Sus micro-partitions presentan mayor solapamiento respecto a FECHA.
3. El filtro de siete días debe leer una proporción elevada.
4. La copia CTAS reduce la profundidad y el solapamiento.
5. El predicado de rango aprovecha mejor los metadatos MIN/MAX.
6. La UDF segura impide determinadas optimizaciones y aumenta el scan.
7. Aumentar el warehouse no corregiría la lectura innecesaria.
```

No afirmes que:

```text
menos particiones = exactamente el mismo porcentaje menos de tiempo
```

La ejecución contiene otros operadores.

---

## 20. Historial de pruning con Account Usage

Estas vistas son útiles para analizar patrones repetidos, no una sola consulta inmediata.

### Pruning por tabla y patrón de consulta

```sql
SELECT
    interval_start_time,
    interval_end_time,
    table_name,
    warehouse_name,
    query_hash,
    num_queries,

    partitions_scanned,
    partitions_pruned,

    ROUND(
        partitions_pruned
        / NULLIF(
            partitions_scanned
            + partitions_pruned,
            0
        )
        * 100,
        2
    ) AS pruning_pct,

    rows_scanned,
    rows_pruned,
    rows_matched,

    aggregate_query_execution_time

FROM SNOWFLAKE.ACCOUNT_USAGE
        .TABLE_QUERY_PRUNING_HISTORY

WHERE database_name = 'DB_CURSO'
  AND schema_name = 'PERFORMANCE'
  AND table_name IN (
      'VENTAS_MP_DESORDENADAS',
      'VENTAS_MP_ORDENADAS'
  )
  AND warehouse_name = 'WH_M09_PRUNING'
  AND interval_start_time >=
      DATEADD(
          'day',
          -1,
          CURRENT_TIMESTAMP()
      )

ORDER BY
    interval_start_time,
    table_name;
```

### Pruning por columna

```sql
SELECT
    interval_start_time,
    table_name,
    column_name,
    access_type,
    num_queries,
    partitions_scanned,
    partitions_pruned,
    rows_scanned,
    rows_pruned,
    rows_matched,
    search_optimization_supported_expressions

FROM SNOWFLAKE.ACCOUNT_USAGE
        .COLUMN_QUERY_PRUNING_HISTORY

WHERE database_name = 'DB_CURSO'
  AND schema_name = 'PERFORMANCE'
  AND table_name IN (
      'VENTAS_MP_DESORDENADAS',
      'VENTAS_MP_ORDENADAS'
  )
  AND interval_start_time >=
      DATEADD(
          'day',
          -1,
          CURRENT_TIMESTAMP()
      )

ORDER BY
    interval_start_time,
    table_name,
    column_name;
```

### Latencia

Estas vistas pueden tardar varias horas en reflejar las consultas.

No sustituyen a Query Profile para el diagnóstico inmediato.

Aportan:

- Agregación por hora.
- Patrones repetidos.
- Filas podadas y encontradas.
- Columnas usadas en filtros o joins.
- Sugerencias potenciales de Search Optimization.

---

## 21. ¿Es necesaria una clustering key?

La copia ordenada demuestra que una organización favorable puede mejorar el pruning.

Eso no significa automáticamente que debas ejecutar:

```sql
ALTER TABLE ...
CLUSTER BY (fecha);
```

Antes se deben valorar:

### Tamaño

Snowflake recomienda clustering explícito principalmente para tablas grandes con muchas micro-partitions, a menudo de varios terabytes.

La tabla del laboratorio es mucho más pequeña.

### Frecuencia de consulta

Una mejora aislada no justifica mantenimiento continuo.

### Frecuencia de DML

Automatic Clustering reescribe micro-partitions y consume servicio serverless.

Una tabla con muchas modificaciones puede tener un coste elevado de mantenimiento.

### Selectividad

Los filtros deben recuperar una pequeña proporción de la tabla.

### Uniformidad del workload

Muchas consultas deben beneficiarse de la misma clave.

---

## 22. Patrón de decisión

Utiliza este orden:

```text
1. Verificar el SQL y el filtro.
2. Revisar Query Profile.
3. Medir pruning.
4. Revisar el orden natural.
5. Corregir el proceso de carga si es posible.
6. Evaluar clustering explícito.
7. Medir coste de mantenimiento.
8. Aumentar compute solo si el scan ya es razonable.
```

---

## 23. Limpiar la UDF y detener recursos

```sql
DROP FUNCTION IF EXISTS
    DB_CURSO.PERFORMANCE
        .FECHA_EN_INTERVALO_SEGURO(
            DATE,
            DATE,
            DATE
        );
```

Restaura:

```sql
ALTER SESSION UNSET USE_CACHED_RESULT;
ALTER SESSION UNSET QUERY_TAG;
```

Suspende:

```sql
ALTER WAREHOUSE WH_M09_PRUNING SUSPEND;
```

Comprueba:

```sql
SHOW WAREHOUSES LIKE 'WH_M09_PRUNING';
```

Conserva:

```text
VENTAS_MP_DESORDENADAS
VENTAS_MP_ORDENADAS
```

para el siguiente ejercicio.

---

## 24. Limpieza opcional completa

Ejecuta esta sección solo cuando termine el módulo:

```sql
DROP TABLE IF EXISTS
    DB_CURSO.PERFORMANCE.VENTAS_MP_ORDENADAS;

DROP TABLE IF EXISTS
    DB_CURSO.PERFORMANCE.VENTAS_MP_DESORDENADAS;

DROP WAREHOUSE IF EXISTS
    WH_M09_PRUNING;
```

No elimines `VENTAS_RENDIMIENTO` si todavía se utiliza en otros laboratorios.

---

## 25. Errores frecuentes

### Las dos tablas muestran un clustering similar

Comprueba que la tabla ordenada se creó con:

```sql
ORDER BY fecha, id_venta
```

y no mediante `CLONE`.

También verifica que analizas:

```sql
(FECHA)
```

en `SYSTEM$CLUSTERING_INFORMATION`.

---

### Las consultas terminan instantáneamente

Comprueba:

```sql
SHOW PARAMETERS LIKE 'USE_CACHED_RESULT'
IN SESSION;
```

Debe ser `FALSE`.

---

### La consulta ordenada muestra caché local

Es posible que no se suspendiera el warehouse inmediatamente antes.

Repite:

```sql
ALTER WAREHOUSE WH_M09_PRUNING SUSPEND;
```

y ejecuta una sola vez.

---

### El total no es 150684

Comprueba:

```text
2025-06-01 inclusive
2025-06-08 exclusive
estado = COMPLETADA
```

También verifica que la tabla de origen se creó con la definición proporcionada.

---

### Las funciones de fecha podan igual que el rango

Puede ser correcto.

El optimizador puede transformar algunas expresiones.

Utiliza el plan ejecutado como evidencia y compara con la secure UDF de control.

---

### La secure UDF no muestra su lógica en Query Profile

Es el comportamiento esperado.

Los detalles internos de objetos seguros se ocultan.

Todavía puedes inspeccionar el `TableScan` de la tabla y las métricas globales.

---

### Account Usage no muestra todavía las consultas

Las vistas de pruning tienen latencia.

Usa Query History y Query Profile para el análisis inmediato.

---

## 26. Respuestas a las preguntas de reflexión

### 1. ¿Por qué no se crean particiones manuales?

Snowflake divide automáticamente todas las tablas en micro-partitions durante la carga.

### 2. ¿Qué metadatos permiten podar?

Entre otros, rangos de valores, valores distintos y propiedades de nulos por columna y micro-partition.

### 3. ¿Por qué ayuda ordenar por fecha?

Fechas cercanas quedan almacenadas juntas y cada partición cubre un rango temporal menor.

### 4. ¿Por qué el clone conserva el patrón?

Comparte inicialmente las micro-partitions de la tabla fuente.

### 5. ¿Por qué CTAS cuesta más?

Debe leer, ordenar y escribir una copia física completa.

### 6. ¿Natural frente a clustering key?

El clustering natural procede del orden de carga. La clustering key declara una dimensión que Automatic Clustering intentará mantener.

### 7. ¿Por qué pruning antes que tamaño?

Un warehouse mayor puede leer más rápido, pero sigue pagando por leer datos innecesarios.

### 8. ¿Por qué no medir solo tiempo total?

Puede incluir aprovisionamiento, compilación, colas y otros factores ajenos al scan.

### 9. ¿Qué indica un Filter posterior muy selectivo?

Que se leyeron muchas filas antes de aplicar el filtro; podría existir una oportunidad de pushdown u organización física.

### 10. ¿Cuándo no clusterizar?

En tablas pequeñas, poco consultadas, reconstruidas con frecuencia o filtradas por dimensiones muy diferentes.

---

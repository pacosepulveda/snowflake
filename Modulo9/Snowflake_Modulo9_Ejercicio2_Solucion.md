# Módulo 9 · Ejercicio 2

## Solución guiada: clustering keys y Automatic Clustering

---

## 1. Diseño del experimento

Crearemos una tabla con clustering key, pero cargaremos sus datos mientras el mantenimiento automático está suspendido.

```text
Tabla vacía
    ↓
CLUSTER BY (FECHA)
    ↓
SUSPEND RECLUSTER
    ↓
INSERT de 30 millones de filas desordenadas
    ↓
Medición y estimación
    ↓
RESUME RECLUSTER
```

Este orden permite observar un estado inicial claramente desfavorable sin que el servicio lo corrija durante la preparación.

---

## 2. Preparar Workspaces y privilegios

Crea:

```text
M09_E02_AUTOMATIC_CLUSTERING.sql
```

Concede acceso al metering:

```sql
USE ROLE ACCOUNTADMIN;

GRANT MONITOR USAGE
ON ACCOUNT
TO ROLE SYSADMIN;
```

Vuelve a:

```sql
USE ROLE SYSADMIN;
```

Configura el contexto:

```sql
CREATE DATABASE IF NOT EXISTS DB_CURSO;
CREATE SCHEMA IF NOT EXISTS DB_CURSO.PERFORMANCE;

USE DATABASE DB_CURSO;
USE SCHEMA PERFORMANCE;

ALTER SESSION SET QUERY_TAG = 'M09_E02_PREPARACION';
```

---

## 3. Crear el warehouse

```sql
CREATE OR REPLACE WAREHOUSE WH_M09_CLUSTER
    WAREHOUSE_TYPE = STANDARD
    WAREHOUSE_SIZE = XSMALL
    GENERATION = '1'
    MIN_CLUSTER_COUNT = 1
    MAX_CLUSTER_COUNT = 1
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE
    ENABLE_QUERY_ACCELERATION = FALSE
    COMMENT = 'M09 laboratorio Automatic Clustering';
```

Comprueba:

```sql
SHOW WAREHOUSES LIKE 'WH_M09_CLUSTER';
```

```sql
DESC WAREHOUSE WH_M09_CLUSTER;
```

### Separación de recursos

`WH_M09_CLUSTER` se utiliza para SQL interactivo.

Automatic Clustering:

- Se ejecuta en segundo plano.
- Utiliza recursos serverless administrados por Snowflake.
- No requiere seleccionar un warehouse.
- Se factura separadamente.

Por eso podremos suspender el warehouse y seguir observando cambios en el estado de clustering.

---

## 4. Comprobar la fuente

```sql
USE WAREHOUSE WH_M09_CLUSTER;
```

```sql
SHOW TABLES LIKE 'VENTAS_RENDIMIENTO'
IN SCHEMA DB_CURSO.PERFORMANCE;
```

Si existe:

```sql
SELECT
    COUNT(*) AS filas,
    MIN(fecha) AS fecha_minima,
    MAX(fecha) AS fecha_maxima
FROM DB_CURSO.PERFORMANCE.VENTAS_RENDIMIENTO;
```

Resultado:

```text
10.000.000
2025-01-01
2025-12-31
```

---

## 5. Recuperación si falta la tabla

Ejecuta únicamente si no existe.

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

---

## 6. Crear la tabla vacía

```sql
CREATE OR REPLACE TABLE
    DB_CURSO.PERFORMANCE.VENTAS_CLUSTER_AUTO

LIKE
    DB_CURSO.PERFORMANCE.VENTAS_RENDIMIENTO;
```

Define la clave mientras no hay datos:

```sql
ALTER TABLE
    DB_CURSO.PERFORMANCE.VENTAS_CLUSTER_AUTO

CLUSTER BY (fecha);
```

Suspende inmediatamente:

```sql
ALTER TABLE
    DB_CURSO.PERFORMANCE.VENTAS_CLUSTER_AUTO

SUSPEND RECLUSTER;
```

### Por qué se hace en este orden

Una clustering key define qué organización debe mantener Snowflake.

Si se añade sobre una tabla ya llena y mal organizada, el servicio puede comenzar a trabajar y consumir créditos.

Al definirla sobre una tabla vacía y suspenderla antes del `INSERT`:

- Existe la clave.
- No existe todavía trabajo que reclusterizar.
- La carga posterior no activa mantenimiento automático.
- Podemos medir un baseline controlado.

---

## 7. Comprobar clave y estado

Utiliza Information Schema:

```sql
SELECT
    table_name,
    clustering_key,
    auto_clustering_on,
    row_count,
    bytes

FROM DB_CURSO.INFORMATION_SCHEMA.TABLES

WHERE table_schema = 'PERFORMANCE'
  AND table_name = 'VENTAS_CLUSTER_AUTO';
```

Resultado conceptual:

```text
CLUSTERING_KEY = LINEAR(FECHA)
AUTO_CLUSTERING_ON = FALSE
ROW_COUNT = 0
```

También:

```sql
SHOW TABLES LIKE 'VENTAS_CLUSTER_AUTO'
IN SCHEMA DB_CURSO.PERFORMANCE;
```

---

## 8. Cargar treinta millones de filas

```sql
INSERT INTO
    DB_CURSO.PERFORMANCE.VENTAS_CLUSTER_AUTO

SELECT
    fuente.id_venta
    + replica.numero * 10000000
        AS id_venta,

    fuente.fecha,
    fuente.region,
    fuente.canal,
    fuente.id_cliente,
    fuente.id_producto,
    fuente.importe,
    fuente.descuento,
    fuente.estado

FROM DB_CURSO.PERFORMANCE.VENTAS_RENDIMIENTO
    AS fuente

CROSS JOIN (
    SELECT column1::NUMBER AS numero
    FROM VALUES
        (0),
        (1),
        (2)
) AS replica

ORDER BY
    id_venta;
```

### Por qué el orden es desfavorable

En la fuente:

```sql
fecha = DATEADD(
    'day',
    MOD(n, 365),
    '2025-01-01'
)
```

El orden por identificador recorre los 365 días una y otra vez.

Una micro-partition puede contener fechas distribuidas por casi todo el año, por lo que sus rangos `MIN/MAX` se solapan con los de muchas otras particiones.

### Validar

```sql
SELECT
    COUNT(*) AS filas,
    COUNT(DISTINCT id_venta) AS ids,
    COUNT(DISTINCT fecha) AS fechas,
    MIN(fecha) AS fecha_minima,
    MAX(fecha) AS fecha_maxima
FROM DB_CURSO.PERFORMANCE.VENTAS_CLUSTER_AUTO;
```

Resultado:

| FILAS | IDS | FECHAS |
|---:|---:|---:|
| 30000000 | 30000000 | 365 |

Confirma que el servicio sigue suspendido:

```sql
SELECT
    table_name,
    clustering_key,
    auto_clustering_on
FROM DB_CURSO.INFORMATION_SCHEMA.TABLES
WHERE table_schema = 'PERFORMANCE'
  AND table_name = 'VENTAS_CLUSTER_AUTO';
```

---

## 9. Crear la tabla de mediciones

```sql
CREATE OR REPLACE TABLE
    DB_CURSO.PERFORMANCE.CLUSTERING_MEDICIONES (
        medido_en                 TIMESTAMP_LTZ,
        fase                     VARCHAR(30),
        total_particiones        NUMBER,
        particiones_constantes   NUMBER,
        solapamiento_medio       FLOAT,
        profundidad_media        FLOAT,
        notas                    VARCHAR,
        histograma               VARIANT
    );
```

Inserta la primera medición:

```sql
INSERT INTO
    DB_CURSO.PERFORMANCE.CLUSTERING_MEDICIONES

WITH info AS (
    SELECT PARSE_JSON(
        SYSTEM$CLUSTERING_INFORMATION(
            'DB_CURSO.PERFORMANCE.VENTAS_CLUSTER_AUTO'
        )
    ) AS j
)

SELECT
    CURRENT_TIMESTAMP(),
    'ANTES',
    j:total_partition_count::NUMBER,
    j:total_constant_partition_count::NUMBER,
    j:average_overlaps::FLOAT,
    j:average_depth::FLOAT,
    j:notes::VARCHAR,
    j:partition_depth_histogram
FROM info;
```

Consulta:

```sql
SELECT *
FROM DB_CURSO.PERFORMANCE.CLUSTERING_MEDICIONES
ORDER BY medido_en;
```

---

## 10. Interpretar el baseline

### Profundidad media

Indica cuántas micro-partitions se solapan en promedio respecto a la clave.

```text
menor profundidad
=
mejor clustering
```

### Solapamiento medio

Mide el número medio de particiones con rangos que se cruzan.

### Particiones constantes

Son particiones que ya no obtendrían un beneficio importante de más reclustering.

Un porcentaje elevado suele indicar un estado más maduro.

### Histograma

Permite ver cuántas particiones están en cada intervalo de profundidad.

No debes resumir todo el estado en una única cifra.

---

## 11. Comparar claves candidatas

```sql
SELECT
    'FECHA' AS expresion,
    SYSTEM$CLUSTERING_DEPTH(
        'DB_CURSO.PERFORMANCE.VENTAS_CLUSTER_AUTO',
        '(FECHA)'
    ) AS profundidad

UNION ALL

SELECT
    'REGION',
    SYSTEM$CLUSTERING_DEPTH(
        'DB_CURSO.PERFORMANCE.VENTAS_CLUSTER_AUTO',
        '(REGION)'
    )

UNION ALL

SELECT
    'FECHA_REGION',
    SYSTEM$CLUSTERING_DEPTH(
        'DB_CURSO.PERFORMANCE.VENTAS_CLUSTER_AUTO',
        '(FECHA, REGION)'
    )

UNION ALL

SELECT
    'ID_VENTA',
    SYSTEM$CLUSTERING_DEPTH(
        'DB_CURSO.PERFORMANCE.VENTAS_CLUSTER_AUTO',
        '(ID_VENTA)'
    );
```

### Interpretación

`ID_VENTA` puede mostrar buen clustering natural porque la carga se ordenó por esa columna.

Sin embargo:

- Tiene cardinalidad muy alta.
- No es el filtro analítico principal.
- Para point lookups puede ser más apropiado Search Optimization.
- Mantener clustering por una clave casi única puede ser costoso.

La clave debe elegirse por el workload, no por la menor profundidad aislada.

---

## 12. Validar el resultado de negocio

```sql
SELECT
    COUNT(*) AS ventas_completadas,
    SUM(importe - descuento)::NUMBER(20,2)
        AS importe_neto

FROM DB_CURSO.PERFORMANCE.VENTAS_CLUSTER_AUTO

WHERE fecha >= '2025-06-01'::DATE
  AND fecha <  '2025-06-08'::DATE
  AND estado = 'COMPLETADA';
```

Resultado:

| VENTAS_COMPLETADAS | IMPORTE_NETO |
|---:|---:|
| 452052 | 222650999.46 |

La consulta ha calentado el warehouse. Suspéndelo:

```sql
ALTER WAREHOUSE WH_M09_CLUSTER SUSPEND;
```

---

## 13. Ejecutar el benchmark inicial

Desactiva la result cache:

```sql
ALTER SESSION SET USE_CACHED_RESULT = FALSE;
```

Tag:

```sql
ALTER SESSION SET QUERY_TAG = 'M09_E02_ANTES_CLUSTERING';
```

Ejecuta:

```sql
USE WAREHOUSE WH_M09_CLUSTER;
```

```sql
SELECT
    region,
    canal,
    COUNT(*) AS num_ventas,
    SUM(importe - descuento)::NUMBER(20,2)
        AS importe_neto

FROM DB_CURSO.PERFORMANCE.VENTAS_CLUSTER_AUTO

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

No repitas la consulta.

Debe devolver quince grupos.

---

## 14. Analizar el benchmark inicial

```sql
ALTER SESSION SET QUERY_TAG = 'M09_E02_ANALISIS';
```

```sql
-- Evita que esta consulta de análisis conserve
-- el mismo QUERY_TAG que la consulta medida.
ALTER SESSION SET QUERY_TAG = 'M09_E02_ANALISIS';

SELECT
    query_id,
    query_tag,
    start_time,

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
        * (
            partitions_total
            - partitions_scanned
        )
        / NULLIF(partitions_total, 0),
        2
    ) AS pruning_pct,

    ROUND(
        COALESCE(
            percentage_scanned_from_cache,
            0
        ) * 100,
        2
    ) AS cache_local_pct

FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY

WHERE warehouse_name = 'WH_M09_CLUSTER'

  AND start_time >= DATEADD(
      'hour',
      -2,
      CURRENT_TIMESTAMP()
  )

  AND query_tag = 'M09_E02_ANTES_CLUSTERING'

  AND query_type = 'SELECT'

  AND query_text ILIKE
      '%VENTAS_CLUSTER_AUTO%'

ORDER BY start_time DESC;
```

Copia el Query ID o abre Query Profile.

---

## 15. Estimar el coste

Ejecuta una sola estimación (si la tabla se ha creado recientemente, como en nuestro ejercicio, es posible que no pueda hacer una estimación completa de coste):

```sql
SELECT
    SYSTEM$ESTIMATE_AUTOMATIC_CLUSTERING_COSTS(
        'DB_CURSO.PERFORMANCE.VENTAS_CLUSTER_AUTO'
    ) AS estimacion;
```

Proyección:

```sql
WITH estimacion AS (
    SELECT PARSE_JSON(
        SYSTEM$ESTIMATE_AUTOMATIC_CLUSTERING_COSTS(
            'DB_CURSO.PERFORMANCE.VENTAS_CLUSTER_AUTO'
        )
    ) AS j
)

SELECT
    j:"reportTime"::VARCHAR
        AS fecha_informe,

    j:"clusteringKey"::VARCHAR
        AS clustering_key,

    j:"warning"::VARCHAR
        AS advertencia,

    j:"initial":"unit"::VARCHAR
        AS unidad_inicial,

    j:"initial":"value"::FLOAT
        AS coste_inicial,

    j:"initial":"comment"::VARCHAR
        AS comentario_inicial,

    j:"maintenance":"unit"::VARCHAR
        AS unidad_mantenimiento,

    j:"maintenance":"value"::FLOAT
        AS coste_mantenimiento,

    j:"maintenance":"comment"::VARCHAR
        AS comentario_mantenimiento

FROM estimacion;
```

### Posible resultado de mantenimiento vacío

La tabla puede no tener suficiente historial DML para estimar mantenimiento.

En ese caso:

```text
maintenance = {}
```

no es un error.

### Precisión

La estimación:

- Muestrea micro-partitions.
- Ejecuta trabajos de clustering de muestra.
- Depende de la velocidad del sistema.
- Puede variar entre ejecuciones.
- Puede diferir del coste real hasta aproximadamente un 100 % y, en casos raros, varias veces.

Por eso no debe utilizarse como presupuesto garantizado.

---

## 16. Activar Automatic Clustering

```sql
ALTER TABLE
    DB_CURSO.PERFORMANCE.VENTAS_CLUSTER_AUTO

RESUME RECLUSTER;
```

Comprueba:

```sql
SELECT
    table_name,
    clustering_key,
    auto_clustering_on

FROM DB_CURSO.INFORMATION_SCHEMA.TABLES

WHERE table_schema = 'PERFORMANCE'
  AND table_name = 'VENTAS_CLUSTER_AUTO';
```

Resultado:

```text
AUTO_CLUSTERING_ON = YES
```

Suspende el warehouse:

```sql
ALTER WAREHOUSE WH_M09_CLUSTER SUSPEND;
```

Automatic Clustering puede continuar porque utiliza recursos serverless.

---

## 17. Registrar mediciones durante el proceso

No ejecutes el sondeo continuamente.

Después de dos o tres minutos:

```sql
INSERT INTO
    DB_CURSO.PERFORMANCE.CLUSTERING_MEDICIONES

WITH info AS (
    SELECT PARSE_JSON(
        SYSTEM$CLUSTERING_INFORMATION(
            'DB_CURSO.PERFORMANCE.VENTAS_CLUSTER_AUTO'
        )
    ) AS j
)

SELECT
    CURRENT_TIMESTAMP(),
    'DURANTE_1',
    j:total_partition_count::NUMBER,
    j:total_constant_partition_count::NUMBER,
    j:average_overlaps::FLOAT,
    j:average_depth::FLOAT,
    j:notes::VARCHAR,
    j:partition_depth_histogram
FROM info;
```

Repite más tarde cambiando la fase:

```text
DURANTE_2
DESPUES
```

Compara:

```sql
SELECT
    medido_en,
    fase,
    total_particiones,
    particiones_constantes,
    solapamiento_medio,
    profundidad_media,
    notas
FROM DB_CURSO.PERFORMANCE.CLUSTERING_MEDICIONES
ORDER BY medido_en;
```

### Qué esperar

Puede ocurrir:

1. La profundidad baja rápidamente.
2. Baja en varias pasadas.
3. No cambia durante la clase.
4. Snowflake decide que el beneficio no justifica trabajo adicional.

Las cuatro situaciones son compatibles con el funcionamiento del servicio.

---

## 18. Consultar errores recientes

La tabla ya tiene una clustering key, por lo que el segundo argumento puede utilizarse como número de errores:

```sql
SELECT
    PARSE_JSON(
        SYSTEM$CLUSTERING_INFORMATION(
            'DB_CURSO.PERFORMANCE.VENTAS_CLUSTER_AUTO',
            20
        )
    ) AS informacion_y_errores;
```

Extrae:

```sql
WITH info AS (
    SELECT PARSE_JSON(
        SYSTEM$CLUSTERING_INFORMATION(
            'DB_CURSO.PERFORMANCE.VENTAS_CLUSTER_AUTO',
            20
        )
    ) AS j
)

SELECT
    j:cluster_by_keys::VARCHAR
        AS clustering_key,

    j:average_depth::FLOAT
        AS profundidad_media,

    j:clustering_errors
        AS errores;
```

Un array vacío indica que no se han registrado errores recientes.

---

## 19. Consultar el consumo

### Account Usage por tabla

```sql
SELECT
    start_time,
    end_time,
    database_name,
    schema_name,
    table_name,
    credits_used,
    num_bytes_reclustered,
    num_rows_reclustered

FROM SNOWFLAKE.ACCOUNT_USAGE
        .AUTOMATIC_CLUSTERING_HISTORY

WHERE database_name = 'DB_CURSO'
  AND schema_name = 'PERFORMANCE'
  AND table_name = 'VENTAS_CLUSTER_AUTO'
  AND start_time >=
      DATEADD(
          'day',
          -1,
          CURRENT_TIMESTAMP()
      )

ORDER BY start_time;
```

Latencia posible:

```text
hasta 3 horas
```

### Metering general del servicio

```sql
SELECT
    start_time,
    end_time,
    service_type,
    credits_used,
    bytes,
    "ROWS" AS filas_reclusterizadas

FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_HISTORY

WHERE service_type = 'AUTO_CLUSTERING'

  AND start_time >= DATEADD(
      'day',
      -1,
      CURRENT_TIMESTAMP()
  )

ORDER BY start_time;
```

### Por qué no aparece en el warehouse

El consumo no pertenece a `WH_M09_CLUSTER`.

Se factura como servicio serverless:

```text
AUTO_CLUSTERING
```

El warehouse puede estar suspendido durante el reclustering.

---

## 20. Suspender antes del benchmark posterior

Cuando el estado haya mejorado o termine la ventana asignada:

```sql
ALTER TABLE
    DB_CURSO.PERFORMANCE.VENTAS_CLUSTER_AUTO

SUSPEND RECLUSTER;
```

Comprueba:

```sql
SELECT
    table_name,
    auto_clustering_on
FROM DB_CURSO.INFORMATION_SCHEMA.TABLES
WHERE table_schema = 'PERFORMANCE'
  AND table_name = 'VENTAS_CLUSTER_AUTO';
```

Debe devolver:

```text
FALSE
```

Suspende el warehouse:

```sql
ALTER WAREHOUSE WH_M09_CLUSTER SUSPEND;
```

---

## 21. Ejecutar el benchmark posterior

```sql
ALTER SESSION SET QUERY_TAG =
    'M09_E02_DESPUES_CLUSTERING';
```

```sql
USE WAREHOUSE WH_M09_CLUSTER;
```

```sql
SELECT
    region,
    canal,
    COUNT(*) AS num_ventas,
    SUM(importe - descuento)::NUMBER(20,2)
        AS importe_neto

FROM DB_CURSO.PERFORMANCE.VENTAS_CLUSTER_AUTO

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

Los resultados deben ser idénticos al benchmark inicial.

---

## 22. Comparar las dos ejecuciones

```sql
ALTER SESSION SET QUERY_TAG = 'M09_E02_COMPARACION';
```

```sql
-- Evita que la consulta de análisis use uno de los tags medidos
ALTER SESSION SET QUERY_TAG = 'M09_E02_ANALISIS';

SELECT
    query_tag,
    query_id,
    start_time,

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
        * (
            partitions_total
            - partitions_scanned
        )
        / NULLIF(partitions_total, 0),
        2
    ) AS pruning_pct,

    rows_produced

FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY

WHERE warehouse_name = 'WH_M09_CLUSTER'

  AND start_time >= DATEADD(
      'hour',
      -4,
      CURRENT_TIMESTAMP()
  )

  AND query_tag IN (
      'M09_E02_ANTES_CLUSTERING',
      'M09_E02_DESPUES_CLUSTERING'
  )

  AND query_type = 'SELECT'

  AND query_text ILIKE
      '%VENTAS_CLUSTER_AUTO%'

ORDER BY start_time;
```

### Interpretación

Busca:

- Menos particiones leídas.
- Mayor pruning.
- Menos bytes.
- Menor tiempo de `TableScan`.

El tiempo total puede no reducirse en la misma proporción debido a:

- Aprovisionamiento.
- Compilación.
- Agregación.
- Variación normal.

---

## 23. Plan alternativo cuando no hay actividad visible

Snowflake no promete reclustering inmediato.

Si no se observa mejora dentro de la clase:

```sql
ALTER TABLE
    DB_CURSO.PERFORMANCE.VENTAS_CLUSTER_AUTO

SUSPEND RECLUSTER;
```

Documenta el estado y crea opcionalmente una baseline:

```sql
CREATE OR REPLACE TRANSIENT TABLE
    DB_CURSO.PERFORMANCE.VENTAS_CLUSTER_BASELINE
AS
SELECT *
FROM DB_CURSO.PERFORMANCE.VENTAS_CLUSTER_AUTO
ORDER BY
    fecha,
    id_venta;
```

Benchmark:

```sql
ALTER WAREHOUSE WH_M09_CLUSTER SUSPEND;

ALTER SESSION SET QUERY_TAG =
    'M09_E02_BASELINE_ORDENADA';

USE WAREHOUSE WH_M09_CLUSTER;

SELECT
    region,
    canal,
    COUNT(*) AS num_ventas,
    SUM(importe - descuento)::NUMBER(20,2)
        AS importe_neto
FROM DB_CURSO.PERFORMANCE.VENTAS_CLUSTER_BASELINE
WHERE fecha >= '2025-06-01'::DATE
  AND fecha <  '2025-06-08'::DATE
  AND estado = 'COMPLETADA'
GROUP BY region, canal
ORDER BY region, canal;
```

### Qué demuestra y qué no

Demuestra el beneficio potencial de una organización física por fecha.

No demuestra:

- El coste real de Automatic Clustering.
- El tiempo que Snowflake necesitaría.
- El mantenimiento posterior.

---

## 24. Demostrar suspensión y reanudación

Reanuda:

```sql
ALTER TABLE
    DB_CURSO.PERFORMANCE.VENTAS_CLUSTER_AUTO

RESUME RECLUSTER;
```

Comprueba `TRUE`.

Después vuelve a suspender:

```sql
ALTER TABLE
    DB_CURSO.PERFORMANCE.VENTAS_CLUSTER_AUTO

SUSPEND RECLUSTER;
```

Comprueba `FALSE`.

### Efecto operativo

Mientras está suspendido:

- La clustering key continúa definida.
- Las consultas pueden utilizar el orden actual.
- Snowflake no realiza mantenimiento automático.
- Nuevas cargas desordenadas pueden degradar el estado.
- No se generan cargos nuevos de reclustering para esa tabla.

Al reanudar, Snowflake evalúa el estado y puede iniciar actividad y consumo.

---

## 25. Por qué las filas reclusterizadas pueden superar el total

Reclustering puede necesitar varias pasadas.

Una micro-partition puede:

1. Reescribirse durante una primera mejora.
2. Volver a solaparse con nuevos datos.
3. Participar en otra operación posterior.

Por eso:

```text
NUM_ROWS_RECLUSTERED
```

puede ser igual o superior al número de filas lógicas de la tabla.

No representa filas únicas.

---

## 26. Cómo tomar la decisión

### Activar Automatic Clustering

Tiene más sentido cuando:

- La tabla es muy grande.
- Tiene muchas micro-partitions.
- Se filtra repetidamente por la misma dimensión.
- Los filtros son selectivos.
- El patrón natural de carga se degrada.
- La mejora de pruning es significativa.
- El coste de mantenimiento es aceptable.

### No activarlo

Tiene más sentido cuando:

- La tabla es pequeña.
- Se recrea completamente cada carga.
- Se consulta poco.
- Los filtros varían entre muchas columnas.
- Puede cargarse ya ordenada.
- La mejora es marginal.
- El churn de DML hace caro el mantenimiento.

### Probar temporalmente

Es la opción prudente cuando todavía no existe baseline.

Snowflake recomienda comenzar con una o dos tablas, medir y ampliar solo después.

---

## 27. Ejemplo de informe FinOps

```text
Decisión: PROBAR DURANTE 14 DÍAS

Motivo:
- Las consultas por fecha representan el 70 % del workload.
- El pruning pasó de X % a Y %.
- La ejecución bajó de A a B segundos.
- El coste inicial fue C créditos.
- El mantenimiento medio fue D créditos/día.

Condiciones de continuidad:
- Reducción de al menos 30 % en p95.
- Coste mensual inferior al presupuesto.
- Sin crecimiento anómalo de reclustering.
```

Las cifras deben proceder de las mediciones reales.

---

## 28. Restaurar y detener

Asegura la suspensión:

```sql
ALTER TABLE
    DB_CURSO.PERFORMANCE.VENTAS_CLUSTER_AUTO

SUSPEND RECLUSTER;
```

Restaura:

```sql
ALTER SESSION UNSET USE_CACHED_RESULT;
ALTER SESSION UNSET QUERY_TAG;
```

Suspende:

```sql
ALTER WAREHOUSE WH_M09_CLUSTER SUSPEND;
```

Comprueba:

```sql
SELECT
    table_name,
    clustering_key,
    auto_clustering_on
FROM DB_CURSO.INFORMATION_SCHEMA.TABLES
WHERE table_schema = 'PERFORMANCE'
  AND table_name = 'VENTAS_CLUSTER_AUTO';
```

Y:

```sql
SHOW WAREHOUSES LIKE 'WH_M09_CLUSTER';
```

Estado final:

```text
Clustering key definida
Automatic Clustering = FALSE
Warehouse = SUSPENDED
```

---

## 29. Limpieza opcional

Cuando no se necesiten las evidencias:

```sql
DROP TABLE IF EXISTS
    DB_CURSO.PERFORMANCE.VENTAS_CLUSTER_BASELINE;

DROP TABLE IF EXISTS
    DB_CURSO.PERFORMANCE.CLUSTERING_MEDICIONES;

DROP TABLE IF EXISTS
    DB_CURSO.PERFORMANCE.VENTAS_CLUSTER_AUTO;

DROP WAREHOUSE IF EXISTS
    WH_M09_CLUSTER;
```

---

## 30. Errores frecuentes

### AUTO_CLUSTERING_ON aparece TRUE durante la carga

Se olvidó ejecutar:

```sql
SUSPEND RECLUSTER
```

antes del `INSERT`.

Suspende el servicio. El baseline podría haber empezado a cambiar.

---

### ALTER TABLE CLUSTER BY falla

Comprueba:

- Ownership o privilegios adecuados sobre la tabla.
- `USAGE` sobre base y esquema.
- Que no se utiliza una tabla temporal no compatible con el escenario.
- Que la expresión referencia columnas válidas.

---

### La estimación no devuelve mantenimiento

Es normal cuando no existe suficiente historial DML.

La estimación inicial puede seguir apareciendo.

---

### No se produce reclustering

Puede ser una decisión del servicio.

Comprueba:

- `AUTO_CLUSTERING_ON = TRUE`.
- Clustering key definida.
- Errores recientes.
- Profundidad inicial.
- Tamaño de la tabla.
- Historial después de su latencia.

Utiliza la baseline opcional para la comparación didáctica.

---

### El warehouse se reanuda durante la espera

Alguna consulta ejecutada utilizó el warehouse.

Las funciones de sistema y consultas de metadatos pueden requerir un warehouse según el contexto de ejecución. Para demostrar la independencia, comprueba el estado antes y después, y evita consultas sobre la tabla de datos durante la espera.

Automatic Clustering no utiliza el warehouse.

---

### El historial de créditos está vacío

Account Usage puede tardar hasta tres horas.

Conserva:

- Nombre de tabla.
- Hora.
- Mediciones.
- Estado.

Vuelve a consultar más tarde.

---

### La tabla ordenada opcional consume espacio

Es una copia física y genera almacenamiento independiente.

Elimínala cuando termine la comparación.

---

## 31. Respuestas a las preguntas de reflexión

### 1. ¿Por qué puede haber coste inmediato?

Añadir una clave a una tabla existente y mal organizada puede provocar un reclustering inicial.

### 2. ¿Por qué no comienza inmediatamente?

Snowflake evalúa si el beneficio esperado justifica la operación y planifica recursos serverless.

### 3. ¿Ordenar frente a mantener?

Ordenar una carga crea un buen estado inicial. Automatic Clustering lo mantiene a medida que nuevos DML lo degradan.

### 4. ¿Problema de alta cardinalidad?

Puede requerir mucho trabajo de mantenimiento y producir poco beneficio general.

### 5. ¿Qué es average depth?

La profundidad media de solapamiento de las micro-partitions respecto a la clave.

### 6. ¿Por qué no llegar a uno?

El objetivo es un estado suficientemente eficiente, no necesariamente una organización perfecta.

### 7. ¿Por qué más filas reclusterizadas que filas reales?

Una fila puede participar en varias pasadas de reescritura.

### 8. ¿Warehouse frente a serverless?

El warehouse ejecuta carga y queries. Automatic Clustering se factura como servicio serverless independiente.

### 9. ¿Cuándo reconstruir?

Cuando la tabla cambia poco, puede recrearse por lotes y el coste de mantenimiento continuo no compensa.

### 10. ¿Por qué empezar con pocas tablas?

Para medir coste, beneficio y efecto del DML antes de extender el servicio.

---
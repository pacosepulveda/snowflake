# Módulo 8 · Ejercicio 3

## Solución guiada: Query Acceleration Service y análisis FinOps

---

## 1. Principio del laboratorio

Query Acceleration Service (QAS) no reemplaza al warehouse.

El flujo real es:

```text
Warehouse
    ├── compila y coordina la consulta
    ├── ejecuta las partes no elegibles
    └── descarga partes elegibles
            ↓
      QAS serverless
```

QAS suele beneficiar a consultas con:

- Escaneos grandes.
- Filtros selectivos.
- Agregaciones.
- Operaciones con una parte importante del trabajo paralelizable.

El coste de QAS se factura por separado del coste del warehouse.

No basta con observar que una consulta termina antes. Para afirmar que QAS se utilizó deben aparecer evidencias como:

```text
QUERY_ACCELERATION_BYTES_SCANNED > 0
```

O bien:

```text
QUERY_ACCELERATION_PARTITIONS_SCANNED > 0
```

Si ambas métricas son cero, no debe atribuirse a QAS ninguna diferencia temporal entre las dos ejecuciones.

---

## 2. Preparar Workspaces y privilegios

Crea en **Workspaces**:

```text
M08_E03_QAS_FINOPS.sql
```

### 2.1. Conceder privilegios

Ejecuta con `ACCOUNTADMIN`:

```sql
USE ROLE ACCOUNTADMIN;
```

Concede a `SYSADMIN` acceso a las funciones de metering de Information Schema:

```sql
GRANT MONITOR USAGE
ON ACCOUNT
TO ROLE SYSADMIN;
```

Concede también los roles de base de datos necesarios para las vistas históricas de `SNOWFLAKE.ACCOUNT_USAGE`:

```sql
GRANT DATABASE ROLE SNOWFLAKE.GOVERNANCE_VIEWER
TO ROLE SYSADMIN;
```

```sql
GRANT DATABASE ROLE SNOWFLAKE.USAGE_VIEWER
TO ROLE SYSADMIN;
```

Estos roles permiten consultar, entre otras, vistas de historial de consultas, elegibilidad, atribución y consumo.

### 2.2. Comprobar el sample database

```sql
SHOW DATABASES LIKE 'SNOWFLAKE_SAMPLE_DATA';
```

Si existe:

```sql
GRANT IMPORTED PRIVILEGES
ON DATABASE SNOWFLAKE_SAMPLE_DATA
TO ROLE SYSADMIN;
```

Si no existe, créala una sola vez desde el share oficial:

```sql
CREATE DATABASE SNOWFLAKE_SAMPLE_DATA
FROM SHARE SFC_SAMPLES.SAMPLE_DATA;
```

Después:

```sql
GRANT IMPORTED PRIVILEGES
ON DATABASE SNOWFLAKE_SAMPLE_DATA
TO ROLE SYSADMIN;
```

Vuelve a `SYSADMIN`:

```sql
USE ROLE SYSADMIN;
```

### 2.3. Configurar la sesión

```sql
ALTER SESSION SET USE_CACHED_RESULT = FALSE;
```

```sql
ALTER SESSION SET QUERY_TAG = 'M08_E03_PREPARACION';
```

### Por qué se desactiva el Result Cache

El resultado persistido de una consulta anterior podría hacer que una ejecución posterior terminara prácticamente de inmediato sin volver a ejecutar el plan completo.

Desactivar `USE_CACHED_RESULT` evita ese sesgo concreto. No desactiva otras cachés internas, como la caché local del warehouse.

---

## 3. Comprobar el sample data

```sql
SHOW SCHEMAS LIKE 'TPCDS_SF10TCL'
IN DATABASE SNOWFLAKE_SAMPLE_DATA;
```

```sql
SHOW TABLES LIKE 'STORE_SALES'
IN SCHEMA SNOWFLAKE_SAMPLE_DATA.TPCDS_SF10TCL;
```

```sql
SHOW TABLES LIKE 'DATE_DIM'
IN SCHEMA SNOWFLAKE_SAMPLE_DATA.TPCDS_SF10TCL;
```

```sql
SHOW TABLES LIKE 'ITEM'
IN SCHEMA SNOWFLAKE_SAMPLE_DATA.TPCDS_SF10TCL;
```

El sample database es compartido y de solo lectura.

No se permite modificar sus objetos mediante operaciones como:

```text
INSERT
UPDATE
DELETE
ALTER TABLE
CLONE
```

Sí se permite consultarlos con un warehouse autorizado.

---

## 4. Crear los warehouses

### 4.1. Warehouse sin QAS

```sql
CREATE OR REPLACE WAREHOUSE WH_M08_NOQAS
    WAREHOUSE_TYPE = STANDARD
    WAREHOUSE_SIZE = XSMALL
    GENERATION = '1'
    MIN_CLUSTER_COUNT = 1
    MAX_CLUSTER_COUNT = 1
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE
    ENABLE_QUERY_ACCELERATION = FALSE
    COMMENT = 'M08 prueba sin QAS';
```

### 4.2. Warehouse con QAS

```sql
CREATE OR REPLACE WAREHOUSE WH_M08_QAS
    WAREHOUSE_TYPE = STANDARD
    WAREHOUSE_SIZE = XSMALL
    GENERATION = '1'
    MIN_CLUSTER_COUNT = 1
    MAX_CLUSTER_COUNT = 1
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE
    ENABLE_QUERY_ACCELERATION = TRUE
    QUERY_ACCELERATION_MAX_SCALE_FACTOR = 8
    COMMENT = 'M08 prueba con QAS factor 8';
```

### Por qué se fija Gen1

La generación se declara explícitamente para mantener controlado el experimento y evitar que la configuración predeterminada del servicio introduzca diferencias adicionales.

Los dos warehouses deben ser equivalentes salvo por:

```text
ENABLE_QUERY_ACCELERATION
QUERY_ACCELERATION_MAX_SCALE_FACTOR
```

### Qué significa el scale factor

El factor configurado es un límite sobre la tasa de recursos serverless que puede utilizar QAS en relación con el warehouse.

No significa:

```text
reservar ocho warehouses adicionales
```

QAS utiliza únicamente:

- Los recursos necesarios.
- Los recursos disponibles.
- Hasta el límite configurado.

El valor `0` elimina el límite superior y puede aumentar el coste, por lo que no se utiliza en este laboratorio.

---

## 5. Inspeccionar la configuración

```sql
SHOW WAREHOUSES LIKE 'WH_M08_%'
->>
SELECT
    "name",
    "state",
    "size",
    "generation",
    "min_cluster_count",
    "max_cluster_count",
    "enable_query_acceleration",
    "query_acceleration_max_scale_factor",
    "auto_suspend",
    "auto_resume"
FROM $1
WHERE "name" IN (
    'WH_M08_NOQAS',
    'WH_M08_QAS'
)
ORDER BY "name";
```

También puedes ejecutar:

```sql
DESC WAREHOUSE WH_M08_NOQAS;
DESC WAREHOUSE WH_M08_QAS;
```

Resultado conceptual:

| Warehouse | QAS | Scale factor máximo |
|---|---|---:|
| `WH_M08_NOQAS` | `FALSE` | — |
| `WH_M08_QAS` | `TRUE` | 8 |

---

## 6. Suspender ambos warehouses

```sql
ALTER WAREHOUSE WH_M08_NOQAS SUSPEND;
ALTER WAREHOUSE WH_M08_QAS SUSPEND;
```

Cada warehouse tendrá:

- Su propio clúster.
- Su propia caché local.
- Un inicio comparable.

Esto reduce, aunque no elimina completamente, la variabilidad del benchmark.

---

## 7. Ejecutar la consulta sin QAS

Selecciona el warehouse:

```sql
USE WAREHOUSE WH_M08_NOQAS;
```

Establece el tag:

```sql
ALTER SESSION SET QUERY_TAG = 'M08_E03_NOQAS';
```

Ejecuta exactamente esta consulta (puede tardar más de un minuto):

```sql
SELECT
    d.d_year AS year,
    i.i_brand_id AS brand_id,
    i.i_brand AS brand,
    SUM(s.ss_net_profit) AS profit

FROM SNOWFLAKE_SAMPLE_DATA
        .TPCDS_SF10TCL.DATE_DIM AS d

JOIN SNOWFLAKE_SAMPLE_DATA
        .TPCDS_SF10TCL.STORE_SALES AS s
    ON d.d_date_sk = s.ss_sold_date_sk

JOIN SNOWFLAKE_SAMPLE_DATA
        .TPCDS_SF10TCL.ITEM AS i
    ON s.ss_item_sk = i.i_item_sk

WHERE i.i_manufact_id = 939
  AND d.d_moy = 12

GROUP BY
    d.d_year,
    i.i_brand,
    i.i_brand_id

ORDER BY
    year,
    profit,
    brand_id

LIMIT 200;
```

### 7.1. Capturar inmediatamente el Query ID

Ejecuta la siguiente sentencia **antes de cualquier otro comando**:

```sql
SET QID_NOQAS = LAST_QUERY_ID();
```

Solo después cambia el tag:

```sql
ALTER SESSION SET QUERY_TAG = 'M08_E03_CAPTURA_ID';
```

Comprueba la variable:

```sql
SELECT $QID_NOQAS AS query_id_sin_qas;
```

> **Importante:** no cambies el tag antes de ejecutar `SET QID_NOQAS = LAST_QUERY_ID()`. De lo contrario, puedes terminar capturando el Query ID de un `ALTER SESSION` en vez del Query ID del `SELECT` analítico.

### 7.2. Validar que el Query ID es correcto

```sql
SELECT
    query_id,
    query_type,
    query_tag,
    warehouse_name,
    execution_status,
    ROUND(total_elapsed_time / 1000, 3)
        AS total_segundos,
    LEFT(query_text, 300)
        AS inicio_query_text

FROM TABLE(
    SNOWFLAKE.INFORMATION_SCHEMA.QUERY_HISTORY(
        END_TIME_RANGE_START =>
            DATEADD('hour', -1, CURRENT_TIMESTAMP()),

        END_TIME_RANGE_END =>
            CURRENT_TIMESTAMP(),

        RESULT_LIMIT => 1000
    )
)

WHERE query_id = $QID_NOQAS;
```

Debes comprobar:

```text
WAREHOUSE_NAME = WH_M08_NOQAS
QUERY_TAG = M08_E03_NOQAS
QUERY_TEXT contiene TPCDS_SF10TCL.STORE_SALES
TOTAL_SEGUNDOS corresponde a la consulta analítica
```

Si aparece un texto como:

```text
ALTER SESSION SET QUERY_TAG ...
```

el Query ID es incorrecto y no debe utilizarse en los pasos posteriores.

---

## 8. Estimar el beneficio potencial

Ejecuta:

```sql
SELECT
    PARSE_JSON(
        SYSTEM$ESTIMATE_QUERY_ACCELERATION(
            $QID_NOQAS
        )
    ) AS estimacion;
```

Proyección detallada:

```sql
WITH e AS (
    SELECT
        PARSE_JSON(
            SYSTEM$ESTIMATE_QUERY_ACCELERATION(
                $QID_NOQAS
            )
        ) AS j
)

SELECT
    j:status::VARCHAR
        AS status,

    j:ineligibleReason::VARCHAR
        AS motivo_no_elegible,

    j:originalQueryTime::FLOAT
        AS tiempo_original_segundos,

    j:upperLimitScaleFactor::NUMBER
        AS upper_limit_scale_factor,

    j:estimatedQueryTimes
        AS tiempos_estimados

FROM e;
```

### 8.1. Interpretar el resultado

| Estado | Interpretación |
|---|---|
| `eligible` | La consulta puede beneficiarse de QAS. |
| `ineligible` | Snowflake no considera que la consulta pueda beneficiarse en esa ejecución. |
| `accelerated` | El Query ID corresponde a una consulta que ya fue acelerada. |
| `invalid` | El Query ID no existe, no está disponible o queda fuera del periodo admitido. |

Si aparece:

```text
UNSUPPORTED_STATEMENT_TYPE
```

revisa primero el Query ID. Ese resultado suele indicar que se ha pasado al estimador una sentencia como `ALTER SESSION`, `SET` o una operación administrativa, no el `SELECT` analítico.

### 8.2. Puerta de decisión

#### Caso A: `eligible`

Continúa con la ejecución en el warehouse QAS.

Los tiempos estimados:

- Son orientativos.
- No constituyen un SLA.
- No contemplan concurrencia.
- Dependen del plan registrado y de los recursos disponibles.

El `upperLimitScaleFactor` indica el mayor factor incluido en la estimación, no una obligación de configurar ese valor.

En este laboratorio se mantiene un máximo de `8` para controlar el coste.

#### Caso B: `ineligible`

También puedes ejecutar la consulta en el warehouse con QAS para demostrar que habilitar el servicio no fuerza su utilización.

En ese caso, lo esperable es:

```text
QUERY_ACCELERATION_BYTES_SCANNED = 0
QUERY_ACCELERATION_PARTITIONS_SCANNED = 0
```

No debe atribuirse a QAS ninguna diferencia temporal entre las ejecuciones.

---

## 9. Ejecutar la consulta con QAS

Comprueba que el warehouse está suspendido antes de la prueba:

```sql
SHOW WAREHOUSES LIKE 'WH_M08_QAS';
```

Selecciona el warehouse:

```sql
USE WAREHOUSE WH_M08_QAS;
```

Establece el tag:

```sql
ALTER SESSION SET QUERY_TAG = 'M08_E03_QAS';
```

Ejecuta exactamente la misma consulta (tardará un poco más de 20 segundos):

```sql
SELECT
    d.d_year AS year,
    i.i_brand_id AS brand_id,
    i.i_brand AS brand,
    SUM(s.ss_net_profit) AS profit

FROM SNOWFLAKE_SAMPLE_DATA
        .TPCDS_SF10TCL.DATE_DIM AS d

JOIN SNOWFLAKE_SAMPLE_DATA
        .TPCDS_SF10TCL.STORE_SALES AS s
    ON d.d_date_sk = s.ss_sold_date_sk

JOIN SNOWFLAKE_SAMPLE_DATA
        .TPCDS_SF10TCL.ITEM AS i
    ON s.ss_item_sk = i.i_item_sk

WHERE i.i_manufact_id = 939
  AND d.d_moy = 12

GROUP BY
    d.d_year,
    i.i_brand,
    i.i_brand_id

ORDER BY
    year,
    profit,
    brand_id

LIMIT 200;
```

> La consulta puede terminar antes, igual o incluso más tarde debido a la variabilidad normal. La utilización de QAS debe verificarse mediante métricas, no inferirse únicamente por la duración.

### 9.1. Capturar inmediatamente el Query ID

Ejecuta antes de cualquier otro comando:

```sql
SET QID_QAS = LAST_QUERY_ID();
```

Después cambia el tag:

```sql
ALTER SESSION SET QUERY_TAG = 'M08_E03_CAPTURA_ID';
```

Comprueba:

```sql
SELECT
    $QID_NOQAS AS query_id_sin_qas,
    $QID_QAS AS query_id_con_qas;
```

### 9.2. Validar el Query ID

```sql
SELECT
    query_id,
    query_type,
    query_tag,
    warehouse_name,
    execution_status,
    ROUND(total_elapsed_time / 1000, 3)
        AS total_segundos,
    LEFT(query_text, 300)
        AS inicio_query_text

FROM TABLE(
    SNOWFLAKE.INFORMATION_SCHEMA.QUERY_HISTORY(
        END_TIME_RANGE_START =>
            DATEADD('hour', -1, CURRENT_TIMESTAMP()),

        END_TIME_RANGE_END =>
            CURRENT_TIMESTAMP(),

        RESULT_LIMIT => 1000
    )
)

WHERE query_id = $QID_QAS;
```

Debes comprobar:

```text
WAREHOUSE_NAME = WH_M08_QAS
QUERY_TAG = M08_E03_QAS
QUERY_TEXT contiene TPCDS_SF10TCL.STORE_SALES
```

---

## 10. Comparación inmediata mediante Information Schema

La función `SNOWFLAKE.INFORMATION_SCHEMA.QUERY_HISTORY` ofrece datos próximos a la ejecución, pero no contiene todas las columnas de la vista histórica de Account Usage.

Esta consulta utiliza únicamente columnas disponibles en la función:

```sql
SELECT
    query_id,
    query_type,
    query_tag,
    warehouse_name,
    warehouse_size,
    execution_status,

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
        COALESCE(bytes_scanned, 0)
        / POWER(1024, 3),
        3
    ) AS gb_warehouse,

    ROUND(
        COALESCE(
            query_acceleration_bytes_scanned,
            0
        )
        / POWER(1024, 3),
        3
    ) AS gb_qas,

    COALESCE(
        query_acceleration_partitions_scanned,
        0
    ) AS particiones_qas,

    COALESCE(
        query_acceleration_upper_limit_scale_factor,
        0
    ) AS upper_limit_scale_factor,

    CASE
        WHEN
            COALESCE(
                query_acceleration_bytes_scanned,
                0
            ) > 0

            OR

            COALESCE(
                query_acceleration_partitions_scanned,
                0
            ) > 0

        THEN 'QAS_UTILIZADO'
        ELSE 'QAS_NO_UTILIZADO'
    END AS uso_qas,

    start_time,
    end_time

FROM TABLE(
    SNOWFLAKE.INFORMATION_SCHEMA.QUERY_HISTORY(
        END_TIME_RANGE_START =>
            DATEADD('hour', -2, CURRENT_TIMESTAMP()),

        END_TIME_RANGE_END =>
            CURRENT_TIMESTAMP(),

        RESULT_LIMIT => 1000
    )
)

WHERE query_id IN (
    $QID_NOQAS,
    $QID_QAS
)

ORDER BY start_time;
```

### 10.1. Confirmar que QAS se utilizó

En la consulta ejecutada sobre `WH_M08_QAS`, debe cumplirse al menos una de estas condiciones:

```text
GB_QAS > 0
PARTICIONES_QAS > 0
```

Si ambas son cero:

```text
QAS_NO_UTILIZADO
```

En ese caso no puede afirmarse que la diferencia temporal haya sido causada por QAS.

### 10.2. Interpretar el upper limit

La columna:

```text
QUERY_ACCELERATION_UPPER_LIMIT_SCALE_FACTOR
```

no representa el scale factor realmente consumido.

Representa el límite superior del que la consulta podría haberse beneficiado según la información registrada por Snowflake.

Por eso el alias utilizado es:

```text
UPPER_LIMIT_SCALE_FACTOR
```

Y no:

```text
SCALE_FACTOR_OBSERVADO
```

---

## 11. Calcular la diferencia temporal

```sql
WITH metricas AS (
    SELECT
        query_id,
        total_elapsed_time,
        execution_time,
        COALESCE(
            query_acceleration_bytes_scanned,
            0
        ) AS qas_bytes,
        COALESCE(
            query_acceleration_partitions_scanned,
            0
        ) AS qas_partitions

    FROM TABLE(
        SNOWFLAKE.INFORMATION_SCHEMA.QUERY_HISTORY(
            END_TIME_RANGE_START =>
                DATEADD('hour', -2, CURRENT_TIMESTAMP()),

            END_TIME_RANGE_END =>
                CURRENT_TIMESTAMP(),

            RESULT_LIMIT => 1000
        )
    )

    WHERE query_id IN (
        $QID_NOQAS,
        $QID_QAS
    )
),

tiempos AS (
    SELECT
        MAX(
            IFF(
                query_id = $QID_NOQAS,
                total_elapsed_time,
                NULL
            )
        ) AS total_noqas_ms,

        MAX(
            IFF(
                query_id = $QID_QAS,
                total_elapsed_time,
                NULL
            )
        ) AS total_qas_ms,

        MAX(
            IFF(
                query_id = $QID_NOQAS,
                execution_time,
                NULL
            )
        ) AS ejecucion_noqas_ms,

        MAX(
            IFF(
                query_id = $QID_QAS,
                execution_time,
                NULL
            )
        ) AS ejecucion_qas_ms,

        MAX(
            IFF(
                query_id = $QID_QAS,
                qas_bytes,
                0
            )
        ) AS qas_bytes,

        MAX(
            IFF(
                query_id = $QID_QAS,
                qas_partitions,
                0
            )
        ) AS qas_partitions

    FROM metricas
)

SELECT
    ROUND(total_noqas_ms / 1000, 3)
        AS total_sin_qas_segundos,

    ROUND(total_qas_ms / 1000, 3)
        AS total_con_qas_segundos,

    ROUND(ejecucion_noqas_ms / 1000, 3)
        AS ejecucion_sin_qas_segundos,

    ROUND(ejecucion_qas_ms / 1000, 3)
        AS ejecucion_con_qas_segundos,

    ROUND(
        (
            total_noqas_ms - total_qas_ms
        )
        / NULLIF(total_noqas_ms, 0)
        * 100,
        2
    ) AS diferencia_total_porcentaje,

    qas_bytes,
    qas_partitions,

    CASE
        WHEN qas_bytes > 0
          OR qas_partitions > 0
        THEN 'HAY_EVIDENCIA_DE_USO_QAS'
        ELSE 'NO_ATRIBUIR_DIFERENCIA_A_QAS'
    END AS interpretacion

FROM tiempos;
```

### Interpretación correcta

La fórmula calcula una diferencia observada:

```text
(tiempo_sin_qas - tiempo_con_qas)
/ tiempo_sin_qas
× 100
```

Sin embargo:

- Si QAS no procesó bytes ni particiones, no se considera una aceleración atribuible a QAS.
- Una sola ejecución no elimina toda la variabilidad.
- El aprovisionamiento, las cachés y las condiciones internas pueden cambiar los tiempos.

---

## 12. Comparación histórica completa con Account Usage

La vista:

```text
SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
```

incluye métricas que no están disponibles en la función inmediata, como:

```text
PARTITIONS_SCANNED
PARTITIONS_TOTAL
PERCENTAGE_SCANNED_FROM_CACHE
```

Puede existir una latencia de hasta aproximadamente 45 minutos.

```sql
SELECT
    query_id,
    query_type,
    query_tag,
    warehouse_name,
    warehouse_size,
    execution_status,

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
        COALESCE(bytes_scanned, 0)
        / POWER(1024, 3),
        3
    ) AS gb_warehouse,

    partitions_scanned
        AS particiones_warehouse,

    partitions_total
        AS particiones_totales,

    ROUND(
        COALESCE(
            query_acceleration_bytes_scanned,
            0
        )
        / POWER(1024, 3),
        3
    ) AS gb_qas,

    COALESCE(
        query_acceleration_partitions_scanned,
        0
    ) AS particiones_qas,

    COALESCE(
        query_acceleration_upper_limit_scale_factor,
        0
    ) AS upper_limit_scale_factor,

    ROUND(
        COALESCE(
            percentage_scanned_from_cache,
            0
        ) * 100,
        2
    ) AS porcentaje_cache_local,

    start_time,
    end_time

FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY

WHERE query_id IN (
    $QID_NOQAS,
    $QID_QAS
)

  AND start_time >=
      DATEADD('hour', -6, CURRENT_TIMESTAMP())

ORDER BY start_time;
```

### Si todavía no aparecen filas

No repitas innecesariamente las consultas analíticas.

Conserva los Query ID y vuelve a ejecutar esta consulta después.

---

## 13. Interpretar bytes y particiones

No debe calcularse un supuesto porcentaje acelerado mediante:

```text
particiones_qas
/
(particiones_warehouse + particiones_qas)
```

Snowflake puede generar resultados intermedios para paralelizar el trabajo. Por ello, al utilizar QAS, la suma de bytes o particiones del warehouse y del servicio puede ser superior a la observada sin QAS.

Por tanto:

- Más bytes totales no implica necesariamente peor rendimiento.
- Los bytes y particiones QAS demuestran trabajo descargado.
- El tiempo indica el resultado de rendimiento.
- Los créditos determinan el coste adicional.
- La decisión debe considerar el SLA y la frecuencia.

---

## 14. Inspeccionar Query Profile

Abre Query Profile para el Query ID almacenado en:

```text
QID_QAS
```

### 14.1. Caso A: QAS fue utilizado

Condición:

```text
QUERY_ACCELERATION_BYTES_SCANNED > 0
```

O:

```text
QUERY_ACCELERATION_PARTITIONS_SCANNED > 0
```

En Query Profile localiza:

- La sección **Query Acceleration** del resumen.
- `Partitions scanned by service`.
- `Scans selected for acceleration`.
- Los operadores `TableScan` afectados.
- La tabla o tablas cuyos scans fueron descargados.

Registra:

| Evidencia | Valor observado |
|---|---:|
| Scans seleccionados para aceleración | |
| Particiones escaneadas por el servicio | |
| Operadores `TableScan` afectados | |
| Tablas afectadas | |
| Operador más costoso | |

Explica qué parte del plan siguió ejecutando el warehouse:

- Compilación.
- Coordinación.
- Joins no descargados.
- Agregaciones no descargadas.
- Ordenación.
- Entrega del resultado.

### 14.2. Caso B: QAS no fue utilizado

Condición:

```text
QUERY_ACCELERATION_BYTES_SCANNED = 0
AND
QUERY_ACCELERATION_PARTITIONS_SCANNED = 0
```

Documenta:

```text
El warehouse tenía QAS habilitado, pero el servicio no participó
materialmente en la ejecución. No puede atribuirse a QAS ninguna
diferencia temporal observada.
```

Query Profile puede no mostrar una sección de aceleración relevante o puede mostrar cero trabajo descargado.

Este resultado es válido y demuestra que habilitar QAS no obliga a Snowflake a utilizarlo.

---

## 15. Medir el consumo principal antes de la consulta de control

La consulta de control se ejecutará más adelante para no contaminar innecesariamente la comparación del workload principal.

Aun así, recuerda que el metering del warehouse es agregado por intervalo y puede incluir:

- La reanudación.
- El mínimo de facturación.
- Tiempo activo sin ejecutar consultas.
- Consultas auxiliares que usaron el warehouse.
- Otras sesiones.

Los warehouses dedicados reducen este problema, pero no convierten automáticamente el dato horario en coste exacto por consulta.

---

## 16. Consultar el consumo de los warehouses

### 16.1. Warehouse sin QAS

```sql
SELECT
    start_time,
    end_time,
    warehouse_name,
    credits_used,
    credits_used_compute,
    credits_used_cloud_services

FROM TABLE(
    SNOWFLAKE.INFORMATION_SCHEMA
        .WAREHOUSE_METERING_HISTORY(
            DATE_RANGE_START =>
                DATEADD(
                    'hour',
                    -3,
                    CURRENT_TIMESTAMP()
                ),

            DATE_RANGE_END =>
                CURRENT_TIMESTAMP(),

            WAREHOUSE_NAME =>
                'WH_M08_NOQAS'
        )
)

ORDER BY start_time;
```

### 16.2. Warehouse con QAS

```sql
SELECT
    start_time,
    end_time,
    warehouse_name,
    credits_used,
    credits_used_compute,
    credits_used_cloud_services

FROM TABLE(
    SNOWFLAKE.INFORMATION_SCHEMA
        .WAREHOUSE_METERING_HISTORY(
            DATE_RANGE_START =>
                DATEADD(
                    'hour',
                    -3,
                    CURRENT_TIMESTAMP()
                ),

            DATE_RANGE_END =>
                CURRENT_TIMESTAMP(),

            WAREHOUSE_NAME =>
                'WH_M08_QAS'
        )
)

ORDER BY start_time;
```

### 16.3. Evitar doble conteo

`CREDITS_USED` ya representa:

```text
CREDITS_USED_COMPUTE
+
CREDITS_USED_CLOUD_SERVICES
```

No calcules:

```text
CREDITS_USED
+ CREDITS_USED_COMPUTE
+ CREDITS_USED_CLOUD_SERVICES
```

porque duplicaría el consumo.

---

## 17. Consultar el consumo de QAS

```sql
SELECT
    start_time,
    end_time,
    warehouse_name,
    credits_used,
    num_files_scanned,
    num_bytes_scanned

FROM TABLE(
    SNOWFLAKE.INFORMATION_SCHEMA
        .QUERY_ACCELERATION_HISTORY(
            DATE_RANGE_START =>
                DATEADD(
                    'hour',
                    -3,
                    CURRENT_TIMESTAMP()
                ),

            DATE_RANGE_END =>
                CURRENT_TIMESTAMP(),

            WAREHOUSE_NAME =>
                'WH_M08_QAS'
        )
)

ORDER BY start_time;
```

Los créditos QAS son adicionales:

```text
coste total alternativa QAS
=
créditos warehouse
+
créditos QAS
```

### Si no aparece inmediatamente

No repitas la consulta analítica para intentar forzar una fila.

Comprueba primero las métricas inmediatas:

```text
QUERY_ACCELERATION_BYTES_SCANNED
QUERY_ACCELERATION_PARTITIONS_SCANNED
```

Conserva:

```text
QID_QAS
QUERY_TAG
hora de ejecución
```

Y vuelve a consultar el metering posteriormente.

Si las métricas QAS son cero, es coherente que no haya créditos QAS.

---

## 18. Informe agregado del laboratorio

```sql
WITH warehouse_cost AS (
    SELECT
        warehouse_name,
        SUM(credits_used)
            AS warehouse_credits

    FROM TABLE(
        SNOWFLAKE.INFORMATION_SCHEMA
            .WAREHOUSE_METERING_HISTORY(
                DATE_RANGE_START =>
                    DATEADD(
                        'hour',
                        -3,
                        CURRENT_TIMESTAMP()
                    ),

                DATE_RANGE_END =>
                    CURRENT_TIMESTAMP()
            )
    )

    WHERE warehouse_name IN (
        'WH_M08_NOQAS',
        'WH_M08_QAS'
    )

    GROUP BY warehouse_name
),

qas_cost AS (
    SELECT
        warehouse_name,
        SUM(credits_used)
            AS qas_credits

    FROM TABLE(
        SNOWFLAKE.INFORMATION_SCHEMA
            .QUERY_ACCELERATION_HISTORY(
                DATE_RANGE_START =>
                    DATEADD(
                        'hour',
                        -3,
                        CURRENT_TIMESTAMP()
                    ),

                DATE_RANGE_END =>
                    CURRENT_TIMESTAMP()
            )
    )

    WHERE warehouse_name = 'WH_M08_QAS'

    GROUP BY warehouse_name
)

SELECT
    w.warehouse_name,
    w.warehouse_credits,

    COALESCE(
        q.qas_credits,
        0
    ) AS qas_credits,

    w.warehouse_credits
    + COALESCE(
        q.qas_credits,
        0
    ) AS creditos_totales

FROM warehouse_cost AS w

LEFT JOIN qas_cost AS q
    ON q.warehouse_name = w.warehouse_name

ORDER BY w.warehouse_name;
```

### Precisión del informe

Este informe es razonable para un laboratorio con warehouses dedicados, pero no equivale necesariamente al coste exacto de cada consulta.

Puede incluir:

- Idle time.
- Mínimos de facturación.
- Consultas auxiliares.
- Variación en la hora de inicio y suspensión.

La atribución histórica por Query ID se analizará más adelante.

---

## 19. Ejecutar una consulta de control no candidata

Ahora ejecuta la consulta pequeña de control.

```sql
USE WAREHOUSE WH_M08_QAS;
```

```sql
ALTER SESSION SET QUERY_TAG = 'M08_E03_QAS_CONTROL';
```

```sql
SELECT *
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
WHERE O_ORDERKEY = 12345;
```

Captura inmediatamente el Query ID:

```sql
SET QID_CONTROL = LAST_QUERY_ID();
```

Después cambia el tag:

```sql
ALTER SESSION SET QUERY_TAG = 'M08_E03_CAPTURA_ID';
```

Comprueba:

```sql
SELECT $QID_CONTROL AS query_id_control;
```

### 19.1. Validar la consulta de control

```sql
SELECT
    query_id,
    query_type,
    query_tag,
    warehouse_name,
    ROUND(total_elapsed_time / 1000, 3)
        AS total_segundos,
    LEFT(query_text, 300)
        AS inicio_query_text

FROM TABLE(
    SNOWFLAKE.INFORMATION_SCHEMA.QUERY_HISTORY(
        END_TIME_RANGE_START =>
            DATEADD('hour', -1, CURRENT_TIMESTAMP()),

        END_TIME_RANGE_END =>
            CURRENT_TIMESTAMP(),

        RESULT_LIMIT => 1000
    )
)

WHERE query_id = $QID_CONTROL;
```

### 19.2. Estimar su elegibilidad

```sql
WITH e AS (
    SELECT
        PARSE_JSON(
            SYSTEM$ESTIMATE_QUERY_ACCELERATION(
                $QID_CONTROL
            )
        ) AS j
)

SELECT
    j:status::VARCHAR
        AS status,

    j:ineligibleReason::VARCHAR
        AS motivo_no_elegible,

    j:originalQueryTime::FLOAT
        AS tiempo_original_segundos,

    j:upperLimitScaleFactor::NUMBER
        AS upper_limit_scale_factor,

    j:estimatedQueryTimes
        AS tiempos_estimados

FROM e;
```

### 19.3. Comprobar métricas QAS

```sql
SELECT
    query_id,
    query_tag,
    warehouse_name,
    ROUND(total_elapsed_time / 1000, 3)
        AS total_segundos,
    bytes_scanned,
    COALESCE(
        query_acceleration_bytes_scanned,
        0
    ) AS qas_bytes,
    COALESCE(
        query_acceleration_partitions_scanned,
        0
    ) AS qas_partitions

FROM TABLE(
    SNOWFLAKE.INFORMATION_SCHEMA.QUERY_HISTORY(
        END_TIME_RANGE_START =>
            DATEADD('hour', -1, CURRENT_TIMESTAMP()),

        END_TIME_RANGE_END =>
            CURRENT_TIMESTAMP(),

        RESULT_LIMIT => 1000
    )
)

WHERE query_id = $QID_CONTROL;
```

Resultado esperado conceptualmente:

```text
STATUS = ineligible
QAS_BYTES = 0
QAS_PARTITIONS = 0
```

QAS no cobra simplemente por estar habilitado. Debe participar realmente en una consulta elegible.

> La consulta de control ya puede aparecer en el metering posterior del warehouse. Para el coste principal del experimento utiliza las mediciones realizadas antes de este paso o la atribución histórica por Query ID.

---

## 20. Consultar vistas históricas

### 20.1. Consultas elegibles no aceleradas

```sql
SELECT
    query_id,
    query_text,
    warehouse_name,
    warehouse_size,
    eligible_query_acceleration_time,
    upper_limit_scale_factor,
    start_time,
    end_time

FROM SNOWFLAKE.ACCOUNT_USAGE
        .QUERY_ACCELERATION_ELIGIBLE

WHERE start_time >=
    DATEADD(
        'day',
        -7,
        CURRENT_TIMESTAMP()
    )

ORDER BY
    eligible_query_acceleration_time DESC;
```

Latencia aproximada:

```text
hasta 3 horas
```

Esta vista contiene consultas elegibles que no fueron aceleradas.

### 20.2. Créditos QAS históricos

```sql
SELECT
    warehouse_name,
    SUM(credits_used)
        AS qas_credits

FROM SNOWFLAKE.ACCOUNT_USAGE
        .QUERY_ACCELERATION_HISTORY

WHERE start_time >=
    DATEADD(
        'day',
        -7,
        CURRENT_TIMESTAMP()
    )

GROUP BY warehouse_name

ORDER BY qas_credits DESC;
```

Latencia aproximada:

```text
hasta 3 horas
```

### 20.3. Coste atribuido por consulta

```sql
SELECT
    query_id,
    query_tag,
    warehouse_name,
    credits_attributed_compute,
    credits_used_query_acceleration,

    credits_attributed_compute
    + COALESCE(
        credits_used_query_acceleration,
        0
    ) AS creditos_atribuidos_totales,

    start_time,
    end_time

FROM SNOWFLAKE.ACCOUNT_USAGE
        .QUERY_ATTRIBUTION_HISTORY

WHERE query_id IN (
    $QID_NOQAS,
    $QID_QAS,
    $QID_CONTROL
)

ORDER BY start_time;
```

Latencia aproximada:

```text
hasta 8 horas
```

`CREDITS_ATTRIBUTED_COMPUTE`:

- Atribuye compute de ejecución.
- Excluye idle time.
- No incluye por sí solo los créditos QAS.

La columna:

```text
CREDITS_USED_QUERY_ACCELERATION
```

permite añadir el coste QAS atribuido a la consulta.

### 20.4. Warehouse metering histórico

```sql
SELECT
    warehouse_name,

    SUM(credits_used)
        AS credits_used,

    SUM(credits_used_compute)
        AS compute_credits,

    SUM(credits_used_cloud_services)
        AS cloud_services_credits,

    SUM(credits_attributed_compute_queries)
        AS attributed_query_compute

FROM SNOWFLAKE.ACCOUNT_USAGE
        .WAREHOUSE_METERING_HISTORY

WHERE start_time >=
    DATEADD(
        'day',
        -7,
        CURRENT_TIMESTAMP()
    )

  AND warehouse_name IN (
      'WH_M08_NOQAS',
      'WH_M08_QAS'
  )

GROUP BY warehouse_name;
```

Latencia aproximada:

```text
hasta 3 horas
Cloud Services puede tardar más, aproximadamente hasta 6 horas
```

### Resumen de latencias

| Fuente | Latencia máxima aproximada |
|---|---:|
| `ACCOUNT_USAGE.QUERY_HISTORY` | 45 minutos |
| `QUERY_ACCELERATION_ELIGIBLE` | 3 horas |
| `QUERY_ACCELERATION_HISTORY` | 3 horas |
| `QUERY_ATTRIBUTION_HISTORY` | 8 horas |
| `WAREHOUSE_METERING_HISTORY` | 3 horas; Cloud Services hasta 6 |

No es obligatorio esperar a que todas las vistas se actualicen durante la sesión del curso.

---

## 21. Elaborar la recomendación FinOps

Completa:

| Criterio | Sin QAS | Con QAS |
|---|---:|---:|
| Tiempo total | | |
| Tiempo de ejecución | | |
| Créditos warehouse | | |
| Créditos QAS | 0 | |
| Coste total estimado | | |
| Bytes QAS | 0 | |
| Particiones QAS | 0 | |
| Diferencia temporal | 0 % | |
| Evidencia de uso QAS | No | Sí / No |

### Preguntas

1. ¿Snowflake clasificó la consulta como `eligible`, `ineligible` o `accelerated`?
2. ¿QAS procesó realmente bytes o particiones?
3. ¿La consulta con QAS terminó antes?
4. ¿Puede atribuirse esa diferencia a QAS?
5. ¿Cuántos segundos absolutos se ahorraron?
6. ¿Cuántos créditos adicionales se consumieron?
7. ¿La consulta se ejecuta una vez al mes, una vez al día o cientos de veces?
8. ¿El SLA justifica el coste?
9. ¿Sería mejor redimensionar temporalmente el warehouse?
10. ¿Sería mejor optimizar SQL, pruning, clustering o el modelo de datos?
11. ¿Dejarías QAS activo para todo el warehouse?
12. ¿Qué scale factor máximo utilizarías?
13. ¿Qué Budget o alerta configurarías?

### Regla principal

No apruebes QAS únicamente porque:

```text
la consulta con QAS terminó antes
```

Debe existir evidencia de uso real:

```text
QAS bytes > 0
O
QAS partitions > 0
```

Y el beneficio debe justificar el coste según la frecuencia del workload.

### Ejemplo de proyección

Si una consulta consume:

```text
0,05 créditos adicionales de QAS
```

Y se ejecuta:

```text
200 veces al día
```

El coste mensual aproximado sería:

```text
0,05 × 200 × 30
= 300 créditos
```

La frecuencia puede cambiar completamente la recomendación.

---

## 22. Alternativas que deben evaluarse

Antes de activar QAS de forma general, considera:

- Optimizar el SQL.
- Mejorar el pruning.
- Revisar clustering.
- Search Optimization Service.
- Materialized views.
- Dynamic Tables.
- Tablas agregadas.
- Separar los outliers en un warehouse dedicado.
- Aumentar temporalmente el tamaño del warehouse.
- Revisar el patrón de acceso y el modelo de datos.

QAS no sustituye una arquitectura adecuada.

---

## 23. Cuándo recomendar QAS

### Buen candidato

- Consulta pesada y ocasional.
- Escaneo grande.
- Filtro suficientemente selectivo.
- Workload mixto con outliers.
- Elegibilidad confirmada.
- Evidencia real de bytes o particiones QAS.
- Mejora relevante para el SLA.
- Coste adicional aceptable.

### Mal candidato

- Consulta corta.
- Point lookup.
- Consulta declarada `ineligible`.
- Problema principalmente de concurrencia.
- SQL claramente ineficiente.
- Pruning deficiente y corregible.
- Consulta ejecutada constantemente que debería resolverse con una tabla agregada.
- Mejora pequeña frente al coste.

---

## 24. Política de adopción propuesta

### Paso 1. Detectar

Utilizar:

- Query History.
- Query Profile.
- Query tags.
- Outliers de ejecución.
- `QUERY_ACCELERATION_ELIGIBLE`.

### Paso 2. Validar el Query ID

Comprobar:

- `QUERY_TYPE`.
- `QUERY_TEXT`.
- Warehouse.
- Tag.
- Duración.

### Paso 3. Estimar

```text
SYSTEM$ESTIMATE_QUERY_ACCELERATION
```

Registrar:

- `status`.
- `ineligibleReason`.
- `upperLimitScaleFactor`.
- `estimatedQueryTimes`.

### Paso 4. Aislar

Crear dos warehouses comparables.

### Paso 5. Probar

- Misma consulta.
- Result cache desactivada.
- Cachés locales separadas.
- Condiciones documentadas.

### Paso 6. Verificar uso real

Comprobar:

```text
QUERY_ACCELERATION_BYTES_SCANNED
QUERY_ACCELERATION_PARTITIONS_SCANNED
```

### Paso 7. Medir

- Tiempo total.
- Tiempo de ejecución.
- Bytes y particiones QAS.
- Créditos warehouse.
- Créditos QAS.

### Paso 8. Limitar

Seleccionar un scale factor máximo prudente.

### Paso 9. Monitorizar

- Query Acceleration History.
- Query Attribution History.
- Budgets.
- Alertas de anomalía.
- Query tags.

### Paso 10. Revisar

Retirar QAS cuando:

- Deja de utilizarse.
- Las consultas dejan de ser elegibles.
- El SQL se optimiza.
- El coste supera el beneficio.
- El workload migra a una tabla agregada.
- El warehouse cambia de función.

---

## 25. Restaurar la sesión y suspender recursos

Restaura la sesión:

```sql
ALTER SESSION UNSET USE_CACHED_RESULT;
```

```sql
ALTER SESSION UNSET QUERY_TAG;
```

Suspende ambos warehouses:

```sql
ALTER WAREHOUSE WH_M08_NOQAS SUSPEND;
ALTER WAREHOUSE WH_M08_QAS SUSPEND;
```

Comprueba:

```sql
SHOW WAREHOUSES LIKE 'WH_M08_%'
->>
SELECT
    "name",
    "state",
    "size",
    "generation",
    "enable_query_acceleration",
    "query_acceleration_max_scale_factor"
FROM $1
WHERE "name" IN (
    'WH_M08_NOQAS',
    'WH_M08_QAS'
)
ORDER BY "name";
```

Cuando ya no necesites esperar al histórico:

```sql
DROP WAREHOUSE IF EXISTS WH_M08_NOQAS;
DROP WAREHOUSE IF EXISTS WH_M08_QAS;
```

---

## 26. Errores frecuentes

### 26.1. `UNSUPPORTED_STATEMENT_TYPE`

Causa probable:

```text
El Query ID corresponde a ALTER SESSION, SET u otra sentencia administrativa.
```

Comprueba:

```sql
SELECT
    query_id,
    query_type,
    query_text
FROM TABLE(
    SNOWFLAKE.INFORMATION_SCHEMA.QUERY_HISTORY(
        END_TIME_RANGE_START =>
            DATEADD('hour', -1, CURRENT_TIMESTAMP()),
        RESULT_LIMIT => 1000
    )
)
WHERE query_id = $QID_NOQAS;
```

Solución:

```sql
-- Inmediatamente después del SELECT analítico:
SET QID_NOQAS = LAST_QUERY_ID();
```

No ejecutes otra sentencia entre la consulta y la captura.

---

### 26.2. `invalid identifier 'PARTITIONS_SCANNED'`

Causa:

```text
PARTITIONS_SCANNED no pertenece a la salida de la función
INFORMATION_SCHEMA.QUERY_HISTORY.
```

Utiliza:

```text
SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
```

cuando el histórico esté disponible.

La misma consideración se aplica a:

```text
PARTITIONS_TOTAL
PERCENTAGE_SCANNED_FROM_CACHE
```

---

### 26.3. La consulta es `ineligible`

No implica necesariamente una configuración incorrecta.

Revisa:

- `ineligibleReason`.
- Query ID correcto.
- Tipo de sentencia.
- Duración.
- Tamaño del scan.
- Plan actual generado por Snowflake.

Si el motivo es real, QAS no debería utilizarse para esa ejecución.

---

### 26.4. QAS está habilitado, pero las métricas son cero

Comprueba:

- Query ID correcto.
- `ENABLE_QUERY_ACCELERATION = TRUE`.
- Consulta exacta.
- Resultado del estimador.
- Query Profile.

Si el Query ID es correcto y las métricas siguen en cero, QAS no participó en esa ejecución.

---

### 26.5. El segundo resultado aparece instantáneamente

Comprueba:

```sql
SHOW PARAMETERS LIKE 'USE_CACHED_RESULT'
IN SESSION;
```

Debe aparecer:

```text
FALSE
```

---

### 26.6. `QUERY_ACCELERATION_HISTORY` no devuelve filas

Puede existir latencia o no haberse utilizado QAS.

Comprueba primero:

```text
QUERY_ACCELERATION_BYTES_SCANNED > 0
O
QUERY_ACCELERATION_PARTITIONS_SCANNED > 0
```

---

### 26.7. Los créditos parecen demasiado altos

Comprueba que no has sumado:

```text
CREDITS_USED
+ CREDITS_USED_COMPUTE
+ CREDITS_USED_CLOUD_SERVICES
```

`CREDITS_USED` ya contiene las otras dos componentes.

---

### 26.8. Account Usage devuelve error de permisos

Con `ACCOUNTADMIN`, concede:

```sql
GRANT DATABASE ROLE SNOWFLAKE.GOVERNANCE_VIEWER
TO ROLE SYSADMIN;
```

```sql
GRANT DATABASE ROLE SNOWFLAKE.USAGE_VIEWER
TO ROLE SYSADMIN;
```

---

### 26.9. Account Usage todavía no muestra las consultas

Latencias aproximadas:

```text
QUERY_HISTORY: hasta 45 minutos
QUERY_ACCELERATION_ELIGIBLE: hasta 3 horas
QUERY_ACCELERATION_HISTORY: hasta 3 horas
QUERY_ATTRIBUTION_HISTORY: hasta 8 horas
```

No repitas consultas costosas solo para acelerar la aparición de metadatos.

---

### 26.10. La consulta de control aumenta el coste del warehouse QAS

Si el warehouse ya se había suspendido, la consulta de control puede reanudarlo y añadir consumo.

Por eso la medición principal se realiza antes de la consulta de control.

Para una atribución posterior más precisa utiliza:

```text
QUERY_ATTRIBUTION_HISTORY
```

filtrando por Query ID o Query Tag.

---

## 27. Respuestas a las preguntas de reflexión

### 1. ¿Por qué QAS puede ser eficiente?

Porque puede utilizarse únicamente para las partes elegibles de consultas concretas, en vez de mantener permanentemente un warehouse mayor.

### 2. ¿Por qué no acelera cualquier consulta?

Solo determinadas partes del plan pueden descargarse y Snowflake debe considerar que existe suficiente beneficio potencial.

### 3. ¿Qué es el scale factor?

Es un límite sobre la tasa de recursos serverless que QAS puede utilizar en relación con el warehouse.

### 4. ¿Por qué 8 no significa consumo constante de 8?

Porque es un máximo, no una reserva fija. QAS utiliza los recursos necesarios y disponibles hasta ese límite.

### 5. ¿Qué riesgo tiene el factor 0?

Elimina el límite superior y puede aumentar significativamente el coste para priorizar rendimiento.

### 6. ¿Por qué pueden aumentar los bytes?

QAS puede generar resultados intermedios para facilitar la paralelización.

### 7. ¿Por qué se suman QAS y warehouse?

Son servicios facturados por separado que participan en la misma consulta.

### 8. ¿Qué diferencia existe entre estimación y medición?

La estimación predice un posible beneficio. Las métricas de Query History, Query Profile y metering registran lo ocurrido realmente.

### 9. ¿Por qué es importante `QUERY_TAG`?

Permite agrupar y atribuir consultas por aplicación, departamento, laboratorio o experimento.

### 10. ¿Qué debe optimizarse primero?

SQL, filtros, pruning, clustering, agregaciones y diseño del workload. QAS no sustituye una buena arquitectura.

### 11. ¿Un tiempo menor demuestra que QAS se utilizó?

No. Debe existir evidencia mediante bytes o particiones QAS mayores que cero.

### 12. ¿Qué demuestra un estado `UNSUPPORTED_STATEMENT_TYPE`?

Que el Query ID suministrado corresponde a un tipo de sentencia no compatible con el estimador. Debe revisarse la captura del identificador.

---

## 29. Referencias oficiales

- [Tutorial: Improve Workload Performance with the Query Acceleration Service](https://docs.snowflake.com/en/user-guide/tutorials/query-acceleration-service)
- [Using the Query Acceleration Service](https://docs.snowflake.com/en/user-guide/query-acceleration-service)
- [`SYSTEM$ESTIMATE_QUERY_ACCELERATION`](https://docs.snowflake.com/en/sql-reference/functions/system_estimate_query_acceleration)
- [`LAST_QUERY_ID`](https://docs.snowflake.com/en/sql-reference/functions/last_query_id)
- [`QUERY_HISTORY` — Information Schema table functions](https://docs.snowflake.com/en/sql-reference/functions/query_history)
- [`QUERY_HISTORY` — Account Usage view](https://docs.snowflake.com/en/sql-reference/account-usage/query_history)
- [`QUERY_ACCELERATION_HISTORY` — Information Schema](https://docs.snowflake.com/en/sql-reference/functions/query_acceleration_history)
- [`QUERY_ACCELERATION_HISTORY` — Account Usage](https://docs.snowflake.com/en/sql-reference/account-usage/query_acceleration_history)
- [`QUERY_ACCELERATION_ELIGIBLE`](https://docs.snowflake.com/en/sql-reference/account-usage/query_acceleration_eligible)
- [`QUERY_ATTRIBUTION_HISTORY`](https://docs.snowflake.com/en/sql-reference/account-usage/query_attribution_history)
- [`WAREHOUSE_METERING_HISTORY`](https://docs.snowflake.com/en/sql-reference/account-usage/warehouse_metering_history)
- [SNOWFLAKE database roles](https://docs.snowflake.com/en/sql-reference/snowflake-db-roles)
- [`CREATE WAREHOUSE`](https://docs.snowflake.com/en/sql-reference/sql/create-warehouse)


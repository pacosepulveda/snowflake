# Módulo 8 · Ejercicio 2

## Solución guiada: multi-cluster warehouses y Resource Monitors

---

## 1. Arquitectura del laboratorio

Realizaremos tres pruebas:

```text
Fase 1
XSMALL · 1 clúster · MAX_CONCURRENCY_LEVEL = 1

Fase 2
XSMALL · auto-scale 1-2 clústeres · STANDARD

Fase 3
XSMALL · auto-scale 1-2 clústeres · ECONOMY
```

Después crearemos:

```text
RM_M08_CONC
        ↓
WH_M08_CONC
```

La finalidad no es obtener un tiempo exacto, sino reconocer:

- Cola.
- Aprovisionamiento.
- Escalado horizontal.
- Diferencia entre políticas.
- Riesgo económico.

---

## 2. Preparar los ficheros de Workspaces

Crea:

```text
M08_E02_CONCURRENCIA_RM.sql
M08_E02_Q1.sql
M08_E02_Q2.sql
M08_E02_Q3.sql
M08_E02_Q4.sql
M08_E02_MONITOR.sql
```

En el fichero principal:

```sql
USE ROLE SYSADMIN;

CREATE DATABASE IF NOT EXISTS DB_CURSO;
CREATE SCHEMA IF NOT EXISTS DB_CURSO.PERFORMANCE;

USE DATABASE DB_CURSO;
USE SCHEMA PERFORMANCE;

ALTER SESSION SET QUERY_TAG = 'M08_E02_PREPARACION';
```

---

## 3. Comprobar la tabla del ejercicio anterior

```sql
SHOW TABLES LIKE 'VENTAS_RENDIMIENTO'
IN SCHEMA DB_CURSO.PERFORMANCE;
```

Comprueba:

```sql
SELECT
    COUNT(*) AS filas,
    MIN(fecha) AS fecha_minima,
    MAX(fecha) AS fecha_maxima
FROM DB_CURSO.PERFORMANCE.VENTAS_RENDIMIENTO;
```

Resultado esperado:

```text
10.000.000 de filas
2025-01-01 a 2025-12-31
```

### Recuperación si la tabla no existe

Crea primero un warehouse temporal o utiliza `WH_M08_XS` del ejercicio anterior.

```sql
CREATE WAREHOUSE IF NOT EXISTS WH_M08_XS
    WAREHOUSE_TYPE = STANDARD
    WAREHOUSE_SIZE = XSMALL
    GENERATION = '1'
    MIN_CLUSTER_COUNT = 1
    MAX_CLUSTER_COUNT = 1
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE
    ENABLE_QUERY_ACCELERATION = FALSE;
```

```sql
USE WAREHOUSE WH_M08_XS;
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
    (n + 1)::NUMBER(18,0) AS id_venta,

    DATEADD(
        'day',
        MOD(n, 365),
        '2025-01-01'::DATE
    )::DATE AS fecha,

    CASE MOD(n, 5)
        WHEN 0 THEN 'NORTE'
        WHEN 1 THEN 'SUR'
        WHEN 2 THEN 'ESTE'
        WHEN 3 THEN 'OESTE'
        ELSE 'CENTRO'
    END::VARCHAR(10) AS region,

    CASE MOD(n, 3)
        WHEN 0 THEN 'WEB'
        WHEN 1 THEN 'TIENDA'
        ELSE 'MARKETPLACE'
    END::VARCHAR(20) AS canal,

    (MOD(n * 13, 500000) + 1)::NUMBER(18,0)
        AS id_cliente,

    (MOD(n * 17, 50000) + 1)::NUMBER(18,0)
        AS id_producto,

    (
        5 + MOD(n * 97, 100000) / 100
    )::NUMBER(12,2) AS importe,

    (
        MOD(n * 19, 2500) / 100
    )::NUMBER(12,2) AS descuento,

    CASE MOD(n, 10)
        WHEN 0 THEN 'CANCELADA'
        WHEN 1 THEN 'PENDIENTE'
        ELSE 'COMPLETADA'
    END::VARCHAR(20) AS estado

FROM base;
```

Suspende el warehouse auxiliar:

```sql
ALTER WAREHOUSE WH_M08_XS SUSPEND;
```

---

## 4. Crear el warehouse de concurrencia

```sql
CREATE OR REPLACE WAREHOUSE WH_M08_CONC
    WAREHOUSE_TYPE = STANDARD
    WAREHOUSE_SIZE = XSMALL
    GENERATION = '1'
    MIN_CLUSTER_COUNT = 1
    MAX_CLUSTER_COUNT = 1
    SCALING_POLICY = STANDARD
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE
    ENABLE_QUERY_ACCELERATION = FALSE
    MAX_CONCURRENCY_LEVEL = 1
    STATEMENT_QUEUED_TIMEOUT_IN_SECONDS = 300
    STATEMENT_TIMEOUT_IN_SECONDS = 600
    COMMENT = 'M08 laboratorio de concurrencia';
```

### Por qué se fija Gen1

Permite utilizar una escala de créditos conocida:

```text
XSMALL = 1 crédito por hora por clúster
```

### Por qué se desactiva QAS

Desde junio de 2026, QAS se habilita de forma predeterminada en warehouses multi-cluster recién creados.

En este ejercicio queremos medir el efecto de los clústeres, no recursos serverless de QAS.

Aunque inicialmente el objeto es single-cluster, se declara explícitamente:

```sql
ENABLE_QUERY_ACCELERATION = FALSE
```

---

## 5. Inspeccionar la configuración

```sql
SHOW WAREHOUSES LIKE 'WH_M08_CONC'
->>
SELECT
    "name",
    "state",
    "size",
    "generation",
    "min_cluster_count",
    "max_cluster_count",
    "started_clusters",
    "running",
    "queued",
    "scaling_policy",
    "enable_query_acceleration",
    "resource_monitor"
FROM $1;
```

Parámetros:

```sql
SHOW PARAMETERS LIKE 'MAX_CONCURRENCY_LEVEL'
IN WAREHOUSE WH_M08_CONC;
```

```sql
SHOW PARAMETERS
IN WAREHOUSE WH_M08_CONC
->>
SELECT
    "key",
    "value",
    "default",
    "level"
FROM $1
WHERE "key" IN (
    'MAX_CONCURRENCY_LEVEL',
    'STATEMENT_QUEUED_TIMEOUT_IN_SECONDS',
    'STATEMENT_TIMEOUT_IN_SECONDS'
)
ORDER BY "key";
```

Resultado esperado:

```text
MAX_CLUSTER_COUNT = 1
MAX_CONCURRENCY_LEVEL = 1
QAS = FALSE
```

---

## 6. Crear la view de carga

```sql
CREATE OR REPLACE VIEW
    DB_CURSO.PERFORMANCE.V_CARGA_CONCURRENCIA
AS

WITH ventas_cliente AS (
    SELECT
        DATE_TRUNC('MONTH', fecha)::DATE AS mes,
        region,
        canal,
        id_cliente,

        COUNT(*) AS num_ventas,

        SUM(
            importe - descuento
        )::NUMBER(20,2) AS importe_neto,

        APPROX_PERCENTILE(
            importe - descuento,
            0.95
        )::NUMBER(20,2) AS p95_ticket

    FROM DB_CURSO.PERFORMANCE.VENTAS_RENDIMIENTO

    WHERE estado = 'COMPLETADA'

    GROUP BY
        mes,
        region,
        canal,
        id_cliente
),

clientes_clasificados AS (
    SELECT
        *,

        ROW_NUMBER() OVER (
            PARTITION BY mes, region, canal
            ORDER BY
                importe_neto DESC,
                id_cliente
        ) AS posicion_cliente

    FROM ventas_cliente
)

SELECT
    mes,
    region,
    canal,

    COUNT(*)::NUMBER(18,0)
        AS clientes_activos,

    SUM(num_ventas)::NUMBER(18,0)
        AS num_ventas,

    SUM(importe_neto)::NUMBER(22,2)
        AS importe_total,

    ROUND(
        AVG(importe_neto),
        2
    )::NUMBER(22,2)
        AS importe_medio_cliente,

    ROUND(
        APPROX_PERCENTILE(
            importe_neto,
            0.90
        ),
        2
    )::NUMBER(22,2)
        AS p90_cliente,

    MAX(
        IFF(
            posicion_cliente <= 100,
            importe_neto,
            NULL
        )
    )::NUMBER(22,2)
        AS mayor_importe_top_100,

    ROUND(
        AVG(p95_ticket),
        2
    )::NUMBER(22,2)
        AS p95_ticket_medio

FROM clientes_clasificados

GROUP BY
    mes,
    region,
    canal;
```

### Por qué utilizamos una view

Los cuatro ficheros ejecutarán exactamente la misma lógica.

La consulta:

- Escanea millones de filas.
- Agrupa por cliente.
- Calcula percentiles.
- Utiliza una función de ventana.
- Devuelve un resultado pequeño.

---

## 7. Plantilla de los ficheros de carga

En cada fichero utiliza esta estructura sustituyendo el Query Tag por el valor correspondiente:

```sql
USE ROLE SYSADMIN;
USE DATABASE DB_CURSO;
USE SCHEMA PERFORMANCE;
USE WAREHOUSE WH_M08_CONC;

ALTER SESSION SET USE_CACHED_RESULT = FALSE;

ALTER SESSION SET QUERY_TAG =
    'SUSTITUIR_POR_EL_TAG';

SELECT *
FROM DB_CURSO.PERFORMANCE.V_CARGA_CONCURRENCIA
ORDER BY mes, region, canal;
```

En la fase single-cluster:

| Fichero | Tag |
|---|---|
| Q1 | `M08_E02_SINGLE_Q1` |
| Q2 | `M08_E02_SINGLE_Q2` |
| Q3 | `M08_E02_SINGLE_Q3` |
| Q4 | `M08_E02_SINGLE_Q4` |

---

## 8. Preparar el fichero de monitorización

En `M08_E02_MONITOR.sql`:

```sql
USE ROLE SYSADMIN;
```

```sql
SHOW WAREHOUSES LIKE 'WH_M08_CONC'
->>
SELECT
    CURRENT_TIMESTAMP() AS observado_en,
    "name",
    "state",
    "size",
    "min_cluster_count",
    "max_cluster_count",
    "started_clusters",
    "running",
    "queued",
    "scaling_policy",
    "enable_query_acceleration",
    "resource_monitor"
FROM $1;
```

Ejecuta esta consulta varias veces mientras los otros ficheros trabajan.

---

## 9. Fase 1: single-cluster

Confirma (en el archivo principal):

```sql
ALTER WAREHOUSE WH_M08_CONC SET
    MIN_CLUSTER_COUNT = 1
    MAX_CLUSTER_COUNT = 1
    SCALING_POLICY = STANDARD
    MAX_CONCURRENCY_LEVEL = 1
    ENABLE_QUERY_ACCELERATION = FALSE;
```

Suspende:

```sql
ALTER WAREHOUSE WH_M08_CONC SUSPEND;
```

### Lanzar la carga

1. Abre los cuatro ficheros.
2. Ejecuta Q1.
3. Ejecuta inmediatamente Q2, Q3 y Q4.
4. Cambia al fichero de monitorización.
5. Ejecuta `SHOW WAREHOUSES` varias veces.

Un patrón posible:

```text
started_clusters = 1
running = 1
queued = 3
```

No es obligatorio obtener exactamente esos valores.

Las consultas pequeñas pueden contar como una fracción de la concurrencia y una consulta puede terminar mientras cambias de fichero. También hay que tener en cuenta la latencia.

---

## 10. Analizar Query History de la fase 1

```sql
SELECT
    query_tag,
    query_id,
    execution_status,
    start_time,
    end_time,

    ROUND(
        total_elapsed_time / 1000,
        3
    ) AS total_segundos,

    ROUND(
        execution_time / 1000,
        3
    ) AS ejecucion_segundos,

    ROUND(
        queued_overload_time / 1000,
        3
    ) AS cola_sobrecarga_segundos,

    ROUND(
        queued_provisioning_time / 1000,
        3
    ) AS cola_aprovisionamiento_segundos,

    ROUND(
        bytes_scanned / POWER(1024, 2),
        2
    ) AS mb_escaneados,

    error_message

FROM TABLE(
    DB_CURSO.INFORMATION_SCHEMA
        .QUERY_HISTORY_BY_WAREHOUSE(
            WAREHOUSE_NAME => 'WH_M08_CONC',
            END_TIME_RANGE_START =>
                DATEADD(
                    'hour',
                    -1,
                    CURRENT_TIMESTAMP()
                ),
            RESULT_LIMIT => 1000
        )
)

WHERE query_tag LIKE 'M08_E02_SINGLE_Q%'

ORDER BY start_time;
```

Resumen:

```sql
WITH q AS (
    SELECT *
    FROM TABLE(
        DB_CURSO.INFORMATION_SCHEMA
            .QUERY_HISTORY_BY_WAREHOUSE(
                WAREHOUSE_NAME => 'WH_M08_CONC',
                END_TIME_RANGE_START =>
                    DATEADD(
                        'hour',
                        -1,
                        CURRENT_TIMESTAMP()
                    ),
                RESULT_LIMIT => 1000
            )
    )
    WHERE query_tag LIKE 'M08_E02_SINGLE_Q%'
)

SELECT
    COUNT(*) AS consultas,

    ROUND(
        AVG(total_elapsed_time) / 1000,
        3
    ) AS total_medio_segundos,

    ROUND(
        AVG(queued_overload_time) / 1000,
        3
    ) AS cola_media_segundos,

    ROUND(
        MAX(queued_overload_time) / 1000,
        3
    ) AS cola_maxima_segundos,

    COUNT_IF(
        queued_overload_time > 0
    ) AS consultas_con_cola

FROM q;
```

---

## 11. Fase 2: multi-cluster STANDARD

Convierte el warehouse:

```sql
ALTER WAREHOUSE WH_M08_CONC SET
    MIN_CLUSTER_COUNT = 1
    MAX_CLUSTER_COUNT = 2
    SCALING_POLICY = STANDARD
    MAX_CONCURRENCY_LEVEL = 1
    ENABLE_QUERY_ACCELERATION = FALSE;
```

### Auto-scale frente a maximized

```text
MIN = 1
MAX = 2
```

significa auto-scale.

Si se configurase:

```text
MIN = 2
MAX = 2
```

el warehouse funcionaría en modo maximized y mantendría dos clústeres mientras estuviera activo.

El modo maximized no se utiliza porque consumiría dos clústeres desde el inicio de cada periodo activo.

### Actualizar los tags

| Fichero | Tag |
|---|---|
| Q1 | `M08_E02_STANDARD_Q1` |
| Q2 | `M08_E02_STANDARD_Q2` |
| Q3 | `M08_E02_STANDARD_Q3` |
| Q4 | `M08_E02_STANDARD_Q4` |

Suspende:

```sql
ALTER WAREHOUSE WH_M08_CONC SUSPEND;
```

Repite la carga y monitoriza.

Un patrón posible es:

```text
started_clusters pasa de 1 a 2
running aumenta
queued disminuye
```

### Si no aparece el segundo clúster

Repite la fase:

- Comprueba que `MAX_CLUSTER_COUNT = 2`.
- Comprueba que los cuatro ficheros tienen `USE_CACHED_RESULT = FALSE`.
- Inicia las cuatro consultas más rápidamente.
- Verifica que la view procesa la tabla completa.
- No aumentes el warehouse ni el número de clústeres.

Que no aparezca el segundo clúster puede significar que la carga no fue suficientemente larga, no que la configuración sea incorrecta.

---

## 12. Comparar single-cluster y STANDARD

```sql
WITH q AS (
    SELECT
        CASE
            WHEN query_tag LIKE 'M08_E02_SINGLE_Q%'
                THEN 'SINGLE'
            WHEN query_tag LIKE 'M08_E02_STANDARD_Q%'
                THEN 'STANDARD'
        END AS fase,

        total_elapsed_time,
        execution_time,
        queued_overload_time,
        queued_provisioning_time

    FROM TABLE(
        DB_CURSO.INFORMATION_SCHEMA
            .QUERY_HISTORY_BY_WAREHOUSE(
                WAREHOUSE_NAME => 'WH_M08_CONC',
                END_TIME_RANGE_START =>
                    DATEADD(
                        'hour',
                        -2,
                        CURRENT_TIMESTAMP()
                    ),
                RESULT_LIMIT => 2000
            )
    )

    WHERE query_tag LIKE 'M08_E02_SINGLE_Q%'
       OR query_tag LIKE 'M08_E02_STANDARD_Q%'
)

SELECT
    fase,
    COUNT(*) AS consultas,

    ROUND(
        AVG(total_elapsed_time) / 1000,
        3
    ) AS total_medio_segundos,

    ROUND(
        AVG(execution_time) / 1000,
        3
    ) AS ejecucion_media_segundos,

    ROUND(
        AVG(queued_overload_time) / 1000,
        3
    ) AS cola_media_segundos,

    ROUND(
        MAX(queued_overload_time) / 1000,
        3
    ) AS cola_maxima_segundos,

    COUNT_IF(
        queued_overload_time > 0
    ) AS consultas_con_cola

FROM q

GROUP BY fase

ORDER BY fase;
```

### Interpretación

Multi-cluster puede:

- Reducir cola.
- Completar el conjunto de consultas antes.
- Mejorar throughput.

No implica que una consulta se ejecute en dos clústeres simultáneamente.

Cada consulta se asigna a un clúster.

---

## 13. Coste potencial del escalado

Un clúster Gen1 XSMALL consume:

```text
1 crédito por hora
```

Con dos clústeres activos:

```text
2 créditos por hora
```

El segundo clúster solo consume mientras está iniciado.

Por eso hay un trade-off:

```text
menos cola
frente a
más créditos durante los picos
```

La decisión debe basarse en:

- SLA de latencia.
- Duración del pico.
- Número de usuarios.
- Valor de las consultas.
- Créditos adicionales.

---

## 14. Fase 3: política ECONOMY

```sql
ALTER WAREHOUSE WH_M08_CONC SET
    SCALING_POLICY = ECONOMY;
```

Mantén:

```text
MIN_CLUSTER_COUNT = 1
MAX_CLUSTER_COUNT = 2
MAX_CONCURRENCY_LEVEL = 1
```

Actualiza los tags:

| Fichero | Tag |
|---|---|
| Q1 | `M08_E02_ECONOMY_Q1` |
| Q2 | `M08_E02_ECONOMY_Q2` |
| Q3 | `M08_E02_ECONOMY_Q3` |
| Q4 | `M08_E02_ECONOMY_Q4` |

Suspende y repite.

### Diferencia conceptual

`STANDARD` prioriza evitar o reducir la cola y tiende a iniciar clústeres antes.

`ECONOMY` intenta mantener los clústeres activos más cargados antes de iniciar otro, lo que puede:

- Ahorrar créditos.
- Aumentar el tiempo en cola.
- Reducir la rapidez del escalado horizontal.

---

## 15. Comparar las tres fases

```sql
WITH q AS (
    SELECT
        CASE
            WHEN query_tag LIKE 'M08_E02_SINGLE_Q%'
                THEN 'SINGLE'
            WHEN query_tag LIKE 'M08_E02_STANDARD_Q%'
                THEN 'STANDARD'
            WHEN query_tag LIKE 'M08_E02_ECONOMY_Q%'
                THEN 'ECONOMY'
        END AS fase,

        total_elapsed_time,
        execution_time,
        queued_overload_time,
        queued_provisioning_time

    FROM TABLE(
        DB_CURSO.INFORMATION_SCHEMA
            .QUERY_HISTORY_BY_WAREHOUSE(
                WAREHOUSE_NAME => 'WH_M08_CONC',
                END_TIME_RANGE_START =>
                    DATEADD(
                        'hour',
                        -3,
                        CURRENT_TIMESTAMP()
                    ),
                RESULT_LIMIT => 3000
            )
    )

    WHERE query_tag LIKE 'M08_E02_SINGLE_Q%'
       OR query_tag LIKE 'M08_E02_STANDARD_Q%'
       OR query_tag LIKE 'M08_E02_ECONOMY_Q%'
)

SELECT
    fase,
    COUNT(*) AS consultas,

    ROUND(
        AVG(total_elapsed_time) / 1000,
        3
    ) AS total_medio_segundos,

    ROUND(
        AVG(execution_time) / 1000,
        3
    ) AS ejecucion_media_segundos,

    ROUND(
        AVG(queued_overload_time) / 1000,
        3
    ) AS cola_media_segundos,

    ROUND(
        MAX(queued_overload_time) / 1000,
        3
    ) AS cola_maxima_segundos,

    COUNT_IF(
        queued_overload_time > 0
    ) AS consultas_con_cola

FROM q

GROUP BY fase

ORDER BY fase;
```

No fuerces una conclusión si las diferencias son pequeñas.

La carga puede ser demasiado corta para distinguir claramente las políticas. En ese caso, documenta:

- Configuración.
- Clústeres observados.
- Métricas.
- Limitación del experimento.

---

## 16. Consultar WAREHOUSE_LOAD_HISTORY

Espera al menos un minuto desde la última prueba.

```sql
SELECT
    start_time,
    end_time,
    warehouse_name,
    avg_running,
    avg_queued_load,
    avg_queued_provisioning,
    avg_blocked

FROM TABLE(
    DB_CURSO.INFORMATION_SCHEMA
        .WAREHOUSE_LOAD_HISTORY(
            DATE_RANGE_START =>
                DATEADD(
                    'minute',
                    -30,
                    CURRENT_TIMESTAMP()
                ),

            DATE_RANGE_END =>
                DATEADD(
                    'minute',
                    -1,
                    CURRENT_TIMESTAMP()
                ),

            WAREHOUSE_NAME =>
                'WH_M08_CONC'
        )
)

ORDER BY start_time;
```

### Cómo interpretar la carga

Los valores no son un conteo directo.

Representan:

```text
tiempo acumulado de consultas en un estado
÷
duración del intervalo
```

Un valor superior a `1` es posible si varias consultas estuvieron simultáneamente en ese estado.

- `AVG_RUNNING`: carga ejecutándose.
- `AVG_QUEUED_LOAD`: carga esperando por sobrecarga.
- `AVG_QUEUED_PROVISIONING`: espera por aprovisionamiento.
- `AVG_BLOCKED`: espera por locks.

---

## 17. Crear el Resource Monitor

Solo `ACCOUNTADMIN` puede:

- Crear un Resource Monitor.
- Asignar warehouses.
- Cambiar el monitor entre nivel warehouse y cuenta.

Ejecuta:

```sql
USE ROLE ACCOUNTADMIN;
```

```sql
CREATE OR REPLACE RESOURCE MONITOR RM_M08_CONC
WITH
    CREDIT_QUOTA = 2
    FREQUENCY = MONTHLY
    START_TIMESTAMP = IMMEDIATELY

TRIGGERS
    ON 50 PERCENT DO NOTIFY
    ON 80 PERCENT DO NOTIFY
    ON 90 PERCENT DO SUSPEND
    ON 100 PERCENT DO SUSPEND_IMMEDIATE;
```

Delega visualización y modificación:

```sql
GRANT MONITOR, MODIFY
ON RESOURCE MONITOR RM_M08_CONC
TO ROLE SYSADMIN;
```

Asigna el warehouse:

```sql
ALTER WAREHOUSE WH_M08_CONC
SET RESOURCE_MONITOR = RM_M08_CONC;
```

Vuelve:

```sql
USE ROLE SYSADMIN;
```

---

## 18. Interpretar los triggers

### 50 % y 80 %: NOTIFY

Envían una notificación, pero no suspenden el warehouse.

Para una cuota de dos créditos:

```text
50 % = 1,0 crédito
80 % = 1,6 créditos
```

### 90 %: SUSPEND

```text
90 % = 1,8 créditos
```

Snowflake:

- Impide nuevas consultas.
- Permite finalizar las que ya están ejecutándose.
- Suspende los warehouses asignados cuando terminan.

### 100 %: SUSPEND_IMMEDIATE

```text
100 % = 2,0 créditos
```

Snowflake:

- Suspende inmediatamente.
- Cancela consultas en ejecución.

### Por qué no forzamos el trigger

Los Resource Monitors no están diseñados para límites exactos al segundo o a una fracción pequeña de crédito.

La detección y suspensión pueden tener retraso.

Consumir créditos deliberadamente para provocar una suspensión contradice el objetivo FinOps del ejercicio.

La práctica consiste en:

- Crear.
- Asignar.
- Inspeccionar.
- Modificar.
- Diseñar la política.

---

## 19. Inspeccionar el monitor

```sql
SHOW RESOURCE MONITORS LIKE 'RM_M08_CONC';
```

Proyección útil:

```sql
SHOW RESOURCE MONITORS LIKE 'RM_M08_CONC'
->>
SELECT
    "name",
    "credit_quota",
    "used_credits",
    "remaining_credits",
    "level",
    "frequency",
    "start_time",
    "end_time",
    "notify_at",
    "suspend_at",
    "suspend_immediately_at",
    "owner",
    "comment"
FROM $1;
```

Comprueba la asignación desde el warehouse:

```sql
SHOW WAREHOUSES LIKE 'WH_M08_CONC'
->>
SELECT
    "name",
    "state",
    "min_cluster_count",
    "max_cluster_count",
    "started_clusters",
    "resource_monitor"
FROM $1;
```

El monitor debe aparecer como:

```text
RM_M08_CONC
```

### Notificaciones

Un trigger `NOTIFY` no garantiza que llegue un correo automáticamente.

Las notificaciones de Resource Monitors están deshabilitadas por defecto para cada usuario.

Deben habilitarse en Snowsight.

Los usuarios sin `ACCOUNTADMIN` solo pueden recibir notificaciones por correo para monitores de warehouse.

---

## 20. Modificar la política desde SYSADMIN

`SYSADMIN` recibió:

```text
MONITOR
MODIFY
```

Por tanto, puede cambiar cuota, calendario y triggers, aunque no puede asignar o desasignar warehouses.

Ejecuta:

```sql
ALTER RESOURCE MONITOR RM_M08_CONC
SET
    CREDIT_QUOTA = 3

TRIGGERS
    ON 60 PERCENT DO NOTIFY
    ON 85 PERCENT DO NOTIFY
    ON 95 PERCENT DO SUSPEND
    ON 105 PERCENT DO SUSPEND_IMMEDIATE;
```

Comprueba:

```sql
SHOW RESOURCE MONITORS LIKE 'RM_M08_CONC';
```

### Los triggers no son aditivos

La cláusula `TRIGGERS`:

- Elimina los triggers anteriores.
- Los reemplaza por el conjunto especificado.

Si quisieras añadir un aviso nuevo, tendrías que repetir también los triggers que deseas conservar.

### Umbral superior a 100 %

Snowflake admite porcentajes mayores que `100`.

En esta política:

- Se suspende normalmente al 95 %.
- El 105 % actúa como protección final si todavía queda una consulta ejecutándose.

No garantiza que el consumo se detenga exactamente en el 105 %.

---

## 21. Qué ocurre tras una suspensión por monitor

Un warehouse suspendido por el monitor no puede reanudarse hasta que ocurra alguna de estas condiciones:

- Comienza el siguiente intervalo.
- Se aumenta la cuota.
- Se aumenta el umbral.
- Se desasigna el warehouse.
- Se elimina el monitor.

Por eso una acción de suspensión debe acompañarse de:

- Procedimiento de escalado.
- Responsable.
- Revisión de la causa.
- Decisión sobre ampliar cuota o detener workload.

---

## 22. Resource Monitor frente a Budget

Los Resource Monitors funcionan con warehouses estándar administrados por el usuario.

No controlan todo el gasto serverless ni los servicios de IA.

Clasificación:

| Consumo | Mecanismo principal |
|---|---|
| Warehouse de BI | Resource Monitor |
| Warehouse de ETL | Resource Monitor |
| Snowpipe serverless | Budget |
| Automatic Clustering | Budget |
| Serverless Tasks | Budget |
| Query Acceleration Service | Budget |
| AI Services | Budget |

### Matiz sobre Cloud Services

El monitor puede incluir los créditos de Cloud Services asociados al warehouse en el cálculo de uso.

Sin embargo, suspender un warehouse no elimina necesariamente todos los costes de Cloud Services.

Para servicios serverless independientes se utilizan Budgets y las vistas de consumo correspondientes.

---

## 23. Diseñar monitores por workload

Ejemplo razonado:

### Desarrollo

```text
Quota: 20 créditos al mes
Notify: 50 % y 75 %
Suspend: 90 %
Suspend immediate: 100 %
Warehouse exclusivo
```

Prioridad: evitar warehouses olvidados y consultas accidentales.

### BI

```text
Quota: 100 créditos al mes
Notify: 60 %, 80 % y 90 %
Suspend: 100 %
Suspend immediate: 110 %
Warehouse exclusivo
```

Prioridad: no interrumpir inmediatamente consultas de negocio salvo exceso grave.

### ETL

```text
Quota: 150 créditos al mes
Notify: 60 %, 80 % y 90 %
Suspend: 105 %
Suspend immediate: 115 %
Warehouse exclusivo
```

Prioridad: permitir completar cargas críticas, pero detectar desviaciones.

Los valores son ejemplos. Deben basarse en:

- Baseline.
- Estacionalidad.
- SLA.
- Forecast.
- Coste unitario.
- Criticidad.

### Por qué un monitor por warehouse crítico

Si varios warehouses comparten una cuota:

- Un workload puede agotar el presupuesto de otro.
- La atribución es menos clara.
- Una suspensión afecta a todos los asignados.

---

## 24. Restaurar el warehouse

Vuelve a single-cluster y al nivel normal de concurrencia:

```sql
ALTER WAREHOUSE WH_M08_CONC SET
    MIN_CLUSTER_COUNT = 1
    MAX_CLUSTER_COUNT = 1
    SCALING_POLICY = STANDARD
    MAX_CONCURRENCY_LEVEL = 8
    ENABLE_QUERY_ACCELERATION = FALSE;
```

---

## 25. Desasignar y eliminar el monitor

La asignación requiere `ACCOUNTADMIN`.

```sql
USE ROLE ACCOUNTADMIN;
```

```sql
ALTER WAREHOUSE WH_M08_CONC
UNSET RESOURCE_MONITOR;
```

Comprueba:

```sql
SHOW WAREHOUSES LIKE 'WH_M08_CONC'
->>
SELECT
    "name",
    "resource_monitor"
FROM $1;
```

El valor debe quedar nulo.

Elimina:

```sql
DROP RESOURCE MONITOR IF EXISTS RM_M08_CONC;
```

Vuelve:

```sql
USE ROLE SYSADMIN;
```

---

## 26. Suspender y restaurar sesiones

```sql
ALTER WAREHOUSE WH_M08_CONC SUSPEND;
```

En cada fichero de carga:

```sql
ALTER SESSION UNSET USE_CACHED_RESULT;
ALTER SESSION UNSET QUERY_TAG;
```

Comprueba:

```sql
SHOW WAREHOUSES LIKE 'WH_M08_CONC'
->>
SELECT
    "name",
    "state",
    "min_cluster_count",
    "max_cluster_count",
    "started_clusters",
    "scaling_policy",
    "resource_monitor"
FROM $1;
```

Resultado final esperado:

```text
SUSPENDED
MIN = 1
MAX = 1
RESOURCE_MONITOR = NULL
```

---

## 27. Errores frecuentes

### MAX_CLUSTER_COUNT = 2 devuelve error de edición

Los multi-cluster warehouses requieren Enterprise Edition o superior.

Las cuentas trial proporcionadas para el curso deben ser Enterprise.

Comprueba que el alumno creó la cuenta con esa edición.

---

### No aparece cola en single-cluster

Posibles causas:

- Las consultas se lanzaron con demasiada separación.
- Se reutilizó result cache.
- La consulta terminó muy rápido.
- Las sentencias pequeñas cuentan como fracciones de concurrencia.

Repite comprobando:

```sql
ALTER SESSION SET USE_CACHED_RESULT = FALSE;
```

y lanza las cuatro consultas rápidamente.

---

### No aparece el segundo clúster

Comprueba:

```text
MIN = 1
MAX = 2
SCALING_POLICY = STANDARD
```

La carga debe mantenerse el tiempo suficiente para que Snowflake detecte cola y aprovisione el clúster.

---

### QAS aparece habilitado

Ejecuta:

```sql
ALTER WAREHOUSE WH_M08_CONC SET
    ENABLE_QUERY_ACCELERATION = FALSE;
```

Los warehouses multi-cluster nuevos pueden habilitar QAS automáticamente en la versión actual.

---

### SYSADMIN no puede crear el Resource Monitor

Es correcto.

Solo `ACCOUNTADMIN` puede crear Resource Monitors.

---

### SYSADMIN puede modificarlo, pero no asignarlo

Es el comportamiento esperado.

`MODIFY` permite cambiar cuota y triggers.

La asignación de warehouses requiere `ACCOUNTADMIN`.

---

### No llegan las notificaciones

Comprueba:

- Notificaciones habilitadas en Snowsight.
- Correo verificado.
- Usuario incluido cuando corresponda.
- Trigger alcanzado.

En este ejercicio no se fuerza el consumo hasta un trigger.

---

### SHOW RESOURCE MONITORS no muestra créditos inmediatamente

La actualización de métricas puede no ser instantánea.

Además, el consumo anterior a la asignación no pertenece al periodo de seguimiento del monitor.

---

## 28. Respuestas a las preguntas de reflexión

### 1. ¿Warehouse grande frente a multi-cluster?

Un tamaño mayor aporta más recursos a un clúster y puede acelerar una consulta. Multi-cluster añade clústeres para atender más consultas simultáneas.

### 2. ¿Métrica de falta de concurrencia?

`QUEUED_OVERLOAD_TIME` y `AVG_QUEUED_LOAD`.

### 3. ¿Por qué no dejar MAX_CONCURRENCY_LEVEL = 1?

Generaría colas innecesarias. Se utiliza para hacer visible el comportamiento del laboratorio.

### 4. ¿Auto-scale frente a maximized?

Auto-scale tiene `MIN < MAX` y añade o retira clústeres. Maximized tiene `MIN = MAX` y mantiene todos los clústeres activos mientras el warehouse funciona.

### 5. ¿STANDARD frente a ECONOMY?

STANDARD prioriza respuesta y evita cola. ECONOMY prioriza utilizar más intensamente los clústeres activos antes de añadir otro.

### 6. ¿Monitor compartido?

Dificulta atribución y permite que un workload suspenda a los demás al agotar la cuota común.

### 7. ¿SUSPEND frente a SUSPEND_IMMEDIATE?

SUSPEND deja terminar las consultas activas. SUSPEND_IMMEDIATE las cancela.

### 8. ¿Por qué no es un límite exacto?

La detección y la suspensión pueden tener latencia; una consulta puede seguir consumiendo tras cruzar el umbral.

### 9. ¿Qué ocurre tras el trigger?

El warehouse no puede reanudarse hasta ampliar o restablecer la cuota, cambiar el umbral, desasignar el monitor, eliminarlo o comenzar un nuevo intervalo.

### 10. ¿Por qué no basta con avisos?

Pueden no estar habilitados, llegar tarde o no ser atendidos. Deben combinarse con suspensión, observabilidad y procedimientos operativos.

---
USE ROLE SYSADMIN;

CREATE DATABASE IF NOT EXISTS DB_CURSO;
CREATE SCHEMA IF NOT EXISTS DB_CURSO.PERFORMANCE;

USE DATABASE DB_CURSO;
USE SCHEMA PERFORMANCE;

ALTER SESSION SET QUERY_TAG = 'M08_E02_PREPARACION';

SHOW TABLES LIKE 'VENTAS_RENDIMIENTO'
IN SCHEMA DB_CURSO.PERFORMANCE;

SELECT
    COUNT(*) AS filas,
    MIN(fecha) AS fecha_minima,
    MAX(fecha) AS fecha_maxima
FROM DB_CURSO.PERFORMANCE.VENTAS_RENDIMIENTO;

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

SHOW PARAMETERS LIKE 'MAX_CONCURRENCY_LEVEL'
IN WAREHOUSE WH_M08_CONC;

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

ALTER WAREHOUSE WH_M08_CONC SET
    MIN_CLUSTER_COUNT = 1
    MAX_CLUSTER_COUNT = 1
    SCALING_POLICY = STANDARD
    MAX_CONCURRENCY_LEVEL = 1
    ENABLE_QUERY_ACCELERATION = FALSE;

ALTER WAREHOUSE WH_M08_CONC SUSPEND;

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

ALTER WAREHOUSE WH_M08_CONC SET
    MIN_CLUSTER_COUNT = 1
    MAX_CLUSTER_COUNT = 2
    SCALING_POLICY = STANDARD
    MAX_CONCURRENCY_LEVEL = 1
    ENABLE_QUERY_ACCELERATION = FALSE;

ALTER WAREHOUSE WH_M08_CONC SUSPEND;

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

ALTER WAREHOUSE WH_M08_CONC SET
    SCALING_POLICY = ECONOMY;

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

USE ROLE ACCOUNTADMIN;

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

GRANT MONITOR, MODIFY
ON RESOURCE MONITOR RM_M08_CONC
TO ROLE SYSADMIN;

ALTER WAREHOUSE WH_M08_CONC
SET RESOURCE_MONITOR = RM_M08_CONC;

USE ROLE SYSADMIN;

SHOW RESOURCE MONITORS LIKE 'RM_M08_CONC';

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

ALTER RESOURCE MONITOR RM_M08_CONC
SET
    CREDIT_QUOTA = 3

TRIGGERS
    ON 60 PERCENT DO NOTIFY
    ON 85 PERCENT DO NOTIFY
    ON 95 PERCENT DO SUSPEND
    ON 105 PERCENT DO SUSPEND_IMMEDIATE;

SHOW RESOURCE MONITORS LIKE 'RM_M08_CONC';

USE ROLE ACCOUNTADMIN;

ALTER WAREHOUSE WH_M08_CONC
UNSET RESOURCE_MONITOR;

DROP RESOURCE MONITOR IF EXISTS RM_M08_CONC;

USE ROLE SYSADMIN;

ALTER WAREHOUSE WH_M08_CONC SUSPEND;


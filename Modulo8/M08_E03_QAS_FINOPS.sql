USE ROLE ACCOUNTADMIN;

GRANT MONITOR USAGE
ON ACCOUNT
TO ROLE SYSADMIN;

GRANT DATABASE ROLE SNOWFLAKE.GOVERNANCE_VIEWER
TO ROLE SYSADMIN;

GRANT DATABASE ROLE SNOWFLAKE.USAGE_VIEWER
TO ROLE SYSADMIN;

SHOW DATABASES LIKE 'SNOWFLAKE_SAMPLE_DATA';

GRANT IMPORTED PRIVILEGES
ON DATABASE SNOWFLAKE_SAMPLE_DATA
TO ROLE SYSADMIN;

USE ROLE SYSADMIN;

ALTER SESSION SET USE_CACHED_RESULT = FALSE;

ALTER SESSION SET QUERY_TAG = 'M08_E03_PREPARACION';

SHOW SCHEMAS LIKE 'TPCDS_SF10TCL'
IN DATABASE SNOWFLAKE_SAMPLE_DATA;

SHOW TABLES LIKE 'STORE_SALES'
IN SCHEMA SNOWFLAKE_SAMPLE_DATA.TPCDS_SF10TCL;

SHOW TABLES LIKE 'DATE_DIM'
IN SCHEMA SNOWFLAKE_SAMPLE_DATA.TPCDS_SF10TCL;

SHOW TABLES LIKE 'ITEM'
IN SCHEMA SNOWFLAKE_SAMPLE_DATA.TPCDS_SF10TCL;

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

ALTER WAREHOUSE WH_M08_NOQAS SUSPEND;
ALTER WAREHOUSE WH_M08_QAS SUSPEND;

USE WAREHOUSE WH_M08_NOQAS;

ALTER SESSION SET QUERY_TAG = 'M08_E03_NOQAS';

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

SET QID_NOQAS = LAST_QUERY_ID();

ALTER SESSION SET QUERY_TAG = 'M08_E03_CAPTURA_ID';

SELECT $QID_NOQAS AS query_id_sin_qas;

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

SELECT
    PARSE_JSON(
        SYSTEM$ESTIMATE_QUERY_ACCELERATION(
            $QID_NOQAS
        )
    ) AS estimacion;

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

SHOW WAREHOUSES LIKE 'WH_M08_QAS';

USE WAREHOUSE WH_M08_QAS;

ALTER SESSION SET QUERY_TAG = 'M08_E03_QAS';

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

SET QID_QAS = LAST_QUERY_ID();

ALTER SESSION SET QUERY_TAG = 'M08_E03_CAPTURA_ID';

SELECT
    $QID_NOQAS AS query_id_sin_qas,
    $QID_QAS AS query_id_con_qas;

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

USE WAREHOUSE WH_M08_QAS;

ALTER SESSION SET QUERY_TAG = 'M08_E03_QAS_CONTROL';

SELECT *
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
WHERE O_ORDERKEY = 12345;

SET QID_CONTROL = LAST_QUERY_ID();

ALTER SESSION SET QUERY_TAG = 'M08_E03_CAPTURA_ID';

SELECT $QID_CONTROL AS query_id_control;

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

ALTER SESSION UNSET USE_CACHED_RESULT;

ALTER SESSION UNSET QUERY_TAG;

ALTER WAREHOUSE WH_M08_NOQAS SUSPEND;
ALTER WAREHOUSE WH_M08_QAS SUSPEND;

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

DROP WAREHOUSE IF EXISTS WH_M08_NOQAS;
DROP WAREHOUSE IF EXISTS WH_M08_QAS;
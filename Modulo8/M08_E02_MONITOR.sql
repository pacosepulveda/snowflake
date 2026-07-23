USE ROLE SYSADMIN;

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
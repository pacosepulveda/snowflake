# Módulo 10 · Ejercicio 3

## Solución guiada: backup lógico, backup nativo y RPO/RTO

---

## 1. Estrategia

```text
Time Travel
    → errores operativos recientes

Backup lógico
    → formato abierto y almacenamiento externo

Backup nativo
    → copia no modificable y restore rápido en Snowflake

Replication y failover
    → continuidad entre cuentas y regiones
```

---

# Parte 1. Preparar la fuente

## 2. Crear el warehouse

```sql
USE ROLE SYSADMIN;

CREATE WAREHOUSE IF NOT EXISTS WH_M10_DR
    WAREHOUSE_SIZE = XSMALL
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE;

USE WAREHOUSE WH_M10_DR;

ALTER SESSION SET QUERY_TAG = 'M10_E03_PREPARACION';
```

---

## 3. Crear una fuente determinista

Para evitar objetos incompatibles procedentes de ejercicios anteriores, se recrea la base completa:

```sql
DROP DATABASE IF EXISTS DB_M10_NATIVE_RESTORE;
DROP DATABASE IF EXISTS DB_M10_LOGICAL_RESTORE;
DROP DATABASE IF EXISTS DB_M10_BACKUP_SNAPSHOT;
DROP DATABASE IF EXISTS DB_M10_PROD;

CREATE DATABASE DB_M10_PROD
    DATA_RETENTION_TIME_IN_DAYS = 1;

CREATE SCHEMA DB_M10_PROD.CORE
    DATA_RETENTION_TIME_IN_DAYS = 1;

CREATE SCHEMA DB_M10_PROD.OPS
    DATA_RETENTION_TIME_IN_DAYS = 1;
```

> Si `DB_M10_BACKUP_REPO` procede de una ejecución anterior y contiene un backup set, elimina primero sus backups y el set antes de recrear el repositorio.

```sql
CREATE DATABASE IF NOT EXISTS DB_M10_BACKUP_REPO
    DATA_RETENTION_TIME_IN_DAYS = 1;

CREATE SCHEMA IF NOT EXISTS DB_M10_BACKUP_REPO.CATALOG;
CREATE SCHEMA IF NOT EXISTS DB_M10_BACKUP_REPO.NATIVE;
```

---

## 4. Crear clientes y pedidos

```sql
CREATE TABLE DB_M10_PROD.CORE.CLIENTES (
    id_cliente NUMBER(18,0),
    nombre     VARCHAR(100),
    segmento   VARCHAR(20)
);
```

```sql
INSERT INTO DB_M10_PROD.CORE.CLIENTES
SELECT
    column1::NUMBER,
    column2::VARCHAR,
    column3::VARCHAR
FROM VALUES
    (1001, 'Alfa SL',  'PYME'),
    (1002, 'Beta SA',  'EMPRESA'),
    (1003, 'Gamma SL', 'PYME');
```

```sql
CREATE TABLE DB_M10_PROD.CORE.PEDIDOS (
    id_pedido       NUMBER(18,0),
    id_cliente      NUMBER(18,0),
    fecha_pedido    DATE,
    region          VARCHAR(20),
    importe         NUMBER(12,2),
    estado          VARCHAR(20),
    actualizado_en  TIMESTAMP_NTZ(3)
);
```

```sql
INSERT INTO DB_M10_PROD.CORE.PEDIDOS
SELECT
    column1::NUMBER,
    column2::NUMBER,
    column3::DATE,
    column4::VARCHAR,
    column5::NUMBER(12,2),
    column6::VARCHAR,
    CURRENT_TIMESTAMP()::TIMESTAMP_NTZ(3)
FROM VALUES
    (20001, 1001, '2026-07-01', 'NORTE', 120.00, 'COMPLETADA'),
    (20002, 1002, '2026-07-01', 'SUR',   250.00, 'PENDIENTE'),
    (20003, 1003, '2026-07-02', 'ESTE',   80.00, 'COMPLETADA'),
    (20004, 1001, '2026-07-02', 'OESTE', 310.00, 'COMPLETADA'),
    (20005, 1002, '2026-07-03', 'NORTE', 150.00, 'CANCELADA'),
    (20006, 1003, '2026-07-03', 'SUR',    95.00, 'PENDIENTE');
```

### Por qué se utiliza TIMESTAMP_NTZ

Snowflake no permite descargar directamente columnas `TIMESTAMP_LTZ` a Parquet. `TIMESTAMP_NTZ(3)` evita ese error y conserva una precisión compatible con la descarga.

---

## 5. Crear objetos para comprobar el backup nativo

Vista:

```sql
USE DATABASE DB_M10_PROD;
USE SCHEMA CORE;

CREATE VIEW V_PEDIDOS_RESUMEN AS
SELECT
    COUNT(*) AS pedidos,
    SUM(importe)::NUMBER(20,2) AS importe_total
FROM PEDIDOS;
```

Stream:

```sql
CREATE STREAM DB_M10_PROD.OPS.PEDIDOS_STREAM
ON TABLE DB_M10_PROD.CORE.PEDIDOS;
```

Stage interno:

```sql
CREATE STAGE DB_M10_PROD.OPS.STG_INTERNO_PRUEBA;
```

Tabla de log y task:

```sql
CREATE TABLE DB_M10_PROD.OPS.TASK_LOG (
    ejecutado_en  TIMESTAMP_LTZ,
    pedidos       NUMBER
);
```

```sql
CREATE TASK DB_M10_PROD.OPS.TASK_AUDITAR_PEDIDOS
    WAREHOUSE = WH_M10_DR
    SCHEDULE = '1440 MINUTES'
AS
INSERT INTO DB_M10_PROD.OPS.TASK_LOG
SELECT
    CURRENT_TIMESTAMP(),
    COUNT(*)
FROM DB_M10_PROD.CORE.PEDIDOS;
```

La task se crea suspendida y no es necesario reanudarla.

---

## 6. Validar el estado inicial

```sql
SELECT
    COUNT(*) AS clientes
FROM DB_M10_PROD.CORE.CLIENTES;
```

```sql
SELECT
    COUNT(*) AS pedidos,
    SUM(importe) AS importe_total
FROM DB_M10_PROD.CORE.PEDIDOS;
```

Resultado:

```text
3 clientes
6 pedidos
1005.00
```

---

# Parte 2. Backup lógico

## 7. Crear el repositorio lógico

```sql
CREATE OR REPLACE STAGE
    DB_M10_BACKUP_REPO.CATALOG.STG_LOGICAL_BACKUP
    ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE');
```

```sql
CREATE OR REPLACE TABLE
    DB_M10_BACKUP_REPO.CATALOG.BACKUP_MANIFEST (
        backup_id         VARCHAR,
        backup_timestamp  TIMESTAMP_LTZ,
        source_object     VARCHAR,
        stage_prefix      VARCHAR,
        row_count         NUMBER,
        amount_total      NUMBER(20,2),
        content_hash      NUMBER,
        file_format       VARCHAR,
        compression       VARCHAR
    );
```

El stage es interno y sirve únicamente para demostrar la técnica. No protege ante la pérdida completa de la cuenta.

---

## 8. Crear un punto consistente

```sql
DROP DATABASE IF EXISTS DB_M10_BACKUP_SNAPSHOT;

SET TS_LOGICAL_BACKUP = CURRENT_TIMESTAMP();

CALL SYSTEM$WAIT(2);
```

```sql
CREATE DATABASE DB_M10_BACKUP_SNAPSHOT
CLONE DB_M10_PROD
AT (
    TIMESTAMP => $TS_LOGICAL_BACKUP::TIMESTAMP_LTZ
);
```

Comprueba:

```sql
SELECT
    (SELECT COUNT(*)
     FROM DB_M10_BACKUP_SNAPSHOT.CORE.CLIENTES) AS clientes,

    (SELECT COUNT(*)
     FROM DB_M10_BACKUP_SNAPSHOT.CORE.PEDIDOS) AS pedidos,

    (SELECT SUM(importe)
     FROM DB_M10_BACKUP_SNAPSHOT.CORE.PEDIDOS) AS importe_total;
```

Resultado:

```text
3
6
1005.00
```

El clone fija un único punto de lectura para todas las tablas del backup.

---

## 9. Limpiar la ruta

```sql
REMOVE
@DB_M10_BACKUP_REPO.CATALOG.STG_LOGICAL_BACKUP/logical_v1/;
```

Si la ruta no contiene ficheros, puedes continuar.

---

## 10. Descargar CLIENTES

```sql
COPY INTO
@DB_M10_BACKUP_REPO.CATALOG.STG_LOGICAL_BACKUP/logical_v1/clientes/

FROM (
    SELECT
        id_cliente,
        nombre,
        segmento
    FROM DB_M10_BACKUP_SNAPSHOT.CORE.CLIENTES
)

FILE_FORMAT = (
    TYPE = PARQUET
    COMPRESSION = SNAPPY
)

HEADER = TRUE
SINGLE = TRUE
OVERWRITE = TRUE;
```

---

## 11. Descargar PEDIDOS

```sql
COPY INTO
@DB_M10_BACKUP_REPO.CATALOG.STG_LOGICAL_BACKUP/logical_v1/pedidos/

FROM (
    SELECT
        id_pedido,
        id_cliente,
        fecha_pedido,
        region,
        importe,
        estado,
        actualizado_en
    FROM DB_M10_BACKUP_SNAPSHOT.CORE.PEDIDOS
)

FILE_FORMAT = (
    TYPE = PARQUET
    COMPRESSION = SNAPPY
)

HEADER = TRUE
SINGLE = TRUE
OVERWRITE = TRUE;
```

Comprueba los ficheros:

```sql
LIST
@DB_M10_BACKUP_REPO.CATALOG.STG_LOGICAL_BACKUP/logical_v1/;
```

---

## 12. Crear el manifest

```sql
TRUNCATE TABLE
    DB_M10_BACKUP_REPO.CATALOG.BACKUP_MANIFEST;
```

Clientes:

```sql
INSERT INTO DB_M10_BACKUP_REPO.CATALOG.BACKUP_MANIFEST
SELECT
    'LOGICAL_V1',
    $TS_LOGICAL_BACKUP::TIMESTAMP_LTZ,
    'DB_M10_PROD.CORE.CLIENTES',
    'logical_v1/clientes/',
    COUNT(*),
    NULL,
    HASH_AGG(HASH(id_cliente, nombre, segmento)),
    'PARQUET',
    'SNAPPY'
FROM DB_M10_BACKUP_SNAPSHOT.CORE.CLIENTES;
```

Pedidos:

```sql
INSERT INTO DB_M10_BACKUP_REPO.CATALOG.BACKUP_MANIFEST
SELECT
    'LOGICAL_V1',
    $TS_LOGICAL_BACKUP::TIMESTAMP_LTZ,
    'DB_M10_PROD.CORE.PEDIDOS',
    'logical_v1/pedidos/',
    COUNT(*),
    SUM(importe),
    HASH_AGG(
        HASH(
            id_pedido,
            id_cliente,
            fecha_pedido,
            region,
            importe,
            estado,
            actualizado_en
        )
    ),
    'PARQUET',
    'SNAPPY'
FROM DB_M10_BACKUP_SNAPSHOT.CORE.PEDIDOS;
```

Exporta el manifest:

```sql
COPY INTO
@DB_M10_BACKUP_REPO.CATALOG.STG_LOGICAL_BACKUP/logical_v1/manifest/

FROM (
    SELECT *
    FROM DB_M10_BACKUP_REPO.CATALOG.BACKUP_MANIFEST
    ORDER BY source_object
)

FILE_FORMAT = (
    TYPE = CSV
    FIELD_DELIMITER = ';'
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    COMPRESSION = GZIP
)

HEADER = TRUE
SINGLE = TRUE
OVERWRITE = TRUE;
```

---

# Parte 3. Restore lógico

## 13. Crear las tablas vacías

```sql
DROP DATABASE IF EXISTS DB_M10_LOGICAL_RESTORE;

SET TS_LOGICAL_RESTORE_START = CURRENT_TIMESTAMP();

CREATE DATABASE DB_M10_LOGICAL_RESTORE;
CREATE SCHEMA DB_M10_LOGICAL_RESTORE.CORE;
```

```sql
CREATE TABLE DB_M10_LOGICAL_RESTORE.CORE.CLIENTES (
    id_cliente NUMBER(18,0),
    nombre     VARCHAR(100),
    segmento   VARCHAR(20)
);
```

```sql
CREATE TABLE DB_M10_LOGICAL_RESTORE.CORE.PEDIDOS (
    id_pedido       NUMBER(18,0),
    id_cliente      NUMBER(18,0),
    fecha_pedido    DATE,
    region          VARCHAR(20),
    importe         NUMBER(12,2),
    estado          VARCHAR(20),
    actualizado_en  TIMESTAMP_NTZ(3)
);
```

El backup lógico conserva los datos, pero el DDL, los grants, las tasks y las policies deben gestionarse aparte.

---

## 14. Cargar Parquet

```sql
COPY INTO DB_M10_LOGICAL_RESTORE.CORE.CLIENTES

FROM
@DB_M10_BACKUP_REPO.CATALOG.STG_LOGICAL_BACKUP/logical_v1/clientes/

FILE_FORMAT = (TYPE = PARQUET)

MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
ON_ERROR = 'ABORT_STATEMENT';
```

```sql
COPY INTO DB_M10_LOGICAL_RESTORE.CORE.PEDIDOS

FROM
@DB_M10_BACKUP_REPO.CATALOG.STG_LOGICAL_BACKUP/logical_v1/pedidos/

FILE_FORMAT = (TYPE = PARQUET)

MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
ON_ERROR = 'ABORT_STATEMENT';
```

---

## 15. Validar conteos e integridad

```sql
SELECT
    (SELECT COUNT(*)
     FROM DB_M10_LOGICAL_RESTORE.CORE.CLIENTES) AS clientes,

    (SELECT COUNT(*)
     FROM DB_M10_LOGICAL_RESTORE.CORE.PEDIDOS) AS pedidos,

    (SELECT SUM(importe)
     FROM DB_M10_LOGICAL_RESTORE.CORE.PEDIDOS) AS importe_total;
```

Resultado:

```text
3
6
1005.00
```

Integridad referencial:

```sql
SELECT COUNT(*) AS pedidos_sin_cliente
FROM DB_M10_LOGICAL_RESTORE.CORE.PEDIDOS p
LEFT JOIN DB_M10_LOGICAL_RESTORE.CORE.CLIENTES c
    ON c.id_cliente = p.id_cliente
WHERE c.id_cliente IS NULL;
```

Resultado:

```text
0
```

---

## 16. Comparar snapshot y restore

```sql
SELECT
    'SNAPSHOT_MINUS_RESTORE' AS comparacion,
    COUNT(*) AS diferencias
FROM (
    SELECT *
    FROM DB_M10_BACKUP_SNAPSHOT.CORE.PEDIDOS

    MINUS

    SELECT *
    FROM DB_M10_LOGICAL_RESTORE.CORE.PEDIDOS
)

UNION ALL

SELECT
    'RESTORE_MINUS_SNAPSHOT',
    COUNT(*)
FROM (
    SELECT *
    FROM DB_M10_LOGICAL_RESTORE.CORE.PEDIDOS

    MINUS

    SELECT *
    FROM DB_M10_BACKUP_SNAPSHOT.CORE.PEDIDOS
);
```

Resultado:

```text
0
0
```

---

## 17. Validar el checksum

```sql
WITH restaurado AS (
    SELECT
        COUNT(*) AS row_count,
        SUM(importe)::NUMBER(20,2) AS amount_total,
        HASH_AGG(
            HASH(
                id_pedido,
                id_cliente,
                fecha_pedido,
                region,
                importe,
                estado,
                actualizado_en
            )
        ) AS content_hash
    FROM DB_M10_LOGICAL_RESTORE.CORE.PEDIDOS
)

SELECT
    m.row_count AS manifest_rows,
    r.row_count AS restored_rows,
    m.amount_total AS manifest_amount,
    r.amount_total AS restored_amount,
    m.content_hash AS manifest_hash,
    r.content_hash AS restored_hash,
    IFF(
        m.row_count = r.row_count
        AND m.amount_total = r.amount_total
        AND m.content_hash = r.content_hash,
        'OK',
        'ERROR'
    ) AS validacion
FROM DB_M10_BACKUP_REPO.CATALOG.BACKUP_MANIFEST m
CROSS JOIN restaurado r
WHERE m.source_object = 'DB_M10_PROD.CORE.PEDIDOS';
```

Resultado:

```text
VALIDACION = OK
```

RTO aproximado:

```sql
SELECT DATEDIFF(
    'second',
    $TS_LOGICAL_RESTORE_START::TIMESTAMP_LTZ,
    CURRENT_TIMESTAMP()
) AS rto_logico_segundos;
```

---

## 18. Demostrar el RPO

```sql
INSERT INTO DB_M10_PROD.CORE.PEDIDOS
VALUES (
    20007,
    1003,
    '2026-07-04',
    'CENTRO',
    180.00,
    'COMPLETADA',
    CURRENT_TIMESTAMP()::TIMESTAMP_NTZ(3)
);
```

```sql
SELECT
    'PROD' AS entorno,
    COUNT(*) AS pedidos,
    SUM(importe) AS importe_total
FROM DB_M10_PROD.CORE.PEDIDOS

UNION ALL

SELECT
    'LOGICAL_RESTORE',
    COUNT(*),
    SUM(importe)
FROM DB_M10_LOGICAL_RESTORE.CORE.PEDIDOS;
```

Resultado:

```text
PROD             7  1185.00
LOGICAL_RESTORE  6  1005.00
```

Interpretación:

```text
RPO
    cantidad de datos que puede perderse
    desde el último backup válido

RTO
    tiempo necesario para restaurar,
    validar y volver a prestar servicio
```

---

# Parte 4. Backup nativo

## 19. Conceder el privilegio

Los backups están disponibles en todas las ediciones, pero el rol necesita un privilegio específico sobre el esquema.

```sql
USE ROLE ACCOUNTADMIN;

GRANT CREATE BACKUP SET
ON SCHEMA DB_M10_BACKUP_REPO.NATIVE
TO ROLE SYSADMIN;

USE ROLE SYSADMIN;
```

No se utiliza retention lock ni legal hold, que requieren Business Critical o superior.

---

## 20. Crear el backup set y el backup

```sql
CREATE BACKUP SET
    DB_M10_BACKUP_REPO.NATIVE.BS_DB_M10_PROD
FOR DATABASE DB_M10_PROD
COMMENT = 'Backup manual del ejercicio M10 E03';
```

```sql
ALTER BACKUP SET
    DB_M10_BACKUP_REPO.NATIVE.BS_DB_M10_PROD
ADD BACKUP;
```

Obtén el UUID:

```sql
SHOW BACKUPS IN BACKUP SET
    DB_M10_BACKUP_REPO.NATIVE.BS_DB_M10_PROD;
```

```sql
SET QID_SHOW_BACKUPS = LAST_QUERY_ID();
```

```sql
SET NATIVE_BACKUP_ID = (
    SELECT "backup_id"::VARCHAR
    FROM TABLE(RESULT_SCAN($QID_SHOW_BACKUPS))
    ORDER BY "created_on" DESC
    LIMIT 1
);
```

```sql
SELECT $NATIVE_BACKUP_ID AS native_backup_id;
```

El backup contiene siete pedidos y `1185.00`.

---

## 21. Simular la corrupción

```sql
ALTER SESSION SET QUERY_TAG = 'M10_E03_INCIDENTE';

UPDATE DB_M10_PROD.CORE.PEDIDOS
SET
    importe = 0,
    estado = 'CANCELADA',
    actualizado_en = CURRENT_TIMESTAMP()::TIMESTAMP_NTZ(3)
WHERE region = 'SUR';
```

Se pierden temporalmente:

```text
250.00 + 95.00 = 345.00
```

Comprueba:

```sql
SELECT
    COUNT(*) AS pedidos,
    SUM(importe) AS importe_total
FROM DB_M10_PROD.CORE.PEDIDOS;
```

Resultado:

```text
7
840.00
```

---

## 22. Restaurar la base

```sql
DROP DATABASE IF EXISTS DB_M10_NATIVE_RESTORE;

SET TS_NATIVE_RESTORE_START = CURRENT_TIMESTAMP();
```

La sentencia necesita el UUID como literal, por lo que se construye dinámicamente:

```sql
SET SQL_NATIVE_RESTORE =
    'CREATE DATABASE DB_M10_NATIVE_RESTORE '
    || 'FROM BACKUP SET '
    || 'DB_M10_BACKUP_REPO.NATIVE.BS_DB_M10_PROD '
    || 'IDENTIFIER '''
    || $NATIVE_BACKUP_ID
    || '''';
```

```sql
EXECUTE IMMEDIATE $SQL_NATIVE_RESTORE;
```

Comprueba:

```sql
SELECT
    COUNT(*) AS pedidos,
    SUM(importe) AS importe_total
FROM DB_M10_NATIVE_RESTORE.CORE.PEDIDOS;
```

Resultado:

```text
7
1185.00
```

RTO aproximado:

```sql
SELECT DATEDIFF(
    'second',
    $TS_NATIVE_RESTORE_START::TIMESTAMP_LTZ,
    CURRENT_TIMESTAMP()
) AS rto_nativo_segundos;
```

La base restaurada es independiente de la original; no mantiene una relación de clone con ella.

---

## 23. Inspeccionar los objetos

Tablas y view:

```sql
SHOW TABLES IN DATABASE DB_M10_NATIVE_RESTORE;
SHOW VIEWS IN DATABASE DB_M10_NATIVE_RESTORE;
```

Task:

```sql
SHOW TASKS IN DATABASE DB_M10_NATIVE_RESTORE
->>
SELECT
    "database_name",
    "schema_name",
    "name",
    "state"
FROM $1;
```

Resultado esperado:

```text
TASK_AUDITAR_PEDIDOS
STATE = suspended
```

Stream:

```sql
SHOW STREAMS IN DATABASE DB_M10_NATIVE_RESTORE;
```

`PEDIDOS_STREAM` no debe aparecer.

Stage:

```sql
SHOW STAGES IN DATABASE DB_M10_NATIVE_RESTORE;
```

`STG_INTERNO_PRUEBA` no debe aparecer.

Resumen:

| Objeto | Backup de base |
|---|---|
| Tablas permanentes y transitorias | Sí |
| Views y secure views | Sí |
| Tasks | Sí, restauradas suspendidas |
| Streams | No |
| Internal y external stages | No |
| Pipes | No |
| Materialized views | No |
| Database roles | No; pueden hacer fallar el backup |

---

## 24. Reparar producción

```sql
ALTER SESSION SET QUERY_TAG = 'M10_E03_REPARACION';

INSERT OVERWRITE INTO DB_M10_PROD.CORE.PEDIDOS
SELECT *
FROM DB_M10_NATIVE_RESTORE.CORE.PEDIDOS;
```

`INSERT OVERWRITE` conserva la identidad, ownership y grants de la tabla original.

Comprueba:

```sql
SELECT
    COUNT(*) AS pedidos,
    SUM(importe) AS importe_total
FROM DB_M10_PROD.CORE.PEDIDOS;
```

Resultado:

```text
7
1185.00
```

Recrea el punto CDC:

```sql
CREATE OR REPLACE STREAM
    DB_M10_PROD.OPS.PEDIDOS_STREAM
ON TABLE DB_M10_PROD.CORE.PEDIDOS;
```

Asegura que la task permanece suspendida:

```sql
ALTER TASK IF EXISTS
    DB_M10_PROD.OPS.TASK_AUDITAR_PEDIDOS
SUSPEND;
```

---

# Parte 5. Interpretación

## 25. Comparar las capas

| Característica | Parquet lógico | Backup nativo |
|---|---|---|
| Portable fuera de Snowflake | Sí | No directamente |
| Conserva los datos y tipos básicos | Sí | Sí |
| Conserva views | No | Sí |
| Conserva tasks | No | Sí, suspendidas |
| Conserva streams y stages | No | No |
| Requiere reconstruir DDL | Sí | No para objetos incluidos |
| Restore rápido en Snowflake | Depende del volumen | Normalmente menor |
| Protege del fallo regional por sí solo | Solo si se almacena fuera | No |

Un internal stage sigue perteneciendo a la misma cuenta. Para una copia externa real se utilizaría S3, Azure Blob/ADLS o Google Cloud Storage mediante una storage integration.

---

## 26. Mapa de incidentes

| Incidente | Mecanismo principal |
|---|---|
| `UPDATE` accidental reciente | Time Travel |
| Restauración en otra plataforma | Backup lógico |
| Copia no modificable | Backup nativo |
| Migración o prueba temporal | Clone |
| Fallo regional | Failover group |
| Pérdida de cuenta | Copia externa o réplica en otra cuenta |

---

# Ampliación opcional

## 27. Replication y failover

Un replication group mantiene objetos en otra cuenta, pero la secundaria permanece de solo lectura.

Template conceptual:

```sql
CREATE REPLICATION GROUP RG_M10_DR
    OBJECT_TYPES = DATABASES
    ALLOWED_DATABASES =
        DB_M10_PROD,
        DB_M10_BACKUP_REPO
    ALLOWED_ACCOUNTS =
        <ORGANIZACION>.<CUENTA_DESTINO>
    REPLICATION_SCHEDULE = '10 MINUTE';
```

Un failover group permite promover la secundaria y requiere Business Critical o superior.

```sql
CREATE FAILOVER GROUP FG_M10_DR
    OBJECT_TYPES =
        DATABASES,
        USERS,
        ROLES,
        WAREHOUSES,
        RESOURCE MONITORS,
        NETWORK POLICIES
    ALLOWED_DATABASES =
        DB_M10_PROD,
        DB_M10_BACKUP_REPO
    ALLOWED_ACCOUNTS =
        <ORGANIZACION>.<CUENTA_DR>
    REPLICATION_SCHEDULE = '10 MINUTE';
```

No ejecutes estas sentencias sin una segunda cuenta configurada.

---

## 28. Matriz RPO/RTO de ejemplo

| Capa | RPO | RTO | Estrategia |
|---|---:|---:|---|
| Pedidos | 10 min | 30 min | Failover + backups |
| Clientes | 1 h | 1 h | Replicación + backup |
| RAW reproducible | 4 h | 8 h | Reingesta |
| MARTS | 24 h | 4 h | Reconstrucción |

Los valores reales deben acordarse con negocio, seguridad, plataforma y FinOps.

---

# Limpieza

## 29. Eliminar el backup nativo

Elimina primero el restore:

```sql
DROP DATABASE IF EXISTS DB_M10_NATIVE_RESTORE;
```

Construye la sentencia de eliminación:

```sql
SET SQL_DELETE_NATIVE_BACKUP =
    'ALTER BACKUP SET '
    || 'DB_M10_BACKUP_REPO.NATIVE.BS_DB_M10_PROD '
    || 'DELETE BACKUP IDENTIFIER '''
    || $NATIVE_BACKUP_ID
    || '''';
```

```sql
EXECUTE IMMEDIATE $SQL_DELETE_NATIVE_BACKUP;
```

Solo existe un backup, por lo que también es el más antiguo y puede eliminarse.

```sql
DROP BACKUP SET
    DB_M10_BACKUP_REPO.NATIVE.BS_DB_M10_PROD;
```

---

## 30. Limpiar el backup lógico

```sql
DROP DATABASE IF EXISTS DB_M10_LOGICAL_RESTORE;
DROP DATABASE IF EXISTS DB_M10_BACKUP_SNAPSHOT;
```

```sql
REMOVE
@DB_M10_BACKUP_REPO.CATALOG.STG_LOGICAL_BACKUP/logical_v1/;
```

---

## 31. Cerrar recursos

```sql
ALTER TASK IF EXISTS
    DB_M10_PROD.OPS.TASK_AUDITAR_PEDIDOS
SUSPEND;
```

```sql
ALTER SESSION UNSET QUERY_TAG;

ALTER WAREHOUSE WH_M10_DR SUSPEND;
```

Puedes conservar:

```text
DB_M10_PROD
DB_M10_BACKUP_REPO
```

---

# Referencias oficiales

- [Backups for disaster recovery and immutable storage](https://docs.snowflake.com/en/user-guide/backups)
- [CREATE BACKUP SET](https://docs.snowflake.com/en/sql-reference/sql/create-backup-set)
- [ALTER BACKUP SET](https://docs.snowflake.com/en/sql-reference/sql/alter-backup-set)
- [CREATE DATABASE](https://docs.snowflake.com/en/sql-reference/sql/create-database)
- [Data unloading considerations](https://docs.snowflake.com/en/user-guide/data-unload-considerations)
- [COPY INTO table](https://docs.snowflake.com/en/sql-reference/sql/copy-into-table)
- [Trial accounts](https://docs.snowflake.com/en/user-guide/admin-trial-account)

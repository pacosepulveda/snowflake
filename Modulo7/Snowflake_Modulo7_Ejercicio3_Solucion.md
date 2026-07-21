# Módulo 7 · Ejercicio 3
## Solución guiada: pipeline híbrido con Snowpipe, Stream, Task y Dynamic Table

> Todas las instrucciones utilizan **Workspaces**, la experiencia actual de edición SQL de Snowflake.

---

## 1. Arquitectura y responsabilidades

```text
CSV
 ↓
Named internal stage
 ↓
Snowpipe
 ↓
RAW append-only
 ↓
Stream
 ↓
Triggered task + MERGE
 ↓
CURATED
 ↓
Dynamic Table
 ↓
Dashboard
```

Cada componente resuelve un problema diferente:

| Componente | Responsabilidad |
|---|---|
| Stage | Almacenar temporalmente ficheros |
| Snowpipe | Introducir ficheros nuevos en RAW |
| RAW | Conservar todos los eventos |
| Stream | Exponer cambios pendientes |
| Task | Ejecutar lógica procedural y `MERGE` |
| CURATED | Mantener el estado actual |
| Dynamic Table | Mantener un agregado declarativo |

---

## 2. Preparar Workspaces y privilegios

En **Workspaces**, crea:

```text
M7_E03_PIPELINE_HIBRIDO.sql
```

Ejecuta:

```sql
USE ROLE ACCOUNTADMIN;

GRANT EXECUTE TASK
ON ACCOUNT
TO ROLE SYSADMIN;

USE ROLE SYSADMIN;

CREATE WAREHOUSE IF NOT EXISTS WH_DEV
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE;

USE WAREHOUSE WH_DEV;

CREATE DATABASE IF NOT EXISTS DB_CURSO;
CREATE SCHEMA IF NOT EXISTS DB_CURSO.STAGING;
CREATE SCHEMA IF NOT EXISTS DB_CURSO.CURATED;
CREATE SCHEMA IF NOT EXISTS DB_CURSO.MARTS;

USE DATABASE DB_CURSO;
USE SCHEMA STAGING;

ALTER SESSION SET QUERY_TAG = 'M07_E03_PIPELINE_HIBRIDO';
```

Comprueba:

```sql
SELECT
    CURRENT_ROLE() AS rol,
    CURRENT_WAREHOUSE() AS warehouse,
    CURRENT_DATABASE() AS base_datos,
    CURRENT_SCHEMA() AS esquema;
```

---

## 3. Crear el file format

```sql
CREATE OR REPLACE FILE FORMAT
    DB_CURSO.STAGING.FF_PEDIDOS_HIBRIDO_CSV

    TYPE = CSV
    FIELD_DELIMITER = ';'
    SKIP_HEADER = 1
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    DATE_FORMAT = 'YYYY-MM-DD'
    TIMESTAMP_FORMAT = 'YYYY-MM-DD HH24:MI:SS'
    NULL_IF = ('', 'NULL')
    EMPTY_FIELD_AS_NULL = TRUE
    ERROR_ON_COLUMN_COUNT_MISMATCH = TRUE
    ENCODING = 'UTF8';
```

Comprueba:

```sql
DESC FILE FORMAT
    DB_CURSO.STAGING.FF_PEDIDOS_HIBRIDO_CSV;
```

---

## 4. Crear el named internal stage

```sql
CREATE OR REPLACE STAGE
    DB_CURSO.STAGING.STG_PEDIDOS_HIBRIDO

    ENCRYPTION = (
        TYPE = 'SNOWFLAKE_SSE'
    )

    DIRECTORY = (
        ENABLE = FALSE
    );
```

El stage no necesita un file format predeterminado porque el pipe lo especificará.

Comprueba:

```sql
DESC STAGE DB_CURSO.STAGING.STG_PEDIDOS_HIBRIDO;

LIST @DB_CURSO.STAGING.STG_PEDIDOS_HIBRIDO;
```

Inicialmente no debe contener ficheros.

---

## 5. Crear la tabla RAW

```sql
CREATE OR REPLACE TRANSIENT TABLE
    DB_CURSO.STAGING.PEDIDOS_PIPE_RAW (
        event_id             NUMBER(18,0),
        id_pedido            NUMBER(18,0),
        id_cliente           NUMBER(18,0),
        fecha_pedido         DATE,
        region               VARCHAR(20),
        canal                VARCHAR(20),
        importe              NUMBER(12,2),
        estado               VARCHAR(20),
        fecha_modificacion   TIMESTAMP_NTZ
    );
```

RAW representa el log de eventos.

No se actualizarán ni eliminarán filas durante el flujo normal.

---

## 6. Crear el pipe

```sql
CREATE OR REPLACE PIPE
    DB_CURSO.STAGING.PIPE_PEDIDOS_RAW

    AUTO_INGEST = FALSE

    COMMENT = 'Pipe didáctico para pipeline híbrido'

AS

COPY INTO DB_CURSO.STAGING.PEDIDOS_PIPE_RAW

FROM @DB_CURSO.STAGING.STG_PEDIDOS_HIBRIDO

FILE_FORMAT = (
    FORMAT_NAME = 'DB_CURSO.STAGING.FF_PEDIDOS_HIBRIDO_CSV'
)

PATTERN = '.*Snowflake_Modulo7_Ejercicio3_pedidos_batch[0-9]+[.]csv([.]gz)?';
```

### Qué significa AUTO_INGEST = FALSE

El pipe existe y define la carga, pero no recibe automáticamente eventos del stage.

El procedimiento normal sería:

1. Subir ficheros.
2. Una aplicación llama a `insertFiles` de la API REST.
3. Snowpipe introduce los nombres en su cola.
4. El cómputo serverless ejecuta el `COPY`.

En el laboratorio utilizaremos:

```sql
ALTER PIPE ... REFRESH;
```

para introducir ficheros recientes en la cola.

Esto permite practicar Snowpipe sin crear claves, un cliente REST o infraestructura cloud adicional.

---

## 7. Inspeccionar el pipe

```sql
SHOW PIPES LIKE 'PIPE_PEDIDOS_RAW'
IN SCHEMA DB_CURSO.STAGING;
```

```sql
DESC PIPE DB_CURSO.STAGING.PIPE_PEDIDOS_RAW;
```

```sql
SELECT
    pipe_catalog,
    pipe_schema,
    pipe_name,
    pipe_owner,
    definition,
    is_autoingest_enabled,
    created,
    last_altered
FROM DB_CURSO.INFORMATION_SCHEMA.PIPES
WHERE pipe_schema = 'STAGING'
  AND pipe_name = 'PIPE_PEDIDOS_RAW';
```

Estado:

```sql
SELECT
    PARSE_JSON(
        SYSTEM$PIPE_STATUS(
            'DB_CURSO.STAGING.PIPE_PEDIDOS_RAW'
        )
    ) AS estado;
```

Campos separados:

```sql
WITH estado AS (
    SELECT PARSE_JSON(
        SYSTEM$PIPE_STATUS(
            'DB_CURSO.STAGING.PIPE_PEDIDOS_RAW'
        )
    ) AS s
)

SELECT
    s:executionState::VARCHAR AS execution_state,
    COALESCE(
        s:pendingFileCount::NUMBER,
        0
    ) AS pending_files,
    s:lastIngestedFilePath::VARCHAR
        AS ultimo_fichero,
    s:lastIngestedTimestamp::TIMESTAMP_LTZ
        AS ultima_ingesta
FROM estado;
```

El pipe debe estar `RUNNING`, aunque no esté observando automáticamente el stage.

`RUNNING` significa que el servicio está operativo y puede procesar elementos de su cola. No significa que examine continuamente el named stage.

---

## 8. Crear el stream

```sql
CREATE OR REPLACE STREAM
    DB_CURSO.STAGING.STR_PEDIDOS_PIPE_RAW

ON TABLE DB_CURSO.STAGING.PEDIDOS_PIPE_RAW

APPEND_ONLY = TRUE;
```

Comprueba:

```sql
SELECT SYSTEM$STREAM_HAS_DATA(
    'DB_CURSO.STAGING.STR_PEDIDOS_PIPE_RAW'
);
```

Resultado inicial:

```text
FALSE
```

---

## 9. Crear la tabla CURATED

```sql
CREATE OR REPLACE TABLE
    DB_CURSO.CURATED.PEDIDOS_ACTUALES_HIBRIDO (
        id_pedido            NUMBER(18,0),
        id_cliente           NUMBER(18,0),
        fecha_pedido         DATE,
        region               VARCHAR(20),
        canal                VARCHAR(20),
        importe              NUMBER(12,2),
        estado               VARCHAR(20),
        fecha_modificacion   TIMESTAMP_NTZ,
        event_id             NUMBER(18,0),
        _processed_at        TIMESTAMP_LTZ
    );
```

Activa el seguimiento de cambios que necesitará la Dynamic Table:

```sql
ALTER TABLE
    DB_CURSO.CURATED.PEDIDOS_ACTUALES_HIBRIDO

SET CHANGE_TRACKING = TRUE;
```

---

## 10. Crear la triggered task

```sql
CREATE OR REPLACE TASK
    DB_CURSO.STAGING.TASK_MERGE_PEDIDOS_HIBRIDO

    WAREHOUSE = WH_DEV

    USER_TASK_MINIMUM_TRIGGER_INTERVAL_IN_SECONDS = 10

    WHEN SYSTEM$STREAM_HAS_DATA(
        'DB_CURSO.STAGING.STR_PEDIDOS_PIPE_RAW'
    )

AS

MERGE INTO
    DB_CURSO.CURATED.PEDIDOS_ACTUALES_HIBRIDO
    AS destino

USING (
    SELECT
        event_id,
        id_pedido,
        id_cliente,
        fecha_pedido,
        region,
        canal,
        importe,
        estado,
        fecha_modificacion

    FROM DB_CURSO.STAGING.STR_PEDIDOS_PIPE_RAW

    WHERE METADATA$ACTION = 'INSERT'

    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY id_pedido
        ORDER BY
            fecha_modificacion DESC,
            event_id DESC
    ) = 1
) AS origen

ON destino.id_pedido = origen.id_pedido

WHEN MATCHED
AND (
       origen.fecha_modificacion
       > destino.fecha_modificacion

    OR (
        origen.fecha_modificacion
        = destino.fecha_modificacion

        AND origen.event_id > destino.event_id
    )
)

THEN UPDATE SET
    destino.id_cliente = origen.id_cliente,
    destino.fecha_pedido = origen.fecha_pedido,
    destino.region = origen.region,
    destino.canal = origen.canal,
    destino.importe = origen.importe,
    destino.estado = origen.estado,
    destino.fecha_modificacion =
        origen.fecha_modificacion,
    destino.event_id = origen.event_id,
    destino._processed_at = CURRENT_TIMESTAMP()

WHEN NOT MATCHED

THEN INSERT (
    id_pedido,
    id_cliente,
    fecha_pedido,
    region,
    canal,
    importe,
    estado,
    fecha_modificacion,
    event_id,
    _processed_at
)

VALUES (
    origen.id_pedido,
    origen.id_cliente,
    origen.fecha_pedido,
    origen.region,
    origen.canal,
    origen.importe,
    origen.estado,
    origen.fecha_modificacion,
    origen.event_id,
    CURRENT_TIMESTAMP()
);
```

Reanuda:

```sql
ALTER TASK
    DB_CURSO.STAGING.TASK_MERGE_PEDIDOS_HIBRIDO
RESUME;
```

---

## 11. Crear la Dynamic Table

```sql
CREATE OR REPLACE DYNAMIC TABLE
    DB_CURSO.MARTS.DT_PEDIDOS_DIA_REGION

    TARGET_LAG = '1 minute'

    SCHEDULER = ENABLE

    WAREHOUSE = WH_DEV

    REFRESH_MODE = INCREMENTAL

    INITIALIZE = ON_CREATE

AS

SELECT
    fecha_pedido AS dia,
    region,
    canal,

    COUNT(*)::NUMBER(18,0)
        AS num_pedidos,

    SUM(importe)::NUMBER(18,2)
        AS importe_total,

    ROUND(
        AVG(importe),
        2
    )::NUMBER(18,2)
        AS ticket_medio,

    MAX(fecha_modificacion)
        AS ultima_modificacion_grupo

FROM DB_CURSO.CURATED.PEDIDOS_ACTUALES_HIBRIDO

WHERE estado = 'COMPLETADA'

GROUP BY
    fecha_pedido,
    region,
    canal;
```

Inicialmente:

```sql
SELECT COUNT(*)
FROM DB_CURSO.MARTS.DT_PEDIDOS_DIA_REGION;
```

Resultado:

```text
0
```

---

## 12. Subir el primer microbatch

Descarga:

```text
Snowflake_Modulo7_Ejercicio3_pedidos_batch01.csv
```

En Snowsight:

1. Abre **Ingestion**.
2. Selecciona **Add Data**.
3. Selecciona **Load files into a Stage**.
4. Elige el CSV.
5. Selecciona:
   - Base: `DB_CURSO`
   - Esquema: `STAGING`
   - Stage: `STG_PEDIDOS_HIBRIDO`
6. Sube el fichero.

Comprueba:

```sql
LIST @DB_CURSO.STAGING.STG_PEDIDOS_HIBRIDO;
```

El nombre puede terminar en `.gz` si la interfaz ha aplicado compresión.

Comprueba RAW:

```sql
SELECT COUNT(*)
FROM DB_CURSO.STAGING.PEDIDOS_PIPE_RAW;
```

Debe seguir en cero.

### Por qué no se ha cargado

El pipe fue creado con:

```text
AUTO_INGEST = FALSE
```

Subir un fichero al stage no introduce automáticamente su nombre en la cola.

---

## 13. Introducir el fichero en la cola

Ejecuta:

```sql
ALTER PIPE
    DB_CURSO.STAGING.PIPE_PEDIDOS_RAW
REFRESH;
```

### Uso correcto de REFRESH

`REFRESH`:

- Busca ficheros staged recientemente.
- Comprueba el historial de la tabla y del pipe.
- Encola los que todavía no se han cargado.
- Solo considera ficheros staged dentro de los últimos siete días.

No se diseñó para ejecutarse continuamente como sustituto de las notificaciones o de la API REST.

### Monitorizar el pipe

```sql
WITH estado AS (
    SELECT PARSE_JSON(
        SYSTEM$PIPE_STATUS(
            'DB_CURSO.STAGING.PIPE_PEDIDOS_RAW'
        )
    ) AS s
)

SELECT
    s:executionState::VARCHAR AS estado,
    COALESCE(
        s:pendingFileCount::NUMBER,
        0
    ) AS pendientes,
    s:lastIngestedFilePath::VARCHAR
        AS ultimo_fichero,
    s:lastIngestedTimestamp::TIMESTAMP_LTZ
        AS ultima_ingesta,
    s:error::VARCHAR AS error
FROM estado;
```

Repite hasta:

```text
PENDIENTES = 0
```

Comprueba RAW:

```sql
SELECT COUNT(*) AS eventos
FROM DB_CURSO.STAGING.PEDIDOS_PIPE_RAW;
```

Resultado:

```text
5
```

---

## 14. Esperar a la triggered task

Consulta:

```sql
SELECT
    name,
    state,
    scheduled_from,
    scheduled_time,
    query_start_time,
    completed_time,
    query_id,
    error_message

FROM TABLE(
    DB_CURSO.INFORMATION_SCHEMA.TASK_HISTORY(
        SCHEDULED_TIME_RANGE_START =>
            DATEADD(
                'hour',
                -1,
                CURRENT_TIMESTAMP()
            ),

        RESULT_LIMIT => 20,

        TASK_NAME =>
            'TASK_MERGE_PEDIDOS_HIBRIDO'
    )
)

WHERE query_id IS NOT NULL

ORDER BY scheduled_time DESC;
```

Busca:

```text
STATE = SUCCEEDED
SCHEDULED_FROM = TRIGGER
```

Valida CURATED:

```sql
SELECT *
FROM DB_CURSO.CURATED.PEDIDOS_ACTUALES_HIBRIDO
ORDER BY id_pedido;
```

Debe contener:

| ID_PEDIDO | IMPORTE | ESTADO | EVENT_ID |
|---:|---:|---|---:|
| 9101 | 100.00 | COMPLETADA | 2 |
| 9102 | 200.00 | COMPLETADA | 3 |
| 9103 | 80.00 | COMPLETADA | 4 |
| 9104 | 50.00 | CANCELADA | 5 |

Resumen:

```sql
SELECT
    COUNT(*) AS pedidos,
    COUNT_IF(estado = 'COMPLETADA')
        AS completados,
    COUNT_IF(estado = 'CANCELADA')
        AS cancelados
FROM DB_CURSO.CURATED.PEDIDOS_ACTUALES_HIBRIDO;
```

Resultado:

```text
4, 3, 1
```

El stream debe estar vacío:

```sql
SELECT COUNT(*)
FROM DB_CURSO.STAGING.STR_PEDIDOS_PIPE_RAW;
```

---

## 15. Actualizar la Dynamic Table

Espera al refresco programado.

Para avanzar de forma determinista en el laboratorio, también puedes solicitar:

```sql
ALTER DYNAMIC TABLE
    DB_CURSO.MARTS.DT_PEDIDOS_DIA_REGION
REFRESH;
```

Comprueba:

```sql
SELECT
    COUNT(*) AS grupos,
    SUM(num_pedidos) AS pedidos,
    SUM(importe_total) AS importe
FROM DB_CURSO.MARTS.DT_PEDIDOS_DIA_REGION;
```

Resultado:

| GRUPOS | PEDIDOS | IMPORTE |
|---:|---:|---:|
| 3 | 3 | 380.00 |

---

## 16. Auditar el primer microbatch

### COPY_HISTORY

```sql
SELECT
    file_name,
    last_load_time,
    row_parsed,
    row_count,
    error_count,
    status,
    pipe_name,
    pipe_received_time
FROM TABLE(
    DB_CURSO.INFORMATION_SCHEMA.COPY_HISTORY(
        TABLE_NAME => 'DB_CURSO.STAGING.PEDIDOS_PIPE_RAW',
        START_TIME => DATEADD('hour', -1, CURRENT_TIMESTAMP()),
        PIPE_NAME  => 'DB_CURSO.STAGING.PIPE_PEDIDOS_RAW'
    )
)
ORDER BY last_load_time;
```

Si quieres consultar FIRST_COMMIT_TIME, entonces consulta la vista de ACCOUNT_USAGE en lugar de la table function.

```sql
SELECT
    file_name,
    last_load_time,
    row_parsed,
    row_count,
    error_count,
    status,
    pipe_name,
    pipe_received_time,
    first_commit_time
FROM SNOWFLAKE.ACCOUNT_USAGE.COPY_HISTORY
WHERE table_catalog_name = 'DB_CURSO'
  AND table_schema_name = 'STAGING'
  AND table_name = 'PEDIDOS_PIPE_RAW'
  AND pipe_name = 'PIPE_PEDIDOS_RAW'
  AND last_load_time >= DATEADD('hour', -1, CURRENT_TIMESTAMP())
ORDER BY last_load_time;
```

Debes observar cinco filas cargadas desde el primer fichero.

### VALIDATE_PIPE_LOAD

```sql
SELECT *
FROM TABLE(
    DB_CURSO.INFORMATION_SCHEMA.VALIDATE_PIPE_LOAD(
        PIPE_NAME =>
          'DB_CURSO.STAGING.PIPE_PEDIDOS_RAW',

        START_TIME =>
          DATEADD(
              'hour',
              -1,
              CURRENT_TIMESTAMP()
          )
    )
);
```

No debe devolver filas porque el pipe no encontró errores.

### Historial de Dynamic Tables

```sql
SELECT
    name,
    state,
    refresh_trigger,
    refresh_action,
    refresh_start_time,
    refresh_end_time,
    query_id,
    warehouse,
    state_message

FROM TABLE(
    DB_CURSO.INFORMATION_SCHEMA
        .DYNAMIC_TABLE_REFRESH_HISTORY(
            DATA_TIMESTAMP_START =>
              DATEADD(
                  'hour',
                  -1,
                  CURRENT_TIMESTAMP()
              ),

            RESULT_LIMIT => 100,

            NAME_PREFIX =>
              'DB_CURSO.MARTS.'
        )
)

WHERE name = 'DT_PEDIDOS_DIA_REGION'

ORDER BY refresh_start_time;
```

---

## 17. Dónde se ejecutó cada etapa

### Snowpipe

Utiliza cómputo serverless proporcionado por Snowflake.

No utiliza `WH_DEV` para cargar el CSV.

### Triggered task

La task se creó con:

```sql
WAREHOUSE = WH_DEV
```

El `MERGE` utiliza ese warehouse.

### Dynamic Table

También utiliza:

```sql
WAREHOUSE = WH_DEV
```

durante el refresco.

El mismo warehouse puede servir para el laboratorio, aunque en producción podrían separarse:

- `WH_ETL`
- `WH_DYNAMIC_TABLES`
- `WH_BI`

para aislar cargas y atribuir costes.

---

## 18. Subir el segundo microbatch

Sube:

```text
Snowflake_Modulo7_Ejercicio3_pedidos_batch02.csv
```

al mismo stage.

Comprueba:

```sql
LIST @DB_CURSO.STAGING.STG_PEDIDOS_HIBRIDO;
```

Deben aparecer dos ficheros.

RAW todavía tiene cinco filas hasta que el segundo fichero entre en la cola.

Ejecuta:

```sql
ALTER PIPE
    DB_CURSO.STAGING.PIPE_PEDIDOS_RAW
REFRESH;
```

Snowflake comprueba el historial y solo debe encolar el segundo fichero.

Monitoriza `SYSTEM$PIPE_STATUS`.

Después:

```sql
SELECT COUNT(*)
FROM DB_CURSO.STAGING.PEDIDOS_PIPE_RAW;
```

Resultado:

```text
11
```

---

## 19. Esperar al segundo MERGE

Consulta `TASK_HISTORY` hasta encontrar una nueva ejecución correcta.

Después:

```sql
SELECT
    id_pedido,
    importe,
    estado,
    fecha_modificacion,
    event_id
FROM DB_CURSO.CURATED.PEDIDOS_ACTUALES_HIBRIDO
ORDER BY id_pedido;
```

Resultado:

| ID_PEDIDO | IMPORTE | ESTADO | EVENT_ID |
|---:|---:|---|---:|
| 9101 | 100.00 | COMPLETADA | 2 |
| 9102 | 220.00 | CANCELADA | 6 |
| 9103 | 90.00 | COMPLETADA | 7 |
| 9104 | 50.00 | CANCELADA | 5 |
| 9105 | 125.00 | COMPLETADA | 9 |
| 9106 | 140.00 | COMPLETADA | 10 |
| 9107 | 75.00 | COMPLETADA | 11 |

Resumen:

```sql
SELECT
    COUNT(*) AS pedidos,
    SUM(importe) AS importe_todos,
    COUNT_IF(estado = 'COMPLETADA')
        AS completados,
    COUNT_IF(estado = 'CANCELADA')
        AS cancelados,
    SUM(
        IFF(
            estado = 'COMPLETADA',
            importe,
            0
        )
    ) AS importe_completado
FROM DB_CURSO.CURATED.PEDIDOS_ACTUALES_HIBRIDO;
```

Resultado:

| PEDIDOS | IMPORTE_TODOS | COMPLETADOS | CANCELADOS | IMPORTE_COMPLETADO |
|---:|---:|---:|---:|---:|
| 7 | 800.00 | 5 | 2 | 530.00 |

Comprueba duplicados:

```sql
SELECT
    id_pedido,
    COUNT(*) AS filas
FROM DB_CURSO.CURATED.PEDIDOS_ACTUALES_HIBRIDO
GROUP BY id_pedido
HAVING COUNT(*) > 1;
```

No debe devolver filas.

---

## 20. Refrescar y validar el agregado final

Espera al refresco o ejecuta:

```sql
ALTER DYNAMIC TABLE
    DB_CURSO.MARTS.DT_PEDIDOS_DIA_REGION
REFRESH;
```

Resumen:

```sql
SELECT
    COUNT(*) AS grupos,
    SUM(num_pedidos) AS pedidos,
    SUM(importe_total) AS importe
FROM DB_CURSO.MARTS.DT_PEDIDOS_DIA_REGION;
```

Resultado:

| GRUPOS | PEDIDOS | IMPORTE |
|---:|---:|---:|
| 4 | 5 | 530.00 |

Resultado completo:

```sql
SELECT *
FROM DB_CURSO.MARTS.DT_PEDIDOS_DIA_REGION
ORDER BY dia, region, canal;
```

Comprueba SUR + WEB:

```sql
SELECT *
FROM DB_CURSO.MARTS.DT_PEDIDOS_DIA_REGION
WHERE dia = '2026-07-01'
  AND region = 'SUR'
  AND canal = 'WEB';
```

Resultado:

```text
NUM_PEDIDOS = 2
IMPORTE_TOTAL = 200.00
TICKET_MEDIO = 100.00
```

---

## 21. Probar la protección contra recargas

Sin subir nada nuevo:

```sql
ALTER PIPE
    DB_CURSO.STAGING.PIPE_PEDIDOS_RAW
REFRESH;
```

Espera a que el pipe quede sin pendientes.

Comprueba:

```sql
SELECT
    COUNT(*) AS eventos,
    COUNT(DISTINCT event_id) AS eventos_distintos
FROM DB_CURSO.STAGING.PEDIDOS_PIPE_RAW;
```

Resultado:

```text
11
11
```

CURATED continúa con siete pedidos.

### Por qué no se recargan

`ALTER PIPE … REFRESH` comprueba el historial:

- Del pipe.
- De la tabla objetivo.

Solo introduce en la cola ficheros que no constan como cargados.

### Riesgo de recrear el pipe

El historial de carga Snowpipe está asociado al objeto pipe.

Recrear el pipe elimina su historial.

Si después se ejecuta `REFRESH`, algunos ficheros conservados en el stage podrían volver a introducirse en la cola, especialmente si ya no hay otro historial que los proteja.

Por eso la recreación de pipes debe planificarse cuidadosamente.

---

## 22. Variante de producción: AWS

Flujo habitual:

```text
S3
 ↓ event notification
SQS o SNS/SQS
 ↓
Snowpipe AUTO_INGEST
```

Pasos:

1. Crear una storage integration.
2. Crear el external stage sobre S3.
3. Crear el pipe con `AUTO_INGEST = TRUE`.
4. Obtener el canal o configurar el SNS topic según el patrón.
5. Configurar la notificación de creación de objetos.
6. Validar `SYSTEM$PIPE_STATUS`.
7. Cargar un fichero de prueba.

Para S3, Snowflake puede gestionar automáticamente la cola SQS en el patrón directo.

---

## 23. Variante de producción: Azure

```text
Blob o ADLS
 ↓
Event Grid
 ↓
Notification integration
 ↓
Snowpipe
```

Se necesitan:

- Storage integration.
- External stage.
- Notification integration.
- Suscripción de Event Grid.
- Pipe con `AUTO_INGEST = TRUE` e `INTEGRATION`.

---

## 24. Variante de producción: GCP

```text
GCS
 ↓
Pub/Sub
 ↓
Notification integration
 ↓
Snowpipe
```

Se necesitan:

- Storage integration.
- External stage.
- Topic y subscription de Pub/Sub.
- Notification integration.
- Pipe con `AUTO_INGEST = TRUE`.

---

## 25. Cuándo usar la API REST

Mantener:

```text
AUTO_INGEST = FALSE
```

es apropiado cuando una aplicación productora quiere controlar explícitamente:

- Qué ficheros envía.
- Cuándo los envía.
- El resultado de cada solicitud.
- Reintentos.
- Confirmación de recepción.
- Integración sin event notifications.

La aplicación sube los ficheros y llama al endpoint `insertFiles`.

Para la API se recomienda:

- Usuario específico.
- Autenticación por clave.
- Rol de mínimo privilegio.
- `OPERATE` sobre el pipe.
- `READ` sobre el internal stage.
- `INSERT` y `SELECT` sobre el destino.

---

## 26. Selección de mecanismos

| Escenario | Mecanismo recomendado | Motivo |
|---|---|---|
| Fichero nocturno de 20 GB | `COPY INTO` | Lote grande y planificado |
| Miles de ficheros durante el día | Snowpipe auto-ingest | Llegada continua |
| Propagar cambios con reglas | Stream + Task | CDC y lógica procedural |
| Mantener agregado SQL | Dynamic Table | Pipeline declarativo |
| Carga histórica inicial | `COPY INTO` | Backfill controlado |
| Productor decide los ficheros | Snowpipe REST API | Envío explícito |

### Patrón híbrido

El pipeline completo puede usar todos los mecanismos:

```text
COPY INTO
    para backfill inicial

Snowpipe
    para nuevos ficheros

Streams + Tasks
    para transformar y hacer MERGE

Dynamic Tables
    para agregados y consumo
```

No son tecnologías excluyentes.

---

## 27. Pausar el pipeline

### Suspender la task

```sql
ALTER TASK
    DB_CURSO.STAGING.TASK_MERGE_PEDIDOS_HIBRIDO
SUSPEND;
```

### Suspender la Dynamic Table

```sql
ALTER DYNAMIC TABLE
    DB_CURSO.MARTS.DT_PEDIDOS_DIA_REGION
SUSPEND;
```

### Pausar el pipe

```sql
ALTER PIPE
    DB_CURSO.STAGING.PIPE_PEDIDOS_RAW

SET PIPE_EXECUTION_PAUSED = TRUE;
```

### Suspender el warehouse

```sql
ALTER WAREHOUSE WH_DEV SUSPEND;
```

Comprueba el pipe:

```sql
SELECT PARSE_JSON(
    SYSTEM$PIPE_STATUS(
        'DB_CURSO.STAGING.PIPE_PEDIDOS_RAW'
    )
);
```

Debe mostrar:

```text
executionState = PAUSED
```

Comprueba task y Dynamic Table:

```sql
SHOW TASKS LIKE 'TASK_MERGE_PEDIDOS_HIBRIDO'
IN SCHEMA DB_CURSO.STAGING;

SHOW DYNAMIC TABLES LIKE 'DT_PEDIDOS_DIA_REGION'
IN SCHEMA DB_CURSO.MARTS;
```

### Qué sigue disponible

Pueden seguir consultándose:

- RAW.
- CURATED.
- La última versión materializada de la Dynamic Table.
- Historiales y metadatos.

Quedan detenidos:

- Procesamiento del pipe.
- Triggered task.
- Refrescos programados de la Dynamic Table.
- Cómputo del warehouse.

---

## 28. Monitorización recomendada

En producción deberían controlarse:

### Snowpipe

- Estado del pipe.
- Ficheros pendientes.
- Último fichero recibido e ingerido.
- Errores y faults.
- `COPY_HISTORY`.
- Créditos y bytes en `PIPE_USAGE_HISTORY`.

### Stream y task

- `STALE` y `STALE_AFTER`.
- Edad del cambio más antiguo.
- Fallos consecutivos.
- Duración de la task.
- Filas insertadas y actualizadas.
- Warehouse y créditos.

### Dynamic Table

- Lag real.
- Último data timestamp.
- Fallos de refresco.
- Reinitializaciones.
- Modo incremental o full.
- Duración y créditos.

### Calidad

- Duplicados.
- Eventos sin pedido.
- Versiones antiguas.
- Reconciliación RAW → CURATED.
- Reconciliación CURATED → MARTS.

---

## 29. Limpieza opcional

No ejecutes la limpieza si quieres conservar el pipeline.

```sql
ALTER TASK
    DB_CURSO.STAGING.TASK_MERGE_PEDIDOS_HIBRIDO
SUSPEND;

ALTER DYNAMIC TABLE
    DB_CURSO.MARTS.DT_PEDIDOS_DIA_REGION
SUSPEND;

ALTER PIPE
    DB_CURSO.STAGING.PIPE_PEDIDOS_RAW
SET PIPE_EXECUTION_PAUSED = TRUE;

DROP DYNAMIC TABLE
    DB_CURSO.MARTS.DT_PEDIDOS_DIA_REGION;

DROP TASK
    DB_CURSO.STAGING.TASK_MERGE_PEDIDOS_HIBRIDO;

DROP STREAM
    DB_CURSO.STAGING.STR_PEDIDOS_PIPE_RAW;

DROP PIPE
    DB_CURSO.STAGING.PIPE_PEDIDOS_RAW;

DROP TABLE
    DB_CURSO.CURATED.PEDIDOS_ACTUALES_HIBRIDO;

DROP TABLE
    DB_CURSO.STAGING.PEDIDOS_PIPE_RAW;

REMOVE @DB_CURSO.STAGING.STG_PEDIDOS_HIBRIDO;

DROP STAGE
    DB_CURSO.STAGING.STG_PEDIDOS_HIBRIDO;

DROP FILE FORMAT
    DB_CURSO.STAGING.FF_PEDIDOS_HIBRIDO_CSV;

ALTER SESSION UNSET QUERY_TAG;
```

---

## 30. Errores frecuentes

### ALTER PIPE REFRESH no carga nada

Comprueba:

- Que el fichero se subió durante los últimos siete días.
- Que el nombre coincide con `PATTERN`.
- Que el pipe está `RUNNING`.
- Que el fichero no se cargó ya.
- Que el stage y el file format existen.
- Que el rol tiene `READ` sobre el internal stage.

---

### PIPE_STATUS muestra RUNNING, pero RAW sigue vacía

`RUNNING` no significa que el pipe observe el stage cuando:

```text
AUTO_INGEST = FALSE
```

Debes enviar nombres mediante REST o usar el `REFRESH` didáctico.

---

### VALIDATE_PIPE_LOAD devuelve un error de uso

Esta función no admite pipes cuya definición utilice una transformación `FROM (SELECT ...)`.

El pipe del ejercicio utiliza una carga posicional estándar para que pueda validarse.

---

### La task no se activa

Comprueba:

- Task reanudada.
- `EXECUTE TASK`.
- Stream con datos.
- Warehouse accesible.
- Errores en `TASK_HISTORY`.

---

### La Dynamic Table no cambia

Comprueba:

- Task `SUCCEEDED`.
- CURATED modificada.
- Dynamic Table no suspendida.
- Historial de refresco.
- Modo incremental.
- Change tracking de CURATED.

Para continuar puedes ejecutar un refresco manual.

---

### RAW tiene 17 filas tras repetir REFRESH

Esto indicaría una recreación del pipe, un cambio de historial o una carga manual adicional.

Revisa `COPY_HISTORY`, el nombre del pipe y si se ejecutó `CREATE OR REPLACE PIPE` después de las cargas.

---

## 31. Respuestas a las preguntas de reflexión

### 1. ¿Por qué no una única task?

Porque mezclaría detección de ficheros, carga, CDC, lógica de negocio y agregación. Separar responsabilidades facilita escalabilidad, recuperación y observabilidad.

### 2. ¿Ventaja de RAW append-only?

Conserva todas las versiones, permite reprocesar y evita perder evidencia del origen.

### 3. ¿Qué historial evita duplicados?

Snowpipe mantiene historial de los ficheros procesados asociado al pipe; `REFRESH` también consulta el historial de la tabla.

### 4. ¿Qué ocurre al recrear el pipe?

Se elimina el historial Snowpipe del objeto y aumenta el riesgo de reintroducir ficheros conservados.

### 5. ¿Por qué no sondeo con REFRESH?

Porque está pensado para recuperación puntual de ficheros recientes, no como mecanismo continuo. Las notificaciones o REST son más eficientes y fiables.

### 6. ¿Qué parte es declarativa?

La Dynamic Table. La task con `MERGE` representa lógica procedural controlada.

### 7. ¿Qué usar para backfill?

`COPY INTO` directamente, especialmente para grandes volúmenes históricos.

### 8. ¿Qué usar si el productor confirma ficheros?

Snowpipe con API REST e `insertFiles`.

### 9. ¿Dónde se consume cómputo?

Snowpipe utiliza cómputo serverless. La task y la Dynamic Table utilizan `WH_DEV`.

### 10. ¿Qué alertas?

Estado detenido, errores, cola creciente, stream próximo a stale, task fallida, lag de Dynamic Table y discrepancias de reconciliación.

---


# Módulo 7 · Ejercicio 4

## Solución guiada: pipeline automático con Snowpipe, Amazon S3, streams y triggered tasks

---

## 1. Arquitectura

```text
Amazon S3
<bucket>/entrada/*.csv
        │
        │ S3 ObjectCreated
        ▼
Cola SQS administrada por Snowflake
        │
        ▼
DB_CURSO.STAGING.PIPE_PEDIDOS_AUTO
        │
        ▼
DB_CURSO.STAGING.PEDIDOS_RAW
        │
        └── STR_PEDIDOS_RAW
                    │
                    └── TASK_RAW_A_CURATED
                                │
                                ▼
               DB_CURSO.CURATED.PEDIDOS_ACTUALES
                                │
                                └── STR_PEDIDOS_CURATED
                                            │
                                            └── TASK_CURATED_A_MART
                                                        │
                                                        ▼
                                      DB_CURSO.MART.VENTAS_DIARIAS
```

### Responsabilidad de cada componente

| Componente | Responsabilidad |
|---|---|
| Amazon S3 | Recibir y conservar los archivos |
| Evento S3 | Informar de la creación de un objeto |
| SQS de Snowflake | Entregar las notificaciones al servicio |
| Snowpipe | Ejecutar cargas serverless en microbatches |
| `PEDIDOS_RAW` | Conservar eventos y metadatos técnicos |
| `STR_PEDIDOS_RAW` | Exponer eventos RAW no procesados |
| `TASK_RAW_A_CURATED` | Tipar, deduplicar y consolidar |
| `PEDIDOS_ACTUALES` | Mantener la versión vigente por pedido |
| `STR_PEDIDOS_CURATED` | Exponer cambios en el estado actual |
| `TASK_CURATED_A_MART` | Recalcular fechas afectadas |
| `VENTAS_DIARIAS` | Servir métricas de negocio |

Snowpipe no transforma todo el modelo analítico. Su función en esta arquitectura es cargar continuamente los archivos en la capa de aterrizaje.

---

## 2. Elegir nombres únicos

Cada participante debe elegir un alias en minúsculas:

```text
<ALIAS>
```

Ejemplo:

```text
alumno1
```

Define nombres siguiendo estos patrones:

```text
Bucket:
sf-m7-snowpipe-<alias>-<sufijo-unico>

Política:
SnowflakeSnowpipeS3ReadPolicy_<ALIAS>

Rol:
SnowflakeSnowpipeS3ReadRole_<ALIAS>

Notificación:
snowpipe-pedidos-<alias>
```

También necesitarás conocer:

```text
<AWS_ACCOUNT_ID>
<S3_BUCKET_NAME>
<IAM_ROLE_NAME>
<IAM_ROLE_ARN>
<SNOWFLAKE_IAM_USER_ARN>
<SNOWFLAKE_EXTERNAL_ID>
<SNOWPIPE_SQS_ARN>
```

No copies valores de otro participante.

---

## 3. Crear los archivos CSV

Crea los tres archivos localmente y guárdalos en UTF-8.

### 3.1 `pedidos_01.csv`

```csv
event_id,id_pedido,id_cliente,fecha_pedido,region,producto,cantidad,precio_unitario,estado,fecha_modificacion
1,9101,2001,2026-07-01,NORTE,Teclado,2,30.00,PENDIENTE,2026-07-01 09:00:00
2,9101,2001,2026-07-01,NORTE,Teclado,2,30.00,COMPLETADA,2026-07-01 09:05:00
3,9102,2002,2026-07-01,SUR,Monitor,1,250.00,COMPLETADA,2026-07-01 09:10:00
4,9103,2003,2026-07-01,CENTRO,Raton,3,20.00,CANCELADA,2026-07-01 09:15:00
5,9104,2004,2026-07-02,NORTE,Auriculares,2,45.00,PENDIENTE,2026-07-02 10:00:00
6,9105,2005,2026-07-02,ESTE,Webcam,1,80.00,COMPLETADA,2026-07-02 10:10:00
```

El pedido `9101` aparece dos veces. CURATED debe conservar el evento `2`.

### 3.2 `pedidos_02.csv`

```csv
event_id,id_pedido,id_cliente,fecha_pedido,region,producto,cantidad,precio_unitario,estado,fecha_modificacion
7,9104,2004,2026-07-02,NORTE,Auriculares,2,45.00,COMPLETADA,2026-07-02 10:30:00
8,9102,2002,2026-07-01,SUR,Monitor,1,250.00,CANCELADA,2026-07-01 11:00:00
9,9106,2006,2026-07-02,SUR,SSD,2,70.00,COMPLETADA,2026-07-02 11:10:00
10,9107,2007,2026-07-03,CENTRO,Portatil,1,900.00,PENDIENTE,2026-07-03 11:20:00
11,9107,2007,2026-07-03,CENTRO,Portatil,1,900.00,COMPLETADA,2026-07-03 11:25:00
```

Este microbatch:

- Completa `9104`.
- Cancela `9102`.
- Inserta `9106`.
- Incluye dos versiones de `9107`.

### 3.3 `pedidos_03_tardio.csv`

```csv
event_id,id_pedido,id_cliente,fecha_pedido,region,producto,cantidad,precio_unitario,estado,fecha_modificacion
12,9104,2004,2026-07-02,NORTE,Auriculares,2,45.00,PENDIENTE,2026-07-02 09:30:00
```

La versión vigente de `9104` será posterior a las `10:30`. El evento de las `09:30` debe cargarse en RAW, pero no aplicarse en CURATED.

No subas todavía estos archivos.

---

# PARTE A · CONFIGURACIÓN EN AWS

## 4. Crear el bucket S3

Este paso lo realiza cada participante dentro de la cuenta AWS proporcionada.

1. Abre **Amazon S3**.
2. Selecciona **Create bucket**.
3. Introduce:

   ```text
   <S3_BUCKET_NAME>
   ```

4. Utiliza la región indicada por el instructor.
5. Mantén:

   ```text
   Block all public access = Enabled
   ```

6. Mantén deshabilitadas las ACL.
7. Crea el bucket.
8. Dentro del bucket, crea la carpeta:

   ```text
   entrada
   ```

La ruta será:

```text
s3://<S3_BUCKET_NAME>/entrada/
```

No subas todavía los CSV de negocio.

---

## 5. Crear la política IAM

Abre:

```text
IAM → Policies → Create policy → JSON
```

Pega:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ListSnowpipeInputPrefix",
      "Effect": "Allow",
      "Action": [
        "s3:GetBucketLocation",
        "s3:ListBucket"
      ],
      "Resource": "arn:aws:s3:::<S3_BUCKET_NAME>",
      "Condition": {
        "StringLike": {
          "s3:prefix": [
            "entrada",
            "entrada/*"
          ]
        }
      }
    },
    {
      "Sid": "ReadSnowpipeInputObjects",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:GetObjectVersion"
      ],
      "Resource": "arn:aws:s3:::<S3_BUCKET_NAME>/entrada/*"
    }
  ]
}
```

Sustituye:

```text
<S3_BUCKET_NAME>
```

Asigna a la política:

```text
SnowflakeSnowpipeS3ReadPolicy_<ALIAS>
```

### Por qué hay dos recursos

Permisos de bucket:

```text
arn:aws:s3:::<S3_BUCKET_NAME>
```

Permisos de objeto:

```text
arn:aws:s3:::<S3_BUCKET_NAME>/entrada/*
```

`ListBucket` se autoriza sobre el bucket.

`GetObject` se autoriza sobre los objetos.

---

## 6. Crear el rol IAM provisional

Abre:

```text
IAM → Roles → Create role
```

Configura:

1. **Trusted entity type**:

   ```text
   AWS account
   ```

2. Cuenta de confianza provisional:

   ```text
   <AWS_ACCOUNT_ID>
   ```

3. Activa el requisito de `External ID`.
4. Introduce temporalmente:

   ```text
   TEMPORAL
   ```

5. Adjunta:

   ```text
   SnowflakeSnowpipeS3ReadPolicy_<ALIAS>
   ```

6. Nombre:

   ```text
   SnowflakeSnowpipeS3ReadRole_<ALIAS>
   ```

7. Crea el rol.

Comprueba en:

```text
IAM → Roles → <IAM_ROLE_NAME> → Permissions
```

que la política aparece realmente adjunta.

Copia el ARN:

```text
<IAM_ROLE_ARN>
```

Formato:

```text
arn:aws:iam::<AWS_ACCOUNT_ID>:role/<IAM_ROLE_NAME>
```

---

# PARTE B · CONFIGURACIÓN BASE EN SNOWFLAKE

## 7. Preparar Workspaces, warehouse y esquemas

En **Workspaces**, crea:

```text
M07_E02_SNOWPIPE_S3_PIPELINE.sql
```

Ejecuta:

```sql
USE ROLE ACCOUNTADMIN;

GRANT EXECUTE TASK
ON ACCOUNT
TO ROLE SYSADMIN;

CREATE WAREHOUSE IF NOT EXISTS WH_DEV
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE;

CREATE DATABASE IF NOT EXISTS DB_CURSO;
CREATE SCHEMA IF NOT EXISTS DB_CURSO.STAGING;
CREATE SCHEMA IF NOT EXISTS DB_CURSO.CURATED;
CREATE SCHEMA IF NOT EXISTS DB_CURSO.MART;

USE ROLE SYSADMIN;
USE WAREHOUSE WH_DEV;
USE DATABASE DB_CURSO;
USE SCHEMA STAGING;

ALTER SESSION SET QUERY_TAG = 'M07_E02_SNOWPIPE_S3_PIPELINE';
```

Comprueba:

```sql
SELECT
    CURRENT_ROLE()      AS rol,
    CURRENT_WAREHOUSE() AS warehouse,
    CURRENT_DATABASE()  AS base_datos,
    CURRENT_SCHEMA()    AS esquema,
    CURRENT_ACCOUNT()   AS cuenta;
```

---

## 8. Crear la storage integration

Vuelve temporalmente a `ACCOUNTADMIN`:

```sql
USE ROLE ACCOUNTADMIN;

CREATE STORAGE INTEGRATION S3_SNOWPIPE_INT
    TYPE = EXTERNAL_STAGE
    STORAGE_PROVIDER = 'S3'
    ENABLED = TRUE
    STORAGE_AWS_ROLE_ARN = '<IAM_ROLE_ARN>'
    STORAGE_ALLOWED_LOCATIONS = (
        's3://<S3_BUCKET_NAME>/entrada/'
    );
```

Sustituye:

```text
<IAM_ROLE_ARN>
<S3_BUCKET_NAME>
```

Concede uso a `SYSADMIN`:

```sql
GRANT USAGE
ON INTEGRATION S3_SNOWPIPE_INT
TO ROLE SYSADMIN;
```

No recrees la integración después de configurar la trust policy salvo que estés dispuesto a volver a actualizar el `External ID`.

---

## 9. Obtener los valores generados por Snowflake

Ejecuta:

```sql
DESC INTEGRATION S3_SNOWPIPE_INT;
```

Sin ejecutar otra consulta entre medias:

```sql
SELECT
    "property",
    "property_value"
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
WHERE "property" IN (
    'STORAGE_AWS_IAM_USER_ARN',
    'STORAGE_AWS_EXTERNAL_ID'
)
ORDER BY "property";
```

Guarda:

```text
<SNOWFLAKE_IAM_USER_ARN>
<SNOWFLAKE_EXTERNAL_ID>
```

---

# PARTE C · COMPLETAR LA CONFIANZA EN AWS

## 10. Actualizar la trust policy

En AWS abre:

```text
IAM → Roles → <IAM_ROLE_NAME> → Trust relationships
```

Selecciona:

```text
Edit trust policy
```

Sustituye la política provisional por:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowSnowflakeStorageIntegration",
      "Effect": "Allow",
      "Principal": {
        "AWS": "<SNOWFLAKE_IAM_USER_ARN>"
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": {
          "sts:ExternalId": "<SNOWFLAKE_EXTERNAL_ID>"
        }
      }
    }
  ]
}
```

Sustituye ambos marcadores.

### Dos políticas distintas

Trust policy:

```text
¿Quién puede asumir el rol?
```

Permissions policy:

```text
¿Qué puede hacer el rol después de ser asumido?
```

Snowflake necesita que ambas sean correctas.

---

## 11. Validar la integración con un archivo temporal

Crea localmente:

```text
validacion.txt
```

Contenido:

```text
prueba de acceso
```

Súbelo a:

```text
s3://<S3_BUCKET_NAME>/entrada/validacion.txt
```

En Snowflake:

```sql
USE ROLE ACCOUNTADMIN;

SELECT SYSTEM$VALIDATE_STORAGE_INTEGRATION(
    'S3_SNOWPIPE_INT',
    's3://<S3_BUCKET_NAME>/entrada/',
    'validacion.txt',
    'read'
);
```

Resultado esperado:

```json
{
  "status": "success"
}
```

Elimina `validacion.txt` de S3.

Este archivo se carga antes de crear el pipe y no tiene extensión `.csv`, por lo que no forma parte del pipeline.

---

# PARTE D · OBJETOS DE DATOS

## 12. Crear el file format

```sql
USE ROLE SYSADMIN;
USE WAREHOUSE WH_DEV;
USE DATABASE DB_CURSO;
USE SCHEMA STAGING;

CREATE OR REPLACE FILE FORMAT FF_PEDIDOS_CSV
    TYPE = CSV
    FIELD_DELIMITER = ','
    SKIP_HEADER = 1
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    TRIM_SPACE = TRUE
    EMPTY_FIELD_AS_NULL = TRUE
    NULL_IF = ('NULL', 'null', '')
    ERROR_ON_COLUMN_COUNT_MISMATCH = TRUE
    ENCODING = 'UTF8';
```

---

## 13. Crear el external stage

```sql
CREATE OR REPLACE STAGE STG_S3_PEDIDOS
    URL = 's3://<S3_BUCKET_NAME>/entrada/'
    STORAGE_INTEGRATION = S3_SNOWPIPE_INT
    FILE_FORMAT = FF_PEDIDOS_CSV;
```

Comprueba la definición:

```sql
DESC STAGE STG_S3_PEDIDOS;
```

Lista la ubicación:

```sql
LIST @STG_S3_PEDIDOS;
```

Debe estar vacía después de eliminar `validacion.txt`.

---

## 14. Crear la tabla RAW

```sql
CREATE OR REPLACE TRANSIENT TABLE
    DB_CURSO.STAGING.PEDIDOS_RAW (
        event_id                VARCHAR,
        id_pedido               VARCHAR,
        id_cliente              VARCHAR,
        fecha_pedido            VARCHAR,
        region                  VARCHAR,
        producto                VARCHAR,
        cantidad                VARCHAR,
        precio_unitario         VARCHAR,
        estado                  VARCHAR,
        fecha_modificacion      VARCHAR,
        _source_file            VARCHAR,
        _source_row_number      NUMBER,
        _file_last_modified     TIMESTAMP_NTZ,
        _loaded_at              TIMESTAMP_LTZ
    );
```

### Por qué los campos RAW son texto

La capa RAW conserva el contenido recibido con el mínimo tratamiento posible.

El tipado y las reglas de negocio se aplicarán en CURATED.

---

## 15. Crear la tabla CURATED

```sql
CREATE OR REPLACE TABLE
    DB_CURSO.CURATED.PEDIDOS_ACTUALES (
        id_pedido               NUMBER(18,0),
        id_cliente              NUMBER(18,0),
        fecha_pedido            DATE,
        region                  VARCHAR(20),
        producto                VARCHAR(100),
        cantidad                NUMBER(10,0),
        precio_unitario         NUMBER(12,2),
        importe_linea           NUMBER(14,2),
        estado                  VARCHAR(20),
        fecha_modificacion      TIMESTAMP_NTZ,
        event_id                NUMBER(18,0),
        _source_file            VARCHAR,
        _source_row_number      NUMBER,
        _file_last_modified     TIMESTAMP_NTZ,
        _loaded_at              TIMESTAMP_LTZ,
        _processed_at           TIMESTAMP_LTZ
    );
```

La clave lógica es:

```text
id_pedido
```

---

## 16. Crear la tabla MART

```sql
CREATE OR REPLACE TABLE
    DB_CURSO.MARTS.VENTAS_DIARIAS (
        fecha_pedido            DATE,
        pedidos_total           NUMBER(18,0),
        pedidos_completados     NUMBER(18,0),
        pedidos_cancelados      NUMBER(18,0),
        pedidos_pendientes      NUMBER(18,0),
        unidades_vendidas       NUMBER(18,0),
        importe_ventas          NUMBER(14,2),
        _updated_at             TIMESTAMP_LTZ
    );
```

---

## 17. Crear los streams antes de cargar datos

### Stream RAW

```sql
CREATE OR REPLACE STREAM
    DB_CURSO.STAGING.STR_PEDIDOS_RAW
ON TABLE DB_CURSO.STAGING.PEDIDOS_RAW
APPEND_ONLY = TRUE;
```

RAW funciona como log append-only.

### Stream CURATED

```sql
CREATE OR REPLACE STREAM
    DB_CURSO.CURATED.STR_PEDIDOS_CURATED
ON TABLE DB_CURSO.CURATED.PEDIDOS_ACTUALES;
```

Este stream es estándar porque CURATED recibe inserciones y actualizaciones.

Comprueba:

```sql
SHOW STREAMS IN DATABASE DB_CURSO;
```

```sql
SELECT SYSTEM$STREAM_HAS_DATA(
    'DB_CURSO.STAGING.STR_PEDIDOS_RAW'
) AS raw_con_datos;
```

```sql
SELECT SYSTEM$STREAM_HAS_DATA(
    'DB_CURSO.CURATED.STR_PEDIDOS_CURATED'
) AS curated_con_datos;
```

Ambos deben devolver `FALSE`.

---

# PARTE E · TRANSFORMACIONES AUTOMÁTICAS

## 18. Crear la triggered task RAW → CURATED

```sql
CREATE OR REPLACE TASK
    DB_CURSO.STAGING.TASK_RAW_A_CURATED

    WAREHOUSE = WH_DEV

    USER_TASK_MINIMUM_TRIGGER_INTERVAL_IN_SECONDS = 10

    WHEN SYSTEM$STREAM_HAS_DATA(
        'DB_CURSO.STAGING.STR_PEDIDOS_RAW'
    )

AS

MERGE INTO DB_CURSO.CURATED.PEDIDOS_ACTUALES AS destino

USING (
    WITH TIPADO AS (
        SELECT
            TO_NUMBER(event_id) AS event_id,
            TO_NUMBER(id_pedido) AS id_pedido,
            TO_NUMBER(id_cliente) AS id_cliente,
            TO_DATE(fecha_pedido, 'YYYY-MM-DD') AS fecha_pedido,
            UPPER(region) AS region,
            producto,
            TO_NUMBER(cantidad) AS cantidad,
            TO_DECIMAL(precio_unitario, 12, 2) AS precio_unitario,
            UPPER(estado) AS estado,
            TO_TIMESTAMP_NTZ(
                fecha_modificacion,
                'YYYY-MM-DD HH24:MI:SS'
            ) AS fecha_modificacion,
            _source_file,
            _source_row_number,
            _file_last_modified,
            _loaded_at

        FROM DB_CURSO.STAGING.STR_PEDIDOS_RAW

        WHERE METADATA$ACTION = 'INSERT'
    )

    SELECT
        event_id,
        id_pedido,
        id_cliente,
        fecha_pedido,
        region,
        producto,
        cantidad,
        precio_unitario,
        cantidad * precio_unitario AS importe_linea,
        estado,
        fecha_modificacion,
        _source_file,
        _source_row_number,
        _file_last_modified,
        _loaded_at

    FROM TIPADO

    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY id_pedido
        ORDER BY
            fecha_modificacion DESC,
            event_id DESC,
            _loaded_at DESC
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
    destino.producto = origen.producto,
    destino.cantidad = origen.cantidad,
    destino.precio_unitario = origen.precio_unitario,
    destino.importe_linea = origen.importe_linea,
    destino.estado = origen.estado,
    destino.fecha_modificacion = origen.fecha_modificacion,
    destino.event_id = origen.event_id,
    destino._source_file = origen._source_file,
    destino._source_row_number = origen._source_row_number,
    destino._file_last_modified = origen._file_last_modified,
    destino._loaded_at = origen._loaded_at,
    destino._processed_at = CURRENT_TIMESTAMP()

WHEN NOT MATCHED
THEN INSERT (
    id_pedido,
    id_cliente,
    fecha_pedido,
    region,
    producto,
    cantidad,
    precio_unitario,
    importe_linea,
    estado,
    fecha_modificacion,
    event_id,
    _source_file,
    _source_row_number,
    _file_last_modified,
    _loaded_at,
    _processed_at
)
VALUES (
    origen.id_pedido,
    origen.id_cliente,
    origen.fecha_pedido,
    origen.region,
    origen.producto,
    origen.cantidad,
    origen.precio_unitario,
    origen.importe_linea,
    origen.estado,
    origen.fecha_modificacion,
    origen.event_id,
    origen._source_file,
    origen._source_row_number,
    origen._file_last_modified,
    origen._loaded_at,
    CURRENT_TIMESTAMP()
);
```

### Qué hace

1. Lee únicamente inserciones del stream append-only.
2. Convierte los textos.
3. Deduplica cada microbatch.
4. Compara la versión de negocio.
5. Inserta o actualiza.
6. Ignora eventos antiguos.
7. Avanza el offset al confirmar el `MERGE`.

---

## 19. Crear la triggered task CURATED → MART

```sql
CREATE OR REPLACE TASK
    DB_CURSO.CURATED.TASK_CURATED_A_MART

    WAREHOUSE = WH_DEV

    USER_TASK_MINIMUM_TRIGGER_INTERVAL_IN_SECONDS = 10

    WHEN SYSTEM$STREAM_HAS_DATA(
        'DB_CURSO.CURATED.STR_PEDIDOS_CURATED'
    )

AS

MERGE INTO DB_CURSO.MARTS.VENTAS_DIARIAS AS destino

USING (
    WITH FECHAS_AFECTADAS AS (
        SELECT DISTINCT
            fecha_pedido

        FROM DB_CURSO.CURATED.STR_PEDIDOS_CURATED
    ),

    RESUMEN AS (
        SELECT
            pedidos.fecha_pedido,

            COUNT(*) AS pedidos_total,

            COUNT_IF(
                pedidos.estado = 'COMPLETADA'
            ) AS pedidos_completados,

            COUNT_IF(
                pedidos.estado = 'CANCELADA'
            ) AS pedidos_cancelados,

            COUNT_IF(
                pedidos.estado = 'PENDIENTE'
            ) AS pedidos_pendientes,

            SUM(
                IFF(
                    pedidos.estado = 'COMPLETADA',
                    pedidos.cantidad,
                    0
                )
            )::NUMBER(18,0) AS unidades_vendidas,

            SUM(
                IFF(
                    pedidos.estado = 'COMPLETADA',
                    pedidos.importe_linea,
                    0
                )
            )::NUMBER(14,2) AS importe_ventas,

            CURRENT_TIMESTAMP() AS _updated_at

        FROM DB_CURSO.CURATED.PEDIDOS_ACTUALES AS pedidos

        INNER JOIN FECHAS_AFECTADAS AS fechas
            ON pedidos.fecha_pedido = fechas.fecha_pedido

        GROUP BY pedidos.fecha_pedido
    )

    SELECT *
    FROM RESUMEN
) AS origen

ON destino.fecha_pedido = origen.fecha_pedido

WHEN MATCHED
THEN UPDATE SET
    destino.pedidos_total = origen.pedidos_total,
    destino.pedidos_completados = origen.pedidos_completados,
    destino.pedidos_cancelados = origen.pedidos_cancelados,
    destino.pedidos_pendientes = origen.pedidos_pendientes,
    destino.unidades_vendidas = origen.unidades_vendidas,
    destino.importe_ventas = origen.importe_ventas,
    destino._updated_at = origen._updated_at

WHEN NOT MATCHED
THEN INSERT (
    fecha_pedido,
    pedidos_total,
    pedidos_completados,
    pedidos_cancelados,
    pedidos_pendientes,
    unidades_vendidas,
    importe_ventas,
    _updated_at
)
VALUES (
    origen.fecha_pedido,
    origen.pedidos_total,
    origen.pedidos_completados,
    origen.pedidos_cancelados,
    origen.pedidos_pendientes,
    origen.unidades_vendidas,
    origen.importe_ventas,
    origen._updated_at
);
```

### Por qué se recalculan las fechas afectadas

Un cambio de estado puede modificar simultáneamente:

- El número de completados.
- El número de cancelados.
- Las unidades vendidas.
- El importe.

Recalcular desde la tabla CURATED actual evita aplicar deltas incorrectos.

### Supuesto del ejercicio

Durante este laboratorio:

- No se eliminan pedidos de CURATED.
- `fecha_pedido` no cambia entre versiones de un mismo pedido.

En un pipeline que permitiese borrar pedidos o cambiar su fecha, habría que tratar también fechas que quedaran sin filas y eliminar agregados obsoletos.

---

# PARTE F · CREAR Y AUTOMATIZAR SNOWPIPE

## 20. Crear el pipe

```sql
CREATE OR REPLACE PIPE
    DB_CURSO.STAGING.PIPE_PEDIDOS_AUTO

    AUTO_INGEST = TRUE

    COMMENT = 'Carga automática de pedidos desde Amazon S3'

AS

COPY INTO DB_CURSO.STAGING.PEDIDOS_RAW (
    event_id,
    id_pedido,
    id_cliente,
    fecha_pedido,
    region,
    producto,
    cantidad,
    precio_unitario,
    estado,
    fecha_modificacion,
    _source_file,
    _source_row_number,
    _file_last_modified,
    _loaded_at
)

FROM (
    SELECT
        archivo.$1::VARCHAR,
        archivo.$2::VARCHAR,
        archivo.$3::VARCHAR,
        archivo.$4::VARCHAR,
        archivo.$5::VARCHAR,
        archivo.$6::VARCHAR,
        archivo.$7::VARCHAR,
        archivo.$8::VARCHAR,
        archivo.$9::VARCHAR,
        archivo.$10::VARCHAR,
        METADATA$FILENAME,
        METADATA$FILE_ROW_NUMBER,
        METADATA$FILE_LAST_MODIFIED,
        METADATA$START_SCAN_TIME

    FROM @DB_CURSO.STAGING.STG_S3_PEDIDOS archivo
)

PATTERN = '.*[.]csv'

ON_ERROR = 'CONTINUE';
```

### Aspectos importantes

- `AUTO_INGEST = TRUE` habilita la carga por notificaciones.
- Snowpipe utiliza cómputo serverless.
- No utiliza `WH_DEV`.
- `METADATA$START_SCAN_TIME` representa mejor el momento de carga que `CURRENT_TIMESTAMP` dentro del pipe.
- `PATTERN` limita el pipe a archivos CSV.
- El filtro principal se configurará también en S3 para reducir eventos innecesarios.
- `ON_ERROR = 'ABORT_STATEMENT'` no es una opción admitida en la definición de un pipe.

### No recrear el pipe después de configurar S3

Utiliza `CREATE OR REPLACE PIPE` únicamente durante la creación inicial del laboratorio.

Después de configurar la notificación S3:

- No recrees el pipe para repetir una prueba.
- La recreación elimina el historial de carga asociado al pipe.
- Vuelve a comprobar `notification_channel` si el pipe se ha recreado.
- Utiliza archivos con nombres nuevos para nuevas pruebas.

Comprueba:

```sql
DESC PIPE DB_CURSO.STAGING.PIPE_PEDIDOS_AUTO;
```

```sql
SHOW PIPES LIKE 'PIPE_PEDIDOS_AUTO'
IN SCHEMA DB_CURSO.STAGING;
```

---

## 21. Obtener el ARN de la cola SQS

Después de `SHOW PIPES`, ejecuta inmediatamente:

```sql
SELECT
    "name",
    "database_name",
    "schema_name",
    "definition",
    "notification_channel"

FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
```

Copia:

```text
<SNOWPIPE_SQS_ARN>
```

El valor tendrá estructura de ARN de SQS, pero no debes fijar ningún identificador manualmente.

Snowflake crea y administra la cola.

---

## 22. Configurar la notificación en S3

En AWS:

```text
S3 → <S3_BUCKET_NAME> → Properties → Event notifications
```

Selecciona:

```text
Create event notification
```

Configura:

| Campo | Valor |
|---|---|
| Nombre | `snowpipe-pedidos-<alias>` |
| Prefix | `entrada/` |
| Suffix | `.csv` |
| Event types | `All object create events` |
| Destination | `SQS queue` |
| SQS | `Specify SQS queue ARN` |
| SQS queue ARN | `<SNOWPIPE_SQS_ARN>` |

Guarda la notificación.

### Por qué todos los eventos de creación

Los archivos pequeños suelen producir eventos `Put`.

Las cargas multipart pueden producir `CompleteMultipartUpload`.

Seleccionar todos los eventos de creación evita perder archivos por el mecanismo utilizado durante la subida.

---

## 23. Reanudar las triggered tasks

Las tasks se crean suspendidas.

Reanuda primero la task de MART:

```sql
ALTER TASK
    DB_CURSO.CURATED.TASK_CURATED_A_MART
RESUME;
```

Después la task RAW:

```sql
ALTER TASK
    DB_CURSO.STAGING.TASK_RAW_A_CURATED
RESUME;
```

Comprueba:

```sql
SHOW TASKS IN DATABASE DB_CURSO;
```

---

## 24. Comprobar el estado inicial

```sql
SELECT SYSTEM$PIPE_STATUS(
    'DB_CURSO.STAGING.PIPE_PEDIDOS_AUTO'
) AS pipe_status;
```

```sql
SELECT COUNT(*) AS filas_raw
FROM DB_CURSO.STAGING.PEDIDOS_RAW;
```

```sql
SELECT COUNT(*) AS pedidos_curated
FROM DB_CURSO.CURATED.PEDIDOS_ACTUALES;
```

```sql
SELECT COUNT(*) AS fechas_mart
FROM DB_CURSO.MARTS.VENTAS_DIARIAS;
```

Todo debe estar vacío.

---

# PARTE G · PRIMER MICROBATCH

## 25. Subir `pedidos_01.csv`

En S3:

```text
<S3_BUCKET_NAME>/entrada/
```

Sube:

```text
pedidos_01.csv
```

No ejecutes un `COPY INTO` manual.

---

## 26. Monitorizar Snowpipe

### Estado general

```sql
SELECT SYSTEM$PIPE_STATUS(
    'DB_CURSO.STAGING.PIPE_PEDIDOS_AUTO'
) AS pipe_status;
```

Entre los campos del JSON pueden aparecer:

```text
executionState
pendingFileCount
notificationChannelName
numOutstandingMessagesOnChannel
lastReceivedMessageTimestamp
lastForwardedMessageTimestamp
error
fault
```

### Historial de carga

```sql
SELECT
    file_name,
    status,
    row_count,
    row_parsed,
    error_count,
    first_error_message,
    last_load_time,
    pipe_received_time,
    pipe_name,
    bytes_billed

FROM TABLE(
    DB_CURSO.INFORMATION_SCHEMA.COPY_HISTORY(
        TABLE_NAME => 'DB_CURSO.STAGING.PEDIDOS_RAW',
        START_TIME => DATEADD(
            'hour',
            -1,
            CURRENT_TIMESTAMP()
        )
    )
)

ORDER BY last_load_time DESC;
```

Resultado esperado para `pedidos_01.csv`:

```text
STATUS = Loaded
ROW_COUNT = 6
ERROR_COUNT = 0
```

---

## 27. Validar RAW

```sql
SELECT *
FROM DB_CURSO.STAGING.PEDIDOS_RAW
ORDER BY TO_NUMBER(event_id);
```

Comprueba los metadatos:

```sql
SELECT
    _source_file,
    COUNT(*) AS filas,
    MIN(_source_row_number) AS primera_fila,
    MAX(_source_row_number) AS ultima_fila,
    MIN(_loaded_at) AS primera_carga,
    MAX(_loaded_at) AS ultima_carga

FROM DB_CURSO.STAGING.PEDIDOS_RAW

GROUP BY _source_file;
```

Resultado:

```text
6 filas
source row numbers 1 a 6
```

---

## 28. Monitorizar las triggered tasks

### RAW → CURATED

```sql
SELECT
    name,
    state,
    scheduled_from,
    scheduled_time,
    query_start_time,
    completed_time,
    query_id,
    error_code,
    error_message

FROM TABLE(
    DB_CURSO.INFORMATION_SCHEMA.TASK_HISTORY(
        SCHEDULED_TIME_RANGE_START
            => DATEADD('hour', -1, CURRENT_TIMESTAMP()),

        SCHEDULED_TIME_RANGE_END
            => CURRENT_TIMESTAMP(),

        RESULT_LIMIT => 20,

        TASK_NAME => 'TASK_RAW_A_CURATED'
    )
)

WHERE query_id IS NOT NULL

ORDER BY scheduled_time DESC;
```

### CURATED → MART

```sql
SELECT
    name,
    state,
    scheduled_from,
    scheduled_time,
    query_start_time,
    completed_time,
    query_id,
    error_code,
    error_message

FROM TABLE(
    DB_CURSO.INFORMATION_SCHEMA.TASK_HISTORY(
        SCHEDULED_TIME_RANGE_START
            => DATEADD('hour', -1, CURRENT_TIMESTAMP()),

        SCHEDULED_TIME_RANGE_END
            => CURRENT_TIMESTAMP(),

        RESULT_LIMIT => 20,

        TASK_NAME => 'TASK_CURATED_A_MART'
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

---

## 29. Validar CURATED tras el primer archivo

```sql
SELECT
    id_pedido,
    id_cliente,
    fecha_pedido,
    region,
    producto,
    cantidad,
    precio_unitario,
    importe_linea,
    estado,
    fecha_modificacion,
    event_id

FROM DB_CURSO.CURATED.PEDIDOS_ACTUALES

ORDER BY id_pedido;
```

Resultado esperado:

| ID_PEDIDO | FECHA | PRODUCTO | IMPORTE | ESTADO | EVENT_ID |
|---:|---|---|---:|---|---:|
| 9101 | 2026-07-01 | Teclado | 60.00 | COMPLETADA | 2 |
| 9102 | 2026-07-01 | Monitor | 250.00 | COMPLETADA | 3 |
| 9103 | 2026-07-01 | Raton | 60.00 | CANCELADA | 4 |
| 9104 | 2026-07-02 | Auriculares | 90.00 | PENDIENTE | 5 |
| 9105 | 2026-07-02 | Webcam | 80.00 | COMPLETADA | 6 |

Comprobación:

```sql
SELECT
    COUNT(*) AS pedidos,
    COUNT(DISTINCT id_pedido) AS pedidos_distintos
FROM DB_CURSO.CURATED.PEDIDOS_ACTUALES;
```

Resultado:

```text
5 pedidos
5 pedidos distintos
```

---

## 30. Validar MART tras el primer archivo

```sql
SELECT *
FROM DB_CURSO.MARTS.VENTAS_DIARIAS
ORDER BY fecha_pedido;
```

Resultado esperado:

| FECHA_PEDIDO | TOTAL | COMPLETADOS | CANCELADOS | PENDIENTES | UNIDADES | IMPORTE |
|---|---:|---:|---:|---:|---:|---:|
| 2026-07-01 | 3 | 2 | 1 | 0 | 3 | 310.00 |
| 2026-07-02 | 2 | 1 | 0 | 1 | 1 | 80.00 |

Comprueba los streams:

```sql
SELECT
    SYSTEM$STREAM_HAS_DATA(
        'DB_CURSO.STAGING.STR_PEDIDOS_RAW'
    ) AS raw_con_datos,

    SYSTEM$STREAM_HAS_DATA(
        'DB_CURSO.CURATED.STR_PEDIDOS_CURATED'
    ) AS curated_con_datos;
```

Resultado esperado:

```text
FALSE
FALSE
```

---

# PARTE H · SEGUNDO MICROBATCH

## 31. Subir `pedidos_02.csv`

Sube el archivo con un nombre nuevo:

```text
s3://<S3_BUCKET_NAME>/entrada/pedidos_02.csv
```

Snowpipe y las tasks procesarán el archivo automáticamente.

---

## 32. Validar el segundo procesamiento

RAW:

```sql
SELECT COUNT(*) AS eventos
FROM DB_CURSO.STAGING.PEDIDOS_RAW;
```

Resultado:

```text
11
```

CURATED:

```sql
SELECT
    id_pedido,
    importe_linea,
    estado,
    fecha_modificacion,
    event_id
FROM DB_CURSO.CURATED.PEDIDOS_ACTUALES
ORDER BY id_pedido;
```

Resultado esperado:

| ID_PEDIDO | IMPORTE | ESTADO | EVENT_ID |
|---:|---:|---|---:|
| 9101 | 60.00 | COMPLETADA | 2 |
| 9102 | 250.00 | CANCELADA | 8 |
| 9103 | 60.00 | CANCELADA | 4 |
| 9104 | 90.00 | COMPLETADA | 7 |
| 9105 | 80.00 | COMPLETADA | 6 |
| 9106 | 140.00 | COMPLETADA | 9 |
| 9107 | 900.00 | COMPLETADA | 11 |

Resumen:

```sql
SELECT
    COUNT(*) AS pedidos,
    COUNT_IF(estado = 'COMPLETADA') AS completados,
    COUNT_IF(estado = 'CANCELADA') AS cancelados,
    COUNT_IF(estado = 'PENDIENTE') AS pendientes,

    SUM(
        IFF(
            estado = 'COMPLETADA',
            cantidad,
            0
        )
    ) AS unidades_vendidas,

    SUM(
        IFF(
            estado = 'COMPLETADA',
            importe_linea,
            0
        )
    ) AS importe_ventas

FROM DB_CURSO.CURATED.PEDIDOS_ACTUALES;
```

Resultado:

| PEDIDOS | COMPLETADOS | CANCELADOS | PENDIENTES | UNIDADES | IMPORTE |
|---:|---:|---:|---:|---:|---:|
| 7 | 5 | 2 | 0 | 8 | 1270.00 |

---

## 33. Validar MART final

```sql
SELECT
    fecha_pedido,
    pedidos_total,
    pedidos_completados,
    pedidos_cancelados,
    pedidos_pendientes,
    unidades_vendidas,
    importe_ventas

FROM DB_CURSO.MARTS.VENTAS_DIARIAS

ORDER BY fecha_pedido;
```

Resultado:

| FECHA_PEDIDO | TOTAL | COMPLETADOS | CANCELADOS | PENDIENTES | UNIDADES | IMPORTE |
|---|---:|---:|---:|---:|---:|---:|
| 2026-07-01 | 3 | 1 | 2 | 0 | 2 | 60.00 |
| 2026-07-02 | 3 | 3 | 0 | 0 | 5 | 310.00 |
| 2026-07-03 | 1 | 1 | 0 | 0 | 1 | 900.00 |

---

# PARTE I · EVENTO TARDÍO

## 34. Subir `pedidos_03_tardio.csv`

Sube:

```text
s3://<S3_BUCKET_NAME>/entrada/pedidos_03_tardio.csv
```

El archivo contiene una versión de `9104` con:

```text
fecha_modificacion = 2026-07-02 09:30:00
```

La versión vigente tiene:

```text
fecha_modificacion = 2026-07-02 10:30:00
```

---

## 35. Comprobar el evento tardío

RAW debe contener doce eventos:

```sql
SELECT COUNT(*) AS eventos
FROM DB_CURSO.STAGING.PEDIDOS_RAW;
```

Resultado:

```text
12
```

Consulta `9104`:

```sql
SELECT
    id_pedido,
    estado,
    fecha_modificacion,
    event_id,
    _source_file

FROM DB_CURSO.CURATED.PEDIDOS_ACTUALES

WHERE id_pedido = 9104;
```

Debe conservar:

```text
ESTADO = COMPLETADA
FECHA_MODIFICACION = 2026-07-02 10:30:00
EVENT_ID = 7
```

La task RAW → CURATED habrá consumido el stream, pero el `WHEN MATCHED AND` del `MERGE` no habrá actualizado la fila.

Comprueba:

```sql
SELECT SYSTEM$STREAM_HAS_DATA(
    'DB_CURSO.STAGING.STR_PEDIDOS_RAW'
);
```

Resultado:

```text
FALSE
```

Como CURATED no cambió, el segundo stream no recibe un nuevo delta útil y la task MART no necesita una nueva ejecución.

MART debe permanecer igual.

---

# PARTE J · HISTORIAL, DUPLICADOS Y RECUPERACIÓN

## 36. Consultar todo el historial de carga

```sql
SELECT
    file_name,
    status,
    row_count,
    row_parsed,
    error_count,
    first_error_message,
    last_load_time,
    pipe_received_time,
    bytes_billed

FROM TABLE(
    DB_CURSO.INFORMATION_SCHEMA.COPY_HISTORY(
        TABLE_NAME => 'DB_CURSO.STAGING.PEDIDOS_RAW',
        START_TIME => DATEADD(
            'day',
            -1,
            CURRENT_TIMESTAMP()
        )
    )
)

ORDER BY last_load_time;
```

Debes identificar:

```text
pedidos_01.csv
pedidos_02.csv
pedidos_03_tardio.csv
```

---

## 37. Evitar nombres reutilizados

Snowpipe conserva metadatos de carga para evitar procesar accidentalmente el mismo archivo varias veces.

Durante el periodo de historial del pipe, sobrescribir un objeto con el mismo nombre no es una forma fiable de reenviar datos.

Patrón recomendado:

```text
pedidos_20260722_150000_001.csv
pedidos_20260722_150500_002.csv
pedidos_20260722_151000_003.csv
```

Los productores deben tratar los archivos como objetos inmutables:

```text
un archivo → un nombre único → una única carga lógica
```

---

## 38. Recuperar archivos no notificados

Si un archivo se subió antes de crear la notificación S3 o se perdió temporalmente una notificación, utiliza:

```sql
ALTER PIPE
    DB_CURSO.STAGING.PIPE_PEDIDOS_AUTO
REFRESH;
```

También se puede limitar por prefijo:

```sql
ALTER PIPE
    DB_CURSO.STAGING.PIPE_PEDIDOS_AUTO
REFRESH PREFIX = '';
```

La definición del stage ya apunta a `entrada/`, por eso un prefijo vacío representa toda esa ubicación.

### Consideraciones

- `REFRESH` encola archivos recientes que no figuran como cargados.
- Solo considera archivos staged dentro de los últimos siete días.
- Consulta el historial del pipe y de la tabla.
- No debe utilizarse como mecanismo normal de ingestión.
- El mecanismo normal son las notificaciones S3.

---

## 39. Inspeccionar el pipe

```sql
SHOW PIPES LIKE 'PIPE_PEDIDOS_AUTO'
IN SCHEMA DB_CURSO.STAGING;
```

```sql
SELECT SYSTEM$PIPE_STATUS(
    'DB_CURSO.STAGING.PIPE_PEDIDOS_AUTO'
);
```

La ejecución normal debe aparecer activa.

---

# PARTE K · RESOLUCIÓN DE ERRORES

## 40. Snowflake no puede asumir el rol

Síntomas:

```text
Failed to assume AWS_ROLE
```

Comprueba:

1. ARN del rol en la integración.
2. `STORAGE_AWS_IAM_USER_ARN`.
3. `STORAGE_AWS_EXTERNAL_ID`.
4. Trust policy del rol.
5. Que no se recreó la integración.
6. Que no copiaste valores de otro alumno.

Ejecuta:

```sql
DESC INTEGRATION S3_SNOWPIPE_INT;
```

---

## 41. Snowflake asume el rol, pero `GetObject` falla

Síntoma:

```text
because no identity-based policy allows the s3:GetObject action
```

La trust policy funciona, pero falta permiso efectivo sobre S3.

Comprueba en:

```text
IAM → Roles → <IAM_ROLE_NAME> → Permissions
```

que el rol tiene:

```json
{
  "Effect": "Allow",
  "Action": [
    "s3:GetObject",
    "s3:GetObjectVersion"
  ],
  "Resource": "arn:aws:s3:::<S3_BUCKET_NAME>/entrada/*"
}
```

---

## 42. `LIST` falla

Comprueba:

```json
{
  "Effect": "Allow",
  "Action": [
    "s3:GetBucketLocation",
    "s3:ListBucket"
  ],
  "Resource": "arn:aws:s3:::<S3_BUCKET_NAME>"
}
```

Y:

```json
"Condition": {
  "StringLike": {
    "s3:prefix": [
      "entrada",
      "entrada/*"
    ]
  }
}
```

---

## 43. `Location is not allowed by integration`

Compara exactamente:

```sql
STORAGE_ALLOWED_LOCATIONS = (
    's3://<S3_BUCKET_NAME>/entrada/'
);
```

con:

```sql
URL = 's3://<S3_BUCKET_NAME>/entrada/'
```

Revisa la barra final.

---

## 44. AWS no permite guardar la notificación S3

Comprueba:

1. El ARN SQS se copió completo.
2. El ARN procede de tu pipe.
3. Bucket y cola están en una configuración compatible.
4. Seleccionaste `Specify SQS queue ARN`.
5. No hay notificaciones con filtros solapados.
6. El prefijo es exactamente `entrada/`.
7. El sufijo es `.csv`.

Si ya existe una notificación que se solapa con el mismo prefijo y sufijo, puede ser necesario modificarla o utilizar una arquitectura con SNS.

---

## 45. El archivo aparece en S3, pero no se carga

Comprueba:

```sql
SELECT SYSTEM$PIPE_STATUS(
    'DB_CURSO.STAGING.PIPE_PEDIDOS_AUTO'
);
```

Después:

```sql
SHOW PIPES LIKE 'PIPE_PEDIDOS_AUTO'
IN SCHEMA DB_CURSO.STAGING;
```

Revisa:

- Notificación S3 activa.
- ARN SQS correcto.
- Prefijo.
- Sufijo.
- Extensión `.csv`.
- Pipe no pausado.
- Archivo nuevo.
- Nombre no utilizado previamente.
- Errores en `COPY_HISTORY`.

Si el archivo se subió antes de crear la notificación:

```sql
ALTER PIPE
    DB_CURSO.STAGING.PIPE_PEDIDOS_AUTO
REFRESH;
```

---

## 46. Snowpipe carga cero filas o carga parcialmente

Consulta:

```sql
SELECT *
FROM TABLE(
    DB_CURSO.INFORMATION_SCHEMA.COPY_HISTORY(
        TABLE_NAME => 'DB_CURSO.STAGING.PEDIDOS_RAW',
        START_TIME => DATEADD(
            'hour',
            -1,
            CURRENT_TIMESTAMP()
        )
    )
)
ORDER BY last_load_time DESC;
```

Revisa:

```text
STATUS
ROW_PARSED
ROW_COUNT
ERROR_COUNT
FIRST_ERROR_MESSAGE
FIRST_ERROR_LINE_NUMBER
FIRST_ERROR_COLUMN_NAME
```

Comprueba también:

- Diez columnas en el CSV.
- Una única cabecera.
- Delimitador coma.
- Codificación UTF-8.
- Fechas sin comas.
- Nombres de producto sin comas no entrecomilladas.

---

## 47. RAW tiene datos, pero CURATED no cambia

Comprueba:

```sql
SHOW TASKS LIKE 'TASK_RAW_A_CURATED'
IN SCHEMA DB_CURSO.STAGING;
```

```sql
SELECT SYSTEM$STREAM_HAS_DATA(
    'DB_CURSO.STAGING.STR_PEDIDOS_RAW'
);
```

Consulta errores:

```sql
SELECT
    state,
    query_id,
    error_code,
    error_message,
    scheduled_time

FROM TABLE(
    DB_CURSO.INFORMATION_SCHEMA.TASK_HISTORY(
        SCHEDULED_TIME_RANGE_START
            => DATEADD('hour', -1, CURRENT_TIMESTAMP()),

        TASK_NAME => 'TASK_RAW_A_CURATED',

        ERROR_ONLY => TRUE
    )
)

ORDER BY scheduled_time DESC;
```

Un valor no convertible puede hacer fallar el tipado.

Como el `MERGE` no se confirma, el offset del stream no debe avanzar.

---

## 48. CURATED cambia, pero MART no cambia

Comprueba:

```sql
SHOW TASKS LIKE 'TASK_CURATED_A_MART'
IN SCHEMA DB_CURSO.CURATED;
```

```sql
SELECT SYSTEM$STREAM_HAS_DATA(
    'DB_CURSO.CURATED.STR_PEDIDOS_CURATED'
);
```

Consulta `TASK_HISTORY`.

Comprueba que la task lee realmente:

```text
DB_CURSO.CURATED.STR_PEDIDOS_CURATED
```

---

## 49. El stream RAW está vacío aunque se esperaban datos

Posibles causas:

- La task ya los procesó.
- El stream se creó después de cargar el archivo.
- La tabla RAW se recreó después del stream.
- Se consultó otro stream.
- El pipe cargó en otra tabla.
- La task consumió el stream antes de la comprobación.

La rapidez del pipeline puede hacer que el stream ya esté vacío cuando se consulte manualmente.

---

## 50. El evento tardío sobrescribe la versión actual

Comprueba la condición:

```sql
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
```

---

## 51. MART contiene resultados incorrectos

Comprueba:

- Que solo se suman pedidos `COMPLETADA`.
- Que las fechas afectadas se obtienen del stream.
- Que el agregado se calcula desde `PEDIDOS_ACTUALES`.
- Que no se suman directamente los registros de cambio.
- Que el stream CURATED se creó antes de procesar datos.

---

# PARTE L · AUDITORÍA FINAL

## 52. Consulta integral de validación

### Archivos y RAW

```sql
SELECT
    COUNT(*) AS eventos_raw,
    COUNT(DISTINCT _source_file) AS archivos

FROM DB_CURSO.STAGING.PEDIDOS_RAW;
```

Resultado esperado:

```text
12 eventos
3 archivos CSV
```

### CURATED

```sql
SELECT
    COUNT(*) AS pedidos,
    COUNT(DISTINCT id_pedido) AS pedidos_distintos,
    COUNT_IF(estado = 'COMPLETADA') AS completados,
    COUNT_IF(estado = 'CANCELADA') AS cancelados,
    COUNT_IF(estado = 'PENDIENTE') AS pendientes

FROM DB_CURSO.CURATED.PEDIDOS_ACTUALES;
```

Resultado:

```text
7, 7, 5, 2, 0
```

### MART

```sql
SELECT
    SUM(pedidos_total) AS pedidos,
    SUM(unidades_vendidas) AS unidades,
    SUM(importe_ventas) AS importe

FROM DB_CURSO.MARTS.VENTAS_DIARIAS;
```

Resultado:

```text
7 pedidos
8 unidades
1270.00
```

### Duplicados

```sql
SELECT
    id_pedido,
    COUNT(*) AS filas

FROM DB_CURSO.CURATED.PEDIDOS_ACTUALES

GROUP BY id_pedido

HAVING COUNT(*) > 1;
```

No debe devolver filas.

---

## 53. Auditar las ejecuciones de ambas tasks

```sql
SELECT
    name,
    state,
    scheduled_from,
    scheduled_time,
    query_start_time,
    completed_time,
    DATEDIFF(
        'millisecond',
        query_start_time,
        completed_time
    ) AS duracion_ms,
    query_id,
    error_message

FROM TABLE(
    DB_CURSO.INFORMATION_SCHEMA.TASK_HISTORY(
        SCHEDULED_TIME_RANGE_START
            => DATEADD('day', -1, CURRENT_TIMESTAMP()),

        SCHEDULED_TIME_RANGE_END
            => CURRENT_TIMESTAMP(),

        RESULT_LIMIT => 100
    )
)

WHERE name IN (
    'TASK_RAW_A_CURATED',
    'TASK_CURATED_A_MART'
)

AND query_id IS NOT NULL

ORDER BY scheduled_time;
```

Debes identificar:

1. RAW → CURATED para el primer archivo.
2. CURATED → MART para el primer archivo.
3. RAW → CURATED para el segundo archivo.
4. CURATED → MART para el segundo archivo.
5. RAW → CURATED para el evento tardío.
6. Ausencia de una transformación MART adicional si CURATED no cambió.

---

# PARTE M · SUSPENSIÓN Y LIMPIEZA

## 54. Suspender las tasks

```sql
ALTER TASK
    DB_CURSO.STAGING.TASK_RAW_A_CURATED
SUSPEND;
```

```sql
ALTER TASK
    DB_CURSO.CURATED.TASK_CURATED_A_MART
SUSPEND;
```

---

## 55. Pausar el pipe

```sql
ALTER PIPE
    DB_CURSO.STAGING.PIPE_PEDIDOS_AUTO
SET PIPE_EXECUTION_PAUSED = TRUE;
```

Comprueba:

```sql
SELECT SYSTEM$PIPE_STATUS(
    'DB_CURSO.STAGING.PIPE_PEDIDOS_AUTO'
);
```

---

## 56. Eliminar la notificación de S3

Antes de destruir el pipe o el bucket:

```text
S3 → Bucket → Properties → Event notifications
```

Elimina:

```text
snowpipe-pedidos-<alias>
```

No elimines notificaciones de otros buckets.

---

## 57. Limpieza en Snowflake

No ejecutes esta sección si los objetos van a reutilizarse.

```sql
USE ROLE SYSADMIN;

ALTER TASK IF EXISTS
    DB_CURSO.STAGING.TASK_RAW_A_CURATED
SUSPEND;

ALTER TASK IF EXISTS
    DB_CURSO.CURATED.TASK_CURATED_A_MART
SUSPEND;

DROP TASK IF EXISTS
    DB_CURSO.STAGING.TASK_RAW_A_CURATED;

DROP TASK IF EXISTS
    DB_CURSO.CURATED.TASK_CURATED_A_MART;

ALTER PIPE IF EXISTS
    DB_CURSO.STAGING.PIPE_PEDIDOS_AUTO
SET PIPE_EXECUTION_PAUSED = TRUE;

DROP PIPE IF EXISTS
    DB_CURSO.STAGING.PIPE_PEDIDOS_AUTO;

DROP STREAM IF EXISTS
    DB_CURSO.STAGING.STR_PEDIDOS_RAW;

DROP STREAM IF EXISTS
    DB_CURSO.CURATED.STR_PEDIDOS_CURATED;

DROP STAGE IF EXISTS
    DB_CURSO.STAGING.STG_S3_PEDIDOS;

DROP FILE FORMAT IF EXISTS
    DB_CURSO.STAGING.FF_PEDIDOS_CSV;

DROP TABLE IF EXISTS
    DB_CURSO.MARTS.VENTAS_DIARIAS;

DROP TABLE IF EXISTS
    DB_CURSO.CURATED.PEDIDOS_ACTUALES;

DROP TABLE IF EXISTS
    DB_CURSO.STAGING.PEDIDOS_RAW;

ALTER SESSION UNSET QUERY_TAG;
```

Elimina la integración con `ACCOUNTADMIN`:

```sql
USE ROLE ACCOUNTADMIN;

DROP STORAGE INTEGRATION IF EXISTS S3_SNOWPIPE_INT;
```

Opcionalmente:

```sql
DROP DATABASE IF EXISTS DB_CURSO;
DROP WAREHOUSE IF EXISTS WH_DEV;
```

---

## 58. Limpieza en AWS

Cada participante elimina únicamente sus recursos:

1. Archivos del bucket.
2. Bucket vacío.
3. Rol IAM propio.
4. Política IAM propia.

Orden recomendado:

```text
Eliminar objetos S3
→ eliminar bucket
→ eliminar rol IAM
→ eliminar política IAM
```

---

# 59. Conceptos clave

## Snowpipe y warehouse

Snowpipe utiliza cómputo serverless administrado por Snowflake.

No utiliza:

```text
WH_DEV
```

Las triggered tasks sí utilizan `WH_DEV`.

---

## Notificación y datos

La notificación S3 contiene información del evento y del objeto.

No transporta el contenido del CSV.

Snowpipe usa la información recibida para localizar el archivo en el stage y leerlo mediante la storage integration.

---

## Idempotencia

Existen dos controles diferentes:

1. Snowpipe evita normalmente volver a cargar el mismo archivo registrado.
2. El `MERGE` de CURATED evita que una versión antigua sobrescriba una reciente.

Ambos son necesarios porque resuelven problemas diferentes.

---

## Latencia extremo a extremo

El pipeline tiene varias etapas asíncronas:

```text
evento S3
→ cola SQS
→ Snowpipe
→ stream RAW
→ task CURATED
→ stream CURATED
→ task MART
```

Una fila puede aparecer en RAW antes de estar disponible en MART.

La monitorización debe observar todas las etapas.

---

## Metadatos de archivo

El pipe incorpora:

```text
METADATA$FILENAME
METADATA$FILE_ROW_NUMBER
METADATA$FILE_LAST_MODIFIED
METADATA$START_SCAN_TIME
```

Estos campos facilitan:

- Trazabilidad.
- Diagnóstico de errores.
- Auditoría.
- Reprocesamiento.
- Identificación de archivos problemáticos.

---

## Versiones de negocio

La versión ganadora se determina por:

```text
1. fecha_modificacion
2. event_id
```

El orden de llegada del archivo no determina por sí solo qué dato es correcto.

---

# 60. Respuestas orientativas a las preguntas de reflexión

### 1. Diferencia entre stage y Snowpipe

El stage describe una ubicación y un mecanismo de acceso. Snowpipe automatiza una sentencia `COPY INTO` sobre archivos notificados.

### 2. Función de la notificación

Informar a Snowpipe de que se ha creado un objeto que puede ser candidato a carga.

### 3. Contenido de la notificación

Incluye metadatos del evento y del objeto, no las filas del CSV.

### 4. Propietario de la cola

Snowflake crea y administra la cola SQS utilizada por el pipe en esta configuración.

### 5. Snowpipe y warehouse

Snowpipe utiliza cómputo serverless. Las tasks del ejercicio utilizan un warehouse administrado por el usuario.

### 6. Motivo de la capa RAW

Permite conservar el dato recibido, separar ingestión de transformación y facilitar auditoría y recuperación.

### 7. Momento de creación del stream

Debe existir antes de los cambios que se quieran capturar.

### 8. Archivo anterior a la notificación

No genera un evento útil para el pipe. Puede recuperarse con `ALTER PIPE ... REFRESH` si es reciente.

### 9. Confianza frente a permisos

La confianza permite asumir el rol. Los permisos determinan las acciones que el rol puede realizar sobre S3.

### 10. Deduplicación

Un microbatch puede contener varias versiones de una misma clave. El `MERGE` necesita una sola fila fuente por pedido.

### 11. Comparación de versiones

`fecha_modificacion` expresa la versión de negocio. `event_id` resuelve empates.

### 12. Recalcular fechas

Los cambios de estado pueden sumar y restar métricas. Recalcular desde el estado actual evita errores acumulativos.

### 13. UPDATE en stream estándar

Se representa mediante una pareja de registros `DELETE` e `INSERT` asociada a la actualización.

### 14. Evento tardío y MART

Si CURATED no cambia, su stream no produce un cambio que requiera recalcular MART.

### 15. Nombres únicos

Evitan ambigüedad en el historial de carga y hacen que los archivos sean inmutables.

### 16. `COPY_HISTORY`

Muestra archivos, estados, filas, errores, tiempos y datos de facturación asociados a las cargas.

### 17. `SYSTEM$PIPE_STATUS`

Muestra el estado operativo del pipe y de su canal de notificación.

### 18. Producción

Se añadirían alertas, tablas de rechazo, validaciones, observabilidad, control de esquemas, retención, cifrado, segregación de roles y reconciliación de conteos.

### 19. SNS o EventBridge

Son útiles cuando existen filtros solapados, varios consumidores, fan-out, integración con más servicios o una arquitectura de eventos centralizada.

### 20. Costes

Snowpipe factura el cómputo serverless de ingestión. Las tasks consumen el warehouse cuando se ejecutan.

---

# 61. Referencias oficiales

- Snowflake: introducción a Snowpipe  
  <https://docs.snowflake.com/en/user-guide/data-load-snowpipe-intro>

- Snowflake: automatización de Snowpipe para Amazon S3  
  <https://docs.snowflake.com/en/user-guide/data-load-snowpipe-auto-s3>

- Snowflake: `CREATE PIPE`  
  <https://docs.snowflake.com/en/sql-reference/sql/create-pipe>

- Snowflake: `SYSTEM$PIPE_STATUS`  
  <https://docs.snowflake.com/en/sql-reference/functions/system_pipe_status>

- Snowflake: `COPY_HISTORY`  
  <https://docs.snowflake.com/en/sql-reference/functions/copy_history>

- Snowflake: metadatos de archivos staged  
  <https://docs.snowflake.com/en/user-guide/querying-metadata>

- Snowflake: transformación durante la carga  
  <https://docs.snowflake.com/en/user-guide/data-load-transform>

- Snowflake: triggered tasks  
  <https://docs.snowflake.com/en/user-guide/tasks-triggered>

- Snowflake: introducción a streams  
  <https://docs.snowflake.com/en/user-guide/streams-intro>

- Snowflake: `ALTER PIPE` y `REFRESH`  
  <https://docs.snowflake.com/en/sql-reference/sql/alter-pipe>

- AWS: notificaciones de eventos de Amazon S3  
  <https://docs.aws.amazon.com/AmazonS3/latest/userguide/EventNotifications.html>

- AWS: filtrado de notificaciones por claves de objeto  
  <https://docs.aws.amazon.com/AmazonS3/latest/userguide/notification-how-to-filtering.html>

- AWS: acceso de terceros mediante roles y External ID  
  <https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_common-scenarios_third-party.html>

---

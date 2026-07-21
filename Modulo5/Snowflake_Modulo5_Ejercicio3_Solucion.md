# Módulo 5 · Ejercicio 3

## Solución guiada: exportación a CSV y Parquet, particionado y validación de ida y vuelta

---

## 1. Arquitectura del ejercicio

Construiremos dos entregas:

```text
DB_CURSO.CURATED.VENTAS_EXPORT
        │
        ├── CSV agregado y comprimido
        │      @STG_EXPORT_VENTAS/csv/resumen/
        │
        └── Parquet detallado y particionado por mes
               @STG_EXPORT_VENTAS/parquet/ventas/
                               │
                               └── COPY INTO <table>
                                   VENTAS_REIMPORTADAS
```

La reimportación demuestra que el fichero no solo existe, sino que puede utilizarse para reconstruir los datos.

---

## 2. Preparar Workspaces

En Snowsight:

1. Abre **Workspaces**.
2. Crea un fichero SQL llamado:

```text
M5_E03_UNLOAD_PARQUET.sql
```

3. Ejecuta:

```sql
USE ROLE SYSADMIN;

CREATE WAREHOUSE IF NOT EXISTS WH_DEV
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE;

USE WAREHOUSE WH_DEV;

CREATE DATABASE IF NOT EXISTS DB_CURSO;
CREATE SCHEMA IF NOT EXISTS DB_CURSO.CURATED;
CREATE SCHEMA IF NOT EXISTS DB_CURSO.STAGING;

USE DATABASE DB_CURSO;
USE SCHEMA CURATED;

ALTER SESSION SET QUERY_TAG = 'M05_E03_UNLOAD_PARQUET';
```

Comprueba:

```sql
SELECT
    CURRENT_ROLE()      AS rol,
    CURRENT_WAREHOUSE() AS warehouse,
    CURRENT_DATABASE()  AS base_datos,
    CURRENT_SCHEMA()    AS esquema,
    CURRENT_SESSION()   AS sesion;
```

---

## 3. Crear la tabla de origen

Ejecuta:

```sql
CREATE OR REPLACE TRANSIENT TABLE DB_CURSO.CURATED.VENTAS_EXPORT AS
WITH base AS (
    SELECT SEQ4() AS n
    FROM TABLE(GENERATOR(ROWCOUNT => 20000))
)
SELECT
    (100000 + n)::NUMBER(18,0) AS id_venta,

    DATEADD(
        'day',
        MOD(n, 59),
        '2026-01-01'::DATE
    )::DATE AS fecha,

    CASE MOD(n, 4)
        WHEN 0 THEN 'NORTE'
        WHEN 1 THEN 'SUR'
        WHEN 2 THEN 'ESTE'
        ELSE 'OESTE'
    END::VARCHAR(10) AS region,

    CASE MOD(n, 3)
        WHEN 0 THEN 'WEB'
        WHEN 1 THEN 'TIENDA'
        ELSE 'MARKETPLACE'
    END::VARCHAR(20) AS canal,

    (
        10 + MOD(n * 37, 50000) / 100
    )::NUMBER(12,2) AS importe,

    'EUR'::VARCHAR(3) AS moneda,

    (MOD(n, 5) = 0)::BOOLEAN AS es_promocion
FROM base;
```

### Explicación

`GENERATOR` produce 20.000 filas sin necesitar un fichero externo.

El CTE asigna un número `n` a cada fila. Después se utilizan operaciones deterministas para generar:

- 59 fechas desde el 1 de enero al 28 de febrero.
- Cuatro regiones.
- Tres canales.
- Importes decimales.
- Una marca de promoción para una de cada cinco ventas.

Comprueba el esquema:

```sql
DESC TABLE DB_CURSO.CURATED.VENTAS_EXPORT;
```

Comprueba las métricas:

```sql
SELECT
    COUNT(*)     AS filas,
    MIN(fecha)   AS fecha_minima,
    MAX(fecha)   AS fecha_maxima,
    SUM(importe) AS importe_total
FROM DB_CURSO.CURATED.VENTAS_EXPORT;
```

Debes obtener:

- `FILAS = 20000`
- `FECHA_MINIMA = 2026-01-01`
- `FECHA_MAXIMA = 2026-02-28`

Guarda el importe total que devuelva tu cuenta.

Distribución mensual:

```sql
SELECT
    TO_CHAR(DATE_TRUNC('month', fecha), 'YYYY-MM') AS mes,
    COUNT(*) AS filas,
    SUM(importe) AS importe_total
FROM DB_CURSO.CURATED.VENTAS_EXPORT
GROUP BY mes
ORDER BY mes;
```

---

## 4. Crear el file format Parquet

```sql
CREATE OR REPLACE FILE FORMAT DB_CURSO.STAGING.FF_EXPORT_PARQUET
    TYPE = PARQUET
    COMPRESSION = SNAPPY
    USE_LOGICAL_TYPE = TRUE;
```

### Explicación

- Parquet conserva estructura columnar y tipos.
- Snappy ofrece compresión rápida y es habitual en pipelines analíticos.
- `USE_LOGICAL_TYPE = TRUE` permite interpretar tipos lógicos de Parquet cuando se vuelva a leer.

Comprueba:

```sql
DESC FILE FORMAT DB_CURSO.STAGING.FF_EXPORT_PARQUET;
```

---

## 5. Crear el named internal stage

```sql
CREATE OR REPLACE STAGE DB_CURSO.STAGING.STG_EXPORT_VENTAS
    ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE')
    DIRECTORY = (ENABLE = FALSE);
```

No asociamos un file format predeterminado porque el stage contendrá:

- CSV.
- Parquet.

Comprueba:

```sql
DESC STAGE DB_CURSO.STAGING.STG_EXPORT_VENTAS;
LIST @DB_CURSO.STAGING.STG_EXPORT_VENTAS;
```

---

## 6. Validar la consulta de descarga sin crear ficheros

Ejecuta:

```sql
COPY INTO @DB_CURSO.STAGING.STG_EXPORT_VENTAS/validacion/
FROM (
    SELECT
        id_venta,
        fecha,
        region,
        canal,
        importe,
        moneda,
        es_promocion
    FROM DB_CURSO.CURATED.VENTAS_EXPORT
    ORDER BY id_venta
    LIMIT 10
)
FILE_FORMAT = (
    TYPE = PARQUET
    COMPRESSION = SNAPPY
)
VALIDATION_MODE = RETURN_ROWS;
```

### Qué ocurre

`RETURN_ROWS` devuelve el resultado de la consulta en lugar de escribir ficheros.

Comprueba que la ruta continúa vacía:

```sql
LIST @DB_CURSO.STAGING.STG_EXPORT_VENTAS/validacion/;
```

No debe devolver ficheros.

### Diferencia respecto a la validación de una carga

En:

```text
COPY INTO <table>
```

`VALIDATION_MODE` intenta detectar errores de lectura y conversión antes de insertar.

En:

```text
COPY INTO <location>
```

la opción admitida es `RETURN_ROWS`, que permite comprobar las filas producidas por la consulta antes de descargarlas.

---

## 7. Generar el CSV de resumen

Primero limpia la ruta por si repites el ejercicio:

```sql
REMOVE @DB_CURSO.STAGING.STG_EXPORT_VENTAS/csv/resumen/;
```

Ejecuta:

```sql
COPY INTO @DB_CURSO.STAGING.STG_EXPORT_VENTAS/csv/resumen/ventas_resumen.csv.gz
FROM (
    SELECT
        TO_CHAR(
            DATE_TRUNC('month', fecha),
            'YYYY-MM'
        ) AS mes,
        region,
        COUNT(*) AS numero_ventas,
        SUM(importe)::NUMBER(18,2) AS importe_total
    FROM DB_CURSO.CURATED.VENTAS_EXPORT
    GROUP BY mes, region
    ORDER BY mes, region
)
FILE_FORMAT = (
    TYPE = CSV
    COMPRESSION = GZIP
    FIELD_DELIMITER = ';'
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    NULL_IF = ()
)
HEADER = TRUE
SINGLE = TRUE
OVERWRITE = TRUE
DETAILED_OUTPUT = TRUE;
```

### Por qué utilizamos SINGLE

El destinatario es una persona que espera una única entrega agregada. La tabla solo genera ocho filas:

```text
2 meses × 4 regiones
```

Para volúmenes grandes, `SINGLE = TRUE` reduce el paralelismo y no suele ser la mejor opción.

Comprueba:

```sql
LIST @DB_CURSO.STAGING.STG_EXPORT_VENTAS/csv/resumen/;
```

Debe aparecer un solo fichero comprimido.

### Consultar el CSV staged

> En un SELECT contra un stage Snowflake no acepta un FILE_FORMAT definido inline con opciones como TYPE, COMPRESSION o FIELD_DELIMITER; en esa sintaxis solo admite un formato con nombre, o bien que el stage ya tenga el formato asociado.

Primero crea un file format con nombre:

```sql
CREATE OR REPLACE FILE FORMAT DB_CURSO.STAGING.FF_RESUMEN_CSV
  TYPE = 'CSV'
  COMPRESSION = 'GZIP'
  FIELD_DELIMITER = ';'
  SKIP_HEADER = 1
  FIELD_OPTIONALLY_ENCLOSED_BY = '"';
```
Después usa ese formato en la consulta al stage:

```sql
SELECT
  METADATA$FILENAME AS fichero,
  t.$1 AS mes,
  t.$2 AS region,
  t.$3 AS numero_ventas,
  t.$4 AS importe_total
FROM @DB_CURSO.STAGING.STG_EXPORT_VENTAS/csv/resumen/
  ( FILE_FORMAT => 'DB_CURSO.STAGING.FF_RESUMEN_CSV' ) t
ORDER BY mes, region;
```

---

## 8. Preparar la ruta Parquet

Las descargas particionadas no admiten `OVERWRITE = TRUE`. Si repetimos la sentencia sin limpiar la ruta, se añadirán nuevos ficheros con otro Query ID.

Por eso ejecutamos:

```sql
REMOVE @DB_CURSO.STAGING.STG_EXPORT_VENTAS/parquet/ventas/;
```

Comprueba:

```sql
LIST @DB_CURSO.STAGING.STG_EXPORT_VENTAS/parquet/ventas/;
```

La ruta debe estar vacía.

---

## 9. Exportar a Parquet por mes

Ejecuta:

```sql
COPY INTO @DB_CURSO.STAGING.STG_EXPORT_VENTAS/parquet/ventas/
FROM DB_CURSO.CURATED.VENTAS_EXPORT
PARTITION BY TO_CHAR(fecha, 'YYYY-MM')
FILE_FORMAT = (
    FORMAT_NAME = 'DB_CURSO.STAGING.FF_EXPORT_PARQUET'
)
HEADER = TRUE
MAX_FILE_SIZE = 16777216
INCLUDE_QUERY_ID = TRUE
DETAILED_OUTPUT = TRUE;
```

### Explicación de las opciones

#### PARTITION BY

```sql
PARTITION BY TO_CHAR(fecha, 'YYYY-MM')
```

Genera rutas que incluyen valores como:

```text
2026-01
2026-02
```

Las filas se separan según el mes.

#### HEADER = TRUE

En Parquet, esta opción conserva los nombres de las columnas en el fichero. Si se omite, Snowflake puede utilizar nombres genéricos como `col1`, `col2`, etc.

Esto permitirá volver a cargar mediante:

```sql
MATCH_BY_COLUMN_NAME
```

#### MAX_FILE_SIZE

```text
16 MB
```

Snowflake intenta aproximarse a ese tamaño. Con solo 20.000 filas es probable que genere pocos ficheros.

#### INCLUDE_QUERY_ID

Incluye un identificador único en los nombres. Reduce el riesgo de colisión cuando varias descargas escriben en una ruta.

#### DETAILED_OUTPUT

Devuelve una fila de resultado por fichero generado, con información de filas y tamaño.

---

## 10. Inspeccionar los ficheros

```sql
LIST @DB_CURSO.STAGING.STG_EXPORT_VENTAS/parquet/ventas/;
```

Debes ver rutas semejantes a:

```text
.../parquet/ventas/2026-01/data_<query-id>...
.../parquet/ventas/2026-02/data_<query-id>...
```

El número exacto de ficheros y su tamaño pueden variar. Snowflake decide el reparto según:

- Volumen.
- Paralelismo.
- Compresión.
- `MAX_FILE_SIZE`.

### Precaución de privacidad

Los valores de `PARTITION BY` forman parte de los nombres y rutas de los ficheros.

Snowflake también conserva URLs de ficheros en registros internos de soporte. Por eso no deben utilizarse:

- Correos.
- Nombres.
- Números de documento.
- Identificadores de cliente.
- Cualquier dato personal o secreto.

Fechas, meses y valores booleanos suelen ser opciones apropiadas.

---

## 11. Consultar el Parquet staged

Ejecuta:

```sql
SELECT
    t.$1:ID_VENTA::NUMBER(18,0) AS id_venta,
    t.$1:FECHA::DATE AS fecha,
    t.$1:REGION::VARCHAR AS region,
    t.$1:CANAL::VARCHAR AS canal,
    t.$1:IMPORTE::NUMBER(12,2) AS importe,
    t.$1:MONEDA::VARCHAR AS moneda,
    t.$1:ES_PROMOCION::BOOLEAN AS es_promocion,
    METADATA$FILENAME AS fichero
FROM @DB_CURSO.STAGING.STG_EXPORT_VENTAS/parquet/ventas/
    ( FILE_FORMAT => 'DB_CURSO.STAGING.FF_EXPORT_PARQUET' ) t
ORDER BY id_venta
LIMIT 20;
```

### Interpretación

Al consultar Parquet, `$1` representa un objeto con los campos de la fila.

La notación:

```sql
$1:ID_VENTA
```

accede al campo. Los casts explícitos restauran el tipo esperado.

Los nombres se conservan porque la descarga utilizó:

```sql
HEADER = TRUE
```

---

## 12. Crear la tabla de reimportación

```sql
CREATE OR REPLACE TRANSIENT TABLE DB_CURSO.STAGING.VENTAS_REIMPORTADAS
LIKE DB_CURSO.CURATED.VENTAS_EXPORT;
```

Comprueba:

```sql
DESC TABLE DB_CURSO.STAGING.VENTAS_REIMPORTADAS;
```

La tabla tiene las mismas columnas y tipos que el origen.

---

## 13. Volver a cargar el Parquet

Ejecuta:

```sql
COPY INTO DB_CURSO.STAGING.VENTAS_REIMPORTADAS
FROM @DB_CURSO.STAGING.STG_EXPORT_VENTAS/parquet/ventas/
FILE_FORMAT = (
    FORMAT_NAME = 'DB_CURSO.STAGING.FF_EXPORT_PARQUET'
)
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
ON_ERROR = ABORT_STATEMENT;
```

### Por qué no necesitamos SELECT

Los ficheros contienen nombres de columna.

```sql
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
```

hace coincidir esos nombres con las columnas de la tabla, aunque varíe la capitalización.

Esta modalidad evita depender de la posición física de las columnas.

---

## 14. Reconciliar las tablas

### 14.1 Conteo, fechas e importe

```sql
SELECT
    'ORIGEN' AS conjunto,
    COUNT(*) AS filas,
    MIN(fecha) AS fecha_minima,
    MAX(fecha) AS fecha_maxima,
    SUM(importe) AS importe_total
FROM DB_CURSO.CURATED.VENTAS_EXPORT

UNION ALL

SELECT
    'REIMPORTADO',
    COUNT(*),
    MIN(fecha),
    MAX(fecha),
    SUM(importe)
FROM DB_CURSO.STAGING.VENTAS_REIMPORTADAS;
```

Las métricas deben ser idénticas.

### 14.2 Distribución por mes

```sql
SELECT
    'ORIGEN' AS conjunto,
    TO_CHAR(DATE_TRUNC('month', fecha), 'YYYY-MM') AS mes,
    COUNT(*) AS filas,
    SUM(importe) AS importe_total
FROM DB_CURSO.CURATED.VENTAS_EXPORT
GROUP BY mes

UNION ALL

SELECT
    'REIMPORTADO',
    TO_CHAR(DATE_TRUNC('month', fecha), 'YYYY-MM'),
    COUNT(*),
    SUM(importe)
FROM DB_CURSO.STAGING.VENTAS_REIMPORTADAS
GROUP BY 2
ORDER BY mes, conjunto;
```

### 14.3 Filas que faltan en el destino

```sql
SELECT *
FROM DB_CURSO.CURATED.VENTAS_EXPORT

MINUS

SELECT *
FROM DB_CURSO.STAGING.VENTAS_REIMPORTADAS;
```

No debe devolver filas.

### 14.4 Filas adicionales en el destino

```sql
SELECT *
FROM DB_CURSO.STAGING.VENTAS_REIMPORTADAS

MINUS

SELECT *
FROM DB_CURSO.CURATED.VENTAS_EXPORT;
```

Tampoco debe devolver filas.

### Por qué comprobamos ambos sentidos

La primera consulta detecta datos perdidos.

La segunda detecta:

- Filas duplicadas.
- Filas ajenas al origen.
- Valores diferentes que solo existan en el destino.

---

## 15. Consultar el historial de consultas del ejercicio

```sql
SELECT
    query_id,
    query_text,
    start_time,
    total_elapsed_time,
    bytes_scanned,
    rows_produced,
    execution_status
FROM TABLE(
    INFORMATION_SCHEMA.QUERY_HISTORY_BY_SESSION(
        RESULT_LIMIT => 100
    )
)
WHERE query_tag = 'M05_E03_UNLOAD_PARQUET'
ORDER BY start_time;
```

Busca:

- La descarga CSV.
- La descarga Parquet.
- La carga de ida y vuelta.
- Las consultas de reconciliación.

---

## 16. Descargar el CSV con GET

La descarga a un stage y la descarga al ordenador son dos pasos diferentes:

```text
COPY INTO <location>
        ↓
Stage de Snowflake
        ↓
GET
        ↓
Sistema de archivos local
```

`GET` es un comando de cliente. Workspaces se ejecuta en el servicio web y no puede escribir directamente en una carpeta arbitraria de tu ordenador.

Debe ejecutarse desde Snowflake CLI, SnowSQL o un cliente compatible.

### Linux o macOS

```sql
GET
    @DB_CURSO.STAGING.STG_EXPORT_VENTAS/csv/resumen/ventas_resumen.csv.gz
    file:///home/alumno/snowflake_export/;
```

### Windows

```sql
GET
    @DB_CURSO.STAGING.STG_EXPORT_VENTAS/csv/resumen/ventas_resumen.csv.gz
    file://C:\snowflake_export\;
```

El nombre exacto debe confirmarse antes mediante:

```sql
LIST @DB_CURSO.STAGING.STG_EXPORT_VENTAS/csv/resumen/;
```

---

## 17. Diseño de producción con almacenamiento externo

El laboratorio utiliza un stage interno porque cada alumno solo necesita su cuenta Snowflake.

En producción, el patrón recomendado es:

### Paso 1. Crear una identidad en el proveedor

- AWS: IAM role.
- Azure: service principal o identidad administrada según el diseño.
- GCP: service account.

Debe tener únicamente los permisos necesarios sobre el bucket o contenedor.

### Paso 2. Crear la storage integration

Ejemplo conceptual para AWS:

```sql
USE ROLE ACCOUNTADMIN;

CREATE STORAGE INTEGRATION SI_EXPORT_S3
    TYPE = EXTERNAL_STAGE
    STORAGE_PROVIDER = 'S3'
    ENABLED = TRUE
    STORAGE_AWS_ROLE_ARN = 'arn:aws:iam::<cuenta>:role/<rol>'
    STORAGE_ALLOWED_LOCATIONS = (
        's3://bucket-retailnova/exports/'
    );
```

### Paso 3. Obtener la identidad Snowflake

```sql
DESC INTEGRATION SI_EXPORT_S3;
```

Snowflake devuelve datos como:

- Usuario o principal cloud.
- External ID.
- Propiedades que deben incorporarse a la relación de confianza.

### Paso 4. Configurar la confianza

En el proveedor se modifica la política del rol o identidad para permitir que la identidad de Snowflake lo utilice.

### Paso 5. Crear el external stage

```sql
CREATE STAGE DB_CURSO.STAGING.STG_EXPORT_EXTERNO
    URL = 's3://bucket-retailnova/exports/'
    STORAGE_INTEGRATION = SI_EXPORT_S3
    FILE_FORMAT = DB_CURSO.STAGING.FF_EXPORT_PARQUET;
```

### Paso 6. Descargar

La sentencia apenas cambia:

```sql
COPY INTO @DB_CURSO.STAGING.STG_EXPORT_EXTERNO/ventas/
FROM DB_CURSO.CURATED.VENTAS_EXPORT
FILE_FORMAT = (
    FORMAT_NAME = 'DB_CURSO.STAGING.FF_EXPORT_PARQUET'
);
```

### Principio de seguridad

No debes incluir en scripts:

```text
AWS_KEY_ID
AWS_SECRET_KEY
SAS tokens permanentes
Claves de cuentas de servicio
```

Las storage integrations separan la autenticación de la lógica SQL y permiten restringir las ubicaciones autorizadas.

---

## 18. Limpieza opcional

No limpies el ejercicio si quieres inspeccionar posteriormente los ficheros.

```sql
REMOVE @DB_CURSO.STAGING.STG_EXPORT_VENTAS/csv/;
REMOVE @DB_CURSO.STAGING.STG_EXPORT_VENTAS/parquet/;
REMOVE @DB_CURSO.STAGING.STG_EXPORT_VENTAS/validacion/;

DROP TABLE IF EXISTS DB_CURSO.STAGING.VENTAS_REIMPORTADAS;
DROP TABLE IF EXISTS DB_CURSO.CURATED.VENTAS_EXPORT;

DROP STAGE IF EXISTS DB_CURSO.STAGING.STG_EXPORT_VENTAS;
DROP FILE FORMAT IF EXISTS DB_CURSO.STAGING.FF_EXPORT_PARQUET;

ALTER SESSION UNSET QUERY_TAG;
```

No elimines `DB_CURSO`, sus esquemas ni `WH_DEV`.

---

## 19. Errores frecuentes

### La descarga particionada crea ficheros adicionales al repetirla

Es el comportamiento esperado. Cada ejecución puede generar nombres nuevos con otro Query ID.

Solución para el laboratorio:

```sql
REMOVE @DB_CURSO.STAGING.STG_EXPORT_VENTAS/parquet/ventas/;
```

antes de regenerar la entrega.

---

### Error al combinar PARTITION BY con SINGLE

Estas opciones no son compatibles.

- `PARTITION BY` busca varias rutas o grupos.
- `SINGLE` exige un único fichero.

Para una entrega particionada, no uses `SINGLE`.

---

### La reimportación no encuentra columnas

Comprueba que la descarga Parquet utilizó:

```sql
HEADER = TRUE
```

y la carga:

```sql
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
```

También verifica la estructura real consultando algunas filas staged.

---

### LIST no muestra ficheros

Comprueba:

- Warehouse activo.
- Ruta correcta.
- Privilegios `READ` sobre el stage.
- Que ejecutaste la sentencia sin `VALIDATION_MODE`.
- Que la descarga no terminó con error.

---

### GET falla en Workspaces

Es normal. Ejecútalo desde Snowflake CLI o SnowSQL, porque necesita acceso al sistema de archivos local.

---

### La consulta directa del Parquet no reconoce el file format

Utiliza el nombre completamente cualificado:

```text
DB_CURSO.STAGING.FF_EXPORT_PARQUET
```

y comprueba:

```sql
DESC FILE FORMAT DB_CURSO.STAGING.FF_EXPORT_PARQUET;
```

---

## 20. Respuestas a las preguntas de reflexión

### 1. ¿Por qué Parquet para analítica?

Porque es columnar, conserva tipos y ofrece buena compresión. Un motor puede leer solo las columnas necesarias.

### 2. ¿Qué aporta HEADER = TRUE?

Conserva los nombres de las columnas en Parquet y facilita la carga por nombre en lugar de por posición.

### 3. ¿Por qué PARTITION BY no admite SINGLE?

El particionado separa datos en grupos y rutas. Un único fichero eliminaría esa separación física.

### 4. ¿Qué ocurre al repetir la descarga?

Se añaden nuevos ficheros, generalmente con otro Query ID. Sin una política de limpieza o versiones, un consumidor podría leer datos duplicados.

### 5. ¿Diferencia entre los dos COPY?

```text
COPY INTO <table>
```

carga ficheros en una tabla.

```text
COPY INTO <location>
```

descarga una tabla o consulta a ficheros.

### 6. ¿Por qué GET no se ejecuta en el editor web?

Porque escribe en un sistema de archivos local. Debe ejecutarse desde un cliente que tenga acceso a ese sistema.

### 7. ¿Por qué una storage integration?

Evita credenciales permanentes en SQL y centraliza la delegación, las ubicaciones autorizadas y la rotación de identidades.

---

## 21. Compatibilidad con la cuenta trial y la versión actual

El ejercicio es compatible con una cuenta trial Enterprise porque utiliza:

- Workspaces.
- Warehouse `XSMALL`.
- Tablas transitorias.
- Named file formats.
- Named internal stages.
- `COPY INTO <location>`.
- CSV, GZIP y Parquet.
- `PARTITION BY`.
- `VALIDATION_MODE = RETURN_ROWS`.
- `MATCH_BY_COLUMN_NAME`.
- `COPY INTO <table>` para la reimportación.

No requiere:

- Bucket externo.
- Storage integration real.
- Cuenta AWS, Azure o GCP.
- Business Critical.
- Servicio externo.

El comando `GET` es opcional y solo necesita un cliente local si se desea descargar físicamente el CSV.

---

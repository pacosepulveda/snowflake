# Módulo 5 · Ejercicio 1

## Solución guiada: carga batch de un fichero CSV desde un stage interno

---

## 1. Resultado que vamos a construir

El flujo será:

```text
Fichero CSV local
        ↓
Named internal stage
DB_CURSO.STAGING.STG_VENTAS_CSV
        ↓
COPY INTO con conversiones, TRIM y metadatos
        ↓
Tabla transitoria
DB_CURSO.STAGING.VENTAS_RAW
        ↓
UPDATE SQL de normalización
UPPER(TRIM(canal)) y UPPER(TRIM(moneda))
```

El fichero contiene doce ventas. El resultado final debe tener:

- 12 filas.
- Importe total: `1850.43`.
- Canales normalizados: `WEB`, `TIENDA` y `MARKETPLACE`.
- Metadatos de fichero, fila y comienzo de lectura.
- Protección frente a una segunda carga accidental del mismo fichero.

La carga y la normalización se separan porque el `SELECT` de transformación de `COPY INTO` solo admite un subconjunto de funciones. `TRIM`, `TO_NUMBER` y `TO_DATE` están admitidas, pero `UPPER` no lo está. La conversión a mayúsculas se realizará inmediatamente después mediante una sentencia SQL ordinaria.

---

## 2. Crear el fichero SQL dentro de Workspaces

En Snowsight:

1. Abre **Workspaces**.
2. Puedes utilizar `My Workspace` o crear uno específico para el curso.
3. Crea un fichero SQL.
4. Ponle el nombre:

```text
M05_E01_CARGA_CSV.sql
```

Un workspace puede contener varios ficheros SQL. El contexto de ejecución se aplica a las consultas que ejecutes, pero conviene fijarlo también en el propio script para que sea reproducible.

---

## 3. Preparar el contexto y el warehouse

Ejecuta:

```sql
USE ROLE SYSADMIN;

CREATE WAREHOUSE IF NOT EXISTS WH_DEV
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE;

USE WAREHOUSE WH_DEV;

CREATE DATABASE IF NOT EXISTS DB_CURSO;
CREATE SCHEMA IF NOT EXISTS DB_CURSO.STAGING;

USE DATABASE DB_CURSO;
USE SCHEMA STAGING;
```

### Explicación

- `SYSADMIN` puede crear y administrar los objetos del laboratorio.
- `XSMALL` es suficiente para un fichero de este tamaño.
- `AUTO_SUSPEND = 60` reduce el consumo cuando dejamos de ejecutar consultas.
- `AUTO_RESUME = TRUE` permite que el warehouse se reactive automáticamente.
- `STAGING` representa la capa de aterrizaje o preparación de datos.

Comprueba el contexto:

```sql
SELECT
    CURRENT_ROLE()      AS rol_actual,
    CURRENT_WAREHOUSE() AS warehouse_actual,
    CURRENT_DATABASE()  AS base_actual,
    CURRENT_SCHEMA()    AS esquema_actual;
```

Resultado esperado:

| ROL_ACTUAL | WAREHOUSE_ACTUAL | BASE_ACTUAL | ESQUEMA_ACTUAL |
|---|---|---|---|
| SYSADMIN | WH_DEV | DB_CURSO | STAGING |

---

## 4. Crear el file format

Ejecuta:

```sql
CREATE OR REPLACE FILE FORMAT DB_CURSO.STAGING.FF_VENTAS_CSV
    TYPE = CSV
    FIELD_DELIMITER = ';'
    SKIP_HEADER = 1
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    NULL_IF = ('', 'NULL')
    EMPTY_FIELD_AS_NULL = TRUE
    ERROR_ON_COLUMN_COUNT_MISMATCH = TRUE
    ENCODING = 'UTF8';
```

### Qué controla cada opción

| Opción | Finalidad |
|---|---|
| `TYPE = CSV` | Indica el parser que debe utilizar Snowflake. |
| `FIELD_DELIMITER = ';'` | Separa las seis columnas del fichero. |
| `SKIP_HEADER = 1` | Omite la primera línea con nombres de columnas. |
| `FIELD_OPTIONALLY_ENCLOSED_BY = '"'` | Permite campos entre comillas dobles. |
| `NULL_IF = ('', 'NULL')` | Convierte cadenas vacías o `NULL` en SQL `NULL`. |
| `EMPTY_FIELD_AS_NULL = TRUE` | Trata un campo sin contenido como nulo. |
| `ERROR_ON_COLUMN_COUNT_MISMATCH = TRUE` | Detecta registros con un número incorrecto de campos. |
| `ENCODING = 'UTF8'` | Interpreta el fichero como UTF-8. |

Comprueba la definición:

```sql
DESC FILE FORMAT DB_CURSO.STAGING.FF_VENTAS_CSV;
```

También puedes listar los formatos del esquema:

```sql
SHOW FILE FORMATS IN SCHEMA DB_CURSO.STAGING;
```

---

## 5. Crear el named internal stage

Ejecuta:

```sql
CREATE OR REPLACE STAGE DB_CURSO.STAGING.STG_VENTAS_CSV
    FILE_FORMAT = DB_CURSO.STAGING.FF_VENTAS_CSV
    ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE')
    DIRECTORY = (ENABLE = FALSE);
```

### Explicación

- Es un **named internal stage** porque no incluye una URL externa.
- El fichero se almacena en almacenamiento gestionado por Snowflake.
- El stage reutiliza el file format.
- `SNOWFLAKE_SSE` utiliza cifrado del lado del servidor gestionado por Snowflake.
- No necesitamos una directory table para este laboratorio.

Comprueba la definición:

```sql
DESC STAGE DB_CURSO.STAGING.STG_VENTAS_CSV;
```

Lista el stage:

```sql
LIST @DB_CURSO.STAGING.STG_VENTAS_CSV;
```

Antes de subir el fichero, la consulta no debería devolver archivos.

---

## 6. Subir el CSV mediante la interfaz actual de Snowsight

Descarga primero:

```text
Snowflake_Modulo5_Ejercicio1_ventas_julio.csv
```

Después, en Snowsight:

1. Abre **Ingestion**.
2. Selecciona **Add Data**.
3. Selecciona **Load files into a Stage**.
4. Elige el fichero CSV.
5. Selecciona:
   - Base de datos: `DB_CURSO`
   - Esquema: `STAGING`
   - Stage: `STG_VENTAS_CSV`
6. No es necesario crear una ruta adicional.
7. Selecciona **Upload**.

### Por qué no usamos PUT dentro de Workspaces

`PUT` es un comando de cliente que lee un fichero del sistema local donde se ejecuta SnowSQL, Snowflake CLI u otro driver. El editor SQL web no puede acceder directamente al sistema de archivos de tu ordenador. Por eso usamos la opción de carga de Snowsight.

Comprueba la subida:

```sql
LIST @DB_CURSO.STAGING.STG_VENTAS_CSV;
```

El nombre almacenado puede incluir compresión automática o una ruta relativa, dependiendo de cómo se haya subido. Debe aparecer un único fichero relacionado con:

```text
Snowflake_Modulo5_Ejercicio1_ventas_julio.csv
```

---

## 7. Consultar directamente el fichero staged

Ejecuta:

```sql
SELECT
    METADATA$FILENAME        AS fichero,
    METADATA$FILE_ROW_NUMBER AS fila_fichero,
    t.$1                     AS id_venta_txt,
    t.$2                     AS fecha_txt,
    t.$3                     AS id_cliente_txt,
    t.$4                     AS canal_txt,
    t.$5                     AS importe_txt,
    t.$6                     AS moneda_txt
FROM @DB_CURSO.STAGING.STG_VENTAS_CSV t
ORDER BY fila_fichero;
```

### Por qué no indicamos otra vez FILE_FORMAT

El file format está asociado al stage:

```sql
FILE_FORMAT = DB_CURSO.STAGING.FF_VENTAS_CSV
```

Snowflake lo utiliza al consultar los archivos del stage.

### Resultado esperado

Deben aparecer doce filas. Los campos de texto de canal conservan todavía sus diferencias:

```text
web
TIENDA
 marketplace 
WEB
...
```

Esto demuestra que el stage conserva el fichero y que la transformación todavía no se ha realizado.

Comprueba el número de filas:

```sql
SELECT COUNT(*) AS filas_en_fichero
FROM @DB_CURSO.STAGING.STG_VENTAS_CSV;
```

Resultado:

```text
12
```

---

## 8. Crear la tabla transitoria de destino

Ejecuta:

```sql
CREATE OR REPLACE TRANSIENT TABLE DB_CURSO.STAGING.VENTAS_RAW (
    id_venta        NUMBER(18,0),
    fecha           DATE,
    id_cliente      NUMBER(18,0),
    canal           VARCHAR(30),
    importe         NUMBER(12,2),
    moneda          VARCHAR(3),
    fichero_origen  VARCHAR,
    fila_origen     NUMBER,
    inicio_carga    TIMESTAMP_LTZ
);
```

### Por qué es TRANSIENT

La tabla pertenece a una capa RAW/STAGING que puede reconstruirse a partir del fichero original. Una tabla transitoria:

- Persiste entre sesiones.
- Puede usar Time Travel con la retención admitida para este tipo.
- No tiene Fail-safe.
- Evita el almacenamiento adicional de Fail-safe de una tabla permanente.

La trazabilidad técnica se almacena junto con los datos porque será útil para investigar errores y reconciliar cargas.

---

## 9. Ejecutar COPY INTO con transformaciones admitidas

Ejecuta:

```sql
COPY INTO DB_CURSO.STAGING.VENTAS_RAW (
    id_venta,
    fecha,
    id_cliente,
    canal,
    importe,
    moneda,
    fichero_origen,
    fila_origen,
    inicio_carga
)
FROM (
    SELECT
        TO_NUMBER(t.$1),
        TO_DATE(t.$2),
        TO_NUMBER(t.$3),
        TRIM(t.$4),
        TO_NUMBER(t.$5, 12, 2),
        TRIM(t.$6),
        METADATA$FILENAME,
        METADATA$FILE_ROW_NUMBER,
        METADATA$START_SCAN_TIME
    FROM @DB_CURSO.STAGING.STG_VENTAS_CSV t
)
FILE_FORMAT = (
    FORMAT_NAME = 'DB_CURSO.STAGING.FF_VENTAS_CSV'
)
ON_ERROR = 'ABORT_STATEMENT'
PURGE = FALSE;
```

### Explicación de la transformación

```sql
TO_NUMBER(t.$1)
```

Convierte el identificador de venta desde texto a número.

```sql
TO_DATE(t.$2)
```

Convierte el texto ISO `YYYY-MM-DD` en un valor `DATE`.

```sql
TRIM(t.$4)
```

Elimina los espacios situados al principio y al final del canal. `TRIM` sí está admitida dentro de una transformación de `COPY INTO`.

```sql
TO_NUMBER(t.$5, 12, 2)
```

Convierte el importe en un decimal exacto con precisión 12 y escala 2.

```sql
TRIM(t.$6)
```

Elimina posibles espacios del código de moneda. La conversión a mayúsculas se hará en la siguiente fase.

```sql
METADATA$FILENAME
METADATA$FILE_ROW_NUMBER
METADATA$START_SCAN_TIME
```

Añaden trazabilidad generada por Snowflake:

- Fichero del que procede la fila.
- Número de fila dentro del fichero.
- Momento en que comenzó el escaneo del registro.

### Por qué no usamos UPPER dentro del COPY

Aunque `UPPER` es una función SQL válida en Snowflake, no pertenece actualmente al subconjunto de funciones admitidas en el `SELECT` de transformación de `COPY INTO`. Una expresión como:

```sql
UPPER(TRIM(t.$4))
```

provoca el error:

```text
SQL Compilation error: Function 'UPPER' not supported within a COPY
```

Por eso el `COPY` se limita a conversiones de tipo, `TRIM` y columnas de metadatos. La normalización restante se aplica después con SQL ordinario.

### Por qué usamos ABORT_STATEMENT

El fichero de este ejercicio es una entrega controlada. Si una fila no puede convertirse, preferimos no cargar parcialmente el lote. En el siguiente ejercicio compararemos otras estrategias de error.

### Por qué usamos PURGE = FALSE

Queremos conservar el fichero para:

- Repetir consultas sobre el stage.
- Analizar el comportamiento anti-duplicados.
- Auditar la carga.

---

## 10. Normalizar canal y moneda después de la carga

Antes de normalizar, puedes comprobar que `TRIM` eliminó los espacios, pero que todavía pueden existir diferencias de mayúsculas y minúsculas:

```sql
SELECT DISTINCT canal, moneda
FROM DB_CURSO.STAGING.VENTAS_RAW
ORDER BY canal, moneda;
```

Aplica ahora la normalización mediante una sentencia SQL ordinaria:

```sql
UPDATE DB_CURSO.STAGING.VENTAS_RAW
SET
    canal  = UPPER(TRIM(canal)),
    moneda = UPPER(TRIM(moneda));
```

### Por qué esta sentencia es segura para repetir

La operación es **idempotente**: aplicar `UPPER(TRIM(...))` a un valor que ya está normalizado no lo modifica de nuevo. En un proceso más avanzado, esta fase podría implementarse mediante una tabla de capa CURATED, una vista, una dynamic table, dbt o una tarea programada.

> En una arquitectura de producción suele ser preferible conservar una capa RAW inmutable y escribir los datos normalizados en otra capa. En este laboratorio se mantiene una sola tabla para no añadir objetos que distraigan de los objetivos principales.

---

## 11. Validar las filas cargadas y normalizadas

Ejecuta estas comprobaciones después del `UPDATE` de normalización.

### 11.1 Número de filas e importe total

```sql
SELECT
    COUNT(*)     AS numero_filas,
    SUM(importe) AS importe_total
FROM DB_CURSO.STAGING.VENTAS_RAW;
```

Resultado esperado:

| NUMERO_FILAS | IMPORTE_TOTAL |
|---:|---:|
| 12 | 1850.43 |

### 11.2 Datos normalizados

```sql
SELECT
    id_venta,
    fecha,
    id_cliente,
    canal,
    importe,
    moneda,
    fichero_origen,
    fila_origen,
    inicio_carga
FROM DB_CURSO.STAGING.VENTAS_RAW
ORDER BY id_venta;
```

Los valores de canal y moneda deben aparecer sin espacios y en mayúsculas.

### 11.3 Total por canal

```sql
SELECT
    canal,
    COUNT(*)     AS ventas,
    SUM(importe) AS importe_total
FROM DB_CURSO.STAGING.VENTAS_RAW
GROUP BY canal
ORDER BY canal;
```

Resultado esperado:

| CANAL | VENTAS | IMPORTE_TOTAL |
|---|---:|---:|
| MARKETPLACE | 3 | 1060.38 |
| TIENDA | 4 | 411.45 |
| WEB | 5 | 378.60 |

### 11.4 Monedas distintas

```sql
SELECT DISTINCT moneda
FROM DB_CURSO.STAGING.VENTAS_RAW;
```

Resultado:

```text
EUR
```

### 11.5 Control de nulos

```sql
SELECT
    COUNT_IF(id_venta IS NULL)       AS id_venta_nulos,
    COUNT_IF(fecha IS NULL)          AS fecha_nulos,
    COUNT_IF(id_cliente IS NULL)     AS cliente_nulos,
    COUNT_IF(canal IS NULL)          AS canal_nulos,
    COUNT_IF(importe IS NULL)        AS importe_nulos,
    COUNT_IF(moneda IS NULL)         AS moneda_nulos,
    COUNT_IF(fichero_origen IS NULL) AS fichero_nulos,
    COUNT_IF(fila_origen IS NULL)    AS fila_nulos,
    COUNT_IF(inicio_carga IS NULL)   AS inicio_nulos
FROM DB_CURSO.STAGING.VENTAS_RAW;
```

Todos los valores deben ser `0`.

### 11.6 Control de trazabilidad duplicada

```sql
SELECT
    fichero_origen,
    fila_origen,
    COUNT(*) AS apariciones
FROM DB_CURSO.STAGING.VENTAS_RAW
GROUP BY fichero_origen, fila_origen
HAVING COUNT(*) > 1;
```

No debe devolver filas.

---

## 12. Repetir COPY INTO y comprobar el historial de ficheros

Vuelve a ejecutar exactamente el mismo `COPY INTO`.

Snowflake conserva metadatos de los ficheros que ya se cargaron en una tabla. Como:

- Es el mismo fichero.
- No ha cambiado.
- Se carga en la misma tabla.
- No se ha utilizado `FORCE = TRUE`.

Snowflake debe omitirlo.

Comprueba el número de filas:

```sql
SELECT COUNT(*) AS filas_despues_del_segundo_copy
FROM DB_CURSO.STAGING.VENTAS_RAW;
```

Resultado:

```text
12
```

No deben existir 24 filas.

### Qué haría FORCE = TRUE

Esta opción obliga a cargar el fichero aunque Snowflake lo recuerde como ya procesado:

```sql
-- No ejecutar en este ejercicio:
-- COPY INTO ...
-- FORCE = TRUE;
```

Podría duplicar los doce registros. `FORCE` es útil para un reproceso deliberado, pero debe acompañarse de una estrategia de idempotencia, deduplicación o limpieza previa.

---

## 13. Consultar COPY_HISTORY

La función pertenece a `INFORMATION_SCHEMA`, por lo que utilizamos el nombre completamente cualificado:

```sql
SELECT
    file_name,
    stage_location,
    last_load_time,
    row_parsed,
    row_count,
    error_count,
    status,
    first_error_message
FROM TABLE(
    DB_CURSO.INFORMATION_SCHEMA.COPY_HISTORY(
        TABLE_NAME => 'DB_CURSO.STAGING.VENTAS_RAW',
        START_TIME => DATEADD('hour', -1, CURRENT_TIMESTAMP())
    )
)
ORDER BY last_load_time;
```

### Interpretación

En función de cómo la versión actual de la interfaz represente la segunda ejecución, deberías observar:

- Una carga con estado `Loaded`, doce filas analizadas y doce filas cargadas.
- Una ejecución posterior omitida o un resultado de `COPY INTO` que indique que el fichero ya estaba cargado.
- Cero errores en la carga correcta.

`COPY_HISTORY` conserva hasta catorce días cuando se consulta mediante esta función de Information Schema.

> Recrear o eliminar la tabla borra el historial de cargas bulk asociado al objeto. Por eso debes consultar el historial antes de volver a ejecutar `CREATE OR REPLACE TABLE`.

---

## 14. Consultas adicionales de inspección

### Ver los objetos creados

```sql
SHOW FILE FORMATS IN SCHEMA DB_CURSO.STAGING;
SHOW STAGES IN SCHEMA DB_CURSO.STAGING;
SHOW TABLES LIKE 'VENTAS_RAW' IN SCHEMA DB_CURSO.STAGING;
```

### Ver otra vez el fichero staged

```sql
LIST @DB_CURSO.STAGING.STG_VENTAS_CSV;
```

El fichero sigue presente porque usamos:

```sql
PURGE = FALSE
```

---

## 15. Limpieza opcional

No realices esta limpieza si el siguiente ejercicio va a reutilizar los objetos.

Para retirar el fichero:

```sql
REMOVE @DB_CURSO.STAGING.STG_VENTAS_CSV
PATTERN = '.*Snowflake_Modulo5_Ejercicio1_ventas_julio.*';
```

Para eliminar los objetos del ejercicio:

```sql
DROP TABLE IF EXISTS DB_CURSO.STAGING.VENTAS_RAW;
DROP STAGE IF EXISTS DB_CURSO.STAGING.STG_VENTAS_CSV;
DROP FILE FORMAT IF EXISTS DB_CURSO.STAGING.FF_VENTAS_CSV;
```

No elimines `DB_CURSO`, `STAGING` ni `WH_DEV`, porque se utilizan en otros módulos.

---

## 16. Errores frecuentes

### `Function 'UPPER' not supported within a COPY`

**Causa:** se ha utilizado `UPPER` dentro del `SELECT` de transformación de `COPY INTO`.

**Solución:** dentro del `COPY`, utiliza únicamente las transformaciones admitidas, por ejemplo:

```sql
TRIM(t.$4)
```

Después de la carga, ejecuta la normalización con SQL ordinario:

```sql
UPDATE DB_CURSO.STAGING.VENTAS_RAW
SET
    canal  = UPPER(TRIM(canal)),
    moneda = UPPER(TRIM(moneda));
```

---

### El fichero aparece entero en `$1`

**Causa:** el delimitador no se está aplicando.

**Comprobación:**

```sql
DESC FILE FORMAT DB_CURSO.STAGING.FF_VENTAS_CSV;
```

Verifica:

```text
FIELD_DELIMITER = ;
```

También comprueba que el stage está asociado al file format correcto.

---

### La cabecera aparece como una fila de datos

**Causa:** falta `SKIP_HEADER = 1`.

**Solución:**

```sql
CREATE OR REPLACE FILE FORMAT DB_CURSO.STAGING.FF_VENTAS_CSV
    TYPE = CSV
    FIELD_DELIMITER = ';'
    SKIP_HEADER = 1
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    NULL_IF = ('', 'NULL')
    EMPTY_FIELD_AS_NULL = TRUE
    ERROR_ON_COLUMN_COUNT_MISMATCH = TRUE
    ENCODING = 'UTF8';
```

Después debes recrear o alterar el stage para garantizar que usa la definición prevista.

---

### LIST no muestra ningún fichero

Revisa que:

- Seleccionaste `Load files into a Stage`.
- Elegiste `DB_CURSO.STAGING.STG_VENTAS_CSV`.
- La subida terminó correctamente.
- Tu rol tiene `USAGE` sobre la base y el esquema y `WRITE` sobre el stage.

---

### Error de privilegios al subir

El rol que sube el fichero necesita:

- `USAGE` sobre la base de datos.
- `USAGE` sobre el esquema.
- `WRITE` sobre el named internal stage.

Con `SYSADMIN`, si este rol es el propietario de los objetos creados, el laboratorio debe funcionar.

---

### No active warehouse

Ejecuta:

```sql
USE WAREHOUSE WH_DEV;
```

O comprueba:

```sql
SELECT CURRENT_WAREHOUSE();
```

---

### COPY_HISTORY no devuelve filas

Revisa:

1. Que la carga se ejecutó durante el intervalo consultado.
2. Que el nombre de tabla es correcto.
3. Que no recreaste la tabla después de cargar.
4. Que estás consultando `DB_CURSO.INFORMATION_SCHEMA.COPY_HISTORY`.
5. Que tu rol conserva privilegios sobre la tabla.

---

## 17. Respuestas a las preguntas de reflexión

### 1. ¿Por qué reutilizar un named file format?

Centraliza las reglas de interpretación. Si cambia el delimitador, la codificación o el tratamiento de nulos, se actualiza un solo objeto y no decenas de sentencias `COPY INTO`.

### 2. ¿Qué diferencia hay entre consultar y cargar el fichero?

Consultar el stage interpreta el fichero en ese momento, pero no lo convierte en almacenamiento tabular de Snowflake. `COPY INTO` crea filas persistentes en la tabla y registra el historial de carga.

### 3. ¿Por qué guardar los metadatos?

Permiten:

- Identificar el fichero que originó una fila.
- Localizar el registro concreto dentro de ese fichero.
- Investigar incidencias.
- Reconciliar una tabla con la entrega de origen.
- Reprocesar selectivamente.

### 4. ¿Por qué no utilizar FORCE por defecto?

Porque ignora el historial de carga y puede producir duplicados. Debe reservarse para reprocesos controlados.

### 5. ¿Cuándo usar PURGE = TRUE?

Cuando el fichero ya no debe permanecer en el stage después de una carga correcta y existe otra copia fiable en el sistema de origen. En procesos auditables puede ser preferible conservarlo durante un periodo definido.

### 6. ¿Por qué una tabla transitoria?

La capa puede reconstruirse y no necesita Fail-safe. Se conserva entre sesiones, a diferencia de una tabla temporal, pero reduce el almacenamiento histórico frente a una tabla permanente.

### 7. ¿Por qué se separa la normalización a mayúsculas del COPY INTO?

Porque las transformaciones de `COPY INTO` solo admiten un subconjunto de funciones SQL. `TRIM` y las conversiones de tipos sí están admitidas, pero `UPPER` no. Separar la ingesta de la normalización evita el error de compilación y refleja un patrón ELT habitual: primero se cargan los datos y después se aplican reglas de limpieza con SQL completo.

---


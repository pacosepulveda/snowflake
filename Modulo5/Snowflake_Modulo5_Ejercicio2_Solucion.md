# Módulo 5 · Ejercicio 2

## Solución guiada: validación de cargas y estrategias de tratamiento de errores

---

## 1. Diseño del laboratorio

Vamos a ejecutar el mismo tipo de carga con políticas diferentes:

```text
VALIDATION_MODE
    └── Detecta errores, no carga

ABORT_STATEMENT
    └── Encuentra un error y detiene la carga

CONTINUE
    └── Carga las filas correctas y rechaza las erróneas

SKIP_FILE
    └── Si un fichero contiene un error, descarta el fichero completo
```

Utilizaremos tablas distintas para evitar que el historial de ficheros ya cargados interfiera en las pruebas.

---

## 2. Preparar Workspaces y el contexto

En **Workspaces**, crea:

```text
M5_E02_VALIDACION_ERRORES.sql
```

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

Comprueba:

```sql
SELECT
    CURRENT_ROLE()      AS rol,
    CURRENT_WAREHOUSE() AS warehouse,
    CURRENT_DATABASE()  AS base_datos,
    CURRENT_SCHEMA()    AS esquema;
```

---

## 3. Crear el file format

```sql
CREATE OR REPLACE FILE FORMAT DB_CURSO.STAGING.FF_VENTAS_CALIDAD_CSV
    TYPE = CSV
    FIELD_DELIMITER = ';'
    SKIP_HEADER = 1
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    DATE_FORMAT = 'YYYY-MM-DD'
    NULL_IF = ('', 'NULL')
    EMPTY_FIELD_AS_NULL = TRUE
    ERROR_ON_COLUMN_COUNT_MISMATCH = TRUE
    ENCODING = 'UTF8';
```

### Por qué indicamos DATE_FORMAT

La tabla destino contiene una columna `DATE`. El formato explícito evita que el resultado dependa de parámetros de sesión o de inferencias ambiguas.

Comprueba:

```sql
DESC FILE FORMAT DB_CURSO.STAGING.FF_VENTAS_CALIDAD_CSV;
```

---

## 4. Crear el stage

```sql
CREATE OR REPLACE STAGE DB_CURSO.STAGING.STG_VENTAS_CALIDAD
    FILE_FORMAT = DB_CURSO.STAGING.FF_VENTAS_CALIDAD_CSV
    ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE')
    DIRECTORY = (ENABLE = FALSE);
```

Comprueba:

```sql
DESC STAGE DB_CURSO.STAGING.STG_VENTAS_CALIDAD;
LIST @DB_CURSO.STAGING.STG_VENTAS_CALIDAD;
```

---

## 5. Crear las tablas de prueba

Creamos una tabla base y tres copias con la misma estructura:

```sql
CREATE OR REPLACE TRANSIENT TABLE DB_CURSO.STAGING.VENTAS_VALIDACION (
    id_venta   NUMBER(18,0),
    fecha      DATE,
    id_cliente NUMBER(18,0),
    canal      VARCHAR(20),
    importe    NUMBER(12,2),
    moneda     VARCHAR(3)
);

CREATE OR REPLACE TRANSIENT TABLE DB_CURSO.STAGING.VENTAS_ABORT
LIKE DB_CURSO.STAGING.VENTAS_VALIDACION;

CREATE OR REPLACE TRANSIENT TABLE DB_CURSO.STAGING.VENTAS_CONTINUE
LIKE DB_CURSO.STAGING.VENTAS_VALIDACION;

CREATE OR REPLACE TRANSIENT TABLE DB_CURSO.STAGING.VENTAS_SKIP_FILE
LIKE DB_CURSO.STAGING.VENTAS_VALIDACION;
```

### Por qué usamos tablas distintas

Snowflake mantiene metadatos sobre qué ficheros se han cargado en cada tabla. Si reutilizásemos la misma tabla, una prueba podría hacer que el fichero se omitiese en la siguiente. Cada tabla proporciona un contexto de carga independiente.

---

## 6. Subir los dos ficheros

Sube mediante:

```text
Ingestion → Add Data → Load files into a Stage
```

los ficheros:

```text
Snowflake_Modulo5_Ejercicio2_ventas_validas.csv
Snowflake_Modulo5_Ejercicio2_ventas_con_errores.csv
```

al stage:

```text
DB_CURSO.STAGING.STG_VENTAS_CALIDAD
```

Después:

```sql
LIST @DB_CURSO.STAGING.STG_VENTAS_CALIDAD;
```

El nombre puede terminar en `.gz` si la interfaz ha aplicado compresión automática. Por eso las sentencias posteriores utilizan expresiones regulares que aceptan `.csv` y `.csv.gz`.

---

## 7. Inspeccionar los datos staged

```sql
SELECT
    METADATA$FILENAME        AS fichero,
    METADATA$FILE_ROW_NUMBER AS fila,
    t.$1 AS id_venta,
    t.$2 AS fecha,
    t.$3 AS id_cliente,
    t.$4 AS canal,
    t.$5 AS importe,
    t.$6 AS moneda
FROM @DB_CURSO.STAGING.STG_VENTAS_CALIDAD t
ORDER BY fichero, fila;
```

En el fichero defectuoso deben localizarse:

| ID | Problema |
|---:|---|
| 3102 | Fecha `2026-02-30` |
| 3103 | Cliente `CLIENTE_X` |
| 3104 | Importe `ABC` |
| 3105 | Moneda `EURO`, superior a `VARCHAR(3)` |

La consulta staged devuelve texto y no intenta todavía convertirlo a los tipos de la tabla. Por eso es posible verlo aunque sea incorrecto.

---

## 8. Validar sin cargar

Ejecuta:

```sql
COPY INTO DB_CURSO.STAGING.VENTAS_VALIDACION
FROM @DB_CURSO.STAGING.STG_VENTAS_CALIDAD
PATTERN = '.*Snowflake_Modulo5_Ejercicio2_ventas_con_errores[.]csv([.]gz)?'
FILE_FORMAT = (
    FORMAT_NAME = 'DB_CURSO.STAGING.FF_VENTAS_CALIDAD_CSV'
)
ENFORCE_LENGTH = TRUE
VALIDATION_MODE = RETURN_ERRORS;
```

### Qué hace VALIDATION_MODE

Snowflake:

1. Lee el fichero.
2. Aplica el file format.
3. Intenta convertir cada campo al tipo de la tabla.
4. Devuelve los errores.
5. No inserta ninguna fila.

El resultado debe incluir cuatro errores:

- Conversión de fecha.
- Conversión de número para `ID_CLIENTE`.
- Conversión de número para `IMPORTE`.
- Longitud superior a la permitida para `MONEDA`.

Comprueba que la tabla sigue vacía:

```sql
SELECT COUNT(*) AS filas
FROM DB_CURSO.STAGING.VENTAS_VALIDACION;
```

Resultado:

```text
0
```

### RETURN_ERRORS frente a RETURN_ALL_ERRORS

`RETURN_ERRORS` devuelve los errores de los ficheros que se validarían en ese momento.

`RETURN_ALL_ERRORS` incluye además errores de ficheros que ya se cargaron parcialmente en esa tabla mediante `ON_ERROR = CONTINUE`.

Antes de cualquier carga parcial, ambos deberían mostrar los mismos cuatro errores.

---

## 9. Probar ABORT_STATEMENT

Ejecuta:

```sql
COPY INTO DB_CURSO.STAGING.VENTAS_ABORT
FROM @DB_CURSO.STAGING.STG_VENTAS_CALIDAD
PATTERN = '.*Snowflake_Modulo5_Ejercicio2_ventas_con_errores[.]csv([.]gz)?'
FILE_FORMAT = (
    FORMAT_NAME = 'DB_CURSO.STAGING.FF_VENTAS_CALIDAD_CSV'
)
ENFORCE_LENGTH = TRUE
ON_ERROR = ABORT_STATEMENT;
```

La sentencia debe finalizar con error al encontrar una fila no convertible.

Comprueba:

```sql
SELECT COUNT(*) AS filas
FROM DB_CURSO.STAGING.VENTAS_ABORT;
```

Resultado esperado:

```text
0
```

### Dónde encontrar el fallo

Abre Query History desde Snowsight y localiza la sentencia `COPY INTO`.

La documentación actual indica que las operaciones terminadas por `ABORT_STATEMENT` no aparecen en `COPY_HISTORY`, porque los ficheros no fueron ingeridos. Query History sí registra la sentencia y su error.

Comprueba:

```sql
SELECT *
FROM TABLE(
    DB_CURSO.INFORMATION_SCHEMA.COPY_HISTORY(
        TABLE_NAME => 'DB_CURSO.STAGING.VENTAS_ABORT',
        START_TIME => DATEADD('hour', -1, CURRENT_TIMESTAMP())
    )
);
```

Es normal que no aparezca una entrada de carga para el fichero abortado.

---

## 10. Probar CONTINUE

Ejecuta:

```sql
COPY INTO DB_CURSO.STAGING.VENTAS_CONTINUE
FROM @DB_CURSO.STAGING.STG_VENTAS_CALIDAD
PATTERN = '.*Snowflake_Modulo5_Ejercicio2_ventas_con_errores[.]csv([.]gz)?'
FILE_FORMAT = (
    FORMAT_NAME = 'DB_CURSO.STAGING.FF_VENTAS_CALIDAD_CSV'
)
ENFORCE_LENGTH = TRUE
ON_ERROR = CONTINUE;
```

### Resultado esperado de COPY INTO

El resultado debe aproximarse a:

| Métrica | Valor esperado |
|---|---:|
| `ROWS_PARSED` | 8 |
| `ROWS_LOADED` | 4 |
| `ERRORS_SEEN` | 4 |

La sentencia solo muestra como máximo el primer error de cada fichero. No debes interpretar `FIRST_ERROR` como si fuera el único problema.

### Validar la tabla

```sql
SELECT *
FROM DB_CURSO.STAGING.VENTAS_CONTINUE
ORDER BY id_venta;
```

IDs esperados:

```text
3101
3106
3107
3108
```

Comprueba:

```sql
SELECT
    COUNT(*)     AS filas,
    SUM(importe) AS total
FROM DB_CURSO.STAGING.VENTAS_CONTINUE;
```

Resultado:

| FILAS | TOTAL |
|---:|---:|
| 4 | 345.74 |

---

## 11. Recuperar todos los errores con VALIDATE

Ejecuta esta consulta inmediatamente después de la carga con `CONTINUE`:

```sql
SELECT *
FROM TABLE(
    VALIDATE(
        DB_CURSO.STAGING.VENTAS_CONTINUE,
        JOB_ID => '_last'
    )
)
ORDER BY file, row_number;
```

`_last` hace referencia al último job `COPY INTO` ejecutado en la sesión.

### Qué devuelve VALIDATE

La función puede mostrar columnas como:

- `ERROR`.
- `FILE`.
- `LINE`.
- `CHARACTER`.
- `BYTE_OFFSET`.
- `CATEGORY`.
- `CODE`.
- `SQL_STATE`.
- `COLUMN_NAME`.
- `ROW_NUMBER`.
- `ROW_START_LINE`.
- `REJECTED_RECORD`.

Los nombres visibles pueden variar ligeramente según el tipo de error, pero deben recuperarse las cuatro filas problemáticas.

### Diferencia con el resultado de COPY INTO

`COPY INTO ... ON_ERROR = CONTINUE` devuelve:

- Conteos.
- Estado.
- Un máximo de un primer error por fichero.

`VALIDATE` devuelve todos los errores encontrados durante aquel job.

### Limitaciones importantes

`VALIDATE`:

- Funciona para cargas estándar.
- No admite un `COPY INTO` que transforme datos con `FROM (SELECT ...)`.
- No devuelve resultados útiles para cargas ejecutadas con `ABORT_STATEMENT`.
- Necesita que el historial de carga siga disponible.

En este ejercicio usamos una carga posicional estándar precisamente para poder practicar `VALIDATE`.

---

## 12. Probar SKIP_FILE

Ejecuta:

```sql
COPY INTO DB_CURSO.STAGING.VENTAS_SKIP_FILE
FROM @DB_CURSO.STAGING.STG_VENTAS_CALIDAD
PATTERN = '.*Snowflake_Modulo5_Ejercicio2_ventas_(validas|con_errores)[.]csv([.]gz)?'
FILE_FORMAT = (
    FORMAT_NAME = 'DB_CURSO.STAGING.FF_VENTAS_CALIDAD_CSV'
)
ENFORCE_LENGTH = TRUE
ON_ERROR = SKIP_FILE;
```

### Comportamiento esperado

- El fichero válido se carga completo.
- El fichero defectuoso se omite completo.
- Las cuatro filas válidas que había dentro del fichero defectuoso también se pierden.

Comprueba:

```sql
SELECT *
FROM DB_CURSO.STAGING.VENTAS_SKIP_FILE
ORDER BY id_venta;
```

IDs esperados:

```text
3001
3002
3003
3004
```

Comprueba el resumen:

```sql
SELECT
    COUNT(*)     AS filas,
    SUM(importe) AS total
FROM DB_CURSO.STAGING.VENTAS_SKIP_FILE;
```

Resultado:

| FILAS | TOTAL |
|---:|---:|
| 4 | 426.50 |

Comprueba que no existen IDs del lote 31xx:

```sql
SELECT COUNT(*) AS filas_del_fichero_defectuoso
FROM DB_CURSO.STAGING.VENTAS_SKIP_FILE
WHERE id_venta BETWEEN 3100 AND 3199;
```

Resultado:

```text
0
```

### Por qué SKIP_FILE puede ser más lento

Snowflake necesita almacenar temporalmente o examinar el fichero completo para decidir si debe aceptar o descartar la unidad completa. La documentación advierte que puede consumir más tiempo que `CONTINUE` o `ABORT_STATEMENT`, especialmente con ficheros grandes.

---

## 13. Consultar COPY_HISTORY

### Historial de CONTINUE

```sql
SELECT
    file_name,
    last_load_time,
    row_parsed,
    row_count,
    error_count,
    status,
    first_error_message,
    first_error_line_number,
    first_error_column_name
FROM TABLE(
    DB_CURSO.INFORMATION_SCHEMA.COPY_HISTORY(
        TABLE_NAME => 'DB_CURSO.STAGING.VENTAS_CONTINUE',
        START_TIME => DATEADD('hour', -1, CURRENT_TIMESTAMP())
    )
)
ORDER BY last_load_time;
```

Debes observar una carga parcial:

- 8 filas analizadas.
- 4 filas cargadas.
- 4 errores.
- Estado coherente con una carga parcial.

### Historial de SKIP_FILE

```sql
SELECT
    file_name,
    last_load_time,
    row_parsed,
    row_count,
    error_count,
    status,
    first_error_message
FROM TABLE(
    DB_CURSO.INFORMATION_SCHEMA.COPY_HISTORY(
        TABLE_NAME => 'DB_CURSO.STAGING.VENTAS_SKIP_FILE',
        START_TIME => DATEADD('hour', -1, CURRENT_TIMESTAMP())
    )
)
ORDER BY file_name;
```

Debes distinguir:

- El fichero válido, cargado con cuatro filas.
- El fichero defectuoso, descartado o no cargado debido a sus errores.

La etiqueta exacta de estado que muestre la interfaz debe interpretarse junto con `ROW_COUNT`, `ERROR_COUNT` y el resultado de la sentencia. No bases el diagnóstico únicamente en una palabra de estado.

### Retención

La función `INFORMATION_SCHEMA.COPY_HISTORY` consulta hasta catorce días de historial. Para periodos superiores se utiliza la vista de Account Usage.

---

## 14. Comparación final

| Mecanismo | Inserta datos | Resultado de este ejercicio | Uso típico |
|---|---|---|---|
| `VALIDATION_MODE` | No | Devuelve cuatro errores | Prevalidación |
| `ABORT_STATEMENT` | No, si hay error | Tabla vacía | Lotes críticos |
| `CONTINUE` | Sí, parcialmente | 4 correctas y 4 rechazadas | Errores tolerables |
| `SKIP_FILE` | Por fichero | Carga el fichero bueno y descarta el malo | Fichero indivisible |

---

## 15. Recomendación por escenario

| Escenario | Estrategia | Justificación |
|---|---|---|
| Cierre contable | `VALIDATION_MODE` y después `ABORT_STATEMENT` | No se acepta un lote incompleto. |
| Telemetría con errores puntuales | `CONTINUE` + `VALIDATE` + cuarentena | Se conserva la mayoría de eventos y se investigan los rechazados. |
| Fichero como unidad indivisible | `SKIP_FILE` | O se acepta todo el fichero o se rechaza. |
| Comprobación previa | `VALIDATION_MODE = RETURN_ERRORS` | Detecta fallos sin modificar datos. |

En producción, `CONTINUE` debería acompañarse de:

- Umbral máximo de error.
- Tabla de cuarentena.
- Alertas.
- Reconciliación de filas.
- Política explícita de reproceso.

---

## 16. Extensión opcional: umbrales

Snowflake admite:

```text
SKIP_FILE_n
SKIP_FILE_n%
```

Por ejemplo:

```sql
ON_ERROR = 'SKIP_FILE_25%'
```

El fichero defectuoso tiene un 50 % de filas erróneas, por lo que debería descartarse al superar ese umbral.

Realiza esta prueba en una tabla nueva si quieres comparar el comportamiento. No reutilices una tabla que ya haya cargado esos mismos ficheros.

---

## 17. Limpieza opcional

```sql
DROP TABLE IF EXISTS DB_CURSO.STAGING.VENTAS_VALIDACION;
DROP TABLE IF EXISTS DB_CURSO.STAGING.VENTAS_ABORT;
DROP TABLE IF EXISTS DB_CURSO.STAGING.VENTAS_CONTINUE;
DROP TABLE IF EXISTS DB_CURSO.STAGING.VENTAS_SKIP_FILE;

REMOVE @DB_CURSO.STAGING.STG_VENTAS_CALIDAD
PATTERN = '.*Snowflake_Modulo5_Ejercicio2_ventas_.*';

DROP STAGE IF EXISTS DB_CURSO.STAGING.STG_VENTAS_CALIDAD;
DROP FILE FORMAT IF EXISTS DB_CURSO.STAGING.FF_VENTAS_CALIDAD_CSV;
```

No elimines `DB_CURSO`, `STAGING` ni `WH_DEV`.

---

## 18. Errores frecuentes

### VALIDATION_MODE intenta insertar

No debería hacerlo. Revisa que la cláusula aparezca dentro de la sentencia:

```sql
VALIDATION_MODE = RETURN_ERRORS
```

y que no estés ejecutando otra sentencia `COPY INTO`.

---

### VALIDATE no devuelve errores

Comprueba:

1. Que la última carga usó `ON_ERROR = CONTINUE`.
2. Que fue una carga estándar, no una transformación `FROM (SELECT ...)`.
3. Que estás en la misma sesión si utilizas `JOB_ID => '_last'`.
4. Que no ejecutaste una carga posterior.
5. Que el fichero sigue disponible.
6. Que tienes acceso a la tabla.

---

### El error de EURO no aparece

Comprueba que:

```sql
moneda VARCHAR(3)
```

y que el `COPY INTO` incluye:

```sql
ENFORCE_LENGTH = TRUE
```

---

### Se cargan datos antiguos o faltan ficheros

Lista el stage:

```sql
LIST @DB_CURSO.STAGING.STG_VENTAS_CALIDAD;
```

Revisa el `PATTERN`. La expresión incluye `.*` porque Snowflake aplica el patrón a la localización completa del fichero en una carga bulk.

---

### COPY INTO omite el fichero

Puede haberse cargado anteriormente en esa misma tabla. Usa una tabla nueva para repetir la prueba. No utilices `FORCE = TRUE` salvo que quieras realizar un reproceso deliberado.

---

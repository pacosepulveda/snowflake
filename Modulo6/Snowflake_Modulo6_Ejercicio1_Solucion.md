# Módulo 6 · Ejercicio 1
## Solución guiada: de datos RAW a datos CURATED

> Todas las instrucciones utilizan **Workspaces**, la experiencia actual de edición SQL de Snowflake.

---

## 1. Resultado que vamos a construir

```text
DB_CURSO.STAGING.VENTAS_RAW_ELT
        │
        └── View con CTE y funciones TRY_*
                │
                └── STAGING.VENTAS_CLASIFICADAS
                        ├── CURATED.VENTAS_LIMPIAS
                        └── STAGING.VENTAS_RECHAZADAS
```

La idea central del patrón ELT es que Snowflake recibe primero una copia fiel de la fuente y realiza la transformación después, utilizando SQL y un virtual warehouse.

---

## 2. Preparar Workspaces y el contexto

En **Workspaces**, crea:

```text
M6_E01_RAW_A_CURATED.sql
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
CREATE SCHEMA IF NOT EXISTS DB_CURSO.CURATED;

USE DATABASE DB_CURSO;
USE SCHEMA STAGING;

ALTER SESSION SET QUERY_TAG = 'M06_E01_RAW_A_CURATED';
```

Comprueba el contexto:

```sql
SELECT
    CURRENT_ROLE()      AS rol,
    CURRENT_WAREHOUSE() AS warehouse,
    CURRENT_DATABASE()  AS base_datos,
    CURRENT_SCHEMA()    AS esquema;
```

---

## 3. Crear la tabla RAW

Ejecuta:

```sql
CREATE OR REPLACE TRANSIENT TABLE DB_CURSO.STAGING.VENTAS_RAW_ELT (
    id_venta_raw              VARCHAR,
    fecha_raw                 VARCHAR,
    id_cliente_raw            VARCHAR,
    canal_raw                 VARCHAR,
    importe_raw               VARCHAR,
    moneda_raw                VARCHAR,
    estado_raw                VARCHAR,
    fecha_modificacion_raw    VARCHAR,
    _source_file              VARCHAR,
    _file_row_number          NUMBER,
    _loaded_at                TIMESTAMP_LTZ
);
```

### Por qué todo es VARCHAR

La capa RAW debe priorizar la fidelidad al origen:

- Evita que una conversión incorrecta detenga la ingesta.
- Permite conservar valores defectuosos para investigarlos.
- Hace posible reprocesar la transformación sin volver a obtener el fichero.
- Separa la responsabilidad de carga de la responsabilidad de calidad.

La tabla es `TRANSIENT` porque el lote puede reconstruirse desde su fuente y no necesita Fail-safe.

---

## 4. Insertar los 16 registros

```sql
INSERT INTO DB_CURSO.STAGING.VENTAS_RAW_ELT (
    id_venta_raw,
    fecha_raw,
    id_cliente_raw,
    canal_raw,
    importe_raw,
    moneda_raw,
    estado_raw,
    fecha_modificacion_raw,
    _source_file,
    _file_row_number,
    _loaded_at
)
SELECT
    column1,
    column2,
    column3,
    column4,
    column5,
    column6,
    column7,
    column8,
    'ventas_marzo_lote_01.csv',
    column9,
    CURRENT_TIMESTAMP()
FROM VALUES
    (' 5001 ', '2026-03-01', '701',       ' web ',        '129,95', ' eur ', ' completada ', '2026-03-01 10:15:00', 1),
    ('5002',   '01/03/2026', '702',       'TIENDA',       '89.50',  'EUR',   'COMPLETADA',   '2026-03-01 11:00:00', 2),
    ('5003',   '2026-03-02', '703',       '',             '45,00',  'eur',   'PENDIENTE',    '2026-03-02 09:00:00', 3),
    ('5004',   '2026-03-02', '704',       'marketplace',  '250.00', 'USD',   'COMPLETADA',   '2026-03-02 13:30:00', 4),
    ('5005',   '03/03/2026', '705',       'tienda',       '310,40', 'GBP',   'CANCELADA',    '2026-03-03 08:45:00', 5),
    ('5006',   '2026-03-03', '706',       'WEB',          '64,75',  'EUR',   'completada',   '2026-03-03 14:10:00', 6),
    ('5007',   '2026-03-04', '707',       ' tienda ',     '54.60',  'eur',   'pendiente',    '2026-03-04 10:00:00', 7),
    ('5008',   '04/03/2026', '708',       'MARKETPLACE',  '119.00', 'EUR',   'COMPLETADA',   '2026-03-04 16:20:00', 8),
    ('5009',   '2026-03-05', '709',       'web',          '92,35',  'EUR',   'COMPLETADA',   '2026-03-05 09:15:00', 9),
    ('5010',   '2026-03-05', '710',       'WEB',          '499.99', 'eur',   'COMPLETADA',   '2026-03-05 18:00:00', 10),
    ('5011',   '06/03/2026', '711',       NULL,           '25.00',  'EUR',   'PENDIENTE',    '2026-03-06 08:00:00', 11),
    ('X-9001', '2026-03-06', '712',       'WEB',          '40.00',  'EUR',   'COMPLETADA',   '2026-03-06 09:00:00', 12),
    ('9002',   '31/02/2026', '713',       'TIENDA',       '50.00',  'EUR',   'COMPLETADA',   '2026-03-06 09:30:00', 13),
    ('9003',   '2026-03-06', 'CLIENTE-X', 'WEB',          '60.00',  'EUR',   'COMPLETADA',   '2026-03-06 10:00:00', 14),
    ('9004',   '2026-03-06', '714',       'WEB',          '-15,00', 'EUR',   'COMPLETADA',   '2026-03-06 10:30:00', 15),
    ('9005',   '2026-03-06', '715',       'WEB',          '70.00',  'JPY',   'COMPLETADA',   '2026-03-06 11:00:00', 16);
```

Comprueba:

```sql
SELECT COUNT(*) AS filas_raw
FROM DB_CURSO.STAGING.VENTAS_RAW_ELT;
```

Resultado:

```text
16
```

Visualiza algunos datos originales:

```sql
SELECT
    _file_row_number,
    id_venta_raw,
    fecha_raw,
    canal_raw,
    importe_raw,
    moneda_raw
FROM DB_CURSO.STAGING.VENTAS_RAW_ELT
ORDER BY _file_row_number;
```

Debes seguir viendo:

- Espacios.
- Comas decimales.
- Dos formatos de fecha.
- Valores incorrectos.

---

## 5. Probar la transformación como consulta

Antes de crear la view, construimos la lógica con CTE.

```sql
WITH raw_limpia AS (
    SELECT
        r.*,

        NULLIF(TRIM(id_venta_raw), '')           AS id_venta_txt,
        NULLIF(TRIM(fecha_raw), '')              AS fecha_txt,
        NULLIF(TRIM(id_cliente_raw), '')         AS id_cliente_txt,
        NULLIF(UPPER(TRIM(canal_raw)), '')       AS canal_txt,
        NULLIF(TRIM(importe_raw), '')            AS importe_txt,
        NULLIF(UPPER(TRIM(moneda_raw)), '')      AS moneda_txt,
        NULLIF(UPPER(TRIM(estado_raw)), '')      AS estado_txt,
        NULLIF(TRIM(fecha_modificacion_raw), '') AS fecha_modificacion_txt
    FROM DB_CURSO.STAGING.VENTAS_RAW_ELT r
),

tipada AS (
    SELECT
        raw_limpia.*,

        TRY_TO_NUMBER(id_venta_txt) AS id_venta,

        COALESCE(
            TRY_TO_DATE(fecha_txt, 'YYYY-MM-DD'),
            TRY_TO_DATE(fecha_txt, 'DD/MM/YYYY')
        ) AS fecha,

        TRY_TO_NUMBER(id_cliente_txt) AS id_cliente,

        COALESCE(canal_txt, 'SIN_CANAL')::VARCHAR(20) AS canal,

        TRY_TO_DECIMAL(
            REPLACE(importe_txt, ',', '.'),
            12,
            2
        ) AS importe,

        moneda_txt::VARCHAR(3) AS moneda,
        estado_txt::VARCHAR(20) AS estado,

        TRY_TO_TIMESTAMP_NTZ(
            fecha_modificacion_txt,
            'YYYY-MM-DD HH24:MI:SS'
        ) AS fecha_modificacion
    FROM raw_limpia
),

clasificada AS (
    SELECT
        tipada.*,

        CASE
            WHEN id_venta IS NULL
                THEN 'ID_VENTA_INVALIDO'

            WHEN fecha IS NULL
                THEN 'FECHA_INVALIDA'

            WHEN id_cliente IS NULL
                THEN 'ID_CLIENTE_INVALIDO'

            WHEN importe IS NULL OR importe <= 0
                THEN 'IMPORTE_INVALIDO'

            WHEN moneda NOT IN ('EUR', 'USD', 'GBP')
                THEN 'MONEDA_INVALIDA'

            WHEN estado NOT IN (
                'COMPLETADA',
                'PENDIENTE',
                'CANCELADA'
            )
                THEN 'ESTADO_INVALIDO'

            WHEN fecha_modificacion IS NULL
                THEN 'FECHA_MODIFICACION_INVALIDA'

            ELSE NULL
        END AS motivo_rechazo,

        CURRENT_TIMESTAMP() AS _transformed_at
    FROM tipada
)

SELECT *
FROM clasificada
ORDER BY _file_row_number;
```

---

## 6. Explicación de las funciones

### TRIM

```sql
TRIM(id_venta_raw)
```

Elimina espacios al principio y al final.

### NULLIF

```sql
NULLIF(TRIM(canal_raw), '')
```

Convierte una cadena vacía en SQL `NULL`.

### UPPER

```sql
UPPER(TRIM(moneda_raw))
```

Normaliza valores como:

```text
 eur
EUR
Eur
```

a:

```text
EUR
```

### COALESCE

```sql
COALESCE(canal_txt, 'SIN_CANAL')
```

Utiliza un valor alternativo cuando el canal original está vacío o es nulo.

### TRY_TO_NUMBER

```sql
TRY_TO_NUMBER('X-9001')
```

devuelve `NULL`, no un error que detenga toda la consulta.

### TRY_TO_DATE y COALESCE

```sql
COALESCE(
    TRY_TO_DATE(fecha_txt, 'YYYY-MM-DD'),
    TRY_TO_DATE(fecha_txt, 'DD/MM/YYYY')
)
```

Prueba el primer formato y, si no funciona, el segundo.

### TRY_TO_DECIMAL

```sql
TRY_TO_DECIMAL(
    REPLACE(importe_txt, ',', '.'),
    12,
    2
)
```

Primero normaliza el separador decimal y después intenta crear un `NUMBER(12,2)`.

Una cantidad como `-15,00` puede convertirse correctamente a `-15.00`, pero sigue siendo inválida por la regla de negocio:

```sql
importe <= 0
```

Esta diferencia es importante:

- **Validez técnica:** el valor puede convertirse.
- **Validez de negocio:** el valor cumple las reglas de la empresa.

---

## 7. Crear la view reutilizable

```sql
CREATE OR REPLACE VIEW DB_CURSO.STAGING.V_VENTAS_NORMALIZADAS AS

WITH raw_limpia AS (
    SELECT
        r.*,

        NULLIF(TRIM(id_venta_raw), '')           AS id_venta_txt,
        NULLIF(TRIM(fecha_raw), '')              AS fecha_txt,
        NULLIF(TRIM(id_cliente_raw), '')         AS id_cliente_txt,
        NULLIF(UPPER(TRIM(canal_raw)), '')       AS canal_txt,
        NULLIF(TRIM(importe_raw), '')            AS importe_txt,
        NULLIF(UPPER(TRIM(moneda_raw)), '')      AS moneda_txt,
        NULLIF(UPPER(TRIM(estado_raw)), '')      AS estado_txt,
        NULLIF(TRIM(fecha_modificacion_raw), '') AS fecha_modificacion_txt
    FROM DB_CURSO.STAGING.VENTAS_RAW_ELT r
),

tipada AS (
    SELECT
        raw_limpia.*,

        TRY_TO_NUMBER(id_venta_txt) AS id_venta,

        COALESCE(
            TRY_TO_DATE(fecha_txt, 'YYYY-MM-DD'),
            TRY_TO_DATE(fecha_txt, 'DD/MM/YYYY')
        ) AS fecha,

        TRY_TO_NUMBER(id_cliente_txt) AS id_cliente,

        COALESCE(canal_txt, 'SIN_CANAL')::VARCHAR(20) AS canal,

        TRY_TO_DECIMAL(
            REPLACE(importe_txt, ',', '.'),
            12,
            2
        ) AS importe,

        moneda_txt::VARCHAR(3) AS moneda,
        estado_txt::VARCHAR(20) AS estado,

        TRY_TO_TIMESTAMP_NTZ(
            fecha_modificacion_txt,
            'YYYY-MM-DD HH24:MI:SS'
        ) AS fecha_modificacion
    FROM raw_limpia
)

SELECT
    tipada.*,

    CASE
        WHEN id_venta IS NULL
            THEN 'ID_VENTA_INVALIDO'

        WHEN fecha IS NULL
            THEN 'FECHA_INVALIDA'

        WHEN id_cliente IS NULL
            THEN 'ID_CLIENTE_INVALIDO'

        WHEN importe IS NULL OR importe <= 0
            THEN 'IMPORTE_INVALIDO'

        WHEN moneda NOT IN ('EUR', 'USD', 'GBP')
            THEN 'MONEDA_INVALIDA'

        WHEN estado NOT IN (
            'COMPLETADA',
            'PENDIENTE',
            'CANCELADA'
        )
            THEN 'ESTADO_INVALIDO'

        WHEN fecha_modificacion IS NULL
            THEN 'FECHA_MODIFICACION_INVALIDA'

        ELSE NULL
    END AS motivo_rechazo,

    CURRENT_TIMESTAMP() AS _transformed_at

FROM tipada;
```

Comprueba:

```sql
SELECT COUNT(*) AS filas_view
FROM DB_CURSO.STAGING.V_VENTAS_NORMALIZADAS;
```

Resultado:

```text
16
```

Inspecciona la definición:

```sql
SELECT GET_DDL(
    'VIEW',
    'DB_CURSO.STAGING.V_VENTAS_NORMALIZADAS'
);
```

---

## 8. Materializar la clasificación con CTAS

```sql
CREATE OR REPLACE TRANSIENT TABLE
    DB_CURSO.STAGING.VENTAS_CLASIFICADAS

COPY GRANTS

AS
SELECT *
FROM DB_CURSO.STAGING.V_VENTAS_NORMALIZADAS;
```

### Qué hace CTAS

`CREATE TABLE AS SELECT`:

1. Ejecuta la consulta.
2. Infiere las columnas y sus tipos.
3. Guarda el resultado físicamente en una tabla.

`COPY GRANTS` conserva los grants de la tabla reemplazada cuando se usa con `CREATE OR REPLACE`. En la primera creación no existen privilegios anteriores que copiar, pero la sentencia queda preparada para reconstrucciones posteriores.

Comprueba:

```sql
SELECT
    COUNT(*) AS filas,
    COUNT_IF(motivo_rechazo IS NULL) AS validas,
    COUNT_IF(motivo_rechazo IS NOT NULL) AS rechazadas
FROM DB_CURSO.STAGING.VENTAS_CLASIFICADAS;
```

Resultado esperado:

| FILAS | VALIDAS | RECHAZADAS |
|---:|---:|---:|
| 16 | 11 | 5 |

---

## 9. Crear la tabla CURATED

```sql
CREATE OR REPLACE TABLE DB_CURSO.CURATED.VENTAS_LIMPIAS

COPY GRANTS

AS
SELECT
    id_venta,
    fecha,
    id_cliente,
    canal,
    importe,
    moneda,
    estado,
    fecha_modificacion,
    _source_file,
    _file_row_number,
    _loaded_at,
    _transformed_at
FROM DB_CURSO.STAGING.VENTAS_CLASIFICADAS
WHERE motivo_rechazo IS NULL;
```

### Por qué es una tabla permanente

`CURATED` contiene datos limpios y consistentes que pueden ser utilizados por procesos posteriores. No es simplemente un área de trabajo recreable a corto plazo.

Comprueba:

```sql
SELECT COUNT(*) AS filas_curated
FROM DB_CURSO.CURATED.VENTAS_LIMPIAS;
```

Resultado:

```text
11
```

---

## 10. Crear la tabla de rechazos

```sql
CREATE OR REPLACE TRANSIENT TABLE
    DB_CURSO.STAGING.VENTAS_RECHAZADAS

COPY GRANTS

AS
SELECT *
FROM DB_CURSO.STAGING.VENTAS_CLASIFICADAS
WHERE motivo_rechazo IS NOT NULL;
```

Comprueba:

```sql
SELECT COUNT(*) AS filas_rechazadas
FROM DB_CURSO.STAGING.VENTAS_RECHAZADAS;
```

Resultado:

```text
5
```

La tabla conserva:

- Valor original.
- Valor tipado cuando la conversión fue posible.
- Motivo.
- Fichero y fila.
- Tiempos de carga y transformación.

---

## 11. Reconciliar el proceso

```sql
WITH control AS (
    SELECT
        (
            SELECT COUNT(*)
            FROM DB_CURSO.STAGING.VENTAS_RAW_ELT
        ) AS filas_raw,

        (
            SELECT COUNT(*)
            FROM DB_CURSO.STAGING.VENTAS_CLASIFICADAS
        ) AS filas_clasificadas,

        (
            SELECT COUNT(*)
            FROM DB_CURSO.CURATED.VENTAS_LIMPIAS
        ) AS filas_validas,

        (
            SELECT COUNT(*)
            FROM DB_CURSO.STAGING.VENTAS_RECHAZADAS
        ) AS filas_rechazadas
)

SELECT
    *,
    filas_raw - filas_validas - filas_rechazadas
        AS diferencia
FROM control;
```

Resultado:

| FILAS_RAW | FILAS_CLASIFICADAS | FILAS_VALIDAS | FILAS_RECHAZADAS | DIFERENCIA |
|---:|---:|---:|---:|---:|
| 16 | 16 | 11 | 5 | 0 |

### Interpretación

La diferencia cero confirma que ninguna fila se ha perdido:

```text
RAW = VÁLIDAS + RECHAZADAS
```

---

## 12. Validar la calidad de CURATED

### 12.1 Controles obligatorios

```sql
SELECT
    COUNT_IF(id_venta IS NULL) AS ids_venta_nulos,

    COUNT_IF(fecha IS NULL) AS fechas_nulas,

    COUNT_IF(id_cliente IS NULL) AS clientes_nulos,

    COUNT_IF(
        importe IS NULL OR importe <= 0
    ) AS importes_invalidos,

    COUNT_IF(
        moneda NOT IN ('EUR', 'USD', 'GBP')
    ) AS monedas_invalidas,

    COUNT_IF(
        estado NOT IN (
            'COMPLETADA',
            'PENDIENTE',
            'CANCELADA'
        )
    ) AS estados_invalidos,

    COUNT_IF(
        canal IS NULL OR TRIM(canal) = ''
    ) AS canales_vacios

FROM DB_CURSO.CURATED.VENTAS_LIMPIAS;
```

Todos los resultados deben ser `0`.

### 12.2 Resultado por moneda

```sql
SELECT
    moneda,
    COUNT(*) AS filas,
    SUM(importe) AS importe_total
FROM DB_CURSO.CURATED.VENTAS_LIMPIAS
GROUP BY moneda
ORDER BY moneda;
```

Resultado esperado:

| MONEDA | FILAS | IMPORTE_TOTAL |
|---|---:|---:|
| EUR | 9 | 1120.14 |
| GBP | 1 | 310.40 |
| USD | 1 | 250.00 |

No debe sumarse indiscriminadamente el total de monedas distintas sin una regla de conversión.

### 12.3 Resultado por estado

```sql
SELECT
    estado,
    COUNT(*) AS filas
FROM DB_CURSO.CURATED.VENTAS_LIMPIAS
GROUP BY estado
ORDER BY estado;
```

Resultado esperado:

| ESTADO | FILAS |
|---|---:|
| CANCELADA | 1 |
| COMPLETADA | 7 |
| PENDIENTE | 3 |

### 12.4 Resultado por canal

```sql
SELECT
    canal,
    COUNT(*) AS filas
FROM DB_CURSO.CURATED.VENTAS_LIMPIAS
GROUP BY canal
ORDER BY canal;
```

Resultado esperado:

| CANAL | FILAS |
|---|---:|
| MARKETPLACE | 2 |
| SIN_CANAL | 2 |
| TIENDA | 3 |
| WEB | 4 |

---

## 13. Analizar los rechazos

```sql
SELECT
    motivo_rechazo,
    COUNT(*) AS filas
FROM DB_CURSO.STAGING.VENTAS_RECHAZADAS
GROUP BY motivo_rechazo
ORDER BY motivo_rechazo;
```

Resultado esperado:

| MOTIVO_RECHAZO | FILAS |
|---|---:|
| FECHA_INVALIDA | 1 |
| ID_CLIENTE_INVALIDO | 1 |
| ID_VENTA_INVALIDO | 1 |
| IMPORTE_INVALIDO | 1 |
| MONEDA_INVALIDA | 1 |

Inspecciona el detalle:

```sql
SELECT
    _file_row_number,
    id_venta_raw,
    fecha_raw,
    id_cliente_raw,
    importe_raw,
    moneda_raw,
    id_venta,
    fecha,
    id_cliente,
    importe,
    moneda,
    motivo_rechazo
FROM DB_CURSO.STAGING.VENTAS_RECHAZADAS
ORDER BY _file_row_number;
```

### Por qué no usar un WHERE silencioso

Una sentencia como:

```sql
WHERE id_venta IS NOT NULL
  AND fecha IS NOT NULL
  AND importe > 0
```

podría producir una tabla aparentemente limpia, pero ocultaría:

- Cuántas filas se descartaron.
- Qué reglas fallaron.
- Qué fichero originó el error.
- Qué debe corregir el sistema de origen.
- Si la reconciliación es completa.

---

## 14. Comparar la view y CTAS

### 14.1 Conteos iniciales

```sql
SELECT
    (
        SELECT COUNT(*)
        FROM DB_CURSO.STAGING.V_VENTAS_NORMALIZADAS
    ) AS filas_view,

    (
        SELECT COUNT(*)
        FROM DB_CURSO.STAGING.VENTAS_CLASIFICADAS
    ) AS filas_ctas;
```

Resultado:

```text
16 y 16
```

### 14.2 Insertar una fila de prueba

```sql
INSERT INTO DB_CURSO.STAGING.VENTAS_RAW_ELT
VALUES (
    '5012',
    '2026-03-07',
    '712',
    'WEB',
    '75,00',
    'EUR',
    'COMPLETADA',
    '2026-03-07 12:00:00',
    'ventas_marzo_lote_02.csv',
    1,
    CURRENT_TIMESTAMP()
);
```

### 14.3 Volver a comparar

```sql
SELECT
    (
        SELECT COUNT(*)
        FROM DB_CURSO.STAGING.V_VENTAS_NORMALIZADAS
    ) AS filas_view,

    (
        SELECT COUNT(*)
        FROM DB_CURSO.STAGING.VENTAS_CLASIFICADAS
    ) AS filas_ctas;
```

Resultado esperado:

| FILAS_VIEW | FILAS_CTAS |
|---:|---:|
| 17 | 16 |

### Explicación

La view no almacena el resultado. Ejecuta su consulta cuando se utiliza y ve el estado actual de RAW.

La tabla CTAS contiene el resultado materializado en el momento en que se creó. No cambia hasta que:

- Se inserten datos explícitamente.
- Se actualice.
- Se reconstruya con otro CTAS.

### 14.4 Retirar la fila de prueba

```sql
DELETE FROM DB_CURSO.STAGING.VENTAS_RAW_ELT
WHERE id_venta_raw = '5012'
  AND _source_file = 'ventas_marzo_lote_02.csv';
```

Comprueba:

```sql
SELECT COUNT(*)
FROM DB_CURSO.STAGING.V_VENTAS_NORMALIZADAS;
```

Resultado:

```text
16
```

---

## 15. Reejecución reproducible

Con la misma tabla RAW, vuelve a ejecutar:

```sql
CREATE OR REPLACE TRANSIENT TABLE
    DB_CURSO.STAGING.VENTAS_CLASIFICADAS
COPY GRANTS
AS
SELECT *
FROM DB_CURSO.STAGING.V_VENTAS_NORMALIZADAS;
```

Después reconstruye:

```sql
CREATE OR REPLACE TABLE DB_CURSO.CURATED.VENTAS_LIMPIAS
COPY GRANTS
AS
SELECT
    id_venta,
    fecha,
    id_cliente,
    canal,
    importe,
    moneda,
    estado,
    fecha_modificacion,
    _source_file,
    _file_row_number,
    _loaded_at,
    _transformed_at
FROM DB_CURSO.STAGING.VENTAS_CLASIFICADAS
WHERE motivo_rechazo IS NULL;
```

Y:

```sql
CREATE OR REPLACE TRANSIENT TABLE
    DB_CURSO.STAGING.VENTAS_RECHAZADAS
COPY GRANTS
AS
SELECT *
FROM DB_CURSO.STAGING.VENTAS_CLASIFICADAS
WHERE motivo_rechazo IS NOT NULL;
```

Los conteos deben volver a ser:

```text
16 RAW
11 válidas
5 rechazadas
```

Esto representa una reconstrucción completa reproducible.

> `CREATE OR REPLACE` reemplaza el objeto. En procesos posteriores con streams u otros objetos dependientes, debe utilizarse con cuidado porque recrear una tabla elimina su historial y puede invalidar streams.

---

## 16. Consultar las operaciones del ejercicio

```sql
SELECT
    query_id,
    query_text,
    start_time,
    total_elapsed_time,
    rows_produced,
    execution_status
FROM TABLE(
    INFORMATION_SCHEMA.QUERY_HISTORY_BY_SESSION(
        RESULT_LIMIT => 100
    )
)
WHERE query_tag = 'M06_E01_RAW_A_CURATED'
ORDER BY start_time;
```

---

## 17. Limpieza opcional

No limpies los objetos si se van a reutilizar en los siguientes ejercicios del módulo.

```sql
DROP TABLE IF EXISTS DB_CURSO.STAGING.VENTAS_RECHAZADAS;
DROP TABLE IF EXISTS DB_CURSO.CURATED.VENTAS_LIMPIAS;
DROP TABLE IF EXISTS DB_CURSO.STAGING.VENTAS_CLASIFICADAS;
DROP VIEW IF EXISTS DB_CURSO.STAGING.V_VENTAS_NORMALIZADAS;
DROP TABLE IF EXISTS DB_CURSO.STAGING.VENTAS_RAW_ELT;

ALTER SESSION UNSET QUERY_TAG;
```

No elimines `DB_CURSO`, sus esquemas ni `WH_DEV`.

---

## 18. Errores frecuentes

### TRY_TO_DECIMAL devuelve valores sin decimales

Comprueba que has indicado precisión y escala:

```sql
TRY_TO_DECIMAL(
    REPLACE(importe_txt, ',', '.'),
    12,
    2
)
```

Si no se especifica la escala, el valor predeterminado es cero.

---

### Las fechas DD/MM/YYYY aparecen como NULL

Comprueba el segundo intento:

```sql
TRY_TO_DATE(fecha_txt, 'DD/MM/YYYY')
```

y el uso de `COALESCE`.

---

### La fila con importe negativo no es NULL

Es correcto. `-15,00` puede convertirse técnicamente.

Debe rechazarse mediante:

```sql
importe <= 0
```

---

### SIN_CANAL no aparece

Utiliza:

```sql
COALESCE(
    NULLIF(UPPER(TRIM(canal_raw)), ''),
    'SIN_CANAL'
)
```

Esto cubre cadenas vacías y SQL `NULL`.

---

### El conteo de rechazados no es cinco

Revisa el orden del `CASE`. Cada fila recibe el primer motivo aplicable.

Comprueba directamente:

```sql
SELECT
    _file_row_number,
    motivo_rechazo
FROM DB_CURSO.STAGING.V_VENTAS_NORMALIZADAS
WHERE motivo_rechazo IS NOT NULL
ORDER BY _file_row_number;
```

---

### La tabla CTAS cambia al insertar en RAW

No debería hacerlo. Asegúrate de que consultas:

```text
VENTAS_CLASIFICADAS
```

y no la view:

```text
V_VENTAS_NORMALIZADAS
```

---

## 19. Respuestas a las preguntas de reflexión

### 1. ¿Por qué conservar VARCHAR en RAW?

Porque permite almacenar fielmente la fuente, incluso cuando un valor no puede convertirse. La calidad se aplica después y puede repetirse.

### 2. ¿Ventaja de TRY_TO_DECIMAL?

Devuelve `NULL` cuando no puede convertir, en lugar de detener toda la transformación.

### 3. ¿Conversión correcta equivale a dato válido?

No. Un importe negativo se convierte correctamente, pero puede incumplir una regla de negocio.

### 4. ¿Por qué importa el orden del CASE?

Una fila puede tener varios problemas. El primer `WHEN` verdadero determina el motivo asignado.

### 5. ¿View frente a CTAS?

La view guarda lógica y se evalúa al consultar. CTAS guarda el resultado obtenido en un momento concreto.

### 6. ¿Por qué reconciliar rechazos?

Porque forman parte del lote recibido. Ignorarlos haría imposible demostrar que todas las filas tienen un destino conocido.

### 7. ¿Qué trazabilidad conservar?

Como mínimo:

- Fichero.
- Número de fila.
- Momento de carga.
- Momento de transformación.
- Lote o ejecución.
- Regla de rechazo.
- Identificador de consulta o proceso.

### 8. ¿Completo o incremental?

Las tablas pequeñas o medianas pueden reconstruirse con CTAS. Las tablas grandes suelen requerir deduplicación y `MERGE`, que se estudiarán en el siguiente ejercicio.

---
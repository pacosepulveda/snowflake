# Módulo 6 · Ejercicio 2

## Solución guiada: deduplicación y carga incremental determinista con `MERGE`

---

## 1. Flujo del laboratorio

```text
STAGING.VENTAS_DELTA
        │
        ├── MERGE directo
        │      └── Error o duplicados
        │
        └── ROW_NUMBER + QUALIFY
                ↓
        V_VENTAS_DELTA_DEDUP
                ↓
              MERGE
                ↓
        CURATED.VENTAS_INCREMENTALES
```

El principio fundamental es:

> La fuente de un `MERGE` debe contener como máximo una fila aplicable por clave de negocio.

---

## 2. Preparar Workspaces y el contexto

En **Workspaces**, crea:

```text
M6_E02_MERGE_INCREMENTAL.sql
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

ALTER SESSION SET QUERY_TAG = 'M06_E02_MERGE_INCREMENTAL';

ALTER SESSION SET ERROR_ON_NONDETERMINISTIC_MERGE = TRUE;
```

Comprueba el parámetro:

```sql
SHOW PARAMETERS LIKE 'ERROR_ON_NONDETERMINISTIC_MERGE'
IN SESSION;
```

El valor debe ser:

```text
TRUE
```

También puedes comprobar el contexto:

```sql
SELECT
    CURRENT_ROLE()      AS rol,
    CURRENT_WAREHOUSE() AS warehouse,
    CURRENT_DATABASE()  AS base_datos,
    CURRENT_SCHEMA()    AS esquema;
```

### Por qué fijamos explícitamente el parámetro

`TRUE` es el valor predeterminado actual, pero declararlo en el script:

- Documenta la intención.
- Evita depender de una configuración heredada.
- Convierte una ambigüedad en un error visible.
- Impide que Snowflake elija una fila fuente indefinida.

---

## 3. Crear el destino inicial

```sql
CREATE OR REPLACE TABLE DB_CURSO.CURATED.VENTAS_INCREMENTALES (
    id_venta             NUMBER(18,0),
    id_cliente           NUMBER(18,0),
    fecha                DATE,
    importe              NUMBER(12,2),
    moneda               VARCHAR(3),
    estado               VARCHAR(20),
    fecha_modificacion   TIMESTAMP_NTZ,
    _source_file         VARCHAR,
    _file_row_number     NUMBER,
    _loaded_at           TIMESTAMP_LTZ,
    _merged_at           TIMESTAMP_LTZ
);
```

Inserta el estado inicial:

```sql
INSERT INTO DB_CURSO.CURATED.VENTAS_INCREMENTALES
SELECT
    column1::NUMBER(18,0),
    column2::NUMBER(18,0),
    column3::DATE,
    column4::NUMBER(12,2),
    column5::VARCHAR(3),
    column6::VARCHAR(20),
    column7::TIMESTAMP_NTZ,
    column8::VARCHAR,
    column9::NUMBER,
    column10::TIMESTAMP_LTZ,
    CURRENT_TIMESTAMP()
FROM VALUES
    (6001, 801, '2026-04-01', 100.00, 'EUR', 'COMPLETADA',
     '2026-04-01 10:00:00', 'ventas_base.csv', 1,
     '2026-04-01 10:05:00 +02:00'),

    (6002, 802, '2026-04-01', 200.00, 'EUR', 'PENDIENTE',
     '2026-04-01 11:00:00', 'ventas_base.csv', 2,
     '2026-04-01 11:05:00 +02:00'),

    (6003, 803, '2026-04-02', 150.00, 'EUR', 'COMPLETADA',
     '2026-04-02 09:00:00', 'ventas_base.csv', 3,
     '2026-04-02 09:05:00 +02:00'),

    (6004, 804, '2026-04-02', 80.00, 'EUR', 'PENDIENTE',
     '2026-04-02 12:00:00', 'ventas_base.csv', 4,
     '2026-04-02 12:05:00 +02:00'),

    (6005, 805, '2026-04-03', 300.00, 'EUR', 'COMPLETADA',
     '2026-04-03 14:00:00', 'ventas_base.csv', 5,
     '2026-04-03 14:05:00 +02:00'),

    (6006, 806, '2026-04-03', 50.00, 'EUR', 'CANCELADA',
     '2026-04-03 15:00:00', 'ventas_base.csv', 6,
     '2026-04-03 15:05:00 +02:00');
```

Comprueba:

```sql
SELECT
    COUNT(*) AS filas,
    SUM(importe) AS importe_total
FROM DB_CURSO.CURATED.VENTAS_INCREMENTALES;
```

Resultado:

| FILAS | IMPORTE_TOTAL |
|---:|---:|
| 6 | 880.00 |

---

## 4. Crear el lote delta

```sql
CREATE OR REPLACE TRANSIENT TABLE DB_CURSO.STAGING.VENTAS_DELTA (
    id_venta             NUMBER(18,0),
    id_cliente           NUMBER(18,0),
    fecha                DATE,
    importe              NUMBER(12,2),
    moneda               VARCHAR(3),
    estado               VARCHAR(20),
    fecha_modificacion   TIMESTAMP_NTZ,
    _source_file         VARCHAR,
    _file_row_number     NUMBER,
    _loaded_at           TIMESTAMP_LTZ
);
```

Inserta las nueve versiones:

```sql
INSERT INTO DB_CURSO.STAGING.VENTAS_DELTA
SELECT
    column1::NUMBER(18,0),
    column2::NUMBER(18,0),
    column3::DATE,
    column4::NUMBER(12,2),
    column5::VARCHAR(3),
    column6::VARCHAR(20),
    column7::TIMESTAMP_NTZ,
    column8::VARCHAR,
    column9::NUMBER,
    column10::TIMESTAMP_LTZ
FROM VALUES
    -- Dos actualizaciones de 6002: gana la segunda.
    (6002, 802, '2026-04-01', 210.00, 'EUR', 'PENDIENTE',
     '2026-04-04 09:00:00', 'ventas_delta_01.csv', 1,
     '2026-04-04 09:05:00 +02:00'),

    (6002, 802, '2026-04-01', 220.00, 'EUR', 'COMPLETADA',
     '2026-04-04 12:00:00', 'ventas_delta_01.csv', 2,
     '2026-04-04 12:05:00 +02:00'),

    -- Versión antigua de 6003: no debe sobrescribir el destino.
    (6003, 803, '2026-04-02', 140.00, 'EUR', 'PENDIENTE',
     '2026-04-01 08:00:00', 'ventas_delta_01.csv', 3,
     '2026-04-04 12:06:00 +02:00'),

    -- Actualización válida de 6004.
    (6004, 804, '2026-04-02', 90.00, 'EUR', 'COMPLETADA',
     '2026-04-04 13:00:00', 'ventas_delta_01.csv', 4,
     '2026-04-04 13:05:00 +02:00'),

    -- Empate de fecha de negocio para 6005.
    -- Gana la fila cargada más tarde.
    (6005, 805, '2026-04-03', 310.00, 'EUR', 'COMPLETADA',
     '2026-04-04 14:00:00', 'ventas_delta_01.csv', 5,
     '2026-04-04 14:05:00 +02:00'),

    (6005, 805, '2026-04-03', 315.00, 'EUR', 'COMPLETADA',
     '2026-04-04 14:00:00', 'ventas_delta_02.csv', 1,
     '2026-04-04 14:06:00 +02:00'),

    -- Dos versiones de una clave nueva.
    (6007, 807, '2026-04-04', 75.00, 'EUR', 'PENDIENTE',
     '2026-04-04 10:00:00', 'ventas_delta_01.csv', 6,
     '2026-04-04 10:05:00 +02:00'),

    (6007, 807, '2026-04-04', 80.00, 'EUR', 'COMPLETADA',
     '2026-04-04 11:00:00', 'ventas_delta_01.csv', 7,
     '2026-04-04 11:05:00 +02:00'),

    -- Otra clave nueva.
    (6008, 808, '2026-04-04', 125.00, 'EUR', 'COMPLETADA',
     '2026-04-04 16:00:00', 'ventas_delta_01.csv', 8,
     '2026-04-04 16:05:00 +02:00');
```

Comprueba:

```sql
SELECT
    COUNT(*) AS filas_fisicas,
    COUNT(DISTINCT id_venta) AS claves,
    COUNT(*) - COUNT(DISTINCT id_venta) AS excedentes
FROM DB_CURSO.STAGING.VENTAS_DELTA;
```

Resultado:

| FILAS_FISICAS | CLAVES | EXCEDENTES |
|---:|---:|---:|
| 9 | 6 | 3 |

---

## 5. Analizar los duplicados

```sql
SELECT
    id_venta,
    COUNT(*) AS versiones,
    MIN(fecha_modificacion) AS primera_version,
    MAX(fecha_modificacion) AS ultima_version,
    MIN(_loaded_at) AS primera_carga,
    MAX(_loaded_at) AS ultima_carga,
    LISTAGG(
        importe::VARCHAR,
        ', '
    ) WITHIN GROUP (
        ORDER BY fecha_modificacion, _loaded_at
    ) AS importes
FROM DB_CURSO.STAGING.VENTAS_DELTA
GROUP BY id_venta
HAVING COUNT(*) > 1
ORDER BY id_venta;
```

Deben aparecer:

```text
6002
6005
6007
```

### Por qué DISTINCT no basta

Las dos versiones de `6002`, por ejemplo, tienen:

- Distinto importe.
- Distinto estado.
- Distinta fecha de modificación.

Por tanto:

```sql
SELECT DISTINCT *
```

conservaría ambas filas.

Deduplicar por clave de negocio significa decidir **qué versión representa el estado correcto**, no eliminar filas completamente idénticas.

---

## 6. Probar un MERGE no deduplicado

Crea una copia materializada del destino:

```sql
CREATE OR REPLACE TRANSIENT TABLE
    DB_CURSO.STAGING.VENTAS_MERGE_PRUEBA
AS
SELECT *
FROM DB_CURSO.CURATED.VENTAS_INCREMENTALES;
```

Ejecuta deliberadamente:

```sql
MERGE INTO DB_CURSO.STAGING.VENTAS_MERGE_PRUEBA AS destino

USING DB_CURSO.STAGING.VENTAS_DELTA AS origen

ON destino.id_venta = origen.id_venta

WHEN MATCHED THEN
    UPDATE SET
        destino.id_cliente = origen.id_cliente,
        destino.fecha = origen.fecha,
        destino.importe = origen.importe,
        destino.moneda = origen.moneda,
        destino.estado = origen.estado,
        destino.fecha_modificacion = origen.fecha_modificacion,
        destino._source_file = origen._source_file,
        destino._file_row_number = origen._file_row_number,
        destino._loaded_at = origen._loaded_at,
        destino._merged_at = CURRENT_TIMESTAMP()

WHEN NOT MATCHED THEN
    INSERT (
        id_venta,
        id_cliente,
        fecha,
        importe,
        moneda,
        estado,
        fecha_modificacion,
        _source_file,
        _file_row_number,
        _loaded_at,
        _merged_at
    )
    VALUES (
        origen.id_venta,
        origen.id_cliente,
        origen.fecha,
        origen.importe,
        origen.moneda,
        origen.estado,
        origen.fecha_modificacion,
        origen._source_file,
        origen._file_row_number,
        origen._loaded_at,
        CURRENT_TIMESTAMP()
    );
```

### Resultado esperado

La sentencia falla porque varias filas de origen para `6002` y `6005` coinciden con una única fila del destino.

Con:

```text
ERROR_ON_NONDETERMINISTIC_MERGE = TRUE
```

Snowflake no elige arbitrariamente qué versión debe actualizar la fila.

Comprueba que no hubo una modificación parcial:

```sql
SELECT
    COUNT(*) AS filas,
    SUM(importe) AS importe_total
FROM DB_CURSO.STAGING.VENTAS_MERGE_PRUEBA;
```

Debe seguir mostrando:

```text
6 filas
880.00
```

`MERGE` es una única sentencia. Si falla, no deja aplicadas algunas de sus actualizaciones.

---

## 7. Demostrar los duplicados en una clave nueva

Crea una tabla vacía:

```sql
CREATE OR REPLACE TRANSIENT TABLE
    DB_CURSO.STAGING.VENTAS_INSERT_DUP_PRUEBA

LIKE DB_CURSO.CURATED.VENTAS_INCREMENTALES;
```

Ejecuta:

```sql
MERGE INTO DB_CURSO.STAGING.VENTAS_INSERT_DUP_PRUEBA AS destino

USING (
    SELECT *
    FROM DB_CURSO.STAGING.VENTAS_DELTA
    WHERE id_venta = 6007
) AS origen

ON destino.id_venta = origen.id_venta

WHEN NOT MATCHED THEN
    INSERT (
        id_venta,
        id_cliente,
        fecha,
        importe,
        moneda,
        estado,
        fecha_modificacion,
        _source_file,
        _file_row_number,
        _loaded_at,
        _merged_at
    )
    VALUES (
        origen.id_venta,
        origen.id_cliente,
        origen.fecha,
        origen.importe,
        origen.moneda,
        origen.estado,
        origen.fecha_modificacion,
        origen._source_file,
        origen._file_row_number,
        origen._loaded_at,
        CURRENT_TIMESTAMP()
    );
```

Comprueba:

```sql
SELECT *
FROM DB_CURSO.STAGING.VENTAS_INSERT_DUP_PRUEBA
ORDER BY fecha_modificacion;
```

Y:

```sql
SELECT
    id_venta,
    COUNT(*) AS filas
FROM DB_CURSO.STAGING.VENTAS_INSERT_DUP_PRUEBA
GROUP BY id_venta;
```

Resultado:

| ID_VENTA | FILAS |
|---:|---:|
| 6007 | 2 |

### Por qué no falla

No existe una fila destino con `6007`.

Cada una de las dos filas de origen satisface:

```text
WHEN NOT MATCHED
```

Por ello, ambas se insertan.

El parámetro de `MERGE` no determinista protege principalmente los casos ambiguos de `UPDATE` o `DELETE`. No convierte automáticamente la fuente en única.

Elimina la tabla:

```sql
DROP TABLE DB_CURSO.STAGING.VENTAS_INSERT_DUP_PRUEBA;
```

---

## 8. Crear la view deduplicada

```sql
CREATE OR REPLACE VIEW
    DB_CURSO.STAGING.V_VENTAS_DELTA_DEDUP
AS
SELECT *
FROM DB_CURSO.STAGING.VENTAS_DELTA

QUALIFY ROW_NUMBER() OVER (
    PARTITION BY id_venta
    ORDER BY
        fecha_modificacion DESC,
        _loaded_at DESC,
        _file_row_number DESC,
        _source_file DESC
) = 1;
```

### Cómo funciona

```sql
PARTITION BY id_venta
```

Crea un grupo de versiones por venta.

```sql
ORDER BY fecha_modificacion DESC
```

Sitúa primero la versión de negocio más reciente.

Los criterios restantes resuelven los empates:

```sql
_loaded_at DESC
_file_row_number DESC
_source_file DESC
```

```sql
ROW_NUMBER() = 1
```

conserva una única versión por clave.

`QUALIFY` filtra después de calcular la función de ventana y evita envolver la consulta en otro subquery.

Comprueba:

```sql
SELECT COUNT(*) AS filas_deduplicadas
FROM DB_CURSO.STAGING.V_VENTAS_DELTA_DEDUP;
```

Resultado:

```text
6
```

Comprueba las ganadoras:

```sql
SELECT
    id_venta,
    importe,
    estado,
    fecha_modificacion,
    _source_file,
    _file_row_number,
    _loaded_at
FROM DB_CURSO.STAGING.V_VENTAS_DELTA_DEDUP
WHERE id_venta IN (6002, 6005, 6007)
ORDER BY id_venta;
```

Resultado esperado:

| ID_VENTA | IMPORTE | ESTADO |
|---:|---:|---|
| 6002 | 220.00 | COMPLETADA |
| 6005 | 315.00 | COMPLETADA |
| 6007 | 80.00 | COMPLETADA |

---

## 9. Clasificar las operaciones

Antes de cambiar el destino, ejecuta:

```sql
SELECT
    origen.id_venta,
    destino.fecha_modificacion AS version_destino,
    origen.fecha_modificacion AS version_origen,

    CASE
        WHEN destino.id_venta IS NULL
            THEN 'INSERTAR'

        WHEN origen.fecha_modificacion
             > destino.fecha_modificacion
            THEN 'ACTUALIZAR'

        ELSE 'IGNORAR_VERSION_ANTIGUA_O_IGUAL'
    END AS operacion

FROM DB_CURSO.STAGING.V_VENTAS_DELTA_DEDUP AS origen

LEFT JOIN DB_CURSO.CURATED.VENTAS_INCREMENTALES AS destino
    ON destino.id_venta = origen.id_venta

ORDER BY origen.id_venta;
```

Resultado esperado:

| ID | OPERACIÓN |
|---:|---|
| 6002 | ACTUALIZAR |
| 6003 | IGNORAR_VERSION_ANTIGUA_O_IGUAL |
| 6004 | ACTUALIZAR |
| 6005 | ACTUALIZAR |
| 6007 | INSERTAR |
| 6008 | INSERTAR |

Resumen:

```sql
WITH operaciones AS (
    SELECT
        CASE
            WHEN destino.id_venta IS NULL
                THEN 'INSERTAR'

            WHEN origen.fecha_modificacion
                 > destino.fecha_modificacion
                THEN 'ACTUALIZAR'

            ELSE 'IGNORAR_VERSION_ANTIGUA_O_IGUAL'
        END AS operacion

    FROM DB_CURSO.STAGING.V_VENTAS_DELTA_DEDUP AS origen

    LEFT JOIN DB_CURSO.CURATED.VENTAS_INCREMENTALES AS destino
        ON destino.id_venta = origen.id_venta
)

SELECT
    operacion,
    COUNT(*) AS filas
FROM operaciones
GROUP BY operacion
ORDER BY operacion;
```

Debe mostrar:

```text
2 INSERTAR
3 ACTUALIZAR
1 IGNORAR
```

---

## 10. Ejecutar el MERGE determinista

```sql
MERGE INTO DB_CURSO.CURATED.VENTAS_INCREMENTALES AS destino

USING DB_CURSO.STAGING.V_VENTAS_DELTA_DEDUP AS origen

ON destino.id_venta = origen.id_venta

WHEN MATCHED
AND origen.fecha_modificacion > destino.fecha_modificacion
THEN UPDATE SET
    destino.id_cliente = origen.id_cliente,
    destino.fecha = origen.fecha,
    destino.importe = origen.importe,
    destino.moneda = origen.moneda,
    destino.estado = origen.estado,
    destino.fecha_modificacion = origen.fecha_modificacion,
    destino._source_file = origen._source_file,
    destino._file_row_number = origen._file_row_number,
    destino._loaded_at = origen._loaded_at,
    destino._merged_at = CURRENT_TIMESTAMP()

WHEN NOT MATCHED
THEN INSERT (
    id_venta,
    id_cliente,
    fecha,
    importe,
    moneda,
    estado,
    fecha_modificacion,
    _source_file,
    _file_row_number,
    _loaded_at,
    _merged_at
)
VALUES (
    origen.id_venta,
    origen.id_cliente,
    origen.fecha,
    origen.importe,
    origen.moneda,
    origen.estado,
    origen.fecha_modificacion,
    origen._source_file,
    origen._file_row_number,
    origen._loaded_at,
    CURRENT_TIMESTAMP()
);
```

### Resultado esperado

La cuadrícula de resultados de `MERGE` debe indicar:

```text
number of rows inserted = 2
number of rows updated  = 3
number of rows deleted  = 0
```

La fila `6003` coincide por clave, pero no satisface la condición de actualización porque su versión es anterior.

---

## 11. Validar el estado final

### 11.1 Conteo e importe

```sql
SELECT
    COUNT(*) AS filas,
    SUM(importe) AS importe_total
FROM DB_CURSO.CURATED.VENTAS_INCREMENTALES;
```

Resultado:

| FILAS | IMPORTE_TOTAL |
|---:|---:|
| 8 | 1130.00 |

### 11.2 Filas afectadas

```sql
SELECT
    id_venta,
    importe,
    estado,
    fecha_modificacion,
    _source_file,
    _file_row_number
FROM DB_CURSO.CURATED.VENTAS_INCREMENTALES
WHERE id_venta IN (
    6002, 6003, 6004, 6005, 6007, 6008
)
ORDER BY id_venta;
```

Valores esperados:

| ID | IMPORTE | ESTADO |
|---:|---:|---|
| 6002 | 220.00 | COMPLETADA |
| 6003 | 150.00 | COMPLETADA |
| 6004 | 90.00 | COMPLETADA |
| 6005 | 315.00 | COMPLETADA |
| 6007 | 80.00 | COMPLETADA |
| 6008 | 125.00 | COMPLETADA |

Observa que `6003` conserva el estado y el importe del destino.

### 11.3 Control de duplicados

```sql
SELECT
    id_venta,
    COUNT(*) AS filas
FROM DB_CURSO.CURATED.VENTAS_INCREMENTALES
GROUP BY id_venta
HAVING COUNT(*) > 1;
```

No debe devolver filas.

### 11.4 Distribución final

```sql
SELECT
    estado,
    COUNT(*) AS filas,
    SUM(importe) AS importe_total
FROM DB_CURSO.CURATED.VENTAS_INCREMENTALES
GROUP BY estado
ORDER BY estado;
```

Resultado esperado:

| ESTADO | FILAS | IMPORTE_TOTAL |
|---|---:|---:|
| CANCELADA | 1 | 50.00 |
| COMPLETADA | 7 | 1080.00 |

---

## 12. Probar la idempotencia

Ejecuta una segunda vez exactamente el mismo `MERGE`.

Resultado esperado:

```text
0 inserted
0 updated
0 deleted
```

Comprueba:

```sql
SELECT
    COUNT(*) AS filas,
    SUM(importe) AS importe_total,
    COUNT(*) - COUNT(DISTINCT id_venta) AS duplicados
FROM DB_CURSO.CURATED.VENTAS_INCREMENTALES;
```

Resultado:

| FILAS | IMPORTE_TOTAL | DUPLICADOS |
|---:|---:|---:|
| 8 | 1130.00 | 0 |

### Por qué la reejecución es segura

Las claves nuevas ya existen en la segunda ejecución, por lo que dejan de satisfacer:

```text
WHEN NOT MATCHED
```

Las filas actualizadas tienen ahora la misma `fecha_modificacion` que la fuente. Como la condición exige:

```sql
origen.fecha_modificacion > destino.fecha_modificacion
```

no vuelven a actualizarse.

La fila antigua `6003` tampoco se actualiza.

El proceso es idempotente para el mismo contenido del lote.

---

## 13. Construir la reconciliación

### 13.1 Delta físico y deduplicado

```sql
SELECT
    (
        SELECT COUNT(*)
        FROM DB_CURSO.STAGING.VENTAS_DELTA
    ) AS filas_delta,

    (
        SELECT COUNT(DISTINCT id_venta)
        FROM DB_CURSO.STAGING.VENTAS_DELTA
    ) AS claves_delta,

    (
        SELECT COUNT(*)
        FROM DB_CURSO.STAGING.V_VENTAS_DELTA_DEDUP
    ) AS filas_deduplicadas,

    (
        SELECT COUNT(*)
        FROM DB_CURSO.STAGING.VENTAS_DELTA
    )
    -
    (
        SELECT COUNT(*)
        FROM DB_CURSO.STAGING.V_VENTAS_DELTA_DEDUP
    ) AS versiones_descartadas;
```

Resultado:

```text
9 delta
6 claves
6 deduplicadas
3 descartadas
```

### 13.2 Clasificación contra el estado inicial

Después del `MERGE`, el destino ya cambió. Para reconstruir el análisis previo de forma reproducible, usamos las fechas iniciales conocidas mediante una tabla temporal lógica:

```sql
WITH destino_inicial AS (
    SELECT *
    FROM VALUES
        (6001, '2026-04-01 10:00:00'::TIMESTAMP_NTZ),
        (6002, '2026-04-01 11:00:00'::TIMESTAMP_NTZ),
        (6003, '2026-04-02 09:00:00'::TIMESTAMP_NTZ),
        (6004, '2026-04-02 12:00:00'::TIMESTAMP_NTZ),
        (6005, '2026-04-03 14:00:00'::TIMESTAMP_NTZ),
        (6006, '2026-04-03 15:00:00'::TIMESTAMP_NTZ)
    AS t(id_venta, fecha_modificacion)
),

operaciones AS (
    SELECT
        origen.id_venta,

        CASE
            WHEN destino.id_venta IS NULL
                THEN 'INSERTAR'

            WHEN origen.fecha_modificacion
                 > destino.fecha_modificacion
                THEN 'ACTUALIZAR'

            ELSE 'IGNORAR_VERSION_ANTIGUA_O_IGUAL'
        END AS operacion

    FROM DB_CURSO.STAGING.V_VENTAS_DELTA_DEDUP origen

    LEFT JOIN destino_inicial destino
        ON destino.id_venta = origen.id_venta
)

SELECT
    operacion,
    COUNT(*) AS filas
FROM operaciones
GROUP BY operacion
ORDER BY operacion;
```

Resultado:

```text
2 insertar
3 actualizar
1 ignorar
```

### 13.3 Ecuación de filas

```text
9 filas físicas
- 3 versiones descartadas
= 6 claves procesables

6 claves procesables
= 2 nuevas
+ 3 actualizaciones
+ 1 versión ignorada

6 filas iniciales
+ 2 nuevas
= 8 filas finales
```

Las actualizaciones y la versión ignorada no cambian el número de filas del destino.

---

## 14. Qué ocurriría con ERROR_ON_NONDETERMINISTIC_MERGE = FALSE

No lo configures así en un proceso real:

```sql
ALTER SESSION SET ERROR_ON_NONDETERMINISTIC_MERGE = FALSE;
```

Cuando varias filas de origen intentan actualizar la misma fila destino, Snowflake puede elegir una de ellas, pero la fila seleccionada no está definida.

El proceso podría:

- Terminar sin error.
- Producir un resultado distinto entre ejecuciones.
- Elegir una versión antigua.
- Romper la auditabilidad.
- Ocultar que la fuente incumple su contrato de unicidad.

La solución correcta no es permitir el no determinismo, sino deduplicar la fuente.

---

## 15. Extensión: eliminaciones lógicas

Un lote real podría incluir:

```text
operacion = DELETE
```

El `MERGE` podría incorporar una cláusula antes del `UPDATE`:

```sql
WHEN MATCHED
AND origen.operacion = 'DELETE'
AND origen.fecha_modificacion > destino.fecha_modificacion
THEN DELETE
```

El orden de las cláusulas importa. Una cláusula `WHEN MATCHED` sin predicado debe ser la última de su tipo; de lo contrario, las cláusulas posteriores serían inalcanzables.

En muchos modelos analíticos se prefiere una eliminación lógica:

```text
estado = 'ELIMINADA'
```

para conservar trazabilidad histórica.

---

## 16. Consultar las operaciones del ejercicio

```sql
SELECT
    query_id,
    query_text,
    start_time,
    total_elapsed_time,
    rows_produced,
    execution_status,
    error_message
FROM TABLE(
    INFORMATION_SCHEMA.QUERY_HISTORY_BY_SESSION(
        RESULT_LIMIT => 100
    )
)
WHERE query_tag = 'M06_E02_MERGE_INCREMENTAL'
ORDER BY start_time;
```

La consulta permite localizar:

- El `MERGE` erróneo.
- El `MERGE` que insertó duplicados nuevos.
- La primera ejecución correcta.
- La segunda ejecución idempotente.

---

## 17. Limpieza opcional

No elimines los objetos si el siguiente ejercicio va a utilizar la tabla final.

```sql
DROP TABLE IF EXISTS DB_CURSO.STAGING.VENTAS_MERGE_PRUEBA;
DROP VIEW IF EXISTS DB_CURSO.STAGING.V_VENTAS_DELTA_DEDUP;
DROP TABLE IF EXISTS DB_CURSO.STAGING.VENTAS_DELTA;
DROP TABLE IF EXISTS DB_CURSO.CURATED.VENTAS_INCREMENTALES;

ALTER SESSION UNSET QUERY_TAG;
ALTER SESSION UNSET ERROR_ON_NONDETERMINISTIC_MERGE;
```

---

## 18. Errores frecuentes

### El MERGE directo no falla

Comprueba:

```sql
SHOW PARAMETERS LIKE 'ERROR_ON_NONDETERMINISTIC_MERGE'
IN SESSION;
```

Debe ser `TRUE`.

También verifica que la tabla de prueba contiene `6002` y `6005`, y que el delta contiene dos filas para cada una.

---

### La view deduplicada tiene más de seis filas

Revisa:

```sql
PARTITION BY id_venta
```

y:

```sql
QUALIFY ROW_NUMBER() ... = 1
```

No particiones por todas las columnas.

---

### Gana 310.00 para 6005

La fecha de modificación está empatada. El siguiente criterio debe ser:

```sql
_loaded_at DESC
```

La fila de `315.00` tiene una hora de carga posterior.

---

### La segunda ejecución vuelve a actualizar filas

Comprueba que la cláusula incluye:

```sql
AND origen.fecha_modificacion
    > destino.fecha_modificacion
```

Sin esta condición, todas las coincidencias se actualizarían otra vez, incluso con la misma versión.

---

### 6003 cambia a 140.00

La condición de versión falta o está invertida.

La versión de origen:

```text
2026-04-01 08:00:00
```

es anterior a la del destino:

```text
2026-04-02 09:00:00
```

---

### Aparecen dos filas de 6007

El `MERGE` correcto está utilizando `VENTAS_DELTA` en lugar de:

```text
V_VENTAS_DELTA_DEDUP
```

---

## 19. Respuestas a las preguntas de reflexión

### 1. ¿Por qué DISTINCT no basta?

Porque elimina filas idénticas. Dos versiones de una venta suelen diferir en estado, importe o fecha y ambas sobreviven.

### 2. ¿Por qué resolver todos los empates?

Si dos filas quedan empatadas en todos los criterios del `ORDER BY`, cuál recibe `ROW_NUMBER = 1` puede no ser reproducible. Debe existir un último criterio estable.

### 3. ¿Por qué se insertan dos claves nuevas?

Ambas filas son `NOT MATCHED` frente al destino y cada una ejecuta la cláusula de inserción.

### 4. ¿Clave frente a versión?

La clave identifica la entidad. La fecha de versión decide qué estado de esa entidad es más reciente.

### 5. ¿Por qué condicionar el UPDATE?

Para impedir que una entrega tardía sobrescriba una versión más nueva.

### 6. ¿Riesgo de desactivar el error?

Snowflake elige una fuente no definida y el resultado deja de ser determinista y auditable.

### 7. ¿Por qué clasificar antes?

Permite anticipar el impacto, reconciliar el lote y detectar anomalías antes de modificar el destino.

### 8. ¿Qué cambiaría con eliminaciones?

Se añadiría una cláusula `WHEN MATCHED ... THEN DELETE` o una actualización a estado eliminado, siempre respetando el orden de versión.

---


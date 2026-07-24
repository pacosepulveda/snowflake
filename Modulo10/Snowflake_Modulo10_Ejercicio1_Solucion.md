# Módulo 10 · Ejercicio 1

## Solución guiada: recuperación con Time Travel y UNDROP

> **Compatibilidad:** cuenta trial Standard o Enterprise

---

## 1. Estrategia de recuperación

Utilizaremos un mecanismo diferente según el incidente:

```text
UPDATE incorrecto
    → BEFORE (STATEMENT)
    → clone histórico
    → INSERT OVERWRITE

DELETE parcial
    → BEFORE (STATEMENT)
    → insertar solo filas ausentes

DROP TABLE
    → liberar el nombre
    → UNDROP TABLE

Fuera de Time Travel
    → Fail-safe, backup o disaster recovery
```

---

# Parte 1. Preparar el laboratorio

## 2. Crear el warehouse y el contexto

```sql
USE ROLE SYSADMIN;

CREATE WAREHOUSE IF NOT EXISTS WH_M10_RECOVERY
    WAREHOUSE_SIZE = XSMALL
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE;

USE WAREHOUSE WH_M10_RECOVERY;

ALTER SESSION SET QUERY_TAG = 'M10_E01_PREPARACION';
```

---

## 3. Crear la base de datos y los esquemas

Se utiliza un día de retención para garantizar la compatibilidad con cuentas Standard y Enterprise.

```sql
CREATE DATABASE IF NOT EXISTS DB_M10_RECOVERY
    DATA_RETENTION_TIME_IN_DAYS = 1
    COMMENT = 'Laboratorio de Time Travel y UNDROP';

ALTER DATABASE DB_M10_RECOVERY
    SET DATA_RETENTION_TIME_IN_DAYS = 1;

CREATE SCHEMA IF NOT EXISTS DB_M10_RECOVERY.OPERACIONES
    DATA_RETENTION_TIME_IN_DAYS = 1;

CREATE SCHEMA IF NOT EXISTS DB_M10_RECOVERY.RECOVERY
    DATA_RETENTION_TIME_IN_DAYS = 1;

USE DATABASE DB_M10_RECOVERY;
USE SCHEMA OPERACIONES;
```

> Una retención superior a un día requiere Enterprise Edition o superior. Como una cuenta trial puede haberse creado con distintas ediciones, el laboratorio no depende de esa característica.

---

## 4. Crear la tabla permanente

```sql
DROP TABLE IF EXISTS DB_M10_RECOVERY.OPERACIONES.PEDIDOS_OPERATIVOS_REEMPLAZO;
DROP TABLE IF EXISTS DB_M10_RECOVERY.RECOVERY.PEDIDOS_PRE_UPDATE;
DROP TABLE IF EXISTS DB_M10_RECOVERY.OPERACIONES.PEDIDOS_OPERATIVOS;

CREATE TABLE DB_M10_RECOVERY.OPERACIONES.PEDIDOS_OPERATIVOS (
    id_pedido       NUMBER(18,0),
    fecha_pedido    DATE,
    importe         NUMBER(12,2),
    estado          VARCHAR(20),
    actualizado_en  TIMESTAMP_LTZ
)
DATA_RETENTION_TIME_IN_DAYS = 1
COMMENT = 'Estado operativo de los pedidos';
```

Inserta ocho pedidos:

```sql
INSERT INTO DB_M10_RECOVERY.OPERACIONES.PEDIDOS_OPERATIVOS
    (id_pedido, fecha_pedido, importe, estado, actualizado_en)
SELECT
    column1::NUMBER,
    column2::DATE,
    column3::NUMBER(12,2),
    column4::VARCHAR,
    column5::TIMESTAMP_LTZ
FROM VALUES
    (10001, '2026-07-01', 120.00, 'COMPLETADA', '2026-07-01 10:00:00 +02:00'),
    (10002, '2026-07-01', 250.00, 'PENDIENTE',  '2026-07-01 10:05:00 +02:00'),
    (10003, '2026-07-02',  80.00, 'COMPLETADA', '2026-07-02 09:00:00 +02:00'),
    (10004, '2026-07-02', 310.00, 'COMPLETADA', '2026-07-02 09:05:00 +02:00'),
    (10005, '2026-07-03', 150.00, 'CANCELADA',  '2026-07-03 11:00:00 +02:00'),
    (10006, '2026-07-03',  95.00, 'PENDIENTE',  '2026-07-03 11:05:00 +02:00'),
    (10007, '2026-07-04', 180.00, 'COMPLETADA', '2026-07-04 12:00:00 +02:00'),
    (10008, '2026-07-04', 220.00, 'PENDIENTE',  '2026-07-04 12:05:00 +02:00');
```

---

## 5. Crear la tabla transitoria

```sql
CREATE OR REPLACE TRANSIENT TABLE
    DB_M10_RECOVERY.OPERACIONES.EVENTOS_REPROCESABLES (
        id_evento    NUMBER,
        descripcion  VARCHAR,
        cargado_en   TIMESTAMP_LTZ
    )
    DATA_RETENTION_TIME_IN_DAYS = 1
    COMMENT = 'Eventos técnicos que pueden reconstruirse';

INSERT INTO DB_M10_RECOVERY.OPERACIONES.EVENTOS_REPROCESABLES
VALUES
    (1, 'Fichero recibido', CURRENT_TIMESTAMP()),
    (2, 'Validación completada', CURRENT_TIMESTAMP());
```

---

## 6. Validar el estado inicial

```sql
SELECT
    COUNT(*) AS pedidos,
    SUM(importe) AS importe_total,
    COUNT_IF(estado = 'COMPLETADA') AS completadas,
    COUNT_IF(estado = 'PENDIENTE') AS pendientes,
    COUNT_IF(estado = 'CANCELADA') AS canceladas
FROM DB_M10_RECOVERY.OPERACIONES.PEDIDOS_OPERATIVOS;
```

Resultado esperado:

| PEDIDOS | IMPORTE_TOTAL | COMPLETADAS | PENDIENTES | CANCELADAS |
|---:|---:|---:|---:|---:|
| 8 | 1405.00 | 4 | 3 | 1 |

---

## 7. Comprobar tipo y retención

```sql
SHOW TABLES IN SCHEMA DB_M10_RECOVERY.OPERACIONES
->>
SELECT
    "name",
    "kind",
    "rows",
    "retention_time",
    "owner"
FROM $1
WHERE "name" IN (
    'PEDIDOS_OPERATIVOS',
    'EVENTOS_REPROCESABLES'
)
ORDER BY "name";
```

Interpretación:

| Tabla | `kind` | Time Travel |
|---|---|---:|---:|
| `PEDIDOS_OPERATIVOS` | `TABLE` | 1 día |
| `EVENTOS_REPROCESABLES` | `TRANSIENT` | 1 día |

La tabla transitoria es adecuada para datos regenerables porque evita el almacenamiento de Fail-safe. No debe utilizarse para el único ejemplar de información crítica.

---

# Parte 2. Recuperar un UPDATE incorrecto

## 8. Registrar un timestamp estable

```sql
SET TS_BASELINE = CURRENT_TIMESTAMP();

SELECT $TS_BASELINE::TIMESTAMP_LTZ AS timestamp_baseline;

CALL SYSTEM$WAIT(6);
```

La espera garantiza que una consulta posterior con un pequeño `OFFSET` no solicite un instante anterior a la creación de la tabla.

Creamos un punto de referencia anterior al UPDATE accidental para hacer esto:

1. Guardar el momento en que los datos están bien
2. Esperar unos segundos
3. Ejecutar el UPDATE accidental
4. Comprobar que los datos se han corrompido
5. Consultar o recuperar la versión anterior con Time Travel

---

## 9. Ejecutar el UPDATE accidental

```sql
ALTER SESSION SET QUERY_TAG = 'M10_E01_INCIDENTE_UPDATE';

UPDATE DB_M10_RECOVERY.OPERACIONES.PEDIDOS_OPERATIVOS
SET
    importe = 0,
    estado = 'CANCELADA',
    actualizado_en = CURRENT_TIMESTAMP()
WHERE fecha_pedido >= '2026-07-03'::DATE;
```

Se actualizan cuatro filas.

Captura inmediatamente el Query ID:

```sql
SET QID_UPDATE = LAST_QUERY_ID();

SELECT $QID_UPDATE AS query_id_update;
```

Comprueba el estado dañado:

```sql
SELECT
    COUNT(*) AS pedidos,
    SUM(importe) AS importe_total,
    COUNT_IF(estado = 'CANCELADA') AS canceladas
FROM DB_M10_RECOVERY.OPERACIONES.PEDIDOS_OPERATIVOS;
```

Resultado:

```text
8 pedidos
760.00
4 canceladas
```

---

## 10. Consultar el estado mediante TIMESTAMP

```sql
SELECT
    COUNT(*) AS pedidos,
    SUM(importe) AS importe_total
FROM DB_M10_RECOVERY.OPERACIONES.PEDIDOS_OPERATIVOS
AT (
    TIMESTAMP => $TS_BASELINE::TIMESTAMP_LTZ
);
```

Resultado:

```text
8
1405.00
```

El cast explícito evita ambigüedades en el tipo de timestamp.

---

## 11. Consultar el estado anterior mediante BEFORE STATEMENT

```sql
SELECT
    COUNT(*) AS pedidos,
    SUM(importe) AS importe_total
FROM DB_M10_RECOVERY.OPERACIONES.PEDIDOS_OPERATIVOS
BEFORE (
    STATEMENT => $QID_UPDATE
);
```

Resultado:

```text
8
1405.00
```

`BEFORE` devuelve el estado inmediatamente anterior a la finalización de la sentencia identificada.

---

## 12. Consultar el estado mediante AT STATEMENT

```sql
SELECT
    COUNT(*) AS pedidos,
    SUM(importe) AS importe_total
FROM DB_M10_RECOVERY.OPERACIONES.PEDIDOS_OPERATIVOS
AT (
    STATEMENT => $QID_UPDATE
);
```

Resultado:

```text
8
760.00
```

Diferencia:

```text
AT (STATEMENT)
    incluye los cambios de la sentencia indicada

BEFORE (STATEMENT)
    consulta el estado inmediatamente anterior
```

---

## 13. Demostrar OFFSET

```sql
SELECT
    COUNT(*) AS pedidos,
    SUM(importe) AS importe_total
FROM DB_M10_RECOVERY.OPERACIONES.PEDIDOS_OPERATIVOS
AT (
    OFFSET => -5
);
```

El resultado puede ser `1405.00` o `760.00`, dependiendo del tiempo empleado por las sentencias anteriores.

Esta variación es precisamente la limitación didáctica de `OFFSET`: se calcula con relación al momento en el que se ejecuta la consulta y no identifica de forma inequívoca la operación causante.

Para una recuperación real son preferibles:

- El Query ID de la sentencia.
- Un timestamp registrado.
- Evidencias del historial de consultas.

---

## 14. Crear un clone del estado anterior

```sql
CREATE OR REPLACE TRANSIENT TABLE
    DB_M10_RECOVERY.RECOVERY.PEDIDOS_PRE_UPDATE
CLONE
    DB_M10_RECOVERY.OPERACIONES.PEDIDOS_OPERATIVOS
BEFORE (
    STATEMENT => $QID_UPDATE
);
```

Comprueba:

```sql
SELECT
    COUNT(*) AS pedidos,
    SUM(importe) AS importe_total
FROM DB_M10_RECOVERY.RECOVERY.PEDIDOS_PRE_UPDATE;
```

Resultado:

```text
8
1405.00
```

El clone es de tipo Zero-Copy: inicialmente comparte las mismas micro-particiones con el origen histórico.

---

## 15. Restaurar con INSERT OVERWRITE

```sql
ALTER SESSION SET QUERY_TAG = 'M10_E01_RECUPERACION_UPDATE';

INSERT OVERWRITE INTO
    DB_M10_RECOVERY.OPERACIONES.PEDIDOS_OPERATIVOS
SELECT *
FROM DB_M10_RECOVERY.RECOVERY.PEDIDOS_PRE_UPDATE;
```

`INSERT OVERWRITE` reemplaza el contenido mediante DML, pero mantiene la identidad, el ownership y los grants de la tabla de destino.

Comprueba:

```sql
SELECT
    COUNT(*) AS pedidos,
    SUM(importe) AS importe_total
FROM DB_M10_RECOVERY.OPERACIONES.PEDIDOS_OPERATIVOS;
```

Resultado:

```text
8
1405.00
```

Comprueba que snapshot y tabla restaurada son iguales:

```sql
SELECT COUNT(*) AS diferencias
FROM (
    SELECT *
    FROM DB_M10_RECOVERY.RECOVERY.PEDIDOS_PRE_UPDATE

    MINUS

    SELECT *
    FROM DB_M10_RECOVERY.OPERACIONES.PEDIDOS_OPERATIVOS
);
```

Resultado:

```text
0
```

---

# Parte 3. Recuperar solo las filas eliminadas

## 16. Ejecutar el DELETE accidental

```sql
ALTER SESSION SET QUERY_TAG = 'M10_E01_INCIDENTE_DELETE';

DELETE FROM DB_M10_RECOVERY.OPERACIONES.PEDIDOS_OPERATIVOS
WHERE estado = 'PENDIENTE';
```

Se eliminan tres filas.

Captura el Query ID:

```sql
SET QID_DELETE = LAST_QUERY_ID();

SELECT $QID_DELETE AS query_id_delete;
```

Comprueba:

```sql
SELECT
    COUNT(*) AS pedidos,
    SUM(importe) AS importe_total
FROM DB_M10_RECOVERY.OPERACIONES.PEDIDOS_OPERATIVOS;
```

Resultado:

```text
5
840.00
```

---

## 17. Insertar únicamente las filas ausentes

```sql
INSERT INTO DB_M10_RECOVERY.OPERACIONES.PEDIDOS_OPERATIVOS
SELECT
    historico.id_pedido,
    historico.fecha_pedido,
    historico.importe,
    historico.estado,
    historico.actualizado_en
FROM DB_M10_RECOVERY.OPERACIONES.PEDIDOS_OPERATIVOS
    BEFORE (STATEMENT => $QID_DELETE) AS historico
LEFT JOIN DB_M10_RECOVERY.OPERACIONES.PEDIDOS_OPERATIVOS AS actual
    ON actual.id_pedido = historico.id_pedido
WHERE actual.id_pedido IS NULL;
```

Se insertan tres filas.

Validación:

```sql
SELECT
    COUNT(*) AS pedidos,
    SUM(importe) AS importe_total,
    COUNT_IF(estado = 'PENDIENTE') AS pendientes
FROM DB_M10_RECOVERY.OPERACIONES.PEDIDOS_OPERATIVOS;
```

Resultado:

```text
8
1405.00
3
```

Comprueba que no existen duplicados:

```sql
SELECT
    id_pedido,
    COUNT(*) AS filas
FROM DB_M10_RECOVERY.OPERACIONES.PEDIDOS_OPERATIVOS
GROUP BY id_pedido
HAVING COUNT(*) > 1;
```

No debe devolver filas.

---

# Parte 4. Recuperar una tabla eliminada

## 18. Eliminar la tabla y ocupar su nombre

```sql
DROP TABLE DB_M10_RECOVERY.OPERACIONES.PEDIDOS_OPERATIVOS;
```

Crea una tabla distinta con el mismo nombre:

```sql
CREATE TABLE DB_M10_RECOVERY.OPERACIONES.PEDIDOS_OPERATIVOS (
    id_pedido   NUMBER,
    comentario VARCHAR
)
DATA_RETENTION_TIME_IN_DAYS = 1;

INSERT INTO DB_M10_RECOVERY.OPERACIONES.PEDIDOS_OPERATIVOS
VALUES (99999, 'Tabla creada después del incidente');
```

Consulta las versiones:

```sql
SHOW TABLES HISTORY
LIKE 'PEDIDOS_OPERATIVOS'
IN SCHEMA DB_M10_RECOVERY.OPERACIONES
->>
SELECT
    "name",
    "kind",
    "created_on",
    "dropped_on",
    "retention_time",
    "rows"
FROM $1
ORDER BY "created_on";
```

---

## 19. Comprobar el conflicto de nombre

Ejecuta deliberadamente:

```sql
UNDROP TABLE DB_M10_RECOVERY.OPERACIONES.PEDIDOS_OPERATIVOS;
```

Snowflake devuelve un error porque ya existe un objeto activo con ese nombre.

Renombra la tabla nueva:

```sql
ALTER TABLE DB_M10_RECOVERY.OPERACIONES.PEDIDOS_OPERATIVOS
RENAME TO PEDIDOS_OPERATIVOS_REEMPLAZO;
```

Recupera la tabla original:

```sql
UNDROP TABLE DB_M10_RECOVERY.OPERACIONES.PEDIDOS_OPERATIVOS;
```

Valida las dos tablas:

```sql
SELECT
    'ORIGINAL' AS objeto,
    COUNT(*) AS filas
FROM DB_M10_RECOVERY.OPERACIONES.PEDIDOS_OPERATIVOS

UNION ALL

SELECT
    'REEMPLAZO',
    COUNT(*)
FROM DB_M10_RECOVERY.OPERACIONES.PEDIDOS_OPERATIVOS_REEMPLAZO;
```

Resultado:

```text
ORIGINAL  = 8
REEMPLAZO = 1
```

Limpia el reemplazo:

```sql
DROP TABLE DB_M10_RECOVERY.OPERACIONES.PEDIDOS_OPERATIVOS_REEMPLAZO;
```

> `UNDROP` recupera la versión eliminada más reciente. Si el ejercicio se repite muchas veces y existen varias versiones con el mismo nombre, consulta el historial antes de restaurar.

---

# Parte 5. Interpretación

## 20. Time Travel frente a Fail-safe

### Tabla permanente

```text
ACTIVE
  → TIME TRAVEL: 1 día
  → FAIL-SAFE: 7 días
  → PURGED
```

### Tabla transitoria

```text
ACTIVE
  → TIME TRAVEL: 1 día
  → PURGED
```

Diferencias:

| Característica | Time Travel | Fail-safe |
|---|---|---|
| Accesible mediante SQL | Sí | No |
| Permite `AT`, `BEFORE`, clone y `UNDROP` | Sí | No |
| Duración configurable | Sí | No, son 7 días |
| Recuperación por el usuario | Sí | No |
| Recuperación por Snowflake Support | No necesaria | Solo como último recurso |
| Disponible en tablas transitorias | Sí, 0 o 1 día | No |

Fail-safe no sustituye a:

- Un backup independiente.
- La replicación a otra cuenta o región.
- Un plan de disaster recovery.
- La conservación de evidencias operativas.

---

## 21. Runbook resumido

| Incidente | Mecanismo | Acción |
|---|---|---|
| `UPDATE` conocido | Time Travel | `BEFORE (STATEMENT)` y clone |
| `DELETE` parcial | Time Travel | Insertar solo filas ausentes |
| `DROP TABLE` | UNDROP | Liberar el nombre y recuperar |
| Fuera de Time Travel | Fail-safe | Abrir un caso con Snowflake |
| Pérdida de la cuenta | Backup o réplica | Recuperar en otra ubicación |

Evidencias recomendadas:

- Query ID.
- Query Tag.
- Usuario y rol.
- Timestamp.
- SQL ejecutado.
- Número de filas afectadas.
- Validación anterior y posterior.

---

# Ampliación opcional

## 22. Recuperar un esquema

```sql
CREATE OR REPLACE SCHEMA DB_M10_RECOVERY.LAB_SCHEMA_DROP
    DATA_RETENTION_TIME_IN_DAYS = 1;

CREATE TABLE DB_M10_RECOVERY.LAB_SCHEMA_DROP.CONFIG_RECUPERACION (
    clave VARCHAR,
    valor VARCHAR
);

INSERT INTO DB_M10_RECOVERY.LAB_SCHEMA_DROP.CONFIG_RECUPERACION
VALUES ('RPO', '0');

DROP SCHEMA DB_M10_RECOVERY.LAB_SCHEMA_DROP CASCADE;

SHOW SCHEMAS HISTORY
LIKE 'LAB_SCHEMA_DROP'
IN DATABASE DB_M10_RECOVERY;

UNDROP SCHEMA DB_M10_RECOVERY.LAB_SCHEMA_DROP;

SELECT *
FROM DB_M10_RECOVERY.LAB_SCHEMA_DROP.CONFIG_RECUPERACION;
```

Al recuperar el esquema se recupera también su tabla hija.

---

## 23. Recuperar una base de datos

```sql
CREATE DATABASE IF NOT EXISTS DB_M10_UNDROP_DEMO
    DATA_RETENTION_TIME_IN_DAYS = 1;

CREATE SCHEMA IF NOT EXISTS DB_M10_UNDROP_DEMO.DATOS;

CREATE OR REPLACE TABLE DB_M10_UNDROP_DEMO.DATOS.MENSAJES (
    id NUMBER,
    mensaje VARCHAR
);

INSERT INTO DB_M10_UNDROP_DEMO.DATOS.MENSAJES
VALUES (1, 'Objeto recuperable');

USE DATABASE DB_M10_RECOVERY;
USE SCHEMA OPERACIONES;

DROP DATABASE DB_M10_UNDROP_DEMO;

SHOW DATABASES HISTORY LIKE 'DB_M10_UNDROP_DEMO';

UNDROP DATABASE DB_M10_UNDROP_DEMO;

SELECT *
FROM DB_M10_UNDROP_DEMO.DATOS.MENSAJES;

DROP DATABASE DB_M10_UNDROP_DEMO;
```

---

## 24. Consultar métricas de almacenamiento

Esta consulta es opcional porque requiere `ACCOUNTADMIN` y las métricas pueden tardar entre una y dos horas en actualizarse.

```sql
USE ROLE ACCOUNTADMIN;

SELECT
    table_catalog,
    table_schema,
    table_name,
    is_transient,
    active_bytes,
    time_travel_bytes,
    failsafe_bytes,
    retained_for_clone_bytes
FROM DB_M10_RECOVERY.INFORMATION_SCHEMA.TABLE_STORAGE_METRICS
WHERE table_schema IN ('OPERACIONES', 'RECOVERY')
ORDER BY table_schema, table_name;

USE ROLE SYSADMIN;
```

No esperes observar bytes en Fail-safe durante la clase: primero debe finalizar el periodo de Time Travel.

---

# Finalización

## 25. Validar y limpiar

```sql
SELECT
    COUNT(*) AS pedidos,
    SUM(importe) AS importe_total,
    COUNT_IF(estado = 'COMPLETADA') AS completadas,
    COUNT_IF(estado = 'PENDIENTE') AS pendientes,
    COUNT_IF(estado = 'CANCELADA') AS canceladas
FROM DB_M10_RECOVERY.OPERACIONES.PEDIDOS_OPERATIVOS;
```

Resultado final:

```text
8
1405.00
4
3
1
```

Elimina el snapshot si ya no es necesario:

```sql
DROP TABLE IF EXISTS DB_M10_RECOVERY.RECOVERY.PEDIDOS_PRE_UPDATE;
```

La tabla transitoria puede conservarse para el siguiente ejercicio o eliminarse:

```sql
-- DROP TABLE IF EXISTS
--     DB_M10_RECOVERY.OPERACIONES.EVENTOS_REPROCESABLES;
```

Restaura la sesión y suspende el warehouse:

```sql
ALTER SESSION UNSET QUERY_TAG;

ALTER WAREHOUSE WH_M10_RECOVERY SUSPEND;
```


---

# Referencias oficiales

- [Understanding and using Time Travel](https://docs.snowflake.com/en/user-guide/data-time-travel)
- [AT | BEFORE](https://docs.snowflake.com/en/sql-reference/constructs/at-before)
- [CREATE ... CLONE](https://docs.snowflake.com/en/sql-reference/sql/create-clone)
- [INSERT](https://docs.snowflake.com/en/sql-reference/sql/insert)
- [UNDROP TABLE](https://docs.snowflake.com/en/sql-reference/sql/undrop-table)
- [Understanding and viewing Fail-safe](https://docs.snowflake.com/en/user-guide/data-failsafe)
- [Trial accounts](https://docs.snowflake.com/en/user-guide/admin-trial-account)

# Módulo 7 · Ejercicio 1

## Solución guiada: pipeline CDC con un append-only stream y una triggered task

---

## 1. Arquitectura

```text
PEDIDOS_EVENTOS_RAW
        │
        └── STR_PEDIDOS_EVENTOS
                    │
                    └── TASK_PROCESAR_PEDIDOS
                                │
                                └── PEDIDOS_ACTUALES
```

La tabla RAW es un log de eventos. No se modifica una versión anterior: cada cambio genera una fila nueva.

El stream expone los eventos que todavía no han sido consumidos por una operación DML confirmada.

---

## 2. Preparar Workspaces, warehouse y privilegios

En **Workspaces**, crea:

```text
M7_E01_STREAM_TRIGGERED_TASK.sql
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

USE DATABASE DB_CURSO;
USE SCHEMA STAGING;

ALTER SESSION SET QUERY_TAG = 'M07_E01_STREAM_TRIGGERED_TASK';
```

### Por qué se concede EXECUTE TASK

Crear un objeto task no es suficiente para permitir que Snowflake lo ejecute.

El rol propietario necesita el privilegio global:

```text
EXECUTE TASK
```

La task utilizará un warehouse administrado por el usuario, por lo que no necesita `EXECUTE MANAGED TASK`, que corresponde a tasks serverless.

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

```sql
CREATE OR REPLACE TRANSIENT TABLE
    DB_CURSO.STAGING.PEDIDOS_EVENTOS_RAW (
        event_id             NUMBER(18,0),
        id_pedido            NUMBER(18,0),
        id_cliente           NUMBER(18,0),
        fecha_pedido         DATE,
        importe              NUMBER(12,2),
        estado               VARCHAR(20),
        fecha_modificacion   TIMESTAMP_NTZ,
        _source_file         VARCHAR,
        _loaded_at           TIMESTAMP_LTZ
    );
```

### Diseño append-only

La tabla no representa el estado actual, sino una secuencia de eventos.

Por ejemplo:

```text
event_id 1 → pedido 8101 → PENDIENTE
event_id 2 → pedido 8101 → COMPLETADA
```

No ejecutaremos `UPDATE` ni `DELETE` sobre RAW durante el flujo normal.

---

## 4. Crear el stream

```sql
CREATE OR REPLACE STREAM
    DB_CURSO.STAGING.STR_PEDIDOS_EVENTOS

ON TABLE DB_CURSO.STAGING.PEDIDOS_EVENTOS_RAW

APPEND_ONLY = TRUE;
```

### Qué significa APPEND_ONLY

El stream solo registra inserciones.

Es más eficiente cuando el origen es un log o una capa de aterrizaje donde:

- Los registros se añaden.
- No se corrigen en el mismo objeto.
- Las nuevas versiones llegan como filas nuevas.

Un append-only stream no registra actualizaciones ni eliminaciones realizadas directamente sobre la tabla fuente.

Comprueba el objeto:

```sql
SHOW STREAMS LIKE 'STR_PEDIDOS_EVENTOS'
IN SCHEMA DB_CURSO.STAGING;
```

Consulta el stream:

```sql
SELECT *
FROM DB_CURSO.STAGING.STR_PEDIDOS_EVENTOS;
```

Debe estar vacío.

Comprueba la función:

```sql
SELECT SYSTEM$STREAM_HAS_DATA(
    'DB_CURSO.STAGING.STR_PEDIDOS_EVENTOS'
) AS hay_cambios;
```

Resultado:

```text
FALSE
```

---

## 5. Crear el destino

```sql
CREATE OR REPLACE TABLE
    DB_CURSO.CURATED.PEDIDOS_ACTUALES (
        id_pedido            NUMBER(18,0),
        id_cliente           NUMBER(18,0),
        fecha_pedido         DATE,
        importe              NUMBER(12,2),
        estado               VARCHAR(20),
        fecha_modificacion   TIMESTAMP_NTZ,
        event_id             NUMBER(18,0),
        _source_file         VARCHAR,
        _loaded_at           TIMESTAMP_LTZ,
        _processed_at        TIMESTAMP_LTZ
    );
```

La clave lógica es:

```text
id_pedido
```

La tabla debe contener una sola fila por pedido.

---

## 6. Crear la tabla de prueba transaccional

```sql
CREATE OR REPLACE TRANSIENT TABLE
    DB_CURSO.STAGING.STREAM_PRUEBA_ROLLBACK (
        event_id           NUMBER(18,0),
        id_pedido          NUMBER(18,0),
        metadata_action    VARCHAR,
        metadata_isupdate  BOOLEAN,
        metadata_row_id    VARCHAR
    );
```

---

## 7. Insertar el primer microbatch

```sql
INSERT INTO DB_CURSO.STAGING.PEDIDOS_EVENTOS_RAW
SELECT
    column1::NUMBER(18,0),
    column2::NUMBER(18,0),
    column3::NUMBER(18,0),
    column4::DATE,
    column5::NUMBER(12,2),
    column6::VARCHAR(20),
    column7::TIMESTAMP_NTZ,
    'pedidos_microbatch_01.csv',
    CURRENT_TIMESTAMP()
FROM VALUES
    (1, 8101, 1001, '2026-05-01', 100.00, 'PENDIENTE',
     '2026-05-01 10:00:00'),

    (2, 8101, 1001, '2026-05-01', 100.00, 'COMPLETADA',
     '2026-05-01 10:05:00'),

    (3, 8102, 1002, '2026-05-01', 250.00, 'COMPLETADA',
     '2026-05-01 10:10:00'),

    (4, 8103, 1003, '2026-05-01', 80.00, 'PENDIENTE',
     '2026-05-01 10:15:00'),

    (5, 8104, 1004, '2026-05-01', 50.00, 'CANCELADA',
     '2026-05-01 10:20:00');
```

Comprueba RAW:

```sql
SELECT
    COUNT(*) AS filas,
    COUNT(DISTINCT id_pedido) AS pedidos
FROM DB_CURSO.STAGING.PEDIDOS_EVENTOS_RAW;
```

Resultado:

| FILAS | PEDIDOS |
|---:|---:|
| 5 | 4 |

Comprueba el stream:

```sql
SELECT COUNT(*) AS cambios_pendientes
FROM DB_CURSO.STAGING.STR_PEDIDOS_EVENTOS;
```

Resultado:

```text
5
```

Y:

```sql
SELECT SYSTEM$STREAM_HAS_DATA(
    'DB_CURSO.STAGING.STR_PEDIDOS_EVENTOS'
) AS hay_cambios;
```

Resultado:

```text
TRUE
```

---

## 8. Inspeccionar los metadatos del stream

```sql
SELECT
    event_id,
    id_pedido,
    estado,
    fecha_modificacion,

    METADATA$ACTION AS accion,

    METADATA$ISUPDATE AS es_parte_de_update,

    METADATA$ROW_ID AS row_id

FROM DB_CURSO.STAGING.STR_PEDIDOS_EVENTOS

ORDER BY event_id;
```

Resultado esperado para las columnas CDC:

```text
ACCION = INSERT
ES_PARTE_DE_UPDATE = FALSE
```

### Por qué

Las cinco filas fueron insertadas en la tabla fuente.

El flujo no utiliza un `UPDATE` sobre el pedido `8101`. Se añadieron dos eventos diferentes.

### Consultar no consume

Ejecuta dos veces:

```sql
SELECT COUNT(*)
FROM DB_CURSO.STAGING.STR_PEDIDOS_EVENTOS;
```

Ambas consultas deben devolver:

```text
5
```

Un stream no avanza por ser consultado.

---

## 9. Probar el consumo con ROLLBACK

Ejecuta:

```sql
BEGIN;

INSERT INTO DB_CURSO.STAGING.STREAM_PRUEBA_ROLLBACK
SELECT
    event_id,
    id_pedido,
    METADATA$ACTION,
    METADATA$ISUPDATE,
    METADATA$ROW_ID
FROM DB_CURSO.STAGING.STR_PEDIDOS_EVENTOS;

ROLLBACK;
```

Comprueba la tabla:

```sql
SELECT COUNT(*) AS filas_prueba
FROM DB_CURSO.STAGING.STREAM_PRUEBA_ROLLBACK;
```

Resultado:

```text
0
```

Comprueba el stream:

```sql
SELECT COUNT(*) AS cambios_pendientes
FROM DB_CURSO.STAGING.STR_PEDIDOS_EVENTOS;
```

Resultado:

```text
5
```

### Explicación

El stream se utilizó dentro de un DML, pero la transacción no se confirmó.

El offset avanza al final de una transacción que consume correctamente el stream. Como ejecutamos `ROLLBACK`, el consumo y el avance del offset se deshicieron.

---

## 10. Crear la triggered task

```sql
CREATE OR REPLACE TASK
    DB_CURSO.STAGING.TASK_PROCESAR_PEDIDOS

    WAREHOUSE = WH_DEV

    USER_TASK_MINIMUM_TRIGGER_INTERVAL_IN_SECONDS = 10

    WHEN SYSTEM$STREAM_HAS_DATA(
        'DB_CURSO.STAGING.STR_PEDIDOS_EVENTOS'
    )

AS

MERGE INTO DB_CURSO.CURATED.PEDIDOS_ACTUALES AS destino

USING (
    SELECT
        event_id,
        id_pedido,
        id_cliente,
        fecha_pedido,
        importe,
        estado,
        fecha_modificacion,
        _source_file,
        _loaded_at

    FROM DB_CURSO.STAGING.STR_PEDIDOS_EVENTOS

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
    destino.importe = origen.importe,
    destino.estado = origen.estado,
    destino.fecha_modificacion = origen.fecha_modificacion,
    destino.event_id = origen.event_id,
    destino._source_file = origen._source_file,
    destino._loaded_at = origen._loaded_at,
    destino._processed_at = CURRENT_TIMESTAMP()

WHEN NOT MATCHED
THEN INSERT (
    id_pedido,
    id_cliente,
    fecha_pedido,
    importe,
    estado,
    fecha_modificacion,
    event_id,
    _source_file,
    _loaded_at,
    _processed_at
)
VALUES (
    origen.id_pedido,
    origen.id_cliente,
    origen.fecha_pedido,
    origen.importe,
    origen.estado,
    origen.fecha_modificacion,
    origen.event_id,
    origen._source_file,
    origen._loaded_at,
    CURRENT_TIMESTAMP()
);
```

### Por qué no se indica SCHEDULE

Es una triggered task.

La condición:

```sql
WHEN SYSTEM$STREAM_HAS_DATA(...)
```

actúa como disparador cuando no existe `SCHEDULE`.

### Estado inicial

Las tasks se crean suspendidas.

Comprueba:

```sql
SHOW TASKS LIKE 'TASK_PROCESAR_PEDIDOS'
IN SCHEMA DB_CURSO.STAGING;
```

La columna de estado debe indicar que está suspendida.

---

## 11. Reanudar la task

```sql
ALTER TASK
    DB_CURSO.STAGING.TASK_PROCESAR_PEDIDOS
RESUME;
```

Al reanudarse, la task comprueba el stream.

Como existen cinco cambios, debe ejecutar el `MERGE`.

Las triggered tasks se evalúan como máximo cada 30 segundos de forma predeterminada. En este ejercicio hemos reducido el intervalo mínimo a 10 segundos.

---

## 12. Consultar TASK_HISTORY

La función solo admite un nombre de task no cualificado en `TASK_NAME`.

Ejecuta:

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

        TASK_NAME => 'TASK_PROCESAR_PEDIDOS'
    )
)

WHERE query_id IS NOT NULL

ORDER BY scheduled_time DESC;
```

Repite la consulta si todavía aparece como `EXECUTING` o no aparece una ejecución iniciada.

Resultado esperado:

```text
STATE = SUCCEEDED
SCHEDULED_FROM = TRIGGER
```

---

## 13. Validar la primera ejecución

```sql
SELECT *
FROM DB_CURSO.CURATED.PEDIDOS_ACTUALES
ORDER BY id_pedido;
```

Deben existir cuatro filas.

Para `8101` debe haberse seleccionado la versión más reciente:

```text
EVENT_ID = 2
ESTADO = COMPLETADA
```

Comprueba:

```sql
SELECT COUNT(*) AS pedidos
FROM DB_CURSO.CURATED.PEDIDOS_ACTUALES;
```

Resultado:

```text
4
```

Comprueba el stream:

```sql
SELECT COUNT(*) AS cambios_pendientes
FROM DB_CURSO.STAGING.STR_PEDIDOS_EVENTOS;
```

Resultado:

```text
0
```

Y:

```sql
SELECT SYSTEM$STREAM_HAS_DATA(
    'DB_CURSO.STAGING.STR_PEDIDOS_EVENTOS'
) AS hay_cambios;
```

Resultado:

```text
FALSE
```

### Qué consumió el stream

El `MERGE` fue una operación DML confirmada.

Aunque cinco eventos entraron en el stream y solo cuatro filas ganadoras llegaron al `MERGE`, la sentencia leyó el conjunto de cambios y confirmó la transacción. El offset avanzó hasta la versión de la tabla correspondiente al inicio de la transacción.

---

## 14. Insertar el segundo microbatch

```sql
INSERT INTO DB_CURSO.STAGING.PEDIDOS_EVENTOS_RAW
SELECT
    column1::NUMBER(18,0),
    column2::NUMBER(18,0),
    column3::NUMBER(18,0),
    column4::DATE,
    column5::NUMBER(12,2),
    column6::VARCHAR(20),
    column7::TIMESTAMP_NTZ,
    'pedidos_microbatch_02.csv',
    CURRENT_TIMESTAMP()
FROM VALUES
    (6, 8102, 1002, '2026-05-01', 250.00, 'CANCELADA',
     '2026-05-01 11:00:00'),

    (7, 8103, 1003, '2026-05-01', 90.00, 'COMPLETADA',
     '2026-05-01 11:05:00'),

    (8, 8105, 1005, '2026-05-01', 60.00, 'PENDIENTE',
     '2026-05-01 11:10:00'),

    (9, 8105, 1005, '2026-05-01', 65.00, 'COMPLETADA',
     '2026-05-01 11:15:00'),

    (10, 8106, 1006, '2026-05-01', 120.00, 'COMPLETADA',
     '2026-05-01 11:20:00');
```

Comprueba brevemente:

```sql
SELECT
    COUNT(*) AS cambios,
    COUNT(DISTINCT id_pedido) AS pedidos
FROM DB_CURSO.STAGING.STR_PEDIDOS_EVENTOS;
```

Antes de que la task termine, el resultado esperado es:

```text
5 cambios
4 pedidos
```

La task está reanudada y procesará el stream automáticamente.

Consulta `TASK_HISTORY` hasta observar otra ejecución `SUCCEEDED`.

---

## 15. Validar el estado final

```sql
SELECT
    id_pedido,
    importe,
    estado,
    fecha_modificacion,
    event_id
FROM DB_CURSO.CURATED.PEDIDOS_ACTUALES
ORDER BY id_pedido;
```

Resultado esperado:

| ID_PEDIDO | IMPORTE | ESTADO | EVENT_ID |
|---:|---:|---|---:|
| 8101 | 100.00 | COMPLETADA | 2 |
| 8102 | 250.00 | CANCELADA | 6 |
| 8103 | 90.00 | COMPLETADA | 7 |
| 8104 | 50.00 | CANCELADA | 5 |
| 8105 | 65.00 | COMPLETADA | 9 |
| 8106 | 120.00 | COMPLETADA | 10 |

Resumen:

```sql
SELECT
    COUNT(*) AS pedidos,
    SUM(importe) AS importe_total,
    COUNT_IF(estado = 'COMPLETADA') AS completados,
    COUNT_IF(estado = 'CANCELADA') AS cancelados
FROM DB_CURSO.CURATED.PEDIDOS_ACTUALES;
```

Resultado:

| PEDIDOS | IMPORTE_TOTAL | COMPLETADOS | CANCELADOS |
|---:|---:|---:|---:|
| 6 | 675.00 | 4 | 2 |

Control de duplicados:

```sql
SELECT
    id_pedido,
    COUNT(*) AS filas
FROM DB_CURSO.CURATED.PEDIDOS_ACTUALES
GROUP BY id_pedido
HAVING COUNT(*) > 1;
```

No debe devolver filas.

El stream debe estar vacío:

```sql
SELECT COUNT(*)
FROM DB_CURSO.STAGING.STR_PEDIDOS_EVENTOS;
```

---

## 16. Probar una versión antigua

Inserta:

```sql
INSERT INTO DB_CURSO.STAGING.PEDIDOS_EVENTOS_RAW
VALUES (
    11,
    8103,
    1003,
    '2026-05-01',
    70.00,
    'PENDIENTE',
    '2026-05-01 10:30:00',
    'pedidos_microbatch_tardio.csv',
    CURRENT_TIMESTAMP()
);
```

La versión actual de `8103` es:

```text
2026-05-01 11:05:00
```

La nueva fila tardía tiene:

```text
2026-05-01 10:30:00
```

La task se ejecutará y consumirá el stream, pero no satisfará:

```sql
origen.fecha_modificacion
> destino.fecha_modificacion
```

Comprueba después:

```sql
SELECT
    id_pedido,
    importe,
    estado,
    fecha_modificacion,
    event_id
FROM DB_CURSO.CURATED.PEDIDOS_ACTUALES
WHERE id_pedido = 8103;
```

Debe conservar:

```text
90.00
COMPLETADA
2026-05-01 11:05:00
event_id 7
```

El stream vuelve a quedar vacío.

### Consumo no equivale a modificación

La task puede consumir correctamente un evento aunque ninguna fila del destino sea insertada o actualizada.

El evento ha sido evaluado y se ha determinado que es obsoleto.

---

## 17. Suspender la task

```sql
ALTER TASK
    DB_CURSO.STAGING.TASK_PROCESAR_PEDIDOS
SUSPEND;
```

Comprueba:

```sql
SHOW TASKS LIKE 'TASK_PROCESAR_PEDIDOS'
IN SCHEMA DB_CURSO.STAGING;
```

La task debe aparecer suspendida.

Suspenderla evita que futuras inserciones accidentales durante la clase provoquen nuevas ejecuciones y consumo de warehouse.

También puedes suspender el warehouse al finalizar:

```sql
ALTER WAREHOUSE WH_DEV SUSPEND;
```

---

## 18. Auditar las ejecuciones

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
            => DATEADD('hour', -1, CURRENT_TIMESTAMP()),

        SCHEDULED_TIME_RANGE_END
            => CURRENT_TIMESTAMP(),

        RESULT_LIMIT => 50,

        TASK_NAME => 'TASK_PROCESAR_PEDIDOS'
    )
)

WHERE query_id IS NOT NULL

ORDER BY scheduled_time;
```

Debes identificar al menos:

1. Primera ejecución: procesa el microbatch inicial.
2. Segunda ejecución: procesa actualizaciones y pedidos nuevos.
3. Tercera ejecución: consume la versión antigua sin modificar el destino.

En las ejecuciones automáticas:

```text
SCHEDULED_FROM = TRIGGER
```

---

## 19. Interpretar SYSTEM$STREAM_HAS_DATA

La función está diseñada para evitar falsos negativos: no debería devolver `FALSE` cuando existen cambios.

Sin embargo, puede devolver `TRUE` aunque la consulta del stream no produzca cambios útiles para la lógica del pipeline.

Por eso:

- La task debe ser segura aunque el `MERGE` no cambie filas.
- El cuerpo no debe asumir que necesariamente habrá una inserción o actualización.
- La monitorización debe diferenciar task ejecutada de filas realmente modificadas.

---

## 20. Offset, transacciones y concurrencia

Un stream puede consultarse varias veces sin avanzar.

Cuando se utiliza dentro de una operación DML:

- El stream queda ligado a la transacción.
- Varias sentencias dentro de la misma transacción pueden ver el mismo conjunto.
- El offset avanza al confirmar.
- Un `ROLLBACK` mantiene el offset anterior.

Este comportamiento permite consumir el cambio y actualizar varios destinos dentro de una transacción explícita, siempre que el diseño lo requiera.

---

## 21. Riesgo de staleness

El stream depende del historial de versiones de la tabla fuente.

Si su offset queda fuera del periodo de retención disponible:

```text
STALE = TRUE
```

El stream ya no puede proporcionar correctamente los cambios y debe recrearse.

Puedes inspeccionar su estado con:

```sql
SHOW STREAMS LIKE 'STR_PEDIDOS_EVENTOS'
IN SCHEMA DB_CURSO.STAGING;
```

En producción deben monitorizarse, al menos:

- `STALE`.
- `STALE_AFTER`.
- Último consumo correcto.
- Fallos consecutivos de la task.
- Edad del cambio más antiguo pendiente.

---

## 22. Limpieza opcional

No realices la limpieza si el siguiente ejercicio va a reutilizar los objetos.

```sql
ALTER TASK IF EXISTS
    DB_CURSO.STAGING.TASK_PROCESAR_PEDIDOS
SUSPEND;

DROP TASK IF EXISTS
    DB_CURSO.STAGING.TASK_PROCESAR_PEDIDOS;

DROP STREAM IF EXISTS
    DB_CURSO.STAGING.STR_PEDIDOS_EVENTOS;

DROP TABLE IF EXISTS
    DB_CURSO.STAGING.STREAM_PRUEBA_ROLLBACK;

DROP TABLE IF EXISTS
    DB_CURSO.CURATED.PEDIDOS_ACTUALES;

DROP TABLE IF EXISTS
    DB_CURSO.STAGING.PEDIDOS_EVENTOS_RAW;

ALTER SESSION UNSET QUERY_TAG;
```

El privilegio global concedido a `SYSADMIN` puede conservarse para los siguientes laboratorios de tasks.

---

## 23. Errores frecuentes

### La task no se ejecuta

Comprueba:

```sql
SHOW TASKS LIKE 'TASK_PROCESAR_PEDIDOS'
IN SCHEMA DB_CURSO.STAGING;
```

Revisa:

- Estado reanudado.
- Rol propietario con `EXECUTE TASK`.
- `USAGE` sobre `WH_DEV`.
- Stream con cambios.
- Nombre completamente cualificado dentro de `SYSTEM$STREAM_HAS_DATA`.

Consulta errores:

```sql
SELECT *
FROM TABLE(
    DB_CURSO.INFORMATION_SCHEMA.TASK_HISTORY(
        SCHEDULED_TIME_RANGE_START
            => DATEADD('hour', -1, CURRENT_TIMESTAMP()),
        TASK_NAME => 'TASK_PROCESAR_PEDIDOS',
        ERROR_ONLY => TRUE
    )
);
```

---

### La task aparece como SKIPPED

La condición `WHEN` se evaluó como falsa.

Comprueba:

```sql
SELECT SYSTEM$STREAM_HAS_DATA(
    'DB_CURSO.STAGING.STR_PEDIDOS_EVENTOS'
);
```

---

### La task sigue en EXECUTING

La ejecución es asíncrona.

Vuelve a consultar `TASK_HISTORY` unos segundos después.

---

### El stream continúa con datos tras una task SUCCEEDED

Comprueba que el cuerpo del task consulta realmente:

```text
DB_CURSO.STAGING.STR_PEDIDOS_EVENTOS
```

dentro del `MERGE`, no la tabla RAW.

---

### PEDIDOS_ACTUALES contiene dos filas para 8105

La fuente del `MERGE` no se deduplicó.

Revisa:

```sql
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY id_pedido
    ORDER BY fecha_modificacion DESC, event_id DESC
) = 1
```

---

### La versión antigua sobrescribe 8103

Falta la condición:

```sql
WHEN MATCHED
AND origen.fecha_modificacion > destino.fecha_modificacion
```

o el criterio de desempate con `event_id`.

---

### No se puede reanudar la task

El rol propietario puede no tener el privilegio global.

Concede:

```sql
USE ROLE ACCOUNTADMIN;

GRANT EXECUTE TASK
ON ACCOUNT
TO ROLE SYSADMIN;
```

Después vuelve a `SYSADMIN`.

---

## 24. Respuestas a las preguntas de reflexión

### 1. ¿Qué almacena un stream?

Mantiene un offset y utiliza el historial de versiones de la fuente para exponer el delta. No almacena una copia completa de las filas.

### 2. ¿Por qué SELECT no consume?

Porque observar los cambios no constituye una transacción DML que avance el offset.

### 3. ¿Por qué consumo y destino deben ser atómicos?

Para evitar avanzar el stream sin haber actualizado correctamente el destino, o actualizar el destino sin avanzar el stream.

### 4. ¿Por qué append-only?

La fuente es un log de eventos que solo recibe inserciones. Este tipo de stream es más eficiente y expresa ese contrato.

### 5. ¿Qué ocurre con UPDATE en RAW?

Un append-only stream no lo registra. Por eso el patrón requiere que cada cambio sea una nueva fila.

### 6. ¿Por qué deduplicar?

Un microbatch puede contener varias versiones del mismo pedido. El `MERGE` necesita una única versión ganadora por clave.

### 7. ¿Ventaja de una triggered task?

No necesita consultar continuamente el stream. Se activa cuando Snowflake detecta cambios.

### 8. ¿Por qué suspenderla?

Para evitar ejecuciones accidentales y consumo adicional después del laboratorio.

### 9. ¿Cuándo usar una task programada?

Cuando se desea agrupar cambios en ventanas concretas, respetar un horario de negocio o coordinar el proceso con otros sistemas.

### 10. ¿Cómo evitar que quede stale?

Monitorizando `STALE_AFTER`, consumiendo regularmente, alertando ante fallos y dimensionando la retención de la tabla fuente.

---
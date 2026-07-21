# Módulo 7 · Ejercicio 2
## Solución guiada: pipeline declarativo con Dynamic Tables

> Todas las instrucciones utilizan **Workspaces**, la experiencia actual de edición SQL de Snowflake.

---

## 1. Arquitectura

```text
VENTAS_DT_RAW ────────────────┐
                              ├── DT_VENTAS_PUBLICABLES
CLIENTES_DT ──────────────────┘             ↓
                                 DT_VENTAS_DIA_REGION
```

La primera Dynamic Table realiza el enriquecimiento y el filtrado.

La segunda materializa el agregado que consumirá el dashboard.

Snowflake:

- Analiza las dependencias.
- Mantiene el orden del pipeline.
- Decide cuándo refrescar para intentar cumplir el target lag.
- Aplica cada refresco de forma atómica.

---

## 2. Preparar Workspaces y el contexto

En **Workspaces**, crea:

```text
M7_E02_DYNAMIC_TABLES.sql
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
CREATE SCHEMA IF NOT EXISTS DB_CURSO.MARTS;

USE DATABASE DB_CURSO;
USE SCHEMA STAGING;

ALTER SESSION SET QUERY_TAG = 'M07_E02_DYNAMIC_TABLES';
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

## 3. Crear la dimensión de clientes

```sql
CREATE OR REPLACE TABLE DB_CURSO.CURATED.CLIENTES_DT (
    id_cliente NUMBER(18,0),
    region     VARCHAR(20),
    segmento   VARCHAR(20)
);
```

Inserta:

```sql
INSERT INTO DB_CURSO.CURATED.CLIENTES_DT
SELECT
    column1::NUMBER(18,0),
    column2::VARCHAR(20),
    column3::VARCHAR(20)
FROM VALUES
    (1001, 'NORTE', 'PYME'),
    (1002, 'SUR',   'EMPRESA'),
    (1003, 'NORTE', 'EMPRESA'),
    (1004, 'ESTE',  'PYME');
```

Activa change tracking:

```sql
ALTER TABLE DB_CURSO.CURATED.CLIENTES_DT
SET CHANGE_TRACKING = TRUE;
```

---

## 4. Crear la tabla de ventas

```sql
CREATE OR REPLACE TABLE DB_CURSO.STAGING.VENTAS_DT_RAW (
    id_venta             NUMBER(18,0),
    id_cliente           NUMBER(18,0),
    fecha                DATE,
    canal                VARCHAR(20),
    importe              NUMBER(12,2),
    moneda               VARCHAR(3),
    estado               VARCHAR(20),
    fecha_modificacion   TIMESTAMP_NTZ
);
```

Inserta:

```sql
INSERT INTO DB_CURSO.STAGING.VENTAS_DT_RAW
SELECT
    column1::NUMBER(18,0),
    column2::NUMBER(18,0),
    column3::DATE,
    column4::VARCHAR(20),
    column5::NUMBER(12,2),
    'EUR'::VARCHAR(3),
    column6::VARCHAR(20),
    column7::TIMESTAMP_NTZ
FROM VALUES
    (9001, 1001, '2026-06-01', 'WEB',         100.00, 'COMPLETADA', '2026-06-01 10:00:00'),
    (9002, 1002, '2026-06-01', 'TIENDA',      200.00, 'COMPLETADA', '2026-06-01 10:05:00'),
    (9003, 1003, '2026-06-01', 'WEB',         150.00, 'PENDIENTE',  '2026-06-01 10:10:00'),
    (9004, 1004, '2026-06-01', 'MARKETPLACE',  80.00, 'COMPLETADA', '2026-06-01 10:15:00'),

    (9005, 1001, '2026-06-02', 'WEB',         120.00, 'COMPLETADA', '2026-06-02 10:00:00'),
    (9006, 1002, '2026-06-02', 'TIENDA',       90.00, 'CANCELADA',  '2026-06-02 10:05:00'),
    (9007, 1003, '2026-06-02', 'WEB',          75.00, 'COMPLETADA', '2026-06-02 10:10:00'),
    (9008, 1004, '2026-06-02', 'MARKETPLACE',  60.00, 'COMPLETADA', '2026-06-02 10:15:00'),

    (9009, 1001, '2026-06-03', 'TIENDA',      110.00, 'COMPLETADA', '2026-06-03 10:00:00'),
    (9010, 1002, '2026-06-03', 'WEB',         140.00, 'COMPLETADA', '2026-06-03 10:05:00'),
    (9011, 1003, '2026-06-03', 'WEB',         160.00, 'COMPLETADA', '2026-06-03 10:10:00'),
    (9012, 1004, '2026-06-03', 'MARKETPLACE',  95.00, 'PENDIENTE',  '2026-06-03 10:15:00');
```

Activa change tracking:

```sql
ALTER TABLE DB_CURSO.STAGING.VENTAS_DT_RAW
SET CHANGE_TRACKING = TRUE;
```

### Comprobar las fuentes

```sql
SELECT
    COUNT(*) AS ventas_totales,
    COUNT_IF(estado = 'COMPLETADA') AS completadas,
    SUM(
        IFF(estado = 'COMPLETADA', importe, 0)
    ) AS importe_completado
FROM DB_CURSO.STAGING.VENTAS_DT_RAW;
```

Resultado:

| VENTAS_TOTALES | COMPLETADAS | IMPORTE_COMPLETADO |
|---:|---:|---:|
| 12 | 9 | 1045.00 |

---

## 5. Crear la Dynamic Table intermedia

```sql
CREATE OR REPLACE DYNAMIC TABLE
    DB_CURSO.CURATED.DT_VENTAS_PUBLICABLES

    TARGET_LAG = DOWNSTREAM

    SCHEDULER = ENABLE

    WAREHOUSE = WH_DEV

    REFRESH_MODE = INCREMENTAL

    INITIALIZE = ON_CREATE

AS

SELECT
    v.id_venta,
    v.fecha,
    v.id_cliente,
    c.region,
    c.segmento,
    v.canal,
    v.importe,
    v.moneda,
    v.estado,
    v.fecha_modificacion

FROM DB_CURSO.STAGING.VENTAS_DT_RAW AS v

JOIN DB_CURSO.CURATED.CLIENTES_DT AS c
    ON c.id_cliente = v.id_cliente

WHERE v.estado = 'COMPLETADA';
```

### `TARGET_LAG = DOWNSTREAM`

Esta tabla no necesita mantener una planificación independiente.

Se refrescará cuando una Dynamic Table descendente necesite datos actualizados.

Esto evita refrescar dos capas con relojes separados y reduce trabajo innecesario.

### `SCHEDULER = ENABLE`

Declara explícitamente que la tabla participa en el planificador interno de Dynamic Tables.

### `REFRESH_MODE = INCREMENTAL`

Snowflake debe procesar los cambios compatibles en lugar de reconstruir siempre todo el resultado.

Declararlo explícitamente tiene dos ventajas:

- El comportamiento queda documentado.
- La creación falla si la definición no admite ese modo, en lugar de elegir silenciosamente otro.

### `INITIALIZE = ON_CREATE`

La sentencia no termina hasta completar la inicialización.

Al acabar, el objeto puede consultarse inmediatamente.

Comprueba:

```sql
SELECT COUNT(*) AS ventas_publicables
FROM DB_CURSO.CURATED.DT_VENTAS_PUBLICABLES;
```

Resultado:

```text
9
```

---

## 6. Crear la Dynamic Table terminal

```sql
CREATE OR REPLACE DYNAMIC TABLE
    DB_CURSO.MARTS.DT_VENTAS_DIA_REGION

    TARGET_LAG = '1 minute'

    SCHEDULER = ENABLE

    WAREHOUSE = WH_DEV

    REFRESH_MODE = INCREMENTAL

    INITIALIZE = ON_CREATE

AS

SELECT
    fecha AS dia,
    region,
    canal,

    COUNT(*)::NUMBER(18,0)
        AS num_ventas,

    SUM(importe)::NUMBER(18,2)
        AS importe_total,

    ROUND(AVG(importe), 2)::NUMBER(18,2)
        AS ticket_medio,

    MAX(fecha_modificacion)
        AS ultima_modificacion_grupo

FROM DB_CURSO.CURATED.DT_VENTAS_PUBLICABLES

GROUP BY
    fecha,
    region,
    canal;
```

### Por qué un minuto

Es el mínimo target lag temporal admitido actualmente.

Se utiliza para que el laboratorio pueda observar un refresco programado sin una espera larga.

En producción debe utilizarse el mayor lag compatible con las necesidades del negocio, porque un objetivo más corto puede aumentar la frecuencia de refresco y el consumo.

### Validación inicial

```sql
SELECT
    COUNT(*) AS filas_agregadas,
    SUM(num_ventas) AS ventas,
    SUM(importe_total) AS importe
FROM DB_CURSO.MARTS.DT_VENTAS_DIA_REGION;
```

Resultado:

| FILAS_AGREGADAS | VENTAS | IMPORTE |
|---:|---:|---:|
| 8 | 9 | 1045.00 |

Muestra el resultado:

```sql
SELECT *
FROM DB_CURSO.MARTS.DT_VENTAS_DIA_REGION
ORDER BY dia, region, canal;
```

---

## 7. Inspeccionar el modo y el estado

```sql
SHOW DYNAMIC TABLES
IN DATABASE DB_CURSO;
```

Revisa para ambos objetos:

- `target_lag`
- `refresh_mode`
- `warehouse`
- `scheduling_state`
- `data_timestamp`

El modo debe ser:

```text
INCREMENTAL
```

El estado activo puede representarse como `RUNNING` o `ACTIVE` según la función o la salida utilizada. No debe aparecer `SUSPENDED`.

### Consultar el pipeline conectado

```sql
SELECT
    qualified_name,
    target_lag_sec,
    target_lag_type,
    latest_data_timestamp,
    last_completed_refresh_state

FROM TABLE(
    DB_CURSO.INFORMATION_SCHEMA.DYNAMIC_TABLES(
        NAME =>
          'DB_CURSO.MARTS.DT_VENTAS_DIA_REGION',

        INCLUDE_CONNECTED => TRUE
    )
)

ORDER BY qualified_name;
```

Deben aparecer las dos Dynamic Tables conectadas.

Para la intermedia, el target lag es de tipo downstream y no representa un número de segundos independiente.

---

## 8. Consultar el historial de creación

```sql
SELECT
    name,
    state,
    refresh_action,
    refresh_trigger,
    data_timestamp,
    refresh_start_time,
    refresh_end_time,
    query_id,
    warehouse,
    state_message

FROM TABLE(
    DB_CURSO.INFORMATION_SCHEMA
        .DYNAMIC_TABLE_REFRESH_HISTORY(
            DATA_TIMESTAMP_START
                => DATEADD(
                    'hour',
                    -2,
                    CURRENT_TIMESTAMP()
                ),

            RESULT_LIMIT => 100,

            NAME_PREFIX => 'DB_CURSO.'
        )
)

WHERE name IN (
    'DT_VENTAS_PUBLICABLES',
    'DT_VENTAS_DIA_REGION'
)

ORDER BY refresh_start_time;
```

En la inicialización debes observar:

```text
STATE = SUCCEEDED
REFRESH_TRIGGER = CREATION
```

La acción inicial puede aparecer como inicialización o reinitialización según el objeto y la versión de la salida.

---

## 9. Demostrar que una Dynamic Table es de solo lectura

Ejecuta deliberadamente:

```sql
INSERT INTO DB_CURSO.MARTS.DT_VENTAS_DIA_REGION
VALUES (
    '2026-06-04',
    'NORTE',
    'WEB',
    1,
    10.00,
    10.00,
    '2026-06-04 10:00:00'
);
```

La sentencia debe fallar.

### Explicación

Una Dynamic Table es un resultado materializado administrado a partir de su `SELECT`.

No se permite:

- `INSERT`
- `UPDATE`
- `DELETE`
- `TRUNCATE`

Para cambiar el resultado debes:

- Modificar las tablas fuente.
- Cambiar la definición mediante `CREATE OR REPLACE`.
- Elegir Streams y Tasks si necesitas DML procedural o `MERGE` sobre la salida.

---

## 10. Introducir cambios para el refresco automático

### Insertar una nueva venta

```sql
INSERT INTO DB_CURSO.STAGING.VENTAS_DT_RAW
VALUES (
    9013,
    1004,
    '2026-06-03',
    'WEB',
    130.00,
    'EUR',
    'COMPLETADA',
    '2026-06-03 11:00:00'
);
```

### Convertir una venta pendiente en completada

```sql
UPDATE DB_CURSO.STAGING.VENTAS_DT_RAW
SET
    importe = 155.00,
    estado = 'COMPLETADA',
    fecha_modificacion = '2026-06-03 11:05:00'
WHERE id_venta = 9003;
```

Comprueba la fuente:

```sql
SELECT
    COUNT_IF(estado = 'COMPLETADA') AS completadas,
    SUM(
        IFF(estado = 'COMPLETADA', importe, 0)
    ) AS importe_completado
FROM DB_CURSO.STAGING.VENTAS_DT_RAW;
```

Resultado:

```text
11
1330.00
```

### No refrescar manualmente todavía

Consulta el historial cada cierto tiempo:

```sql
SELECT
    name,
    state,
    refresh_trigger,
    refresh_action,
    data_timestamp,
    refresh_start_time,
    refresh_end_time,
    query_id

FROM TABLE(
    DB_CURSO.INFORMATION_SCHEMA
        .DYNAMIC_TABLE_REFRESH_HISTORY(
            DATA_TIMESTAMP_START
                => DATEADD(
                    'minute',
                    -15,
                    CURRENT_TIMESTAMP()
                ),

            RESULT_LIMIT => 100,

            NAME_PREFIX => 'DB_CURSO.'
        )
)

WHERE name IN (
    'DT_VENTAS_PUBLICABLES',
    'DT_VENTAS_DIA_REGION'
)

ORDER BY refresh_start_time DESC;
```

Busca un refresco:

```text
REFRESH_TRIGGER = SCHEDULED
STATE = SUCCEEDED
```

### El target lag no es un cron

`TARGET_LAG = '1 minute'` significa que Snowflake intenta mantener el dato dentro de ese objetivo de frescura.

No significa:

```text
ejecutar exactamente en el segundo 00 de cada minuto
```

La planificación depende, entre otros factores, de:

- Cambios en las fuentes.
- Duración de refrescos anteriores.
- Dependencias.
- Disponibilidad del warehouse.
- Decisiones del planificador.

---

## 11. Validar el refresco automático

Cuando el historial muestre el refresco correcto:

```sql
SELECT
    (
        SELECT COUNT(*)
        FROM DB_CURSO.CURATED.DT_VENTAS_PUBLICABLES
    ) AS filas_intermedias,

    (
        SELECT COUNT(*)
        FROM DB_CURSO.MARTS.DT_VENTAS_DIA_REGION
    ) AS filas_agregadas,

    (
        SELECT SUM(num_ventas)
        FROM DB_CURSO.MARTS.DT_VENTAS_DIA_REGION
    ) AS ventas_agregadas,

    (
        SELECT SUM(importe_total)
        FROM DB_CURSO.MARTS.DT_VENTAS_DIA_REGION
    ) AS importe_agregado;
```

Resultado:

| FILAS_INTERMEDIAS | FILAS_AGREGADAS | VENTAS_AGREGADAS | IMPORTE_AGREGADO |
|---:|---:|---:|---:|
| 11 | 9 | 11 | 1330.00 |

Comprueba el grupo modificado:

```sql
SELECT *
FROM DB_CURSO.MARTS.DT_VENTAS_DIA_REGION
WHERE dia = '2026-06-01'
  AND region = 'NORTE'
  AND canal = 'WEB';
```

Resultado:

```text
NUM_VENTAS = 2
IMPORTE_TOTAL = 255.00
TICKET_MEDIO = 127.50
```

---

## 12. Suspender la tabla terminal

```sql
ALTER DYNAMIC TABLE
    DB_CURSO.MARTS.DT_VENTAS_DIA_REGION
SUSPEND;
```

Comprueba:

```sql
SHOW DYNAMIC TABLES LIKE 'DT_VENTAS_DIA_REGION'
IN SCHEMA DB_CURSO.MARTS;
```

El estado debe indicar suspensión.

Los datos continúan disponibles:

```sql
SELECT
    COUNT(*) AS filas,
    SUM(importe_total) AS importe
FROM DB_CURSO.MARTS.DT_VENTAS_DIA_REGION;
```

Resultado:

```text
9
1330.00
```

### Insertar una nueva venta durante la suspensión

```sql
INSERT INTO DB_CURSO.STAGING.VENTAS_DT_RAW
VALUES (
    9014,
    1002,
    '2026-06-03',
    'TIENDA',
    50.00,
    'EUR',
    'COMPLETADA',
    '2026-06-03 11:10:00'
);
```

La fuente ya contiene:

```text
12 ventas completadas
1380.00
```

Comprueba:

```sql
SELECT
    COUNT_IF(estado = 'COMPLETADA') AS completadas,
    SUM(
        IFF(estado = 'COMPLETADA', importe, 0)
    ) AS importe
FROM DB_CURSO.STAGING.VENTAS_DT_RAW;
```

La Dynamic Table suspendida continúa mostrando el estado anterior hasta que se refresque.

---

## 13. Reanudar y refrescar manualmente

Reanuda:

```sql
ALTER DYNAMIC TABLE
    DB_CURSO.MARTS.DT_VENTAS_DIA_REGION
RESUME;
```

Ejecuta el refresco:

```sql
ALTER DYNAMIC TABLE
    DB_CURSO.MARTS.DT_VENTAS_DIA_REGION
REFRESH;
```

La solicitud manual sobre la tabla terminal refresca las dependencias necesarias para entregar un resultado coherente.

Comprueba el historial:

```sql
SELECT
    name,
    state,
    refresh_trigger,
    refresh_action,
    data_timestamp,
    refresh_start_time,
    refresh_end_time,
    query_id,
    warehouse

FROM TABLE(
    DB_CURSO.INFORMATION_SCHEMA
        .DYNAMIC_TABLE_REFRESH_HISTORY(
            DATA_TIMESTAMP_START
                => DATEADD(
                    'minute',
                    -15,
                    CURRENT_TIMESTAMP()
                ),

            RESULT_LIMIT => 100,

            NAME_PREFIX => 'DB_CURSO.'
        )
)

WHERE name IN (
    'DT_VENTAS_PUBLICABLES',
    'DT_VENTAS_DIA_REGION'
)

ORDER BY refresh_start_time DESC;
```

Debes encontrar una entrada:

```text
REFRESH_TRIGGER = MANUAL
STATE = SUCCEEDED
```

---

## 14. Validar el resultado final

```sql
SELECT
    (
        SELECT COUNT(*)
        FROM DB_CURSO.CURATED.DT_VENTAS_PUBLICABLES
    ) AS filas_intermedias,

    (
        SELECT COUNT(*)
        FROM DB_CURSO.MARTS.DT_VENTAS_DIA_REGION
    ) AS filas_agregadas,

    (
        SELECT SUM(num_ventas)
        FROM DB_CURSO.MARTS.DT_VENTAS_DIA_REGION
    ) AS ventas_agregadas,

    (
        SELECT SUM(importe_total)
        FROM DB_CURSO.MARTS.DT_VENTAS_DIA_REGION
    ) AS importe_agregado;
```

Resultado:

| FILAS_INTERMEDIAS | FILAS_AGREGADAS | VENTAS_AGREGADAS | IMPORTE_AGREGADO |
|---:|---:|---:|---:|
| 12 | 10 | 12 | 1380.00 |

Comprueba la nueva combinación:

```sql
SELECT *
FROM DB_CURSO.MARTS.DT_VENTAS_DIA_REGION
WHERE dia = '2026-06-03'
  AND region = 'SUR'
  AND canal = 'TIENDA';
```

Resultado:

```text
NUM_VENTAS = 1
IMPORTE_TOTAL = 50.00
TICKET_MEDIO = 50.00
```

---

## 15. Reconciliar las tres capas

```sql
WITH fuente AS (
    SELECT
        COUNT_IF(estado = 'COMPLETADA')
            AS ventas,

        SUM(
            IFF(estado = 'COMPLETADA', importe, 0)
        ) AS importe

    FROM DB_CURSO.STAGING.VENTAS_DT_RAW
),

intermedia AS (
    SELECT
        COUNT(*) AS ventas,
        SUM(importe) AS importe

    FROM DB_CURSO.CURATED.DT_VENTAS_PUBLICABLES
),

mart AS (
    SELECT
        SUM(num_ventas) AS ventas,
        SUM(importe_total) AS importe

    FROM DB_CURSO.MARTS.DT_VENTAS_DIA_REGION
)

SELECT
    fuente.ventas AS ventas_fuente,
    intermedia.ventas AS ventas_intermedia,
    mart.ventas AS ventas_mart,

    fuente.ventas - intermedia.ventas
        AS diferencia_fuente_intermedia,

    intermedia.ventas - mart.ventas
        AS diferencia_intermedia_mart,

    fuente.importe AS importe_fuente,
    intermedia.importe AS importe_intermedia,
    mart.importe AS importe_mart,

    fuente.importe - intermedia.importe
        AS diferencia_importe_fuente_intermedia,

    intermedia.importe - mart.importe
        AS diferencia_importe_intermedia_mart

FROM fuente
CROSS JOIN intermedia
CROSS JOIN mart;
```

Todas las diferencias deben ser:

```text
0
```

---

## 16. Comparación conceptual

### Dynamic Table frente a view

Una view:

- Guarda la consulta.
- No almacena su resultado.
- Calcula al consultarse.
- Siempre lee el estado actual de las fuentes.

Una Dynamic Table:

- Guarda la consulta y materializa el resultado.
- Se actualiza en segundo plano.
- Puede tener cierto lag.
- Consume cómputo durante los refrescos.

### Dynamic Table frente a Streams y Tasks

Dynamic Tables son apropiadas cuando:

- La salida se expresa como una `SELECT`.
- Snowflake puede gestionar dependencias y refrescos.
- No se necesita lógica procedural.

Streams y Tasks son preferibles cuando se requiere:

- `MERGE` complejo.
- Procedimientos.
- Bifurcaciones.
- APIs o funciones externas.
- Reintentos personalizados.
- Horarios cron estrictos.
- Escrituras en varios destinos con control explícito.

### Dynamic Table frente a materialized view

Una materialized view se orienta principalmente a acelerar consultas sobre una tabla base y puede ser utilizada automáticamente por el optimizador.

Una Dynamic Table se orienta a construir pipelines SQL con joins, agregaciones y varias etapas. Los consumidores consultan el objeto explícitamente.

---

## 17. Errores de diseño que debes evitar

### Todas las tablas con DOWNSTREAM

Si la terminal también tuviera:

```sql
TARGET_LAG = DOWNSTREAM
```

no existiría ningún consumidor temporal que impulsara la planificación.

El pipeline no se refrescaría automáticamente y Snowflake no tendría por qué mostrar un error.

### Utilizar AUTO sin verificar

`AUTO` decide el modo durante la creación.

Una modificación o recreación puede resolver de otro modo si cambia la consulta o la capacidad del motor.

En producción conviene declarar:

```text
INCREMENTAL
FULL
```

de forma explícita.

### Usar funciones de sesión en la definición

Las actualizaciones se ejecutan de forma asíncrona y no disponen de una sesión interactiva normal.

Funciones como:

```text
CURRENT_SESSION()
```

no son adecuadas en una definición de Dynamic Table.

### Recrear una fuente sin planificación

`CREATE OR REPLACE TABLE` cambia la identidad del objeto y elimina su historial de change tracking.

Puede obligar a reinitializar o causar fallos temporales en objetos dependientes.

Para ciertos despliegues es preferible:

- Suspender el pipeline.
- Evitar reemplazos innecesarios.
- Usar `INSERT OVERWRITE` cuando sea apropiado.
- Reanudar y monitorizar la reinitialización.

---

## 18. Suspender al finalizar

Suspende la terminal:

```sql
ALTER DYNAMIC TABLE
    DB_CURSO.MARTS.DT_VENTAS_DIA_REGION
SUSPEND;
```

Suspende también la intermedia:

```sql
ALTER DYNAMIC TABLE
    DB_CURSO.CURATED.DT_VENTAS_PUBLICABLES
SUSPEND;
```

Suspende el warehouse:

```sql
ALTER WAREHOUSE WH_DEV SUSPEND;
```

Los resultados siguen siendo consultables:

```sql
SELECT *
FROM DB_CURSO.MARTS.DT_VENTAS_DIA_REGION
ORDER BY dia, region, canal;
```

Una Dynamic Table suspendida conserva almacenamiento, pero no ejecuta refrescos programados.

---

## 19. Limpieza opcional

No elimines los objetos si el siguiente laboratorio los va a reutilizar.

```sql
ALTER DYNAMIC TABLE IF EXISTS
    DB_CURSO.MARTS.DT_VENTAS_DIA_REGION
SUSPEND;

ALTER DYNAMIC TABLE IF EXISTS
    DB_CURSO.CURATED.DT_VENTAS_PUBLICABLES
SUSPEND;

DROP DYNAMIC TABLE IF EXISTS
    DB_CURSO.MARTS.DT_VENTAS_DIA_REGION;

DROP DYNAMIC TABLE IF EXISTS
    DB_CURSO.CURATED.DT_VENTAS_PUBLICABLES;

DROP TABLE IF EXISTS
    DB_CURSO.STAGING.VENTAS_DT_RAW;

DROP TABLE IF EXISTS
    DB_CURSO.CURATED.CLIENTES_DT;

ALTER SESSION UNSET QUERY_TAG;
```

---

## 20. Errores frecuentes

### La creación incremental falla

Comprueba:

- Que ambas fuentes tienen `CHANGE_TRACKING = TRUE`.
- Que el rol propietario de la Dynamic Table tiene acceso a las fuentes.
- Que `WH_DEV` existe y el rol tiene `USAGE`.
- Que la consulta utiliza construcciones compatibles con incremental.

No cambies directamente a `AUTO` sin investigar el motivo.

### La tabla intermedia no se refresca sola

Es correcto que no tenga un reloj independiente:

```text
TARGET_LAG = DOWNSTREAM
```

Necesita una Dynamic Table descendente activa con target lag temporal.

### La terminal no cambia exactamente al minuto

El target lag no es un cron.

Consulta:

```sql
DYNAMIC_TABLE_REFRESH_HISTORY
```

y comprueba el estado, duración y data timestamp.

### SHOW indica FULL

La definición o alguna función no es compatible con incremental, o la tabla se creó con otro modo.

Revisa la sentencia y recrea explícitamente con:

```sql
REFRESH_MODE = INCREMENTAL
```

La creación debería fallar en lugar de resolver a `FULL`.

### El refresco manual no incorpora los datos

Comprueba:

- Estado de planificación.
- Que la venta fuente está confirmada.
- Que el estado es `COMPLETADA`.
- Historial de errores.
- Privilegios del propietario.
- Que no recreaste una tabla fuente después de crear el pipeline.

### No aparecen columnas completas en `DYNAMIC_TABLES`

La función devuelve metadatos ampliados a roles con privilegio `MONITOR` o al propietario del objeto.

Utiliza el rol propietario, o concede el privilegio de monitorización adecuado.

---

## 21. Respuestas a las preguntas de reflexión

### 1. ¿Dynamic Table frente a view?

La view calcula al leer. La Dynamic Table materializa y refresca en segundo plano.

### 2. ¿Frente a materialized view?

La materialized view se orienta a acelerar una consulta sobre una tabla base. La Dynamic Table modela pipelines declarativos de varias etapas.

### 3. ¿Coste de reducir el lag?

Puede requerir refrescos más frecuentes y aumentar el consumo del warehouse.

### 4. ¿Por qué la terminal tiene lag temporal?

Porque impulsa el plan de refresco. Una cadena formada solo por tablas `DOWNSTREAM` no se actualiza automáticamente.

### 5. ¿Qué significa refresco atómico?

Los lectores ven el resultado anterior o el nuevo, nunca una versión parcialmente actualizada.

### 6. ¿Por qué no usarla para `MERGE` procedural?

La definición es una `SELECT` declarativa y la salida es de solo lectura.

### 7. ¿Qué monitorizar?

- Estado de planificación.
- Fallos.
- Lag real.
- Duración de refrescos.
- Filas o particiones modificadas.
- Warehouse usado.
- Créditos.
- Reinitializaciones.
- Cambios del modo de refresco.

---
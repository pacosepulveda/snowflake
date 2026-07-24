# Módulo 10 · Ejercicio 2

## Solución guiada: entornos DEV y QA con Zero-Copy Cloning

> **Compatibilidad:** cuenta trial Standard o Enterprise

---

## 1. Modelo utilizado

```text
Al crear el clone
PROD ───────────┐
                ├── comparte micro-partitions
DEV  ───────────┘

Después de escribir
PROD → crea sus propias micro-partitions nuevas
DEV  → crea sus propias micro-partitions nuevas
```

Zero-Copy evita una copia física inicial de las tablas estándar. No significa que los entornos permanezcan sin coste cuando empiezan a divergir.

---

# Parte 1. Preparar producción

## 2. Warehouse y privilegio para tasks

```sql
USE ROLE ACCOUNTADMIN;

GRANT EXECUTE TASK
ON ACCOUNT
TO ROLE SYSADMIN;

USE ROLE SYSADMIN;

CREATE WAREHOUSE IF NOT EXISTS WH_M10_CLONE
    WAREHOUSE_SIZE = XSMALL
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE;

USE WAREHOUSE WH_M10_CLONE;

ALTER SESSION SET QUERY_TAG = 'M10_E02_PREPARACION';
```

---

## 3. Limpiar ejecuciones anteriores

```sql
DROP DATABASE IF EXISTS DB_M10_DEV_FALLIDA;
DROP DATABASE IF EXISTS DB_M10_DEV_PRE_MIGRACION;
DROP DATABASE IF EXISTS DB_M10_QA_HISTORICO;
DROP DATABASE IF EXISTS DB_M10_DEV;
DROP DATABASE IF EXISTS DB_M10_PROD;

USE ROLE SECURITYADMIN;
DROP ROLE IF EXISTS M10_PROD_READER;
USE ROLE SYSADMIN;
```

---

## 4. Crear producción

Se utiliza un día de retención porque Standard Edition solo permite `0` o `1`.

```sql
CREATE DATABASE DB_M10_PROD
    DATA_RETENTION_TIME_IN_DAYS = 1
    COMMENT = 'Producción simulada para Zero-Copy Cloning';

CREATE SCHEMA DB_M10_PROD.CORE
    DATA_RETENTION_TIME_IN_DAYS = 1;

CREATE SCHEMA DB_M10_PROD.MARTS
    DATA_RETENTION_TIME_IN_DAYS = 1;

CREATE SCHEMA DB_M10_PROD.OPS
    DATA_RETENTION_TIME_IN_DAYS = 1;
```

---

## 5. Crear los pedidos

```sql
CREATE TABLE DB_M10_PROD.CORE.PEDIDOS (
    id_pedido       NUMBER(18,0),
    fecha_pedido    DATE,
    region          VARCHAR(20),
    importe         NUMBER(12,2),
    estado          VARCHAR(20),
    actualizado_en  TIMESTAMP_LTZ
);
```

```sql
INSERT INTO DB_M10_PROD.CORE.PEDIDOS
SELECT
    column1::NUMBER,
    column2::DATE,
    column3::VARCHAR,
    column4::NUMBER(12,2),
    column5::VARCHAR,
    CURRENT_TIMESTAMP()
FROM VALUES
    (20001, '2026-07-01', 'NORTE', 120.00, 'COMPLETADA'),
    (20002, '2026-07-01', 'SUR',   250.00, 'PENDIENTE'),
    (20003, '2026-07-02', 'ESTE',   80.00, 'COMPLETADA'),
    (20004, '2026-07-02', 'OESTE', 310.00, 'COMPLETADA'),
    (20005, '2026-07-03', 'NORTE', 150.00, 'CANCELADA'),
    (20006, '2026-07-03', 'SUR',    95.00, 'PENDIENTE');
```

---

## 6. Crear una vista local y otra fijada a PROD

### Vista local

La vista se crea en el mismo esquema que la tabla y utiliza un nombre no cualificado.

```sql
USE DATABASE DB_M10_PROD;
USE SCHEMA CORE;

CREATE VIEW V_PEDIDOS_LOCAL AS
SELECT
    COUNT(*) AS pedidos,
    SUM(importe)::NUMBER(20,2) AS importe_total
FROM PEDIDOS;
```

Al clonar toda la base, la copia de esta vista puede resolver `PEDIDOS` dentro de `DB_M10_DEV.CORE`.

### Vista fijada a producción

```sql
CREATE VIEW DB_M10_PROD.MARTS.V_PEDIDOS_PROD AS
SELECT
    COUNT(*) AS pedidos,
    SUM(importe)::NUMBER(20,2) AS importe_total
FROM DB_M10_PROD.CORE.PEDIDOS;
```

La definición contiene explícitamente el nombre de producción y lo conserva en el clone.

> En la versión original, una vista en `MARTS` que utilizaba `CORE.PEDIDOS` se consideraba portable. Esa referencia ya incluye el esquema y Snowflake conserva las referencias almacenadas durante la clonación. Para demostrar de forma inequívoca una referencia local se utiliza una vista en el mismo esquema con `FROM PEDIDOS`.

---

## 7. Crear el stream

Se crea después de las seis filas iniciales:

```sql
CREATE STREAM DB_M10_PROD.OPS.PEDIDOS_STREAM
ON TABLE DB_M10_PROD.CORE.PEDIDOS;
```

Inserta un cambio pendiente:

```sql
INSERT INTO DB_M10_PROD.CORE.PEDIDOS
VALUES (
    20007,
    '2026-07-04',
    'NORTE',
    75.00,
    'PENDIENTE',
    CURRENT_TIMESTAMP()
);
```

Comprueba:

```sql
SELECT
    COUNT(*) AS pedidos,
    SUM(importe) AS importe_total
FROM DB_M10_PROD.CORE.PEDIDOS;
```

Resultado:

```text
7
1080.00
```

El stream debe mostrar el pedido nuevo:

```sql
SELECT
    id_pedido,
    METADATA$ACTION,
    METADATA$ISUPDATE
FROM DB_M10_PROD.OPS.PEDIDOS_STREAM;
```

Un `SELECT` no consume el stream.

---

## 8. Crear y reanudar la task

```sql
CREATE TABLE DB_M10_PROD.OPS.TASK_LOG (
    ejecutado_en   TIMESTAMP_LTZ,
    base_contexto  VARCHAR,
    pedidos        NUMBER
);
```

La task utiliza referencias explícitas a PROD. Esto permite observar por qué debe revisarse antes de reanudar un clone.

```sql
CREATE TASK DB_M10_PROD.OPS.TASK_AUDITAR_PEDIDOS
    WAREHOUSE = WH_M10_CLONE
    SCHEDULE = '1440 MINUTES'
AS
INSERT INTO DB_M10_PROD.OPS.TASK_LOG
SELECT
    CURRENT_TIMESTAMP(),
    CURRENT_DATABASE(),
    COUNT(*)
FROM DB_M10_PROD.CORE.PEDIDOS;
```

Reanuda:

```sql
ALTER TASK DB_M10_PROD.OPS.TASK_AUDITAR_PEDIDOS RESUME;
```

Comprueba:

```sql
SHOW TASKS LIKE 'TASK_AUDITAR_PEDIDOS'
IN SCHEMA DB_M10_PROD.OPS
->>
SELECT
    "database_name",
    "name",
    "state",
    "schedule"
FROM $1;
```

No es necesario esperar a su ejecución.

---

## 9. Crear el rol lector

```sql
USE ROLE SECURITYADMIN;

CREATE ROLE M10_PROD_READER;

GRANT USAGE
ON DATABASE DB_M10_PROD
TO ROLE M10_PROD_READER;

GRANT USAGE
ON SCHEMA DB_M10_PROD.CORE
TO ROLE M10_PROD_READER;

GRANT SELECT
ON TABLE DB_M10_PROD.CORE.PEDIDOS
TO ROLE M10_PROD_READER;

USE ROLE SYSADMIN;
```

---

# Parte 2. Crear y revisar DEV

## 10. Clonar la base

```sql
CREATE DATABASE DB_M10_DEV
CLONE DB_M10_PROD;
```

Zero-Copy crea nuevos objetos lógicos y comparte inicialmente las micro-partitions de las tablas.

Valida:

```sql
SELECT
    COUNT(*) AS pedidos,
    SUM(importe) AS importe_total
FROM DB_M10_DEV.CORE.PEDIDOS;
```

Resultado:

```text
7
1080.00
```

---

## 11. Comprobar la task clonada

```sql
SHOW TASKS LIKE 'TASK_AUDITAR_PEDIDOS'
IN SCHEMA DB_M10_DEV.OPS
->>
SELECT
    "database_name",
    "name",
    "state"
FROM $1;
```

Resultado:

```text
STATE = suspended
```

Las tasks incluidas en un clone actual de una base o esquema quedan suspendidas por defecto.

Comprueba además su definición:

```sql
SELECT GET_DDL(
    'TASK',
    'DB_M10_DEV.OPS.TASK_AUDITAR_PEDIDOS'
);
```

La definición continúa mencionando `DB_M10_PROD`. Por eso no debe reanudarse sin corregirla.

Suspende la task de producción:

```sql
ALTER TASK DB_M10_PROD.OPS.TASK_AUDITAR_PEDIDOS SUSPEND;
```

---

## 12. Comprobar los streams

```sql
SELECT COUNT(*) AS cambios_prod
FROM DB_M10_PROD.OPS.PEDIDOS_STREAM;

SELECT COUNT(*) AS cambios_dev
FROM DB_M10_DEV.OPS.PEDIDOS_STREAM;
```

Resultado esperado:

```text
PROD = 1
DEV  = 0
```

Los cambios no consumidos anteriores al clone no quedan accesibles como backlog del stream clonado. El seguimiento del clone comienza desde el punto de clonación.

---

## 13. Comprobar los grants

Usa `SECURITYADMIN` para revisar todos los grants:

```sql
USE ROLE SECURITYADMIN;

SHOW GRANTS
ON TABLE DB_M10_DEV.CORE.PEDIDOS;
```

Debe aparecer el grant `SELECT` para `M10_PROD_READER`.

Ahora revisa el contenedor:

```sql
SHOW GRANTS
ON DATABASE DB_M10_DEV;
```

El grant `USAGE` de `DB_M10_PROD` no se transfiere al nuevo database.

Concédelo:

```sql
GRANT USAGE
ON DATABASE DB_M10_DEV
TO ROLE M10_PROD_READER;

GRANT USAGE
ON SCHEMA DB_M10_DEV.CORE
TO ROLE M10_PROD_READER;

USE ROLE SYSADMIN;
```

Regla:

```text
Clone de database o schema
    → conserva grants de los objetos hijos
    → no conserva los grants del propio contenedor
```

---

## 14. Modificar DEV

```sql
UPDATE DB_M10_DEV.CORE.PEDIDOS
SET
    importe = 260.00,
    actualizado_en = CURRENT_TIMESTAMP()
WHERE id_pedido = 20002;
```

```sql
INSERT INTO DB_M10_DEV.CORE.PEDIDOS
VALUES (
    29999,
    '2026-07-05',
    'TEST',
    1.00,
    'TEST',
    CURRENT_TIMESTAMP()
);
```

Compara:

```sql
SELECT
    'PROD' AS entorno,
    COUNT(*) AS pedidos,
    SUM(importe) AS importe_total
FROM DB_M10_PROD.CORE.PEDIDOS

UNION ALL

SELECT
    'DEV',
    COUNT(*),
    SUM(importe)
FROM DB_M10_DEV.CORE.PEDIDOS;
```

Resultado:

```text
PROD  7  1080.00
DEV   8  1091.00
```

Los cambios de DEV no afectan a PROD.

---

## 15. Modificar PROD

Guarda primero un punto histórico:

```sql
SET TS_PROD_ANTES_CAMBIO = CURRENT_TIMESTAMP();

CALL SYSTEM$WAIT(2);
```

Inserta:

```sql
INSERT INTO DB_M10_PROD.CORE.PEDIDOS
VALUES (
    20008,
    '2026-07-05',
    'SUR',
    400.00,
    'COMPLETADA',
    CURRENT_TIMESTAMP()
);
```

Compara:

```sql
SELECT
    'PROD' AS entorno,
    COUNT(*) AS pedidos,
    SUM(importe) AS importe_total
FROM DB_M10_PROD.CORE.PEDIDOS

UNION ALL

SELECT
    'DEV',
    COUNT(*),
    SUM(importe)
FROM DB_M10_DEV.CORE.PEDIDOS;
```

Resultado:

```text
PROD  8  1480.00
DEV   8  1091.00
```

---

## 16. Comprobar las vistas de DEV

```sql
SELECT
    'LOCAL' AS vista,
    *
FROM DB_M10_DEV.CORE.V_PEDIDOS_LOCAL

UNION ALL

SELECT
    'FIJADA_A_PROD',
    *
FROM DB_M10_DEV.MARTS.V_PEDIDOS_PROD;
```

Resultado:

```text
LOCAL          8  1091.00
FIJADA_A_PROD  8  1480.00
```

Inspecciona las definiciones:

```sql
SELECT GET_DDL(
    'VIEW',
    'DB_M10_DEV.CORE.V_PEDIDOS_LOCAL'
);

SELECT GET_DDL(
    'VIEW',
    'DB_M10_DEV.MARTS.V_PEDIDOS_PROD'
);
```

La referencia explícita a `DB_M10_PROD` se conserva y rompe el aislamiento.

---

# Parte 3. QA histórico y rollback

## 17. Crear QA desde el pasado

```sql
CREATE DATABASE DB_M10_QA_HISTORICO
CLONE DB_M10_PROD
AT (
    TIMESTAMP =>
        $TS_PROD_ANTES_CAMBIO::TIMESTAMP_LTZ
);
```

Valida:

```sql
SELECT
    COUNT(*) AS pedidos,
    SUM(importe) AS importe_total
FROM DB_M10_QA_HISTORICO.CORE.PEDIDOS;
```

Resultado:

```text
7
1080.00
```

Producción actual permanece en:

```text
8
1480.00
```

### Tasks en un clone histórico

```sql
SHOW TASKS IN DATABASE DB_M10_QA_HISTORICO;
```

No debe aparecer la task. Las user tasks no se incluyen en clones creados mediante Time Travel.

Esto diferencia:

```text
Clone actual
    → task clonada y suspendida

Clone histórico
    → task no incluida
```

---

## 18. Crear el snapshot pre-migración

```sql
CREATE DATABASE DB_M10_DEV_PRE_MIGRACION
CLONE DB_M10_DEV;
```

Valida:

```sql
SELECT
    COUNT(*) AS pedidos,
    SUM(importe) AS importe_total
FROM DB_M10_DEV_PRE_MIGRACION.CORE.PEDIDOS;
```

Resultado:

```text
8
1091.00
```

El snapshot es otro clone actual, por lo que su task existe pero queda suspendida.

---

## 19. Ejecutar la migración fallida

Añade la columna:

```sql
ALTER TABLE DB_M10_DEV.CORE.PEDIDOS
ADD COLUMN importe_migrado NUMBER(12,2);
```

Introduce el error:

```sql
UPDATE DB_M10_DEV.CORE.PEDIDOS
SET
    importe = importe * 10,
    importe_migrado = importe * 10,
    actualizado_en = CURRENT_TIMESTAMP()
WHERE region = 'SUR';
```

Elimina una vista necesaria:

```sql
DROP VIEW DB_M10_DEV.CORE.V_PEDIDOS_LOCAL;
```

Valida:

```sql
SELECT
    COUNT(*) AS pedidos,
    SUM(importe) AS importe_total
FROM DB_M10_DEV.CORE.PEDIDOS;
```

Resultado:

```text
8
4286.00
```

El cálculo es:

```text
1091
+ incremento de 260 a 2600 = 2340
+ incremento de 95 a 950   = 855
= 4286
```

Comprueba que la vista ya no existe:

```sql
SHOW VIEWS LIKE 'V_PEDIDOS_LOCAL'
IN SCHEMA DB_M10_DEV.CORE;
```

---

## 20. Recuperar el entorno completo

Conserva temporalmente el entorno defectuoso:

```sql
ALTER DATABASE DB_M10_DEV
RENAME TO DB_M10_DEV_FALLIDA;
```

Crea un nuevo DEV desde el snapshot:

```sql
CREATE DATABASE DB_M10_DEV
CLONE DB_M10_DEV_PRE_MIGRACION;
```

Reasigna el acceso al contenedor:

```sql
USE ROLE SECURITYADMIN;

GRANT USAGE
ON DATABASE DB_M10_DEV
TO ROLE M10_PROD_READER;

GRANT USAGE
ON SCHEMA DB_M10_DEV.CORE
TO ROLE M10_PROD_READER;

USE ROLE SYSADMIN;
```

---

## 21. Validar el rollback

Datos:

```sql
SELECT
    COUNT(*) AS pedidos,
    SUM(importe) AS importe_total
FROM DB_M10_DEV.CORE.PEDIDOS;
```

Resultado:

```text
8
1091.00
```

Vista:

```sql
SELECT *
FROM DB_M10_DEV.CORE.V_PEDIDOS_LOCAL;
```

Columna:

```sql
SHOW COLUMNS LIKE 'IMPORTE_MIGRADO'
IN TABLE DB_M10_DEV.CORE.PEDIDOS;
```

No debe devolver filas.

Task:

```sql
SHOW TASKS IN DATABASE DB_M10_DEV
->>
SELECT
    "name",
    "state"
FROM $1;
```

Debe aparecer suspendida.

Elimina el entorno fallido:

```sql
DROP DATABASE DB_M10_DEV_FALLIDA;
```

---

## 22. Efecto sobre el stream

```sql
SELECT COUNT(*) AS cambios_pendientes
FROM DB_M10_DEV.OPS.PEDIDOS_STREAM;
```

No debe utilizarse el stream clonado como copia del backlog del entorno anterior.

En una recuperación por reclonado debe existir un plan para:

- Recrear streams cuando sea necesario.
- Reanudar desde una marca de agua.
- Reconciliar las tablas de destino.
- Reprocesar eventos desde el sistema de origen.

---

# Parte 4. Interpretación

## 23. Runbook resumido

| Situación | Acción |
|---|---|
| Crear DEV | `CREATE DATABASE ... CLONE` |
| Vista que apunta a PROD | Recrear la vista con referencias de DEV |
| Task clonada | Revisar `GET_DDL` antes de reanudar |
| Stream clonado | No asumir que conserva el backlog |
| Grants del contenedor | Conceder `USAGE` explícitamente |
| Migración fallida | Renombrar y reclonar el snapshot |
| Reproducir el pasado | Clone histórico con Time Travel |
| Clone antiguo | Validar utilidad y eliminarlo |

---

## 24. Coste y copy-on-write

Al crear el clone:

- Las tablas comparten micro-partitions.
- Cada tabla tiene identidad y ciclo de vida propios.
- No se duplica inicialmente todo el almacenamiento.

Después de los cambios:

- DEV posee las nuevas micro-partitions generadas por su DML.
- PROD posee las nuevas micro-partitions generadas por su DML.
- Las partes sin cambios continúan compartidas.
- Time Travel y clones antiguos pueden obligar a conservar bytes históricos.

Por eso Zero-Copy no significa almacenamiento gratuito e ilimitado.

---

# Ampliación opcional

## 25. Consultar grupos de clones

Las métricas requieren `ACCOUNTADMIN` y pueden tardar entre una y dos horas en actualizarse.

```sql
USE ROLE ACCOUNTADMIN;
```

Producción:

```sql
SELECT
    'PROD' AS entorno,
    id,
    clone_group_id,
    active_bytes,
    time_travel_bytes,
    failsafe_bytes,
    retained_for_clone_bytes
FROM DB_M10_PROD.INFORMATION_SCHEMA.TABLE_STORAGE_METRICS
WHERE table_schema = 'CORE'
  AND table_name = 'PEDIDOS';
```

Desarrollo:

```sql
SELECT
    'DEV' AS entorno,
    id,
    clone_group_id,
    active_bytes,
    time_travel_bytes,
    failsafe_bytes,
    retained_for_clone_bytes
FROM DB_M10_DEV.INFORMATION_SCHEMA.TABLE_STORAGE_METRICS
WHERE table_schema = 'CORE'
  AND table_name = 'PEDIDOS';
```

Snapshot:

```sql
SELECT
    'SNAPSHOT' AS entorno,
    id,
    clone_group_id,
    active_bytes,
    time_travel_bytes,
    failsafe_bytes,
    retained_for_clone_bytes
FROM DB_M10_DEV_PRE_MIGRACION
    .INFORMATION_SCHEMA.TABLE_STORAGE_METRICS
WHERE table_schema = 'CORE'
  AND table_name = 'PEDIDOS';
```

Cada tabla tiene un `ID` distinto, pero las relacionadas mediante clones comparten un `CLONE_GROUP_ID`.

`RETAINED_FOR_CLONE_BYTES` representa bytes que deben conservarse porque algún clone todavía los referencia; no todos los bytes compartidos aparecen automáticamente en esa columna.

```sql
USE ROLE SYSADMIN;
```

---

# Finalización

## 26. Limpiar y detener

```sql
DROP DATABASE DB_M10_QA_HISTORICO;
DROP DATABASE DB_M10_DEV_PRE_MIGRACION;
```

Asegura que las tasks actuales quedan suspendidas:

```sql
ALTER TASK IF EXISTS
    DB_M10_PROD.OPS.TASK_AUDITAR_PEDIDOS
SUSPEND;

ALTER TASK IF EXISTS
    DB_M10_DEV.OPS.TASK_AUDITAR_PEDIDOS
SUSPEND;
```

Elimina el rol temporal:

```sql
USE ROLE SECURITYADMIN;

DROP ROLE IF EXISTS M10_PROD_READER;

USE ROLE SYSADMIN;
```

Restaura la sesión y suspende el warehouse:

```sql
ALTER SESSION UNSET QUERY_TAG;

ALTER WAREHOUSE WH_M10_CLONE SUSPEND;
```

Conserva:

```text
DB_M10_PROD
DB_M10_DEV
```

---

# Referencias oficiales

- [Cloning considerations](https://docs.snowflake.com/en/user-guide/object-clone)
- [CREATE ... CLONE](https://docs.snowflake.com/en/sql-reference/sql/create-clone)
- [Understanding and using Time Travel](https://docs.snowflake.com/en/user-guide/data-time-travel)
- [Introduction to streams](https://docs.snowflake.com/en/user-guide/streams-intro)
- [Access control best practices](https://docs.snowflake.com/en/user-guide/security-access-control-considerations)
- [TABLE_STORAGE_METRICS](https://docs.snowflake.com/en/sql-reference/info-schema/table_storage_metrics)

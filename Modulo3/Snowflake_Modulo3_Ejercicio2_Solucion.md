# Módulo 3 - Ejercicio 2 - Solución guiada

## Cachés y concurrencia: acelerar lecturas sin perder consistencia

**Cuenta prevista:** Snowflake Trial, edición Enterprise  
**Interfaz:** Snowsight  
**Fecha de validación documental:** 16 de julio de 2026

---

## 1. Qué vamos a demostrar

Este laboratorio tiene dos bloques relacionados con la arquitectura interna de Snowflake.

En el primero diferenciaremos dos cachés:

```text
                         CLOUD SERVICES
                   ┌──────────────────────┐
                   │ Persisted result     │
                   │ RESULT CACHE         │
                   │ Resultado ya creado  │
                   └──────────┬───────────┘
                              │
                     Puede evitar ejecutar
                              │
                              ▼
                  ┌────────────────────────┐
                  │ WH_M3_ANALITICA        │
                  │ WAREHOUSE CACHE        │
                  │ Datos en SSD local     │
                  └───────────┬────────────┘
                              │
                    Reduce lecturas remotas
                              │
                              ▼
                  SNOWFLAKE MANAGED STORAGE
```

En el segundo utilizaremos dos sesiones para observar el aislamiento transaccional:

```text
SESIÓN A                                  SESIÓN B
BEGIN                                     BEGIN
UPDATE stock 100 → 90                     SELECT stock → 100
sin COMMIT                                no ve datos sin confirmar

COMMIT                                    SELECT stock → 90
                                          cada sentencia usa datos confirmados
```

Después provocaremos un conflicto controlado entre dos escritores sobre el mismo producto.

---

## 2. Compatibilidad con la cuenta trial y la versión actual

El ejercicio es compatible con una cuenta trial actual porque utiliza únicamente:

- Virtual warehouses creados por el usuario.
- Tablas Snowflake normales y transitorias.
- Consultas SQL y operaciones DML.
- Parámetros de sesión.
- Transacciones explícitas.
- Query History y Query Profile.
- Dos sesiones de Snowsight abiertas por el mismo usuario.

### Control del coste

El warehouse es `XSMALL` y ya dispone de `AUTO_SUSPEND`.

Aun así, este ejercicio arranca el warehouse varias veces. Snowflake aplica un mínimo de facturación al aprovisionar recursos de un warehouse, por lo que no conviene repetir innecesariamente las fases de suspensión y reanudación.

---

# Parte A - Result cache y caché local del warehouse

## 3. Crear el SQL File y establecer el contexto

Crea un SQL File llamado:

`M3_E2_CACHE_Y_CONCURRENCIA_A`

Ejecuta:

```sql
USE ROLE SYSADMIN;
USE WAREHOUSE WH_M3_ANALITICA;
USE DATABASE DB_CURSO;
USE SCHEMA ARQUITECTURA;

SELECT
    CURRENT_USER()       AS USUARIO,
    CURRENT_ROLE()       AS ROL,
    CURRENT_WAREHOUSE()  AS WAREHOUSE,
    CURRENT_DATABASE()   AS BASE_DATOS,
    CURRENT_SCHEMA()     AS ESQUEMA,
    CURRENT_VERSION()    AS VERSION_SNOWFLAKE,
    CURRENT_SESSION()    AS ID_SESION;
```

El resultado debería mostrar:

```text
ROL        = SYSADMIN
WAREHOUSE  = WH_M3_ANALITICA
BASE_DATOS = DB_CURSO
ESQUEMA    = ARQUITECTURA
```

`CURRENT_VERSION()` permite registrar la versión efectiva que Snowflake sirve a la cuenta. Snowflake utiliza entrega continua, por lo que no se instala ni selecciona manualmente una versión del motor.

---

## 4. Comprobar el conjunto de datos de partida

Ejecuta:

```sql
SELECT
    COUNT(*)   AS FILAS,
    MIN(FECHA) AS FECHA_MINIMA,
    MAX(FECHA) AS FECHA_MAXIMA
FROM DB_CURSO.ARQUITECTURA.VENTAS_ARQ;
```

Resultado esperado:

```text
FILAS = 5.000.000
```

Si la tabla no existe, completa primero el ejercicio 1 del módulo 3.

---

## 5. Crear una copia transitoria para las pruebas

Ejecuta:

```sql
ALTER SESSION SET QUERY_TAG = 'M3_E2_PREPARACION';

CREATE OR REPLACE TRANSIENT TABLE DB_CURSO.ARQUITECTURA.M3_CACHE_VENTAS AS
SELECT *
FROM DB_CURSO.ARQUITECTURA.VENTAS_ARQ;
```

Comprueba la copia:

```sql
SELECT
    COUNT(*)   AS FILAS,
    MIN(FECHA) AS FECHA_MINIMA,
    MAX(FECHA) AS FECHA_MAXIMA,
    COUNT(DISTINCT REGION) AS REGIONES,
    COUNT(DISTINCT CANAL)  AS CANALES
FROM DB_CURSO.ARQUITECTURA.M3_CACHE_VENTAS;
```

El número de filas debe coincidir con `VENTAS_ARQ`.

### Por qué creamos otra tabla

Durante la prueba invalidaremos un resultado mediante `UPDATE`.

Es preferible modificar una tabla de laboratorio para:

- No alterar el conjunto de datos principal.
- Poder repetir el ejercicio.
- Eliminar todos los cambios al final mediante `DROP TABLE`.

La tabla es transitoria porque sus datos son recreables y no necesitan Fail-safe.

### Consultar metadatos básicos

Puedes ejecutar:

```sql
SHOW TABLES LIKE 'M3_CACHE_VENTAS' IN SCHEMA DB_CURSO.ARQUITECTURA;
```

En Snowsight también puedes abrir:

```text
Horizon Catalog » Catalog » Database Esplorer » DB_CURSO » ARQUITECTURA » M3_CACHE_VENTAS
```

---

## 6. Definir la consulta de prueba del result cache

Utilizaremos exactamente esta consulta en las tres ejecuciones:

```sql
SELECT
    'M3_E2_RESULT_CACHE' AS PRUEBA,
    REGION,
    COUNT(*)             AS NUM_VENTAS,
    SUM(UNIDADES)        AS TOTAL_UNIDADES,
    SUM(IMPORTE)         AS TOTAL_IMPORTE
FROM DB_CURSO.ARQUITECTURA.M3_CACHE_VENTAS
WHERE FECHA BETWEEN '2025-01-01'::DATE AND '2025-03-31'::DATE
GROUP BY REGION
ORDER BY REGION;
```

### Por qué es reutilizable

La consulta es determinista:

- Utiliza fechas literales.
- No genera números aleatorios.
- No consulta la hora actual.
- No incluye funciones externas.
- Devuelve el mismo resultado mientras los datos permanezcan sin cambios.

La documentación indica que para la reutilización exacta importa el texto de la consulta. Cambiar mayúsculas, alias o incluso introducir otras diferencias sintácticas puede impedir el 100 % de reutilización.

Por esa razón, copia y ejecuta siempre el mismo bloque.

---

## 7. Primera ejecución: cálculo real

Desactiva la reutilización de resultados:

```sql
ALTER SESSION SET USE_CACHED_RESULT = FALSE;
ALTER SESSION SET QUERY_TAG = 'M3_E2_RESULT_CACHE';
```

Ejecuta la consulta:

```sql
SELECT
    'M3_E2_RESULT_CACHE' AS PRUEBA,
    REGION,
    COUNT(*)             AS NUM_VENTAS,
    SUM(UNIDADES)        AS TOTAL_UNIDADES,
    SUM(IMPORTE)         AS TOTAL_IMPORTE
FROM DB_CURSO.ARQUITECTURA.M3_CACHE_VENTAS
WHERE FECHA BETWEEN '2025-01-01'::DATE AND '2025-03-31'::DATE
GROUP BY REGION
ORDER BY REGION;
```

Captura el Query ID inmediatamente:

```sql
SET QID_RC_1 = (SELECT LAST_QUERY_ID());

SELECT $QID_RC_1 AS QID_PRIMERA_EJECUCION;
```

### Qué significa `USE_CACHED_RESULT = FALSE`

La consulta no podrá servirse mediante la reutilización de un resultado persistido anterior.

Esto no significa que Snowflake deje de almacenar el nuevo resultado. El parámetro controla la reutilización, no la existencia general del mecanismo de resultados persistidos.

---

## 8. Segunda ejecución: permitir la reutilización

Activa de nuevo el mecanismo:

```sql
ALTER SESSION SET USE_CACHED_RESULT = TRUE;
```

Ejecuta el mismo bloque, sin editarlo:

```sql
SELECT
    'M3_E2_RESULT_CACHE' AS PRUEBA,
    REGION,
    COUNT(*)             AS NUM_VENTAS,
    SUM(UNIDADES)        AS TOTAL_UNIDADES,
    SUM(IMPORTE)         AS TOTAL_IMPORTE
FROM DB_CURSO.ARQUITECTURA.M3_CACHE_VENTAS
WHERE FECHA BETWEEN '2025-01-01'::DATE AND '2025-03-31'::DATE
GROUP BY REGION
ORDER BY REGION;
```

Guarda el segundo Query ID:

```sql
SET QID_RC_2 = (SELECT LAST_QUERY_ID());

SELECT $QID_RC_2 AS QID_SEGUNDA_EJECUCION;
```

---

## 9. Comparar las dos ejecuciones en Query History

Ejecuta:

```sql
SELECT
    QUERY_ID,
    QUERY_TAG,
    WAREHOUSE_NAME,
    EXECUTION_STATUS,
    TOTAL_ELAPSED_TIME,
    COMPILATION_TIME,
    EXECUTION_TIME,
    BYTES_SCANNED,
    ROWS_PRODUCED,
    START_TIME,
    END_TIME
FROM TABLE(
    DB_CURSO.INFORMATION_SCHEMA.QUERY_HISTORY_BY_SESSION(
        SESSION_ID => CURRENT_SESSION()::INT,
        RESULT_LIMIT => 200
    )
)
WHERE QUERY_ID IN ($QID_RC_1, $QID_RC_2)
ORDER BY START_TIME;
```

### Patrón esperado

La segunda ejecución debería mostrar evidencias compatibles con la reutilización:

- Mucho menor tiempo total o de ejecución.
- `BYTES_SCANNED` igual a cero o muy inferior.
- Query Profile sin un plan normal de escaneo y agregación, o con una indicación equivalente a reutilización del resultado.

No utilices únicamente la duración como prueba.

Los tiempos pueden verse afectados por:

- Aprovisionamiento del warehouse.
- Carga del sistema.
- Compilación.
- Red y cliente.
- Tamaño del resultado.

La evidencia más sólida combina Query History y Query Profile.

### Revisar Query Profile

En Snowsight:

1. Abre **Monitoring » Query History**.
2. Busca `$QID_RC_1` y `$QID_RC_2`.
3. Abre cada ejecución.
4. Compara la pestaña **Query Profile**.

En la primera deberías observar operadores como:

```text
TableScan → Aggregate → Sort → Result
```

En la segunda Snowflake puede indicar que reutilizó un resultado anterior y no mostrar una ejecución normal del plan.

---

## 10. Invalidar el resultado mediante DML

La generación del ejercicio anterior asigna la fecha `2025-01-01` al identificador 367. Podemos verificarlo:

```sql
SELECT ID_VENTA, FECHA, REGION, IMPORTE
FROM DB_CURSO.ARQUITECTURA.M3_CACHE_VENTAS
WHERE ID_VENTA = 367;
```

Actualiza esa fila:

```sql
ALTER SESSION SET QUERY_TAG = 'M3_E2_INVALIDACION_DML';

UPDATE DB_CURSO.ARQUITECTURA.M3_CACHE_VENTAS
SET IMPORTE = IMPORTE + 0.01
WHERE ID_VENTA = 367;
```

Comprueba que se modificó una fila.

Vuelve a asignar el tag de la prueba:

```sql
ALTER SESSION SET QUERY_TAG = 'M3_E2_RESULT_CACHE';
```

Ejecuta otra vez la consulta idéntica:

```sql
SELECT
    'M3_E2_RESULT_CACHE' AS PRUEBA,
    REGION,
    COUNT(*)             AS NUM_VENTAS,
    SUM(UNIDADES)        AS TOTAL_UNIDADES,
    SUM(IMPORTE)         AS TOTAL_IMPORTE
FROM DB_CURSO.ARQUITECTURA.M3_CACHE_VENTAS
WHERE FECHA BETWEEN '2025-01-01'::DATE AND '2025-03-31'::DATE
GROUP BY REGION
ORDER BY REGION;
```

Guarda el Query ID:

```sql
SET QID_RC_3 = (SELECT LAST_QUERY_ID());

SELECT $QID_RC_3 AS QID_TRAS_DML;
```

Compara las tres ejecuciones:

```sql
SELECT
    QUERY_ID,
    TOTAL_ELAPSED_TIME,
    COMPILATION_TIME,
    EXECUTION_TIME,
    BYTES_SCANNED,
    ROWS_PRODUCED,
    START_TIME
FROM TABLE(
    DB_CURSO.INFORMATION_SCHEMA.QUERY_HISTORY_BY_SESSION(
        SESSION_ID => CURRENT_SESSION()::INT,
        RESULT_LIMIT => 300
    )
)
WHERE QUERY_ID IN ($QID_RC_1, $QID_RC_2, $QID_RC_3)
ORDER BY START_TIME;
```

### Explicación

El resultado de la segunda consulta se calculó con un estado anterior de la tabla.

Después del `UPDATE`, devolver ese mismo resultado sería incorrecto. Snowflake debe ejecutar de nuevo la consulta y producir un nuevo resultado persistido.

El importe agregado de la región correspondiente debería aumentar en `0.01`.

Aunque un DML modifique una fila que no participara en el filtro, los cambios en las micro-particiones de una tabla pueden impedir la reutilización del resultado. En este caso hemos elegido deliberadamente una fila incluida en el intervalo para que también cambie el resultado funcional.

---

## 11. Preparar la prueba de caché local

Desactiva el result cache:

```sql
ALTER SESSION SET USE_CACHED_RESULT = FALSE;
ALTER SESSION SET QUERY_TAG = 'M3_E2_WAREHOUSE_CACHE';
```

Suspende el warehouse:

```sql
ALTER WAREHOUSE WH_M3_ANALITICA SUSPEND;
```

Comprueba el estado:

```sql
SHOW WAREHOUSES LIKE 'WH_M3_ANALITICA';
```

La columna `state` debería indicar `SUSPENDED`.

Vuelve a establecer el warehouse como contexto:

```sql
USE WAREHOUSE WH_M3_ANALITICA;
```

`USE WAREHOUSE` selecciona el warehouse, pero la siguiente consulta que necesite cómputo será la que provoque su reanudación si `AUTO_RESUME = TRUE`.

### Por qué suspendemos antes de la primera prueba

La documentación indica que la caché de datos local del warehouse se elimina al suspenderlo.

Así reducimos la posibilidad de que lecturas anteriores del ejercicio hayan dejado la tabla caliente en SSD local.

---

## 12. Primera ejecución con caché local fría

Utilizaremos esta consulta (no la ejecutes aún):

```sql
SELECT
    REGION,
    CANAL,
    COUNT(*)      AS NUM_VENTAS,
    SUM(UNIDADES) AS TOTAL_UNIDADES,
    SUM(IMPORTE)  AS TOTAL_IMPORTE
FROM DB_CURSO.ARQUITECTURA.M3_CACHE_VENTAS
GROUP BY REGION, CANAL
ORDER BY REGION, CANAL;
```

Ejecuta el bloque y guarda su ID:

```sql
SELECT
    REGION,
    CANAL,
    COUNT(*)      AS NUM_VENTAS,
    SUM(UNIDADES) AS TOTAL_UNIDADES,
    SUM(IMPORTE)  AS TOTAL_IMPORTE
FROM DB_CURSO.ARQUITECTURA.M3_CACHE_VENTAS
GROUP BY REGION, CANAL
ORDER BY REGION, CANAL;
```

```sql
SET QID_WC_1 = (SELECT LAST_QUERY_ID());
```

Esta consulta puede incluir tiempo de aprovisionamiento porque el warehouse estaba suspendido.

---

## 13. Segunda ejecución con el warehouse activo

Sin modificar la consulta ni suspender el warehouse, vuelve a ejecutarla:

```sql
SELECT
    REGION,
    CANAL,
    COUNT(*)      AS NUM_VENTAS,
    SUM(UNIDADES) AS TOTAL_UNIDADES,
    SUM(IMPORTE)  AS TOTAL_IMPORTE
FROM DB_CURSO.ARQUITECTURA.M3_CACHE_VENTAS
GROUP BY REGION, CANAL
ORDER BY REGION, CANAL;
```

Guarda el ID:

```sql
SET QID_WC_2 = (SELECT LAST_QUERY_ID());
```

Como `USE_CACHED_RESULT = FALSE`, Snowflake debe volver a ejecutar la consulta.

Sin embargo, el warehouse puede reutilizar bloques de datos que leyó durante la primera ejecución y mantiene en su caché local.

---

## 14. Tercera ejecución después de suspender

Suspende el warehouse:

```sql
ALTER WAREHOUSE WH_M3_ANALITICA SUSPEND;
SHOW WAREHOUSES LIKE 'WH_M3_ANALITICA';
```

Selecciona de nuevo el warehouse:

```sql
USE WAREHOUSE WH_M3_ANALITICA;
```

Ejecuta exactamente la misma consulta:

```sql
SELECT
    REGION,
    CANAL,
    COUNT(*)      AS NUM_VENTAS,
    SUM(UNIDADES) AS TOTAL_UNIDADES,
    SUM(IMPORTE)  AS TOTAL_IMPORTE
FROM DB_CURSO.ARQUITECTURA.M3_CACHE_VENTAS
GROUP BY REGION, CANAL
ORDER BY REGION, CANAL;
```

Guarda el ID:

```sql
SET QID_WC_3 = (SELECT LAST_QUERY_ID());
```

---

## 15. Comparar las tres ejecuciones

Consulta el historial inmediato:

```sql
SELECT
    QUERY_ID,
    WAREHOUSE_NAME,
    TOTAL_ELAPSED_TIME,
    COMPILATION_TIME,
    EXECUTION_TIME,
    QUEUED_PROVISIONING_TIME,
    BYTES_SCANNED,
    ROWS_PRODUCED,
    START_TIME
FROM TABLE(
    DB_CURSO.INFORMATION_SCHEMA.QUERY_HISTORY_BY_SESSION(
        SESSION_ID => CURRENT_SESSION()::INT,
        RESULT_LIMIT => 500
    )
)
WHERE QUERY_ID IN ($QID_WC_1, $QID_WC_2, $QID_WC_3)
ORDER BY START_TIME;
```

### Qué puede verse en esta función

La función de Information Schema proporciona datos casi inmediatos como:

- Tiempo total.
- Tiempo de compilación.
- Tiempo de ejecución.
- Tiempo de aprovisionamiento.
- Bytes escaneados.

No incluye todas las métricas que ofrece la vista `SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY`.

### Revisar el porcentaje de caché en Query Profile

Abre los tres Query ID desde **Monitoring » Query History**.

En Query Profile revisa las estadísticas del escaneo. Dependiendo de la versión de Snowsight, puedes encontrar campos equivalentes a:

- Bytes scanned.
- Percentage scanned from cache.
- Partitions scanned.
- Tiempo del operador de escaneo.

Patrón razonable:

```text
QID_WC_1  Caché fría + posible resume
QID_WC_2  Warehouse activo; mayor reutilización local
QID_WC_3  Caché local eliminada + nuevo resume
```

### No conviertas el patrón en una regla numérica rígida

No es obligatorio que:

- La segunda ejecución sea siempre mucho más rápida.
- El porcentaje de caché sea exactamente 100 %.
- La primera y la tercera sean idénticas.

Influyen:

- Tamaño comprimido de la tabla.
- Capacidad del warehouse.
- Datos que permanezcan en otras capas de caché gestionadas por Snowflake.
- Variación de carga.
- Aprovisionamiento.
- Optimización del plan.

Lo que sí está documentado es que la caché local del warehouse existe mientras está activo y se elimina al suspenderlo.

### Consulta opcional de Account Usage

La vista de Account Usage dispone de `PERCENTAGE_SCANNED_FROM_CACHE`, `PARTITIONS_SCANNED` y `PARTITIONS_TOTAL`, pero puede tener una latencia de hasta unos 45 minutos.

Por eso no debe ser el mecanismo obligatorio para validar el ejercicio en directo.

Un administrador podría consultar más tarde:

```sql
SELECT
    QUERY_ID,
    WAREHOUSE_NAME,
    TOTAL_ELAPSED_TIME,
    EXECUTION_TIME,
    BYTES_SCANNED,
    PERCENTAGE_SCANNED_FROM_CACHE * 100 AS PORCENTAJE_CACHE,
    PARTITIONS_SCANNED,
    PARTITIONS_TOTAL
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE QUERY_ID IN ($QID_WC_1, $QID_WC_2, $QID_WC_3)
ORDER BY START_TIME;
```

Esta consulta puede requerir `ACCOUNTADMIN` o un rol con acceso importado a la base `SNOWFLAKE`.

---

## 16. Conclusión de la Parte A

### Result cache

- Está gestionado por Cloud Services.
- Conserva el resultado final de una consulta.
- Puede evitar que el warehouse ejecute de nuevo el plan.
- El resultado expira normalmente después de 24 horas.
- Una reutilización renueva el periodo, con límites documentados.
- Requiere que sigan cumpliéndose las condiciones de seguridad, texto, configuración y datos.

### Warehouse cache

- Pertenece a los recursos de cómputo de un warehouse concreto.
- Conserva datos de tabla leídos durante ejecuciones anteriores.
- La consulta vuelve a ejecutar su plan.
- Puede reducir lecturas desde almacenamiento remoto.
- Se elimina cuando se suspende el warehouse.

### Diferencia esencial

```text
Result cache:
«No necesito ejecutar otra vez esta consulta; ya tengo el resultado».

Warehouse cache:
«Debo ejecutar la consulta, pero parte de los datos ya está cerca del cómputo».
```

---

# Parte B - Concurrencia transaccional y aislamiento

## 17. Crear la tabla de inventario

Desde la sesión A ejecuta:

```sql
ALTER SESSION SET USE_CACHED_RESULT = FALSE;
ALTER SESSION SET QUERY_TAG = 'M3_E2_MVCC_PREPARACION';

CREATE OR REPLACE TRANSIENT TABLE DB_CURSO.ARQUITECTURA.M3_INVENTARIO_MVCC (
    ID_PRODUCTO    NUMBER(10,0)   NOT NULL,
    PRODUCTO       VARCHAR(100)   NOT NULL,
    STOCK          NUMBER(10,0)   NOT NULL,
    ACTUALIZADO_EN TIMESTAMP_LTZ  NOT NULL
);

INSERT INTO DB_CURSO.ARQUITECTURA.M3_INVENTARIO_MVCC
    (ID_PRODUCTO, PRODUCTO, STOCK, ACTUALIZADO_EN)
VALUES
    (1, 'Portátil profesional', 100, CURRENT_TIMESTAMP()),
    (2, 'Monitor 27 pulgadas',   80, CURRENT_TIMESTAMP()),
    (3, 'Docking station',       60, CURRENT_TIMESTAMP());
```

Comprueba:

```sql
SELECT *
FROM DB_CURSO.ARQUITECTURA.M3_INVENTARIO_MVCC
ORDER BY ID_PRODUCTO;
```

Resultado inicial relevante:

```text
ID_PRODUCTO = 1
STOCK       = 100
```

---

## 18. Abrir y preparar la sesión B

Abre un segundo SQL File:

`M3_E2_CACHE_Y_CONCURRENCIA_B`

En la sesión B ejecuta:

```sql
USE ROLE SYSADMIN;
USE WAREHOUSE WH_M3_ANALITICA;
USE DATABASE DB_CURSO;
USE SCHEMA ARQUITECTURA;

ALTER SESSION SET USE_CACHED_RESULT = FALSE;
ALTER SESSION SET QUERY_TAG = 'M3_E2_SESION_B';

SELECT
    CURRENT_SESSION()   AS ID_SESION,
    CURRENT_WAREHOUSE() AS WAREHOUSE,
    CURRENT_ROLE()      AS ROL;
```

En la sesión A ejecuta:

```sql
SELECT CURRENT_SESSION() AS ID_SESION_A;
```

Los identificadores deben ser diferentes.

### Por qué hacen falta dos SQL Files

Una transacción pertenece a una única sesión.

Dos pestañas de Snowsight pueden utilizar sesiones distintas, lo que permite observar cambios confirmados y no confirmados desde dos contextos independientes.

No intentes ejecutar toda la Parte B seleccionando un único script. Debes alternar manualmente entre A y B.

---

## 19. Sesión A: abrir una transacción y actualizar

En la sesión A ejecuta solamente:

```sql
ALTER SESSION SET QUERY_TAG = 'M3_E2_A_CAMBIO_PENDIENTE';

BEGIN TRANSACTION;

UPDATE DB_CURSO.ARQUITECTURA.M3_INVENTARIO_MVCC
SET
    STOCK = STOCK - 10,
    ACTUALIZADO_EN = CURRENT_TIMESTAMP()
WHERE ID_PRODUCTO = 1;

SELECT
    ID_PRODUCTO,
    PRODUCTO,
    STOCK,
    ACTUALIZADO_EN
FROM DB_CURSO.ARQUITECTURA.M3_INVENTARIO_MVCC
WHERE ID_PRODUCTO = 1;
```

No ejecutes todavía `COMMIT`.

La sesión A debe devolver:

```text
STOCK = 90
```

### Por qué A ve 90

Una sentencia dentro de una transacción puede ver los cambios realizados por sentencias anteriores de esa misma transacción, aunque todavía no estén confirmados para otras sesiones.

---

## 20. Sesión B: leer mientras A mantiene el cambio pendiente

En la sesión B ejecuta:

```sql
ALTER SESSION SET QUERY_TAG = 'M3_E2_B_LECTURA_ANTES_COMMIT';

BEGIN TRANSACTION;

SELECT
    ID_PRODUCTO,
    PRODUCTO,
    STOCK,
    ACTUALIZADO_EN
FROM DB_CURSO.ARQUITECTURA.M3_INVENTARIO_MVCC
WHERE ID_PRODUCTO = 1;
```

Resultado esperado:

```text
STOCK = 100
```

### Qué demuestra

1. La lectura de B no debería esperar a que A confirme.
2. B no ve el valor 90 porque todavía no está confirmado.
3. B obtiene la versión confirmada anterior del dato.

Esto representa la parte más importante del modelo de versiones para cargas analíticas: una lectura consistente puede continuar mientras otra sesión escribe.

### Precisión terminológica

A veces se resume este comportamiento diciendo «Snowflake no usa bloqueos».

Esa frase es demasiado amplia.

La formulación más correcta es:

- Los lectores no necesitan esperar a los escritores para leer una versión confirmada.
- Las operaciones de escritura sí pueden adquirir bloqueos y entrar en conflicto con otras escrituras.

---

## 21. Sesión A: confirmar el cambio

En la sesión A ejecuta:

```sql
COMMIT;
```

Comprueba:

```sql
SELECT
    ID_PRODUCTO,
    STOCK,
    ACTUALIZADO_EN
FROM DB_CURSO.ARQUITECTURA.M3_INVENTARIO_MVCC
WHERE ID_PRODUCTO = 1;
```

Resultado:

```text
STOCK = 90
```

---

## 22. Sesión B: segunda lectura dentro de la misma transacción

Sin cerrar aún la transacción que B inició antes del `COMMIT` de A, ejecuta en B:

```sql
ALTER SESSION SET QUERY_TAG = 'M3_E2_B_LECTURA_DESPUES_COMMIT';

SELECT
    ID_PRODUCTO,
    PRODUCTO,
    STOCK,
    ACTUALIZADO_EN
FROM DB_CURSO.ARQUITECTURA.M3_INVENTARIO_MVCC
WHERE ID_PRODUCTO = 1;
```

Resultado esperado:

```text
STOCK = 90
```

Finaliza la transacción de B:

```sql
ROLLBACK;
```

No hay cambios que deshacer, pero cerramos explícitamente la transacción.

### Por qué B puede ver un valor diferente

Snowflake utiliza `READ COMMITTED`.

Cada sentencia ve:

- Datos confirmados antes de que comience esa sentencia.
- Cambios anteriores realizados por la propia transacción.

La transacción B no conserva obligatoriamente el mismo snapshot durante toda su vida.

Por eso:

```text
Primer SELECT de B  comenzó antes del COMMIT de A → ve 100
Segundo SELECT de B comenzó después del COMMIT de A → ve 90
```

Esto diferencia `READ COMMITTED` de un aislamiento que mantuviera un snapshot fijo durante toda la transacción.

### Posible demora entre sesiones

La documentación señala que cambios casi simultáneos entre sesiones pueden presentar una pequeña demora de consistencia con el modo de lectura predeterminado.

Si la segunda consulta de B devolviera brevemente 100:

1. Espera uno o dos segundos.
2. Ejecuta de nuevo el `SELECT`.
3. No cambies a `READ_CONSISTENCY_MODE = GLOBAL` para este laboratorio.

Lo habitual es que el valor confirmado sea visible inmediatamente o con una demora mínima.

---

## 23. Preparar el conflicto entre escritores

En la sesión A abre otra transacción:

```sql
ALTER SESSION SET QUERY_TAG = 'M3_E2_A_SEGUNDO_CAMBIO_PENDIENTE';

BEGIN TRANSACTION;

UPDATE DB_CURSO.ARQUITECTURA.M3_INVENTARIO_MVCC
SET
    STOCK = STOCK - 5,
    ACTUALIZADO_EN = CURRENT_TIMESTAMP()
WHERE ID_PRODUCTO = 1;
```

No confirmes ni reviertas todavía.

La sesión A ve temporalmente:

```text
STOCK = 85
```

La versión confirmada para las demás sesiones sigue siendo 90.

---

## 24. Sesión B: limitar la espera por bloqueo

En la sesión B ejecuta:

```sql
ALTER SESSION SET LOCK_TIMEOUT = 5;
ALTER SESSION SET QUERY_TAG = 'M3_E2_CONFLICTO_ESCRITORES';
```

`LOCK_TIMEOUT = 5` indica que la sentencia esperará como máximo cinco segundos al intentar adquirir un bloqueo.

El valor predeterminado documentado es mucho mayor, por lo que no conviene utilizarlo en un laboratorio.

Ejecuta **solo** esta sentencia:

```sql
UPDATE DB_CURSO.ARQUITECTURA.M3_INVENTARIO_MVCC
SET
    STOCK = STOCK - 1,
    ACTUALIZADO_EN = CURRENT_TIMESTAMP()
WHERE ID_PRODUCTO = 1;
```

### Resultado esperado

La sentencia debería:

1. Intentar modificar el mismo recurso que mantiene A.
2. Esperar aproximadamente hasta el límite configurado.
3. Fallar con un mensaje relacionado con bloqueo, timeout o transacción concurrente.

La redacción exacta del error puede variar.

Snowsight detiene la ejecución del conjunto seleccionado al encontrar un error. Por eso debes ejecutar el `UPDATE` de forma aislada.

### Obtener el historial después del error

Aunque la sentencia falle, queda registrada en Query History.

Ejecuta en B:

```sql
SELECT
    QUERY_ID,
    QUERY_TAG,
    EXECUTION_STATUS,
    ERROR_CODE,
    ERROR_MESSAGE,
    TOTAL_ELAPSED_TIME,
    EXECUTION_TIME,
    TRANSACTION_BLOCKED_TIME,
    TRANSACTION_ID,
    START_TIME,
    END_TIME
FROM TABLE(
    DB_CURSO.INFORMATION_SCHEMA.QUERY_HISTORY_BY_SESSION(
        SESSION_ID => CURRENT_SESSION()::INT,
        RESULT_LIMIT => 200
    )
)
WHERE QUERY_TAG = 'M3_E2_CONFLICTO_ESCRITORES'
ORDER BY START_TIME DESC;
```

El registro debería mostrar:

- Estado fallido.
- Mensaje de error.
- Tiempo bloqueado distinto de cero o compatible con la espera.
- Identificador de la transacción o de la sentencia.

---

## 25. Sesión A: liberar el recurso

En la sesión A ejecuta:

```sql
ROLLBACK;
```

La segunda reducción de cinco unidades queda cancelada.

Comprueba:

```sql
SELECT ID_PRODUCTO, STOCK
FROM DB_CURSO.ARQUITECTURA.M3_INVENTARIO_MVCC
WHERE ID_PRODUCTO = 1;
```

Resultado confirmado:

```text
STOCK = 90
```

---

## 26. Sesión B: repetir la escritura

En B cambia el tag:

```sql
ALTER SESSION SET QUERY_TAG = 'M3_E2_ESCRITOR_TRAS_LIBERACION';
```

Repite:

```sql
UPDATE DB_CURSO.ARQUITECTURA.M3_INVENTARIO_MVCC
SET
    STOCK = STOCK - 1,
    ACTUALIZADO_EN = CURRENT_TIMESTAMP()
WHERE ID_PRODUCTO = 1;
```

Como no existe una transacción explícita abierta y `AUTOCOMMIT` es `TRUE` por defecto, la sentencia se confirma automáticamente si tiene éxito.

Comprueba:

```sql
SELECT ID_PRODUCTO, STOCK, ACTUALIZADO_EN
FROM DB_CURSO.ARQUITECTURA.M3_INVENTARIO_MVCC
WHERE ID_PRODUCTO = 1;
```

Resultado esperado:

```text
STOCK = 89
```

---

## 27. Comparar la operación bloqueada y la operación correcta

En B ejecuta:

```sql
SELECT
    QUERY_ID,
    QUERY_TAG,
    EXECUTION_STATUS,
    ERROR_MESSAGE,
    TOTAL_ELAPSED_TIME,
    EXECUTION_TIME,
    TRANSACTION_BLOCKED_TIME,
    TRANSACTION_ID,
    START_TIME,
    END_TIME
FROM TABLE(
    DB_CURSO.INFORMATION_SCHEMA.QUERY_HISTORY_BY_SESSION(
        SESSION_ID => CURRENT_SESSION()::INT,
        RESULT_LIMIT => 300
    )
)
WHERE QUERY_TAG IN (
    'M3_E2_CONFLICTO_ESCRITORES',
    'M3_E2_ESCRITOR_TRAS_LIBERACION'
)
ORDER BY START_TIME;
```

### Interpretación

#### Primer `UPDATE`

- Compite con una modificación pendiente de A.
- No puede adquirir inmediatamente el recurso.
- Espera hasta `LOCK_TIMEOUT`.
- Termina con error.
- No modifica el stock confirmado.

#### Segundo `UPDATE`

- A ya ejecutó `ROLLBACK`.
- El recurso está disponible.
- La sentencia se ejecuta y confirma.
- El stock pasa de 90 a 89.

### Qué significa esto para MVCC

El modelo de versiones permite que B lea la versión 90 mientras A trabaja con una versión pendiente 85.

Pero si B intenta crear otra versión mediante `UPDATE` sobre el mismo recurso, Snowflake debe coordinar a los escritores para evitar resultados incoherentes.

Por eso:

```text
Lectura frente a escritura:
normalmente no bloqueante para el lector.

Escritura frente a escritura:
puede bloquear, esperar, reintentarse o fallar.
```

---

## 28. Relacionar la práctica con READ COMMITTED

La documentación actual establece que `READ COMMITTED` es el único nivel de aislamiento admitido para tablas Snowflake.

Sus efectos observados en el laboratorio son:

### No hay dirty reads

B no vio 90 mientras el primer cambio de A estaba sin confirmar.

### La propia transacción ve sus cambios

A sí vio 90 inmediatamente después de su `UPDATE`.

### No hay snapshot fijo para toda la transacción

B pudo ver 100 en su primer `SELECT` y 90 en el segundo, aunque ambos estuvieran dentro de la misma transacción.

### Los escritores pueden bloquearse

El segundo `UPDATE` de B no pudo competir libremente con el `UPDATE` pendiente de A.

---

## 29. Limpieza

### 29.1 Confirmar que no quedan transacciones abiertas

En ambas sesiones ejecuta preventivamente:

```sql
ROLLBACK;
```

Si no existe una transacción abierta, Snowflake no tendrá cambios que revertir.

### 29.2 Restaurar parámetros en la sesión A

```sql
ALTER SESSION SET USE_CACHED_RESULT = TRUE;
ALTER SESSION UNSET QUERY_TAG;
```

### 29.3 Restaurar parámetros en la sesión B

```sql
ALTER SESSION SET USE_CACHED_RESULT = TRUE;
ALTER SESSION UNSET LOCK_TIMEOUT;
ALTER SESSION UNSET QUERY_TAG;
```

`UNSET LOCK_TIMEOUT` elimina el override de la sesión y vuelve a aplicar el valor heredado.

### 29.4 Eliminar tablas del laboratorio

Desde A o B, con `SYSADMIN`:

```sql
DROP TABLE IF EXISTS DB_CURSO.ARQUITECTURA.M3_INVENTARIO_MVCC;
DROP TABLE IF EXISTS DB_CURSO.ARQUITECTURA.M3_CACHE_VENTAS;
```

No elimines `VENTAS_ARQ`.

### 29.5 Suspender el warehouse

```sql
ALTER WAREHOUSE WH_M3_ANALITICA SUSPEND;
SHOW WAREHOUSES LIKE 'WH_M3_ANALITICA';
```

El estado final debe ser:

```text
SUSPENDED
```

---

## 30. Script de referencia - Parte A

El siguiente bloque reúne las sentencias principales. No sustituye la revisión manual de Query Profile.

```sql
USE ROLE SYSADMIN;
USE WAREHOUSE WH_M3_ANALITICA;
USE DATABASE DB_CURSO;
USE SCHEMA ARQUITECTURA;

CREATE OR REPLACE TRANSIENT TABLE M3_CACHE_VENTAS AS
SELECT * FROM VENTAS_ARQ;

-- RESULT CACHE: ejecución real
ALTER SESSION SET USE_CACHED_RESULT = FALSE;
ALTER SESSION SET QUERY_TAG = 'M3_E2_RESULT_CACHE';

SELECT
    'M3_E2_RESULT_CACHE' AS PRUEBA,
    REGION,
    COUNT(*)             AS NUM_VENTAS,
    SUM(UNIDADES)        AS TOTAL_UNIDADES,
    SUM(IMPORTE)         AS TOTAL_IMPORTE
FROM DB_CURSO.ARQUITECTURA.M3_CACHE_VENTAS
WHERE FECHA BETWEEN '2025-01-01'::DATE AND '2025-03-31'::DATE
GROUP BY REGION
ORDER BY REGION;

SET QID_RC_1 = (SELECT LAST_QUERY_ID());

-- RESULT CACHE: posible reutilización
ALTER SESSION SET USE_CACHED_RESULT = TRUE;

SELECT
    'M3_E2_RESULT_CACHE' AS PRUEBA,
    REGION,
    COUNT(*)             AS NUM_VENTAS,
    SUM(UNIDADES)        AS TOTAL_UNIDADES,
    SUM(IMPORTE)         AS TOTAL_IMPORTE
FROM DB_CURSO.ARQUITECTURA.M3_CACHE_VENTAS
WHERE FECHA BETWEEN '2025-01-01'::DATE AND '2025-03-31'::DATE
GROUP BY REGION
ORDER BY REGION;

SET QID_RC_2 = (SELECT LAST_QUERY_ID());

-- Invalidar mediante DML
UPDATE DB_CURSO.ARQUITECTURA.M3_CACHE_VENTAS
SET IMPORTE = IMPORTE + 0.01
WHERE ID_VENTA = 367;

ALTER SESSION SET QUERY_TAG = 'M3_E2_RESULT_CACHE';

SELECT
    'M3_E2_RESULT_CACHE' AS PRUEBA,
    REGION,
    COUNT(*)             AS NUM_VENTAS,
    SUM(UNIDADES)        AS TOTAL_UNIDADES,
    SUM(IMPORTE)         AS TOTAL_IMPORTE
FROM DB_CURSO.ARQUITECTURA.M3_CACHE_VENTAS
WHERE FECHA BETWEEN '2025-01-01'::DATE AND '2025-03-31'::DATE
GROUP BY REGION
ORDER BY REGION;

SET QID_RC_3 = (SELECT LAST_QUERY_ID());

-- WAREHOUSE CACHE
ALTER SESSION SET USE_CACHED_RESULT = FALSE;
ALTER SESSION SET QUERY_TAG = 'M3_E2_WAREHOUSE_CACHE';
ALTER WAREHOUSE WH_M3_ANALITICA SUSPEND;
USE WAREHOUSE WH_M3_ANALITICA;

SELECT
    REGION,
    CANAL,
    COUNT(*)      AS NUM_VENTAS,
    SUM(UNIDADES) AS TOTAL_UNIDADES,
    SUM(IMPORTE)  AS TOTAL_IMPORTE
FROM DB_CURSO.ARQUITECTURA.M3_CACHE_VENTAS
GROUP BY REGION, CANAL
ORDER BY REGION, CANAL;

SET QID_WC_1 = (SELECT LAST_QUERY_ID());

SELECT
    REGION,
    CANAL,
    COUNT(*)      AS NUM_VENTAS,
    SUM(UNIDADES) AS TOTAL_UNIDADES,
    SUM(IMPORTE)  AS TOTAL_IMPORTE
FROM DB_CURSO.ARQUITECTURA.M3_CACHE_VENTAS
GROUP BY REGION, CANAL
ORDER BY REGION, CANAL;

SET QID_WC_2 = (SELECT LAST_QUERY_ID());

ALTER WAREHOUSE WH_M3_ANALITICA SUSPEND;
USE WAREHOUSE WH_M3_ANALITICA;

SELECT
    REGION,
    CANAL,
    COUNT(*)      AS NUM_VENTAS,
    SUM(UNIDADES) AS TOTAL_UNIDADES,
    SUM(IMPORTE)  AS TOTAL_IMPORTE
FROM DB_CURSO.ARQUITECTURA.M3_CACHE_VENTAS
GROUP BY REGION, CANAL
ORDER BY REGION, CANAL;

SET QID_WC_3 = (SELECT LAST_QUERY_ID());
```

---

## 31. Guion de coordinación - Parte B

Ejecuta las filas en este orden:

| Paso | Sesión A | Sesión B | Resultado esperado |
|---:|---|---|---|
| 1 | Crear tabla con stock 100 | Preparar contexto | Ambas sesiones listas |
| 2 | `BEGIN` + `UPDATE` a 90 | — | A ve 90 sin confirmar |
| 3 | Mantener abierta | `BEGIN` + `SELECT` | B ve 100 sin bloquearse |
| 4 | `COMMIT` | — | 90 queda confirmado |
| 5 | — | Segundo `SELECT` | B ve 90 |
| 6 | — | `ROLLBACK` | B cierra su transacción |
| 7 | `BEGIN` + `UPDATE` a 85 | — | A mantiene otra escritura |
| 8 | Mantener abierta | `LOCK_TIMEOUT=5` + `UPDATE` | B espera y falla |
| 9 | `ROLLBACK` | — | A libera el recurso; vuelve a 90 |
| 10 | — | Repetir `UPDATE` | B tiene éxito; stock 89 |

---

## 32. Errores frecuentes

### El segundo query no reutiliza el result cache

Posibles causas:

- El texto SQL no es exactamente igual.
- Cambió un alias, comentario, mayúscula o espacio relevante para la coincidencia.
- Se dejó `USE_CACHED_RESULT = FALSE`.
- Los datos cambiaron.
- La consulta utiliza una función no reutilizable.
- El resultado anterior no está disponible.
- Snowflake decidió no reutilizarlo aun cumpliéndose las condiciones; la documentación indica que las condiciones son necesarias, pero no una garantía absoluta.

Repite la fase desde la primera consulta con el bloque copiado exactamente.

### La segunda consulta de warehouse cache no es más rápida

No es necesariamente un error.

Revisa:

- Que el result cache estaba desactivado.
- Que el warehouse no se suspendió entre ambas.
- Las estadísticas de Query Profile.
- El porcentaje leído desde caché, cuando esté disponible.

La tabla puede caber ampliamente en la caché o ser tan pequeña que la diferencia temporal sea mínima.

### La sesión B ve 90 antes del COMMIT

Comprueba que:

- La sesión A no ejecutó `COMMIT` accidentalmente.
- El `UPDATE` se ejecutó dentro de un `BEGIN TRANSACTION` explícito.
- Las dos SQL Files usan sesiones distintas.
- No ejecutaste el script completo de A incluyendo un `COMMIT` posterior.

### La actualización de B permanece esperando demasiado

Configura antes:

```sql
ALTER SESSION SET LOCK_TIMEOUT = 5;
```

Si olvidaste hacerlo, cancela la consulta desde Query History y vuelve a intentarlo.

### B actualiza sin esperar

Comprueba que:

- A no ejecutó `COMMIT` o `ROLLBACK`.
- A modificó exactamente `ID_PRODUCTO = 1`.
- B intenta modificar el mismo producto.
- Las dos sesiones apuntan a la misma tabla totalmente cualificada.

### Aparece un error de transacción al limpiar

Puede existir una transacción abierta.

Ejecuta:

```sql
ROLLBACK;
```

Después realiza los `DROP TABLE`.

Recuerda que ejecutar DDL dentro de una transacción activa provoca un commit implícito de la transacción anterior. Por eso la limpieza debe hacerse después de cerrar explícitamente todas las transacciones.

---

## 33. Respuestas a las preguntas de reflexión

### 1. ¿Por qué no basta con comparar tiempos para demostrar el result cache?

Porque el tiempo depende también de aprovisionamiento, carga, compilación, red y tamaño del resultado. Debemos combinar duración, bytes escaneados y Query Profile.

### 2. ¿Por qué una diferencia en el SQL puede impedir la reutilización?

Snowflake busca una coincidencia del texto y de otras condiciones. Dos consultas lógicamente equivalentes no tienen por qué considerarse la misma ejecución reutilizable.

### 3. ¿Qué ocurre si dejamos el result cache activo al probar la caché local?

La segunda consulta podría no ejecutarse en el warehouse. En ese caso atribuiríamos erróneamente la mejora al SSD local, cuando en realidad Cloud Services devolvió el resultado final.

### 4. ¿Por qué suspender ahorra pero puede aumentar la latencia siguiente?

Al suspender se liberan recursos de cómputo y deja de consumirse mientras permanece apagado. Al reanudar hay tiempo de aprovisionamiento y la caché local debe reconstruirse.

### 5. ¿Dirty reads y snapshot fijo son lo mismo?

No. Evitar dirty reads significa no ver cambios sin confirmar. Mantener un snapshot fijo implicaría que todas las sentencias de la transacción ven el mismo estado, incluso después de commits externos. Snowflake usa `READ COMMITTED`, no un snapshot fijo para toda la transacción.

### 6. ¿Por qué dos `SELECT` de B pueden devolver valores diferentes?

Cada sentencia ve los datos confirmados antes de su propio inicio. El `COMMIT` de A ocurrió entre ambas.

### 7. ¿Qué concurrencia fue no bloqueante?

La lectura de B frente a la escritura pendiente de A. B pudo leer la versión confirmada anterior.

### 8. ¿Qué concurrencia produjo espera?

Dos escritores que intentaron modificar el mismo recurso.

### 9. ¿Por qué reducir `LOCK_TIMEOUT`?

El valor heredado puede permitir esperas muy largas. Un límite de cinco segundos hace el laboratorio seguro, predecible y fácil de repetir.

### 10. ¿Cómo equilibrar ahorro y caché para dashboards?

No existe una única cifra correcta. Un dashboard consultado frecuentemente puede beneficiarse de un auto-suspend menos agresivo para conservar la caché local. Una carga esporádica puede priorizar una suspensión rápida. La decisión debe basarse en patrones reales de consultas, latencia aceptable y coste.

---

## 34. Resumen final

Al terminar el ejercicio has demostrado cuatro comportamientos distintos:

```text
1. RESULT CACHE
   Puede entregar un resultado ya calculado sin ejecutar de nuevo el plan.

2. WAREHOUSE CACHE
   Puede acelerar una consulta que sí vuelve a ejecutarse.

3. READ COMMITTED
   Una sesión no ve cambios sin confirmar y cada sentencia puede ver
   nuevos commits realizados antes de su inicio.

4. COORDINACIÓN ENTRE ESCRITORES
   Dos operaciones DML sobre el mismo recurso pueden bloquearse;
   LOCK_TIMEOUT limita la espera.
```

Esta combinación explica por qué Snowflake puede ofrecer alta concurrencia analítica sin renunciar a la consistencia transaccional ni al control de coste.

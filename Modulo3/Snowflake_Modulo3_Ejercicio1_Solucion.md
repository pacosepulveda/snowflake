# Módulo 3 - Ejercicio 1 - Solución guiada

## Separación de almacenamiento y cómputo y ciclo de vida de una consulta

**Cuenta prevista:** Snowflake Trial, edición Enterprise  
**Interfaz:** Snowsight  

---

## 1. Resultado que vamos a construir

En este laboratorio crearemos una única tabla y la consultaremos mediante dos warehouses independientes:

```text
                       CLOUD SERVICES
        permisos · metadatos · compilación · optimización
                             │
               ┌─────────────┴─────────────┐
               │                           │
       WH_M3_ANALITICA              WH_M3_FINANZAS
       compute independiente        compute independiente
               │                           │
               └─────────────┬─────────────┘
                             │
                         STORAGE
            DB_CURSO.ARQUITECTURA.VENTAS_ARQ
                 5.000.000 de filas compartidas
```

También ejecutaremos dos consultas sobre la misma tabla:

- Un escaneo que cubre todo el periodo.
- Una consulta limitada a siete días.

Después utilizaremos Query History y Query Profile para observar:

- Qué warehouse ejecutó cada consulta.
- Cuánto se tardó en compilar y ejecutar.
- Cuántos bytes se escanearon.
- Cuántas micro-particiones se leyeron.
- Cómo el filtro por fecha permite aplicar pruning.

---

## 2. Compatibilidad con la cuenta trial y la versión actual

El ejercicio es compatible con una cuenta trial Enterprise actual porque utiliza únicamente:

- Bases de datos, esquemas y tablas Snowflake normales.
- Tablas transitorias.
- Virtual warehouses creados por el usuario.
- SQL estándar de Snowflake.
- La función de tabla `GENERATOR`.
- Parámetros de sesión.
- Query History de Information Schema.
- Query History y Query Profile de Snowsight.

Snowflake utiliza entrega continua. El alumno no selecciona una versión concreta del motor. El script consulta `CURRENT_VERSION()` para registrar la versión efectiva de la cuenta.

### Limitaciones que no afectan al ejercicio

Algunas funciones de red, continuidad entre regiones o servicios especializados pueden no estar disponibles en una cuenta trial o requerir otras ediciones. Este laboratorio no usa ninguna de ellas.

No se necesita:

- Replicación entre cuentas.
- Failover groups.
- PrivateLink.
- Integraciones con almacenamiento externo.
- Snowpipe.
- Snowpark.
- Servicios serverless.

---

## 3. Crear el SQL File

En Snowsight, crea un nuevo SQL File y llámalo:

`M3_E1_ARQUITECTURA_CONSULTA`

Ejecuta todo el ejercicio desde este SQL File y evita cerrar la pestaña antes de terminar.

Esto es importante porque vamos a utilizar:

- Variables de sesión.
- `LAST_QUERY_ID()`.
- `QUERY_HISTORY_BY_SESSION`.

Si abres otro SQL File, Snowflake puede crear otra sesión y las variables no estarán disponibles allí.

---

## 4. Establecer el contexto y registrar la versión

Ejecuta:

```sql
USE ROLE SYSADMIN;
USE DATABASE DB_CURSO;

SELECT
    CURRENT_USER()       AS USUARIO,
    CURRENT_ROLE()       AS ROL,
    CURRENT_DATABASE()   AS BASE_DATOS,
    CURRENT_REGION()     AS REGION,
    CURRENT_VERSION()    AS VERSION_SNOWFLAKE,
    CURRENT_SESSION()    AS ID_SESION;
```

### Qué estamos comprobando

- `CURRENT_USER()` identifica al usuario que ejecuta el laboratorio.
- `CURRENT_ROLE()` debe devolver `SYSADMIN`.
- `CURRENT_DATABASE()` debe devolver `DB_CURSO`.
- `CURRENT_REGION()` registra dónde está desplegada la cuenta.
- `CURRENT_VERSION()` registra la versión que Snowflake sirve en ese momento.
- `CURRENT_SESSION()` será útil para entender el alcance de `QUERY_HISTORY_BY_SESSION`.

Si `DB_CURSO` no existe, revisa el módulo 2. Como solución de emergencia puedes crearla con:

```sql
CREATE DATABASE IF NOT EXISTS DB_CURSO;
USE DATABASE DB_CURSO;
```

---

## 5. Crear los dos virtual warehouses

Ejecuta:

```sql
CREATE WAREHOUSE IF NOT EXISTS WH_M3_ANALITICA
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE;

CREATE WAREHOUSE IF NOT EXISTS WH_M3_FINANZAS
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE;
```

Comprueba su configuración:

```sql
SHOW WAREHOUSES LIKE 'WH_M3_%';
```

En el resultado deberías localizar dos filas.

Comprueba especialmente:

- `name`
- `state`
- `size`
- `auto_suspend`
- `auto_resume`

### Por qué utilizamos dos warehouses

Los dos warehouses representan dos cargas de trabajo independientes.

No son dos copias de la base de datos. Son dos conjuntos de recursos de cómputo que pueden:

- Arrancar y suspenderse por separado.
- Tener distinto tamaño.
- Ejecutar consultas simultáneamente.
- Mantener su propia caché local.
- Acceder al mismo almacenamiento persistente.

### Control del coste

Los warehouses se crean suspendidos y son `XSMALL`. Solo consumen créditos mientras están ejecutándose.

`AUTO_SUSPEND = 60` indica que Snowflake intentará suspenderlos después de un minuto de inactividad.

---

## 6. Crear el esquema del módulo

Activa el warehouse de Analítica y crea el esquema:

```sql
USE WAREHOUSE WH_M3_ANALITICA;

CREATE SCHEMA IF NOT EXISTS DB_CURSO.ARQUITECTURA;
USE SCHEMA DB_CURSO.ARQUITECTURA;
```

Comprueba el contexto:

```sql
SELECT
    CURRENT_WAREHOUSE() AS WAREHOUSE,
    CURRENT_DATABASE()  AS BASE_DATOS,
    CURRENT_SCHEMA()    AS ESQUEMA;
```

Resultado esperado:

```text
WH_M3_ANALITICA | DB_CURSO | ARQUITECTURA
```

---

## 7. Crear 5.000.000 de ventas sintéticas

Ejecuta este CTAS:

```sql
ALTER SESSION SET QUERY_TAG = 'M3_E1_CREACION_DATOS';

CREATE OR REPLACE TRANSIENT TABLE DB_CURSO.ARQUITECTURA.VENTAS_ARQ AS
WITH NUMEROS AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY SEQ4()) AS N
    FROM TABLE(GENERATOR(ROWCOUNT => 5000000))
)
SELECT
    N::NUMBER(18,0) AS ID_VENTA,

    DATEADD(
        DAY,
        MOD(N - 1, 730),
        '2024-01-01'::DATE
    )::DATE AS FECHA,

    CASE MOD(N, 6)
        WHEN 0 THEN 'NORTE'
        WHEN 1 THEN 'SUR'
        WHEN 2 THEN 'ESTE'
        WHEN 3 THEN 'OESTE'
        WHEN 4 THEN 'CENTRO'
        ELSE 'ISLAS'
    END::VARCHAR(10) AS REGION,

    CASE MOD(FLOOR((N - 1) / 6), 3)
        WHEN 0 THEN 'WEB'
        WHEN 1 THEN 'TIENDA'
        ELSE 'PARTNER'
    END::VARCHAR(10) AS CANAL,

    (1 + MOD(N, 5))::NUMBER(2,0) AS UNIDADES,

    ROUND(
        25 + MOD(N * 37, 497500) / 100,
        2
    )::NUMBER(12,2) AS IMPORTE

FROM NUMEROS
ORDER BY FECHA, ID_VENTA;
```

### Qué hace `GENERATOR`

`GENERATOR(ROWCOUNT => 5000000)` produce exactamente cinco millones de filas virtuales.

La función no genera por sí sola los valores de las columnas. Esos valores se construyen en la proyección mediante:

- `ROW_NUMBER()` para el identificador.
- `MOD()` para distribuir fechas, regiones, canales y unidades.
- Operaciones aritméticas deterministas para el importe.

### Por qué usamos `ROW_NUMBER()`

`SEQ4()` es adecuado para ordenar las filas generadas, pero la documentación advierte de que las funciones de secuencia pueden presentar huecos en algunos escenarios.

`ROW_NUMBER()` proporciona una numeración consecutiva de 1 a 5.000.000 para este resultado.

### Por qué la tabla es transitoria

La tabla se utiliza como conjunto reproducible de laboratorio.

Una tabla transitoria:

- Persiste entre sesiones.
- Puede consultarse desde ambos warehouses.
- No tiene Fail-safe.
- Es adecuada para datos recreables.

### Por qué ordenamos por fecha

Snowflake no almacena las filas como un fichero ordenado tradicional ni garantiza un orden al consultar sin `ORDER BY`.

Sin embargo, el orden de inserción puede favorecer que filas con fechas próximas terminen en micro-particiones con rangos de fechas relativamente acotados. Esto hace más visible el pruning cuando filtramos por fecha.

No estamos creando un índice.

---

## 8. Validar la tabla

Ejecuta:

```sql
SELECT
    COUNT(*)                 AS NUM_FILAS,
    MIN(FECHA)               AS FECHA_MINIMA,
    MAX(FECHA)               AS FECHA_MAXIMA,
    COUNT(DISTINCT REGION)   AS NUM_REGIONES,
    COUNT(DISTINCT CANAL)    AS NUM_CANALES,
    SUM(UNIDADES)            AS TOTAL_UNIDADES,
    SUM(IMPORTE)             AS IMPORTE_TOTAL
FROM DB_CURSO.ARQUITECTURA.VENTAS_ARQ;
```

Debes obtener:

```text
NUM_FILAS = 5000000
NUM_REGIONES = 6
NUM_CANALES = 3
```

La fecha mínima debe ser:

```text
2024-01-01
```

La fecha máxima debe encontrarse aproximadamente dos años después.

Comprueba además algunos registros:

```sql
SELECT *
FROM DB_CURSO.ARQUITECTURA.VENTAS_ARQ
ORDER BY ID_VENTA
LIMIT 10;
```

### Advertencia sobre `SELECT *`

Aquí se utiliza únicamente para inspeccionar diez filas.

En las consultas analíticas que compararemos después seleccionaremos solo las columnas necesarias para no confundir el análisis de column pruning.

---

## 9. Desactivar temporalmente el result cache

Ejecuta:

```sql
ALTER SESSION SET USE_CACHED_RESULT = FALSE;
```

Comprueba el parámetro:

```sql
SHOW PARAMETERS LIKE 'USE_CACHED_RESULT' IN SESSION;
```

El valor debe aparecer como `false`.

### Por qué hacemos esto

Snowflake puede reutilizar el resultado persistido de una consulta anterior cuando se cumplen las condiciones necesarias.

Si ejecutáramos exactamente el mismo SQL desde el segundo warehouse con el result cache habilitado, Snowflake podría devolver el resultado desde Cloud Services sin utilizar realmente el cómputo del segundo warehouse.

Eso sería muy eficiente en producción, pero impediría demostrar con claridad que ambos warehouses son capaces de procesar la consulta sobre el mismo almacenamiento.

### Qué no estamos desactivando

No estamos desactivando la caché local del warehouse.

Cada warehouse puede mantener en sus SSD locales datos leídos previamente mientras permanece activo. Esa caché se estudiará con más detalle en otro ejercicio.

---

## 10. Ejecutar la consulta de control con Analítica

Establece el contexto:

```sql
USE WAREHOUSE WH_M3_ANALITICA;

ALTER SESSION SET QUERY_TAG = 'M3_E1_CONTROL_ANALITICA';
```

Ejecuta la consulta:

```sql
SELECT
    COUNT(*)       AS NUM_VENTAS,
    SUM(UNIDADES)  AS TOTAL_UNIDADES,
    SUM(IMPORTE)   AS IMPORTE_TOTAL
FROM DB_CURSO.ARQUITECTURA.VENTAS_ARQ;
```

Inmediatamente después, conserva el Query ID:

```sql
SET QID_ANALITICA = LAST_QUERY_ID();
```

Comprueba la variable:

```sql
SELECT $QID_ANALITICA AS QID_ANALITICA;
```

### Importante sobre `LAST_QUERY_ID()`

Debes ejecutar el `SET` inmediatamente después de la consulta que quieres conservar.

Si ejecutas otra sentencia entre medias, `LAST_QUERY_ID()` puede referirse a esa sentencia intermedia.

---

## 11. Suspender Analítica

Ejecuta:

```sql
ALTER WAREHOUSE WH_M3_ANALITICA SUSPEND;
```

Comprueba el estado:

```sql
SHOW WAREHOUSES LIKE 'WH_M3_ANALITICA';
```

El estado debe terminar apareciendo como `SUSPENDED`.

### Qué ha ocurrido con los datos

Nada.

Suspender un warehouse libera los recursos de cómputo de ese warehouse. No elimina:

- La base de datos.
- El esquema.
- La tabla.
- Las micro-particiones.
- Los metadatos.

Los datos viven en la capa de almacenamiento, no dentro del warehouse.

---

## 12. Ejecutar la misma consulta con Finanzas

Cambia de warehouse:

```sql
USE WAREHOUSE WH_M3_FINANZAS;

ALTER SESSION SET QUERY_TAG = 'M3_E1_CONTROL_FINANZAS';
```

Ejecuta exactamente la misma consulta:

```sql
SELECT
    COUNT(*)       AS NUM_VENTAS,
    SUM(UNIDADES)  AS TOTAL_UNIDADES,
    SUM(IMPORTE)   AS IMPORTE_TOTAL
FROM DB_CURSO.ARQUITECTURA.VENTAS_ARQ;
```

Conserva su Query ID:

```sql
SET QID_FINANZAS = LAST_QUERY_ID();
```

Comprueba ambas variables:

```sql
SELECT
    $QID_ANALITICA AS QID_ANALITICA,
    $QID_FINANZAS  AS QID_FINANZAS;
```

### Resultado esperado

Los valores de negocio deben coincidir:

- Mismo número de ventas.
- Mismo total de unidades.
- Mismo importe total.

Los Query ID deben ser diferentes porque son dos ejecuciones independientes.

### Qué demuestra esta prueba

- La tabla no pertenece a `WH_M3_ANALITICA`.
- Los dos warehouses pueden leer el mismo almacenamiento.
- Suspender Analítica no impide que Finanzas consulte.
- El compute puede aislarse por equipo sin copiar los datos.

---

## 13. Consultar el historial de las dos ejecuciones

Ejecuta:

```sql
SELECT
    QUERY_ID,
    QUERY_TAG,
    WAREHOUSE_NAME,
    WAREHOUSE_SIZE,
    EXECUTION_STATUS,
    ROUND(TOTAL_ELAPSED_TIME / 1000, 3)      AS TOTAL_SEGUNDOS,
    ROUND(COMPILATION_TIME / 1000, 3)        AS COMPILACION_SEGUNDOS,
    ROUND(EXECUTION_TIME / 1000, 3)          AS EJECUCION_SEGUNDOS,
    ROUND(QUEUED_PROVISIONING_TIME / 1000, 3) AS APROVISIONAMIENTO_SEGUNDOS,
    BYTES_SCANNED,
    ROWS_PRODUCED,
    START_TIME,
    END_TIME
FROM TABLE(
    DB_CURSO.INFORMATION_SCHEMA.QUERY_HISTORY_BY_SESSION(
        RESULT_LIMIT => 100
    )
)
WHERE QUERY_ID = $QID_ANALITICA
   OR QUERY_ID = $QID_FINANZAS
ORDER BY START_TIME;
```

### Columnas principales

#### `QUERY_TAG`

Permite identificar la finalidad de la consulta sin depender solo del texto SQL.

#### `WAREHOUSE_NAME`

Debe mostrar:

```text
WH_M3_ANALITICA
WH_M3_FINANZAS
```

Esta es la evidencia directa de qué recurso de cómputo ejecutó cada consulta.

#### `COMPILATION_TIME`

Incluye trabajo previo a la ejecución, como análisis y preparación del plan. Conceptualmente se relaciona con Cloud Services.

No significa que todo el trabajo de Cloud Services quede resumido únicamente en esta columna.

#### `EXECUTION_TIME`

Representa el tiempo dedicado a ejecutar el plan. Para estas consultas, el trabajo principal se realiza en el virtual warehouse.

#### `QUEUED_PROVISIONING_TIME`

Puede ser mayor en la primera consulta ejecutada después de que un warehouse estuviera suspendido, porque Snowflake necesita reanudar o aprovisionar recursos.

#### `BYTES_SCANNED`

Indica el volumen leído por la sentencia.

No debe confundirse con el tamaño lógico de las filas devueltas.

#### `ROWS_PRODUCED`

La consulta agregada produce una sola fila, aunque haya procesado cinco millones de filas de entrada.

### Por qué los tiempos pueden ser distintos

Aunque los dos warehouses tengan el mismo tamaño y ejecuten el mismo SQL:

- Uno puede haber necesitado arrancar.
- Cada warehouse tiene su propia caché local.
- Puede haber variaciones normales de infraestructura.
- La compilación no siempre tarda exactamente lo mismo.
- El entorno es un servicio compartido y administrado.

No utilices una única ejecución para afirmar que un warehouse es más rápido que el otro.

---

## 14. Relacionar la prueba con las tres capas

### Cloud Services

Antes de ejecutar el plan, Snowflake debe realizar tareas como:

- Autenticar la sesión.
- Evaluar el rol y los privilegios.
- Resolver nombres de objetos.
- Analizar la sintaxis y la semántica.
- Consultar metadatos.
- Optimizar el plan.
- Registrar la consulta y sus métricas.

### Compute

El warehouse realiza operaciones como:

- Leer las micro-particiones necesarias.
- Procesar filas en paralelo.
- Agregar `COUNT`, `SUM(UNIDADES)` y `SUM(IMPORTE)`.
- Ensamblar el resultado de la ejecución.

### Storage

`VENTAS_ARQ` se almacena una sola vez en micro-particiones gestionadas por Snowflake.

Ambos warehouses acceden a esas mismas micro-particiones.

---

## 15. Ejecutar el escaneo amplio

Asegúrate de utilizar Finanzas:

```sql
USE WAREHOUSE WH_M3_FINANZAS;
```

Configura el tag:

```sql
ALTER SESSION SET QUERY_TAG = 'M3_E1_ESCANEO_AMPLIO';
```

Ejecuta:

```sql
SELECT
    CANAL,
    COUNT(*)       AS NUM_VENTAS,
    SUM(UNIDADES)  AS TOTAL_UNIDADES,
    SUM(IMPORTE)   AS IMPORTE_TOTAL
FROM DB_CURSO.ARQUITECTURA.VENTAS_ARQ
WHERE FECHA BETWEEN '2024-01-01'::DATE AND '2025-12-30'::DATE
GROUP BY CANAL
ORDER BY CANAL;
```

Conserva el Query ID:

```sql
SET QID_AMPLIO = LAST_QUERY_ID();
```

### Qué esperamos

El rango incluye prácticamente todo el periodo de la tabla.

El optimizador no podrá descartar muchas micro-particiones por el predicado de fecha, porque casi todas contienen fechas incluidas en el rango.

---

## 16. Ejecutar la consulta selectiva

Configura otro tag:

```sql
ALTER SESSION SET QUERY_TAG = 'M3_E1_ESCANEO_7_DIAS';
```

Ejecuta:

```sql
SELECT
    CANAL,
    COUNT(*)       AS NUM_VENTAS,
    SUM(UNIDADES)  AS TOTAL_UNIDADES,
    SUM(IMPORTE)   AS IMPORTE_TOTAL
FROM DB_CURSO.ARQUITECTURA.VENTAS_ARQ
WHERE FECHA BETWEEN '2025-06-01'::DATE AND '2025-06-07'::DATE
GROUP BY CANAL
ORDER BY CANAL;
```

Conserva el Query ID:

```sql
SET QID_7_DIAS = LAST_QUERY_ID();
```

Comprueba los dos identificadores:

```sql
SELECT
    $QID_AMPLIO AS QID_AMPLIO,
    $QID_7_DIAS AS QID_7_DIAS;
```

### Por qué mantenemos el resto del SQL igual

Queremos que la diferencia principal sea el filtro temporal.

Las dos consultas:

- Seleccionan las mismas columnas.
- Calculan las mismas agregaciones.
- Agrupan del mismo modo.
- Ordenan del mismo modo.

Así resulta más fácil atribuir la diferencia de lectura al rango de fechas.

---

## 17. Comparar ambas consultas mediante Query History

Ejecuta:

```sql
SELECT
    QUERY_ID,
    QUERY_TAG,
    WAREHOUSE_NAME,
    ROUND(TOTAL_ELAPSED_TIME / 1000, 3) AS TOTAL_SEGUNDOS,
    ROUND(COMPILATION_TIME / 1000, 3)   AS COMPILACION_SEGUNDOS,
    ROUND(EXECUTION_TIME / 1000, 3)     AS EJECUCION_SEGUNDOS,
    BYTES_SCANNED,
    ROWS_PRODUCED,
    START_TIME
FROM TABLE(
    DB_CURSO.INFORMATION_SCHEMA.QUERY_HISTORY_BY_SESSION(
        RESULT_LIMIT => 100
    )
)
WHERE QUERY_ID = $QID_AMPLIO
   OR QUERY_ID = $QID_7_DIAS
ORDER BY START_TIME;
```

### Interpretación esperada

Normalmente, la consulta de siete días debería:

- Escanear menos bytes.
- Ejecutarse en menos tiempo.
- Leer menos micro-particiones.

Sin embargo, no debes exigir una proporción exacta.

Los tiempos cortos son sensibles a:

- Arranque del warehouse.
- Caché local.
- Compilación.
- Variaciones de ejecución.
- Número real de micro-particiones creadas.

La evidencia más importante para el pruning será el número de particiones mostrado en Query Profile.

---

## 18. Localizar las consultas en Snowsight

Puedes utilizar cualquiera de estas rutas, según la navegación disponible en tu cuenta:

- El historial del propio SQL File (El reloj que aparece en la parte superior derecha de la ventana de resultados "Show query history").
- **Monitoring** y después **Query History**.
- El enlace de detalles que aparece tras ejecutar una consulta.

La interfaz de Snowsight evoluciona, pero el objetivo es abrir los detalles de una consulta mediante su Query ID.

Busca primero:

```text
$QID_AMPLIO
```

Después busca:

```text
$QID_7_DIAS
```

En cada consulta abre la pestaña o sección **Query Profile**.

---

## 19. Interpretar el plan de ejecución

El perfil puede presentar operadores como:

```text
TableScan → Aggregate → Sort → Result
```

El plan exacto puede variar.

### `TableScan`

Lee las columnas y micro-particiones necesarias de `VENTAS_ARQ`.

Selecciona este nodo para localizar estadísticas como:

- Bytes scanned.
- Partitions scanned.
- Partitions total.
- Percentage scanned from cache.

### `Aggregate`

Calcula:

- `COUNT(*)`
- `SUM(UNIDADES)`
- `SUM(IMPORTE)`

Además agrupa por `CANAL`.

### `Sort`

Aplica:

```sql
ORDER BY CANAL
```

Como solo se ordenan tres filas finales, no debería ser una operación costosa.

### `Result`

Representa la producción y devolución del resultado.

---

## 20. Registrar las estadísticas de pruning

Completa una tabla como esta con los valores reales de tu cuenta:

| Métrica | Escaneo amplio | Intervalo de 7 días |
|---|---:|---:|
| Bytes scanned | valor real | valor real |
| Partitions scanned | valor real | valor real |
| Partitions total | valor real | valor real |
| Porcentaje de particiones leído | calculado | calculado |
| Tiempo de ejecución | valor real | valor real |
| Porcentaje desde caché local | valor real | valor real |
| Operador más costoso | valor real | valor real |

Calcula:

```text
porcentaje leído = partitions scanned / partitions total × 100
```

Ejemplo puramente ilustrativo:

```text
Escaneo amplio: 38 / 40 × 100 = 95 %
Consulta 7 días: 2 / 40 × 100 = 5 %
```

No copies esos números como resultado. Tus valores dependerán de cómo Snowflake haya creado las micro-particiones.

### Evidencia de pruning

Existe evidencia clara de pruning cuando:

```text
Partitions scanned < Partitions total
```

La evidencia es más fuerte si la consulta de siete días escanea muchas menos particiones que la consulta amplia.

---

## 21. Qué es micro-partition pruning

Snowflake mantiene metadatos sobre las micro-particiones, incluidos rangos de valores.

Cuando una consulta contiene:

```sql
WHERE FECHA BETWEEN '2025-06-01' AND '2025-06-07'
```

el optimizador puede descartar una micro-partición si sus valores de fecha no pueden satisfacer ese predicado.

Por ejemplo, no necesita leer una partición cuyo rango sea:

```text
2024-01-01 a 2024-01-20
```

porque ninguna fila puede pertenecer a junio de 2025.

### No es un índice tradicional

El alumno no ha creado:

- B-tree.
- Índice bitmap.
- Índice manual sobre `FECHA`.

El pruning utiliza los metadatos mantenidos por Snowflake.

---

## 22. Column pruning

Las consultas analíticas seleccionan únicamente:

```text
FECHA
CANAL
UNIDADES
IMPORTE
```

No necesitan recuperar `ID_VENTA` ni `REGION`.

Como Snowflake utiliza almacenamiento columnar, el motor puede evitar leer columnas no requeridas.

Por eso evitamos:

```sql
SELECT *
```

El micro-partition pruning reduce particiones. El column pruning reduce columnas dentro de las particiones que sí se leen.

---

## 23. Respuestas razonadas a las preguntas finales

### 1. ¿Qué demuestra el uso de dos warehouses?

Demuestra que el cómputo está desacoplado del almacenamiento.

`WH_M3_ANALITICA` y `WH_M3_FINANZAS` son recursos de cómputo diferentes, pero ambos acceden a `VENTAS_ARQ` sin duplicarla.

### 2. ¿Por qué suspender un warehouse no elimina la tabla?

Porque el warehouse no almacena la copia persistente de los datos.

Al suspenderlo se liberan sus recursos de cómputo. La tabla permanece en la capa de almacenamiento gestionada por Snowflake.

### 3. ¿Qué operaciones pertenecen a Cloud Services?

Entre otras:

- Autenticación.
- Control de acceso.
- Resolución de objetos.
- Parsing.
- Análisis semántico.
- Optimización.
- Consulta de metadatos.
- Gestión del historial.

### 4. ¿Qué operaciones ejecuta el warehouse?

Entre otras:

- Lectura de micro-particiones.
- Procesamiento paralelo.
- Agregaciones.
- Intercambio de datos entre nodos cuando es necesario.
- Ordenación.

### 5. ¿Qué evidencia muestra que se aplicó pruning?

En Query Profile:

```text
Partitions scanned < Partitions total
```

Además, la consulta selectiva suele mostrar menos bytes escaneados que la amplia.

### 6. ¿Por qué el filtro de fecha evita leer parte de la tabla?

Porque Snowflake dispone de metadatos de rangos de valores por micro-partición.

Si el rango de una partición no se solapa con el intervalo solicitado, puede descartarla antes de leerla.

### 7. ¿Por qué desactivamos el result cache?

Para evitar que Snowflake devuelva una ejecución repetida directamente desde un resultado persistido.

Queríamos obligar a que las consultas de control utilizaran realmente los warehouses y generaran métricas de ejecución comparables.

### 8. ¿Por qué los valores varían entre alumnos?

Pueden variar por:

- Región y proveedor cloud.
- Versión desplegada.
- Forma concreta de las micro-particiones.
- Estado del warehouse.
- Caché local.
- Variaciones normales de infraestructura.
- Momento de ejecución.

El objetivo no es obtener una cifra exacta, sino observar relaciones coherentes.

---

## 24. Restaurar la sesión y suspender los warehouses

Restaura la configuración normal del result cache:

```sql
ALTER SESSION UNSET USE_CACHED_RESULT;
```

Elimina el query tag de la sesión:

```sql
ALTER SESSION UNSET QUERY_TAG;
```

Suspende los dos warehouses:

```sql
ALTER WAREHOUSE WH_M3_ANALITICA SUSPEND;
ALTER WAREHOUSE WH_M3_FINANZAS SUSPEND;
```

Comprueba el estado:

```sql
SHOW WAREHOUSES LIKE 'WH_M3_%';
```

Ambos deben quedar como:

```text
SUSPENDED
```

### No eliminar los objetos

Conserva:

```text
WH_M3_ANALITICA
WH_M3_FINANZAS
DB_CURSO.ARQUITECTURA.VENTAS_ARQ
```

Se reutilizarán en los ejercicios siguientes.

---

## 25. Script completo reproducible

El siguiente bloque reúne la parte SQL principal. Las operaciones manuales de Query Profile deben realizarse desde Snowsight.

```sql
-- =============================================================
-- MÓDULO 3 · EJERCICIO 1
-- Separación de almacenamiento y cómputo
-- =============================================================

-- 1. Contexto
USE ROLE SYSADMIN;
USE DATABASE DB_CURSO;

SELECT
    CURRENT_USER()       AS USUARIO,
    CURRENT_ROLE()       AS ROL,
    CURRENT_DATABASE()   AS BASE_DATOS,
    CURRENT_REGION()     AS REGION,
    CURRENT_VERSION()    AS VERSION_SNOWFLAKE,
    CURRENT_SESSION()    AS ID_SESION;

-- 2. Warehouses
CREATE WAREHOUSE IF NOT EXISTS WH_M3_ANALITICA
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE;

CREATE WAREHOUSE IF NOT EXISTS WH_M3_FINANZAS
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE;

SHOW WAREHOUSES LIKE 'WH_M3_%';

-- 3. Esquema
USE WAREHOUSE WH_M3_ANALITICA;
CREATE SCHEMA IF NOT EXISTS DB_CURSO.ARQUITECTURA;
USE SCHEMA DB_CURSO.ARQUITECTURA;

-- 4. Datos sintéticos
ALTER SESSION SET QUERY_TAG = 'M3_E1_CREACION_DATOS';

CREATE OR REPLACE TRANSIENT TABLE DB_CURSO.ARQUITECTURA.VENTAS_ARQ AS
WITH NUMEROS AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY SEQ4()) AS N
    FROM TABLE(GENERATOR(ROWCOUNT => 5000000))
)
SELECT
    N::NUMBER(18,0) AS ID_VENTA,
    DATEADD(
        DAY,
        MOD(N - 1, 730),
        '2024-01-01'::DATE
    )::DATE AS FECHA,
    CASE MOD(N, 6)
        WHEN 0 THEN 'NORTE'
        WHEN 1 THEN 'SUR'
        WHEN 2 THEN 'ESTE'
        WHEN 3 THEN 'OESTE'
        WHEN 4 THEN 'CENTRO'
        ELSE 'ISLAS'
    END::VARCHAR(10) AS REGION,
    CASE MOD(FLOOR((N - 1) / 6), 3)
        WHEN 0 THEN 'WEB'
        WHEN 1 THEN 'TIENDA'
        ELSE 'PARTNER'
    END::VARCHAR(10) AS CANAL,
    (1 + MOD(N, 5))::NUMBER(2,0) AS UNIDADES,
    ROUND(
        25 + MOD(N * 37, 497500) / 100,
        2
    )::NUMBER(12,2) AS IMPORTE
FROM NUMEROS
ORDER BY FECHA, ID_VENTA;

-- 5. Validación
SELECT
    COUNT(*)                 AS NUM_FILAS,
    MIN(FECHA)               AS FECHA_MINIMA,
    MAX(FECHA)               AS FECHA_MAXIMA,
    COUNT(DISTINCT REGION)   AS NUM_REGIONES,
    COUNT(DISTINCT CANAL)    AS NUM_CANALES,
    SUM(UNIDADES)            AS TOTAL_UNIDADES,
    SUM(IMPORTE)             AS IMPORTE_TOTAL
FROM DB_CURSO.ARQUITECTURA.VENTAS_ARQ;

-- 6. Desactivar result cache para las pruebas
ALTER SESSION SET USE_CACHED_RESULT = FALSE;

-- 7. Control con Analítica
USE WAREHOUSE WH_M3_ANALITICA;
ALTER SESSION SET QUERY_TAG = 'M3_E1_CONTROL_ANALITICA';

SELECT
    COUNT(*)       AS NUM_VENTAS,
    SUM(UNIDADES)  AS TOTAL_UNIDADES,
    SUM(IMPORTE)   AS IMPORTE_TOTAL
FROM DB_CURSO.ARQUITECTURA.VENTAS_ARQ;

SET QID_ANALITICA = LAST_QUERY_ID();

-- 8. Suspender Analítica
ALTER WAREHOUSE WH_M3_ANALITICA SUSPEND;

-- 9. Control con Finanzas
USE WAREHOUSE WH_M3_FINANZAS;
ALTER SESSION SET QUERY_TAG = 'M3_E1_CONTROL_FINANZAS';

SELECT
    COUNT(*)       AS NUM_VENTAS,
    SUM(UNIDADES)  AS TOTAL_UNIDADES,
    SUM(IMPORTE)   AS IMPORTE_TOTAL
FROM DB_CURSO.ARQUITECTURA.VENTAS_ARQ;

SET QID_FINANZAS = LAST_QUERY_ID();

-- 10. Historial de ambas consultas
SELECT
    QUERY_ID,
    QUERY_TAG,
    WAREHOUSE_NAME,
    WAREHOUSE_SIZE,
    EXECUTION_STATUS,
    ROUND(TOTAL_ELAPSED_TIME / 1000, 3)       AS TOTAL_SEGUNDOS,
    ROUND(COMPILATION_TIME / 1000, 3)         AS COMPILACION_SEGUNDOS,
    ROUND(EXECUTION_TIME / 1000, 3)           AS EJECUCION_SEGUNDOS,
    ROUND(QUEUED_PROVISIONING_TIME / 1000, 3) AS APROVISIONAMIENTO_SEGUNDOS,
    BYTES_SCANNED,
    ROWS_PRODUCED,
    START_TIME,
    END_TIME
FROM TABLE(
    DB_CURSO.INFORMATION_SCHEMA.QUERY_HISTORY_BY_SESSION(
        RESULT_LIMIT => 100
    )
)
WHERE QUERY_ID = $QID_ANALITICA
   OR QUERY_ID = $QID_FINANZAS
ORDER BY START_TIME;

-- 11. Escaneo amplio
ALTER SESSION SET QUERY_TAG = 'M3_E1_ESCANEO_AMPLIO';

SELECT
    CANAL,
    COUNT(*)       AS NUM_VENTAS,
    SUM(UNIDADES)  AS TOTAL_UNIDADES,
    SUM(IMPORTE)   AS IMPORTE_TOTAL
FROM DB_CURSO.ARQUITECTURA.VENTAS_ARQ
WHERE FECHA BETWEEN '2024-01-01'::DATE AND '2025-12-30'::DATE
GROUP BY CANAL
ORDER BY CANAL;

SET QID_AMPLIO = LAST_QUERY_ID();

-- 12. Escaneo selectivo
ALTER SESSION SET QUERY_TAG = 'M3_E1_ESCANEO_7_DIAS';

SELECT
    CANAL,
    COUNT(*)       AS NUM_VENTAS,
    SUM(UNIDADES)  AS TOTAL_UNIDADES,
    SUM(IMPORTE)   AS IMPORTE_TOTAL
FROM DB_CURSO.ARQUITECTURA.VENTAS_ARQ
WHERE FECHA BETWEEN '2025-06-01'::DATE AND '2025-06-07'::DATE
GROUP BY CANAL
ORDER BY CANAL;

SET QID_7_DIAS = LAST_QUERY_ID();

-- 13. Comparación en Query History
SELECT
    QUERY_ID,
    QUERY_TAG,
    WAREHOUSE_NAME,
    ROUND(TOTAL_ELAPSED_TIME / 1000, 3) AS TOTAL_SEGUNDOS,
    ROUND(COMPILATION_TIME / 1000, 3)   AS COMPILACION_SEGUNDOS,
    ROUND(EXECUTION_TIME / 1000, 3)     AS EJECUCION_SEGUNDOS,
    BYTES_SCANNED,
    ROWS_PRODUCED,
    START_TIME
FROM TABLE(
    DB_CURSO.INFORMATION_SCHEMA.QUERY_HISTORY_BY_SESSION(
        RESULT_LIMIT => 100
    )
)
WHERE QUERY_ID = $QID_AMPLIO
   OR QUERY_ID = $QID_7_DIAS
ORDER BY START_TIME;

-- 14. Limpieza operativa, sin borrar objetos
ALTER SESSION UNSET USE_CACHED_RESULT;
ALTER SESSION UNSET QUERY_TAG;

ALTER WAREHOUSE WH_M3_ANALITICA SUSPEND;
ALTER WAREHOUSE WH_M3_FINANZAS SUSPEND;

SHOW WAREHOUSES LIKE 'WH_M3_%';
```

---

## 26. Errores frecuentes y resolución

### Error: `Object 'DB_CURSO' does not exist`

La base de datos del módulo 2 no existe o el rol actual no puede verla.

Comprueba:

```sql
SHOW DATABASES LIKE 'DB_CURSO';
```

Usa `SYSADMIN` o crea la base de datos si el instructor lo autoriza.

### Error: `Insufficient privileges to operate on warehouse`

El rol actual no es propietario del warehouse ni tiene los privilegios necesarios.

Comprueba:

```sql
SELECT CURRENT_ROLE();
SHOW GRANTS ON WAREHOUSE WH_M3_ANALITICA;
```

Para el laboratorio utiliza `SYSADMIN` y crea los warehouses con ese rol.

### La creación de cinco millones de filas tarda demasiado

Comprueba que:

- El warehouse es `XSMALL` y está activo.
- No hay otras consultas pesadas ejecutándose en el mismo warehouse.
- No has repetido accidentalmente el CTAS varias veces.

No aumentes el tamaño sin indicación del instructor.

Si el CTAS falla por una interrupción, puedes volver a ejecutarlo porque utiliza `CREATE OR REPLACE`.

### `LAST_QUERY_ID()` no corresponde a la consulta deseada

Se ejecutó otra sentencia antes de guardar el identificador.

Repite la consulta objetivo y ejecuta inmediatamente:

```sql
SET QID_EJEMPLO = LAST_QUERY_ID();
```

### La consulta de historial no devuelve filas

Posibles causas:

- La variable contiene otro Query ID.
- La consulta se ejecutó en otro SQL File o sesión.
- Se cerró y reabrió el SQL File.
- Se escribió mal el nombre de la variable.

Comprueba:

```sql
SHOW VARIABLES;

SELECT *
FROM TABLE(
    DB_CURSO.INFORMATION_SCHEMA.QUERY_HISTORY_BY_SESSION(
        RESULT_LIMIT => 100
    )
)
ORDER BY START_TIME DESC;
```

### No encuentro Query Profile

La posición exacta depende de la versión de Snowsight.

Localiza la consulta mediante:

- El historial del SQL File.
- Query History en Activity o Monitoring.
- Su Query ID.

El perfil solo está disponible después de que la consulta haya finalizado correctamente y su detalle puede mostrarse con distintas disposiciones de interfaz.

### Las dos consultas escanean el mismo número de particiones

Comprueba:

1. Que analizaste los Query ID correctos.
2. Que una consulta cubre todo el periodo y la otra solo siete días.
3. Que la tabla se creó con el `ORDER BY FECHA, ID_VENTA` indicado.
4. Que la tabla contiene cinco millones de filas.

También puede ocurrir que la tabla tenga pocas micro-particiones o que la distribución física concreta reduzca la diferencia visible.

En ese caso documenta el resultado real y explica la limitación. No inventes métricas.

### El porcentaje leído desde caché local no es cero

`USE_CACHED_RESULT = FALSE` desactiva el result cache, no la caché local del warehouse.

Si el mismo warehouse ya leyó esas micro-particiones, puede reutilizarlas desde su SSD local.

Esto es correcto y no invalida el análisis de pruning.

### Un warehouse vuelve a aparecer iniciado después de suspenderlo

Si el warehouse tiene `AUTO_RESUME = TRUE`, cualquier consulta posterior que lo utilice puede reanudarlo.

Comprueba el warehouse actual antes de ejecutar consultas:

```sql
SELECT CURRENT_WAREHOUSE();
```

---

## 27. Comprobación final

El laboratorio queda completado cuando puedes afirmar, con evidencias, que:

```text
✓ Existe una única tabla de 5.000.000 de filas.
✓ Dos warehouses independientes pueden consultarla.
✓ Suspender uno no afecta al almacenamiento.
✓ Query History atribuye cada consulta a su warehouse.
✓ Se distinguen compilación y ejecución.
✓ Query Profile muestra el plan de ejecución.
✓ El filtro de siete días permite descartar micro-particiones.
✓ El result cache se restauró.
✓ Los dos warehouses quedaron suspendidos.
```

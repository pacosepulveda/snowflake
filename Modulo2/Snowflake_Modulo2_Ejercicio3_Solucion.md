# Módulo 2 - Ejercicio 3 - Solución guiada

## Diagnóstico operativo y trazabilidad de consultas en Snowflake

**Cuenta prevista:** Snowflake Trial, edición Enterprise  
**Interfaz:** Snowsight  

---

## 1. Resultado del ejercicio

En este laboratorio no construiremos un nuevo modelo de datos. Aprenderemos a diagnosticar una sesión y a reconstruir lo ocurrido mediante este flujo:

```text
Etiquetar la sesión
        ↓
Comprobar el contexto
        ↓
Reproducir un fallo del warehouse
        ↓
Diagnosticar y corregir
        ↓
Reproducir un fallo de resolución de objetos
        ↓
Diagnosticar y corregir
        ↓
Recuperar resultados anteriores
        ↓
Consultar Query History
        ↓
Restaurar configuración y suspender
```

Los dos errores esperados serán:

1. Consulta de detalle rechazada porque `WH_LAB_M2` está suspendido, `AUTO_RESUME` está desactivado y no se permite reutilizar un resultado almacenado.
2. Objeto no encontrado o no autorizado porque el nombre corto `VENTAS` se resuelve dentro de `STAGING` en vez de `CURATED`.

---

## 2. Crear el SQL File

1. Accede a Snowsight.
2. Crea un SQL File.
3. Ponle el nombre `M2_E3_DIAGNOSTICO_TRAZABILIDAD`.
4. Ejecuta cada bloque por separado, especialmente los bloques que deben fallar.

No selecciones todo el script y lo ejecutes como una única operación. Un error esperado podría detener o dificultar la interpretación de los pasos posteriores.

---

## 3. Seleccionar el rol y etiquetar la sesión

Selecciona el rol administrativo de objetos:

```sql
USE ROLE SYSADMIN;
```

Configura el query tag:

```sql
ALTER SESSION SET QUERY_TAG = 'M2_E3_DIAGNOSTICO';
```

Comprueba el valor:

```sql
SHOW PARAMETERS LIKE 'QUERY_TAG';
```

En la cuadrícula de resultados debes encontrar una fila cuyo valor sea:

```text
M2_E3_DIAGNOSTICO
```

### Qué es `QUERY_TAG`

`QUERY_TAG` es un parámetro de sesión. Snowflake copia su valor al registro de cada consulta y sentencia SQL ejecutada posteriormente en esa sesión.

Es útil para:

- Identificar las consultas de un curso o laboratorio.
- Relacionar consultas con una aplicación, pipeline o equipo.
- Filtrar Query History.
- Analizar consumo y rendimiento por carga de trabajo.

El tag no cambia los permisos ni la ejecución de la consulta. Solo añade contexto de observabilidad.

---

## 4. Registrar y fijar el contexto de sesión

Antes de cambiar nada, consulta el contexto recibido por el SQL File:

```sql
SELECT
    CURRENT_USER()            AS USUARIO_ACTUAL,
    CURRENT_ROLE()            AS ROL_ACTUAL,
    CURRENT_SECONDARY_ROLES() AS ROLES_SECUNDARIOS,
    CURRENT_WAREHOUSE()       AS WAREHOUSE_ACTUAL,
    CURRENT_DATABASE()        AS BASE_DATOS_ACTUAL,
    CURRENT_SCHEMA()          AS ESQUEMA_ACTUAL,
    CURRENT_SESSION()         AS ID_SESION,
    CURRENT_VERSION()         AS VERSION_SNOWFLAKE;
```

Los valores pueden variar según la configuración de la cuenta y lo seleccionado previamente en Snowsight.

Fija ahora el contexto esperado:

```sql
USE ROLE SYSADMIN;
USE WAREHOUSE WH_LAB_M2;
USE DATABASE DB_CURSO;
USE SCHEMA CURATED;
```

Compruébalo de nuevo:

```sql
SELECT
    CURRENT_USER()            AS USUARIO_ACTUAL,
    CURRENT_ROLE()            AS ROL_ACTUAL,
    CURRENT_SECONDARY_ROLES() AS ROLES_SECUNDARIOS,
    CURRENT_WAREHOUSE()       AS WAREHOUSE_ACTUAL,
    CURRENT_DATABASE()        AS BASE_DATOS_ACTUAL,
    CURRENT_SCHEMA()          AS ESQUEMA_ACTUAL,
    CURRENT_SESSION()         AS ID_SESION,
    CURRENT_VERSION()         AS VERSION_SNOWFLAKE;
```

Resultado lógico esperado:

| Elemento | Valor esperado |
|---|---|
| Rol | `SYSADMIN` |
| Warehouse | `WH_LAB_M2` |
| Base de datos | `DB_CURSO` |
| Esquema | `CURATED` |

### Por qué conviene fijar el contexto

Un SQL File puede conservar o recibir selecciones anteriores. Si una consulta utiliza nombres no cualificados, el contexto determina dónde busca Snowflake el objeto.

Esta instrucción:

```sql
SELECT * FROM VENTAS;
```

se interpreta utilizando la base de datos y el esquema activos.

Esta otra no depende del esquema activo:

```sql
SELECT * FROM DB_CURSO.CURATED.VENTAS;
```

---

## 5. Comprobar los prerrequisitos

Ejecuta:

```sql
SHOW TABLES LIKE 'VENTAS' IN SCHEMA DB_CURSO.CURATED;
SHOW WAREHOUSES LIKE 'WH_LAB_M2';
```

También puedes verificar los datos:

```sql
SELECT COUNT(*) AS NUMERO_VENTAS
FROM DB_CURSO.CURATED.VENTAS;
```

Con los datos del ejercicio 1, el resultado esperado es:

```text
8
```

Si la tabla o el warehouse no existen, completa primero los ejercicios anteriores.

---

## 6. Procesar un comando `SHOW` con `RESULT_SCAN`

Ejecuta el comando `SHOW`:

```sql
SHOW WAREHOUSES LIKE 'WH_LAB_M2';
```

Inmediatamente después, consulta el identificador de ese comando:

```sql
SELECT LAST_QUERY_ID() AS ID_SHOW_WAREHOUSE;
```

Copia el identificador devuelto como evidencia. Tendrá un formato parecido a:

```text
01c12345-0001-....
```

### Procesar el resultado del `SHOW`

La forma más sencilla es ejecutar `RESULT_SCAN()` inmediatamente después del `SHOW`. Como en este caso ya hemos ejecutado `SELECT LAST_QUERY_ID()`, utilizaremos un índice relativo:

```sql
SELECT
    "name"         AS WAREHOUSE,
    "state"        AS ESTADO,
    "size"         AS TAMANO,
    "auto_suspend" AS AUTO_SUSPEND_SEGUNDOS,
    "auto_resume"  AS AUTO_RESUME,
    "owner"        AS PROPIETARIO
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID(-2)));
```

La secuencia es:

```text
-1  SELECT LAST_QUERY_ID()
-2  SHOW WAREHOUSES
```

Por eso utilizamos `LAST_QUERY_ID(-2)`.

### Alternativa más robusta usando el Query ID copiado

Sustituye el marcador por el identificador real:

```sql
SELECT
    "name"         AS WAREHOUSE,
    "state"        AS ESTADO,
    "size"         AS TAMANO,
    "auto_suspend" AS AUTO_SUSPEND_SEGUNDOS,
    "auto_resume"  AS AUTO_RESUME,
    "owner"        AS PROPIETARIO
FROM TABLE(RESULT_SCAN('<ID_DEL_SHOW>'));
```

Ejemplo conceptual:

```sql
FROM TABLE(RESULT_SCAN('01c12345-0001-....'));
```

### Por qué las columnas aparecen entre comillas

Los comandos `SHOW` generan nombres de columna en minúsculas. Los identificadores sin comillas se normalizan a mayúsculas, por lo que usamos:

```sql
"name"
```

en lugar de:

```sql
name
```

---

## 7. Reproducir el incidente del warehouse suspendido

### 7.1 Desactivar temporalmente la reutilización de resultados

```sql
ALTER SESSION SET USE_CACHED_RESULT = FALSE;
```

Snowflake conserva durante un tiempo los resultados de consultas correctas y puede reutilizarlos. Para que la prueba dependa realmente del warehouse, desactivamos esa reutilización durante el incidente.

Esto no elimina datos ni cachés del warehouse; solo impide que la sesión utilice un resultado persistido de una consulta anterior.

### 7.2 Desactivar temporalmente la reanudación automática

```sql
USE ROLE SYSADMIN;

ALTER WAREHOUSE WH_LAB_M2
    SET AUTO_RESUME = FALSE;
```

### 7.3 Suspender el warehouse

```sql
ALTER WAREHOUSE WH_LAB_M2 SUSPEND;
```

Si ya estaba suspendido, Snowflake puede devolver un mensaje indicando que el warehouse ya se encuentra en ese estado o un error. Lo importante es que al final esté suspendido.

### 7.4 Comprobar el estado

```sql
SHOW WAREHOUSES LIKE 'WH_LAB_M2';

SELECT
    "name"         AS WAREHOUSE,
    "state"        AS ESTADO,
    "auto_resume"  AS AUTO_RESUME,
    "auto_suspend" AS AUTO_SUSPEND_SEGUNDOS
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
```

Resultado lógico esperado si el warehouse estuviera activo:

| Propiedad | Valor esperado |
|---|---|
| Estado | `SUSPENDED` |
| Auto resume | `false` |
| Auto suspend | `60` |

En este caso, al estar suspendido recibiremos un mensaje con el comando para reanudar el warehouse.

### 7.5 Seleccionar el warehouse suspendido

```sql
USE WAREHOUSE WH_LAB_M2;
```

Seleccionar un warehouse no implica necesariamente que pueda ejecutar consultas. Su estado y la configuración de reanudación siguen siendo relevantes.

### 7.6 Ejecutar la prueba negativa

Ejecuta esta instrucción por separado:

```sql
SELECT
    ID_VENTA,
    CLIENTE,
    REGION,
    IMPORTE
FROM DB_CURSO.CURATED.VENTAS
ORDER BY IMPORTE DESC;
```

La consulta debe fallar. Elegimos una lectura de filas con ordenación, en lugar de un `COUNT(*)`, porque algunas consultas puramente basadas en metadatos pueden no necesitar cómputo de warehouse.

El texto exacto del mensaje puede variar, pero debe indicar que el warehouse está suspendido y que no puede utilizarse sin reanudarlo.

> Conserva el error. No lo interpretes como un fallo del laboratorio: es la evidencia de que `AUTO_RESUME = FALSE` está funcionando.

---

## 8. Diagnosticar y corregir el warehouse

### 8.1 Confirmar la causa

Vuelve a consultar sus propiedades:

```sql
SHOW WAREHOUSES LIKE 'WH_LAB_M2';
```

La combinación problemática es:

```text
STATE = SUSPENDED
AUTO_RESUME = FALSE
```

### 8.2 Reanudar manualmente

```sql
ALTER WAREHOUSE WH_LAB_M2 RESUME IF SUSPENDED;
```

`IF SUSPENDED` evita un error si el warehouse ya se hubiese reanudado por otra operación.

### 8.3 Restaurar las propiedades del laboratorio

```sql
ALTER WAREHOUSE WH_LAB_M2 SET
    WAREHOUSE_SIZE = XSMALL
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE;
```

### 8.4 Repetir la consulta

```sql
USE WAREHOUSE WH_LAB_M2;

SELECT
    ID_VENTA,
    CLIENTE,
    REGION,
    IMPORTE
FROM DB_CURSO.CURATED.VENTAS
ORDER BY IMPORTE DESC;
```

La consulta debe devolver las ocho ventas, ordenadas de mayor a menor importe.

### Interpretación

El SQL y los datos no habían cambiado. La causa era operativa:

```text
Warehouse suspendido + AUTO_RESUME desactivado + resultado persistido deshabilitado
```

La corrección fue:

```text
RESUME + AUTO_RESUME = TRUE
```

---

## 9. Reproducir el incidente de contexto de esquema

Fija la base de datos, pero selecciona deliberadamente el esquema incorrecto:

```sql
USE DATABASE DB_CURSO;
USE SCHEMA STAGING;
```

Comprueba el contexto:

```sql
SELECT
    CURRENT_DATABASE() AS BASE_DATOS_ACTUAL,
    CURRENT_SCHEMA()   AS ESQUEMA_ACTUAL;
```

Resultado esperado:

```text
DB_CURSO | STAGING
```

### 9.1 Prueba negativa con nombre corto

Ejecuta por separado:

```sql
SELECT *
FROM VENTAS;
```

Snowflake intentará resolver el nombre como:

```text
DB_CURSO.STAGING.VENTAS
```

Ese objeto no existe. El mensaje puede indicar que el objeto no existe o que no está autorizado.

### 9.2 Probar un nombre totalmente cualificado

Sin cambiar el esquema activo, ejecuta:

```sql
SELECT *
FROM DB_CURSO.CURATED.VENTAS
ORDER BY ID_VENTA;
```

Esta consulta debe funcionar porque especifica explícitamente:

```text
BASE_DE_DATOS.ESQUEMA.OBJETO
```

El esquema activo continúa siendo `STAGING`, pero ya no interviene en la resolución del nombre.

---

## 10. Corregir el contexto de esquema

Selecciona el esquema correcto:

```sql
USE SCHEMA DB_CURSO.CURATED;
```

Comprueba el contexto:

```sql
SELECT
    CURRENT_DATABASE() AS BASE_DATOS_ACTUAL,
    CURRENT_SCHEMA()   AS ESQUEMA_ACTUAL;
```

Resultado esperado:

```text
DB_CURSO | CURATED
```

Repite la consulta con nombre corto:

```sql
SELECT *
FROM VENTAS
ORDER BY ID_VENTA;
```

Ahora debe funcionar.

### Explicación para incluir en el SQL File

Puedes añadir este comentario SQL:

```sql
-- VENTAS es un nombre no cualificado.
-- Snowflake lo busca en CURRENT_DATABASE().CURRENT_SCHEMA().
-- Desde STAGING intenta resolver DB_CURSO.STAGING.VENTAS y falla.
-- Desde CURATED resuelve DB_CURSO.CURATED.VENTAS y funciona.
-- El nombre DB_CURSO.CURATED.VENTAS no depende del esquema activo.
```

---

## 11. Crear una consulta identificable por región

Ejecuta la agregación:

```sql
SELECT
    REGION,
    COUNT(*)                    AS NUMERO_VENTAS,
    SUM(IMPORTE)                AS IMPORTE_TOTAL,
    ROUND(AVG(IMPORTE), 2)      AS IMPORTE_MEDIO
FROM DB_CURSO.CURATED.VENTAS
GROUP BY REGION
ORDER BY IMPORTE_TOTAL DESC;
```

Con los datos del ejercicio 1, los resultados son aproximadamente:

| Región | Ventas | Importe total | Importe medio |
|---|---:|---:|---:|
| `NORTE` | 2 | 1595.50 | 797.75 |
| `ESTE` | 2 | 1510.40 | 755.20 |
| `CENTRO` | 2 | 1255.35 | 627.68 |
| `SUR` | 2 | 430.75 | 215.38 |

---

## 12. Obtener el Query ID y reutilizar el resultado

Inmediatamente después de la agregación ejecuta:

```sql
SELECT LAST_QUERY_ID() AS ID_CONSULTA_REGIONES;
```

Copia el identificador devuelto.

### 12.1 Reutilizar mediante el identificador explícito

Sustituye `<ID_CONSULTA_REGIONES>` por el valor real:

```sql
SELECT
    REGION,
    NUMERO_VENTAS,
    IMPORTE_TOTAL,
    IMPORTE_MEDIO
FROM TABLE(RESULT_SCAN('<ID_CONSULTA_REGIONES>'))
WHERE IMPORTE_TOTAL > 1000
ORDER BY IMPORTE_TOTAL DESC;
```

Resultado esperado:

| Región | Ventas | Importe total |
|---|---:|---:|
| `NORTE` | 2 | 1595.50 |
| `ESTE` | 2 | 1510.40 |
| `CENTRO` | 2 | 1255.35 |

`SUR` queda excluida porque su total no supera 1.000.

### 12.2 Alternativa mediante posición relativa

Si no ejecutaste ninguna instrucción adicional entre la agregación y `SELECT LAST_QUERY_ID()`, la agregación es la segunda consulta más reciente cuando ejecutas el siguiente bloque:

```sql
SELECT
    REGION,
    NUMERO_VENTAS,
    IMPORTE_TOTAL,
    IMPORTE_MEDIO
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID(-2)))
WHERE IMPORTE_TOTAL > 1000
ORDER BY IMPORTE_TOTAL DESC;
```

Usar el Query ID explícito es más robusto, porque una consulta adicional cambia los índices relativos.

### Qué hace realmente `RESULT_SCAN`

`RESULT_SCAN` no vuelve a ejecutar la agregación original. Trata el resultado persistido de una consulta anterior como si fuese una tabla y permite aplicar nuevas operaciones sobre él.

En este caso añadimos un filtro que no estaba en la consulta original:

```sql
WHERE IMPORTE_TOTAL > 1000
```

---

## 13. Consultar el historial de la sesión mediante SQL

Utilizaremos la función `QUERY_HISTORY_BY_SESSION` del `INFORMATION_SCHEMA` de `DB_CURSO`.

```sql
SELECT
    START_TIME,
    QUERY_ID,
    QUERY_TAG,
    QUERY_TYPE,
    WAREHOUSE_NAME,
    DATABASE_NAME,
    SCHEMA_NAME,
    EXECUTION_STATUS,
    ERROR_CODE,
    ERROR_MESSAGE,
    TOTAL_ELAPSED_TIME,
    QUERY_TEXT
FROM TABLE(
    DB_CURSO.INFORMATION_SCHEMA.QUERY_HISTORY_BY_SESSION(
        SESSION_ID => CURRENT_SESSION()::INT,
        RESULT_LIMIT => 200
    )
)
WHERE QUERY_TAG = 'M2_E3_DIAGNOSTICO'
ORDER BY START_TIME;
```

### Qué debes observar

Deberían aparecer, entre otras, estas operaciones:

- Los cambios de contexto.
- Los comandos `SHOW`.
- Las modificaciones del warehouse.
- La consulta fallida con el warehouse suspendido.
- La consulta correcta después de reanudarlo.
- La consulta fallida `SELECT * FROM VENTAS` desde `STAGING`.
- La consulta totalmente cualificada correcta.
- La agregación por región.
- Las consultas con `RESULT_SCAN`.

### Estados y errores

En las consultas correctas, normalmente observarás:

```text
EXECUTION_STATUS = SUCCESS
ERROR_CODE = NULL
ERROR_MESSAGE = NULL
```

En las consultas fallidas aparecerán valores en `ERROR_CODE` y `ERROR_MESSAGE`.

El texto exacto del error puede variar entre versiones y situaciones. Evalúa la causa, no una cadena literal concreta.

### Localizar solo los errores

```sql
SELECT
    START_TIME,
    QUERY_ID,
    WAREHOUSE_NAME,
    DATABASE_NAME,
    SCHEMA_NAME,
    EXECUTION_STATUS,
    ERROR_CODE,
    ERROR_MESSAGE,
    QUERY_TEXT
FROM TABLE(
    DB_CURSO.INFORMATION_SCHEMA.QUERY_HISTORY_BY_SESSION(
        SESSION_ID => CURRENT_SESSION()::INT,
        RESULT_LIMIT => 200
    )
)
WHERE QUERY_TAG = 'M2_E3_DIAGNOSTICO'
  AND ERROR_CODE IS NOT NULL
ORDER BY START_TIME;
```

Deberías identificar al menos los dos incidentes controlados.

### Nota sobre visibilidad

Las funciones de Query History devuelven las consultas ejecutadas por el usuario actual. Para ver consultas de otros usuarios se necesitan privilegios adicionales de monitorización sobre los warehouses u otros objetos correspondientes.

Por tanto, este ejercicio no requiere conceder privilegios nuevos: cada alumno consulta sus propias ejecuciones.

---

## 14. Revisar Query History en Snowsight

La navegación actual documentada por Snowflake es:

```text
Monitoring → Query History
```

En algunas evoluciones de la interfaz pueden cambiar ligeramente los nombres o la posición de los elementos, pero la página continúa siendo Query History.

### 14.1 Aplicar filtros

Utiliza los filtros siguientes:

- **User:** tu usuario.
- **Query Tag:** `M2_E3_DIAGNOSTICO`.
- **Warehouse:** `WH_LAB_M2`, cuando quieras limitarte a consultas que utilizaron cómputo.
- **Status:** alterna entre consultas correctas y fallidas.

Algunos comandos de metadatos o de sesión pueden no mostrar un warehouse porque no necesitan ejecutar trabajo de datos sobre un virtual warehouse.

### 14.2 Revisar una consulta correcta

Abre, por ejemplo, la agregación por región. Comprueba:

- Query ID.
- Status.
- Query tag.
- Usuario.
- Warehouse.
- Duración.
- Texto SQL.
- Filas producidas.

El Query ID debe coincidir con el obtenido mediante `LAST_QUERY_ID()` si seleccionas la misma ejecución.

### 14.3 Revisar una consulta fallida

Abre la consulta ejecutada con el warehouse suspendido o la consulta `SELECT * FROM VENTAS` desde `STAGING`.

Comprueba:

- Estado fallido.
- Mensaje de error.
- Contexto registrado.
- Query tag.
- Query ID.

Esto permite pasar de un mensaje informado por un usuario a una evidencia concreta y trazable.

---

## 15. Restaurar el entorno

### 15.1 Restaurar el warehouse

```sql
USE ROLE SYSADMIN;

ALTER WAREHOUSE WH_LAB_M2 SET
    WAREHOUSE_SIZE = XSMALL
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE;
```

### 15.2 Verificar la configuración final

```sql
SHOW WAREHOUSES LIKE 'WH_LAB_M2';

SELECT
    "name"         AS WAREHOUSE,
    "state"        AS ESTADO_ANTES_DE_SUSPENDER,
    "size"         AS TAMANO,
    "auto_suspend" AS AUTO_SUSPEND_SEGUNDOS,
    "auto_resume"  AS AUTO_RESUME
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
```

Debes comprobar:

```text
SIZE = X-Small
AUTO_SUSPEND = 60
AUTO_RESUME = true
```

### 15.3 Suspender el warehouse

```sql
ALTER WAREHOUSE WH_LAB_M2 SUSPEND;
```

Comprueba el estado final:

```sql
SHOW WAREHOUSES LIKE 'WH_LAB_M2';
```

Resultado esperado:

```text
WH_LAB_M2 | SUSPENDED
```

### 15.4 Restaurar la reutilización normal de resultados

```sql
ALTER SESSION UNSET USE_CACHED_RESULT;
```

Esto devuelve el parámetro al valor heredado o predeterminado de la cuenta.

### 15.5 Eliminar el query tag de la sesión

Hazlo después de las consultas de auditoría que quieras conservar con el tag:

```sql
ALTER SESSION UNSET QUERY_TAG;
```

Comprueba que se ha restablecido:

```sql
SHOW PARAMETERS LIKE 'QUERY_TAG';
```

El valor efectivo debería volver al valor predeterminado o al heredado de niveles superiores.

---

## 16. Script de referencia

El siguiente script resume el camino principal. Los bloques identificados como **error esperado** deben ejecutarse individualmente.

```sql
-- =========================================================
-- 1. SESION Y CONTEXTO
-- =========================================================
USE ROLE SYSADMIN;
ALTER SESSION SET QUERY_TAG = 'M2_E3_DIAGNOSTICO';

USE WAREHOUSE WH_LAB_M2;
USE DATABASE DB_CURSO;
USE SCHEMA CURATED;

SELECT
    CURRENT_USER()            AS USUARIO_ACTUAL,
    CURRENT_ROLE()            AS ROL_ACTUAL,
    CURRENT_SECONDARY_ROLES() AS ROLES_SECUNDARIOS,
    CURRENT_WAREHOUSE()       AS WAREHOUSE_ACTUAL,
    CURRENT_DATABASE()        AS BASE_DATOS_ACTUAL,
    CURRENT_SCHEMA()          AS ESQUEMA_ACTUAL,
    CURRENT_SESSION()         AS ID_SESION,
    CURRENT_VERSION()         AS VERSION_SNOWFLAKE;

-- =========================================================
-- 2. SHOW + RESULT_SCAN
-- =========================================================
SHOW WAREHOUSES LIKE 'WH_LAB_M2';

SELECT
    "name"         AS WAREHOUSE,
    "state"        AS ESTADO,
    "size"         AS TAMANO,
    "auto_suspend" AS AUTO_SUSPEND_SEGUNDOS,
    "auto_resume"  AS AUTO_RESUME,
    "owner"        AS PROPIETARIO
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

-- =========================================================
-- 3. INCIDENTE DE WAREHOUSE
-- =========================================================
ALTER SESSION SET USE_CACHED_RESULT = FALSE;
ALTER WAREHOUSE WH_LAB_M2 SET AUTO_RESUME = FALSE;
ALTER WAREHOUSE WH_LAB_M2 SUSPEND;
USE WAREHOUSE WH_LAB_M2;

-- ERROR ESPERADO: ejecutar de forma independiente
SELECT
    ID_VENTA, CLIENTE, REGION, IMPORTE
FROM DB_CURSO.CURATED.VENTAS
ORDER BY IMPORTE DESC;

-- CORRECCION
ALTER WAREHOUSE WH_LAB_M2 RESUME IF SUSPENDED;
ALTER WAREHOUSE WH_LAB_M2 SET
    WAREHOUSE_SIZE = XSMALL
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE;

SELECT
    ID_VENTA, CLIENTE, REGION, IMPORTE
FROM DB_CURSO.CURATED.VENTAS
ORDER BY IMPORTE DESC;

-- =========================================================
-- 4. INCIDENTE DE CONTEXTO
-- =========================================================
USE DATABASE DB_CURSO;
USE SCHEMA STAGING;

-- ERROR ESPERADO: ejecutar de forma independiente
SELECT * FROM VENTAS;

-- FUNCIONA AUN CON STAGING ACTIVO
SELECT *
FROM DB_CURSO.CURATED.VENTAS
ORDER BY ID_VENTA;

-- CORRECCION
USE SCHEMA DB_CURSO.CURATED;

SELECT *
FROM VENTAS
ORDER BY ID_VENTA;

-- =========================================================
-- 5. CONSULTA PARA REUTILIZAR
-- =========================================================
SELECT
    REGION,
    COUNT(*)               AS NUMERO_VENTAS,
    SUM(IMPORTE)           AS IMPORTE_TOTAL,
    ROUND(AVG(IMPORTE), 2) AS IMPORTE_MEDIO
FROM DB_CURSO.CURATED.VENTAS
GROUP BY REGION
ORDER BY IMPORTE_TOTAL DESC;

-- Ejecutar inmediatamente después y copiar el resultado
SELECT LAST_QUERY_ID() AS ID_CONSULTA_REGIONES;

-- Sustituir el marcador por el ID real
SELECT
    REGION,
    NUMERO_VENTAS,
    IMPORTE_TOTAL,
    IMPORTE_MEDIO
FROM TABLE(RESULT_SCAN('<ID_CONSULTA_REGIONES>'))
WHERE IMPORTE_TOTAL > 1000
ORDER BY IMPORTE_TOTAL DESC;

-- =========================================================
-- 6. HISTORIAL DE LA SESION
-- =========================================================
SELECT
    START_TIME,
    QUERY_ID,
    QUERY_TAG,
    QUERY_TYPE,
    WAREHOUSE_NAME,
    DATABASE_NAME,
    SCHEMA_NAME,
    EXECUTION_STATUS,
    ERROR_CODE,
    ERROR_MESSAGE,
    TOTAL_ELAPSED_TIME,
    QUERY_TEXT
FROM TABLE(
    DB_CURSO.INFORMATION_SCHEMA.QUERY_HISTORY_BY_SESSION(
        SESSION_ID => CURRENT_SESSION(),
        RESULT_LIMIT => 200
    )
)
WHERE QUERY_TAG = 'M2_E3_DIAGNOSTICO'
ORDER BY START_TIME;

-- =========================================================
-- 7. RESTAURAR Y FINALIZAR
-- =========================================================
USE ROLE SYSADMIN;
ALTER WAREHOUSE WH_LAB_M2 SET
    WAREHOUSE_SIZE = XSMALL
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE;

ALTER WAREHOUSE WH_LAB_M2 SUSPEND;
ALTER SESSION UNSET USE_CACHED_RESULT;
ALTER SESSION UNSET QUERY_TAG;
```

---

## 17. Problemas frecuentes y resolución

### La consulta de detalle funciona cuando debería fallar

Comprueba la configuración inmediatamente antes de ejecutarlo:

```sql
SHOW WAREHOUSES LIKE 'WH_LAB_M2';
```

Debes tener:

```text
STATE = SUSPENDED
AUTO_RESUME = false
USE_CACHED_RESULT = false en la sesión
```

Comprueba el parámetro de sesión con:

```sql
SHOW PARAMETERS LIKE 'USE_CACHED_RESULT';
```

También confirma que la consulta utiliza `WH_LAB_M2`:

```sql
SELECT CURRENT_WAREHOUSE();
```

Si otro proceso reanudó el warehouse, vuelve a suspenderlo antes de la prueba.

### `ALTER WAREHOUSE ... SUSPEND` devuelve que ya está suspendido

No es un problema. El estado requerido para la prueba ya se cumple.

### No puedo reanudar o modificar el warehouse

Comprueba:

```sql
SELECT CURRENT_ROLE();
```

Debe ser `SYSADMIN` o un rol que tenga los privilegios necesarios sobre el warehouse. El rol `ROL_ANALISTA_VENTAS` del ejercicio anterior solo recibió `USAGE`, no `OPERATE` ni `MODIFY`.

### La consulta corta `SELECT * FROM VENTAS` funciona desde STAGING

Comprueba el esquema activo:

```sql
SELECT CURRENT_DATABASE(), CURRENT_SCHEMA();
```

También comprueba que no has creado accidentalmente una tabla `DB_CURSO.STAGING.VENTAS`.

```sql
SHOW TABLES LIKE 'VENTAS' IN SCHEMA DB_CURSO.STAGING;
```

Si existe un objeto con ese nombre creado fuera del ejercicio, utiliza un nombre de tabla inexistente controlado o elimina únicamente el objeto accidental, siempre que estés seguro de que no contiene trabajo previo.

### `RESULT_SCAN(LAST_QUERY_ID())` devuelve otro resultado

`LAST_QUERY_ID()` cambia cada vez que ejecutas una sentencia. Ejecuta `RESULT_SCAN` inmediatamente después del comando cuyo resultado quieres procesar o copia el Query ID y úsalo explícitamente.

### Error al referenciar columnas de un `SHOW`

Los nombres generados por `SHOW` suelen estar en minúsculas. Utiliza comillas dobles:

```sql
"name"
"state"
"auto_resume"
```

### No aparecen todavía todas las consultas en Query History

Actualiza la página o habilita la actualización automática. La interfaz puede tardar unos segundos en reflejar las ejecuciones más recientes.

La función `QUERY_HISTORY_BY_SESSION` suele ser la forma más directa de comprobar las consultas de la sesión desde SQL.

### El historial incluye más consultas de las esperadas

Todas las sentencias posteriores a la activación del tag pueden aparecer etiquetadas, incluidas consultas de diagnóstico y la propia consulta del historial.

Filtra también por:

- `SESSION_ID`.
- Intervalo de tiempo.
- `QUERY_TYPE`.
- Parte del texto SQL.

### El Query ID no coincide con el que esperaba

Verifica que seleccionas exactamente la misma ejecución. Ejecutar dos veces el mismo SQL crea dos Query IDs distintos.

---

## 18. Referencias oficiales utilizadas para la validación

- [Trial accounts](https://docs.snowflake.com/en/user-guide/admin-trial-account)
- [USE WAREHOUSE](https://docs.snowflake.com/en/sql-reference/sql/use-warehouse)
- [ALTER WAREHOUSE](https://docs.snowflake.com/en/sql-reference/sql/alter-warehouse)
- [ALTER SESSION](https://docs.snowflake.com/en/sql-reference/sql/alter-session)
- [Snowflake parameters: QUERY_TAG](https://docs.snowflake.com/en/sql-reference/parameters#label-query-tag)
- [LAST_QUERY_ID](https://docs.snowflake.com/en/sql-reference/functions/last_query_id)
- [RESULT_SCAN](https://docs.snowflake.com/en/sql-reference/functions/result_scan)
- [QUERY_HISTORY and QUERY_HISTORY_BY_*](https://docs.snowflake.com/en/sql-reference/functions/query_history)
- [Monitor query activity with Query History](https://docs.snowflake.com/en/user-guide/ui-snowsight-activity)
- [Warehouse considerations and billing](https://docs.snowflake.com/en/user-guide/warehouses-considerations)

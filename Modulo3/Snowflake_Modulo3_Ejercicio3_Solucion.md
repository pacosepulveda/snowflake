# Módulo 3 · Ejercicio 3

# Solución guiada: observabilidad de la plataforma

## Resultado que se va a construir

En este ejercicio vamos a generar una carga de trabajo identificable y a observarla desde dos perspectivas:

- **Tiempo casi real:** funciones de `INFORMATION_SCHEMA`.
- **Histórico de cuenta:** vistas de `SNOWFLAKE.ACCOUNT_USAGE`.

También analizaremos el consumo horario de los warehouses y relacionaremos las métricas con las capas de Cloud Services, Compute y Storage.

---

# 1. Preparar el contexto

## 1.1. Crear el warehouse

Crea un SQL File llamado:

`M3_E3_OBSERVABILIDAD.sql`

Ejecuta:

```sql
USE ROLE SYSADMIN;

CREATE WAREHOUSE IF NOT EXISTS WH_M3_OBS
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE;
```

### Explicación

- `XSMALL` minimiza el consumo del laboratorio.
- `AUTO_SUSPEND = 60` suspende el warehouse después de un minuto sin actividad.
- `AUTO_RESUME = TRUE` permite que Snowflake lo reanude cuando llegue una consulta.
- `INITIALLY_SUSPENDED = TRUE` evita consumo antes del primer uso.

El almacenamiento de las tablas no depende de que el warehouse esté encendido. El warehouse solo proporciona recursos de cómputo.

---

## 1.2. Crear o seleccionar los objetos

```sql
USE WAREHOUSE WH_M3_OBS;

CREATE DATABASE IF NOT EXISTS DB_CURSO;
CREATE SCHEMA IF NOT EXISTS DB_CURSO.ARQUITECTURA;

USE DATABASE DB_CURSO;
USE SCHEMA ARQUITECTURA;
```

---

## 1.3. Crear la tabla cuando no exista

Los alumnos que hayan completado el primer ejercicio del módulo ya deberían tener `VENTAS_ARQ`.

Compruébalo:

```sql
SHOW TABLES LIKE 'VENTAS_ARQ'
IN SCHEMA DB_CURSO.ARQUITECTURA;
```

Cuando no exista, créala con un millón de filas sintéticas:

```sql
CREATE TRANSIENT TABLE IF NOT EXISTS DB_CURSO.ARQUITECTURA.VENTAS_ARQ AS
SELECT
    SEQ4() + 1 AS ID_VENTA,
    DATEADD(
        'day',
        UNIFORM(0, 364, RANDOM()),
        '2025-01-01'::DATE
    ) AS FECHA,
    ROUND(UNIFORM(100, 100000, RANDOM()) / 100, 2) AS IMPORTE,
    'REGION_' || UNIFORM(1, 6, RANDOM()) AS REGION
FROM TABLE(GENERATOR(ROWCOUNT => 1000000));
```

Comprueba el resultado:

```sql
SELECT
    COUNT(*) AS FILAS,
    MIN(FECHA) AS FECHA_MINIMA,
    MAX(FECHA) AS FECHA_MAXIMA,
    MIN(IMPORTE) AS IMPORTE_MINIMO,
    MAX(IMPORTE) AS IMPORTE_MAXIMO
FROM DB_CURSO.ARQUITECTURA.VENTAS_ARQ;
```

### Resultado esperado

- `FILAS`: 1.000.000 cuando se ha usado el bloque alternativo.
- Fechas distribuidas durante 2025.
- Importes positivos.

Los valores concretos varían porque los datos se generan aleatoriamente.

---

## 1.4. Verificar el contexto

```sql
SELECT
    CURRENT_ROLE() AS ROL_ACTIVO,
    CURRENT_WAREHOUSE() AS WAREHOUSE_ACTIVO,
    CURRENT_DATABASE() AS BASE_ACTIVA,
    CURRENT_SCHEMA() AS ESQUEMA_ACTIVO,
    CURRENT_SESSION() AS SESSION_ID;
```

El resultado esperado es similar a:

| Campo | Valor esperado |
|---|---|
| ROL_ACTIVO | SYSADMIN |
| WAREHOUSE_ACTIVO | WH_M3_OBS |
| BASE_ACTIVA | DB_CURSO |
| ESQUEMA_ACTIVO | ARQUITECTURA |
| SESSION_ID | Identificador numérico de la sesión |

---

# 2. Etiquetar la carga de trabajo

Ejecuta:

```sql
ALTER SESSION SET QUERY_TAG = 'M3_E3_OBSERVABILIDAD';
ALTER SESSION SET USE_CACHED_RESULT = TRUE;
```

## ¿Qué hace QUERY_TAG?

`QUERY_TAG` añade una etiqueta a las consultas posteriores de la sesión. La etiqueta aparece en Query History y en las vistas de observabilidad.

Es útil para identificar:

- Una aplicación.
- Un pipeline.
- Una sesión formativa.
- Una versión de un proceso.
- Un departamento o centro de coste.

`USE_CACHED_RESULT = TRUE` permite que Snowflake reutilice resultados persistidos cuando se cumplen las condiciones necesarias.

---

# 3. Generar la carga de trabajo

Ejecuta cada bloque por separado y en el orden indicado.

## 3.1. Operación de metadatos

```sql
SHOW TABLES LIKE 'VENTAS_ARQ'
IN SCHEMA DB_CURSO.ARQUITECTURA;
```

### Qué ocurre arquitectónicamente

La sentencia consulta principalmente el catálogo de metadatos gestionado por Cloud Services. No necesita escanear las filas de la tabla.

Dependiendo de cómo Snowflake registre la operación y del contexto de la sesión, el historial puede mostrar un warehouse nulo o un consumo de datos inexistente.

---

## 3.2. Primera agregación

```sql
SELECT /* M3_E3_CACHE_TEST */
    COUNT(*) AS NUM_VENTAS,
    SUM(IMPORTE) AS IMPORTE_TOTAL,
    AVG(IMPORTE) AS IMPORTE_MEDIO
FROM DB_CURSO.ARQUITECTURA.VENTAS_ARQ;
```

Esta primera ejecución normalmente requiere:

1. Parsing y análisis semántico.
2. Optimización.
3. Comprobación del result cache.
4. Lectura de micro-particiones.
5. Agregación en el warehouse.
6. Creación del resultado persistido.

---

## 3.3. Segunda agregación idéntica

Vuelve a ejecutar exactamente:

```sql
SELECT /* M3_E3_CACHE_TEST */
    COUNT(*) AS NUM_VENTAS,
    SUM(IMPORTE) AS IMPORTE_TOTAL,
    AVG(IMPORTE) AS IMPORTE_MEDIO
FROM DB_CURSO.ARQUITECTURA.VENTAS_ARQ;
```

### Qué esperamos observar

Si el resultado persistido puede reutilizarse:

- La segunda ejecución será mucho más rápida.
- `BYTES_SCANNED` será normalmente cero o muy inferior.
- El tiempo de ejecución será mínimo.
- No será necesario volver a procesar las micro-particiones con el warehouse.

No debe afirmarse que el tiempo será idéntico para todos los alumnos. La latencia del cliente, la carga del servicio y otros factores pueden variar.

---

## 3.4. Consulta con filtro

```sql
SELECT /* M3_E3_PRUNING */
    DATE_TRUNC('month', FECHA) AS MES,
    COUNT(*) AS NUM_VENTAS,
    SUM(IMPORTE) AS IMPORTE_TOTAL
FROM DB_CURSO.ARQUITECTURA.VENTAS_ARQ
WHERE FECHA BETWEEN '2025-03-01'::DATE AND '2025-05-31'::DATE
GROUP BY 1
ORDER BY 1;
```

### Qué se estudia

El optimizador utiliza los metadatos de las micro-particiones para descartar, cuando sea posible, aquellas cuyos rangos de fecha no pueden cumplir el predicado.

La efectividad concreta del pruning depende de cómo hayan quedado distribuidas las filas dentro de las micro-particiones.

---

## 3.5. Generar un error controlado

```sql
SELECT /* M3_E3_ERROR */
    COLUMNA_INEXISTENTE
FROM DB_CURSO.ARQUITECTURA.VENTAS_ARQ;
```

La consulta debe fallar con un mensaje indicando que la columna no existe o no puede resolverse.

### Qué ocurre

El error se detecta durante el análisis semántico, antes de que sea necesario escanear los datos. Por ello:

- Aparecerá un estado de error.
- Se registrará `ERROR_MESSAGE`.
- Normalmente no habrá bytes escaneados.
- El tiempo corresponderá principalmente a Cloud Services.

---

## 3.6. Finalizar el etiquetado

```sql
ALTER SESSION UNSET QUERY_TAG;
```

A partir de este momento, las consultas de análisis no utilizarán el tag del workload.

Es posible que la sentencia que elimina el tag todavía aparezca asociada al valor anterior. Esto no afecta al ejercicio.

---

# 4. Historial inmediato con INFORMATION_SCHEMA

Ejecuta:

```sql
SELECT
    QUERY_ID,
    START_TIME,
    QUERY_TYPE,
    EXECUTION_STATUS,
    WAREHOUSE_NAME,
    WAREHOUSE_SIZE,
    TOTAL_ELAPSED_TIME,
    COMPILATION_TIME,
    EXECUTION_TIME,
    QUEUED_PROVISIONING_TIME,
    QUEUED_OVERLOAD_TIME,
    TRANSACTION_BLOCKED_TIME,
    BYTES_SCANNED,
    ROWS_PRODUCED,
    ERROR_MESSAGE,
    QUERY_TEXT
FROM TABLE(
    DB_CURSO.INFORMATION_SCHEMA.QUERY_HISTORY_BY_SESSION(
        RESULT_LIMIT => 200
    )
)
WHERE QUERY_TAG = 'M3_E3_OBSERVABILIDAD'
ORDER BY START_TIME;
```

## Por qué se cualifica la función

Las funciones de Information Schema deben ejecutarse desde el `INFORMATION_SCHEMA` de una base de datos o utilizar un nombre completamente cualificado.

En este caso usamos:

```text
DB_CURSO.INFORMATION_SCHEMA.QUERY_HISTORY_BY_SESSION
```

---

# 5. Interpretar las métricas

## 5.1. QUERY_ID

Identificador único de la sentencia. Permite localizarla en Snowsight, abrir su Query Profile y correlacionarla con herramientas externas.

## 5.2. TOTAL_ELAPSED_TIME

Tiempo total transcurrido, en milisegundos, desde que Snowflake recibe la sentencia hasta que termina.

Incluye diferentes fases, por ejemplo:

- Compilación.
- Espera por aprovisionamiento.
- Espera por sobrecarga.
- Bloqueo transaccional.
- Ejecución.

No debe interpretarse como sinónimo de tiempo de ejecución.

## 5.3. COMPILATION_TIME

Tiempo empleado por Cloud Services en tareas como:

- Parsing.
- Resolución de nombres.
- Comprobación de permisos.
- Optimización.
- Construcción del plan.

La consulta con una columna inexistente suele consumir compilación, pero no lectura de datos.

## 5.4. EXECUTION_TIME

Tiempo utilizado para ejecutar el plan. Cuando hay lectura y procesamiento, interviene el warehouse.

La segunda consulta servida desde result cache debería mostrar un valor muy reducido.

## 5.5. QUEUED_PROVISIONING_TIME

Tiempo que la consulta ha esperado mientras el warehouse se iniciaba, reanudaba o redimensionaba.

Puede aparecer en la primera consulta ejecutada después de que el warehouse estuviera suspendido.

## 5.6. QUEUED_OVERLOAD_TIME

Tiempo de espera porque el warehouse estaba saturado con otras consultas.

En un laboratorio individual y secuencial normalmente será cero.

## 5.7. TRANSACTION_BLOCKED_TIME

Tiempo bloqueado por DML concurrente.

En este ejercicio debería ser cero, ya que no se han creado transacciones enfrentadas.

## 5.8. BYTES_SCANNED

Cantidad de datos leídos por la consulta.

- Una agregación inicial debería escanear datos.
- Una sentencia de metadatos no necesita leer las filas.
- Una consulta con error semántico no debería escanear datos.
- Una consulta resuelta desde result cache normalmente muestra cero bytes escaneados.

---

# 6. Patrones esperados

Los valores exactos variarán, pero deberían observarse patrones similares a los siguientes:

| Operación | Estado | Bytes escaneados | Interpretación |
|---|---|---:|---|
| `SHOW TABLES` | Correcto | 0 o no aplicable | Trabajo principalmente de Cloud Services |
| Primera `M3_E3_CACHE_TEST` | Correcto | Mayor que cero | Lectura y agregación con Compute |
| Segunda `M3_E3_CACHE_TEST` | Correcto | Normalmente 0 | Reutilización del result cache |
| `M3_E3_PRUNING` | Correcto | Variable | Lectura selectiva según micro-particiones |
| `M3_E3_ERROR` | Error | Normalmente 0 | Fallo durante análisis semántico |

---

# 7. Revisar Query History y Query Profile en Snowsight

1. Abre **Monitoring** o **Activity** según la organización actual de la interfaz.
2. Accede a **Query History**.
3. Filtra por el tag:

```text
M3_E3_OBSERVABILIDAD
```

4. Abre la primera consulta `M3_E3_CACHE_TEST`.
5. Revisa su Query Profile.
6. Repite el proceso con `M3_E3_PRUNING`.

## Elementos que pueden aparecer

- Table scan.
- Aggregate.
- Result.
- Bytes escaneados.
- Particiones escaneadas y totales.
- Porcentaje leído desde caché local.
- Duración de los operadores.

La segunda ejecución servida desde result cache puede no presentar un plan de ejecución equivalente al de la primera, porque no ha sido necesario repetir el procesamiento completo.

---

# 8. Histórico de cuenta con ACCOUNT_USAGE

## 8.1. Cambiar temporalmente a ACCOUNTADMIN

```sql
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE WH_M3_OBS;
```

El warehouse es necesario para ejecutar la consulta SQL sobre las vistas compartidas.

## 8.2. Consultar QUERY_HISTORY

```sql
SELECT
    QUERY_ID,
    START_TIME,
    EXECUTION_STATUS,
    WAREHOUSE_NAME,
    WAREHOUSE_SIZE,
    TOTAL_ELAPSED_TIME,
    COMPILATION_TIME,
    EXECUTION_TIME,
    QUEUED_PROVISIONING_TIME,
    QUEUED_OVERLOAD_TIME,
    TRANSACTION_BLOCKED_TIME,
    BYTES_SCANNED,
    ROUND(PERCENTAGE_SCANNED_FROM_CACHE * 100, 2)
        AS PORCENTAJE_CACHE_LOCAL,
    PARTITIONS_SCANNED,
    PARTITIONS_TOTAL,
    CREDITS_USED_CLOUD_SERVICES,
    ERROR_CODE,
    ERROR_MESSAGE,
    QUERY_TEXT
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE QUERY_TAG = 'M3_E3_OBSERVABILIDAD'
  AND START_TIME >= DATEADD('day', -1, CURRENT_TIMESTAMP())
ORDER BY START_TIME;
```

## Resultado posible 1: aparecen las filas

Si ha transcurrido suficiente tiempo, verás las consultas y podrás comparar sus métricas con el informe inmediato.

## Resultado posible 2: no aparece ninguna fila reciente

También es correcto.

La vista `SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY` puede tener una latencia de hasta aproximadamente 45 minutos.

Esto demuestra que no es la fuente adecuada para diagnosticar un incidente ocurrido hace pocos segundos.

---

# 9. Diferencias entre las dos fuentes

| Característica | INFORMATION_SCHEMA | ACCOUNT_USAGE |
|---|---|---|
| Objetivo principal | Diagnóstico inmediato | Histórico, auditoría y tendencias |
| Latencia | Muy baja | Puede alcanzar unos 45 minutos en Query History |
| Retención del historial de consultas | Últimos 7 días | Hasta 365 días |
| Ámbito por defecto | Usuario, sesión o warehouse según función y privilegios | Cuenta completa según privilegios |
| Métricas detalladas históricas | Selección operativa | Más columnas de análisis físico y tendencias |
| Uso recomendado | Operaciones y troubleshooting | FinOps, auditoría y reporting |

## Matiz de permisos

Las funciones de Information Schema devuelven por defecto las consultas del usuario actual. Para observar consultas de otros usuarios hacen falta privilegios de monitorización apropiados.

Las vistas de la base `SNOWFLAKE` también están protegidas. En producción no se utilizaría `ACCOUNTADMIN` de forma habitual. Se concederían database roles específicos, por ejemplo:

- `SNOWFLAKE.GOVERNANCE_VIEWER` para `ACCOUNT_USAGE.QUERY_HISTORY`.
- `SNOWFLAKE.USAGE_VIEWER` para vistas históricas de consumo como `WAREHOUSE_METERING_HISTORY`.

---

# 10. Analizar el consumo de warehouses

Ejecuta:

```sql
SELECT
    DATE_TRUNC('hour', START_TIME) AS HORA,
    WAREHOUSE_NAME,
    ROUND(SUM(CREDITS_USED_COMPUTE), 4)
        AS CREDITOS_COMPUTE,
    ROUND(SUM(COALESCE(CREDITS_ATTRIBUTED_COMPUTE_QUERIES, 0)), 4)
        AS CREDITOS_ATRIBUIDOS_A_CONSULTAS,
    ROUND(
        SUM(CREDITS_USED_COMPUTE)
        - SUM(COALESCE(CREDITS_ATTRIBUTED_COMPUTE_QUERIES, 0)),
        4
    ) AS CREDITOS_IDLE_APROX
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE START_TIME >= DATEADD('day', -2, CURRENT_TIMESTAMP())
GROUP BY 1, 2
ORDER BY 1 DESC, 2;
```

## Interpretación

### CREDITS_USED_COMPUTE

Créditos de cómputo consumidos por el warehouse durante la hora.

Incluyen tanto trabajo útil como tiempo durante el que el warehouse permaneció encendido sin ejecutar consultas.

### CREDITS_ATTRIBUTED_COMPUTE_QUERIES

Créditos atribuidos por Snowflake a la ejecución de consultas.

No incluyen el tiempo inactivo del warehouse.

### CREDITOS_IDLE_APROX

La diferencia permite estimar el consumo de cómputo no atribuido directamente a consultas.

La propia documentación de Snowflake utiliza esta diferencia como forma de estudiar el coste de inactividad.

No debe confundirse con el importe final facturado, porque:

- Las vistas pueden tener latencia.
- Existen ajustes de Cloud Services.
- La atribución se realiza por intervalos temporales.
- La facturación final se calcula con otras vistas de metering y con las tarifas de la cuenta.

---

# 11. Latencia de WAREHOUSE_METERING_HISTORY

Es posible que todavía no aparezca el consumo del warehouse utilizado en este ejercicio.

La vista puede tener:

- Hasta aproximadamente 3 horas de latencia para los datos generales.
- Hasta aproximadamente 6 horas para determinados datos de Cloud Services.

Por ello:

- `INFORMATION_SCHEMA.QUERY_HISTORY_BY_SESSION` sirve para investigar ahora.
- `ACCOUNT_USAGE.QUERY_HISTORY` sirve para análisis histórico con menor urgencia.
- `WAREHOUSE_METERING_HISTORY` sirve para reporting de consumo y FinOps, no para medir en tiempo real el último minuto.

En un curso que ya lleva varias horas, normalmente aparecerá el consumo de warehouses utilizados en ejercicios anteriores.

---

# 12. Volver al rol de trabajo

```sql
USE ROLE SYSADMIN;
USE WAREHOUSE WH_M3_OBS;
```

No mantengas `ACCOUNTADMIN` como rol activo para el trabajo habitual.

---

# 13. Diagnóstico de arquitectura resuelto

Una posible conclusión sería:

> Cloud Services recibe la sentencia, valida la identidad y los privilegios, analiza el SQL, consulta los metadatos y genera el plan de ejecución. El tiempo de compilación refleja principalmente ese trabajo. Cuando una consulta necesita procesar datos, el virtual warehouse aporta CPU, memoria y almacenamiento local, lo que se observa en el tiempo de ejecución, los bytes escaneados y las posibles colas. Storage contiene las micro-particiones compartidas, y su acceso se refleja en las métricas de bytes y particiones leídas. El result cache puede evitar una nueva ejecución y servir el resultado desde Cloud Services, reduciendo latencia y consumo. Information Schema ofrece visibilidad casi inmediata y es adecuado para troubleshooting. Account Usage conserva más histórico y métricas de cuenta, pero introduce latencia, por lo que resulta más apropiado para auditoría, análisis de tendencias y FinOps.

---

# 14. Errores frecuentes

## Error: la tabla VENTAS_ARQ no existe

Comprueba el contexto:

```sql
SELECT
    CURRENT_DATABASE(),
    CURRENT_SCHEMA();
```

Utiliza siempre el nombre cualificado:

```text
DB_CURSO.ARQUITECTURA.VENTAS_ARQ
```

O ejecuta el bloque alternativo de creación.

---

## Error: no active warehouse selected

```sql
USE WAREHOUSE WH_M3_OBS;
```

---

## Error: no aparecen las consultas etiquetadas

Comprueba primero el historial inmediato:

```sql
SELECT
    QUERY_TAG,
    QUERY_TEXT,
    START_TIME
FROM TABLE(
    DB_CURSO.INFORMATION_SCHEMA.QUERY_HISTORY_BY_SESSION(
        RESULT_LIMIT => 200
    )
)
ORDER BY START_TIME DESC;
```

Si el tag no aparece, probablemente se ejecutó la carga antes de establecer `QUERY_TAG` o en otro SQL File con una sesión diferente.

---

## Error: ACCOUNT_USAGE no devuelve las consultas recientes

No es necesariamente un error. Espera a la actualización de la vista o utiliza Information Schema para la investigación inmediata.

---

## Error: insufficient privileges al consultar SNOWFLAKE.ACCOUNT_USAGE

En la cuenta individual del laboratorio utiliza temporalmente:

```sql
USE ROLE ACCOUNTADMIN;
```

En producción se debe usar un rol de observabilidad con los database roles mínimos necesarios.

---

## La segunda consulta no parece utilizar result cache

Comprueba:

```sql
SHOW PARAMETERS LIKE 'USE_CACHED_RESULT' IN SESSION;
```

El valor debe ser `TRUE`.

Además, confirma que las dos consultas son textualmente idénticas y que no se ha modificado la tabla entre ambas ejecuciones.

---

# 15. Limpieza opcional

No es necesario eliminar los objetos, ya que pueden reutilizarse posteriormente.

Para detener inmediatamente el consumo:

```sql
ALTER WAREHOUSE WH_M3_OBS SUSPEND;
```

No desactives `AUTO_RESUME`; será útil en ejercicios posteriores.

---

# Referencias oficiales

- Query History mediante Information Schema:  
  https://docs.snowflake.com/en/sql-reference/functions/query_history

- Query History en Account Usage:  
  https://docs.snowflake.com/en/sql-reference/account-usage/query_history

- Warehouse Metering History:  
  https://docs.snowflake.com/en/sql-reference/account-usage/warehouse_metering_history

- Database roles de la base compartida SNOWFLAKE:  
  https://docs.snowflake.com/en/sql-reference/snowflake-db-roles

- Cuentas trial:  
  https://docs.snowflake.com/en/user-guide/admin-trial-account

- Replicación y failover:  
  https://docs.snowflake.com/en/user-guide/account-replication-intro

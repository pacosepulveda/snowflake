# Módulo 8 · Ejercicio 1

## Solución guiada: dimensionamiento de warehouses, caché y suspensión

---

## 1. Diseño del experimento

Compararemos:

```text
WH_M08_XS → Gen1 XSMALL → 1 crédito/hora
WH_M08_S  → Gen1 SMALL  → 2 créditos/hora
```

Para evitar factores externos:

- Se usa la misma consulta.
- Se desactiva la caché de resultados persistidos.
- Se desactiva Query Acceleration Service.
- Ambos warehouses son single-cluster.
- Se registran las ejecuciones mediante `QUERY_TAG`.

La caché local del warehouse permanece activa porque forma parte del comportamiento que queremos observar.

---

## 2. Preparar Workspaces y el contexto

Crea en **Workspaces**:

```text
M8_E01_DIMENSIONAMIENTO.sql
```

Ejecuta:

```sql
USE ROLE SYSADMIN;

CREATE DATABASE IF NOT EXISTS DB_CURSO;
CREATE SCHEMA IF NOT EXISTS DB_CURSO.PERFORMANCE;

USE DATABASE DB_CURSO;
USE SCHEMA PERFORMANCE;

ALTER SESSION SET QUERY_TAG = 'M08_E01_PREPARACION';
```

---

## 3. Crear los dos warehouses

```sql
CREATE OR REPLACE WAREHOUSE WH_M08_XS
    WAREHOUSE_TYPE = STANDARD
    WAREHOUSE_SIZE = XSMALL
    GENERATION = '1'
    MIN_CLUSTER_COUNT = 1
    MAX_CLUSTER_COUNT = 1
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE
    ENABLE_QUERY_ACCELERATION = FALSE
    COMMENT = 'M08 benchmark Gen1 XSMALL';
```

```sql
CREATE OR REPLACE WAREHOUSE WH_M08_S
    WAREHOUSE_TYPE = STANDARD
    WAREHOUSE_SIZE = SMALL
    GENERATION = '1'
    MIN_CLUSTER_COUNT = 1
    MAX_CLUSTER_COUNT = 1
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE
    ENABLE_QUERY_ACCELERATION = FALSE
    COMMENT = 'M08 benchmark Gen1 SMALL';
```

### Por qué especificamos GENERATION

En la versión actual, Snowflake utiliza Gen2 como valor predeterminado para nuevos warehouses estándar en las regiones donde está disponible.

Gen2 puede tener características de rendimiento y consumo diferentes. Para que todos comparen la misma escala, fijamos:

```sql
GENERATION = '1'
```

La sintaxis recomendada actual es `GENERATION`; no se debe utilizar `RESOURCE_CONSTRAINT = STANDARD_GEN_1` para crear nuevos warehouses.

### Por qué desactivamos QAS

QAS puede aportar recursos serverless adicionales a consultas elegibles.

Si estuviera activo, una consulta ejecutada sobre `XSMALL` podría utilizar recursos que no pertenecen únicamente al clúster XSMALL, invalidando una comparación simple entre tamaños.

---

## 4. Inspeccionar los warehouses

```sql
SHOW WAREHOUSES LIKE 'WH_M08_%';
```

Comprueba visualmente:

```text
STATE = SUSPENDED
MIN_CLUSTER_COUNT = 1
MAX_CLUSTER_COUNT = 1
AUTO_SUSPEND = 60
AUTO_RESUME = TRUE
ENABLE_QUERY_ACCELERATION = FALSE
GENERATION = 1
```

Los nombres exactos de algunas columnas de `SHOW WAREHOUSES` pueden evolucionar.

---

## 5. Crear los datos sintéticos

Utiliza el warehouse pequeño:

```sql
USE WAREHOUSE WH_M08_XS;
```

Crea la tabla:

```sql
CREATE OR REPLACE TRANSIENT TABLE
    DB_CURSO.PERFORMANCE.VENTAS_RENDIMIENTO
AS
WITH base AS (
    SELECT SEQ8() AS n
    FROM TABLE(
        GENERATOR(ROWCOUNT => 10000000)
    )
)
SELECT
    (n + 1)::NUMBER(18,0)
        AS id_venta,

    DATEADD(
        'day',
        MOD(n, 365),
        '2025-01-01'::DATE
    )::DATE
        AS fecha,

    CASE MOD(n, 5)
        WHEN 0 THEN 'NORTE'
        WHEN 1 THEN 'SUR'
        WHEN 2 THEN 'ESTE'
        WHEN 3 THEN 'OESTE'
        ELSE 'CENTRO'
    END::VARCHAR(10)
        AS region,

    CASE MOD(n, 3)
        WHEN 0 THEN 'WEB'
        WHEN 1 THEN 'TIENDA'
        ELSE 'MARKETPLACE'
    END::VARCHAR(20)
        AS canal,

    (MOD(n * 13, 500000) + 1)::NUMBER(18,0)
        AS id_cliente,

    (MOD(n * 17, 50000) + 1)::NUMBER(18,0)
        AS id_producto,

    (
        5 + MOD(n * 97, 100000) / 100
    )::NUMBER(12,2)
        AS importe,

    (
        MOD(n * 19, 2500) / 100
    )::NUMBER(12,2)
        AS descuento,

    CASE MOD(n, 10)
        WHEN 0 THEN 'CANCELADA'
        WHEN 1 THEN 'PENDIENTE'
        ELSE 'COMPLETADA'
    END::VARCHAR(20)
        AS estado

FROM base;
```

### Validar el conjunto

```sql
SELECT
    COUNT(*) AS filas,
    MIN(fecha) AS fecha_minima,
    MAX(fecha) AS fecha_maxima,
    COUNT(DISTINCT id_cliente) AS clientes,
    COUNT(DISTINCT region) AS regiones,
    COUNT(DISTINCT canal) AS canales
FROM DB_CURSO.PERFORMANCE.VENTAS_RENDIMIENTO;
```

Resultado esperado:

```text
FILAS = 10000000
FECHA_MINIMA = 2025-01-01
FECHA_MAXIMA = 2025-12-31
REGIONES = 5
CANALES = 3
```

El número de clientes debe aproximarse al máximo generado y ser estable para la misma expresión.

### Suspender después del CTAS

```sql
ALTER WAREHOUSE WH_M08_XS SUSPEND;
```

Esto evita que la creación de la tabla deje una ventaja de caché local para la primera prueba.

---

## 6. Crear la view del benchmark

```sql
CREATE OR REPLACE VIEW
    DB_CURSO.PERFORMANCE.V_BENCHMARK_VENTAS
AS

WITH ventas_cliente AS (
    SELECT
        DATE_TRUNC('MONTH', fecha)::DATE
            AS mes,

        region,
        canal,
        id_cliente,

        COUNT(*) AS num_ventas,

        SUM(importe - descuento)::NUMBER(18,2)
            AS importe_neto

    FROM DB_CURSO.PERFORMANCE.VENTAS_RENDIMIENTO

    WHERE estado = 'COMPLETADA'

    GROUP BY
        mes,
        region,
        canal,
        id_cliente
)

SELECT
    mes,
    region,
    canal,

    COUNT(*)::NUMBER(18,0)
        AS clientes_activos,

    SUM(num_ventas)::NUMBER(18,0)
        AS num_ventas,

    SUM(importe_neto)::NUMBER(20,2)
        AS importe_total,

    ROUND(
        AVG(importe_neto),
        2
    )::NUMBER(20,2)
        AS importe_medio_cliente,

    ROUND(
        APPROX_PERCENTILE(
            importe_neto,
            0.90
        ),
        2
    )::NUMBER(20,2)
        AS p90_importe_cliente

FROM ventas_cliente

GROUP BY
    mes,
    region,
    canal;
```

Prueba de estructura:

```sql
SELECT *
FROM DB_CURSO.PERFORMANCE.V_BENCHMARK_VENTAS
LIMIT 5;
```

Después vuelve a suspender `WH_M08_XS`, porque esta comprobación ha reanudado y calentado el warehouse:

```sql
ALTER WAREHOUSE WH_M08_XS SUSPEND;
```

---

## 7. Desactivar la result cache

```sql
ALTER SESSION SET USE_CACHED_RESULT = FALSE;
```

Comprueba:

```sql
SHOW PARAMETERS LIKE 'USE_CACHED_RESULT'
IN SESSION;
```

Debe aparecer:

```text
FALSE
```

### Dos cachés diferentes

#### Result cache

- Es un resultado persistido gestionado por Snowflake.
- Puede devolver el resultado sin ejecutar otra vez la consulta.
- Se controla mediante `USE_CACHED_RESULT`.

#### Warehouse cache

- Reside en los SSD locales de los nodos del warehouse.
- Contiene datos leídos previamente.
- Puede acelerar una nueva ejecución real.
- Se pierde al suspender el warehouse.
- No se desactiva mediante `USE_CACHED_RESULT`.

---

## 8. Consulta exacta del benchmark

Utiliza siempre:

```sql
SELECT *
FROM DB_CURSO.PERFORMANCE.V_BENCHMARK_VENTAS
ORDER BY mes, region, canal;
```

No añadas ni elimines filtros entre ejecuciones.

---

## 9. Pruebas con XSMALL

### 9.1 Ejecución fría

```sql
ALTER SESSION SET QUERY_TAG = 'M08_E01_XS_COLD';

USE WAREHOUSE WH_M08_XS;

SELECT *
FROM DB_CURSO.PERFORMANCE.V_BENCHMARK_VENTAS
ORDER BY mes, region, canal;
```

El warehouse estaba suspendido. La consulta debe incluir:

- Posible tiempo de aprovisionamiento.
- Lectura con poca o ninguna caché local.

### 9.2 Ejecución caliente

```sql
ALTER SESSION SET QUERY_TAG = 'M08_E01_XS_WARM';

SELECT *
FROM DB_CURSO.PERFORMANCE.V_BENCHMARK_VENTAS
ORDER BY mes, region, canal;
```

La result cache sigue desactivada, por lo que la consulta se ejecuta otra vez.

Sin embargo, parte de los datos puede encontrarse en la caché local.

### 9.3 Ejecución después de suspensión

```sql
ALTER WAREHOUSE WH_M08_XS SUSPEND;
```

```sql
ALTER SESSION SET QUERY_TAG =
    'M08_E01_XS_AFTER_SUSPEND';

USE WAREHOUSE WH_M08_XS;

SELECT *
FROM DB_CURSO.PERFORMANCE.V_BENCHMARK_VENTAS
ORDER BY mes, region, canal;
```

Al reanudarse se ha perdido la caché local del clúster anterior.

---

## 10. Pruebas con SMALL

Asegúrate de que estaba suspendido:

```sql
ALTER WAREHOUSE WH_M08_S SUSPEND;
```

### 10.1 Primera ejecución

```sql
ALTER SESSION SET QUERY_TAG = 'M08_E01_S_COLD';

USE WAREHOUSE WH_M08_S;

SELECT *
FROM DB_CURSO.PERFORMANCE.V_BENCHMARK_VENTAS
ORDER BY mes, region, canal;
```

### 10.2 Ejecución caliente

```sql
ALTER SESSION SET QUERY_TAG = 'M08_E01_S_WARM';

SELECT *
FROM DB_CURSO.PERFORMANCE.V_BENCHMARK_VENTAS
ORDER BY mes, region, canal;
```

---

## 11. Analizar Query History

Cambia el tag para no confundir la consulta de análisis con el benchmark:

```sql
ALTER SESSION SET QUERY_TAG = 'M08_E01_ANALISIS';
```

Ejecuta:

```sql
SELECT
    query_tag,
    warehouse_name,
    warehouse_size,
    start_time,

    ROUND(total_elapsed_time / 1000, 3)
        AS total_segundos,

    ROUND(compilation_time / 1000, 3)
        AS compilacion_segundos,

    ROUND(execution_time / 1000, 3)
        AS ejecucion_segundos,

    ROUND(queued_provisioning_time / 1000, 3)
        AS aprovisionamiento_segundos,

    ROUND(queued_overload_time / 1000, 3)
        AS cola_sobrecarga_segundos,

    ROUND(bytes_scanned / POWER(1024, 2), 2)
        AS mb_escaneados,

    rows_written_to_result

FROM TABLE(
    DB_CURSO.INFORMATION_SCHEMA.QUERY_HISTORY_BY_SESSION(
        RESULT_LIMIT => 200
    )
)

WHERE query_tag IN (
    'M08_E01_XS_COLD',
    'M08_E01_XS_WARM',
    'M08_E01_XS_AFTER_SUSPEND',
    'M08_E01_S_COLD',
    'M08_E01_S_WARM'
)

ORDER BY start_time;
```

### Si una columna no aparece inmediatamente

La función de Information Schema ofrece información casi inmediata, pero alguna métrica puede tardar unos segundos en quedar completa.

Vuelve a ejecutar el informe.

Una consulta más completa, pero que podría tener una latencia de hasta 45 minutos (puede que no muestre los resultados recientes) es la siguiente:

```sql
SELECT
    query_tag,
    warehouse_name,
    warehouse_size,
    start_time,

    ROUND(
        total_elapsed_time / 1000,
        3
    ) AS total_segundos,

    ROUND(
        compilation_time / 1000,
        3
    ) AS compilacion_segundos,

    ROUND(
        execution_time / 1000,
        3
    ) AS ejecucion_segundos,

    ROUND(
        queued_provisioning_time / 1000,
        3
    ) AS aprovisionamiento_segundos,

    ROUND(
        queued_overload_time / 1000,
        3
    ) AS cola_sobrecarga_segundos,

    ROUND(
        bytes_scanned / POWER(1024, 2),
        2
    ) AS mb_escaneados,

    ROUND(
        COALESCE(
            percentage_scanned_from_cache,
            0
        ) * 100,
        2
    ) AS porcentaje_cache_local,

    partitions_scanned,
    partitions_total,

    ROUND(
        bytes_spilled_to_local_storage
        / POWER(1024, 2),
        2
    ) AS mb_spill_local,

    ROUND(
        bytes_spilled_to_remote_storage
        / POWER(1024, 2),
        2
    ) AS mb_spill_remoto,

    rows_written_to_result

FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY

WHERE query_tag IN (
    'M08_E01_XS_COLD',
    'M08_E01_XS_WARM',
    'M08_E01_XS_AFTER_SUSPEND',
    'M08_E01_S_COLD',
    'M08_E01_S_WARM'
)

ORDER BY start_time;
```

---

## 12. Interpretar los tiempos

### TOTAL_ELAPSED_TIME

Incluye el tiempo total experimentado por el usuario:

```text
compilación
+ aprovisionamiento
+ colas
+ ejecución
+ otros tiempos internos
```

### EXECUTION_TIME

Tiempo dedicado principalmente a ejecutar el plan.

Es más adecuado que el tiempo total para estudiar la diferencia de potencia entre tamaños.

### QUEUED_PROVISIONING_TIME

Tiempo esperando a que el warehouse:

- Se cree.
- Se reanude.
- Termine un resize.

Una ejecución fría puede tardar más por este motivo sin que el plan de consulta sea peor.

### QUEUED_OVERLOAD_TIME

Tiempo esperando porque el warehouse estaba sobrecargado.

Si este valor aparece repetidamente bajo concurrencia, el problema puede resolverse con:

- Más warehouses.
- Multi-cluster.
- Distribución de workloads.

No necesariamente aumentando el tamaño para una consulta individual.

---

## 13. Interpretar la caché local

Un patrón habitual, aunque no obligatorio, es:

```text
XS_COLD
    menor porcentaje de caché
    mayor tiempo

XS_WARM
    mayor porcentaje de caché
    menor tiempo

XS_AFTER_SUSPEND
    vuelve a reducirse la caché
```

Los porcentajes no tienen que ser exactamente `0 %` o `100 %`.

Snowflake puede:

- Leer metadatos sin escanear todos los bloques.
- Evitar particiones mediante pruning.
- Reutilizar diferentes partes del almacenamiento local.
- Cambiar el plan.
- Aplicar optimizaciones internas.

La conclusión debe basarse en la tendencia observada.

---

## 14. Comparar tamaño y créditos teóricos

Para cada ejecución fría:

```text
créditos teóricos
= execution_time_seconds
  × rate_credits_per_hour
  ÷ 3600
```

Ejemplo:

```text
XSMALL:
12 segundos × 1 / 3600
= 0,00333 créditos

SMALL:
7 segundos × 2 / 3600
= 0,00389 créditos
```

En ese ejemplo, SMALL sería más rápido, pero no más barato para esa consulta.

En otra carga, SMALL podría reducir el tiempo más de la mitad y resultar competitivo.

### Mínimo por reanudación

Snowflake factura warehouses por segundo después de un mínimo de 60 segundos cada vez que se inician o reanudan.

Para Gen1:

```text
XSMALL:
1 crédito/hora ÷ 60
= 0,01667 créditos mínimos

SMALL:
2 créditos/hora ÷ 60
= 0,03333 créditos mínimos
```

### Por qué no es coste exacto por consulta

El warehouse puede:

- Ejecutar varias consultas dentro del mismo minuto.
- Permanecer activo después de la consulta.
- Compartir su periodo facturado entre usuarios.
- Reanudarse varias veces.
- Cambiar de tamaño.
- Mantenerse activo por auto-suspend.

El cálculo basado en `EXECUTION_TIME` es un indicador comparativo, no una factura.

La medición real por warehouse se estudiará con las vistas de metering del módulo.

---

## 15. Verificar AUTO_SUSPEND

Elige uno de los warehouses y ejecuta una consulta.

Después no ejecutes SQL durante aproximadamente 90 segundos.

A continuación:

```sql
SHOW WAREHOUSES LIKE 'WH_M08_XS';
```

Debe aparecer suspendido.

### Por qué esperamos más de 60 segundos

El proceso que comprueba la inactividad se ejecuta aproximadamente cada 30 segundos.

`AUTO_SUSPEND = 60` no representa un temporizador de precisión al segundo.

### Verificar AUTO_RESUME

```sql
ALTER SESSION SET QUERY_TAG =
    'M08_E01_AUTORRESUME';

USE WAREHOUSE WH_M08_XS;

SELECT *
FROM DB_CURSO.PERFORMANCE.V_BENCHMARK_VENTAS
ORDER BY mes, region, canal;
```

Comprueba:

```sql
SELECT
    query_tag,
    warehouse_name,
    total_elapsed_time,
    queued_provisioning_time,
    execution_time

FROM TABLE(
    DB_CURSO.INFORMATION_SCHEMA
        .QUERY_HISTORY_BY_SESSION(
            RESULT_LIMIT => 50
        )
)

WHERE query_tag = 'M08_E01_AUTORRESUME'
ORDER BY start_time DESC;
```

La consulta reanuda el warehouse automáticamente.

---

## 16. Propuesta para desarrollo y BI

### Desarrollo

Configuración inicial razonable:

```text
Tamaño: XSMALL
AUTO_SUSPEND: 60
AUTO_RESUME: TRUE
Single-cluster
Warehouse separado
```

Justificación:

- Uso intermitente.
- Poca concurrencia.
- Prioridad de coste.
- La pérdida de caché suele ser aceptable.

### BI interactivo

Punto de partida posible:

```text
Tamaño: XSMALL o SMALL, según pruebas
AUTO_SUSPEND: 300-600
AUTO_RESUME: TRUE
Warehouse separado
```

Justificación:

- Consultas repetidas.
- La caché local puede mejorar la latencia.
- Evita reanudaciones constantes y mínimos de 60 segundos.
- Debe monitorizarse la concurrencia.

Antes de ampliar el tamaño se revisan:

- `EXECUTION_TIME`.
- Spill local y remoto.
- Bytes escaneados.
- Particiones.
- Query Profile.
- `QUEUED_OVERLOAD_TIME`.
- Warehouse Load History.
- Frecuencia de reanudaciones.
- Créditos consumidos.

### Separación por workload

No conviene compartir necesariamente un warehouse para:

```text
ETL + desarrollo + BI
```

Separarlos permite:

- Dimensionamiento independiente.
- Auto-suspend distinto.
- Caché específica.
- Aislamiento de CPU.
- Atribución de coste.
- Menos interferencia.

---

## 17. Escalado vertical frente a horizontal

### Vertical

Cambiar:

```text
XSMALL → SMALL → MEDIUM
```

Aumenta los recursos de cada clúster.

Puede acelerar una consulta pesada individual.

### Horizontal

Configurar varios clústeres permite ejecutar más consultas simultáneamente y reducir colas.

No divide una consulta individual entre varios clústeres.

Por tanto, un multi-cluster warehouse no es la solución directa para acelerar el benchmark de este ejercicio cuando se ejecuta una sola consulta.

---

## 18. Restaurar la sesión y suspender recursos

```sql
ALTER SESSION UNSET USE_CACHED_RESULT;
```

Comprueba que vuelve a su valor heredado:

```sql
SHOW PARAMETERS LIKE 'USE_CACHED_RESULT'
IN SESSION;
```

Suspende:

```sql
ALTER WAREHOUSE WH_M08_XS SUSPEND;
ALTER WAREHOUSE WH_M08_S SUSPEND;
```

Comprueba:

```sql
SHOW WAREHOUSES LIKE 'WH_M08_%';
```

No elimines todavía:

```text
DB_CURSO.PERFORMANCE.VENTAS_RENDIMIENTO
```

---

## 19. Errores frecuentes

### La segunda consulta termina casi instantáneamente

Comprueba:

```sql
SHOW PARAMETERS LIKE 'USE_CACHED_RESULT'
IN SESSION;
```

Debe ser `FALSE`.

Si era `TRUE`, probablemente se reutilizó el resultado persistido y no se ejecutó el benchmark real.

---

### XS_COLD muestra mucha caché local

Comprueba que suspendiste `WH_M08_XS` después de crear la tabla y después de probar la view.

También puede existir variabilidad interna. Repite el ciclo:

```text
SUSPEND → consulta fría → consulta caliente
```

---

### El warehouse aparece como Gen2

La creación no utilizó:

```sql
GENERATION = '1'
```

Recrea los warehouses con la definición proporcionada.

---

### QAS aparece habilitado

Comprueba:

```sql
DESC WAREHOUSE WH_M08_XS;
```

Debe aparecer:

```text
ENABLE_QUERY_ACCELERATION = FALSE
```

En la versión actual QAS puede habilitarse automáticamente en Gen2 y en warehouses multi-cluster recién creados, por lo que debe declararse explícitamente en experimentos controlados.

---

### SMALL no es más rápido

No constituye necesariamente un error.

Posibles causas:

- La consulta es demasiado corta.
- El tiempo de compilación domina.
- La caché no era equivalente.
- El cuello de botella no escala con más recursos.
- Variación de ejecución.
- Aprovisionamiento.

Ejecuta varias veces y compara medianas de ejecuciones frías equivalentes.

---

### No se suspende exactamente a los 60 segundos

El proceso de auto-suspend comprueba la inactividad aproximadamente cada 30 segundos.

Espera algo más y no ejecutes consultas que utilicen el warehouse.

---

## 20. Respuestas a las preguntas de reflexión

### 1. ¿Aumentar tamaño reduce siempre coste?

No. Cada tamaño cuesta más créditos por unidad de tiempo. Debe reducir la duración lo suficiente para compensarlo.

### 2. ¿Qué implica el mínimo?

Cada reanudación inicia al menos un minuto facturable. Reanudar repetidamente un warehouse para consultas muy cortas puede ser ineficiente.

### 3. ¿Auto-suspend demasiado agresivo?

Puede perder caché, añadir aprovisionamiento y repetir mínimos de facturación.

### 4. ¿Vertical frente a horizontal?

Vertical mejora recursos por clúster. Horizontal añade clústeres para concurrencia.

### 5. ¿Por qué multi-cluster no acelera la consulta?

Una consulta se ejecuta en un clúster. Los clústeres adicionales atienden otras consultas.

### 6. ¿Riesgo de QAS?

Podría añadir compute serverless y atribuir una mejora al tamaño equivocado.

### 7. ¿Métrica de concurrencia?

`QUEUED_OVERLOAD_TIME` y `AVG_QUEUED_LOAD`.

### 8. ¿Warehouses para cada caso?

Desarrollo suele comenzar con XSMALL y suspensión rápida. BI necesita pruebas reales y una suspensión menos agresiva si la caché aporta valor.

---
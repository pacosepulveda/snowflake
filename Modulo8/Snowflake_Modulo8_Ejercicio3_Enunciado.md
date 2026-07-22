# Módulo 8 · Ejercicio 3

## Query Acceleration Service y análisis FinOps del consumo

### Contexto

RetailNova utiliza un warehouse pequeño para un workload mixto:

- La mayoría de las consultas son cortas.
- De forma ocasional aparece una consulta analítica que realiza un escaneo grande.
- El equipo no quiere aumentar permanentemente el tamaño del warehouse por unas pocas consultas atípicas.

Debes evaluar si **Query Acceleration Service (QAS)** es una solución adecuada.

La evaluación no puede limitarse a comprobar si la consulta termina antes. Debe considerar:

1. Elegibilidad real de la consulta.
2. Trabajo que QAS descarga a cómputo serverless.
3. Tiempo total y tiempo de ejecución.
4. Créditos del warehouse.
5. Créditos adicionales de QAS.
6. Latencia de las fuentes de metering.
7. Decisión FinOps basada en rendimiento, coste y frecuencia del workload.

El flujo será:

```text
Consulta analítica
        ↓
Ejecución sin QAS
        ↓
SYSTEM$ESTIMATE_QUERY_ACCELERATION
        ↓
Ejecución con QAS
        ↓
Query History + Query Profile
        ↓
Warehouse Metering + QAS Metering
        ↓
Decisión FinOps
```

---

## Objetivos

Al finalizar el ejercicio deberás ser capaz de:

1. Explicar qué parte de una consulta puede descargar QAS.
2. Crear warehouses comparables con y sin QAS.
3. Seleccionar explícitamente Gen1 para controlar el experimento.
4. Limitar el uso serverless mediante un scale factor.
5. Ejecutar una consulta oficial conocida por ser candidata a QAS.
6. Obtener y conservar los Query ID.
7. Utilizar `SYSTEM$ESTIMATE_QUERY_ACCELERATION`.
8. Interpretar `status`, `upperLimitScaleFactor` y los tiempos estimados.
9. Comparar una ejecución acelerada y otra no acelerada.
10. Comprobar que QAS realmente se utilizó.
11. Interpretar las métricas de bytes y particiones aceleradas.
12. Consultar el consumo del warehouse y el consumo de QAS por separado.
13. Evitar sumar dos veces `CREDITS_USED`.
14. Diferenciar medición casi inmediata e histórico con latencia.
15. Utilizar `QUERY_TAG` para atribuir costes.
16. Comprobar que QAS no acelera todas las consultas.
17. Elaborar una recomendación FinOps.
18. Suspender los recursos al finalizar.

---

## Recursos utilizados

La consulta principal utiliza el conjunto compartido:

```text
SNOWFLAKE_SAMPLE_DATA.TPCDS_SF10TCL
```

Es la consulta de ejemplo utilizada en el tutorial oficial de Snowflake sobre Query Acceleration Service.

El conjunto TPC-DS compartido:

- No consume almacenamiento de la cuenta.
- Es de solo lectura.
- Sí requiere un warehouse activo para ejecutar consultas.

Si `SNOWFLAKE_SAMPLE_DATA` no existe, la solución explica cómo crear la base de datos desde el share oficial.

---

## Convenciones

| Objeto | Nombre |
|---|---|
| Warehouse sin QAS | `WH_M08_NOQAS` |
| Warehouse con QAS | `WH_M08_QAS` |
| Fichero SQL principal | `M08_E03_QAS_FINOPS.sql` |
| Tag sin QAS | `M08_E03_NOQAS` |
| Tag con QAS | `M08_E03_QAS` |
| Tag de consulta de control | `M08_E03_QAS_CONTROL` |

---

## Configuración de los warehouses

Ambos warehouses deben tener:

```text
WAREHOUSE_TYPE = STANDARD
WAREHOUSE_SIZE = XSMALL
GENERATION = 1
MIN_CLUSTER_COUNT = 1
MAX_CLUSTER_COUNT = 1
AUTO_SUSPEND = 60
AUTO_RESUME = TRUE
INITIALLY_SUSPENDED = TRUE
```

Diferencia:

```text
WH_M08_NOQAS
    ENABLE_QUERY_ACCELERATION = FALSE

WH_M08_QAS
    ENABLE_QUERY_ACCELERATION = TRUE
    QUERY_ACCELERATION_MAX_SCALE_FACTOR = 8
```

El factor `8` es un límite de consumo, no una reserva fija de recursos.

---

## Consulta principal

Utiliza exactamente esta lógica:

```sql
SELECT
    d.d_year AS year,
    i.i_brand_id AS brand_id,
    i.i_brand AS brand,
    SUM(s.ss_net_profit) AS profit
FROM SNOWFLAKE_SAMPLE_DATA.TPCDS_SF10TCL.DATE_DIM AS d
JOIN SNOWFLAKE_SAMPLE_DATA.TPCDS_SF10TCL.STORE_SALES AS s
    ON d.d_date_sk = s.ss_sold_date_sk
JOIN SNOWFLAKE_SAMPLE_DATA.TPCDS_SF10TCL.ITEM AS i
    ON s.ss_item_sk = i.i_item_sk
WHERE i.i_manufact_id = 939
  AND d.d_moy = 12
GROUP BY
    d.d_year,
    i.i_brand,
    i.i_brand_id
ORDER BY
    year,
    profit,
    brand_id
LIMIT 200;
```

No cambies filtros, joins, agrupación, orden o límite entre las dos ejecuciones.

---

## Tareas

### Tarea 1. Preparar Workspaces y privilegios

En **Workspaces**, crea:

```text
M08_E03_QAS_FINOPS.sql
```

Configura:

- Rol.
- `USE_CACHED_RESULT = FALSE`.
- Un `QUERY_TAG` de preparación.

Con `ACCOUNTADMIN`:

- Comprueba la existencia de `SNOWFLAKE_SAMPLE_DATA`.
- Concede sus privilegios importados a `SYSADMIN` si es necesario.
- Concede `MONITOR USAGE` a `SYSADMIN` para consultar las funciones de metering.

Vuelve después a `SYSADMIN`.

---

### Tarea 2. Comprobar el sample data

Comprueba que existen:

```text
TPCDS_SF10TCL.DATE_DIM
TPCDS_SF10TCL.STORE_SALES
TPCDS_SF10TCL.ITEM
```

Ejecuta consultas de metadatos o conteos pequeños.

No intentes modificar los objetos compartidos.

---

### Tarea 3. Crear los warehouses

Crea `WH_M08_NOQAS` y `WH_M08_QAS`.

Comprueba mediante `SHOW WAREHOUSES` y `DESC WAREHOUSE`:

- Tamaño.
- Generación.
- Número de clústeres.
- QAS activado o desactivado.
- Scale factor.
- Estado inicial.
- Auto-suspend y auto-resume.

Explica por qué se fija Gen1 explícitamente.

---

### Tarea 4. Ejecutar la consulta sin QAS

Asegúrate de que ambos warehouses están suspendidos.

Con `WH_M08_NOQAS`:

- Establece el tag `M08_E03_NOQAS`.
- Ejecuta la consulta principal.
- Obtén su Query ID.
- Guarda el identificador en una variable de sesión o en tus notas.
- No vuelvas a ejecutar la consulta en ese warehouse.

Registra:

- Tiempo observado.
- Query ID.
- Número de filas.
- Warehouse.

---

### Tarea 5. Estimar el beneficio potencial

Utiliza el Query ID de la ejecución sin QAS con:

```text
SYSTEM$ESTIMATE_QUERY_ACCELERATION
```

Extrae del JSON:

- `status`
- `upperLimitScaleFactor`
- `estimatedQueryTimes`

La consulta oficial debería aparecer como candidata.

Explica:

- Por qué los tiempos son estimaciones.
- Por qué no incluyen concurrencia.
- Por qué el scale factor del warehouse puede ser inferior al límite estimado.

---

### Tarea 6. Ejecutar la consulta con QAS

Con `WH_M08_QAS`:

- Comprueba otra vez que está suspendido.
- Establece el tag `M08_E03_QAS`.
- Ejecuta exactamente la misma consulta.
- Conserva su Query ID.
- No repitas la consulta antes de analizarla.

Ambos warehouses tienen cachés locales independientes y comienzan suspendidos, lo que reduce el sesgo por caché.

---

### Tarea 7. Comparar Query History

Construye un informe para los dos Query ID con:

- Warehouse.
- Tag.
- Estado.
- Tiempo total.
- Tiempo de compilación.
- Tiempo de ejecución.
- Tiempo de aprovisionamiento.
- Bytes escaneados por el warehouse.
- Particiones escaneadas por el warehouse.
- Bytes escaneados por QAS.
- Particiones escaneadas por QAS.
- Scale factor observado.
- Porcentaje de caché local.

Calcula:

```text
mejora de tiempo (%)
= (tiempo_sin_qas - tiempo_con_qas)
  / tiempo_sin_qas
  × 100
```

No presupongas que la mejora será idéntica para todos los alumnos.

---

### Tarea 8. Inspeccionar Query Profile

Abre Query Profile para la ejecución acelerada.

Localiza:

- Resumen de Query Acceleration.
- Scans seleccionados para aceleración.
- Particiones escaneadas por el servicio.
- Operadores `TableScan` afectados.

Explica por qué QAS acelera solo una parte del plan y no sustituye al warehouse.

---

### Tarea 9. Comprobar una consulta no candidata

Ejecuta en `WH_M08_QAS` una consulta puntual y pequeña sobre TPC-H:

```sql
SELECT *
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
WHERE O_ORDERKEY = 12345;
```

Utiliza el tag:

```text
M08_E03_QAS_CONTROL
```

Comprueba:

- Tiempo.
- Bytes y particiones acelerados.
- Resultado de `SYSTEM$ESTIMATE_QUERY_ACCELERATION`.

La consulta debería ser `ineligible` y no consumir QAS.

---

### Tarea 10. Consultar el consumo del warehouse

Utiliza `WAREHOUSE_METERING_HISTORY` para los dos warehouses durante el intervalo del laboratorio.

Muestra:

- `CREDITS_USED`
- `CREDITS_USED_COMPUTE`
- `CREDITS_USED_CLOUD_SERVICES`

Recuerda:

```text
CREDITS_USED
=
CREDITS_USED_COMPUTE
+
CREDITS_USED_CLOUD_SERVICES
```

No sumes las tres columnas.

Explica por qué esta información es horaria y no equivale automáticamente al coste exacto de una sola consulta.

---

### Tarea 11. Consultar el consumo de QAS

Utiliza `QUERY_ACCELERATION_HISTORY` para `WH_M08_QAS`.

Muestra:

- Intervalo.
- Créditos QAS.
- Ficheros escaneados.
- Bytes escaneados.

Calcula conceptualmente:

```text
coste total de la alternativa QAS
=
créditos del warehouse
+
créditos de Query Acceleration
```

Si la función todavía no devuelve una fila, conserva el Query ID y repite la consulta más tarde. La evidencia inmediata de utilización debe obtenerse de Query History y Query Profile.

---

### Tarea 12. Consultar las vistas históricas

Consulta o prepara estas vistas:

```text
SNOWFLAKE.ACCOUNT_USAGE.QUERY_ACCELERATION_ELIGIBLE
SNOWFLAKE.ACCOUNT_USAGE.QUERY_ACCELERATION_HISTORY
SNOWFLAKE.ACCOUNT_USAGE.QUERY_ATTRIBUTION_HISTORY
SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
```

Documenta sus latencias aproximadas:

| Fuente | Latencia máxima aproximada |
|---|---:|
| `QUERY_ACCELERATION_ELIGIBLE` | 3 horas |
| `QUERY_ACCELERATION_HISTORY` | 3 horas |
| `QUERY_ATTRIBUTION_HISTORY` | 8 horas |
| `WAREHOUSE_METERING_HISTORY` | 3 horas; Cloud Services hasta 6 |

Explica para qué utilizarías cada una.

No es obligatorio que todas muestren ya las consultas recién ejecutadas.

---

### Tarea 13. Elaborar la recomendación FinOps

Completa una tabla como esta usando tus resultados:

| Criterio | Sin QAS | Con QAS |
|---|---:|---:|
| Tiempo total |  |  |
| Tiempo de ejecución |  |  |
| Créditos warehouse |  |  |
| Créditos QAS | 0 |  |
| Coste total estimado |  |  |
| Particiones QAS | 0 |  |
| Mejora de tiempo | 0 % |  |

Responde:

1. ¿QAS redujo el tiempo?
2. ¿El ahorro de tiempo justifica el coste adicional?
3. ¿La consulta se ejecuta una vez al mes, una vez al día o cientos de veces?
4. ¿Sería mejor redimensionar el warehouse?
5. ¿Sería mejor optimizar SQL, clustering o pruning antes de activar QAS?
6. ¿Dejarías QAS activo para todo el warehouse?
7. ¿Qué scale factor utilizarías?
8. ¿Qué alerta o Budget configurarías?

---

### Tarea 14. Diseñar una política de adopción

Propón un proceso de producción:

1. Detectar outliers.
2. Identificar consultas elegibles.
3. Estimar el beneficio.
4. Probar con y sin QAS.
5. Medir coste.
6. Seleccionar scale factor.
7. Monitorizar.
8. Revisar periódicamente.

Define también condiciones para retirar QAS.

---

### Tarea 15. Detener el laboratorio

Al finalizar:

- Restaura `USE_CACHED_RESULT`.
- Suspende ambos warehouses.
- Comprueba el estado.
- Mantén los warehouses únicamente si necesitas esperar a que aparezcan los datos históricos.
- Elimínalos cuando termine el análisis.

---

## Resultados no deterministas

Snowflake no garantiza una duración o mejora concreta.

El resultado depende de:

- Disponibilidad del servicio QAS.
- Región.
- Estado de los warehouses.
- Cambios internos en el optimizador.
- Scale factor.
- Volumen elegible del plan.
- Carga concurrente del servicio.
- Aprovisionamiento.
- Variación normal de ejecución.

La consulta debe considerarse acelerada cuando las métricas indiquen trabajo realizado por QAS, no solo porque haya terminado más rápido.

---

## Preguntas de reflexión

1. ¿Por qué QAS puede ser más eficiente que mantener un warehouse grande todo el día?
2. ¿Por qué QAS no garantiza acelerar cualquier consulta?
3. ¿Qué significa el scale factor?
4. ¿Por qué `scale factor = 8` no implica consumir siempre ocho veces el warehouse?
5. ¿Por qué `scale factor = 0` puede ser arriesgado?
6. ¿Por qué los bytes escaneados totales pueden aumentar al utilizar QAS?
7. ¿Por qué los créditos QAS se suman a los créditos del warehouse?
8. ¿Qué diferencia existe entre una estimación y una medición real?
9. ¿Por qué `QUERY_TAG` es importante en FinOps?
10. ¿Qué optimizaciones probarías antes de activar QAS de forma general?

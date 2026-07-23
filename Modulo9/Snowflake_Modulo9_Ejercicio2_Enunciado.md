# Módulo 9 · Ejercicio 2
## Clustering keys y Automatic Clustering: beneficio, mantenimiento y coste

### Contexto

En el ejercicio anterior, RetailNova comprobó que una tabla ordenada por fecha puede leer muchas menos micro-partitions que una tabla cuyos días están mezclados.

Ahora debe decidir si merece la pena mantener esa organización de forma automática.

El equipo propone definir:

```text
CLUSTER BY (fecha)
```

sobre una tabla que recibe cargas desordenadas. Sin embargo, una clustering key no es gratuita:

- Snowflake puede ejecutar reclustering inicial.
- El mantenimiento posterior utiliza cómputo serverless.
- Las operaciones DML pueden volver a degradar el clustering.
- Una tabla demasiado pequeña puede no justificar el servicio.
- Snowflake decide cuándo existe beneficio suficiente para reclusterizar.

Debes construir un experimento controlado que permita evaluar rendimiento y coste antes de recomendar Automatic Clustering.

---

## Arquitectura del laboratorio

```text
VENTAS_RENDIMIENTO
        ↓
Carga de 30 millones de filas
        ↓
VENTAS_CLUSTER_AUTO
        │
        ├── Clustering key: FECHA
        ├── Automatic Clustering inicialmente suspendido
        └── Datos cargados en orden desfavorable
                    ↓
       Estimación de coste + benchmark inicial
                    ↓
          RESUME RECLUSTER
                    ↓
       Seguimiento de profundidad y créditos
                    ↓
           Benchmark posterior
```

---

## Objetivos

Al finalizar el ejercicio deberás ser capaz de:

1. Diferenciar clustering natural y clustering key.
2. Crear una tabla con clustering key y Automatic Clustering suspendido.
3. Cargar datos de forma deliberadamente desfavorable.
4. Consultar `CLUSTERING_KEY` y `AUTO_CLUSTERING_ON`.
5. Interpretar profundidad, solapamiento y particiones constantes.
6. Estimar el coste inicial y de mantenimiento.
7. Comprender que la estimación no es una garantía.
8. Activar y suspender Automatic Clustering.
9. Demostrar que el reclustering no utiliza el warehouse del usuario.
10. Observar que el proceso es asíncrono y puede no comenzar inmediatamente.
11. Consultar errores recientes de clustering.
12. Medir el consumo serverless de Automatic Clustering.
13. Comparar pruning antes y después.
14. Evaluar si la mejora justifica el mantenimiento.
15. Evitar habilitar clustering indiscriminadamente.
16. Dejar la tabla suspendida para impedir nuevos cargos.

---

## Prerrequisitos

Debe existir:

```text
DB_CURSO.PERFORMANCE.VENTAS_RENDIMIENTO
```

con diez millones de filas.

También pueden existir las tablas del ejercicio anterior:

```text
VENTAS_MP_DESORDENADAS
VENTAS_MP_ORDENADAS
```

La solución incluye recuperación si falta `VENTAS_RENDIMIENTO`.

---

## Convenciones

| Objeto | Nombre |
|---|---|
| Base de datos | `DB_CURSO` |
| Esquema | `PERFORMANCE` |
| Warehouse | `WH_M09_CLUSTER` |
| Tabla candidata | `VENTAS_CLUSTER_AUTO` |
| Tabla de mediciones | `CLUSTERING_MEDICIONES` |
| Baseline opcional | `VENTAS_CLUSTER_BASELINE` |
| Fichero SQL | `M09_E02_AUTOMATIC_CLUSTERING.sql` |

---

## Volumen del laboratorio

La tabla candidata contendrá:

```text
30.000.000 filas
```

Se obtendrá replicando tres veces las diez millones de ventas originales con identificadores distintos.

Las fechas seguirán un patrón cíclico, por lo que filas consecutivas recorrerán continuamente los 365 días. Esto crea solapamiento respecto a `FECHA`.

La consulta de siete días debe producir:

```text
15 grupos
452.052 ventas completadas
importe neto = 222.650.999,46
```

Los valores de particiones, profundidad, duración y créditos no son fijos.

---

## Condiciones del warehouse

```text
WAREHOUSE_TYPE = STANDARD
WAREHOUSE_SIZE = XSMALL
GENERATION = 1
MIN_CLUSTER_COUNT = 1
MAX_CLUSTER_COUNT = 1
AUTO_SUSPEND = 60
AUTO_RESUME = TRUE
ENABLE_QUERY_ACCELERATION = FALSE
```

El warehouse solo se utiliza para:

- Crear y cargar la tabla.
- Ejecutar los benchmarks.
- Consultar metadatos.

Automatic Clustering utiliza cómputo serverless independiente.

---

## Tags del benchmark

| Fase | Query tag |
|---|---|
| Antes del reclustering | `M09_E02_ANTES_CLUSTERING` |
| Después del reclustering | `M09_E02_DESPUES_CLUSTERING` |
| Baseline física opcional | `M09_E02_BASELINE_ORDENADA` |

---

## Tareas

### Tarea 1. Preparar Workspaces y privilegios

En **Workspaces**, crea:

```text
M09_E02_AUTOMATIC_CLUSTERING.sql
```

Configura:

- Rol.
- Base de datos.
- Esquema.
- Query tag de preparación.

Con `ACCOUNTADMIN`, concede a `SYSADMIN`:

```text
MONITOR USAGE
```

para consultar el historial de consumo serverless.

Vuelve después a `SYSADMIN`.

---

### Tarea 2. Crear y comprobar el warehouse

Crea `WH_M09_CLUSTER` con la configuración indicada.

Comprueba:

- Estado inicial.
- Tamaño.
- Generación.
- QAS.
- Auto-suspend.
- Auto-resume.
- Número de clústeres.

Explica por qué Automatic Clustering no se ejecutará dentro de este warehouse.

---

### Tarea 3. Comprobar la tabla de origen

Valida:

```text
10.000.000 filas
fecha mínima 2025-01-01
fecha máxima 2025-12-31
```

Si falta la tabla, utiliza la sección de recuperación de la solución.

---

### Tarea 4. Crear la tabla candidata sin provocar reclustering inicial

Crea una tabla vacía con la misma estructura que la fuente:

```text
VENTAS_CLUSTER_AUTO
```

Después:

1. Define `CLUSTER BY (fecha)` mientras la tabla está vacía.
2. Suspende inmediatamente Automatic Clustering.
3. Comprueba que:
   - La clustering key existe.
   - `AUTO_CLUSTERING_ON = FALSE`.
   - La tabla continúa vacía.

El orden es importante: al suspender antes de cargar los datos se evita que el servicio comience a reclusterizar durante la preparación.

---

### Tarea 5. Cargar treinta millones de filas desordenadas

Inserta tres copias de la tabla fuente.

Requisitos:

- Identificadores de venta únicos.
- Mismos valores de negocio.
- Orden de salida por el nuevo `id_venta`.
- Automatic Clustering suspendido durante toda la carga.

Comprueba:

```text
30.000.000 filas
30.000.000 identificadores distintos
365 fechas distintas
```

Suspende el warehouse después de la carga.

---

### Tarea 6. Registrar el estado inicial

Crea:

```text
CLUSTERING_MEDICIONES
```

y guarda una medición con fase:

```text
ANTES
```

Debe registrar:

- Momento.
- Número de particiones.
- Particiones constantes.
- Solapamiento medio.
- Profundidad media.
- Notas.
- Histograma de profundidad.

Utiliza la clustering key definida, sin repetir la expresión cuando no sea necesario.

---

### Tarea 7. Analizar claves alternativas

Sin modificar la tabla, compara la profundidad respecto a:

```text
(FECHA)
(REGION)
(FECHA, REGION)
(ID_VENTA)
```

Responde:

1. ¿Qué columnas aparecen en los filtros más frecuentes?
2. ¿Cuál tiene una cardinalidad excesiva?
3. ¿Qué clave ayuda a consultas por fecha?
4. ¿Añadir `REGION` aportaría valor suficiente?
5. ¿Por qué un buen clustering respecto a `ID_VENTA` no implica que sea la mejor clustering key?

---

### Tarea 8. Ejecutar el benchmark inicial

Configura:

```text
USE_CACHED_RESULT = FALSE
```

Suspende el warehouse antes de la consulta.

Ejecuta sobre `VENTAS_CLUSTER_AUTO` el filtro:

```text
2025-06-01 inclusive
2025-06-08 exclusive
estado = COMPLETADA
```

Agrupa por región y canal.

Utiliza:

```text
M09_E02_ANTES_CLUSTERING
```

Conserva el Query ID y registra:

- Tiempo de ejecución.
- Bytes.
- Particiones leídas.
- Particiones totales.
- Porcentaje de pruning.

---

### Tarea 9. Estimar el coste antes de activar

Ejecuta:

```text
SYSTEM$ESTIMATE_AUTOMATIC_CLUSTERING_COSTS
```

sobre la clave actual.

Extrae:

- Fecha del informe.
- Clustering key.
- Coste inicial estimado.
- Unidad.
- Comentario.
- Coste de mantenimiento, si está disponible.
- Advertencias.

No ejecutes la función repetidamente en todas las cuentas sin necesidad.

Explica por qué la estimación puede variar ampliamente frente al coste real.

---

### Tarea 10. Activar Automatic Clustering

Ejecuta:

```text
RESUME RECLUSTER
```

Comprueba que:

```text
AUTO_CLUSTERING_ON = TRUE
```

Suspende inmediatamente `WH_M09_CLUSTER`.

Observa durante unos minutos que:

- El warehouse permanece suspendido.
- La profundidad puede cambiar.
- El número de particiones puede cambiar.
- Automatic Clustering puede tardar en comenzar.
- Snowflake puede decidir que una tabla no obtiene suficiente beneficio.

No ejecutes una consulta de sondeo cada pocos segundos. Un intervalo de dos o tres minutos es suficiente.

---

### Tarea 11. Monitorizar progreso y errores

Registra varias mediciones:

```text
DURANTE_1
DURANTE_2
DESPUES
```

Consulta también los errores recientes mediante `SYSTEM$CLUSTERING_INFORMATION`.

La actividad puede considerarse suficiente cuando se cumple alguna de estas condiciones:

- La profundidad baja de forma material.
- Las particiones constantes aumentan.
- El benchmark lee menos particiones.
- El historial serverless muestra bytes o filas reclusterizados.

No se exige llegar a profundidad `1`.

---

### Tarea 12. Consultar el historial de Automatic Clustering

Prepara una consulta sobre:

```text
SNOWFLAKE.ACCOUNT_USAGE.AUTOMATIC_CLUSTERING_HISTORY
```

para obtener:

- Inicio y fin.
- Créditos.
- Bytes reclusterizados.
- Filas reclusterizadas.
- Base, esquema y tabla.

La vista puede tardar hasta tres horas.

Consulta también:

```text
SNOWFLAKE.ACCOUNT_USAGE.METERING_HISTORY
```

con:

```text
SERVICE_TYPE = AUTO_CLUSTERING
```

Explica por qué este consumo no aparece en el historial de `WH_M09_CLUSTER`.

---

### Tarea 13. Ejecutar el benchmark posterior

Cuando el estado haya mejorado o el instructor cierre la ventana de observación:

1. Suspende Automatic Clustering.
2. Suspende el warehouse.
3. Ejecuta la misma consulta con:
   - Misma tabla.
   - Mismo rango.
   - Mismas columnas.
   - Result cache desactivada.
4. Utiliza:

```text
M09_E02_DESPUES_CLUSTERING
```

Compara con la ejecución inicial.

El resultado de negocio debe seguir siendo idéntico.

---

### Tarea 14. Aplicar el plan alternativo cuando no haya reclustering observable

Automatic Clustering no garantiza actividad inmediata.

Si después de una ventana razonable no hay cambios:

1. Documenta:
   - Estado `ON`.
   - Profundidad.
   - Errores.
   - Ausencia de actividad visible.
2. Suspende Automatic Clustering.
3. Crea opcionalmente una baseline física:

```text
VENTAS_CLUSTER_BASELINE
```

mediante CTAS ordenada por:

```text
fecha, id_venta
```

4. Ejecuta la consulta con:

```text
M09_E02_BASELINE_ORDENADA
```

Esta baseline permite demostrar el beneficio potencial del orden, pero no representa el coste de mantenimiento automático.

---

### Tarea 15. Demostrar el control operativo

Con la tabla ya clusterizada o parcialmente mejorada:

1. Ejecuta `SUSPEND RECLUSTER`.
2. Comprueba `AUTO_CLUSTERING_ON = FALSE`.
3. Explica qué ocurriría tras nuevas cargas desordenadas.
4. Ejecuta `RESUME RECLUSTER`.
5. Comprueba `AUTO_CLUSTERING_ON = TRUE`.
6. Vuelve a suspenderlo para cerrar el laboratorio.

No dejes Automatic Clustering habilitado después de la clase.

---

### Tarea 16. Comparar estimación y consumo real

Cuando el historial esté disponible, crea una tabla de análisis:

| Métrica | Valor |
|---|---:|
| Coste inicial estimado |  |
| Créditos reales observados |  |
| Bytes reclusterizados |  |
| Filas reclusterizadas |  |
| Profundidad inicial |  |
| Profundidad final |  |
| Particiones leídas antes |  |
| Particiones leídas después |  |
| Mejora de ejecución |  |

Explica por qué las filas reclusterizadas pueden superar el número de filas de la tabla.

---

### Tarea 17. Elaborar una recomendación FinOps

Redacta una decisión para RetailNova:

- `ACTIVAR`
- `NO ACTIVAR`
- `PROBAR DURANTE UN PERIODO LIMITADO`

Justifica:

1. Tamaño real de la tabla.
2. Frecuencia de consultas.
3. Selectividad temporal.
4. Volumen y frecuencia de DML.
5. Beneficio de pruning.
6. Créditos iniciales.
7. Créditos de mantenimiento.
8. Alternativa de cargar los datos ya ordenados.
9. Alternativa de una tabla agregada.
10. Riesgo de habilitar clustering en muchas tablas a la vez.

---

### Tarea 18. Dejar los recursos seguros

Al finalizar:

- Suspende Automatic Clustering.
- Restaura `USE_CACHED_RESULT`.
- Suspende `WH_M09_CLUSTER`.
- Conserva la tabla y las mediciones para revisión.
- Elimina la baseline opcional si fue creada y no se necesita.

---

## Resultados no deterministas

Snowflake decide automáticamente si una tabla se beneficiará del reclustering.

No se puede exigir:

- Inicio inmediato.
- Número fijo de créditos.
- Profundidad final concreta.
- Una sola pasada.
- Una mejora temporal exacta.

Una tabla puede necesitar varias pasadas, y una misma fila puede ser reclusterizada más de una vez.

La práctica es correcta cuando el alumno puede medir, interpretar y justificar la decisión, incluso si Snowflake decide no iniciar trabajo visible durante la sesión.

---

## Criterios de finalización

El ejercicio se considera completado cuando puedas demostrar que:

- La tabla contiene treinta millones de filas.
- Tiene clustering key sobre `FECHA`.
- Se cargó con Automatic Clustering suspendido.
- Existe una medición inicial.
- Se obtuvo una estimación de coste.
- Se activó y comprobó el servicio.
- El warehouse permaneció independiente del reclustering.
- Se registró progreso o se documentó correctamente la ausencia de actividad.
- Se ejecutó una comparación de pruning.
- Se preparó el análisis de créditos.
- La recomendación tiene en cuenta rendimiento y coste.
- Automatic Clustering queda suspendido al terminar.

---

## Preguntas de reflexión

1. ¿Por qué definir una clustering key puede generar coste inmediato?
2. ¿Por qué Snowflake no reclusteriza siempre de forma inmediata?
3. ¿Qué diferencia existe entre ordenar una carga y mantener clustering continuamente?
4. ¿Por qué una clave de alta cardinalidad puede ser problemática?
5. ¿Qué significa `average_depth`?
6. ¿Por qué la profundidad no tiene que llegar a uno?
7. ¿Por qué las filas reclusterizadas pueden superar las filas de la tabla?
8. ¿Qué consumo corresponde al warehouse y cuál al servicio serverless?
9. ¿Cuándo preferirías reconstruir una tabla ordenada?
10. ¿Por qué debes comenzar con una o dos tablas y no con todo el catálogo?

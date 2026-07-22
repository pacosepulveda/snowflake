# Módulo 8 · Ejercicio 2

## Concurrencia con multi-cluster warehouses y control presupuestario con Resource Monitors

### Contexto

RetailNova utiliza un warehouse de BI que funciona correctamente cuando hay pocos usuarios, pero en las horas punta varias consultas quedan en cola. El equipo ha propuesto dos soluciones diferentes:

- Aumentar el tamaño del warehouse.
- Convertirlo en multi-cluster para atender más consultas simultáneamente.

El problema observado es de **concurrencia**, no necesariamente de velocidad de una consulta individual. Debes reproducir una situación de cola, convertir el warehouse a modo multi-cluster y comprobar qué cambia.

Además, el equipo FinOps quiere limitar el riesgo económico. Configurarás un Resource Monitor que controle el consumo del warehouse y aplique avisos y acciones de suspensión.

El laboratorio combinará:

```text
Carga concurrente
        ↓
Single cluster frente a multi-cluster
        ↓
STANDARD frente a ECONOMY
        ↓
Resource Monitor
        ↓
Análisis de rendimiento y coste
```

---

## Objetivos

Al finalizar el ejercicio deberás ser capaz de:

1. Diferenciar escalado vertical y horizontal.
2. Crear un warehouse single-cluster y convertirlo en multi-cluster.
3. Configurar los modos auto-scale y maximized.
4. Utilizar `MAX_CONCURRENCY_LEVEL` para provocar una cola controlada.
5. Ejecutar consultas concurrentes desde varios ficheros de Workspaces.
6. Observar consultas ejecutándose y en cola mediante `SHOW WAREHOUSES`.
7. Comparar `queued_overload_time` entre varias configuraciones.
8. Utilizar `WAREHOUSE_LOAD_HISTORY`.
9. Diferenciar las políticas `STANDARD` y `ECONOMY`.
10. Explicar por qué multi-cluster no acelera una consulta individual.
11. Crear y asignar un Resource Monitor.
12. Configurar `NOTIFY`, `SUSPEND` y `SUSPEND_IMMEDIATE`.
13. Delegar `MONITOR` y `MODIFY` sobre un Resource Monitor.
14. Comprobar la asignación del monitor al warehouse.
15. Modificar una cuota y comprender que los triggers se reemplazan.
16. Explicar qué consumo cubre un Resource Monitor y qué consumo requiere Budgets.
17. Detener y dejar los recursos en un estado seguro.

---

## Prerrequisito

El ejercicio reutiliza:

```text
DB_CURSO.PERFORMANCE.VENTAS_RENDIMIENTO
```

creada en el ejercicio anterior con diez millones de filas.

La solución contiene una sección de recuperación para crearla si no existe.

---

## Convenciones

| Objeto | Nombre |
|---|---|
| Base de datos | `DB_CURSO` |
| Esquema | `PERFORMANCE` |
| Warehouse | `WH_M08_CONC` |
| View de carga | `V_CARGA_CONCURRENCIA` |
| Resource Monitor | `RM_M08_CONC` |
| Fichero principal | `M08_E02_CONCURRENCIA_RM.sql` |
| Ficheros de carga | `M08_E02_Q1.sql` a `M08_E02_Q4.sql` |
| Fichero de monitorización | `M08_E02_MONITOR.sql` |

---

## Configuración inicial del warehouse

El warehouse debe comenzar como single-cluster:

```text
WAREHOUSE_TYPE = STANDARD
WAREHOUSE_SIZE = XSMALL
GENERATION = 1
MIN_CLUSTER_COUNT = 1
MAX_CLUSTER_COUNT = 1
MAX_CONCURRENCY_LEVEL = 1
SCALING_POLICY = STANDARD
AUTO_SUSPEND = 60
AUTO_RESUME = TRUE
STATEMENT_QUEUED_TIMEOUT_IN_SECONDS = 300
ENABLE_QUERY_ACCELERATION = FALSE
```

`MAX_CONCURRENCY_LEVEL = 1` se utiliza para crear una demostración clara. No es una recomendación general para producción.

---

## Tareas

### Tarea 1. Preparar Workspaces

Crea en **Workspaces**:

```text
M08_E02_CONCURRENCIA_RM.sql
M08_E02_Q1.sql
M08_E02_Q2.sql
M08_E02_Q3.sql
M08_E02_Q4.sql
M08_E02_MONITOR.sql
```

El fichero principal se utilizará para crear y modificar objetos.

Los cuatro ficheros `Q1` a `Q4` permitirán iniciar consultas casi simultáneamente.

El fichero `MONITOR` permitirá observar el warehouse sin modificar las consultas de carga.

---

### Tarea 2. Comprobar el conjunto de datos

Verifica que existe:

```text
DB_CURSO.PERFORMANCE.VENTAS_RENDIMIENTO
```

y que contiene diez millones de filas.

Si no existe, utiliza la sección de recuperación de la solución.

No recrees la tabla si ya está disponible.

---

### Tarea 3. Crear el warehouse single-cluster

Crea `WH_M08_CONC` con la configuración inicial.

Comprueba:

- Tamaño.
- Generación.
- Clústeres mínimos y máximos.
- Clústeres iniciados.
- Nivel de concurrencia.
- Tiempo máximo en cola.
- QAS desactivado.
- Auto-suspend y auto-resume.

Explica por qué QAS debe quedar desactivado en este experimento.

---

### Tarea 4. Crear la consulta de carga

Crea `V_CARGA_CONCURRENCIA`.

La view debe:

1. Leer las ventas completadas.
2. Agrupar por mes, región, canal y cliente.
3. Calcular ventas, importe neto y percentiles.
4. Aplicar una función de ventana para clasificar clientes.
5. Generar un resultado final pequeño por mes, región y canal.

La consulta debe procesar un volumen significativo sin devolver millones de filas al cliente.

---

### Tarea 5. Preparar los cuatro ficheros de carga

Cada fichero debe:

- Seleccionar `WH_M08_CONC`.
- Desactivar `USE_CACHED_RESULT`.
- Establecer un `QUERY_TAG` único.
- Ejecutar exactamente la misma consulta sobre `V_CARGA_CONCURRENCIA`.

Utiliza estos tags para la primera fase:

```text
M08_E02_SINGLE_Q1
M08_E02_SINGLE_Q2
M08_E02_SINGLE_Q3
M08_E02_SINGLE_Q4
```

---

### Tarea 6. Probar el warehouse single-cluster

Asegúrate de que:

```text
MAX_CLUSTER_COUNT = 1
MAX_CONCURRENCY_LEVEL = 1
```

Suspende el warehouse.

Desde los cuatro ficheros de carga, inicia las consultas con la menor diferencia de tiempo posible.

Mientras se ejecutan, utiliza el fichero de monitorización para observar:

- `state`
- `started_clusters`
- `running`
- `queued`
- `min_cluster_count`
- `max_cluster_count`

Resultado conceptual esperado:

- Un clúster iniciado.
- Al menos una consulta ejecutándose.
- Una o más consultas en cola.
- `queued_overload_time` superior a cero en algunas consultas.

Los resultados exactos dependerán de la duración de la consulta y de la capacidad disponible.

---

### Tarea 7. Analizar la primera fase

Consulta Query History para los cuatro tags.

Muestra:

- Tiempo total.
- Tiempo de ejecución.
- Tiempo en cola por sobrecarga.
- Tiempo en cola por aprovisionamiento.
- Bytes escaneados.
- Particiones escaneadas.
- Estado.

Calcula:

- Tiempo medio total.
- Tiempo medio de cola.
- Tiempo máximo de cola.
- Número de consultas que esperaron por sobrecarga.

---

### Tarea 8. Convertir a multi-cluster STANDARD

Modifica `WH_M08_CONC`:

```text
MIN_CLUSTER_COUNT = 1
MAX_CLUSTER_COUNT = 2
SCALING_POLICY = STANDARD
```

Mantén:

```text
MAX_CONCURRENCY_LEVEL = 1
ENABLE_QUERY_ACCELERATION = FALSE
```

Comprueba que el warehouse está en modo auto-scale y no maximized.

Actualiza los tags de los cuatro ficheros:

```text
M08_E02_STANDARD_Q1
M08_E02_STANDARD_Q2
M08_E02_STANDARD_Q3
M08_E02_STANDARD_Q4
```

Suspende el warehouse y repite la carga concurrente.

Durante la ejecución intenta observar:

```text
started_clusters = 2
```

Si las consultas terminan antes de que el segundo clúster se aprovisione, repite la prueba. No aumentes el número máximo por encima de dos.

---

### Tarea 9. Comparar single-cluster y STANDARD

Compara ambas fases:

- Consultas con cola.
- Tiempo medio de cola.
- Tiempo máximo de cola.
- Tiempo total del grupo completo.
- Clústeres iniciados.
- Aprovisionamiento.
- Consumo potencial.

Explica por qué:

- El segundo clúster mejora el throughput.
- No convierte una consulta individual en una consulta distribuida entre dos clústeres.
- El coste por unidad de tiempo puede duplicarse mientras ambos clústeres están activos.

---

### Tarea 10. Probar la política ECONOMY

Cambia únicamente:

```text
SCALING_POLICY = ECONOMY
```

Utiliza estos tags:

```text
M08_E02_ECONOMY_Q1
M08_E02_ECONOMY_Q2
M08_E02_ECONOMY_Q3
M08_E02_ECONOMY_Q4
```

Repite la carga.

Compara con `STANDARD`:

- Momento en que aparece el segundo clúster.
- Consultas en cola.
- Tiempo medio y máximo de cola.
- Duración total de la fase.

No se exige una diferencia fija. `ECONOMY` puede conservar créditos a cambio de tolerar más cola.

---

### Tarea 11. Consultar Warehouse Load History

Espera al menos un minuto después de las pruebas.

Consulta `WAREHOUSE_LOAD_HISTORY` para los últimos treinta minutos y muestra:

- `AVG_RUNNING`
- `AVG_QUEUED_LOAD`
- `AVG_QUEUED_PROVISIONING`
- `AVG_BLOCKED`

Explica por qué los valores representan carga relativa durante un intervalo y no un simple número de consultas.

---

### Tarea 12. Crear el Resource Monitor

Con `ACCOUNTADMIN`, crea `RM_M08_CONC` con:

```text
CREDIT_QUOTA = 2
FREQUENCY = MONTHLY
START_TIMESTAMP = IMMEDIATELY
```

Triggers:

```text
50 %  → NOTIFY
80 %  → NOTIFY
90 %  → SUSPEND
100 % → SUSPEND_IMMEDIATE
```

Concede a `SYSADMIN`:

```text
MONITOR
MODIFY
```

sobre el monitor.

Asigna el monitor a `WH_M08_CONC` y vuelve a `SYSADMIN`.

---

### Tarea 13. Inspeccionar el monitor

Utiliza:

```text
SHOW RESOURCE MONITORS
SHOW WAREHOUSES
```

Comprueba:

- Cuota.
- Créditos usados.
- Nivel `WAREHOUSE`.
- Warehouse asignado.
- Umbrales.
- Monitor visible desde `SYSADMIN`.

No se exige que los avisos se hayan disparado.

Las notificaciones deben habilitarse para el usuario antes de que se reciban por correo o en Snowsight.

---

### Tarea 14. Modificar la política presupuestaria

Desde `SYSADMIN`, cambia:

```text
CREDIT_QUOTA = 3
```

y los triggers a:

```text
60 %  → NOTIFY
85 %  → NOTIFY
95 %  → SUSPEND
105 % → SUSPEND_IMMEDIATE
```

Comprueba que los triggers anteriores han sido reemplazados.

Explica por qué un umbral superior al 100 % puede ser válido.

---

### Tarea 15. Diseñar un control por workload

Propón Resource Monitors independientes para:

- Desarrollo.
- BI.
- ETL.

Para cada workload indica:

- Cuota.
- Frecuencia.
- Umbrales.
- Acción final.
- Usuarios o roles que deberían recibir avisos.
- Si debe compartir monitor con otros warehouses.

---

### Tarea 16. Identificar límites del Resource Monitor

Explica por qué un Resource Monitor no basta para controlar todo el gasto de Snowflake.

Clasifica estos consumos:

| Consumo | Resource Monitor o Budget |
|---|---|
| Warehouse de BI |  |
| Warehouse de ETL |  |
| Snowpipe serverless |  |
| Automatic Clustering |  |
| Serverless Tasks |  |
| Query Acceleration Service |  |
| AI Services |  |

---

### Tarea 17. Dejar el laboratorio seguro

Al finalizar:

1. Cambia el warehouse a:
   - `MIN_CLUSTER_COUNT = 1`
   - `MAX_CLUSTER_COUNT = 1`
   - `SCALING_POLICY = STANDARD`
   - `MAX_CONCURRENCY_LEVEL = 8`
2. Desasigna el Resource Monitor con `ACCOUNTADMIN`.
3. Elimina `RM_M08_CONC`.
4. Suspende `WH_M08_CONC`.
5. Restaura `USE_CACHED_RESULT` en todos los ficheros.

No elimines la tabla de diez millones de filas.

---

## Consideraciones sobre resultados

No todas las cuentas mostrarán exactamente dos clústeres durante la primera ejecución.

Puede ocurrir que:

- La consulta termine demasiado rápido.
- El segundo clúster termine de aprovisionarse cuando queda poco trabajo.
- Una consulta pequeña cuente como una fracción del nivel de concurrencia.
- La caché reduzca la duración de una fase.
- La disponibilidad regional altere el aprovisionamiento.

La conclusión debe combinar:

```text
SHOW WAREHOUSES
QUERY_HISTORY
WAREHOUSE_LOAD_HISTORY
```

y no basarse en una única captura.

---

## Preguntas de reflexión

1. ¿Por qué un warehouse más grande y un warehouse multi-cluster resuelven problemas distintos?
2. ¿Qué métrica identifica mejor una falta de capacidad concurrente?
3. ¿Por qué `MAX_CONCURRENCY_LEVEL = 1` no es una recomendación general?
4. ¿Qué diferencia existe entre auto-scale y maximized?
5. ¿Por qué `STANDARD` suele reducir la cola antes que `ECONOMY`?
6. ¿Por qué un monitor asignado a varios warehouses puede ser más difícil de interpretar?
7. ¿Qué diferencia existe entre `SUSPEND` y `SUSPEND_IMMEDIATE`?
8. ¿Por qué un Resource Monitor no garantiza un límite exacto al crédito?
9. ¿Qué ocurre con un warehouse después de alcanzar un trigger de suspensión?
10. ¿Por qué las notificaciones no deben ser el único mecanismo de control?

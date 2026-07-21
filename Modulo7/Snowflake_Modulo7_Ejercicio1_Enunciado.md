# Módulo 7 · Ejercicio 1

## Pipeline CDC con un append-only stream y una triggered task

### Contexto

RetailNova recibe eventos de pedidos desde varios sistemas. Cada cambio de estado se añade como una nueva fila a una tabla de aterrizaje; los eventos anteriores no se actualizan ni se eliminan.

Un mismo pedido puede aparecer varias veces:

```text
PENDIENTE → COMPLETADA
PENDIENTE → CANCELADA
```

La capa `CURATED` debe conservar únicamente el estado más reciente de cada pedido.

El equipo quiere evitar una tarea que consulte la tabla cada minuto aunque no haya cambios. Para ello utilizará:

- Un **append-only stream** que expone únicamente los eventos nuevos.
- Una **triggered task** que se ejecuta cuando el stream tiene cambios.
- Un `MERGE` que deduplica el microbatch y actualiza la tabla de estado actual.

El flujo será:

```text
STAGING.PEDIDOS_EVENTOS_RAW
            ↓
STAGING.STR_PEDIDOS_EVENTOS
            ↓
TASK_PROCESAR_PEDIDOS
            ↓
CURATED.PEDIDOS_ACTUALES
```

---

## Objetivos

Al finalizar el ejercicio deberás ser capaz de:

1. Explicar qué almacena realmente un stream.
2. Crear un append-only stream sobre una tabla de eventos.
3. Consultar `METADATA$ACTION`, `METADATA$ISUPDATE` y `METADATA$ROW_ID`.
4. Demostrar que un `SELECT` no consume un stream.
5. Demostrar que un DML revertido con `ROLLBACK` no avanza el offset.
6. Comprobar que el offset avanza al confirmar un DML consumidor.
7. Utilizar `SYSTEM$STREAM_HAS_DATA`.
8. Crear una task disparada por cambios, sin `SCHEDULE`.
9. Deduplicar cada microbatch antes del `MERGE`.
10. Insertar pedidos nuevos y actualizar versiones más recientes.
11. Ignorar versiones antiguas o iguales.
12. Monitorizar la task mediante `TASK_HISTORY`.
13. Verificar que una triggered task muestra `TRIGGER` como origen de ejecución.
14. Suspender la task al finalizar para controlar el consumo.

---

## Convenciones

| Objeto | Nombre |
|---|---|
| Base de datos | `DB_CURSO` |
| Esquema de aterrizaje | `STAGING` |
| Esquema de destino | `CURATED` |
| Warehouse | `WH_DEV` |
| Tabla de eventos | `PEDIDOS_EVENTOS_RAW` |
| Stream | `STR_PEDIDOS_EVENTOS` |
| Tabla destino | `PEDIDOS_ACTUALES` |
| Tabla de prueba transaccional | `STREAM_PRUEBA_ROLLBACK` |
| Task | `TASK_PROCESAR_PEDIDOS` |
| Fichero SQL del workspace | `M07_E01_STREAM_TRIGGERED_TASK.sql` |

---

## Diseño de los datos

### Tabla de eventos

Cada fila representa una versión de un pedido:

| Columna | Finalidad |
|---|---|
| `event_id` | Identificador único del evento |
| `id_pedido` | Clave de negocio |
| `id_cliente` | Cliente |
| `fecha_pedido` | Fecha del pedido |
| `importe` | Importe actual |
| `estado` | Estado de la versión |
| `fecha_modificacion` | Versión de negocio |
| `_source_file` | Origen |
| `_loaded_at` | Momento de carga |

La tabla funciona como un log append-only: los cambios se representan mediante nuevos eventos.

### Tabla CURATED

Debe conservar una sola fila por `id_pedido`, correspondiente a la versión con mayor:

1. `fecha_modificacion`.
2. `event_id`, como criterio de desempate.

---

## Tareas

### Tarea 1. Preparar Workspaces y los privilegios

En **Workspaces**, crea un fichero SQL llamado:

```text
M07_E01_STREAM_TRIGGERED_TASK.sql
```

Configura:

- Warehouse `XSMALL`.
- Auto-suspend de 60 segundos.
- Rol, base de datos y esquemas.
- Un `QUERY_TAG`.

Las tasks requieren el privilegio global `EXECUTE TASK`. Con `ACCOUNTADMIN`, concédelo a `SYSADMIN` y vuelve después a `SYSADMIN`.

> Utiliza Workspaces, no Legacy Worksheets.

---

### Tarea 2. Crear la tabla de eventos y el stream

Crea una tabla transitoria:

```text
DB_CURSO.STAGING.PEDIDOS_EVENTOS_RAW
```

Crea después:

```text
DB_CURSO.STAGING.STR_PEDIDOS_EVENTOS
```

como stream append-only.

Comprueba:

- Que el stream existe.
- Que inicialmente está vacío.
- Que `SYSTEM$STREAM_HAS_DATA` devuelve `FALSE`.

---

### Tarea 3. Crear el destino y la tabla de prueba

Crea:

```text
DB_CURSO.CURATED.PEDIDOS_ACTUALES
```

con una fila por pedido y una columna `_processed_at`.

Crea también:

```text
DB_CURSO.STAGING.STREAM_PRUEBA_ROLLBACK
```

para demostrar el comportamiento transaccional del offset.

---

### Tarea 4. Insertar el primer microbatch

Inserta cinco eventos:

| event_id | id_pedido | importe | estado | fecha_modificacion |
|---:|---:|---:|---|---|
| 1 | 8101 | 100.00 | PENDIENTE | 2026-05-01 10:00 |
| 2 | 8101 | 100.00 | COMPLETADA | 2026-05-01 10:05 |
| 3 | 8102 | 250.00 | COMPLETADA | 2026-05-01 10:10 |
| 4 | 8103 | 80.00 | PENDIENTE | 2026-05-01 10:15 |
| 5 | 8104 | 50.00 | CANCELADA | 2026-05-01 10:20 |

Comprueba:

```text
5 filas en RAW
5 filas en el stream
4 claves de pedido
SYSTEM$STREAM_HAS_DATA = TRUE
```

---

### Tarea 5. Inspeccionar los metadatos CDC

Consulta el stream al menos dos veces.

Muestra:

- Columnas de negocio.
- `METADATA$ACTION`.
- `METADATA$ISUPDATE`.
- `METADATA$ROW_ID`.

Explica por qué, en este stream:

```text
METADATA$ACTION = INSERT
METADATA$ISUPDATE = FALSE
```

Comprueba que consultar el stream no cambia el número de filas pendientes.

---

### Tarea 6. Probar un consumo con ROLLBACK

Abre una transacción.

Inserta el contenido del stream en `STREAM_PRUEBA_ROLLBACK` y ejecuta:

```text
ROLLBACK
```

Comprueba que:

- La tabla de prueba queda vacía.
- El stream sigue mostrando cinco filas.
- `SYSTEM$STREAM_HAS_DATA` sigue devolviendo `TRUE`.

Explica por qué el offset no avanzó.

---

### Tarea 7. Crear la triggered task

Crea una task con estas características:

- Warehouse `WH_DEV`.
- Sin `SCHEDULE`.
- Intervalo mínimo de disparo de 10 segundos.
- Condición `SYSTEM$STREAM_HAS_DATA`.
- Cuerpo formado por un `MERGE`.

El `MERGE` debe:

1. Leer el stream.
2. Deduplicar por `id_pedido`.
3. Conservar el evento con mayor `fecha_modificacion` y `event_id`.
4. Actualizar el destino solo si la versión es más reciente.
5. Insertar pedidos que todavía no existen.
6. Actualizar `_processed_at`.

La task debe permanecer inicialmente suspendida.

---

### Tarea 8. Activar y monitorizar la primera ejecución

Reanuda la task.

Como el stream ya contiene cambios, la task debe ejecutarse.

Consulta `TASK_HISTORY` hasta encontrar una ejecución finalizada.

Comprueba:

- Estado `SUCCEEDED`.
- `SCHEDULED_FROM = TRIGGER`.
- Query ID de la sentencia.
- Hora de inicio y finalización.

Después valida:

```text
4 pedidos en CURATED
el stream está vacío
SYSTEM$STREAM_HAS_DATA = FALSE
```

El pedido `8101` debe aparecer como `COMPLETADA`.

---

### Tarea 9. Insertar el segundo microbatch

Con la task reanudada, inserta cinco eventos:

| event_id | id_pedido | importe | estado | fecha_modificacion |
|---:|---:|---:|---|---|
| 6 | 8102 | 250.00 | CANCELADA | 2026-05-01 11:00 |
| 7 | 8103 | 90.00 | COMPLETADA | 2026-05-01 11:05 |
| 8 | 8105 | 60.00 | PENDIENTE | 2026-05-01 11:10 |
| 9 | 8105 | 65.00 | COMPLETADA | 2026-05-01 11:15 |
| 10 | 8106 | 120.00 | COMPLETADA | 2026-05-01 11:20 |

Sin ejecutar manualmente el `MERGE`, espera a que la triggered task procese el stream.

---

### Tarea 10. Validar el resultado final

Comprueba:

```text
6 pedidos
importe total = 675.00
4 pedidos COMPLETADA
2 pedidos CANCELADA
0 duplicados por id_pedido
stream vacío
```

Valida específicamente:

- `8102` cambia a `CANCELADA`.
- `8103` cambia a `COMPLETADA` y `90.00`.
- `8105` se inserta una sola vez con la versión de `65.00`.
- `8106` se inserta con `120.00`.

---

### Tarea 11. Comprobar una versión antigua

Inserta un evento adicional para `8103` cuya `fecha_modificacion` sea anterior a la almacenada en CURATED.

La task consumirá el evento, pero la condición de versión del `MERGE` debe impedir que sobrescriba el pedido.

Comprueba que:

- La task finaliza correctamente.
- El stream queda vacío.
- `8103` conserva `90.00` y su versión más reciente.
- La fila antigua ha sido procesada, pero no aplicada.

---

### Tarea 12. Suspender y auditar

Suspende la task al terminar.

Comprueba su estado con `SHOW TASKS`.

Consulta el historial de la última hora y diferencia:

- Primera ejecución.
- Segunda ejecución.
- Ejecución que ignoró la versión antigua.

Explica:

- Por qué una triggered task no necesita sondeo periódico.
- Por qué `SYSTEM$STREAM_HAS_DATA` puede producir falsos positivos.
- Por qué la sentencia debe poder ejecutarse de forma segura aunque el stream finalmente no aporte cambios aplicables.
- Qué ocurriría si el stream no se consume antes del periodo de retención.

---

## Preguntas de reflexión

1. ¿Qué almacena un stream y qué no almacena?
2. ¿Por qué una consulta `SELECT` no consume los cambios?
3. ¿Por qué es importante que el consumo y la actualización del destino formen una sola sentencia o transacción?
4. ¿Por qué se utiliza un append-only stream en este escenario?
5. ¿Qué ocurriría si alguien ejecutara `UPDATE` directamente sobre la tabla RAW?
6. ¿Por qué hay que deduplicar el microbatch antes del `MERGE`?
7. ¿Qué aporta una triggered task frente a una task cada minuto?
8. ¿Por qué debe suspenderse la task al finalizar el laboratorio?
9. ¿Cuándo sería preferible una task programada en lugar de una triggered task?
10. ¿Qué controles añadirías para detectar un stream próximo a quedar stale?

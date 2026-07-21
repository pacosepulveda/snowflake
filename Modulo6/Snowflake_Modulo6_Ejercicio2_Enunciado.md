# Módulo 6 · Ejercicio 2
## Deduplicación y carga incremental determinista con `ROW_NUMBER`, `QUALIFY` y `MERGE`

### Contexto

RetailNova ya dispone de una tabla de ventas limpia en la capa `CURATED`. Cada pocas horas recibe un lote de cambios procedente del sistema comercial.

El lote puede contener:

- Varias versiones de una misma venta.
- Cambios más recientes que deben actualizar el destino.
- Versiones antiguas que no deben sobrescribir información nueva.
- Ventas nuevas.
- Duplicados de una clave que todavía no existe en el destino.

La empresa quiere aplicar los cambios con `MERGE`, pero ha detectado dos riesgos:

1. Si varias filas de la fuente coinciden con una misma fila del destino, la actualización puede ser no determinista.
2. Si una clave nueva aparece repetida en la fuente, un `MERGE` puede insertar varias copias.

Debes construir un proceso incremental que deduplique primero el lote y que pueda ejecutarse varias veces sin cambiar el resultado.

---

## Objetivos

Al finalizar el ejercicio deberás ser capaz de:

1. Detectar claves duplicadas en un lote incremental.
2. Explicar por qué `DISTINCT` no resuelve la deduplicación por versión.
3. Utilizar `ROW_NUMBER()` y `QUALIFY`.
4. Definir un criterio de desempate determinista.
5. Observar el error de un `MERGE` con múltiples fuentes para una misma fila destino.
6. Comprobar que los duplicados nuevos pueden insertarse varias veces.
7. Preparar una fuente con una fila como máximo por clave.
8. Actualizar únicamente cuando la versión de origen es más reciente.
9. Insertar claves que no existen.
10. Ignorar versiones antiguas.
11. Reejecutar el mismo `MERGE` sin producir nuevos cambios.
12. Reconciliar filas insertadas, actualizadas, ignoradas y deduplicadas.

---

## Convenciones

| Objeto | Nombre |
|---|---|
| Base de datos | `DB_CURSO` |
| Esquema origen | `STAGING` |
| Esquema destino | `CURATED` |
| Warehouse | `WH_DEV` |
| Tabla destino | `VENTAS_INCREMENTALES` |
| Tabla delta | `VENTAS_DELTA` |
| View delta deduplicada | `V_VENTAS_DELTA_DEDUP` |
| Tabla de prueba del MERGE erróneo | `VENTAS_MERGE_PRUEBA` |
| Tabla de prueba de inserción duplicada | `VENTAS_INSERT_DUP_PRUEBA` |
| Fichero SQL del workspace | `M06_E02_MERGE_INCREMENTAL.sql` |

---

## Regla de versionado

La clave de negocio es:

```text
id_venta
```

Para cada `id_venta`, la versión ganadora del lote será la primera según este orden:

1. `fecha_modificacion` descendente.
2. `_loaded_at` descendente.
3. `_file_row_number` descendente.
4. `_source_file` descendente.

Una fila solo puede actualizar una venta existente cuando:

```text
origen.fecha_modificacion > destino.fecha_modificacion
```

Si las fechas son iguales o la fuente es más antigua, no se actualiza el destino.

---

## Tareas

### Tarea 1. Preparar Workspaces

En **Workspaces**, crea:

```text
M06_E02_MERGE_INCREMENTAL.sql
```

Configura:

- Rol.
- Warehouse.
- Base de datos.
- Esquema.
- `QUERY_TAG`.
- El parámetro `ERROR_ON_NONDETERMINISTIC_MERGE` a `TRUE`.

Comprueba su valor en la sesión.

> Utiliza Workspaces, no Legacy Worksheets.

---

### Tarea 2. Crear el estado inicial del destino

Crea:

```text
DB_CURSO.CURATED.VENTAS_INCREMENTALES
```

con estas columnas:

- `id_venta`
- `id_cliente`
- `fecha`
- `importe`
- `moneda`
- `estado`
- `fecha_modificacion`
- `_source_file`
- `_file_row_number`
- `_loaded_at`
- `_merged_at`

Inserta seis ventas iniciales, con identificadores `6001` a `6006`.

Comprueba:

```text
6 filas
importe total = 880.00
```

---

### Tarea 3. Crear el lote delta

Crea una tabla transitoria:

```text
DB_CURSO.STAGING.VENTAS_DELTA
```

El lote debe contener nueve filas y seis claves diferentes:

- `6002`: dos versiones; debe ganar la que tiene importe `220.00`.
- `6003`: una versión anterior a la del destino; debe ignorarse.
- `6004`: una versión nueva; debe actualizarse a `90.00`.
- `6005`: dos versiones con la misma `fecha_modificacion`; debe ganar la cargada más tarde, con importe `315.00`.
- `6007`: dos versiones de una venta nueva; debe insertarse una sola vez con importe `80.00`.
- `6008`: una venta nueva con importe `125.00`.

Comprueba:

```text
9 filas físicas
6 claves de negocio
3 filas excedentes por duplicidad
```

---

### Tarea 4. Analizar los duplicados

Construye un informe que muestre por `id_venta`:

- Número de versiones.
- Fecha de modificación mínima y máxima.
- Primera y última hora de carga.
- Importe de las distintas versiones.

Identifica las claves `6002`, `6005` y `6007` como duplicadas.

Explica por qué `SELECT DISTINCT` no solucionaría el problema.

---

### Tarea 5. Ejecutar un MERGE no deduplicado

Crea `VENTAS_MERGE_PRUEBA` como copia del estado inicial.

Ejecuta sobre ella un `MERGE` utilizando directamente `VENTAS_DELTA`, sin deduplicar.

Comprueba que:

- La sentencia falla.
- El mensaje hace referencia a una operación no determinista.
- La tabla de prueba conserva seis filas.
- No se ha aplicado una actualización parcial.

Explica la relación con `ERROR_ON_NONDETERMINISTIC_MERGE`.

---

### Tarea 6. Demostrar el riesgo para claves nuevas

Crea una tabla vacía `VENTAS_INSERT_DUP_PRUEBA` con la misma estructura del destino.

Ejecuta un `MERGE` utilizando únicamente las dos filas de `id_venta = 6007`.

Comprueba que:

- El `MERGE` no falla.
- Se insertan dos filas.
- La tabla contiene dos registros con `id_venta = 6007`.

Explica por qué el parámetro de no determinismo no evita este caso.

Elimina después esta tabla de prueba.

---

### Tarea 7. Crear la fuente deduplicada

Crea la view:

```text
DB_CURSO.STAGING.V_VENTAS_DELTA_DEDUP
```

Debe usar:

```text
ROW_NUMBER() OVER (...)
QUALIFY ... = 1
```

La view debe contener exactamente seis filas.

Demuestra qué versión ha ganado para `6002`, `6005` y `6007`.

---

### Tarea 8. Clasificar las operaciones antes del MERGE

Sin modificar todavía el destino, une la view deduplicada con la tabla destino y clasifica cada fila como:

- `INSERTAR`
- `ACTUALIZAR`
- `IGNORAR_VERSION_ANTIGUA_O_IGUAL`

Resultado esperado:

| Operación | Filas |
|---|---:|
| `INSERTAR` | 2 |
| `ACTUALIZAR` | 3 |
| `IGNORAR_VERSION_ANTIGUA_O_IGUAL` | 1 |

Identifica la clave incluida en cada categoría.

---

### Tarea 9. Ejecutar el MERGE determinista

Ejecuta un `MERGE` contra `CURATED.VENTAS_INCREMENTALES` utilizando la view deduplicada.

Requisitos:

- `ON` debe utilizar `id_venta`.
- Los registros coincidentes solo se actualizan si la fuente es más reciente.
- Las claves nuevas se insertan.
- `_merged_at` se actualiza en las filas modificadas o insertadas.
- No se elimina ninguna fila.

El resultado esperado de la primera ejecución es:

```text
2 filas insertadas
3 filas actualizadas
0 filas eliminadas
```

---

### Tarea 10. Validar el resultado

Demuestra que el destino contiene:

```text
8 filas
importe total = 1130.00
```

Comprueba específicamente:

- `6002` tiene importe `220.00` y estado `COMPLETADA`.
- `6003` conserva importe `150.00` y no acepta la versión antigua.
- `6004` tiene importe `90.00`.
- `6005` tiene importe `315.00`.
- `6007` aparece una sola vez con importe `80.00`.
- `6008` se ha insertado con importe `125.00`.
- No existen claves duplicadas.

---

### Tarea 11. Probar la idempotencia

Sin cambiar el lote, ejecuta por segunda vez el mismo `MERGE`.

Resultado esperado:

```text
0 filas insertadas
0 filas actualizadas
0 filas eliminadas
```

Comprueba que:

- Siguen existiendo ocho filas.
- El importe total sigue siendo `1130.00`.
- No aparecen duplicados.
- Las fechas de versión no han retrocedido.

Explica qué parte del diseño hace que la reejecución sea segura.

---

### Tarea 12. Reconciliar el proceso

Construye un informe que muestre:

- Filas físicas del delta.
- Claves del delta.
- Duplicados eliminados.
- Filas deduplicadas.
- Nuevas claves.
- Actualizaciones aplicables.
- Versiones ignoradas.
- Filas del destino antes y después.

El informe debe justificar:

```text
9 filas delta
- 3 versiones descartadas
= 6 filas deduplicadas

6 filas deduplicadas
= 2 inserciones
+ 3 actualizaciones
+ 1 versión ignorada

6 filas iniciales
+ 2 nuevas
= 8 filas finales
```

---

## Preguntas de reflexión

1. ¿Por qué `DISTINCT` no equivale a deduplicar por clave de negocio?
2. ¿Qué ocurriría si el `ORDER BY` de `ROW_NUMBER` no resolviera completamente los empates?
3. ¿Por qué un duplicado nuevo puede insertarse varias veces sin generar un error de no determinismo?
4. ¿Qué diferencia hay entre la clave de negocio y la fecha de versión?
5. ¿Por qué se incluye una condición de versión en `WHEN MATCHED`?
6. ¿Qué riesgo tendría configurar `ERROR_ON_NONDETERMINISTIC_MERGE = FALSE`?
7. ¿Por qué es útil clasificar previamente las operaciones?
8. ¿Qué cambiaría si el lote incluyera eliminaciones lógicas?

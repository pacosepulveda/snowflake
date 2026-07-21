# Módulo 6 · Ejercicio 1
## De datos RAW a datos CURATED: limpieza, tipado seguro y clasificación de rechazos

### Contexto

El equipo de datos de **RetailNova** recibe ventas desde varios sistemas heredados. Para evitar perder información durante la ingesta, todos los campos se almacenan inicialmente como texto en la capa `STAGING`.

El lote contiene:

- Espacios innecesarios.
- Diferencias de mayúsculas y minúsculas.
- Fechas en dos formatos.
- Importes con coma o punto decimal.
- Canales vacíos.
- Identificadores incorrectos.
- Fechas imposibles.
- Importes negativos.
- Monedas no admitidas.

La empresa quiere aplicar un patrón **ELT**:

```text
STAGING.VENTAS_RAW_ELT
        ↓
Vista de normalización y clasificación
        ↓
STAGING.VENTAS_CLASIFICADAS
        ├── CURATED.VENTAS_LIMPIAS
        └── STAGING.VENTAS_RECHAZADAS
```

No se deben eliminar silenciosamente los registros incorrectos. Cada rechazo debe conservarse junto con su motivo y sus datos originales.

---

## Objetivos

Al terminar el ejercicio deberás ser capaz de:

1. Explicar la diferencia entre ETL y ELT.
2. Mantener una copia fiel de los datos de origen en STAGING.
3. Limpiar texto con `TRIM`, `UPPER`, `NULLIF` y `COALESCE`.
4. Convertir datos de forma segura con funciones `TRY_*`.
5. Admitir más de un formato de fecha.
6. Diferenciar errores de conversión y errores de reglas de negocio.
7. Dividir una transformación compleja mediante CTE.
8. Reutilizar lógica mediante una view.
9. Materializar resultados con CTAS.
10. Separar registros válidos y rechazados.
11. Reconciliar el número de filas entre las distintas capas.
12. Comprobar la diferencia entre una view y una tabla creada con CTAS.

---

## Convenciones

| Objeto | Nombre |
|---|---|
| Base de datos | `DB_CURSO` |
| Esquema de origen | `STAGING` |
| Esquema de destino | `CURATED` |
| Warehouse | `WH_DEV` |
| Tabla RAW | `VENTAS_RAW_ELT` |
| View de normalización | `V_VENTAS_NORMALIZADAS` |
| Tabla clasificada | `VENTAS_CLASIFICADAS` |
| Tabla válida | `VENTAS_LIMPIAS` |
| Tabla de rechazos | `VENTAS_RECHAZADAS` |
| Fichero SQL del workspace | `M06_E01_RAW_A_CURATED.sql` |

---

## Reglas de negocio

Un registro será rechazado cuando se cumpla la primera regla aplicable:

1. `id_venta` no es numérico.
2. La fecha no puede convertirse.
3. `id_cliente` no es numérico.
4. El importe no puede convertirse o es menor o igual que cero.
5. La moneda no pertenece a `EUR`, `USD` o `GBP`.
6. El estado no pertenece a `COMPLETADA`, `PENDIENTE` o `CANCELADA`.
7. La fecha de modificación no puede convertirse.

Los canales vacíos o nulos **no se rechazan**. Deben normalizarse como:

```text
SIN_CANAL
```

Las fechas válidas pueden llegar en cualquiera de estos formatos:

```text
YYYY-MM-DD
DD/MM/YYYY
```

---

## Tareas

### Tarea 1. Preparar el workspace

En **Workspaces**, crea un fichero SQL llamado:

```text
M6_E01_RAW_A_CURATED.sql
```

Configura explícitamente:

- Rol.
- Warehouse.
- Base de datos.
- Esquema.
- Un `QUERY_TAG` identificativo.

Comprueba el contexto de sesión.

> Utiliza Workspaces. No busques el antiguo menú Worksheets.

---

### Tarea 2. Crear la tabla RAW

Crea una tabla transitoria:

```text
DB_CURSO.STAGING.VENTAS_RAW_ELT
```

Todos los campos de negocio deben ser `VARCHAR`, aunque conceptualmente representen números, fechas o importes.

Incluye también estas columnas de trazabilidad:

- `_source_file`
- `_file_row_number`
- `_loaded_at`

La tabla debe representar una copia fiel de la fuente. No apliques limpieza ni conversiones en este punto.

---

### Tarea 3. Insertar el lote de prueba

Inserta exactamente los 16 registros incluidos en la sección **Datos de entrada** de este documento.

Después comprueba:

- Que existen 16 filas.
- Que los valores conservan espacios, minúsculas y formatos originales.
- Que la capa RAW contiene tanto filas válidas como defectuosas.

---

## Datos de entrada

| Fila | id_venta | fecha | id_cliente | canal | importe | moneda | estado | fecha_modificacion |
|---:|---|---|---|---|---|---|---|---|
| 1 | ` 5001 ` | `2026-03-01` | `701` | ` web ` | `129,95` | ` eur ` | ` completada ` | `2026-03-01 10:15:00` |
| 2 | `5002` | `01/03/2026` | `702` | `TIENDA` | `89.50` | `EUR` | `COMPLETADA` | `2026-03-01 11:00:00` |
| 3 | `5003` | `2026-03-02` | `703` | cadena vacía | `45,00` | `eur` | `PENDIENTE` | `2026-03-02 09:00:00` |
| 4 | `5004` | `2026-03-02` | `704` | `marketplace` | `250.00` | `USD` | `COMPLETADA` | `2026-03-02 13:30:00` |
| 5 | `5005` | `03/03/2026` | `705` | `tienda` | `310,40` | `GBP` | `CANCELADA` | `2026-03-03 08:45:00` |
| 6 | `5006` | `2026-03-03` | `706` | `WEB` | `64,75` | `EUR` | `completada` | `2026-03-03 14:10:00` |
| 7 | `5007` | `2026-03-04` | `707` | ` tienda ` | `54.60` | `eur` | `pendiente` | `2026-03-04 10:00:00` |
| 8 | `5008` | `04/03/2026` | `708` | `MARKETPLACE` | `119.00` | `EUR` | `COMPLETADA` | `2026-03-04 16:20:00` |
| 9 | `5009` | `2026-03-05` | `709` | `web` | `92,35` | `EUR` | `COMPLETADA` | `2026-03-05 09:15:00` |
| 10 | `5010` | `2026-03-05` | `710` | `WEB` | `499.99` | `eur` | `COMPLETADA` | `2026-03-05 18:00:00` |
| 11 | `5011` | `06/03/2026` | `711` | SQL `NULL` | `25.00` | `EUR` | `PENDIENTE` | `2026-03-06 08:00:00` |
| 12 | `X-9001` | `2026-03-06` | `712` | `WEB` | `40.00` | `EUR` | `COMPLETADA` | `2026-03-06 09:00:00` |
| 13 | `9002` | `31/02/2026` | `713` | `TIENDA` | `50.00` | `EUR` | `COMPLETADA` | `2026-03-06 09:30:00` |
| 14 | `9003` | `2026-03-06` | `CLIENTE-X` | `WEB` | `60.00` | `EUR` | `COMPLETADA` | `2026-03-06 10:00:00` |
| 15 | `9004` | `2026-03-06` | `714` | `WEB` | `-15,00` | `EUR` | `COMPLETADA` | `2026-03-06 10:30:00` |
| 16 | `9005` | `2026-03-06` | `715` | `WEB` | `70.00` | `JPY` | `COMPLETADA` | `2026-03-06 11:00:00` |

Utiliza como `_source_file`:

```text
ventas_marzo_lote_01.csv
```

y como `_file_row_number` los valores del 1 al 16.

---

### Tarea 4. Diseñar la transformación con CTE

Crea una consulta con varios CTE que realice pasos lógicos separados:

1. Limpieza básica de cadenas.
2. Conversión de identificadores.
3. Conversión de fechas admitiendo los dos formatos.
4. Conversión de importes con coma o punto decimal.
5. Normalización de canal, moneda y estado.
6. Conversión de la fecha de modificación.
7. Clasificación mediante `motivo_rechazo`.

La consulta debe conservar:

- Los valores RAW originales.
- Los valores tipados.
- Las columnas de trazabilidad.
- Una columna `_transformed_at`.

Prueba cada CTE antes de guardar la lógica definitiva.

---

### Tarea 5. Crear una view reutilizable

Guarda la transformación como:

```text
DB_CURSO.STAGING.V_VENTAS_NORMALIZADAS
```

La view debe devolver una fila por registro RAW e incluir:

- Columnas originales.
- Columnas normalizadas y tipadas.
- `motivo_rechazo`.
- Trazabilidad.
- Momento de transformación.

Comprueba que la view devuelve 16 filas.

---

### Tarea 6. Materializar la clasificación con CTAS

Crea mediante CTAS una tabla transitoria:

```text
DB_CURSO.STAGING.VENTAS_CLASIFICADAS
```

a partir de la view.

Utiliza una sentencia reproducible que permita reconstruir la tabla completa.

Comprueba que la tabla contiene:

- 16 filas.
- 11 registros válidos.
- 5 registros rechazados.

---

### Tarea 7. Publicar los registros válidos

Crea mediante CTAS:

```text
DB_CURSO.CURATED.VENTAS_LIMPIAS
```

Incluye únicamente:

- `id_venta`
- `fecha`
- `id_cliente`
- `canal`
- `importe`
- `moneda`
- `estado`
- `fecha_modificacion`
- `_source_file`
- `_file_row_number`
- `_loaded_at`
- `_transformed_at`

No copies las columnas RAW ni `motivo_rechazo`.

La tabla debe contener 11 filas.

---

### Tarea 8. Conservar los registros rechazados

Crea mediante CTAS una tabla transitoria:

```text
DB_CURSO.STAGING.VENTAS_RECHAZADAS
```

Debe conservar:

- Todas las columnas RAW.
- Los valores tipados cuando existan.
- `motivo_rechazo`.
- Trazabilidad.

La tabla debe contener cinco filas.

---

### Tarea 9. Reconciliar el proceso

Construye una consulta de reconciliación que muestre:

- Filas RAW.
- Filas clasificadas.
- Filas válidas.
- Filas rechazadas.
- Diferencia entre RAW y válidas más rechazadas.

Resultado esperado:

```text
RAW = 16
CLASIFICADAS = 16
VÁLIDAS = 11
RECHAZADAS = 5
DIFERENCIA = 0
```

---

### Tarea 10. Validar la calidad de CURATED

Demuestra que en `VENTAS_LIMPIAS`:

- No hay identificadores nulos.
- No hay fechas nulas.
- No hay clientes nulos.
- No hay importes nulos o no positivos.
- Solo existen las monedas permitidas.
- Solo existen los estados permitidos.
- Los canales vacíos se han convertido en `SIN_CANAL`.

Muestra también:

- Filas e importe por moneda.
- Filas por estado.
- Filas por canal.

---

### Tarea 11. Analizar los rechazos

Agrupa `VENTAS_RECHAZADAS` por `motivo_rechazo`.

Deben aparecer exactamente estos cinco motivos, una vez cada uno:

```text
ID_VENTA_INVALIDO
FECHA_INVALIDA
ID_CLIENTE_INVALIDO
IMPORTE_INVALIDO
MONEDA_INVALIDA
```

Explica por qué es mejor conservar estas filas que descartarlas con un `WHERE` silencioso.

---

### Tarea 12. Comparar view y CTAS

Inserta temporalmente una nueva fila RAW válida con `id_venta = 5012`.

Sin reconstruir ninguna tabla:

1. Cuenta las filas de `V_VENTAS_NORMALIZADAS`.
2. Cuenta las filas de `VENTAS_CLASIFICADAS`.
3. Explica por qué la view muestra el nuevo registro y la tabla CTAS no.
4. Elimina la fila de prueba de la tabla RAW.
5. Comprueba que la view vuelve a 16 filas.

No reconstruyas las tablas finales durante esta prueba.

---

## Preguntas de reflexión

1. ¿Por qué es útil conservar los campos de origen como `VARCHAR` en RAW?
2. ¿Qué ventaja aporta `TRY_TO_DECIMAL` frente a `TO_DECIMAL`?
3. ¿Por qué una conversión correcta no garantiza que el dato sea válido para el negocio?
4. ¿Por qué el orden de las condiciones del `CASE` importa?
5. ¿Qué diferencia existe entre una view y una tabla creada con CTAS?
6. ¿Por qué los rechazos forman parte de la reconciliación?
7. ¿Qué columnas de trazabilidad conservarías en un entorno real?
8. ¿Qué parte del proceso reconstruirías completamente y cuál implementarías de forma incremental?

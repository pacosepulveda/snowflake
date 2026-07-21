# Módulo 6 · Ejercicio 3
## Construcción idempotente de un data mart mensual con controles de calidad

### Contexto

El equipo de Business Intelligence de **RetailNova** necesita un conjunto de datos estable para analizar las ventas por mes, segmento de cliente y canal.

Los analistas no deberían consultar directamente las tablas operativas de `CURATED`. Necesitan una tabla de `MARTS` con una granularidad clara y métricas ya calculadas.

El flujo será:

```text
CURATED.CLIENTES_MART
            +
CURATED.VENTAS_MART_BASE
            ↓
CURATED.V_VENTAS_ENRIQUECIDAS_MART
            ↓
Controles de calidad
            ↓
MARTS.VENTAS_MES_SEGMENTO_CANAL
```

La publicación debe cumplir dos requisitos:

1. **Calidad:** no se publicará si existen claves duplicadas, clientes huérfanos, importes inválidos o estados desconocidos.
2. **Idempotencia:** con la misma entrada, ejecutar el proceso varias veces debe producir exactamente las mismas filas de negocio.

---

## Objetivos

Al finalizar el ejercicio deberás ser capaz de:

1. Definir la granularidad de un data mart.
2. Crear una view de enriquecimiento reutilizable.
3. Validar relaciones y reglas de calidad antes de publicar.
4. Diferenciar una carga mediante `INSERT…SELECT` de una reconstrucción completa con CTAS.
5. Demostrar por qué un `INSERT…SELECT` sin control no es idempotente.
6. Construir un mart mediante `CREATE OR REPLACE TABLE … AS SELECT`.
7. Conservar grants al reemplazar una tabla.
8. Reconciliar las métricas entre CURATED y MARTS.
9. Detectar duplicados en la granularidad del mart.
10. Probar la idempotencia comparando dos reconstrucciones.
11. Incorporar un cambio en la fuente y regenerar el resultado.
12. Explicar cuándo una reconstrucción completa deja de ser una estrategia adecuada.

---

## Convenciones

| Objeto | Nombre |
|---|---|
| Base de datos | `DB_CURSO` |
| Esquema de origen | `CURATED` |
| Esquema de consumo | `MARTS` |
| Warehouse | `WH_DEV` |
| Dimensión de clientes | `CLIENTES_MART` |
| Tabla de ventas | `VENTAS_MART_BASE` |
| View enriquecida | `V_VENTAS_ENRIQUECIDAS_MART` |
| Mart final | `VENTAS_MES_SEGMENTO_CANAL` |
| Tabla de prueba no idempotente | `VENTAS_MES_INSERT_PRUEBA` |
| Fichero SQL del workspace | `M06_E03_MART_IDEMPOTENTE.sql` |

---

## Granularidad del mart

Cada fila debe representar una combinación única de:

```text
mes + segmento + canal
```

Las columnas del mart serán:

| Columna | Significado |
|---|---|
| `mes` | Primer día del mes |
| `segmento` | Segmento del cliente |
| `canal` | Canal de venta |
| `num_ventas` | Ventas completadas |
| `clientes_unicos` | Clientes distintos |
| `importe_total` | Suma de importes |
| `ticket_medio` | Importe medio |
| `ultima_modificacion_grupo` | Versión más reciente dentro del grupo |
| `_source_watermark` | Versión más reciente de toda la fuente publicada |

Solo deben incluirse ventas cuyo estado sea:

```text
COMPLETADA
```

---

## Datos de clientes

Crea ocho clientes:

| id_cliente | segmento | región |
|---:|---|---|
| 901 | PYME | NORTE |
| 902 | EMPRESA | SUR |
| 903 | PYME | ESTE |
| 904 | CORPORATIVO | OESTE |
| 905 | EMPRESA | NORTE |
| 906 | PYME | SUR |
| 907 | CORPORATIVO | ESTE |
| 908 | EMPRESA | OESTE |

---

## Datos de ventas

Crea 26 ventas entre enero y marzo de 2026.

La solución contiene las sentencias completas de inserción. El conjunto debe cumplir inicialmente:

```text
26 ventas totales
21 ventas COMPLETADAS
15 combinaciones mes + segmento + canal
importe COMPLETADO total = 3690.00
```

Debe contener también ventas `PENDIENTE` y `CANCELADA` para comprobar que no llegan al mart.

---

## Tareas

### Tarea 1. Preparar Workspaces

En **Workspaces**, crea:

```text
M06_E03_MART_IDEMPOTENTE.sql
```

Configura explícitamente:

- Rol.
- Warehouse.
- Base de datos.
- Esquema.
- `QUERY_TAG`.

Crea el esquema `MARTS` si todavía no existe.

> Utiliza Workspaces, no Legacy Worksheets.

---

### Tarea 2. Crear las tablas CURATED

Crea:

```text
DB_CURSO.CURATED.CLIENTES_MART
DB_CURSO.CURATED.VENTAS_MART_BASE
```

Las tablas deben utilizar tipos correctos, no campos RAW.

Comprueba:

- Ocho clientes.
- Veintiséis ventas.
- Identificadores de venta únicos.
- Tres meses de datos.
- Estados `COMPLETADA`, `PENDIENTE` y `CANCELADA`.

---

### Tarea 3. Crear una view de enriquecimiento

Crea:

```text
DB_CURSO.CURATED.V_VENTAS_ENRIQUECIDAS_MART
```

La view debe combinar ventas y clientes e incluir:

- Datos de la venta.
- Segmento.
- Región.
- Columna `mes` calculada con `DATE_TRUNC`.
- Una marca booleana que indique si la venta es publicable.

La view debe contener las 26 ventas, no solo las completadas.

---

### Tarea 4. Implementar controles de calidad

Antes de publicar, crea consultas que detecten:

1. Identificadores de venta duplicados.
2. Clientes referenciados por ventas que no existen en la dimensión.
3. Importes nulos o menores o iguales que cero.
4. Estados distintos de `COMPLETADA`, `PENDIENTE` y `CANCELADA`.
5. Segmentos o canales nulos.

Construye un resumen con estado:

```text
OK
ERROR
```

La publicación solo debe continuar cuando todos los contadores sean cero.

---

### Tarea 5. Probar que el control detecta un problema

Inserta temporalmente una venta con:

```text
id_venta = 7999
id_cliente = 999
```

El cliente `999` no existe.

Comprueba que:

- El control de clientes huérfanos pasa de cero a uno.
- El estado global se convierte en `ERROR`.
- No debes reconstruir el mart mientras el control falla.

Elimina después la fila y verifica que el estado vuelve a `OK`.

---

### Tarea 6. Crear la consulta agregada

Construye una consulta con CTE que:

1. Seleccione únicamente ventas completadas.
2. Calcule el watermark de la fuente.
3. Agrupe por `mes`, `segmento` y `canal`.
4. Calcule las métricas definidas.
5. Ordene el resultado para facilitar su inspección.

Antes de crear la tabla, comprueba:

```text
15 filas
21 ventas agregadas
importe total = 3690.00
```

---

### Tarea 7. Demostrar el problema de INSERT…SELECT

Crea una tabla de prueba vacía con la estructura del resultado agregado.

Ejecuta el mismo `INSERT…SELECT` dos veces.

Comprueba:

```text
Primera ejecución: 15 filas
Segunda ejecución: 30 filas
15 claves de granularidad duplicadas
importe total duplicado
```

Explica por qué este proceso no es idempotente.

Elimina después la tabla de prueba.

---

### Tarea 8. Publicar el mart mediante CTAS

Crea o reemplaza:

```text
DB_CURSO.MARTS.VENTAS_MES_SEGMENTO_CANAL
```

mediante CTAS.

Requisitos:

- `CREATE OR REPLACE TABLE`.
- `COPY GRANTS`.
- La consulta agregada completa.
- Sin timestamp de publicación no determinista dentro de las filas.
- `_source_watermark` calculado a partir de la fuente.

Comprueba:

```text
15 filas
SUM(num_ventas) = 21
SUM(importe_total) = 3690.00
```

---

### Tarea 9. Validar la calidad del mart

Demuestra que:

1. No hay duplicados de `mes + segmento + canal`.
2. No hay dimensiones nulas.
3. Todos los contadores son positivos.
4. No hay importes negativos.
5. `ticket_medio` coincide con `importe_total / num_ventas`.
6. La suma de ventas coincide con CURATED.
7. La suma de importes coincide con CURATED.
8. Todas las filas contienen el mismo `_source_watermark`.

Muestra el resultado completo del mart ordenado por mes, segmento y canal.

---

### Tarea 10. Probar la idempotencia de la reconstrucción

Crea una copia temporal del mart.

Vuelve a ejecutar exactamente la misma sentencia CTAS sin modificar las fuentes.

Compara la copia y la tabla reconstruida mediante `MINUS` en ambos sentidos.

Resultado esperado:

```text
0 diferencias
15 filas
3690.00 de importe
```

Explica por qué el resultado es determinista.

---

### Tarea 11. Procesar un cambio en CURATED

Inserta una nueva venta:

```text
id_venta = 7027
id_cliente = 903
fecha = 2026-03-29
canal = MARKETPLACE
importe = 105.00
estado = COMPLETADA
```

Ejecuta los controles y reconstruye el mart.

Resultado esperado:

```text
16 filas del mart
22 ventas agregadas
importe total = 3795.00
```

Debe aparecer una nueva combinación:

```text
2026-03 + PYME + MARKETPLACE
```

con una venta y `105.00`.

---

### Tarea 12. Volver a ejecutar tras el cambio

Ejecuta una vez más la misma reconstrucción, sin nuevos cambios.

Comprueba que el resultado permanece:

```text
16 filas
22 ventas
3795.00
0 claves duplicadas
```

---

### Tarea 13. Evaluar la estrategia

Responde:

1. ¿Por qué CTAS es adecuado para este mart?
2. ¿Qué ocurre con los lectores concurrentes durante `CREATE OR REPLACE`?
3. ¿Qué ventaja aporta `COPY GRANTS`?
4. ¿Qué riesgo existe si hay streams dependientes de la tabla?
5. ¿Cuándo sería preferible una estrategia incremental con `MERGE`?
6. ¿Por qué `_source_watermark` es más reproducible que `CURRENT_TIMESTAMP()` dentro del resultado?

---

## Preguntas de reflexión

1. ¿Qué significa exactamente la granularidad de una tabla?
2. ¿Por qué debe comprobarse la unicidad de la granularidad?
3. ¿Por qué la suma de agregados debe reconciliarse con la fuente?
4. ¿Qué diferencia existe entre idempotencia técnica e idempotencia de negocio?
5. ¿Por qué un timestamp generado durante la publicación dificulta comparar resultados?
6. ¿Qué ventajas y costes tiene una reconstrucción completa?
7. ¿Qué controles añadirías antes de permitir acceso a una herramienta BI?

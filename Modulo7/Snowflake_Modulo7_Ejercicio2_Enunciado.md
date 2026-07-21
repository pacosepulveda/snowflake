# Módulo 7 · Ejercicio 2
## Pipeline declarativo con Dynamic Tables

### Contexto

RetailNova mantiene una tabla de ventas operativa y una dimensión de clientes. El equipo de analítica necesita dos resultados derivados:

1. Una capa intermedia con las ventas completadas, enriquecidas con la región y el segmento del cliente.
2. Un agregado diario por región y canal para un dashboard.

Hasta ahora, estos resultados se reconstruyen mediante scripts y tasks. La lógica es puramente SQL y no requiere procedimientos, bifurcaciones ni operaciones `MERGE`, por lo que se quiere evaluar un pipeline declarativo con **Dynamic Tables**.

El flujo será:

```text
STAGING.VENTAS_DT_RAW ───────┐
                             ├── CURATED.DT_VENTAS_PUBLICABLES
CURATED.CLIENTES_DT ─────────┘                  ↓
                                  MARTS.DT_VENTAS_DIA_REGION
```

Snowflake deberá inferir las dependencias, actualizar los objetos en el orden correcto y mantener el resultado dentro de un objetivo de frescura.

---

## Objetivos

Al finalizar el ejercicio deberás ser capaz de:

1. Crear una Dynamic Table intermedia y otra de consumo.
2. Diferenciar una Dynamic Table de una view y de una tabla estándar.
3. Utilizar `TARGET_LAG = DOWNSTREAM` en una tabla intermedia.
4. Utilizar un target lag temporal en la tabla terminal.
5. Fijar explícitamente `REFRESH_MODE = INCREMENTAL`.
6. Inicializar las tablas durante la creación.
7. Verificar el modo de refresco resuelto y el estado de planificación.
8. Consultar los metadatos y el historial de refrescos.
9. Observar una actualización programada después de cambiar las fuentes.
10. Suspender un pipeline y comprobar que los datos siguen siendo consultables.
11. Reanudar y ejecutar un refresco manual.
12. Demostrar que una Dynamic Table es de solo lectura.
13. Reconciliar las métricas entre las fuentes y el resultado.
14. Suspender los objetos al finalizar para limitar el consumo.

---

## Convenciones

| Objeto | Nombre |
|---|---|
| Base de datos | `DB_CURSO` |
| Esquema de origen | `STAGING` |
| Esquema intermedio | `CURATED` |
| Esquema de consumo | `MARTS` |
| Warehouse | `WH_DEV` |
| Tabla de clientes | `CLIENTES_DT` |
| Tabla de ventas | `VENTAS_DT_RAW` |
| Dynamic Table intermedia | `DT_VENTAS_PUBLICABLES` |
| Dynamic Table terminal | `DT_VENTAS_DIA_REGION` |
| Fichero SQL del workspace | `M07_E02_DYNAMIC_TABLES.sql` |

---

## Granularidad de los objetos

### `DT_VENTAS_PUBLICABLES`

Una fila por venta completada.

Debe incluir:

- Identificador de venta.
- Fecha.
- Cliente.
- Región.
- Segmento.
- Canal.
- Importe.
- Estado.
- Fecha de modificación.

### `DT_VENTAS_DIA_REGION`

Una fila por:

```text
día + región + canal
```

Debe incluir:

- Número de ventas.
- Importe total.
- Ticket medio.
- Fecha de modificación más reciente del grupo.

---

## Tareas

### Tarea 1. Preparar Workspaces

En **Workspaces**, crea:

```text
M07_E02_DYNAMIC_TABLES.sql
```

Configura explícitamente:

- Rol.
- Warehouse.
- Base de datos.
- Esquema.
- `QUERY_TAG`.

Crea los esquemas `STAGING`, `CURATED` y `MARTS` si todavía no existen.

> Utiliza Workspaces, no Legacy Worksheets.

---

### Tarea 2. Crear las tablas fuente

Crea:

```text
DB_CURSO.CURATED.CLIENTES_DT
DB_CURSO.STAGING.VENTAS_DT_RAW
```

Activa `CHANGE_TRACKING` en ambas tablas para que puedan participar de forma predecible en refrescos incrementales.

Inserta:

- Cuatro clientes.
- Doce ventas.
- Estados `COMPLETADA`, `PENDIENTE` y `CANCELADA`.
- Datos entre el 1 y el 3 de junio de 2026.

El conjunto inicial debe contener:

```text
12 ventas totales
9 ventas COMPLETADA
importe completado = 1045.00
```

---

### Tarea 3. Crear la Dynamic Table intermedia

Crea:

```text
DB_CURSO.CURATED.DT_VENTAS_PUBLICABLES
```

Requisitos:

- `TARGET_LAG = DOWNSTREAM`.
- `SCHEDULER = ENABLE`.
- Warehouse `WH_DEV`.
- `REFRESH_MODE = INCREMENTAL`.
- `INITIALIZE = ON_CREATE`.
- Join entre ventas y clientes.
- Solo ventas `COMPLETADA`.

Explica por qué una tabla intermedia puede usar `DOWNSTREAM`.

Comprueba que contiene nueve filas.

---

### Tarea 4. Crear la Dynamic Table terminal

Crea:

```text
DB_CURSO.MARTS.DT_VENTAS_DIA_REGION
```

Requisitos:

- `TARGET_LAG = '1 minute'`.
- `SCHEDULER = ENABLE`.
- Warehouse `WH_DEV`.
- `REFRESH_MODE = INCREMENTAL`.
- `INITIALIZE = ON_CREATE`.
- Agregación por día, región y canal.

Comprueba inicialmente:

```text
8 filas agregadas
SUM(num_ventas) = 9
SUM(importe_total) = 1045.00
```

---

### Tarea 5. Inspeccionar el pipeline

Utiliza:

```text
SHOW DYNAMIC TABLES
```

y las funciones de Information Schema para comprobar:

- Nombre cualificado.
- Target lag.
- Modo de refresco.
- Estado de planificación.
- Último refresco.
- Data timestamp.
- Tablas conectadas al pipeline.

El modo resuelto debe ser `INCREMENTAL`.

Explica por qué la tabla intermedia no tiene una planificación temporal independiente.

---

### Tarea 6. Consultar el historial de refrescos

Consulta `DYNAMIC_TABLE_REFRESH_HISTORY`.

Identifica los refrescos de creación de ambas tablas y muestra:

- Nombre.
- Estado.
- Acción.
- Disparador.
- Inicio y fin.
- Data timestamp.
- Query ID.
- Warehouse utilizado.

Comprueba que la inicialización terminó correctamente.

---

### Tarea 7. Demostrar que son objetos de solo lectura

Intenta ejecutar un `INSERT` sobre la Dynamic Table terminal.

La operación debe fallar.

Explica:

- Por qué no se puede modificar directamente.
- Qué objeto debe cambiarse para alterar el resultado.
- En qué caso serían preferibles Streams y Tasks.

---

### Tarea 8. Probar el refresco automático

Sin suspender el pipeline:

1. Inserta una venta `9013`, completada, de `130.00`.
2. Actualiza la venta `9003` de `PENDIENTE` a `COMPLETADA` y cambia su importe a `155.00`.
3. No ejecutes todavía un refresco manual.
4. Consulta periódicamente el historial hasta observar un refresco programado.
5. Comprueba el resultado.

Valores esperados después del refresco:

```text
11 filas en DT_VENTAS_PUBLICABLES
9 filas agregadas
SUM(num_ventas) = 11
SUM(importe_total) = 1330.00
```

El grupo:

```text
2026-06-01 + NORTE + WEB
```

debe contener dos ventas y `255.00`.

> `TARGET_LAG` es un objetivo de frescura, no una ejecución exacta cada minuto. Si la actualización no aparece inmediatamente, espera y vuelve a consultar el historial.

---

### Tarea 9. Suspender el pipeline

Suspende la Dynamic Table terminal.

Comprueba que:

- Sigue siendo consultable.
- Conserva nueve filas y `1330.00`.
- No se ejecutan refrescos programados mientras está suspendida.

Inserta una nueva venta `9014`, completada, de `50.00`, para la combinación:

```text
2026-06-03 + SUR + TIENDA
```

Comprueba que las fuentes han cambiado, pero el resultado dinámico permanece temporalmente sin esa combinación.

---

### Tarea 10. Reanudar y refrescar manualmente

Reanuda la Dynamic Table terminal y ejecuta:

```text
ALTER DYNAMIC TABLE ... REFRESH
```

Comprueba que Snowflake actualiza primero las dependencias necesarias y después el resultado terminal.

Valores finales:

```text
12 filas en DT_VENTAS_PUBLICABLES
10 filas agregadas
SUM(num_ventas) = 12
SUM(importe_total) = 1380.00
```

La nueva combinación debe contener una venta y `50.00`.

En el historial debe aparecer un refresco con disparador manual.

---

### Tarea 11. Reconciliar el pipeline

Construye una consulta que compare:

- Ventas completadas en la tabla fuente.
- Filas de la Dynamic Table intermedia.
- Suma de `num_ventas` en la Dynamic Table terminal.
- Importe completado en la fuente.
- Importe en la intermedia.
- Suma de importes del agregado.

Todas las diferencias deben ser cero.

---

### Tarea 12. Analizar el diseño

Responde:

1. ¿Qué trabajo realiza Snowflake que habría que programar con Streams y Tasks?
2. ¿Por qué el target lag no es un cron ni un SLA estricto?
3. ¿Qué ocurriría si ambas Dynamic Tables utilizaran `TARGET_LAG = DOWNSTREAM`?
4. ¿Por qué conviene fijar `REFRESH_MODE` explícitamente?
5. ¿Qué diferencia existe entre `INITIALIZE = ON_CREATE` y `ON_SCHEDULE`?
6. ¿Qué operaciones obligarían a utilizar `CREATE OR REPLACE`?
7. ¿Por qué no debe recrearse alegremente una tabla fuente con Dynamic Tables dependientes?
8. ¿Cuándo usarías Streams y Tasks en lugar de Dynamic Tables?

---

### Tarea 13. Controlar costes al finalizar

Suspende ambas Dynamic Tables y el warehouse.

Comprueba que:

- Los datos siguen siendo consultables.
- No se ejecutarán refrescos programados hasta reanudar el pipeline.
- El warehouse queda suspendido.

---

## Criterios de finalización

El ejercicio se considera completado cuando puedas demostrar que:

- El pipeline contiene dos Dynamic Tables conectadas.
- El modo de refresco es incremental.
- La intermedia usa `DOWNSTREAM`.
- La terminal dirige el pipeline con un target lag de un minuto.
- La inicialización produce ocho filas agregadas.
- Los cambios de las fuentes se propagan automáticamente.
- La suspensión conserva datos, pero detiene la planificación.
- El refresco manual incorpora la última venta.
- El resultado final tiene diez filas, doce ventas y `1380.00`.
- La reconciliación produce diferencias cero.
- Las Dynamic Tables quedan suspendidas al terminar.

---

## Preguntas de reflexión

1. ¿En qué se diferencia una Dynamic Table de una view?
2. ¿En qué se diferencia de una materialized view?
3. ¿Qué coste tiene reducir excesivamente el target lag?
4. ¿Por qué la tabla terminal debe tener un lag temporal?
5. ¿Qué significa que el refresco sea atómico para los lectores?
6. ¿Por qué una Dynamic Table no es adecuada para un proceso con `MERGE` y lógica condicional?
7. ¿Qué monitorizarías en producción para detectar problemas de frescura o coste?

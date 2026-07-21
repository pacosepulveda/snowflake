# Módulo 5 · Ejercicio 2
## Validación de cargas y estrategias de tratamiento de errores

### Contexto

El equipo de datos de **RetailNova** recibe dos nuevos ficheros de ventas:

- Un lote que ha superado las validaciones del sistema de origen.
- Un lote que contiene una mezcla de registros correctos y registros defectuosos.

Hasta ahora, el equipo ejecutaba las cargas sin una política clara: en ocasiones se rechazaba todo el fichero y, en otras, se aceptaban silenciosamente los registros válidos. Esto dificulta la reconciliación y puede provocar que datos incompletos lleguen a producción.

Tu misión es diseñar y probar un procedimiento que permita:

1. Detectar errores antes de insertar datos.
2. Comparar distintas estrategias `ON_ERROR`.
3. Recuperar el detalle de los registros rechazados.
4. Auditar qué ocurrió en cada carga.
5. Recomendar la estrategia adecuada según la criticidad del proceso.

---

## Objetivos

Al finalizar el ejercicio deberás ser capaz de:

- Validar ficheros con `VALIDATION_MODE` sin modificar la tabla destino.
- Interpretar los errores de parsing y conversión.
- Comparar `ABORT_STATEMENT`, `CONTINUE` y `SKIP_FILE`.
- Recuperar todos los errores de una carga parcial con `VALIDATE`.
- Diferenciar Query History y `COPY_HISTORY`.
- Interpretar `ROWS_PARSED`, `ROWS_LOADED`, `ERRORS_SEEN` y el primer error.
- Diseñar una política de carga adecuada para procesos críticos y no críticos.

---

## Recursos proporcionados

### Fichero correcto

```text
Snowflake_Modulo5_Ejercicio2_ventas_validas.csv
```

Contiene cuatro registros válidos.

### Fichero con errores

```text
Snowflake_Modulo5_Ejercicio2_ventas_con_errores.csv
```

Contiene ocho registros:

- Cuatro registros válidos.
- Una fecha imposible.
- Un identificador de cliente no numérico.
- Un importe no numérico.
- Un código de moneda que supera la longitud permitida.

No corrijas los ficheros antes de subirlos.

---

## Convenciones

| Objeto | Nombre |
|---|---|
| Base de datos | `DB_CURSO` |
| Esquema | `STAGING` |
| Warehouse | `WH_DEV` |
| File format | `FF_VENTAS_CALIDAD_CSV` |
| Stage | `STG_VENTAS_CALIDAD` |
| Tabla para validación | `VENTAS_VALIDACION` |
| Tabla para ABORT | `VENTAS_ABORT` |
| Tabla para CONTINUE | `VENTAS_CONTINUE` |
| Tabla para SKIP_FILE | `VENTAS_SKIP_FILE` |
| Fichero SQL del workspace | `M05_E02_VALIDACION_ERRORES.sql` |

---

## Tareas

### Tarea 1. Preparar el workspace

En **Workspaces**, crea un fichero SQL llamado:

```text
M05_E02_VALIDACION_ERRORES.sql
```

Configura explícitamente:

- Rol.
- Warehouse.
- Base de datos.
- Esquema.

Comprueba el contexto de sesión.

> Utiliza Workspaces. No busques el antiguo menú Worksheets.

---

### Tarea 2. Crear los objetos del laboratorio

Crea un file format CSV con las siguientes características:

- Separador `;`.
- Una fila de cabecera.
- Fechas `YYYY-MM-DD`.
- Campos opcionalmente entre comillas.
- Cadenas vacías y `NULL` tratados como valores nulos.
- Detección de un número incorrecto de columnas.
- UTF-8.

Crea después un named internal stage asociado a ese file format.

Crea cuatro tablas transitorias con la misma estructura:

| Columna | Tipo |
|---|---|
| `id_venta` | `NUMBER(18,0)` |
| `fecha` | `DATE` |
| `id_cliente` | `NUMBER(18,0)` |
| `canal` | `VARCHAR(20)` |
| `importe` | `NUMBER(12,2)` |
| `moneda` | `VARCHAR(3)` |

---

### Tarea 3. Subir e inspeccionar los ficheros

Utiliza **Ingestion → Add Data → Load files into a Stage** para subir ambos CSV al stage:

```text
DB_CURSO.STAGING.STG_VENTAS_CALIDAD
```

Después:

1. Lista el stage.
2. Comprueba que aparecen los dos ficheros.
3. Consulta directamente el contenido staged.
4. Identifica visualmente las cuatro filas defectuosas.

No utilices todavía `COPY INTO` para cargar datos.

---

### Tarea 4. Validar antes de cargar

Ejecuta un `COPY INTO` contra `VENTAS_VALIDACION` con:

```text
VALIDATION_MODE = RETURN_ERRORS
```

Debes seleccionar únicamente el fichero con errores mediante `PATTERN`.

Comprueba que:

- Snowflake devuelve cuatro errores.
- La tabla `VENTAS_VALIDACION` continúa vacía.
- El resultado identifica fichero, fila, columna y mensaje de error.
- Los errores incluyen fecha, cliente, importe y longitud de moneda.

Explica por qué esta operación no inserta registros.

---

### Tarea 5. Probar ABORT_STATEMENT

Carga únicamente el fichero con errores en `VENTAS_ABORT` usando:

```text
ON_ERROR = ABORT_STATEMENT
```

Debes comprobar:

- La sentencia termina con error.
- La tabla queda vacía.
- El fallo puede localizarse en Query History.
- La operación abortada no se comporta como una carga parcial.

Investiga si aparece o no en `COPY_HISTORY` y explica el resultado.

---

### Tarea 6. Probar CONTINUE

Carga únicamente el fichero con errores en `VENTAS_CONTINUE` usando:

```text
ON_ERROR = CONTINUE
```

Comprueba en el resultado de `COPY INTO`:

- Filas analizadas.
- Filas cargadas.
- Errores detectados.
- Primer mensaje de error.
- Primera línea y columna con error.

La tabla debe contener únicamente los cuatro registros válidos:

```text
3101, 3106, 3107 y 3108
```

El total cargado debe ser:

```text
345.74
```

Explica el riesgo de aceptar una carga parcial sin revisar sus errores.

---

### Tarea 7. Recuperar todos los errores con VALIDATE

Inmediatamente después de la carga con `CONTINUE`, utiliza la función:

```text
VALIDATE
```

para recuperar todos los errores del último job de carga de la sesión.

Debes mostrar:

- Fichero.
- Número de fila.
- Nombre de columna.
- Categoría o código de error.
- Mensaje.
- Contenido de la fila rechazada cuando esté disponible.

Compara este resultado con el resultado directo de `COPY INTO`.

Explica por qué `VALIDATE` puede devolver más detalle que la sentencia de carga.

---

### Tarea 8. Probar SKIP_FILE

Carga los dos ficheros en `VENTAS_SKIP_FILE` utilizando:

```text
ON_ERROR = SKIP_FILE
```

El resultado esperado es:

- El fichero correcto se carga por completo.
- El fichero defectuoso se descarta por completo.
- La tabla contiene solo cuatro filas.
- Los identificadores cargados son `3001` a `3004`.
- El importe total es `426.50`.

Comprueba que ninguna de las filas válidas del fichero defectuoso ha sido cargada.

---

### Tarea 9. Auditar las cargas

Consulta `COPY_HISTORY` para las tablas:

- `VENTAS_CONTINUE`.
- `VENTAS_SKIP_FILE`.

Para cada fichero muestra:

- Estado.
- Filas analizadas.
- Filas cargadas.
- Número de errores.
- Primer error.
- Momento de finalización.

Compara el historial con:

- La ejecución abortada.
- La carga parcial.
- El fichero omitido.
- El fichero cargado correctamente.

---

### Tarea 10. Elaborar una recomendación

Completa esta tabla:

| Escenario | Estrategia recomendada | Justificación |
|---|---|---|
| Cierre contable |  |  |
| Telemetría con errores puntuales tolerables |  |  |
| Fichero que debe tratarse como una unidad indivisible |  |  |
| Validación previa sin insertar |  |  |

Tu recomendación debe mencionar:

- Integridad.
- Trazabilidad.
- Coste del reproceso.
- Riesgo de datos incompletos.
- Necesidad de revisar errores.

---

## Criterios de finalización

El ejercicio se considera completado cuando puedas demostrar que:

- `VALIDATION_MODE` detecta errores sin insertar filas.
- `ABORT_STATEMENT` impide la carga del fichero defectuoso.
- `CONTINUE` carga cuatro filas y rechaza cuatro.
- `VALIDATE` recupera el detalle de los errores.
- `SKIP_FILE` carga el fichero correcto y descarta el defectuoso.
- `COPY_HISTORY` permite auditar las cargas completadas.
- Puedes justificar qué estrategia utilizar en cada escenario.

---

## Preguntas de reflexión

1. ¿Por qué `CONTINUE` puede ser peligroso en un proceso financiero?
2. ¿Qué información se pierde si solo revisamos `FIRST_ERROR`?
3. ¿Por qué `SKIP_FILE` puede consumir más recursos que `ABORT_STATEMENT` o `CONTINUE`?
4. ¿Qué diferencia existe entre `VALIDATION_MODE` y `VALIDATE`?
5. ¿Por qué una sentencia abortada puede verse en Query History pero no en `COPY_HISTORY`?
6. ¿Qué controles adicionales implementarías antes de promover datos desde STAGING a CURATED?

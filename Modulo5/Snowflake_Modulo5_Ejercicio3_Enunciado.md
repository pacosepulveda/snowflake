# Módulo 5 · Ejercicio 3
## Exportación de datos a CSV y Parquet, particionado y validación de ida y vuelta

### Contexto

El equipo de datos de **RetailNova** debe entregar información de ventas a dos consumidores diferentes:

- El equipo financiero necesita un único fichero CSV agregado, fácil de descargar y abrir.
- La plataforma analítica necesita datos detallados en Parquet, conservando tipos y organizados por mes para facilitar su procesamiento.

La entrega se realizará inicialmente en un **named internal stage** de Snowflake. Antes de darla por válida, debes volver a cargar los ficheros Parquet en una tabla de comprobación y demostrar que los datos exportados coinciden con la tabla de origen.

Este laboratorio representa la operación inversa a la carga:

```text
Tabla o consulta
        ↓
COPY INTO <location>
        ↓
Ficheros en un stage
```

---

## Objetivos

Al finalizar el ejercicio deberás ser capaz de:

1. Crear formatos reutilizables para descarga.
2. Exportar el resultado de una consulta a un único CSV.
3. Exportar una tabla a Parquet.
4. Particionar una descarga mediante `PARTITION BY`.
5. Utilizar `VALIDATION_MODE = RETURN_ROWS` para validar la consulta de descarga.
6. Inspeccionar los ficheros generados con `LIST`.
7. Consultar directamente los ficheros Parquet staged.
8. Volver a cargarlos con `MATCH_BY_COLUMN_NAME`.
9. Reconciliar origen y destino.
10. Explicar cómo cambiaría el diseño al utilizar un bucket externo y una storage integration.

---

## Recursos

No es necesario descargar ningún fichero de datos. La tabla de origen se generará mediante SQL con 20.000 ventas sintéticas y deterministas.

---

## Convenciones

| Objeto | Nombre |
|---|---|
| Base de datos | `DB_CURSO` |
| Esquema origen | `CURATED` |
| Esquema técnico | `STAGING` |
| Warehouse | `WH_DEV` |
| Tabla origen | `VENTAS_EXPORT` |
| Stage de exportación | `STG_EXPORT_VENTAS` |
| File format Parquet | `FF_EXPORT_PARQUET` |
| Tabla de comprobación | `VENTAS_REIMPORTADAS` |
| Fichero SQL del workspace | `M05_E03_UNLOAD_PARQUET.sql` |

Rutas dentro del stage:

```text
csv/resumen/
parquet/ventas/
```

---

## Tareas

### Tarea 1. Preparar Workspaces y el contexto

En **Workspaces**, crea un fichero SQL llamado:

```text
M05_E03_UNLOAD_PARQUET.sql
```

Configura explícitamente:

- Rol.
- Warehouse.
- Base de datos.
- Esquema.

Añade un `QUERY_TAG` que permita identificar las consultas del ejercicio.

> Utiliza Workspaces, no Legacy Worksheets.

---

### Tarea 2. Crear la tabla de origen

Crea una tabla transitoria en:

```text
DB_CURSO.CURATED.VENTAS_EXPORT
```

con 20.000 filas y estas columnas:

| Columna | Tipo |
|---|---|
| `id_venta` | `NUMBER(18,0)` |
| `fecha` | `DATE` |
| `region` | `VARCHAR(10)` |
| `canal` | `VARCHAR(20)` |
| `importe` | `NUMBER(12,2)` |
| `moneda` | `VARCHAR(3)` |
| `es_promocion` | `BOOLEAN` |

Los datos deben cubrir enero y febrero de 2026.

Comprueba:

- Número de filas.
- Fecha mínima y máxima.
- Importe total.
- Número de ventas por mes.

Guarda estas métricas porque se utilizarán para reconciliar la reimportación.

---

### Tarea 3. Crear el stage y el file format Parquet

Crea:

```text
DB_CURSO.STAGING.FF_EXPORT_PARQUET
```

con:

- Tipo Parquet.
- Compresión Snappy.
- Tipos lógicos habilitados.

Crea después:

```text
DB_CURSO.STAGING.STG_EXPORT_VENTAS
```

como named internal stage cifrado mediante el mecanismo gestionado por Snowflake.

No asocies un file format predeterminado al stage, porque se utilizará para CSV y Parquet.

---

### Tarea 4. Validar la consulta de descarga

Antes de generar ficheros, utiliza:

```text
VALIDATION_MODE = RETURN_ROWS
```

en un `COPY INTO <location>` para devolver diez filas de la consulta que posteriormente exportarás.

Comprueba que:

- Se muestran las filas.
- No se crea ningún fichero en la ruta de validación.
- Los tipos y columnas son los esperados.

Explica la diferencia entre este modo de validación y `VALIDATION_MODE` de una carga hacia una tabla.

---

### Tarea 5. Crear una entrega CSV de resumen

Exporta a la ruta:

```text
@DB_CURSO.STAGING.STG_EXPORT_VENTAS/csv/resumen/
```

un resumen mensual por región con:

- Mes.
- Región.
- Número de ventas.
- Importe total.

Requisitos:

- Formato CSV.
- Separador `;`.
- Cabecera.
- Compresión GZIP.
- Un solo fichero.
- Sobrescritura permitida para poder regenerar la entrega.
- Resultado detallado de la operación.

Después, utiliza `LIST` para comprobar que se ha generado un único fichero.

---

### Tarea 6. Exportar el detalle a Parquet particionado

Antes de exportar, elimina cualquier fichero previo que exista bajo:

```text
parquet/ventas/
```

Exporta la tabla completa a:

```text
@DB_CURSO.STAGING.STG_EXPORT_VENTAS/parquet/ventas/
```

Requisitos:

- Utilizar el named file format `FF_EXPORT_PARQUET`.
- Conservar los nombres de las columnas.
- Particionar por mes con una expresión `YYYY-MM`.
- Utilizar un tamaño máximo de fichero de 16 MB.
- Incluir el Query ID en los nombres.
- Solicitar salida detallada.

No utilices:

- `SINGLE = TRUE`.
- `OVERWRITE = TRUE`.
- Datos personales en la expresión de particionado.

---

### Tarea 7. Inspeccionar los ficheros generados

Utiliza `LIST` para comprobar:

- Número de ficheros.
- Rutas correspondientes a enero y febrero.
- Extensión Parquet.
- Tamaño de los ficheros.
- Presencia de identificadores únicos en los nombres.

Explica por qué no debe utilizarse una columna sensible, como correo o identificador de cliente, en `PARTITION BY`.

---

### Tarea 8. Consultar directamente el Parquet staged

Consulta algunas filas directamente desde:

```text
@DB_CURSO.STAGING.STG_EXPORT_VENTAS/parquet/ventas/
```

utilizando el file format Parquet.

Muestra al menos:

- `ID_VENTA`.
- `FECHA`.
- `REGION`.
- `CANAL`.
- `IMPORTE`.
- `ES_PROMOCION`.
- `METADATA$FILENAME`.

Comprueba que los campos pueden convertirse a sus tipos originales.

---

### Tarea 9. Realizar una carga de ida y vuelta

Crea la tabla:

```text
DB_CURSO.STAGING.VENTAS_REIMPORTADAS
```

con la misma estructura que la tabla de origen.

Carga en ella todos los ficheros Parquet de la ruta de exportación usando:

```text
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
```

y:

```text
ON_ERROR = ABORT_STATEMENT
```

No transformes los datos durante esta carga.

---

### Tarea 10. Reconciliar origen y reimportación

Demuestra que:

1. Ambas tablas contienen 20.000 filas.
2. Tienen la misma fecha mínima y máxima.
3. Tienen el mismo importe total.
4. Tienen la misma distribución por mes.
5. No existen filas en origen que falten en destino.
6. No existen filas en destino que falten en origen.

La comprobación de diferencias debe realizarse en ambos sentidos.

---

### Tarea 11. Descargar opcionalmente el CSV

Explica por qué el comando `GET` no debe ejecutarse dentro de Workspaces.

Prepara, sin necesidad de ejecutarlo, un ejemplo para descargar el fichero CSV mediante Snowflake CLI o SnowSQL a:

- Una carpeta Linux o macOS.
- Una carpeta Windows.

---

### Tarea 12. Diseñar la variante de producción

Sin crear recursos externos, describe cómo cambiaría el diseño para descargar directamente a:

- Amazon S3.
- Azure Blob Storage o ADLS.
- Google Cloud Storage.

La respuesta debe incluir:

1. Rol o identidad en el proveedor cloud.
2. `CREATE STORAGE INTEGRATION`.
3. `DESC INTEGRATION`.
4. Configuración de confianza en el proveedor.
5. Named external stage.
6. `STORAGE_ALLOWED_LOCATIONS`.
7. Ausencia de claves permanentes en scripts.

---

## Preguntas de reflexión

1. ¿Por qué Parquet es más adecuado que CSV para una plataforma analítica?
2. ¿Qué ventaja aporta `HEADER = TRUE` al descargar Parquet?
3. ¿Por qué `PARTITION BY` no puede combinarse con `SINGLE = TRUE`?
4. ¿Qué ocurre al repetir una descarga particionada sin limpiar la ruta?
5. ¿Cuál es la diferencia entre `COPY INTO <table>` y `COPY INTO <location>`?
6. ¿Por qué `GET` es un comando de cliente y no una operación propia del editor web?
7. ¿Por qué una storage integration es preferible a incrustar credenciales cloud?

# Módulo 5 · Ejercicio 1
## Carga batch de un fichero CSV desde un stage interno

### Contexto

La empresa **RetailNova** recibe cada día un fichero CSV exportado por su sistema de ventas. El equipo de datos quiere empezar con una carga batch sencilla y controlada antes de automatizar el proceso.

El fichero recibido contiene ventas de varios canales. Algunos valores de la columna `canal` utilizan mayúsculas, minúsculas o espacios adicionales. Además de cargar los datos de negocio, el equipo necesita conservar información de trazabilidad que permita saber de qué fichero y de qué fila procede cada registro. La ingesta utilizará las transformaciones básicas admitidas por `COPY INTO`, y la conversión a mayúsculas se realizará después con SQL ordinario.

---

## Objetivos

Al terminar el ejercicio deberás ser capaz de:

1. Crear y reutilizar un **file format** para un fichero CSV.
2. Crear un **named internal stage**.
3. Subir un fichero desde Snowsight.
4. Inspeccionar el contenido del stage antes de cargarlo.
5. Consultar directamente un fichero staged.
6. Aplicar dentro de `COPY INTO` conversiones y transformaciones compatibles.
7. Completar la normalización mediante una sentencia SQL posterior a la carga.
8. Incorporar metadatos de trazabilidad del fichero.
9. Comprobar el mecanismo que evita recargar accidentalmente el mismo fichero.
10. Consultar el historial de carga con `COPY_HISTORY`.

---

## Recursos proporcionados

Descarga el fichero:

`Snowflake_Modulo5_Ejercicio1_ventas_julio.csv`

Características del fichero:

- Codificación: UTF-8.
- Primera fila: cabecera.
- Separador: punto y coma (`;`).
- Doce registros de datos.
- Fechas con formato `YYYY-MM-DD`.
- Importes con punto decimal.
- Algunos valores de `canal` contienen espacios o diferencias de mayúsculas.

No modifiques el fichero antes de subirlo.

---

## Convenciones que debes utilizar

| Objeto | Nombre |
|---|---|
| Base de datos | `DB_CURSO` |
| Esquema | `STAGING` |
| Warehouse | `WH_DEV` |
| File format | `FF_VENTAS_CSV` |
| Named internal stage | `STG_VENTAS_CSV` |
| Tabla destino | `VENTAS_RAW` |
| Fichero SQL del workspace | `M05_E01_CARGA_CSV.sql` |

Utiliza nombres completamente cualificados cuando sea útil:

```text
DB_CURSO.STAGING.OBJETO
```

---

## Tareas

### Tarea 1. Preparar el entorno de trabajo

En **Workspaces**, crea o abre un workspace para el curso y añade un fichero SQL llamado:

```text
M05_E01_CARGA_CSV.sql
```

Configura explícitamente al principio del fichero:

- El rol con el que crearás los objetos.
- El warehouse.
- La base de datos.
- El esquema.

Comprueba mediante funciones de contexto que la sesión utiliza los valores esperados.

> En la interfaz actual de Snowflake se utiliza **Workspaces** como experiencia de edición SQL. No debes buscar el antiguo menú Worksheets.

---

### Tarea 2. Crear el file format

Crea un file format llamado `FF_VENTAS_CSV` que permita leer correctamente el fichero proporcionado.

Debe contemplar, como mínimo:

- Tipo CSV.
- Separador `;`.
- Una fila de cabecera.
- Campos opcionalmente encerrados entre comillas dobles.
- Cadenas vacías y el texto `NULL` tratados como valores nulos.
- Codificación UTF-8.
- Detección de un número incorrecto de columnas.

Comprueba su configuración con un comando de descripción.

---

### Tarea 3. Crear el named internal stage

Crea el stage `STG_VENTAS_CSV` dentro de `DB_CURSO.STAGING`.

Requisitos:

- Debe ser un named internal stage.
- Debe reutilizar el file format creado anteriormente.
- Debe usar cifrado gestionado por Snowflake.
- No es necesario habilitar una directory table.

Comprueba que el stage existe y que inicialmente no contiene ficheros.

---

### Tarea 4. Subir el fichero desde Snowsight

Utiliza la interfaz de Snowsight para subir:

```text
Snowflake_Modulo5_Ejercicio1_ventas_julio.csv
```

al stage:

```text
DB_CURSO.STAGING.STG_VENTAS_CSV
```

No utilices `PUT`, ya que este comando no se ejecuta desde el editor SQL web.

Después de la subida:

1. Lista el contenido del stage.
2. Comprueba el nombre del fichero.
3. Comprueba su tamaño.
4. No elimines ni purgues todavía el fichero.

---

### Tarea 5. Consultar el fichero antes de cargarlo

Ejecuta una consulta directamente contra el stage para mostrar:

- `METADATA$FILENAME`.
- `METADATA$FILE_ROW_NUMBER`.
- Las seis columnas del fichero mediante `$1` a `$6`.

Ordena el resultado por número de fila.

Comprueba que:

- La cabecera no aparece como un registro.
- Se obtienen doce filas.
- Cada columna se ha separado correctamente.
- Los espacios de la columna `canal` todavía están presentes.

---

### Tarea 6. Crear la tabla RAW

Crea una tabla **transitoria** llamada `VENTAS_RAW`.

Debe contener:

| Columna | Tipo o finalidad |
|---|---|
| `id_venta` | Número entero |
| `fecha` | Fecha |
| `id_cliente` | Número entero |
| `canal` | Texto cargado y posteriormente normalizado |
| `importe` | Número con dos decimales |
| `moneda` | Código de moneda |
| `fichero_origen` | Nombre del fichero staged |
| `fila_origen` | Número de fila dentro del fichero |
| `inicio_carga` | Momento en que Snowflake comenzó a leer el registro |

La tabla pertenece a la capa STAGING porque conserva datos próximos a la fuente y trazabilidad técnica.

---

### Tarea 7. Cargar con transformaciones compatibles mediante COPY INTO

Carga el fichero en `VENTAS_RAW` mediante una transformación dentro de `COPY INTO`.

Durante la carga debes:

- Convertir los identificadores a números.
- Convertir la fecha a `DATE`.
- Convertir el importe a `NUMBER(12,2)`.
- Eliminar espacios al principio y al final de `canal` mediante `TRIM`.
- Eliminar posibles espacios de `moneda` mediante `TRIM`.
- Cargar `METADATA$FILENAME`.
- Cargar `METADATA$FILE_ROW_NUMBER`.
- Cargar `METADATA$START_SCAN_TIME`.
- Abortar la sentencia si se encuentra un error.
- Mantener el fichero en el stage después de la carga.

No utilices `FORCE = TRUE`.

> El `SELECT` de transformación de `COPY INTO` solo admite un subconjunto de funciones SQL. Aunque `UPPER` es una función válida en consultas ordinarias, no está admitida actualmente dentro de esta transformación. Por tanto, no utilices `UPPER` dentro del `COPY`.

---

### Tarea 8. Normalizar los valores después de la carga

Una vez terminada la carga, utiliza una sentencia `UPDATE` para normalizar:

- `canal` sin espacios exteriores y en mayúsculas.
- `moneda` sin espacios exteriores y en mayúsculas.

La transformación debe utilizar:

```text
UPPER(TRIM(...))
```

Comprueba que la sentencia es idempotente: si se ejecuta otra vez, los valores no cambian.

Explica por qué esta normalización se ejecuta fuera de `COPY INTO`.

> En una arquitectura de producción, la capa RAW suele conservarse inmutable y la normalización se escribe en una capa posterior. En este ejercicio se utiliza una sola tabla para mantener el laboratorio acotado.

---

### Tarea 9. Validar el resultado

Demuestra mediante consultas SQL que:

1. La tabla contiene exactamente **12 filas**.
2. La suma de `importe` es **1850.43**.
3. Solo existen los canales `WEB`, `TIENDA` y `MARKETPLACE`.
4. Todos los registros tienen moneda `EUR`.
5. Ninguna columna obligatoria contiene `NULL`.
6. Todos los registros conservan fichero y fila de origen.
7. La combinación `(fichero_origen, fila_origen)` no contiene duplicados.

Muestra también el total vendido por canal.

---

### Tarea 10. Comprobar la protección contra recargas accidentales

Sin modificar el fichero ni recrear la tabla, ejecuta por segunda vez el mismo `COPY INTO` de la tarea 7.

Después:

1. Comprueba el resultado devuelto por `COPY INTO`.
2. Vuelve a contar las filas de `VENTAS_RAW`.
3. Confirma que siguen existiendo **12 filas**, no 24.
4. Explica por qué Snowflake no ha vuelto a cargar el fichero.
5. Explica qué riesgo tendría utilizar `FORCE = TRUE`.

No es necesario volver a ejecutar el `UPDATE`, porque el segundo `COPY` no debe añadir filas.

---

### Tarea 11. Auditar la carga

Consulta `COPY_HISTORY` para la tabla `VENTAS_RAW` durante la última hora.

El informe debe mostrar al menos:

- Nombre del fichero.
- Localización del stage.
- Fecha y hora de carga.
- Filas analizadas.
- Filas cargadas.
- Número de errores.
- Estado.

Relaciona el resultado de `COPY_HISTORY` con las dos ejecuciones de `COPY INTO`.

---

## Preguntas de reflexión

1. ¿Por qué es preferible reutilizar un named file format en lugar de repetir todas las opciones en cada `COPY INTO`?
2. ¿Qué diferencia práctica existe entre consultar un fichero staged y cargarlo en una tabla?
3. ¿Por qué es útil guardar `METADATA$FILENAME` y `METADATA$FILE_ROW_NUMBER`?
4. ¿Por qué `FORCE = TRUE` no debería ser la opción predeterminada?
5. ¿En qué situación tendría sentido añadir `PURGE = TRUE`?
6. ¿Por qué se utiliza una tabla transitoria para esta capa RAW?
7. ¿Por qué la normalización con `UPPER` se realiza después de `COPY INTO` y no dentro de su `SELECT` de transformación?

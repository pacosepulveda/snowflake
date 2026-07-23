# Módulo 7 · Ejercicio 2

## Pipeline automático con Snowpipe, Amazon S3, streams y triggered tasks

### Contexto

RetailNova recibe continuamente archivos CSV con eventos de pedidos generados por sus sistemas de venta.

Cada archivo se deposita en Amazon S3 y puede contener:

- Pedidos nuevos.
- Cambios de estado de pedidos existentes.
- Varias versiones del mismo pedido dentro del mismo archivo.
- Eventos tardíos con una versión anterior a la ya procesada.

El equipo de datos quiere construir un pipeline automático que no dependa de ejecutar manualmente `COPY INTO` ni de lanzar transformaciones a intervalos fijos.

Cada participante trabajará con:

- Su propia cuenta de Snowflake.
- Su propio bucket de Amazon S3.
- Sus propios objetos de AWS IAM.
- Sus propias tablas, streams, tasks y pipe.

Todos los buckets estarán alojados en una única cuenta AWS proporcionada por el instructor. Cada alumno recibirá permisos para crear y configurar exclusivamente los recursos necesarios para su laboratorio.

---

## Arquitectura objetivo

```text
Archivo CSV
    │
    ▼
Amazon S3
<bucket-del-alumno>/entrada/
    │
    │ Evento ObjectCreated
    ▼
SQS administrada por Snowflake
    │
    ▼
Snowpipe AUTO_INGEST
    │
    ▼
STAGING.PEDIDOS_RAW
    │
    │ Stream + triggered task
    ▼
CURATED.PEDIDOS_ACTUALES
    │
    │ Stream + triggered task
    ▼
MART.VENTAS_DIARIAS
```

Snowpipe se encargará únicamente de la ingestión de los archivos.

Las transformaciones posteriores se realizarán mediante streams y triggered tasks:

```text
S3
 ↓
PIPE_PEDIDOS_AUTO
 ↓
STAGING.PEDIDOS_RAW
 ↓
STR_PEDIDOS_RAW
 ↓
TASK_RAW_A_CURATED
 ↓
CURATED.PEDIDOS_ACTUALES
 ↓
STR_PEDIDOS_CURATED
 ↓
TASK_CURATED_A_MART
 ↓
MART.VENTAS_DIARIAS
```

---

## Objetivos

Al finalizar el ejercicio deberás ser capaz de:

1. Crear un bucket S3 privado y una carpeta de entrada.
2. Crear una política IAM de acceso mínimo al bucket.
3. Crear un rol IAM que pueda ser asumido por Snowflake.
4. Configurar una `STORAGE INTEGRATION`.
5. Diferenciar la política de confianza de la política de permisos.
6. Crear un stage externo sobre Amazon S3.
7. Crear un pipe con `AUTO_INGEST = TRUE`.
8. Obtener el canal de notificación SQS administrado por Snowflake.
9. Configurar una notificación de eventos en el bucket S3.
10. Comprobar que un archivo nuevo se carga sin ejecutar manualmente `COPY INTO`.
11. Incorporar metadatos del archivo durante la ingestión.
12. Monitorizar Snowpipe mediante `SYSTEM$PIPE_STATUS`.
13. Consultar el historial de carga mediante `COPY_HISTORY`.
14. Crear un stream sobre la tabla RAW.
15. Crear una triggered task que deduplica y consolida pedidos.
16. Mantener una única versión actual por pedido en `CURATED`.
17. Crear un segundo stream y una segunda triggered task.
18. Mantener automáticamente un agregado diario en `MART`.
19. Procesar pedidos nuevos y cambios de estado.
20. Ignorar correctamente versiones antiguas.
21. Explicar cómo se evita volver a cargar el mismo archivo.
22. Recuperar archivos que se subieron antes de configurar las notificaciones.
23. Auditar el pipeline completo.
24. Suspender y eliminar los recursos al finalizar.

---

## Convenciones de nombres

### Snowflake

Como cada participante utiliza una cuenta Snowflake diferente, todos pueden usar los mismos nombres:

| Objeto | Nombre |
|---|---|
| Rol de trabajo | `SYSADMIN` |
| Warehouse | `WH_DEV` |
| Base de datos | `DB_CURSO` |
| Esquema de aterrizaje | `STAGING` |
| Esquema depurado | `CURATED` |
| Esquema analítico | `MART` |
| Storage integration | `S3_SNOWPIPE_INT` |
| File format | `FF_PEDIDOS_CSV` |
| External stage | `STG_S3_PEDIDOS` |
| Tabla RAW | `PEDIDOS_RAW` |
| Stream RAW | `STR_PEDIDOS_RAW` |
| Pipe | `PIPE_PEDIDOS_AUTO` |
| Tabla CURATED | `PEDIDOS_ACTUALES` |
| Stream CURATED | `STR_PEDIDOS_CURATED` |
| Task RAW → CURATED | `TASK_RAW_A_CURATED` |
| Tabla MART | `VENTAS_DIARIAS` |
| Task CURATED → MART | `TASK_CURATED_A_MART` |
| Fichero SQL del workspace | `M07_E02_SNOWPIPE_S3_PIPELINE.sql` |

### AWS

Los recursos de AWS se comparten dentro de una única cuenta, por lo que sus nombres deben ser únicos.

Cada participante elegirá un alias corto en minúsculas:

```text
<ALIAS>
```

Por ejemplo:

```text
ana
luis
instructor
```

Utiliza ese alias en todos tus recursos AWS.

| Recurso | Patrón |
|---|---|
| Bucket | `sf-m7-snowpipe-<alias>-<sufijo-unico>` |
| Carpeta de entrada | `entrada/` |
| Política IAM | `SnowflakeSnowpipeS3ReadPolicy_<ALIAS>` |
| Rol IAM | `SnowflakeSnowpipeS3ReadRole_<ALIAS>` |
| Notificación S3 | `snowpipe-pedidos-<alias>` |

> Los nombres de bucket deben escribirse en minúsculas y ser globalmente únicos.

---

## Reglas de aislamiento

1. Utiliza únicamente el bucket y los recursos IAM que incluyan tu alias.
2. No modifiques recursos creados por otros alumnos.
3. No reutilices el rol IAM de otro participante.
4. No configures tu stage con el bucket de otro participante.
5. Mantén activado **Block all public access**.
6. No compartas claves de acceso.
7. No hagas público ningún objeto.
8. Utiliza nombres de archivo nuevos para cada microbatch.

---

## Diseño del archivo de entrada

Los archivos CSV tendrán una fila de cabecera y las siguientes columnas:

| Posición | Columna | Descripción |
|---:|---|---|
| 1 | `event_id` | Identificador único del evento |
| 2 | `id_pedido` | Clave de negocio del pedido |
| 3 | `id_cliente` | Cliente asociado |
| 4 | `fecha_pedido` | Fecha del pedido |
| 5 | `region` | Región comercial |
| 6 | `producto` | Producto |
| 7 | `cantidad` | Número de unidades |
| 8 | `precio_unitario` | Precio por unidad |
| 9 | `estado` | `PENDIENTE`, `COMPLETADA` o `CANCELADA` |
| 10 | `fecha_modificacion` | Versión de negocio del evento |

La tabla RAW añadirá además metadatos técnicos:

| Columna técnica | Finalidad |
|---|---|
| `_source_file` | Archivo de origen |
| `_source_row_number` | Número de fila dentro del archivo |
| `_file_last_modified` | Última modificación del objeto en S3 |
| `_loaded_at` | Momento en que Snowpipe empezó a procesar la fila |

---

## Diseño de las capas

### STAGING

```text
DB_CURSO.STAGING.PEDIDOS_RAW
```

Características:

- Recibe los archivos mediante Snowpipe.
- Conserva los campos de negocio como texto.
- Conserva metadatos del archivo.
- Funciona como registro append-only.
- No se actualiza ni elimina durante el flujo normal.

### CURATED

```text
DB_CURSO.CURATED.PEDIDOS_ACTUALES
```

Características:

- Contiene datos tipados.
- Mantiene una sola fila por `id_pedido`.
- Conserva la versión más reciente.
- Utiliza `fecha_modificacion` como criterio principal.
- Utiliza `event_id` como desempate.
- Calcula `importe_linea = cantidad × precio_unitario`.

### MART

```text
DB_CURSO.MART.VENTAS_DIARIAS
```

Contendrá una fila por fecha con:

| Métrica | Descripción |
|---|---|
| `pedidos_total` | Pedidos actuales de la fecha |
| `pedidos_completados` | Pedidos completados |
| `pedidos_cancelados` | Pedidos cancelados |
| `pedidos_pendientes` | Pedidos pendientes |
| `unidades_vendidas` | Unidades de pedidos completados |
| `importe_ventas` | Importe de pedidos completados |
| `_updated_at` | Momento de actualización del agregado |

---

# Tareas

## Tarea 1. Preparar el workspace y el contexto

En **Workspaces**, crea:

```text
M07_E02_SNOWPIPE_S3_PIPELINE.sql
```

Configura:

- Rol `SYSADMIN`.
- Warehouse `XSMALL`.
- Auto-suspend de 60 segundos.
- Base de datos `DB_CURSO`.
- Esquemas `STAGING`, `CURATED` y `MART`.
- Un `QUERY_TAG`.

Con `ACCOUNTADMIN`, concede a `SYSADMIN` los privilegios globales necesarios para ejecutar tasks.

---

## Tarea 2. Crear los archivos de prueba

Crea localmente tres archivos:

```text
pedidos_01.csv
pedidos_02.csv
pedidos_03_tardio.csv
```

Los archivos representarán:

1. Un primer microbatch con pedidos nuevos y varias versiones de un pedido.
2. Un segundo microbatch con pedidos nuevos y cambios de estado.
3. Un evento tardío que no debe sobrescribir una versión más reciente.

Los archivos no deben subirse todavía.

---

## Tarea 3. Crear un bucket S3 propio

En la cuenta AWS del laboratorio:

1. Crea un bucket privado que incluya tu alias.
2. Utiliza la región indicada por el instructor.
3. Mantén activado el bloqueo de acceso público.
4. Crea el prefijo:

```text
entrada/
```

No subas todavía los archivos CSV.

---

## Tarea 4. Crear la política IAM de almacenamiento

Crea una política IAM que conceda al futuro rol de Snowflake exclusivamente:

```text
s3:GetBucketLocation
s3:ListBucket
s3:GetObject
s3:GetObjectVersion
```

Limita los permisos:

- Al bucket que has creado.
- Al prefijo `entrada/`.
- A los objetos situados bajo ese prefijo.

Comprueba la diferencia entre:

```text
arn:aws:s3:::<bucket>
```

y:

```text
arn:aws:s3:::<bucket>/entrada/*
```

---

## Tarea 5. Crear el rol IAM

Crea un rol IAM propio:

```text
SnowflakeSnowpipeS3ReadRole_<ALIAS>
```

Inicialmente:

- Confía de forma provisional en la cuenta AWS indicada durante la creación.
- Requiere un `External ID` temporal.
- Tiene adjunta la política de lectura creada en la tarea anterior.

Copia el ARN del rol.

---

## Tarea 6. Crear la storage integration

En tu cuenta de Snowflake:

1. Crea `S3_SNOWPIPE_INT`.
2. Configura el ARN de tu rol IAM.
3. Limita `STORAGE_ALLOWED_LOCATIONS` a tu bucket y a `entrada/`.
4. Concede `USAGE` sobre la integración a `SYSADMIN`.

Obtén:

```text
STORAGE_AWS_IAM_USER_ARN
STORAGE_AWS_EXTERNAL_ID
```

---

## Tarea 7. Completar la política de confianza

Actualiza la trust policy de tu rol IAM para permitir que Snowflake lo asuma.

La relación debe exigir simultáneamente:

- El `STORAGE_AWS_IAM_USER_ARN` de tu cuenta Snowflake.
- El `STORAGE_AWS_EXTERNAL_ID` de tu integración.

Comprueba que:

- La política de confianza permite `sts:AssumeRole`.
- La política de permisos sigue concediendo acceso a S3.
- Ambas políticas están configuradas en el mismo rol.

---

## Tarea 8. Validar el acceso a S3

Antes de crear Snowpipe:

1. Sube un pequeño archivo temporal bajo `entrada/`.
2. Valida la operación de lectura con `SYSTEM$VALIDATE_STORAGE_INTEGRATION`.
3. Elimina el archivo temporal.
4. Comprueba que la integración no permite acceder a otros buckets.

---

## Tarea 9. Crear los objetos de las tres capas

Crea:

```text
STAGING.PEDIDOS_RAW
CURATED.PEDIDOS_ACTUALES
MART.VENTAS_DIARIAS
```

Crea también:

```text
STAGING.STR_PEDIDOS_RAW
CURATED.STR_PEDIDOS_CURATED
```

Los dos streams deben existir antes de subir el primer archivo.

---

## Tarea 10. Crear el file format y el external stage

Crea:

```text
STAGING.FF_PEDIDOS_CSV
STAGING.STG_S3_PEDIDOS
```

El stage debe:

- Apuntar a tu bucket.
- Apuntar al prefijo `entrada/`.
- Utilizar `S3_SNOWPIPE_INT`.
- Utilizar el formato CSV.
- Permitir listar los archivos sin hacer público el bucket.

---

## Tarea 11. Crear la transformación RAW → CURATED

Crea una triggered task:

```text
STAGING.TASK_RAW_A_CURATED
```

La task debe:

1. Ejecutarse cuando `STR_PEDIDOS_RAW` tenga cambios.
2. No utilizar `SCHEDULE`.
3. Utilizar `WH_DEV`.
4. Convertir los campos de texto a sus tipos correctos.
5. Deduplicar el microbatch por `id_pedido`.
6. Conservar la mayor `fecha_modificacion`.
7. Utilizar `event_id` como desempate.
8. Insertar pedidos nuevos.
9. Actualizar únicamente versiones más recientes.
10. Ignorar versiones antiguas.
11. Consumir el stream al confirmar el `MERGE`.

La task debe crearse inicialmente suspendida.

---

## Tarea 12. Crear la transformación CURATED → MART

Crea una segunda triggered task:

```text
CURATED.TASK_CURATED_A_MART
```

La task debe:

1. Ejecutarse cuando `STR_PEDIDOS_CURATED` tenga cambios.
2. Identificar las fechas afectadas por el microbatch.
3. Recalcular esas fechas desde el estado actual de CURATED.
4. Insertar o actualizar las filas correspondientes de MART.
5. Contabilizar ventas únicamente para pedidos `COMPLETADA`.
6. Consumir el stream al confirmar el `MERGE`.

La task debe crearse inicialmente suspendida.

---

## Tarea 13. Crear Snowpipe

Crea:

```text
STAGING.PIPE_PEDIDOS_AUTO
```

La definición debe:

- Utilizar `AUTO_INGEST = TRUE`.
- Cargar en `STAGING.PEDIDOS_RAW`.
- Leer desde `STG_S3_PEDIDOS`.
- Incorporar las diez columnas del CSV.
- Incorporar los cuatro metadatos técnicos.
- Procesar únicamente archivos CSV.
- No depender de `WH_DEV`.

Comprueba la definición del pipe.

---

## Tarea 14. Obtener el canal SQS

Ejecuta `SHOW PIPES` y localiza:

```text
notification_channel
```

Copia el ARN completo de la cola SQS.

No debes crear esa cola manualmente: está administrada por Snowflake.

---

## Tarea 15. Configurar la notificación S3

En las propiedades de tu bucket, crea una notificación con:

| Opción | Valor |
|---|---|
| Nombre | Incluye tu alias |
| Prefijo | `entrada/` |
| Sufijo | `.csv` |
| Evento | Todos los eventos de creación de objetos |
| Destino | Cola SQS |
| ARN SQS | Valor obtenido de `SHOW PIPES` |

No selecciones una cola de otro alumno.

---

## Tarea 16. Activar las tasks

Reanuda:

```text
TASK_RAW_A_CURATED
TASK_CURATED_A_MART
```

Comprueba que ambas están activas y que los streams están inicialmente vacíos.

---

## Tarea 17. Procesar el primer microbatch

Sube:

```text
pedidos_01.csv
```

a:

```text
s3://<tu-bucket>/entrada/
```

No ejecutes manualmente:

```sql
COPY INTO
```

Comprueba el flujo completo:

```text
S3
→ Snowpipe
→ PEDIDOS_RAW
→ TASK_RAW_A_CURATED
→ PEDIDOS_ACTUALES
→ TASK_CURATED_A_MART
→ VENTAS_DIARIAS
```

Resultados esperados:

```text
6 eventos en RAW
5 pedidos en CURATED
2 fechas en MART
```

---

## Tarea 18. Monitorizar Snowpipe

Utiliza:

```text
SHOW PIPES
SYSTEM$PIPE_STATUS
COPY_HISTORY
```

Comprueba:

- Estado del pipe.
- Canal de notificación.
- Nombre del archivo cargado.
- Número de filas.
- Estado de carga.
- Errores.
- Hora de recepción.
- Bytes facturados, cuando estén disponibles.

---

## Tarea 19. Monitorizar las tasks

Consulta `TASK_HISTORY` para las dos tasks.

Comprueba:

- Estado `SUCCEEDED`.
- Origen `TRIGGER`.
- Hora de inicio.
- Hora de finalización.
- Query ID.
- Mensajes de error.
- Orden lógico de las transformaciones.

Comprueba también que ambos streams quedan vacíos tras el procesamiento.

---

## Tarea 20. Procesar el segundo microbatch

Sube:

```text
pedidos_02.csv
```

El archivo incluye:

- Dos cambios de estado.
- Dos pedidos nuevos.
- Dos versiones de uno de los pedidos nuevos.

No ejecutes manualmente ninguna transformación.

Resultados esperados después de completar el pipeline:

```text
11 eventos en RAW
7 pedidos en CURATED
3 fechas en MART
```

Resumen global esperado:

```text
5 pedidos COMPLETADA
2 pedidos CANCELADA
0 pedidos PENDIENTE
8 unidades vendidas
importe de ventas = 1270.00
```

---

## Tarea 21. Procesar un evento tardío

Sube:

```text
pedidos_03_tardio.csv
```

El archivo contiene una versión antigua de un pedido existente.

Comprueba que:

- Snowpipe carga el evento en RAW.
- `TASK_RAW_A_CURATED` se ejecuta.
- El `MERGE` no sobrescribe la versión más reciente.
- CURATED mantiene siete pedidos.
- MART no cambia.
- El stream RAW queda vacío.
- La task de MART no necesita ejecutarse si CURATED no cambia.

---

## Tarea 22. Comprobar la idempotencia por archivo

Intenta cargar nuevamente un archivo ya procesado sin cambiar su nombre.

Analiza:

- Qué registra Snowpipe como historial de carga.
- Por qué se recomiendan nombres de archivo únicos e inmutables.
- Qué riesgos existen al sobrescribir objetos con el mismo nombre.
- En qué casos sería necesario recrear un pipe.

No utilices esta prueba sobre datos que deban conservarse como resultado definitivo.

---

## Tarea 23. Recuperar un archivo no notificado

Analiza el caso de un archivo que se subió antes de crear la notificación S3.

Utiliza el mecanismo de recuperación de Snowpipe para incorporar archivos recientes que no generaron una notificación válida.

Explica:

- Para qué sirve `ALTER PIPE ... REFRESH`.
- Por qué no debe utilizarse como mecanismo habitual.
- Qué límite temporal tiene.
- Cómo evita cargar archivos que ya figuran en el historial.

---

## Tarea 24. Auditar y limpiar

Al finalizar:

1. Suspende ambas tasks.
2. Suspende el pipe.
3. Comprueba los estados.
4. Elimina la notificación S3 si vas a destruir el entorno.
5. Elimina los objetos Snowflake.
6. Vacía y elimina tu bucket.
7. Elimina tu rol IAM.
8. Elimina tu política IAM.
9. No elimines recursos de otros participantes.

---

## Validaciones finales

### STAGING

```text
12 eventos
3 archivos de negocio
metadatos de archivo presentes
sin duplicación accidental de archivos
```

### CURATED

```text
7 pedidos
una fila por id_pedido
5 COMPLETADA
2 CANCELADA
0 PENDIENTE
importe completado total = 1270.00
```

### MART

| FECHA_PEDIDO | PEDIDOS_TOTAL | COMPLETADOS | CANCELADOS | PENDIENTES | UNIDADES | IMPORTE |
|---|---:|---:|---:|---:|---:|---:|
| 2026-07-01 | 3 | 1 | 2 | 0 | 2 | 60.00 |
| 2026-07-02 | 3 | 3 | 0 | 0 | 5 | 310.00 |
| 2026-07-03 | 1 | 1 | 0 | 0 | 1 | 900.00 |

---

## Preguntas de reflexión

1. ¿Qué diferencia existe entre un stage externo y Snowpipe?
2. ¿Qué función cumple la notificación S3?
3. ¿Contiene la notificación los datos del archivo?
4. ¿Quién administra la cola SQS utilizada en este ejercicio?
5. ¿Por qué Snowpipe no necesita un warehouse creado por el usuario?
6. ¿Qué componente utiliza `WH_DEV`?
7. ¿Por qué se carga primero en una tabla RAW de texto?
8. ¿Por qué el stream debe existir antes de cargar el primer archivo?
9. ¿Qué ocurre si el archivo llega antes de configurar la notificación?
10. ¿Qué diferencia existe entre una política de confianza y una política de permisos?
11. ¿Por qué la task RAW → CURATED debe deduplicar el microbatch?
12. ¿Por qué no basta con comparar únicamente `event_id`?
13. ¿Cómo se evita que una versión antigua sobrescriba una reciente?
14. ¿Por qué MART se recalcula para las fechas afectadas?
15. ¿Qué sucede en el segundo stream cuando CURATED recibe un `UPDATE`?
16. ¿Por qué el evento tardío no provoca cambios en MART?
17. ¿Por qué se recomiendan nombres de archivo únicos?
18. ¿Qué información aporta `COPY_HISTORY`?
19. ¿Qué información aporta `SYSTEM$PIPE_STATUS`?
20. ¿Qué controles añadirías en producción para detectar archivos fallidos?
21. ¿Cómo separarías permisos AWS entre varios alumnos en una cuenta compartida?
22. ¿Qué diferencias habría entre este diseño y Snowpipe Streaming?
23. ¿Cuándo utilizarías SNS o EventBridge en lugar de una notificación directa S3 → SQS?
24. ¿Qué costes generan Snowpipe y las triggered tasks?
25. ¿Qué objetos deberías monitorizar para garantizar el procesamiento extremo a extremo?

---

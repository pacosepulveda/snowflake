# Módulo 7 · Ejercicio 3
## Pipeline híbrido: Snowpipe, Stream, triggered Task y Dynamic Table

### Contexto

RetailNova recibe continuamente ficheros CSV con eventos de pedidos. Cada fichero puede contener pedidos nuevos y nuevas versiones de pedidos existentes.

La empresa necesita un pipeline con responsabilidades separadas:

1. **Snowpipe** introduce los ficheros en una tabla RAW.
2. Un **stream** detecta las filas nuevas.
3. Una **triggered task** deduplica el microbatch y mantiene el estado actual de cada pedido mediante `MERGE`.
4. Una **Dynamic Table** mantiene un agregado declarativo para el dashboard.

El diseño será:

```text
Ficheros CSV
    ↓
STG_PEDIDOS_HIBRIDO
    ↓
PIPE_PEDIDOS_RAW
    ↓
STAGING.PEDIDOS_PIPE_RAW
    ↓
STR_PEDIDOS_PIPE_RAW
    ↓
TASK_MERGE_PEDIDOS_HIBRIDO
    ↓
CURATED.PEDIDOS_ACTUALES_HIBRIDO
    ↓
MARTS.DT_PEDIDOS_DIA_REGION
```

Cada mecanismo se utiliza para la responsabilidad para la que está mejor preparado.

---

## Particularidad del laboratorio

En producción, Snowpipe recibe normalmente los nombres de los nuevos ficheros mediante:

- Notificaciones del proveedor cloud con `AUTO_INGEST = TRUE`.
- La API REST de Snowpipe con `AUTO_INGEST = FALSE`.

Cada alumno solo dispone de su cuenta trial de Snowflake y no necesariamente de un bucket o de una identidad cloud adicional.

Por ello:

- Se creará un pipe real con `AUTO_INGEST = FALSE`.
- Los ficheros se subirán a un named internal stage.
- Se utilizará `ALTER PIPE … REFRESH` para introducir los ficheros recientes en la cola.

`REFRESH` se utiliza aquí únicamente como mecanismo didáctico y de recuperación. No debe convertirse en la estrategia normal de activación de Snowpipe en producción.

---

## Objetivos

Al finalizar el ejercicio deberás ser capaz de:

1. Crear un pipe real sobre un named internal stage.
2. Diferenciar `AUTO_INGEST = FALSE` de `AUTO_INGEST = TRUE`.
3. Subir varios microbatches a un stage.
4. Introducir ficheros recientes en la cola con `ALTER PIPE … REFRESH`.
5. Inspeccionar el estado del pipe con `SYSTEM$PIPE_STATUS`.
6. Auditar las cargas mediante `COPY_HISTORY`.
7. Utilizar un append-only stream sobre la tabla RAW.
8. Procesar los cambios mediante una triggered task.
9. Deduplicar versiones dentro de cada microbatch.
10. Mantener una tabla CURATED con `MERGE`.
11. Mantener un agregado mediante una Dynamic Table.
12. Comprobar la idempotencia del historial de ficheros.
13. Diferenciar cómputo Snowpipe, warehouse de task y warehouse de Dynamic Table.
14. Diseñar la variante de producción para AWS, Azure y GCP.
15. Seleccionar correctamente entre `COPY INTO`, Snowpipe, Streams + Tasks y Dynamic Tables.

---

## Recursos proporcionados

### Primer microbatch

```text
Snowflake_Modulo7_Ejercicio3_pedidos_batch01.csv
```

Contiene cinco eventos y cuatro pedidos.

### Segundo microbatch

```text
Snowflake_Modulo7_Ejercicio3_pedidos_batch02.csv
```

Contiene seis eventos:

- Dos actualizaciones.
- Dos versiones del pedido nuevo `9105`.
- Dos pedidos nuevos adicionales.

No modifiques los ficheros.

---

## Convenciones

| Objeto | Nombre |
|---|---|
| Base de datos | `DB_CURSO` |
| Esquema técnico | `STAGING` |
| Esquema limpio | `CURATED` |
| Esquema analítico | `MARTS` |
| Warehouse | `WH_DEV` |
| File format | `FF_PEDIDOS_HIBRIDO_CSV` |
| Stage | `STG_PEDIDOS_HIBRIDO` |
| Tabla RAW | `PEDIDOS_PIPE_RAW` |
| Pipe | `PIPE_PEDIDOS_RAW` |
| Stream | `STR_PEDIDOS_PIPE_RAW` |
| Tabla CURATED | `PEDIDOS_ACTUALES_HIBRIDO` |
| Task | `TASK_MERGE_PEDIDOS_HIBRIDO` |
| Dynamic Table | `DT_PEDIDOS_DIA_REGION` |
| Fichero SQL del workspace | `M07_E03_PIPELINE_HIBRIDO.sql` |

---

## Reglas de versionado

La clave de negocio es:

```text
id_pedido
```

La versión ganadora es la primera según:

1. `fecha_modificacion` descendente.
2. `event_id` descendente.

Una versión solo actualiza el destino cuando es posterior a la versión almacenada.

---

## Tareas

### Tarea 1. Preparar Workspaces y los privilegios

En **Workspaces**, crea:

```text
M07_E03_PIPELINE_HIBRIDO.sql
```

Configura:

- Rol.
- Warehouse `XSMALL`.
- Auto-suspend de 60 segundos.
- Base de datos y esquemas.
- `QUERY_TAG`.

Concede a `SYSADMIN` el privilegio global `EXECUTE TASK` usando temporalmente `ACCOUNTADMIN`.

---

### Tarea 2. Crear el stage, el formato y RAW

Crea un file format CSV con:

- Separador `;`.
- Una línea de cabecera.
- Fechas `YYYY-MM-DD`.
- Timestamps `YYYY-MM-DD HH24:MI:SS`.
- UTF-8.
- Validación del número de columnas.

Crea un named internal stage cifrado por Snowflake.

Crea la tabla transitoria:

```text
DB_CURSO.STAGING.PEDIDOS_PIPE_RAW
```

con las nueve columnas del CSV y tipos correctos.

---

### Tarea 3. Crear e inspeccionar el pipe

Crea:

```text
DB_CURSO.STAGING.PIPE_PEDIDOS_RAW
```

con:

```text
AUTO_INGEST = FALSE
```

El `COPY INTO` del pipe debe:

- Leer el named stage.
- Utilizar el file format.
- Admitir los dos nombres de fichero proporcionados.
- Abortar el fichero ante un error.
- No purgar los ficheros.

Inspecciona:

- `SHOW PIPES`.
- `DESC PIPE`.
- La vista `INFORMATION_SCHEMA.PIPES`.
- `SYSTEM$PIPE_STATUS`.

Explica por qué `AUTO_INGEST = FALSE` no observa por sí mismo el stage.

---

### Tarea 4. Crear stream, destino y task

Crea:

```text
STR_PEDIDOS_PIPE_RAW
```

como append-only stream sobre RAW.

Crea:

```text
CURATED.PEDIDOS_ACTUALES_HIBRIDO
```

con una fila por pedido.

Crea una triggered task que:

- Use `WH_DEV`.
- Se active mediante `SYSTEM$STREAM_HAS_DATA`.
- Deduzca una versión ganadora por `id_pedido`.
- Haga `MERGE`.
- Inserte pedidos nuevos.
- Actualice versiones posteriores.
- Ignore versiones antiguas.
- Actualice `_processed_at`.

Reanuda la task.

---

### Tarea 5. Crear la Dynamic Table

Activa `CHANGE_TRACKING` en la tabla CURATED.

Crea:

```text
MARTS.DT_PEDIDOS_DIA_REGION
```

con:

- `TARGET_LAG = '1 minute'`.
- `SCHEDULER = ENABLE`.
- `WAREHOUSE = WH_DEV`.
- `REFRESH_MODE = INCREMENTAL`.
- `INITIALIZE = ON_CREATE`.

Debe incluir únicamente pedidos `COMPLETADA` y agrupar por:

```text
fecha_pedido + region + canal
```

Métricas:

- Número de pedidos.
- Importe total.
- Ticket medio.
- Última modificación del grupo.

Inicialmente estará vacía.

---

### Tarea 6. Subir el primer microbatch

Utiliza:

```text
Ingestion → Add Data → Load files into a Stage
```

para subir solo:

```text
Snowflake_Modulo7_Ejercicio3_pedidos_batch01.csv
```

al stage.

Comprueba que:

- El fichero aparece con `LIST`.
- RAW sigue vacía.
- El stream sigue vacío.
- El pipe no lo carga automáticamente.

Explica el motivo.

---

### Tarea 7. Encolar el primer fichero

Ejecuta:

```text
ALTER PIPE … REFRESH
```

Consulta `SYSTEM$PIPE_STATUS` hasta que no haya ficheros pendientes.

Comprueba:

```text
5 filas en RAW
```

Después espera a que la triggered task procese el stream.

Resultado esperado en CURATED:

```text
4 pedidos
3 pedidos COMPLETADA
1 pedido CANCELADA
```

El pedido `9101` debe conservar su versión `COMPLETADA`.

---

### Tarea 8. Refrescar y validar el agregado

Espera al refresco programado de la Dynamic Table o solicita un refresco manual si necesitas continuar sin esperar.

Resultado inicial:

```text
3 filas agregadas
3 pedidos completados
importe completado = 380.00
```

Comprueba que el stream está vacío y que la task se ejecutó con origen `TRIGGER`.

---

### Tarea 9. Auditar el primer microbatch

Consulta:

- `COPY_HISTORY` filtrado por pipe.
- `SYSTEM$PIPE_STATUS`.
- `TASK_HISTORY`.
- `DYNAMIC_TABLE_REFRESH_HISTORY`.
- `VALIDATE_PIPE_LOAD`.

`VALIDATE_PIPE_LOAD` no debe devolver filas si el fichero se procesó sin errores.

Identifica qué parte del pipeline utilizó:

- Cómputo serverless de Snowpipe.
- `WH_DEV` para la task.
- `WH_DEV` para el refresco de la Dynamic Table.

---

### Tarea 10. Subir y procesar el segundo microbatch

Sube:

```text
Snowflake_Modulo7_Ejercicio3_pedidos_batch02.csv
```

Comprueba que el stage contiene los dos ficheros.

Ejecuta de nuevo:

```text
ALTER PIPE … REFRESH
```

Snowflake debe encolar solo el fichero todavía no procesado.

Espera a que:

1. Snowpipe inserte seis filas nuevas en RAW.
2. El stream detecte los cambios.
3. La task actualice CURATED.
4. La Dynamic Table se refresque.

---

### Tarea 11. Validar el resultado final

Comprueba:

```text
11 filas en RAW
7 pedidos en CURATED
5 pedidos COMPLETADA
2 pedidos CANCELADA
importe completado = 530.00
4 filas agregadas
```

Valida específicamente:

- `9102` queda `CANCELADA` y `220.00`.
- `9103` queda `COMPLETADA` y `90.00`.
- `9105` aparece una sola vez con `125.00`.
- `9106` queda `COMPLETADA` y `140.00`.
- `9107` queda `COMPLETADA` y `75.00`.
- El agregado `SUR + WEB` contiene dos pedidos y `200.00`.

---

### Tarea 12. Probar la protección de historial

Sin añadir ficheros, ejecuta otra vez:

```text
ALTER PIPE … REFRESH
```

Comprueba que:

- RAW sigue teniendo 11 filas.
- CURATED sigue teniendo 7 pedidos.
- No aparecen eventos duplicados.
- El historial del pipe evita volver a cargar los mismos ficheros.

Explica por qué recrear el pipe puede ser peligroso para esta protección.

---

### Tarea 13. Diseñar la versión de producción

Describe el diseño para:

#### AWS

- Stage externo S3.
- Storage integration.
- `AUTO_INGEST = TRUE`.
- SQS gestionada por Snowflake o SNS según el patrón.
- Event notification del bucket.

#### Azure

- Stage en Blob o ADLS.
- Storage integration.
- Notification integration.
- Event Grid.
- `AUTO_INGEST = TRUE`.

#### GCP

- Stage en GCS.
- Storage integration.
- Notification integration.
- Pub/Sub.
- `AUTO_INGEST = TRUE`.

Explica también cuándo sería preferible mantener:

```text
AUTO_INGEST = FALSE + API REST
```

---

### Tarea 14. Seleccionar mecanismos

Completa esta tabla justificando la elección:

| Escenario | Mecanismo |
|---|---|
| Fichero nocturno de 20 GB |  |
| Miles de ficheros pequeños durante el día |  |
| Propagar cambios con reglas y MERGE |  |
| Mantener un agregado SQL fresco |  |
| Carga histórica inicial |  |
| Integración que decide explícitamente qué ficheros enviar |  |

---

### Tarea 15. Detener el pipeline

Al finalizar:

1. Suspende la task.
2. Suspende la Dynamic Table.
3. Pausa el pipe.
4. Suspende el warehouse.

Comprueba los estados.

Explica qué datos siguen siendo consultables y qué procesamiento queda detenido.

---

## Preguntas de reflexión

1. ¿Por qué no se utiliza una única task para hacer todo?
2. ¿Qué ventaja aporta mantener RAW como un log append-only?
3. ¿Qué historial evita que Snowpipe vuelva a cargar un fichero?
4. ¿Qué ocurre con ese historial al recrear el pipe?
5. ¿Por qué `ALTER PIPE … REFRESH` no debe utilizarse como sondeo periódico?
6. ¿Qué parte del pipeline es declarativa y cuál es procedural?
7. ¿Qué componente usarías para un backfill histórico?
8. ¿Qué componente usarías si el productor necesita confirmar qué ficheros ha enviado?
9. ¿Dónde se consumen créditos de warehouse y dónde cómputo serverless?
10. ¿Qué alertas configurarías en producción?

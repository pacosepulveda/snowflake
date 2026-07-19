# Módulo 3 · Ejercicio 3

# Observabilidad de la plataforma: del diagnóstico inmediato al análisis histórico

## Contexto

Formas parte del equipo responsable de una plataforma de datos basada en Snowflake. Durante una revisión operativa, el responsable del servicio plantea varias preguntas:

- ¿Qué consultas acaba de ejecutar un usuario y cuál ha fallado?
- ¿Cuánto tiempo se ha dedicado a compilar y cuánto a ejecutar cada consulta?
- ¿Qué consultas han leído datos y cuáles se han resuelto sin utilizar realmente el warehouse?
- ¿Podemos identificar consultas servidas desde caché?
- ¿Cuántos créditos han consumido los warehouses?
- ¿Por qué unas fuentes de monitorización muestran información casi inmediatamente y otras tardan en actualizarse?

Tu objetivo será generar una pequeña carga de trabajo controlada y construir dos vistas de observabilidad:

1. **Diagnóstico inmediato**, utilizando las funciones de `INFORMATION_SCHEMA`.
2. **Análisis histórico y de consumo**, utilizando las vistas de `SNOWFLAKE.ACCOUNT_USAGE`.

Al terminar deberás relacionar las métricas observadas con las capas de **Cloud Services**, **Compute** y **Storage** de Snowflake.

---

## Objetivos

Al completar el ejercicio serás capaz de:

- Etiquetar una carga de trabajo mediante `QUERY_TAG`.
- Consultar el historial reciente de la sesión.
- Diferenciar tiempo de compilación, ejecución, colas y bloqueo transaccional.
- Identificar consultas correctas y consultas fallidas.
- Reconocer indicios de reutilización del result cache.
- Comparar `INFORMATION_SCHEMA` con `SNOWFLAKE.ACCOUNT_USAGE`.
- Consultar el consumo horario de créditos de los warehouses.
- Explicar la latencia de las distintas fuentes de observabilidad.
- Asociar cada métrica con la capa arquitectónica que la genera.

---

## Requisitos

- Una cuenta trial de Snowflake en edición Enterprise.
- Acceso a Snowsight.
- Los roles `SYSADMIN` y `ACCOUNTADMIN` disponibles en la cuenta individual del laboratorio.
- Haber completado preferentemente los ejercicios anteriores del módulo.
- Disponer de la tabla:

```text
DB_CURSO.ARQUITECTURA.VENTAS_ARQ
```

La solución incluye un bloque alternativo para crearla cuando el ejercicio se ejecute de forma independiente.

---

## Escenario de trabajo

La tabla `VENTAS_ARQ` contiene ventas sintéticas. Vas a ejecutar sobre ella:

- Una operación de metadatos.
- Una consulta de agregación completa.
- La misma consulta una segunda vez para estudiar la caché.
- Una consulta con filtro por fecha.
- Una consulta incorrecta que deberá quedar registrada como error.

Todas las operaciones deberán quedar identificadas con el siguiente tag:

```text
M3_E3_OBSERVABILIDAD
```

---

# Tareas

## Tarea 1. Preparar el contexto de la sesión

Crea o reutiliza un warehouse denominado `WH_M3_OBS` con las siguientes características:

- Tamaño `XSMALL`.
- Suspensión automática tras 60 segundos de inactividad.
- Reanudación automática.
- Estado inicial suspendido.

Establece después el contexto de trabajo:

- Rol: `SYSADMIN`.
- Warehouse: `WH_M3_OBS`.
- Base de datos: `DB_CURSO`.
- Esquema: `ARQUITECTURA`.

Activa el uso de resultados persistidos y asigna a la sesión el `QUERY_TAG` indicado.

### Comprobación

Obtén mediante una consulta:

- Rol activo.
- Warehouse activo.
- Base de datos activa.
- Esquema activo.
- Identificador de la sesión.

---

## Tarea 2. Generar una carga de trabajo controlada

Ejecuta las siguientes operaciones en este orden.

### 2.1. Operación de metadatos

Muestra la definición o la existencia de la tabla `VENTAS_ARQ` sin consultar sus filas.

### 2.2. Consulta de agregación

Calcula:

- Número total de ventas.
- Importe total.
- Importe medio.

Incluye en el texto SQL el comentario:

```sql
/* M3_E3_CACHE_TEST */
```

### 2.3. Repetición exacta

Ejecuta una segunda vez **exactamente el mismo texto SQL** de la consulta anterior.

No cambies:

- Mayúsculas o minúsculas.
- Espacios.
- Comentarios.
- Alias.
- Orden de las expresiones.

El objetivo es que Snowflake pueda reutilizar el resultado persistido de la primera ejecución.

### 2.4. Consulta con filtro

Obtén las ventas mensuales de un intervalo reducido de fechas. Incluye el comentario:

```sql
/* M3_E3_PRUNING */
```

La consulta deberá devolver, por mes:

- Mes de la venta.
- Número de ventas.
- Importe total.

### 2.5. Consulta incorrecta

Ejecuta deliberadamente una consulta que solicite una columna inexistente de `VENTAS_ARQ`.

Incluye el comentario:

```sql
/* M3_E3_ERROR */
```

La consulta debe fallar. No corrijas el error hasta haber anotado el mensaje devuelto por Snowflake.

### 2.6. Finalizar el etiquetado

Elimina el `QUERY_TAG` de la sesión para que las consultas de análisis posteriores no se mezclen con la carga de trabajo estudiada.

---

## Tarea 3. Construir el informe de diagnóstico inmediato

Utiliza la función:

```text
DB_CURSO.INFORMATION_SCHEMA.QUERY_HISTORY_BY_SESSION
```

Recupera las consultas recientes de la sesión y filtra exclusivamente aquellas cuyo `QUERY_TAG` sea:

```text
M3_E3_OBSERVABILIDAD
```

El informe debe incluir al menos:

- `QUERY_ID`.
- `QUERY_TYPE`.
- `EXECUTION_STATUS`.
- `WAREHOUSE_NAME`.
- `WAREHOUSE_SIZE`.
- `TOTAL_ELAPSED_TIME`.
- `COMPILATION_TIME`.
- `EXECUTION_TIME`.
- `QUEUED_PROVISIONING_TIME`.
- `QUEUED_OVERLOAD_TIME`.
- `TRANSACTION_BLOCKED_TIME`.
- `BYTES_SCANNED`.
- `ROWS_PRODUCED`.
- `ERROR_MESSAGE`.
- `QUERY_TEXT`.

Ordena los resultados cronológicamente.

### Análisis requerido

Responde en tus notas:

1. ¿Qué consulta muestra un error?
2. ¿Qué diferencia observas entre la primera y la segunda ejecución de `M3_E3_CACHE_TEST`?
3. ¿Qué sentencia parece depender principalmente de Cloud Services?
4. ¿Qué consulta ha necesitado leer datos almacenados?
5. ¿Ha existido tiempo de cola, sobrecarga o bloqueo transaccional?
6. ¿Qué diferencia existe entre `TOTAL_ELAPSED_TIME`, `COMPILATION_TIME` y `EXECUTION_TIME`?

---

## Tarea 4. Revisar Query History y Query Profile en Snowsight

Abre la página **Query History** de Snowsight y localiza las consultas mediante el tag:

```text
M3_E3_OBSERVABILIDAD
```

Abre el Query Profile de:

- La primera consulta `M3_E3_CACHE_TEST`.
- La consulta `M3_E3_PRUNING`.

Anota, cuando estén disponibles:

- Bytes escaneados.
- Particiones escaneadas.
- Particiones totales.
- Porcentaje de datos leídos desde caché local.
- Operadores principales del plan.
- Tiempo de compilación y tiempo de ejecución.

No todos los perfiles mostrarán exactamente los mismos valores, ya que dependen de la organización física de los datos y del estado de las cachés.

---

## Tarea 5. Comparar con el histórico de ACCOUNT_USAGE

Cambia temporalmente al rol `ACCOUNTADMIN` y consulta:

```text
SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
```

Busca las consultas etiquetadas con `M3_E3_OBSERVABILIDAD` durante el último día.

El informe histórico deberá incluir, cuando las filas ya estén disponibles:

- Identificador y texto de la consulta.
- Estado de ejecución.
- Warehouse utilizado.
- Bytes escaneados.
- Porcentaje leído desde la caché local.
- Particiones escaneadas y totales.
- Tiempo de compilación.
- Tiempo de ejecución.
- Tiempo de cola.
- Tiempo bloqueado por transacciones.
- Créditos de Cloud Services atribuidos a la consulta.

### Análisis requerido

1. ¿Aparecen inmediatamente las consultas que acabas de ejecutar?
2. ¿Qué explicación tiene que todavía no aparezcan?
3. ¿Qué ventajas ofrece `ACCOUNT_USAGE.QUERY_HISTORY` frente a la función de `INFORMATION_SCHEMA`?
4. ¿Para qué caso usarías cada una de las dos fuentes?

> La ausencia temporal de las filas recién generadas no representa un error del ejercicio. Forma parte del comportamiento que se pretende observar.

---

## Tarea 6. Analizar el consumo de los warehouses

Consulta:

```text
SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
```

Obtén el consumo de los warehouses durante los dos últimos días, agrupado por hora y warehouse.

Calcula:

- Créditos de cómputo consumidos.
- Créditos atribuidos a consultas.
- Diferencia aproximada entre ambos valores como indicio de tiempo de warehouse encendido sin ejecutar consultas.

### Preguntas

1. ¿Aparece ya el consumo del warehouse utilizado en este ejercicio?
2. ¿Por qué puede tardar más en aparecer que el historial de consultas?
3. ¿Qué efecto tienen `AUTO_SUSPEND` y `AUTO_RESUME` sobre el consumo observado?
4. ¿Por qué la diferencia calculada debe interpretarse como una aproximación operativa y no como una factura definitiva?

---

## Tarea 7. Elaborar un diagnóstico de arquitectura

Redacta una conclusión breve, de entre 8 y 12 líneas, que responda a estas cuestiones:

- ¿Qué trabajo realiza Cloud Services antes de que intervenga el warehouse?
- ¿Qué métricas demuestran que una consulta ha utilizado Compute?
- ¿Qué métricas indican acceso a Storage?
- ¿Cómo reduce el result cache el consumo?
- ¿Por qué `INFORMATION_SCHEMA` es más apropiado para una investigación inmediata?
- ¿Por qué `ACCOUNT_USAGE` resulta más adecuado para auditoría, tendencias y FinOps?


---

## Restricción de seguridad

El rol `ACCOUNTADMIN` se utilizará únicamente durante las consultas administrativas de `ACCOUNT_USAGE`. Al terminar, vuelve a `SYSADMIN`.

En un entorno real se crearían roles de observabilidad con privilegios mínimos y se les concederían los database roles apropiados de la base compartida `SNOWFLAKE`.

# Módulo 3 - Ejercicio 2

## Cachés y concurrencia: acelerar lecturas sin perder consistencia

**Modalidad:** individual, con una fase coordinada entre dos sesiones  
**Herramientas:** Snowsight y SQL  
**Cuenta:** Snowflake Trial, edición Enterprise

---

## Contexto

El equipo de datos de **Northwind Retail** ha comprobado que Snowflake separa el almacenamiento del cómputo y que distintos virtual warehouses pueden consultar las mismas tablas.

Ahora han aparecido dos preguntas nuevas.

La primera procede del equipo de FinOps:

> «Algunas consultas repetidas responden casi instantáneamente. ¿Se están ejecutando realmente o Snowflake está reutilizando información almacenada? ¿Qué ocurre con esas cachés cuando suspendemos un warehouse?»

La segunda procede del equipo de operaciones:

> «Mientras Finanzas está actualizando el inventario, los analistas deben poder seguir consultándolo. Sin embargo, no queremos que vean cambios sin confirmar ni que dos procesos modifiquen simultáneamente el mismo dato sin control.»

Tu misión consiste en preparar un laboratorio que permita diferenciar dos mecanismos de caché y observar el comportamiento transaccional de Snowflake:

```text
RESULT CACHE
Resultado final persistido en Cloud Services
Puede evitar por completo la nueva ejecución de una consulta

WAREHOUSE CACHE
Datos de tabla almacenados temporalmente en el SSD local del warehouse
La consulta sí se ejecuta, pero puede leer menos desde almacenamiento remoto

CONCURRENCIA TRANSACCIONAL
Las lecturas solo ven datos confirmados
Lectores y escritores pueden trabajar simultáneamente
Los escritores que compiten por el mismo recurso pueden bloquearse
```

El ejercicio no busca obtener tiempos idénticos en todas las cuentas. Debes recopilar evidencias, interpretarlas y explicar por qué los resultados pueden variar.

---

## Objetivos de aprendizaje

Al completar el ejercicio deberás ser capaz de:

1. Diferenciar el result cache de la caché local de un virtual warehouse.
2. Controlar la reutilización de resultados mediante `USE_CACHED_RESULT`.
3. Demostrar que una consulta idéntica puede reutilizar un resultado persistido.
4. Comprobar que un cambio DML invalida el resultado almacenado asociado a una tabla.
5. Ejecutar pruebas de caché local sin que el result cache falsee la comparación.
6. Explicar por qué suspender un warehouse elimina su caché local, pero no los datos persistentes.
7. Utilizar Query History y Query Profile para analizar las ejecuciones.
8. Crear y controlar transacciones explícitas con `BEGIN TRANSACTION`, `COMMIT` y `ROLLBACK`.
9. Comprobar que una sesión no puede leer cambios no confirmados de otra sesión.
10. Observar el aislamiento `READ COMMITTED` mediante dos consultas sucesivas.
11. Demostrar que una lectura puede continuar mientras otra sesión mantiene una actualización sin confirmar.
12. Provocar de forma controlada un conflicto entre dos escritores.
13. Limitar la espera por bloqueos mediante `LOCK_TIMEOUT`.
14. Consultar el tiempo bloqueado y el error de una operación desde Query History.
15. Restaurar los parámetros de sesión y suspender el warehouse al finalizar.

---

## Prerrequisitos

Debes haber completado el ejercicio 1 del módulo 3 y disponer de:

```text
DB_CURSO.ARQUITECTURA.VENTAS_ARQ
WH_M3_ANALITICA
```

La tabla `VENTAS_ARQ` debe contener aproximadamente 5.000.000 de filas.

Este ejercicio creará temporalmente:

```text
DB_CURSO.ARQUITECTURA.M3_CACHE_VENTAS
DB_CURSO.ARQUITECTURA.M3_INVENTARIO_MVCC
```

Utiliza un usuario que pueda trabajar con el rol `SYSADMIN` y tenga permisos para:

- Usar y modificar `WH_M3_ANALITICA`.
- Crear y eliminar tablas en `DB_CURSO.ARQUITECTURA`.
- Consultar su propio historial de consultas.

---

# Parte A - Result cache y caché local del warehouse

## 1. Crear el SQL File principal

Crea un SQL File llamado:

`M3_E2_CACHE_Y_CONCURRENCIA_A`

Mantén toda la Parte A en el mismo SQL File y sesión para poder conservar Query ID en variables de sesión.

## 2. Establecer y comprobar el contexto

Configura explícitamente:

- Rol `SYSADMIN`.
- Warehouse `WH_M3_ANALITICA`.
- Base de datos `DB_CURSO`.
- Esquema `ARQUITECTURA`.

Comprueba:

- Usuario actual.
- Rol actual.
- Warehouse actual.
- Base de datos y esquema.
- Versión de Snowflake.
- Identificador de sesión.

## 3. Preparar una tabla de laboratorio

Crea una tabla transitoria llamada:

`DB_CURSO.ARQUITECTURA.M3_CACHE_VENTAS`

Debe contener una copia de las filas de `VENTAS_ARQ`.

Utilizamos una tabla independiente para poder ejecutar cambios DML sin alterar el conjunto de datos original del ejercicio anterior.

Comprueba:

- Número de filas.
- Fecha mínima y máxima.
- Tamaño aproximado de la tabla mediante la información disponible en Snowsight o `SHOW TABLES`.

## 4. Preparar una consulta de prueba para el result cache

Diseña una consulta determinista que:

- Lea `M3_CACHE_VENTAS`.
- Filtre un intervalo fijo de fechas.
- Agrupe por región.
- Devuelva número de ventas, unidades e importe.
- Incluya una columna literal que identifique el laboratorio.
- Ordene el resultado.

No utilices en esta consulta:

- `CURRENT_TIMESTAMP()`.
- `RANDOM()`.
- `UUID_STRING()`.
- Otras funciones cuyo resultado pueda cambiar entre ejecuciones.

La consulta deberá ejecutarse varias veces con un texto **exactamente idéntico**.

## 5. Generar una ejecución real

Realiza las siguientes acciones:

1. Desactiva temporalmente la reutilización de resultados almacenados.
2. Configura el query tag `M3_E2_RESULT_CACHE`.
3. Ejecuta la consulta de prueba.
4. Conserva su Query ID en una variable de sesión.

Esta primera ejecución deberá calcular el resultado en lugar de reutilizar uno anterior.

## 6. Reutilizar el resultado persistido

A continuación:

1. Activa de nuevo la reutilización de resultados.
2. Ejecuta **exactamente la misma consulta**, sin cambiar espacios, mayúsculas, alias ni comentarios.
3. Conserva el segundo Query ID.
4. Comprueba que el resultado funcional es idéntico.

Desde Query History y Query Profile, recopila evidencias que permitan decidir si la segunda consulta reutilizó el resultado de la primera.

Como mínimo, compara:

- `TOTAL_ELAPSED_TIME`.
- `COMPILATION_TIME`.
- `EXECUTION_TIME`.
- `BYTES_SCANNED`.
- Warehouse asociado.
- Representación del plan o mensaje mostrado en Query Profile.

## 7. Invalidar el result cache mediante DML

Modifica en `M3_CACHE_VENTAS` una fila que participe en el intervalo de fechas de la consulta.

La modificación debe cambiar el importe en una cantidad pequeña y controlada.

Después:

1. Mantén activada la reutilización de resultados.
2. Ejecuta otra vez la misma consulta, con texto idéntico.
3. Conserva el tercer Query ID.
4. Comprueba si el importe agregado refleja el cambio.
5. Analiza si Snowflake pudo seguir reutilizando el resultado anterior.

Explica por qué un resultado almacenado no debe entregarse si los datos que lo originaron han cambiado.

## 8. Preparar una prueba de caché local

Para evitar confundir la caché del warehouse con el result cache:

1. Desactiva `USE_CACHED_RESULT`.
2. Suspende explícitamente `WH_M3_ANALITICA` para vaciar su caché local.
3. Confirma su estado.
4. Vuelve a seleccionar el warehouse; deja que la siguiente consulta provoque el auto-resume.

## 9. Ejecutar una consulta con la caché local fría

Ejecuta una agregación sobre toda `M3_CACHE_VENTAS` agrupada por región y canal.

La consulta deberá:

- Leer varias columnas.
- Recorrer todo el periodo de la tabla.
- Devolver un resultado pequeño.
- Evitar `SELECT *`.

Configura el query tag `M3_E2_WAREHOUSE_CACHE` y conserva el Query ID de esta primera ejecución.

## 10. Repetir con el warehouse activo

Sin suspender ni redimensionar el warehouse:

1. Ejecuta exactamente la misma consulta.
2. Conserva el segundo Query ID.
3. Compara la ejecución con la anterior.

Utiliza Query Profile para localizar, cuando la interfaz lo muestre:

- Bytes escaneados.
- Porcentaje leído desde caché.
- Tiempo de ejecución.
- Operadores principales.

No des por hecho que el porcentaje será exactamente el 100 %.

## 11. Suspender, reanudar y repetir

Ahora:

1. Suspende explícitamente `WH_M3_ANALITICA`.
2. Confirma que está suspendido.
3. Ejecuta nuevamente la misma consulta y deja que `AUTO_RESUME` reactive el warehouse.
4. Conserva el tercer Query ID.
5. Compara las tres ejecuciones.

Debes explicar:

- Qué caché se pierde al suspender el warehouse.
- Qué información permanece disponible.
- Por qué la primera consulta después del resume puede ser más lenta.
- Por qué los resultados exactos pueden variar aunque el principio arquitectónico sea el mismo.

---

# Parte B - Concurrencia transaccional y aislamiento

## 12. Preparar la tabla de inventario

Desde el SQL File principal crea:

`DB_CURSO.ARQUITECTURA.M3_INVENTARIO_MVCC`

La tabla debe contener al menos tres productos con estas columnas:

- `ID_PRODUCTO`.
- `PRODUCTO`.
- `STOCK`.
- `ACTUALIZADO_EN`.

El producto con `ID_PRODUCTO = 1` debe comenzar con un stock conocido, por ejemplo, 100 unidades.

Comprueba los datos iniciales antes de continuar.

## 13. Abrir dos sesiones independientes

Abre un segundo SQL File llamado:

`M3_E2_CACHE_Y_CONCURRENCIA_B`

Debes mantener abiertas simultáneamente:

```text
Sesión A: M3_E2_CACHE_Y_CONCURRENCIA_A
Sesión B: M3_E2_CACHE_Y_CONCURRENCIA_B
```

En ambas sesiones configura el mismo contexto:

```text
SYSADMIN
WH_M3_ANALITICA
DB_CURSO.ARQUITECTURA
```

Desactiva el result cache en ambas sesiones para que las lecturas del laboratorio no se respondan con un resultado persistido.

Comprueba que los dos SQL Files tienen identificadores de sesión distintos.

## 14. Dejar un cambio sin confirmar en la sesión A

En la sesión A:

1. Inicia una transacción explícita.
2. Reduce en 10 unidades el stock del producto 1.
3. Actualiza su marca de tiempo.
4. Consulta el producto desde la propia sesión A.
5. No ejecutes todavía `COMMIT` ni `ROLLBACK`.

La sesión A debe ver su propio cambio pendiente.

## 15. Leer desde la sesión B

Mientras la transacción de A continúa abierta, en la sesión B:

1. Inicia otra transacción explícita.
2. Consulta el producto 1.
3. Registra el valor observado y el tiempo de respuesta.

Responde:

- ¿La lectura quedó bloqueada por el `UPDATE` de A?
- ¿La sesión B vio el valor modificado pero no confirmado?
- ¿Qué propiedad de aislamiento estás observando?

No cierres aún la transacción de B.

## 16. Confirmar A y volver a leer desde B

En la sesión A:

1. Ejecuta `COMMIT`.
2. Comprueba el valor confirmado.

Después, sin cerrar todavía la transacción iniciada en B:

1. Ejecuta una segunda consulta sobre el mismo producto.
2. Comprueba si ahora observa el valor confirmado por A.
3. Finaliza la transacción de B mediante `ROLLBACK` o `COMMIT`, sin hacer cambios.

Explica por qué dos sentencias sucesivas de la misma transacción pueden ver valores diferentes bajo `READ COMMITTED`.

## 17. Provocar un conflicto entre escritores

En la sesión A:

1. Inicia una nueva transacción.
2. Modifica otra vez el stock del producto 1.
3. Mantén la transacción abierta.

En la sesión B:

1. Configura `LOCK_TIMEOUT` en 5 segundos.
2. Asigna el query tag `M3_E2_CONFLICTO_ESCRITORES`.
3. Intenta actualizar el mismo producto.
4. Ejecuta únicamente ese `UPDATE`, no un bloque completo de sentencias.
5. Espera a que la operación finalice o devuelva un error.

Registra:

- Si la operación esperó.
- Si terminó con error.
- El mensaje devuelto.
- El Query ID o query tag que permite localizarla.

## 18. Liberar el recurso y repetir

En la sesión A:

1. Ejecuta `ROLLBACK` para cancelar la segunda modificación.

En la sesión B:

1. Cambia el query tag a `M3_E2_ESCRITOR_TRAS_LIBERACION`.
2. Repite la actualización.
3. Comprueba que ahora puede completarse.
4. Consulta el stock resultante.

## 19. Analizar el conflicto en Query History

Desde la sesión B consulta su historial y localiza:

- La actualización que encontró el bloqueo.
- La actualización que se ejecutó después de liberar el recurso.

Recupera, como mínimo:

- `QUERY_ID`.
- `QUERY_TAG`.
- `EXECUTION_STATUS`.
- `ERROR_MESSAGE`.
- `TOTAL_ELAPSED_TIME`.
- `EXECUTION_TIME`.
- `TRANSACTION_BLOCKED_TIME`.
- `TRANSACTION_ID`.
- `START_TIME` y `END_TIME`.

Explica por qué MVCC evita que una lectura tenga que esperar por una escritura, pero no significa que dos escritores puedan modificar libremente el mismo recurso al mismo tiempo.

---

## 20. Limpieza obligatoria

Al finalizar:

1. Asegúrate de que no queda ninguna transacción abierta en ninguna sesión.
2. Restaura `USE_CACHED_RESULT` a `TRUE` en ambas sesiones.
3. Elimina la configuración específica de `LOCK_TIMEOUT` en la sesión B.
4. Elimina o vacía `QUERY_TAG`.
5. Elimina las dos tablas creadas para el ejercicio.
6. Suspende `WH_M3_ANALITICA`.
7. Comprueba el estado final del warehouse.

No elimines:

- `DB_CURSO.ARQUITECTURA.VENTAS_ARQ`.
- Los objetos necesarios para ejercicios posteriores.

---

## Preguntas de reflexión

1. ¿Por qué no basta con comparar tiempos para demostrar que se utilizó el result cache?
2. ¿Por qué una diferencia mínima en el texto SQL puede impedir la reutilización exacta de un resultado?
3. ¿Qué riesgo tendría dejar activado el result cache durante una prueba de caché local?
4. ¿Por qué suspender un warehouse ahorra créditos, pero puede perjudicar la latencia de la siguiente consulta?
5. ¿Qué diferencia existe entre «no leer datos sin confirmar» y mantener un snapshot fijo durante toda la transacción?
6. ¿Por qué `READ COMMITTED` permite que dos `SELECT` sucesivos dentro de la misma transacción devuelvan valores distintos?
7. ¿Qué tipo de concurrencia es prácticamente no bloqueante en este ejercicio?
8. ¿Qué tipo de concurrencia sí puede producir esperas o errores?
9. ¿Por qué es importante reducir `LOCK_TIMEOUT` en un laboratorio didáctico?
10. ¿Qué decisiones tomarías para equilibrar ahorro, caché local y experiencia de usuario en un dashboard empresarial?

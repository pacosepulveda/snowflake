# Módulo 3 - Ejercicio 1

## Separación de almacenamiento y cómputo y ciclo de vida de una consulta

**Modalidad:** individual  
**Herramientas:** Snowsight y SQL  
**Cuenta:** Snowflake Trial, edición Enterprise

---

## Contexto

El equipo de datos de **Northwind Retail** está preparando Snowflake para dos áreas con necesidades diferentes:

- El equipo de **Analítica** ejecutará consultas exploratorias y agregaciones sobre grandes volúmenes de ventas.
- El equipo de **Finanzas** utilizará los mismos datos para sus informes y controles mensuales.

La dirección quiere confirmar que ambas áreas pueden disponer de recursos de cómputo independientes sin duplicar las tablas ni crear copias del conjunto de datos.

También quiere una demostración técnica de lo que ocurre cuando se ejecuta una consulta:

1. Snowflake comprueba la identidad, los permisos y la sintaxis.
2. El optimizador construye un plan y decide qué micro-particiones necesita leer.
3. Un virtual warehouse ejecuta las operaciones.
4. El resultado se devuelve al usuario y la ejecución queda registrada.

Tu misión consiste en preparar un pequeño laboratorio que demuestre de forma observable la arquitectura de tres capas de Snowflake:

```text
Cloud Services
Autenticación, permisos, metadatos, optimización e historial
                         ↓
Compute
Virtual warehouses independientes que ejecutan las consultas
                         ↓
Storage
Una única tabla compartida, almacenada en micro-particiones
```

No basta con obtener un resultado correcto. Debes recopilar evidencias que permitan explicar **qué warehouse ejecutó cada consulta, cuánto tiempo se dedicó a compilarla y ejecutarla, cuántos bytes se leyeron y cómo influyó el pruning**.

---

## Objetivos de aprendizaje

Al completar el ejercicio deberás ser capaz de:

1. Relacionar operaciones reales con las capas de Cloud Services, Compute y Storage.
2. Crear dos virtual warehouses independientes con una configuración orientada al ahorro.
3. Generar un conjunto de datos sintético sin utilizar ficheros ni servicios externos.
4. Comprobar que dos warehouses diferentes pueden consultar la misma tabla.
5. Demostrar que suspender un warehouse no elimina ni bloquea los datos.
6. Desactivar temporalmente la reutilización del result cache para realizar pruebas comparables.
7. Etiquetar consultas mediante `QUERY_TAG`.
8. Obtener y conservar los Query ID de consultas relevantes.
9. Consultar el historial casi en tiempo real mediante `QUERY_HISTORY_BY_SESSION`.
10. Distinguir tiempo de compilación y tiempo de ejecución.
11. Utilizar Query Profile para identificar operadores y estadísticas de lectura.
12. Comparar un escaneo amplio con una consulta que permita aplicar micro-partition pruning.
13. Explicar por qué el número exacto de particiones y los tiempos pueden variar entre cuentas.
14. Finalizar el laboratorio sin dejar warehouses consumiendo créditos.

---

## Prerrequisitos

Debes haber completado el módulo 2 y disponer de:

```text
DB_CURSO
```

El ejercicio creará dentro de esa base de datos:

```text
DB_CURSO.ARQUITECTURA.VENTAS_ARQ
```

También creará estos virtual warehouses:

```text
WH_M3_ANALITICA
WH_M3_FINANZAS
```

Realiza el laboratorio con un usuario que pueda utilizar `SYSADMIN` y que tenga permisos para:

- Crear esquemas y tablas en `DB_CURSO`.
- Crear y modificar virtual warehouses.
- Consultar su propio historial de consultas.

---

## Requisitos

### 1. Crear el SQL File

Crea un nuevo SQL File y ponle un nombre identificable, por ejemplo:

`M3_E1_ARQUITECTURA_CONSULTA`

Mantén todo el ejercicio en el mismo SQL File y en la misma sesión. Esto facilitará el uso de variables de sesión y de `QUERY_HISTORY_BY_SESSION`.

### 2. Establecer el contexto administrativo

Configura explícitamente:

- Rol: `SYSADMIN`
- Base de datos: `DB_CURSO`

Comprueba además:

- Usuario actual.
- Rol actual.
- Región.
- Versión actual de Snowflake.
- Identificador de la sesión.

### 3. Crear dos warehouses independientes

Crea:

- `WH_M3_ANALITICA`
- `WH_M3_FINANZAS`

Ambos deben configurarse con:

- Tamaño `XSMALL`.
- `AUTO_SUSPEND` de 60 segundos.
- `AUTO_RESUME` activado.
- Estado inicial suspendido.

Comprueba mediante SQL que existen y registra su estado inicial.

### 4. Crear el esquema del módulo

Crea, si no existe:

`DB_CURSO.ARQUITECTURA`

Establece este esquema como contexto de trabajo.

### 5. Generar el conjunto de datos

Utiliza `WH_M3_ANALITICA` para crear una tabla transitoria llamada:

`DB_CURSO.ARQUITECTURA.VENTAS_ARQ`

La tabla debe contener **5.000.000 de ventas sintéticas**, generadas íntegramente con SQL mediante `GENERATOR`.

Cada fila debe incluir, como mínimo:

- `ID_VENTA`: identificador numérico único.
- `FECHA`: fecha comprendida dentro de un periodo de aproximadamente dos años.
- `REGION`: una de varias regiones.
- `CANAL`: por ejemplo, `WEB`, `TIENDA` o `PARTNER`.
- `UNIDADES`: número entero positivo.
- `IMPORTE`: valor numérico con dos decimales.

Organiza el resultado de la creación por `FECHA` e `ID_VENTA` para favorecer que los rangos de fechas queden relativamente próximos en el almacenamiento.

No utilices:

- Ficheros CSV.
- Stages.
- Snowflake Marketplace.
- Tablas de ejemplo compartidas.
- Python o herramientas externas.

### 6. Validar el conjunto de datos

Comprueba:

- Número total de filas.
- Fecha mínima y máxima.
- Número de regiones.
- Número de canales.
- Importe total.

El número de filas debe ser exactamente 5.000.000.

### 7. Preparar las pruebas sin result cache

Desactiva temporalmente la reutilización de resultados almacenados para la sesión mediante el parámetro correspondiente.

Configura un `QUERY_TAG` diferente para cada prueba importante.

El objetivo es impedir que una segunda consulta aparentemente ejecutada por otro warehouse sea respondida únicamente desde el result cache.

> No confundas esta acción con la caché local del warehouse. En este ejercicio solo debes desactivar la reutilización del resultado persistido.

### 8. Ejecutar una consulta con el warehouse de Analítica

Utiliza `WH_M3_ANALITICA` y ejecuta una consulta de control sobre `VENTAS_ARQ` que calcule, como mínimo:

- Número de ventas.
- Suma de unidades.
- Suma de importe.

Asigna a la consulta un query tag identificable y conserva su Query ID en una variable de sesión.

### 9. Suspender Analítica y consultar desde Finanzas

Suspende explícitamente `WH_M3_ANALITICA`.

Después:

1. Cambia a `WH_M3_FINANZAS`.
2. Ejecuta la misma consulta de control.
3. Utiliza otro query tag.
4. Conserva el segundo Query ID.
5. Comprueba que los resultados coinciden.

Debes demostrar que:

- La tabla sigue existiendo aunque el warehouse que la creó esté suspendido.
- El segundo warehouse puede consultar los mismos datos.
- Cada consulta queda asociada al warehouse que realmente la ejecutó.

### 10. Consultar el historial de las dos ejecuciones

Utiliza la función de Information Schema para consultar el historial de la sesión.

Recupera para los dos Query ID, como mínimo:

- `QUERY_ID`
- `QUERY_TAG`
- `WAREHOUSE_NAME`
- `WAREHOUSE_SIZE`
- `EXECUTION_STATUS`
- `TOTAL_ELAPSED_TIME`
- `COMPILATION_TIME`
- `EXECUTION_TIME`
- `QUEUED_PROVISIONING_TIME`
- `BYTES_SCANNED`
- `ROWS_PRODUCED`
- `START_TIME`
- `END_TIME`

Convierte los tiempos a una unidad legible cuando resulte útil.

Explica:

- Qué parte puede relacionarse con Cloud Services.
- Qué parte representa trabajo de Compute.
- Por qué ambas consultas leen un único objeto de Storage.
- Por qué los tiempos de los dos warehouses no tienen que ser idénticos.

### 11. Ejecutar un escaneo amplio

Utilizando `WH_M3_FINANZAS`, ejecuta una agregación que cubra todo el periodo de la tabla y agrupe las ventas por canal.

La consulta debe utilizar únicamente las columnas necesarias y no debe contener `SELECT *`.

Configura un query tag específico y conserva el Query ID.

### 12. Ejecutar una consulta selectiva por fecha

Ejecuta una segunda agregación equivalente, pero limitada a un intervalo de siete días.

Mantén:

- Las mismas columnas seleccionadas.
- La misma agrupación.
- El mismo orden de salida.

Cambia únicamente el filtro temporal.

Asigna otro query tag y conserva el Query ID.

### 13. Comparar el historial

Consulta el historial de la sesión para comparar el escaneo amplio y el selectivo.

Incluye, como mínimo:

- Warehouse.
- Tiempo total.
- Tiempo de compilación.
- Tiempo de ejecución.
- Bytes escaneados.
- Filas producidas.

No asumas que la consulta que tarda menos siempre compila menos o que los tiempos serán idénticos en todas las cuentas.

### 14. Analizar ambas consultas en Query Profile

Localiza las dos consultas mediante sus Query ID en Query History y abre Query Profile.

Para cada una, identifica:

- El operador que lee `VENTAS_ARQ`.
- Los operadores de agregación y ordenación, si aparecen.
- `Bytes scanned`.
- `Partitions scanned`.
- `Partitions total`.
- El porcentaje leído desde la caché local, si se muestra.
- El operador más costoso.

Registra los datos en una tabla como esta:

| Métrica | Escaneo amplio | Intervalo de 7 días |
|---|---:|---:|
| Bytes scanned | | |
| Partitions scanned | | |
| Partitions total | | |
| Porcentaje de particiones leído | | |
| Tiempo de ejecución | | |
| Operador más costoso | | |

Calcula el porcentaje de particiones leído como:

```text
particiones escaneadas / particiones totales × 100
```

### 15. Interpretar los resultados

Redacta una explicación breve que responda a estas preguntas:

1. ¿Qué demuestra el uso de dos warehouses sobre la separación entre Compute y Storage?
2. ¿Por qué suspender un warehouse no elimina la tabla?
3. ¿Qué operaciones del ciclo de vida de una consulta pertenecen a Cloud Services?
4. ¿Qué operaciones se ejecutan en el virtual warehouse?
5. ¿Qué evidencia muestra que se aplicó pruning?
6. ¿Por qué el filtro por fecha puede evitar leer parte de la tabla?
7. ¿Por qué era necesario desactivar el result cache para esta comparación?
8. ¿Por qué los valores exactos pueden variar entre alumnos?

### 16. Cerrar el laboratorio sin consumo innecesario

Al finalizar:

- Restaura el comportamiento normal del result cache.
- Elimina el query tag de la sesión o déjalo vacío.
- Suspende los dos warehouses.
- Comprueba su estado.

No elimines la tabla, el esquema ni los warehouses. Se reutilizarán en los ejercicios siguientes del módulo.

---

## Evidencias que debes entregar

Entrega:

1. El script SQL utilizado.
2. El resultado de validación con 5.000.000 de filas.
3. Los Query ID de las consultas ejecutadas con cada warehouse.
4. La consulta de historial y su resultado.
5. Una captura o registro del estado de los dos warehouses.
6. La tabla comparativa de Query Profile.
7. La explicación razonada de las ocho preguntas finales.
8. La comprobación de que los warehouses quedaron suspendidos.

---

## Criterios de éxito

El ejercicio se considera completado cuando:

- Existen los dos warehouses con la configuración solicitada.
- `VENTAS_ARQ` contiene exactamente 5.000.000 de filas.
- Los dos warehouses obtienen el mismo resultado sobre la misma tabla.
- `WH_M3_ANALITICA` puede permanecer suspendido mientras Finanzas consulta los datos.
- El historial identifica correctamente el warehouse de cada consulta.
- Se distinguen compilación y ejecución.
- Query Profile muestra el plan y las estadísticas de escaneo.
- La consulta de siete días lee una fracción menor de las particiones que el escaneo amplio, salvo variaciones justificadas.
- El alumno puede relacionar cada evidencia con Cloud Services, Compute o Storage.
- Ambos warehouses quedan suspendidos al terminar.

---

## Restricciones de coste

- Utiliza exclusivamente warehouses `XSMALL`.
- Mantén `AUTO_SUSPEND = 60`.
- Ejecuta las pruebas de forma secuencial.
- No aumentes el tamaño de los warehouses.
- No crees más de 5.000.000 de filas.
- No repitas innecesariamente la creación de la tabla.
- Suspende los warehouses al finalizar.

El laboratorio está diseñado para tener un consumo reducido dentro del saldo de la cuenta trial.

# Módulo 4 · Ejercicio 3

# Diseñar un modelo de pedidos: tipos de tabla, tipos de datos, secuencias y constraints

## Contexto

La empresa ficticia **Northwind Bikes Iberia** está migrando a Snowflake una parte de su plataforma de ventas. El equipo necesita un modelo sencillo para registrar clientes y pedidos, pero no todos los datos tienen el mismo ciclo de vida:

- Los datos maestros y los pedidos confirmados deben conservarse y disponer de las capacidades de recuperación propias de las tablas permanentes.
- Los datos recibidos antes de ser validados pueden reconstruirse desde el sistema de origen y no necesitan Fail-safe.
- Algunos resultados intermedios solo deben existir durante la sesión de trabajo de un analista.

Además, el responsable de arquitectura quiere comprobar que el equipo entiende cuatro aspectos que suelen causar errores en proyectos reales:

1. La diferencia entre tablas **permanentes**, **transitorias** y **temporales**.
2. La elección correcta de tipos numéricos y temporales.
3. El comportamiento real de las **sequences**.
4. Qué constraints se aplican realmente en una tabla estándar de Snowflake.

Tu objetivo será diseñar el modelo, cargar un conjunto pequeño de datos y ejecutar pruebas controladas que demuestren cada comportamiento.

---

## Objetivos

Al completar el ejercicio serás capaz de:

- Elegir el tipo de tabla adecuado según persistencia, recuperación y coste.
- Crear tablas permanentes, transitorias y temporales.
- Diseñar importes con `NUMBER` en lugar de `FLOAT`.
- Diferenciar `DATE`, `TIMESTAMP_NTZ` y `TIMESTAMP_LTZ`.
- Generar identificadores mediante una sequence.
- Comprobar que una sequence puede producir saltos.
- Definir claves primarias, claves foráneas, `NOT NULL` y `CHECK`.
- Verificar qué constraints son declarativos y cuáles son enforced en tablas estándar.
- Comprobar que una tabla temporal está limitada a la sesión en la que se creó.
- Inspeccionar el DDL y los metadatos del modelo.

---

## Requisitos

- Una cuenta trial de Snowflake en edición Enterprise.
- Acceso a Snowsight.
- Rol `SYSADMIN` disponible en la cuenta individual del laboratorio.
- Haber completado preferentemente los ejercicios de los módulos 2 y 3.

---

## Resultado final esperado

En la base de datos `DB_CURSO` deberás crear el esquema:

```text
MODELO
```

El modelo final incluirá los siguientes objetos:

```text
DB_CURSO.MODELO.SEQ_PEDIDO
DB_CURSO.MODELO.CLIENTES
DB_CURSO.MODELO.PEDIDOS
DB_CURSO.MODELO.PEDIDOS_STAGING
DB_CURSO.MODELO.RESUMEN_SESION
```

Los objetos tendrán este propósito:

| Objeto | Tipo | Propósito |
|---|---|---|
| `CLIENTES` | Tabla permanente | Datos maestros de clientes |
| `PEDIDOS` | Tabla permanente | Pedidos confirmados y validados |
| `PEDIDOS_STAGING` | Tabla transitoria | Datos crudos o recreables antes de validar |
| `RESUMEN_SESION` | Tabla temporal | Resultado intermedio privado de una sesión |
| `SEQ_PEDIDO` | Sequence | Generación de identificadores de pedido |

---

# Tareas

## Tarea 1. Preparar el entorno

Crea o reutiliza un warehouse llamado `WH_M4_MODELO` con estas características:

- Tamaño `XSMALL`.
- Suspensión automática tras 60 segundos de inactividad.
- Reanudación automática.
- Estado inicial suspendido.

Establece el contexto:

- Rol: `SYSADMIN`.
- Warehouse: `WH_M4_MODELO`.
- Base de datos: `DB_CURSO`.
- Esquema: `MODELO`.
- Zona horaria inicial: `Europe/Madrid`.

### Comprobación

Obtén mediante una consulta:

- Rol activo.
- Warehouse activo.
- Base de datos activa.
- Esquema activo.
- Timestamp actual con el offset aplicado.
- Identificador de la sesión.

Consulta también el parámetro `TIMEZONE` de la sesión para verificar el nombre de la zona configurada.

---

## Tarea 2. Crear el modelo con el tipo de tabla adecuado

### 2.1. Sequence de pedidos

Crea `SEQ_PEDIDO` con estas condiciones:

- Valor inicial: `1000`.
- Incremento: `1`.
- Generación ordenada.

La sequence se utilizará como valor por defecto de la clave de los pedidos.

### 2.2. Tabla permanente CLIENTES

Crea `CLIENTES` con las siguientes columnas:

| Columna | Requisito |
|---|---|
| `ID_CLIENTE` | Número entero, obligatorio |
| `NOMBRE` | Texto de hasta 100 caracteres, obligatorio |
| `PAIS` | Código de país de dos caracteres, obligatorio |
| `FECHA_ALTA` | Fecha sin hora, obligatoria |

Declara `ID_CLIENTE` como clave primaria.

### 2.3. Tabla permanente PEDIDOS

Crea `PEDIDOS` con estas columnas:

| Columna | Requisito |
|---|---|
| `ID_PEDIDO` | Número entero, obligatorio y generado por `SEQ_PEDIDO` por defecto |
| `ID_CLIENTE` | Número entero, obligatorio |
| `FECHA_FACTURA` | Fecha sin hora, obligatoria |
| `INSTANTE_EVENTO` | Instante real mostrado en la zona horaria de la sesión |
| `IMPORTE` | Importe exacto con dos decimales |
| `ESTADO` | Texto: `PENDIENTE`, `PAGADO` o `CANCELADO` |
| `CREADO_EN` | Instante de creación con valor por defecto actual |

Añade:

- Una clave primaria sobre `ID_PEDIDO`.
- Una clave foránea desde `ID_CLIENTE` hacia `CLIENTES.ID_CLIENTE`.
- Un `CHECK` que impida importes negativos.
- Un `CHECK` que limite los estados a los tres valores permitidos.

### 2.4. Tabla transitoria PEDIDOS_STAGING

Crea una tabla transitoria que almacene todos sus campos como texto:

- Identificador externo.
- Identificador del cliente.
- Fecha.
- Instante del evento.
- Importe.
- Estado.

Esta tabla representa datos recibidos del sistema origen antes de ser tipados y validados.

### 2.5. Inspección del modelo

Utiliza comandos de metadatos para comprobar:

- Qué tablas se han creado.
- Cuáles son permanentes y cuál es transitoria.
- La retención de Time Travel configurada.
- Las columnas y tipos de `PEDIDOS`.
- Las claves primarias y foráneas declaradas.
- Los `CHECK` definidos.
- El DDL reconstruido de `PEDIDOS`.

Anota por qué `PEDIDOS_STAGING` no debería ser permanente en este escenario.

---

## Tarea 3. Cargar datos válidos

Inserta al menos tres clientes:

1. Un cliente de España.
2. Un cliente de Portugal.
3. Un cliente de Francia.

Inserta después tres pedidos válidos sin especificar manualmente `ID_PEDIDO`, de forma que Snowflake utilice la sequence.

Los pedidos deberán incluir:

- Dos clientes distintos como mínimo.
- Una fecha de factura.
- Un instante expresado con offset UTC explícito.
- Importes con dos decimales.
- Al menos dos estados diferentes.

### Comprobación

Consulta los pedidos ordenados por `ID_PEDIDO` y comprueba:

- Que los identificadores se han generado automáticamente.
- Que los importes mantienen dos decimales.
- Que `CREADO_EN` se ha rellenado automáticamente.
- Que `INSTANTE_EVENTO` se muestra según `Europe/Madrid`.

---

## Tarea 4. Demostrar que una sequence puede tener saltos

Realiza la siguiente prueba:

1. Anota el mayor `ID_PEDIDO` existente.
2. Solicita un valor de `SEQ_PEDIDO.NEXTVAL` sin insertarlo en ninguna tabla.
3. Inserta un nuevo pedido utilizando el valor por defecto de la sequence.
4. Vuelve a consultar los identificadores.

### Preguntas

1. ¿Se ha reutilizado el valor solicitado y descartado?
2. ¿Existe un salto entre los identificadores almacenados?
3. ¿Sería correcto utilizar una sequence para generar números de factura legalmente consecutivos?

---

## Tarea 5. Comprobar el comportamiento real de los constraints

Ejecuta por separado las siguientes pruebas. Algunas deben fallar y otras deben completarse correctamente.

### 5.1. Clave primaria duplicada

Intenta insertar otro pedido utilizando explícitamente un `ID_PEDIDO` que ya exista, manteniendo válidos todos los demás campos.

### 5.2. Clave foránea inexistente

Inserta un pedido cuyo `ID_CLIENTE` no exista en `CLIENTES`.

### 5.3. Valor NULL

Intenta insertar un pedido con `ID_CLIENTE` nulo.

### 5.4. Importe negativo

Intenta insertar un pedido con `IMPORTE` negativo.

### 5.5. Estado no permitido

Intenta insertar un pedido con un estado diferente de:

```text
PENDIENTE
PAGADO
CANCELADO
```

### Análisis requerido

Completa esta tabla con el resultado observado:

| Prueba | ¿Aceptada o rechazada? | Explicación |
|---|---|---|
| Clave primaria duplicada | | |
| Clave foránea inexistente | | |
| `NOT NULL` | | |
| `CHECK` de importe | | |
| `CHECK` de estado | | |

Después crea una consulta que detecte:

- Identificadores de pedido duplicados.
- Pedidos huérfanos cuyo cliente no exista.

---

## Tarea 6. Comparar NUMBER y FLOAT

Ejecuta una prueba que compare:

```text
0.1 + 0.2
```

utilizando:

- `FLOAT`.
- `NUMBER` con dos decimales.

Comprueba también si el resultado `FLOAT` es exactamente igual a `0.3`.

### Pregunta

¿Por qué no debería utilizarse `FLOAT` para importes monetarios, saldos o conciliaciones contables?

---

## Tarea 7. Observar el comportamiento de TIMESTAMP_LTZ

Consulta los pedidos con la zona horaria:

```text
Europe/Madrid
```

Cambia después la zona horaria de la sesión a:

```text
UTC
```

Vuelve a ejecutar exactamente la misma consulta.

Compara:

- `FECHA_FACTURA`.
- `INSTANTE_EVENTO`.
- `CREADO_EN`.

Restaura finalmente la zona horaria `Europe/Madrid`.

### Preguntas

1. ¿Qué columnas cambian su representación?
2. ¿Ha cambiado realmente el instante almacenado?
3. ¿Por qué `DATE` no se ve afectado por la zona horaria?
4. ¿En qué caso utilizarías `TIMESTAMP_NTZ` en lugar de `TIMESTAMP_LTZ`?

---

## Tarea 8. Crear y probar una tabla temporal

En el SQL File principal, crea la tabla temporal `RESUMEN_SESION` con un resumen por estado que incluya:

- Estado.
- Número de pedidos.
- Importe total.

Anota el valor de `CURRENT_SESSION()` y consulta la tabla.

Abre después un **segundo SQL File**, configura el mismo rol, warehouse, base de datos y esquema, y ejecuta:

1. `CURRENT_SESSION()`.
2. Una consulta sobre `DB_CURSO.MODELO.RESUMEN_SESION`.

### Resultado esperado

El segundo SQL File debe utilizar otra sesión y no debe poder ver la tabla temporal creada en la primera.

Vuelve al SQL File original y comprueba que la tabla sigue disponible allí.

---

## Tarea 9. Elaborar una recomendación de diseño

Redacta una conclusión breve para el arquitecto del proyecto indicando:

- Por qué `CLIENTES` y `PEDIDOS` son permanentes.
- Por qué `PEDIDOS_STAGING` es transitoria.
- Por qué `RESUMEN_SESION` es temporal.
- Por qué los importes utilizan `NUMBER(12,2)`.
- Por qué los eventos utilizan `TIMESTAMP_LTZ`.
- Por qué una sequence no debe confundirse con una numeración sin huecos.
- Por qué las claves primaria y foránea no sustituyen los controles de calidad en tablas estándar.

---

## Evidencias que debes conservar

Guarda capturas o resultados de:

- El contexto inicial de la sesión.
- Los tipos de las tablas creadas.
- El DDL de `PEDIDOS`.
- Los pedidos con identificadores generados.
- El salto de la sequence.
- Las cinco pruebas de constraints.
- La detección de duplicados y huérfanos.
- La comparación `NUMBER` frente a `FLOAT`.
- La misma consulta de timestamps en `Europe/Madrid` y en `UTC`.
- El error de acceso a la tabla temporal desde la segunda sesión.

---

## Control de costes

El ejercicio debe realizarse con:

- Un único warehouse `XSMALL`.
- `AUTO_SUSPEND = 60`.
- Un volumen de datos de pocas filas.
- Ejecución secuencial.

Al terminar, suspende el warehouse. No es necesario eliminar las tablas permanentes, porque podrán reutilizarse en ejercicios posteriores.

# Módulo 4 · Ejercicio 2

## De eventos JSON a información analítica con `VARIANT` y `LATERAL FLATTEN`

### Contexto

Una empresa de comercio electrónico recibe eventos generados por su web, su aplicación móvil y su pasarela de pagos. Los eventos llegan como documentos JSON porque no todos tienen exactamente la misma estructura:

- Un evento de creación de pedido contiene el cliente y un array de líneas de producto.
- Un evento de pago contiene información del pago, pero no las líneas del pedido.
- Un evento de cancelación contiene el motivo de la cancelación.
- Algunos documentos pueden tener campos ausentes, arrays vacíos o valores con un formato incorrecto.

El equipo quiere conservar el documento original para no perder información, pero también necesita consultar sus campos con SQL y convertir determinadas partes del JSON a una forma tabular.

En este ejercicio trabajarás con datos semi-estructurados de Snowflake mediante `VARIANT`, `PARSE_JSON`, navegación por rutas y `LATERAL FLATTEN`.

---

## Objetivos

Al finalizar el ejercicio deberás ser capaz de:

1. Almacenar documentos JSON en una columna `VARIANT`.
2. Inspeccionar el tipo y la estructura de los valores almacenados.
3. Consultar atributos de primer nivel y objetos anidados.
4. Convertir explícitamente valores JSON a tipos SQL.
5. Tratar de forma segura fechas o números con formato incorrecto.
6. Convertir un array JSON en varias filas mediante `LATERAL FLATTEN`.
7. Conservar eventos con arrays vacíos usando `OUTER => TRUE`.
8. Detectar problemas básicos de calidad en documentos semi-estructurados.

---

## Requisitos

- Una cuenta trial Enterprise de Snowflake.
- Acceso a Snowsight y a una SQL Worksheet.
- Un rol con permisos para crear objetos en `DB_CURSO`.
- Un virtual warehouse `XSMALL` con `AUTO_SUSPEND` y `AUTO_RESUME`.

El ejercicio debe poder ejecutarse de forma independiente. Si no existen todavía `DB_CURSO`, `DB_CURSO.STAGING` o `DB_CURSO.CURATED`, créalos antes de continuar.

---

## Escenario de datos

Crearás una tabla llamada:

```text
DB_CURSO.STAGING.EVENTOS_COMERCIO_RAW
```

La tabla deberá almacenar, como mínimo:

- Un identificador técnico de carga.
- La fecha y hora de recepción.
- El documento original en una columna `VARIANT`.

Debes cargar seis eventos JSON con las siguientes situaciones:

1. Un pedido válido con dos líneas.
2. Otro pedido válido con dos líneas.
3. Un pago confirmado sin array de líneas.
4. Un pedido con una fecha inválida y valores no numéricos en una línea.
5. Un pedido con el array de líneas vacío.
6. Una cancelación en la que no exista el array de líneas.

Los documentos serán proporcionados en la sección **Datos de entrada**.

---

# Tareas

## Tarea 1 · Preparar el entorno

1. Establece explícitamente el rol y el warehouse de trabajo.
2. Comprueba el contexto de sesión.
3. Crea, si no existen, la base de datos y los esquemas necesarios.
4. Crea la tabla `EVENTOS_COMERCIO_RAW` como tabla transitoria.
5. Configura el warehouse para minimizar el consumo cuando quede inactivo.

### Comprobación esperada

La tabla debe aparecer dentro del esquema `DB_CURSO.STAGING` y la columna que contiene el documento debe ser de tipo `VARIANT`.

---

## Tarea 2 · Cargar los documentos JSON

Inserta los seis documentos proporcionados usando `PARSE_JSON`.

No debes descomponer todavía el documento en múltiples columnas: el objetivo de esta fase es conservar el JSON original.

Después de la carga:

1. Cuenta las filas.
2. Muestra el identificador técnico y el documento completo.
3. Comprueba con `TYPEOF` qué tipo se ha almacenado en la columna `VARIANT`.

### Resultado esperado

- La tabla debe contener seis filas.
- Todos los documentos completos deben aparecer como objetos JSON.
- `TYPEOF` debe indicar que el valor raíz es un `OBJECT`.

---

## Tarea 3 · Navegar por el JSON

Construye una consulta que muestre, para cada evento:

- Identificador del evento.
- Tipo de evento.
- Fecha del evento.
- Identificador del cliente.
- Nombre y correo del cliente.
- Identificador del pedido, cuando exista.
- Importe del pago, cuando exista.
- Tipo interno del atributo `pedido.lineas`.

Utiliza navegación por rutas con `:` y `.`.

Convierte explícitamente los valores obtenidos a tipos SQL adecuados. No dejes que cadenas y fechas se presenten como valores `VARIANT` entrecomillados.

### Cuestiones que debes responder

1. ¿Qué ocurre al consultar una ruta que no existe en un documento?
2. ¿Qué diferencia observas entre un campo ausente y un campo cuyo valor JSON es `null`?
3. ¿Por qué no conviene convertir directamente una fecha o un número si la fuente puede contener datos incorrectos?

---

## Tarea 4 · Crear una representación normalizada segura

Crea una vista estándar llamada:

```text
DB_CURSO.CURATED.V_EVENTOS_NORMALIZADOS
```

La vista deberá exponer una fila por evento con, al menos, estas columnas:

- `ID_CARGA`
- `RECIBIDO_EN`
- `EVENTO_ID`
- `TIPO_EVENTO`
- `FECHA_EVENTO`
- `CLIENTE_ID`
- `CLIENTE_NOMBRE`
- `CLIENTE_EMAIL`
- `PEDIDO_ID`
- `MONEDA`
- `IMPORTE_PAGO`
- `TIPO_LINEAS`

Requisitos:

- Las fechas incorrectas deben convertirse en `NULL`, sin provocar que falle toda la consulta.
- Los importes incorrectos deben convertirse en `NULL`.
- Los campos ausentes deben seguir produciendo `NULL`.
- No incluyas el documento completo en la vista normalizada.

---

## Tarea 5 · Aplanar el array de líneas de pedido

Utiliza `LATERAL FLATTEN` para obtener una fila por cada elemento del array:

```text
pedido.lineas
```

La consulta deberá mostrar:

- Identificador del evento.
- Identificador del pedido.
- Posición del elemento en el array.
- SKU.
- Cantidad.
- Precio unitario.
- Subtotal calculado de la línea.

Realiza dos versiones:

### Versión A

Usa el comportamiento predeterminado de `FLATTEN`.

### Versión B

Usa `OUTER => TRUE`.

### Análisis requerido

1. Compara el número de filas de ambas consultas.
2. Identifica qué pedido desaparece en la primera versión.
3. Explica por qué `OUTER => TRUE` es importante cuando un array puede estar vacío.
4. Comprueba qué ocurre con la línea que contiene valores no numéricos.

---

## Tarea 6 · Crear controles de calidad

Construye una consulta de control que identifique, al menos:

- Eventos con fecha inválida.
- Pedidos sin identificador de cliente.
- Líneas con cantidad inválida.
- Líneas con precio unitario inválido.
- Pedidos cuyo array de líneas está vacío o ausente.

La consulta debe permitir localizar el `EVENTO_ID` afectado y describir el problema detectado.

No corrijas ni elimines el documento original. El objetivo es identificar los defectos manteniendo intacta la capa RAW.

---

## Tarea 7 · Validación final

Entrega los resultados de las siguientes comprobaciones:

1. Número total de eventos cargados.
2. Número de eventos por tipo.
3. Número de líneas válidas de pedido.
4. Importe total calculado para cada pedido válido.
5. Lista de eventos con algún problema de calidad.
6. Diferencia entre el número de filas obtenido con y sin `OUTER => TRUE`.

---

# Datos de entrada

Utiliza exactamente estos seis documentos JSON:

```json
{
  "evento_id": "EVT-1001",
  "tipo": "pedido_creado",
  "fecha": "2026-07-15T08:30:00Z",
  "cliente": {
    "id": "C001",
    "nombre": "Ana López",
    "email": "ana@example.com"
  },
  "pedido": {
    "id": "P1001",
    "moneda": "EUR",
    "lineas": [
      {"sku": "SKU-001", "cantidad": 2, "precio_unitario": 19.95},
      {"sku": "SKU-002", "cantidad": 1, "precio_unitario": 49.90}
    ]
  },
  "canal": "web",
  "etiquetas": ["nuevo", "promocion"]
}
```

```json
{
  "evento_id": "EVT-1002",
  "tipo": "pedido_creado",
  "fecha": "2026-07-15T09:10:00+02:00",
  "cliente": {
    "id": "C002",
    "nombre": "Carlos Ruiz",
    "email": "carlos@example.com"
  },
  "pedido": {
    "id": "P1002",
    "moneda": "EUR",
    "lineas": [
      {"sku": "SKU-001", "cantidad": 1, "precio_unitario": 19.95},
      {"sku": "SKU-003", "cantidad": 3, "precio_unitario": 23.50}
    ]
  },
  "canal": "app",
  "etiquetas": ["recurrente"]
}
```

```json
{
  "evento_id": "EVT-1003",
  "tipo": "pago_confirmado",
  "fecha": "2026-07-15T09:15:00Z",
  "cliente": {
    "id": "C002"
  },
  "pago": {
    "pedido_id": "P1002",
    "importe": 90.45,
    "metodo": "tarjeta"
  },
  "etiquetas": ["pago"]
}
```

```json
{
  "evento_id": "EVT-1004",
  "tipo": "pedido_creado",
  "fecha": "fecha-invalida",
  "cliente": {
    "id": "C003",
    "nombre": "Luis Martín"
  },
  "pedido": {
    "id": "P1003",
    "moneda": "EUR",
    "lineas": [
      {"sku": "SKU-004", "cantidad": "dos", "precio_unitario": "no_disponible"}
    ]
  },
  "canal": "web"
}
```

```json
{
  "evento_id": "EVT-1005",
  "tipo": "pedido_creado",
  "fecha": "2026-07-15T11:30:00+02:00",
  "cliente": {
    "id": "C004",
    "nombre": "Marta Gómez",
    "email": null
  },
  "pedido": {
    "id": "P1004",
    "moneda": "EUR",
    "lineas": []
  },
  "canal": "tienda"
}
```

```json
{
  "evento_id": "EVT-1006",
  "tipo": "pedido_cancelado",
  "fecha": "2026-07-15T12:00:00Z",
  "cliente": {
    "id": "C001"
  },
  "pedido": {
    "id": "P1001",
    "motivo": "solicitud_cliente"
  }
}
```

---

## Restricciones

- No utilices almacenamiento externo ni integraciones cloud.
- No elimines ni modifiques los documentos JSON originales para ocultar errores.
- No utilices `ACCOUNTADMIN` como rol habitual de trabajo.
- No aumentes el warehouse por encima de `XSMALL`; el volumen del ejercicio no lo necesita.

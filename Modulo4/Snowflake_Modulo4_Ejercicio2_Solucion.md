# Módulo 4 · Ejercicio 2 · Solución

## De eventos JSON a información analítica con `VARIANT` y `LATERAL FLATTEN`

---

## 1. Objetivo de la solución

La solución construye un pequeño patrón RAW-to-query para datos JSON:

```text
Documentos JSON
      ↓ PARSE_JSON
STAGING.EVENTOS_COMERCIO_RAW.documento VARIANT
      ↓ navegación, casts y funciones TRY_*
CURATED.V_EVENTOS_NORMALIZADOS
      ↓ LATERAL FLATTEN
Una fila por línea de pedido
```

La tabla RAW conserva el documento completo. Las consultas posteriores interpretan únicamente los campos necesarios y tratan los errores de formato sin alterar la fuente.

---

# 2. Preparar el entorno

## 2.1 Establecer el rol

Abre un SQL File nuevo "M4_E2_JSON.sql" en Snowsight.

Utilizaremos `SYSADMIN` porque es el rol de sistema destinado normalmente a crear y administrar objetos y warehouses.

```sql
USE ROLE SYSADMIN;
```

No es necesario utilizar `ACCOUNTADMIN` para este laboratorio.

## 2.2 Crear un warehouse de bajo consumo

```sql
CREATE WAREHOUSE IF NOT EXISTS WH_LAB_MODELO
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE;

USE WAREHOUSE WH_LAB_MODELO;
```

Explicación:

- `XSMALL` es suficiente para seis documentos y unas pocas consultas.
- `AUTO_SUSPEND = 60` detiene el cómputo después de un minuto de inactividad.
- `AUTO_RESUME = TRUE` permite que el warehouse se inicie automáticamente.
- `INITIALLY_SUSPENDED = TRUE` evita consumo hasta que llegue la primera consulta.

## 2.3 Crear la base de datos y los esquemas

```sql
CREATE DATABASE IF NOT EXISTS DB_CURSO;
CREATE SCHEMA IF NOT EXISTS DB_CURSO.STAGING;
CREATE SCHEMA IF NOT EXISTS DB_CURSO.CURATED;
```

## 2.4 Fijar el contexto

```sql
USE DATABASE DB_CURSO;
USE SCHEMA STAGING;

SELECT
  CURRENT_ROLE()      AS rol,
  CURRENT_WAREHOUSE() AS warehouse,
  CURRENT_DATABASE()  AS base_datos,
  CURRENT_SCHEMA()    AS esquema;
```

El resultado debe mostrar:

```text
SYSADMIN | WH_LAB_MODELO | DB_CURSO | STAGING
```

---

# 3. Crear la tabla RAW

```sql
CREATE OR REPLACE TRANSIENT TABLE DB_CURSO.STAGING.EVENTOS_COMERCIO_RAW (
  id_carga   NUMBER AUTOINCREMENT START 1 INCREMENT 1,
  recibido_en TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP(),
  documento  VARIANT NOT NULL
);
```

## Por qué se usa una tabla transitoria

La capa de staging contiene datos recreables y no necesita Fail-safe. La tabla sigue existiendo entre sesiones, pero evita la retención adicional de Fail-safe de una tabla permanente.

## Por qué se usa `VARIANT`

`VARIANT` puede almacenar objetos y arrays JSON sin imponer que todos los documentos tengan exactamente las mismas claves. También conserva el tipo interno de números, booleanos, objetos y arrays.

---

# 4. Cargar los seis documentos

Snowflake recomienda usar `INSERT INTO ... SELECT` para insertar valores producidos por `PARSE_JSON` en una columna `VARIANT`.

```sql
INSERT INTO DB_CURSO.STAGING.EVENTOS_COMERCIO_RAW (documento)
SELECT PARSE_JSON(column1)
FROM VALUES
($${
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
}$$),
($${
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
}$$),
($${
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
}$$),
($${
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
}$$),
($${
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
}$$),
($${
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
}$$);
```

Se utilizan delimitadores `$$...$$` para que las comillas dobles del JSON no necesiten escaparse como parte de un literal SQL convencional.

---

# 5. Verificar la carga

## 5.1 Contar documentos

```sql
SELECT COUNT(*) AS numero_documentos
FROM DB_CURSO.STAGING.EVENTOS_COMERCIO_RAW;
```

Resultado esperado:

```text
6
```

## 5.2 Mostrar el documento y su tipo raíz

```sql
SELECT
  id_carga,
  TYPEOF(documento) AS tipo_raiz,
  documento
FROM DB_CURSO.STAGING.EVENTOS_COMERCIO_RAW
ORDER BY id_carga;
```

Todos los valores de `TIPO_RAIZ` deben ser:

```text
OBJECT
```

`PARSE_JSON` no ha guardado el JSON como una cadena de texto. Lo ha interpretado como una jerarquía de objetos, arrays y valores dentro de `VARIANT`.

## 5.3 Inspeccionar las claves de primer nivel

```sql
SELECT
  id_carga,
  documento:evento_id::STRING AS evento_id,
  OBJECT_KEYS(documento) AS claves_raiz
FROM DB_CURSO.STAGING.EVENTOS_COMERCIO_RAW
ORDER BY id_carga;
```

Las claves varían entre documentos. Por ejemplo, el evento de pago tiene `pago`, mientras que los eventos de pedido tienen `pedido`.

---

# 6. Navegar por rutas JSON

```sql
SELECT
  id_carga,
  documento:evento_id::STRING          AS evento_id,
  documento:tipo::STRING               AS tipo_evento,
  documento:fecha::STRING              AS fecha_texto,
  documento:cliente.id::STRING         AS cliente_id,
  documento:cliente.nombre::STRING     AS cliente_nombre,
  documento:cliente.email::STRING      AS cliente_email,
  documento:pedido.id::STRING          AS pedido_id,
  documento:pago.importe::STRING       AS importe_pago_texto,
  TYPEOF(documento:pedido.lineas)      AS tipo_lineas
FROM DB_CURSO.STAGING.EVENTOS_COMERCIO_RAW
ORDER BY id_carga;
```

## Interpretación

### Operador `:`

Selecciona una clave dentro del `VARIANT`:

```sql
documento:evento_id
```

### Operador `.`

Continúa la navegación en objetos anidados:

```sql
documento:cliente.id
```

También sería posible escribir rutas con varios operadores `:` o mediante `GET_PATH`, pero la notación combinada suele ser más legible.

### Cast explícito

Sin `::STRING`, los textos extraídos siguen siendo valores `VARIANT` y pueden mostrarse entre comillas dobles. El cast los convierte a un tipo relacional.

### Rutas ausentes

Al consultar, por ejemplo, `documento:pago.importe` sobre un evento de pedido, Snowflake devuelve `NULL`; no se produce un error por la ausencia de la ruta.

---

# 7. Campo ausente frente a JSON `null`

El evento `EVT-1005` contiene explícitamente:

```json
"email": null
```

Otros eventos no contienen la clave `email`.

La siguiente consulta permite observar la diferencia:

```sql
SELECT
  documento:evento_id::STRING AS evento_id,
  documento:cliente.email AS email_variant,
  documento:cliente.email IS NULL AS ruta_ausente_o_sql_null,
  IS_NULL_VALUE(documento:cliente.email) AS es_json_null
FROM DB_CURSO.STAGING.EVENTOS_COMERCIO_RAW
ORDER BY evento_id;
```

Interpretación:

- Una ruta que no existe se comporta como SQL `NULL`.
- El literal JSON `null` es un valor nulo almacenado dentro de `VARIANT` y puede identificarse mediante `IS_NULL_VALUE`.
- Al convertir el valor a `STRING`, ambos suelen terminar representados como `NULL` para el consumo relacional, pero no son idénticos en la capa semi-estructurada.

---

# 8. Demostrar el riesgo de un cast directo

Esta consulta puede fallar por el valor `fecha-invalida`:

```sql
-- Ejecutar solo para observar el error.
SELECT documento:fecha::TIMESTAMP_TZ
FROM DB_CURSO.STAGING.EVENTOS_COMERCIO_RAW;
```

Una conversión directa presupone que todos los valores son válidos. En datos externos, esa suposición puede hacer que una sola fila incorrecta aborte toda la consulta.

La conversión segura es:

```sql
SELECT
  documento:evento_id::STRING AS evento_id,
  TRY_TO_TIMESTAMP_TZ(documento:fecha::STRING) AS fecha_evento
FROM DB_CURSO.STAGING.EVENTOS_COMERCIO_RAW
ORDER BY evento_id;
```

`EVT-1004` debe devolver `NULL` en `FECHA_EVENTO`, mientras que los demás eventos se convierten correctamente.

---

# 9. Crear la vista normalizada

```sql
CREATE OR REPLACE VIEW DB_CURSO.CURATED.V_EVENTOS_NORMALIZADOS AS
SELECT
  id_carga,
  recibido_en,
  documento:evento_id::STRING                         AS evento_id,
  documento:tipo::STRING                              AS tipo_evento,
  TRY_TO_TIMESTAMP_TZ(documento:fecha::STRING)        AS fecha_evento,
  documento:cliente.id::STRING                        AS cliente_id,
  documento:cliente.nombre::STRING                    AS cliente_nombre,
  documento:cliente.email::STRING                     AS cliente_email,
  documento:pedido.id::STRING                         AS pedido_id,
  documento:pedido.moneda::STRING                     AS moneda,
  TRY_TO_DECIMAL(documento:pago.importe::STRING, 12, 2)
                                                        AS importe_pago,
  TYPEOF(documento:pedido.lineas)                     AS tipo_lineas
FROM DB_CURSO.STAGING.EVENTOS_COMERCIO_RAW;
```

## Verificar la vista

```sql
SELECT *
FROM DB_CURSO.CURATED.V_EVENTOS_NORMALIZADOS
ORDER BY id_carga;
```

Puntos que se deben observar:

- `EVT-1004` tiene `FECHA_EVENTO = NULL`.
- Los eventos que no son pagos tienen `IMPORTE_PAGO = NULL`.
- Los eventos sin nombre o email de cliente muestran `NULL`.
- `TIPO_LINEAS` es `ARRAY` para los pedidos que tienen la clave `lineas`.
- En eventos sin esa ruta, `TIPO_LINEAS` es `NULL`.

---

# 10. Aplanar las líneas sin `OUTER => TRUE`

```sql
SELECT
  e.documento:evento_id::STRING             AS evento_id,
  e.documento:pedido.id::STRING             AS pedido_id,
  f.index                                   AS posicion,
  f.value:sku::STRING                       AS sku,
  TRY_TO_NUMBER(f.value:cantidad::STRING)   AS cantidad,
  TRY_TO_DECIMAL(
    f.value:precio_unitario::STRING,
    12,
    2
  )                                         AS precio_unitario,
  TRY_TO_NUMBER(f.value:cantidad::STRING)
    * TRY_TO_DECIMAL(
        f.value:precio_unitario::STRING,
        12,
        2
      )                                     AS subtotal
FROM DB_CURSO.STAGING.EVENTOS_COMERCIO_RAW e,
LATERAL FLATTEN(
  INPUT => e.documento:pedido.lineas
) f
WHERE e.documento:tipo::STRING = 'pedido_creado'
ORDER BY evento_id, posicion;
```

## Resultado esperado

Se obtienen cinco filas:

- Dos de `EVT-1001`.
- Dos de `EVT-1002`.
- Una de `EVT-1004`.

`EVT-1005` desaparece porque su array está vacío y, de manera predeterminada, `FLATTEN` no produce ninguna fila para una expansión vacía.

La línea de `EVT-1004` aparece, pero:

```text
CANTIDAD = NULL
PRECIO_UNITARIO = NULL
SUBTOTAL = NULL
```

Las funciones `TRY_TO_NUMBER` y `TRY_TO_DECIMAL` evitan que los valores `dos` y `no_disponible` aborten la consulta.

---

# 11. Aplanar las líneas con `OUTER => TRUE`

```sql
SELECT
  e.documento:evento_id::STRING             AS evento_id,
  e.documento:pedido.id::STRING             AS pedido_id,
  f.index                                   AS posicion,
  f.value:sku::STRING                       AS sku,
  TRY_TO_NUMBER(f.value:cantidad::STRING)   AS cantidad,
  TRY_TO_DECIMAL(
    f.value:precio_unitario::STRING,
    12,
    2
  )                                         AS precio_unitario,
  TRY_TO_NUMBER(f.value:cantidad::STRING)
    * TRY_TO_DECIMAL(
        f.value:precio_unitario::STRING,
        12,
        2
      )                                     AS subtotal
FROM DB_CURSO.STAGING.EVENTOS_COMERCIO_RAW e,
LATERAL FLATTEN(
  INPUT => e.documento:pedido.lineas,
  OUTER => TRUE
) f
WHERE e.documento:tipo::STRING = 'pedido_creado'
ORDER BY evento_id, posicion;
```

## Resultado esperado

Se obtienen seis filas. La nueva fila representa `EVT-1005` y sus columnas de línea son `NULL`.

`OUTER => TRUE` genera una fila para una expansión que produciría cero filas. Esto permite conservar el registro origen y distinguir un pedido sin líneas de un pedido que no existiera en el resultado.

---

# 12. Comparar formalmente ambas versiones

```sql
WITH sin_outer AS (
  SELECT e.id_carga
  FROM DB_CURSO.STAGING.EVENTOS_COMERCIO_RAW e,
       LATERAL FLATTEN(
         INPUT => e.documento:pedido.lineas
       ) f
  WHERE e.documento:tipo::STRING = 'pedido_creado'
),
con_outer AS (
  SELECT e.id_carga
  FROM DB_CURSO.STAGING.EVENTOS_COMERCIO_RAW e,
       LATERAL FLATTEN(
         INPUT => e.documento:pedido.lineas,
         OUTER => TRUE
       ) f
  WHERE e.documento:tipo::STRING = 'pedido_creado'
)
SELECT
  (SELECT COUNT(*) FROM sin_outer) AS filas_sin_outer,
  (SELECT COUNT(*) FROM con_outer) AS filas_con_outer;
```

Resultado esperado:

```text
FILAS_SIN_OUTER = 5
FILAS_CON_OUTER = 6
```

---

# 13. Crear una vista de líneas de pedido

Esta vista reutiliza la lógica de `FLATTEN` y conserva pedidos vacíos para que puedan detectarse posteriormente.

```sql
CREATE OR REPLACE VIEW DB_CURSO.CURATED.V_LINEAS_PEDIDO AS
SELECT
  e.id_carga,
  e.documento:evento_id::STRING             AS evento_id,
  e.documento:pedido.id::STRING             AS pedido_id,
  f.index                                   AS posicion,
  f.value:sku::STRING                       AS sku,
  TRY_TO_NUMBER(f.value:cantidad::STRING)   AS cantidad,
  TRY_TO_DECIMAL(
    f.value:precio_unitario::STRING,
    12,
    2
  )                                         AS precio_unitario,
  TRY_TO_NUMBER(f.value:cantidad::STRING)
    * TRY_TO_DECIMAL(
        f.value:precio_unitario::STRING,
        12,
        2
      )                                     AS subtotal
FROM DB_CURSO.STAGING.EVENTOS_COMERCIO_RAW e,
LATERAL FLATTEN(
  INPUT => e.documento:pedido.lineas,
  OUTER => TRUE
) f
WHERE e.documento:tipo::STRING = 'pedido_creado';
```

## Consultar la vista

```sql
SELECT *
FROM DB_CURSO.CURATED.V_LINEAS_PEDIDO
ORDER BY evento_id, posicion;
```

---

# 14. Control de calidad de eventos

## 14.1 Problemas a nivel de evento

```sql
SELECT
  documento:evento_id::STRING AS evento_id,
  documento:tipo::STRING AS tipo_evento,
  CASE
    WHEN TRY_TO_TIMESTAMP_TZ(documento:fecha::STRING) IS NULL
      THEN 'FECHA_INVALIDA'
    WHEN documento:tipo::STRING = 'pedido_creado'
         AND documento:cliente.id::STRING IS NULL
      THEN 'CLIENTE_ID_AUSENTE'
    WHEN documento:tipo::STRING = 'pedido_creado'
         AND documento:pedido.lineas IS NULL
      THEN 'ARRAY_LINEAS_AUSENTE'
    WHEN documento:tipo::STRING = 'pedido_creado'
         AND ARRAY_SIZE(documento:pedido.lineas) = 0
      THEN 'ARRAY_LINEAS_VACIO'
    ELSE 'OK'
  END AS estado_calidad
FROM DB_CURSO.STAGING.EVENTOS_COMERCIO_RAW
ORDER BY evento_id;
```

Resultados destacados:

- `EVT-1004` → `FECHA_INVALIDA`.
- `EVT-1005` → `ARRAY_LINEAS_VACIO`.

El orden del `CASE` importa. Un registro con varios defectos devolvería solo la primera condición coincidente. Para obtener todos los defectos conviene construir controles separados y unirlos con `UNION ALL`.

## 14.2 Problemas a nivel de línea

```sql
SELECT
  evento_id,
  pedido_id,
  posicion,
  sku,
  CASE
    WHEN sku IS NULL
      THEN 'PEDIDO_SIN_LINEAS'
    WHEN cantidad IS NULL
      THEN 'CANTIDAD_INVALIDA'
    WHEN precio_unitario IS NULL
      THEN 'PRECIO_INVALIDO'
    ELSE 'OK'
  END AS estado_calidad
FROM DB_CURSO.CURATED.V_LINEAS_PEDIDO
ORDER BY evento_id, posicion;
```

Resultados destacados:

- La línea de `EVT-1004` se marca como `CANTIDAD_INVALIDA`.
- `EVT-1005` se marca como `PEDIDO_SIN_LINEAS`.

Para capturar simultáneamente cantidad y precio inválidos, se puede crear un informe vertical:

```sql
SELECT evento_id, pedido_id, posicion, 'CANTIDAD_INVALIDA' AS problema
FROM DB_CURSO.CURATED.V_LINEAS_PEDIDO
WHERE sku IS NOT NULL AND cantidad IS NULL

UNION ALL

SELECT evento_id, pedido_id, posicion, 'PRECIO_INVALIDO' AS problema
FROM DB_CURSO.CURATED.V_LINEAS_PEDIDO
WHERE sku IS NOT NULL AND precio_unitario IS NULL

UNION ALL

SELECT evento_id, pedido_id, posicion, 'PEDIDO_SIN_LINEAS' AS problema
FROM DB_CURSO.CURATED.V_LINEAS_PEDIDO
WHERE sku IS NULL
ORDER BY evento_id, problema;
```

Resultado esperado:

```text
EVT-1004 | P1003 | 0    | CANTIDAD_INVALIDA
EVT-1004 | P1003 | 0    | PRECIO_INVALIDO
EVT-1005 | P1004 | NULL | PEDIDO_SIN_LINEAS
```

A estos resultados debe añadirse el problema de fecha de `EVT-1004` obtenido en el control a nivel de evento.

---

# 15. Validaciones finales

## 15.1 Número total de eventos

```sql
SELECT COUNT(*) AS total_eventos
FROM DB_CURSO.STAGING.EVENTOS_COMERCIO_RAW;
```

Resultado:

```text
6
```

## 15.2 Eventos por tipo

```sql
SELECT
  documento:tipo::STRING AS tipo_evento,
  COUNT(*) AS numero_eventos
FROM DB_CURSO.STAGING.EVENTOS_COMERCIO_RAW
GROUP BY tipo_evento
ORDER BY tipo_evento;
```

Resultado esperado:

```text
pago_confirmado  | 1
pedido_cancelado | 1
pedido_creado    | 4
```

## 15.3 Número de líneas válidas

```sql
SELECT COUNT(*) AS lineas_validas
FROM DB_CURSO.CURATED.V_LINEAS_PEDIDO
WHERE sku IS NOT NULL
  AND cantidad IS NOT NULL
  AND precio_unitario IS NOT NULL;
```

Resultado esperado:

```text
4
```

Son las dos líneas de `P1001` y las dos líneas de `P1002`.

## 15.4 Importe por pedido válido

```sql
SELECT
  pedido_id,
  SUM(subtotal) AS importe_calculado
FROM DB_CURSO.CURATED.V_LINEAS_PEDIDO
WHERE sku IS NOT NULL
  AND cantidad IS NOT NULL
  AND precio_unitario IS NOT NULL
GROUP BY pedido_id
ORDER BY pedido_id;
```

Resultado esperado:

```text
P1001 | 89.80
P1002 | 90.45
```

Cálculos:

```text
P1001 = (2 × 19.95) + (1 × 49.90) = 89.80
P1002 = (1 × 19.95) + (3 × 23.50) = 90.45
```

El importe de `P1002` coincide con el evento `pago_confirmado`, lo que permite hacer una reconciliación básica.

## 15.5 Reconciliar pedido y pago

```sql
WITH pedidos AS (
  SELECT
    pedido_id,
    SUM(subtotal) AS importe_pedido
  FROM DB_CURSO.CURATED.V_LINEAS_PEDIDO
  WHERE sku IS NOT NULL
    AND cantidad IS NOT NULL
    AND precio_unitario IS NOT NULL
  GROUP BY pedido_id
),
pagos AS (
  SELECT
    documento:pago.pedido_id::STRING AS pedido_id,
    TRY_TO_DECIMAL(documento:pago.importe::STRING, 12, 2) AS importe_pagado
  FROM DB_CURSO.STAGING.EVENTOS_COMERCIO_RAW
  WHERE documento:tipo::STRING = 'pago_confirmado'
)
SELECT
  p.pedido_id,
  p.importe_pedido,
  g.importe_pagado,
  p.importe_pedido - g.importe_pagado AS diferencia
FROM pedidos p
JOIN pagos g
  ON p.pedido_id = g.pedido_id;
```

Resultado esperado para `P1002`:

```text
IMPORTE_PEDIDO = 90.45
IMPORTE_PAGADO = 90.45
DIFERENCIA     = 0.00
```

---

# 16. Qué se ha demostrado

## `VARIANT` conserva flexibilidad

Los seis documentos pueden coexistir en la misma columna aunque sus estructuras sean distintas.

## `PARSE_JSON` interpreta el documento

No guarda simplemente una cadena. Convierte el texto JSON en una jerarquía consultable de objetos, arrays y valores.

## La navegación es tolerante a campos ausentes

Una ruta no existente devuelve `NULL`, lo que permite consultar documentos heterogéneos sin escribir una estructura diferente para cada tipo de evento.

## Los casts deben ser explícitos

Los valores extraídos siguen siendo `VARIANT`. Los casts proporcionan tipos adecuados para comparar, sumar y presentar los datos.

## Las funciones `TRY_*` protegen el proceso

Un dato mal formado se transforma en `NULL` y puede enviarse a un control de calidad, en lugar de detener toda la consulta.

## `LATERAL FLATTEN` cambia la granularidad

Cada elemento del array se convierte en una fila y conserva el acceso a las columnas del documento origen.

## `OUTER => TRUE` evita pérdidas silenciosas

Un array vacío produce una fila con valores de línea nulos. Sin esta opción, el registro origen desaparece del resultado.

---

## Documentación oficial consultada

- Semi-structured data types: https://docs.snowflake.com/en/sql-reference/data-types-semistructured
- PARSE_JSON: https://docs.snowflake.com/en/sql-reference/functions/parse_json
- FLATTEN: https://docs.snowflake.com/en/sql-reference/functions/flatten
- TRY_TO_DECIMAL: https://docs.snowflake.com/en/sql-reference/functions/try_to_decimal
- TRY_TO_TIMESTAMP: https://docs.snowflake.com/en/sql-reference/functions/try_to_timestamp
- Trial accounts: https://docs.snowflake.com/en/user-guide/admin-trial-account

---

# 17. Limpieza opcional

No es necesario eliminar los objetos porque se reutilizarán conceptualmente en el siguiente ejercicio sobre vistas. Para limpiar únicamente este laboratorio:

```sql
DROP VIEW IF EXISTS DB_CURSO.CURATED.V_LINEAS_PEDIDO;
DROP VIEW IF EXISTS DB_CURSO.CURATED.V_EVENTOS_NORMALIZADOS;
DROP TABLE IF EXISTS DB_CURSO.STAGING.EVENTOS_COMERCIO_RAW;
DROP WAREHOUSE IF EXISTS WH_LAB_MODELO;
```

Para conservar los objetos y detener el consumo:

```sql
ALTER WAREHOUSE WH_LAB_MODELO SUSPEND;
```

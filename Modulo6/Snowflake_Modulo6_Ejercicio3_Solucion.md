# Módulo 6 · Ejercicio 3
## Solución guiada: construcción idempotente de un data mart mensual

---

## 1. Arquitectura del laboratorio

```text
CURATED.CLIENTES_MART
            +
CURATED.VENTAS_MART_BASE
            ↓
V_VENTAS_ENRIQUECIDAS_MART
            ↓
Calidad y reconciliación
            ↓
MARTS.VENTAS_MES_SEGMENTO_CANAL
```

La granularidad será:

```text
una fila por mes + segmento + canal
```

Las métricas solo incluirán ventas `COMPLETADA`.

---

## 2. Preparar Workspaces y el contexto

En **Workspaces**, crea:

```text
M6_E03_MART_IDEMPOTENTE.sql
```

Ejecuta:

```sql
USE ROLE SYSADMIN;

CREATE WAREHOUSE IF NOT EXISTS WH_DEV
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE;

USE WAREHOUSE WH_DEV;

CREATE DATABASE IF NOT EXISTS DB_CURSO;
CREATE SCHEMA IF NOT EXISTS DB_CURSO.CURATED;
CREATE SCHEMA IF NOT EXISTS DB_CURSO.MARTS;

USE DATABASE DB_CURSO;
USE SCHEMA CURATED;

ALTER SESSION SET QUERY_TAG = 'M06_E03_MART_IDEMPOTENTE';
```

Comprueba:

```sql
SELECT
    CURRENT_ROLE()      AS rol,
    CURRENT_WAREHOUSE() AS warehouse,
    CURRENT_DATABASE()  AS base_datos,
    CURRENT_SCHEMA()    AS esquema;
```

---

## 3. Crear la dimensión de clientes

```sql
CREATE OR REPLACE TABLE DB_CURSO.CURATED.CLIENTES_MART (
    id_cliente NUMBER(18,0),
    segmento   VARCHAR(20),
    region     VARCHAR(20)
);
```

Inserta:

```sql
INSERT INTO DB_CURSO.CURATED.CLIENTES_MART
SELECT
    column1::NUMBER(18,0),
    column2::VARCHAR(20),
    column3::VARCHAR(20)
FROM VALUES
    (901, 'PYME',        'NORTE'),
    (902, 'EMPRESA',     'SUR'),
    (903, 'PYME',        'ESTE'),
    (904, 'CORPORATIVO', 'OESTE'),
    (905, 'EMPRESA',     'NORTE'),
    (906, 'PYME',        'SUR'),
    (907, 'CORPORATIVO', 'ESTE'),
    (908, 'EMPRESA',     'OESTE');
```

Comprueba:

```sql
SELECT COUNT(*) AS clientes
FROM DB_CURSO.CURATED.CLIENTES_MART;
```

Resultado:

```text
8
```

---

## 4. Crear la tabla de ventas

```sql
CREATE OR REPLACE TABLE DB_CURSO.CURATED.VENTAS_MART_BASE (
    id_venta             NUMBER(18,0),
    id_cliente           NUMBER(18,0),
    fecha                DATE,
    canal                VARCHAR(20),
    importe              NUMBER(12,2),
    moneda               VARCHAR(3),
    estado               VARCHAR(20),
    fecha_modificacion   TIMESTAMP_NTZ
);
```

Inserta las 26 ventas:

```sql
INSERT INTO DB_CURSO.CURATED.VENTAS_MART_BASE
SELECT
    column1::NUMBER(18,0),
    column2::NUMBER(18,0),
    column3::DATE,
    column4::VARCHAR(20),
    column5::NUMBER(12,2),
    'EUR'::VARCHAR(3),
    column6::VARCHAR(20),
    column7::TIMESTAMP_NTZ
FROM VALUES
    (7001, 901, '2026-01-05', 'WEB',         100.00, 'COMPLETADA', '2026-01-05 10:00:00'),
    (7002, 902, '2026-01-07', 'TIENDA',      200.00, 'COMPLETADA', '2026-01-07 11:00:00'),
    (7003, 903, '2026-01-10', 'WEB',         150.00, 'PENDIENTE',  '2026-01-10 09:00:00'),
    (7004, 904, '2026-01-15', 'MARKETPLACE', 300.00, 'COMPLETADA', '2026-01-15 12:00:00'),
    (7005, 905, '2026-01-20', 'WEB',         120.00, 'CANCELADA',  '2026-01-20 15:00:00'),
    (7006, 906, '2026-01-25', 'TIENDA',       80.00, 'COMPLETADA', '2026-01-25 16:00:00'),
    (7021, 903, '2026-01-28', 'WEB',          50.00, 'COMPLETADA', '2026-01-28 17:00:00'),
    (7022, 905, '2026-01-29', 'TIENDA',      130.00, 'COMPLETADA', '2026-01-29 18:00:00'),

    (7007, 901, '2026-02-02', 'WEB',         110.00, 'COMPLETADA', '2026-02-02 10:00:00'),
    (7008, 902, '2026-02-05', 'MARKETPLACE', 220.00, 'COMPLETADA', '2026-02-05 11:00:00'),
    (7009, 903, '2026-02-08', 'TIENDA',       90.00, 'COMPLETADA', '2026-02-08 09:00:00'),
    (7010, 904, '2026-02-12', 'WEB',         330.00, 'COMPLETADA', '2026-02-12 12:00:00'),
    (7011, 907, '2026-02-18', 'MARKETPLACE', 410.00, 'PENDIENTE',  '2026-02-18 15:00:00'),
    (7012, 908, '2026-02-21', 'TIENDA',      140.00, 'COMPLETADA', '2026-02-21 16:00:00'),
    (7023, 906, '2026-02-24', 'WEB',          70.00, 'COMPLETADA', '2026-02-24 17:00:00'),
    (7024, 908, '2026-02-26', 'MARKETPLACE', 180.00, 'COMPLETADA', '2026-02-26 18:00:00'),

    (7013, 901, '2026-03-01', 'WEB',         130.00, 'COMPLETADA', '2026-03-01 10:00:00'),
    (7014, 902, '2026-03-04', 'TIENDA',      240.00, 'COMPLETADA', '2026-03-04 11:00:00'),
    (7015, 903, '2026-03-06', 'MARKETPLACE',  95.00, 'CANCELADA',  '2026-03-06 09:00:00'),
    (7016, 904, '2026-03-10', 'WEB',         350.00, 'COMPLETADA', '2026-03-10 12:00:00'),
    (7017, 905, '2026-03-15', 'WEB',         160.00, 'COMPLETADA', '2026-03-15 15:00:00'),
    (7018, 906, '2026-03-20', 'TIENDA',       85.00, 'COMPLETADA', '2026-03-20 16:00:00'),
    (7019, 907, '2026-03-22', 'MARKETPLACE', 420.00, 'COMPLETADA', '2026-03-22 17:00:00'),
    (7020, 908, '2026-03-25', 'TIENDA',      150.00, 'PENDIENTE',  '2026-03-25 18:00:00'),
    (7025, 903, '2026-03-27', 'TIENDA',       95.00, 'COMPLETADA', '2026-03-27 17:00:00'),
    (7026, 902, '2026-03-28', 'WEB',         210.00, 'COMPLETADA', '2026-03-28 18:00:00');
```

Comprueba:

```sql
SELECT
    COUNT(*) AS ventas,
    COUNT(DISTINCT id_venta) AS ids_distintos,
    MIN(fecha) AS fecha_minima,
    MAX(fecha) AS fecha_maxima,
    COUNT_IF(estado = 'COMPLETADA') AS completadas,
    COUNT_IF(estado = 'PENDIENTE') AS pendientes,
    COUNT_IF(estado = 'CANCELADA') AS canceladas
FROM DB_CURSO.CURATED.VENTAS_MART_BASE;
```

Resultado esperado:

| VENTAS | IDS_DISTINTOS | COMPLETADAS | PENDIENTES | CANCELADAS |
|---:|---:|---:|---:|---:|
| 26 | 26 | 21 | 3 | 2 |

---

## 5. Crear la view enriquecida

```sql
CREATE OR REPLACE VIEW
    DB_CURSO.CURATED.V_VENTAS_ENRIQUECIDAS_MART
AS
SELECT
    v.id_venta,
    v.id_cliente,
    v.fecha,
    DATE_TRUNC('MONTH', v.fecha)::DATE AS mes,
    v.canal,
    v.importe,
    v.moneda,
    v.estado,
    v.fecha_modificacion,
    c.segmento,
    c.region,
    (v.estado = 'COMPLETADA') AS es_publicable
FROM DB_CURSO.CURATED.VENTAS_MART_BASE AS v
LEFT JOIN DB_CURSO.CURATED.CLIENTES_MART AS c
    ON c.id_cliente = v.id_cliente;
```

### Por qué usamos LEFT JOIN

Si una venta referencia un cliente inexistente, no queremos ocultarla mediante un `INNER JOIN`.

Con `LEFT JOIN`:

- La venta sigue apareciendo.
- `segmento` y `region` serán `NULL`.
- El control de calidad puede detectar el cliente huérfano.

Comprueba:

```sql
SELECT
    COUNT(*) AS filas,
    COUNT_IF(es_publicable) AS publicables
FROM DB_CURSO.CURATED.V_VENTAS_ENRIQUECIDAS_MART;
```

Resultado:

```text
26 filas
21 publicables
```

---

## 6. Implementar el control de calidad

```sql
WITH controles AS (
    SELECT
        (
            SELECT
                COUNT(*) - COUNT(DISTINCT id_venta)
            FROM DB_CURSO.CURATED.VENTAS_MART_BASE
        ) AS ids_venta_duplicados,

        (
            SELECT
                COALESCE(COUNT_IF(c.id_cliente IS NULL), 0)
            FROM DB_CURSO.CURATED.VENTAS_MART_BASE v
            LEFT JOIN DB_CURSO.CURATED.CLIENTES_MART c
                ON c.id_cliente = v.id_cliente
        ) AS clientes_huerfanos,

        (
            SELECT
                COALESCE(
                    COUNT_IF(importe IS NULL OR importe <= 0),
                    0
                )
            FROM DB_CURSO.CURATED.VENTAS_MART_BASE
        ) AS importes_invalidos,

        (
            SELECT
                COALESCE(
                    COUNT_IF(
                        estado NOT IN (
                            'COMPLETADA',
                            'PENDIENTE',
                            'CANCELADA'
                        )
                    ),
                    0
                )
            FROM DB_CURSO.CURATED.VENTAS_MART_BASE
        ) AS estados_invalidos,

        (
            SELECT
                COALESCE(
                    COUNT_IF(
                        segmento IS NULL
                        OR canal IS NULL
                        OR TRIM(canal) = ''
                    ),
                    0
                )
            FROM DB_CURSO.CURATED.V_VENTAS_ENRIQUECIDAS_MART
        ) AS dimensiones_invalidas
)

SELECT
    *,
    CASE
        WHEN ids_venta_duplicados = 0
         AND clientes_huerfanos = 0
         AND importes_invalidos = 0
         AND estados_invalidos = 0
         AND dimensiones_invalidas = 0
        THEN 'OK'
        ELSE 'ERROR'
    END AS estado_control
FROM controles;
```

Todos los contadores deben ser cero y el estado `OK`.

### Por qué usamos COALESCE con COUNT_IF

`COUNT_IF` puede devolver `NULL` cuando ninguna fila cumple la condición. Para un control operativo resulta más útil presentar `0`.

---

## 7. Probar que el control detecta un cliente huérfano

Inserta temporalmente:

```sql
INSERT INTO DB_CURSO.CURATED.VENTAS_MART_BASE
VALUES (
    7999,
    999,
    '2026-03-30',
    'WEB',
    50.00,
    'EUR',
    'COMPLETADA',
    '2026-03-30 10:00:00'
);
```

Ejecuta otra vez el control.

Debes obtener, como mínimo:

```text
CLIENTES_HUERFANOS = 1
DIMENSIONES_INVALIDAS = 1
ESTADO_CONTROL = ERROR
```

La fila aparece en la view, pero sin segmento ni región.

No publiques el mart mientras el control sea `ERROR`.

Retira la fila:

```sql
DELETE FROM DB_CURSO.CURATED.VENTAS_MART_BASE
WHERE id_venta = 7999;
```

Repite el control. Debe volver a `OK`.

---

## 8. Construir la consulta agregada

Prueba primero la consulta sin crear la tabla:

```sql
WITH ventas_publicables AS (
    SELECT
        mes,
        segmento,
        canal,
        id_cliente,
        importe,
        fecha_modificacion
    FROM DB_CURSO.CURATED.V_VENTAS_ENRIQUECIDAS_MART
    WHERE es_publicable
),

watermark AS (
    SELECT
        MAX(fecha_modificacion) AS source_watermark
    FROM ventas_publicables
)

SELECT
    v.mes,
    v.segmento,
    v.canal,

    COUNT(*)::NUMBER(18,0) AS num_ventas,

    COUNT(DISTINCT v.id_cliente)::NUMBER(18,0)
        AS clientes_unicos,

    SUM(v.importe)::NUMBER(18,2)
        AS importe_total,

    ROUND(AVG(v.importe), 2)::NUMBER(18,2)
        AS ticket_medio,

    MAX(v.fecha_modificacion)
        AS ultima_modificacion_grupo,

    w.source_watermark
        AS _source_watermark

FROM ventas_publicables v
CROSS JOIN watermark w

GROUP BY
    v.mes,
    v.segmento,
    v.canal,
    w.source_watermark

ORDER BY
    v.mes,
    v.segmento,
    v.canal;
```

Valida el resumen:

```sql
WITH agregado AS (
    -- Copia aquí la consulta anterior sin ORDER BY.
    SELECT
        v.mes,
        v.segmento,
        v.canal,
        COUNT(*) AS num_ventas,
        COUNT(DISTINCT v.id_cliente) AS clientes_unicos,
        SUM(v.importe) AS importe_total,
        ROUND(AVG(v.importe), 2) AS ticket_medio,
        MAX(v.fecha_modificacion) AS ultima_modificacion_grupo,
        w.source_watermark AS _source_watermark
    FROM (
        SELECT
            mes,
            segmento,
            canal,
            id_cliente,
            importe,
            fecha_modificacion
        FROM DB_CURSO.CURATED.V_VENTAS_ENRIQUECIDAS_MART
        WHERE es_publicable
    ) v
    CROSS JOIN (
        SELECT
            MAX(fecha_modificacion) AS source_watermark
        FROM DB_CURSO.CURATED.V_VENTAS_ENRIQUECIDAS_MART
        WHERE es_publicable
    ) w
    GROUP BY
        v.mes,
        v.segmento,
        v.canal,
        w.source_watermark
)

SELECT
    COUNT(*) AS filas_mart,
    SUM(num_ventas) AS ventas_agregadas,
    SUM(importe_total) AS importe_total
FROM agregado;
```

Resultado:

| FILAS_MART | VENTAS_AGREGADAS | IMPORTE_TOTAL |
|---:|---:|---:|
| 15 | 21 | 3690.00 |

---

## 9. Demostrar que INSERT…SELECT no es idempotente

Crea la tabla de prueba:

```sql
CREATE OR REPLACE TRANSIENT TABLE
    DB_CURSO.MARTS.VENTAS_MES_INSERT_PRUEBA (
        mes                         DATE,
        segmento                    VARCHAR(20),
        canal                       VARCHAR(20),
        num_ventas                  NUMBER(18,0),
        clientes_unicos             NUMBER(18,0),
        importe_total               NUMBER(18,2),
        ticket_medio                NUMBER(18,2),
        ultima_modificacion_grupo   TIMESTAMP_NTZ,
        _source_watermark           TIMESTAMP_NTZ
    );
```

Inserta una primera vez:

```sql
INSERT INTO DB_CURSO.MARTS.VENTAS_MES_INSERT_PRUEBA
WITH ventas_publicables AS (
    SELECT
        mes,
        segmento,
        canal,
        id_cliente,
        importe,
        fecha_modificacion
    FROM DB_CURSO.CURATED.V_VENTAS_ENRIQUECIDAS_MART
    WHERE es_publicable
),

watermark AS (
    SELECT MAX(fecha_modificacion) AS source_watermark
    FROM ventas_publicables
)

SELECT
    v.mes,
    v.segmento,
    v.canal,
    COUNT(*)::NUMBER(18,0),
    COUNT(DISTINCT v.id_cliente)::NUMBER(18,0),
    SUM(v.importe)::NUMBER(18,2),
    ROUND(AVG(v.importe), 2)::NUMBER(18,2),
    MAX(v.fecha_modificacion),
    w.source_watermark
FROM ventas_publicables v
CROSS JOIN watermark w
GROUP BY
    v.mes,
    v.segmento,
    v.canal,
    w.source_watermark;
```

Comprueba:

```sql
SELECT COUNT(*) AS filas
FROM DB_CURSO.MARTS.VENTAS_MES_INSERT_PRUEBA;
```

Resultado:

```text
15
```

Ejecuta el mismo `INSERT` una segunda vez.

Comprueba:

```sql
SELECT
    COUNT(*) AS filas,
    SUM(num_ventas) AS ventas_sumadas,
    SUM(importe_total) AS importe_sumado
FROM DB_CURSO.MARTS.VENTAS_MES_INSERT_PRUEBA;
```

Resultado:

```text
30 filas
42 ventas sumadas
7380.00
```

Detecta las claves duplicadas:

```sql
SELECT
    mes,
    segmento,
    canal,
    COUNT(*) AS apariciones
FROM DB_CURSO.MARTS.VENTAS_MES_INSERT_PRUEBA
GROUP BY mes, segmento, canal
HAVING COUNT(*) > 1;
```

Debe devolver las 15 claves, cada una con dos apariciones.

Elimina la tabla:

```sql
DROP TABLE DB_CURSO.MARTS.VENTAS_MES_INSERT_PRUEBA;
```

---

## 10. Publicar el mart mediante CTAS

```sql
CREATE OR REPLACE TABLE
    DB_CURSO.MARTS.VENTAS_MES_SEGMENTO_CANAL

COPY GRANTS

AS

WITH ventas_publicables AS (
    SELECT
        mes,
        segmento,
        canal,
        id_cliente,
        importe,
        fecha_modificacion
    FROM DB_CURSO.CURATED.V_VENTAS_ENRIQUECIDAS_MART
    WHERE es_publicable
),

watermark AS (
    SELECT
        MAX(fecha_modificacion) AS source_watermark
    FROM ventas_publicables
)

SELECT
    v.mes,

    v.segmento,

    v.canal,

    COUNT(*)::NUMBER(18,0)
        AS num_ventas,

    COUNT(DISTINCT v.id_cliente)::NUMBER(18,0)
        AS clientes_unicos,

    SUM(v.importe)::NUMBER(18,2)
        AS importe_total,

    ROUND(AVG(v.importe), 2)::NUMBER(18,2)
        AS ticket_medio,

    MAX(v.fecha_modificacion)
        AS ultima_modificacion_grupo,

    w.source_watermark
        AS _source_watermark

FROM ventas_publicables v
CROSS JOIN watermark w

GROUP BY
    v.mes,
    v.segmento,
    v.canal,
    w.source_watermark;
```

### Por qué CTAS

La sentencia:

- Reconstruye el resultado completo.
- No depende de lo que hubiera en la tabla anterior.
- Evita acumulaciones por reejecución.
- Es fácil de comprender y mantener para un mart pequeño.
- Reemplaza el objeto de forma atómica.

Las consultas concurrentes utilizan la versión anterior o la nueva, no una tabla parcialmente construida.

### Qué hace COPY GRANTS

Cuando la tabla ya existe, copia sus privilegios, excepto `OWNERSHIP`, al objeto que la reemplaza.

No copia futuros grants del esquema como nuevos grants directos del objeto.

---

## 11. Validar el mart

### 11.1 Resumen

```sql
SELECT
    COUNT(*) AS filas,
    SUM(num_ventas) AS ventas,
    SUM(importe_total) AS importe_total
FROM DB_CURSO.MARTS.VENTAS_MES_SEGMENTO_CANAL;
```

Resultado:

```text
15 filas
21 ventas
3690.00
```

### 11.2 Unicidad de la granularidad

```sql
SELECT
    mes,
    segmento,
    canal,
    COUNT(*) AS apariciones
FROM DB_CURSO.MARTS.VENTAS_MES_SEGMENTO_CANAL
GROUP BY mes, segmento, canal
HAVING COUNT(*) > 1;
```

No debe devolver filas.

### 11.3 Nulos, contadores e importes

```sql
SELECT
    COALESCE(
        COUNT_IF(
            mes IS NULL
            OR segmento IS NULL
            OR canal IS NULL
        ),
        0
    ) AS dimensiones_nulas,

    COALESCE(
        COUNT_IF(
            num_ventas <= 0
            OR clientes_unicos <= 0
        ),
        0
    ) AS contadores_invalidos,

    COALESCE(
        COUNT_IF(
            importe_total < 0
            OR ticket_medio < 0
        ),
        0
    ) AS importes_invalidos,

    COALESCE(
        COUNT_IF(
            ABS(
                ticket_medio
                - ROUND(importe_total / num_ventas, 2)
            ) > 0.01
        ),
        0
    ) AS tickets_inconsistentes

FROM DB_CURSO.MARTS.VENTAS_MES_SEGMENTO_CANAL;
```

Todos los resultados deben ser cero.

### 11.4 Reconciliación de ventas e importe

```sql
WITH fuente AS (
    SELECT
        COUNT(*) AS ventas,
        SUM(importe) AS importe_total
    FROM DB_CURSO.CURATED.V_VENTAS_ENRIQUECIDAS_MART
    WHERE es_publicable
),

mart AS (
    SELECT
        SUM(num_ventas) AS ventas,
        SUM(importe_total) AS importe_total
    FROM DB_CURSO.MARTS.VENTAS_MES_SEGMENTO_CANAL
)

SELECT
    fuente.ventas AS ventas_fuente,
    mart.ventas AS ventas_mart,
    fuente.ventas - mart.ventas AS diferencia_ventas,

    fuente.importe_total AS importe_fuente,
    mart.importe_total AS importe_mart,
    fuente.importe_total - mart.importe_total
        AS diferencia_importe

FROM fuente
CROSS JOIN mart;
```

Las diferencias deben ser cero.

### 11.5 Watermark

```sql
SELECT
    COUNT(DISTINCT _source_watermark) AS watermarks_distintos,
    MIN(_source_watermark) AS watermark_minimo,
    MAX(_source_watermark) AS watermark_maximo
FROM DB_CURSO.MARTS.VENTAS_MES_SEGMENTO_CANAL;
```

Resultado:

```text
1 watermark distinto
```

### 11.6 Resultado completo

```sql
SELECT *
FROM DB_CURSO.MARTS.VENTAS_MES_SEGMENTO_CANAL
ORDER BY mes, segmento, canal;
```

---

## 12. Probar la idempotencia

Crea una copia temporal exacta:

```sql
CREATE OR REPLACE TEMP TABLE MART_ANTES_REEJECUCION AS
SELECT *
FROM DB_CURSO.MARTS.VENTAS_MES_SEGMENTO_CANAL;
```

Ejecuta de nuevo la misma sentencia CTAS de la sección anterior.

Compara en ambos sentidos:

```sql
SELECT 'ANTES_MENOS_DESPUES' AS comparacion, COUNT(*) AS diferencias
FROM (
    SELECT *
    FROM MART_ANTES_REEJECUCION

    MINUS

    SELECT *
    FROM DB_CURSO.MARTS.VENTAS_MES_SEGMENTO_CANAL
)

UNION ALL

SELECT 'DESPUES_MENOS_ANTES', COUNT(*)
FROM (
    SELECT *
    FROM DB_CURSO.MARTS.VENTAS_MES_SEGMENTO_CANAL

    MINUS

    SELECT *
    FROM MART_ANTES_REEJECUCION
);
```

Resultado:

```text
0
0
```

Comprueba otra vez:

```sql
SELECT
    COUNT(*) AS filas,
    SUM(importe_total) AS importe_total
FROM DB_CURSO.MARTS.VENTAS_MES_SEGMENTO_CANAL;
```

Resultado:

```text
15
3690.00
```

### Por qué las filas son idénticas

La consulta depende únicamente de:

- Tablas de entrada sin cambios.
- Expresiones deterministas.
- Un watermark calculado desde la propia fuente.

No incluye:

```sql
CURRENT_TIMESTAMP()
```

como columna de la tabla. Un timestamp de ejecución sería distinto en cada reconstrucción y dificultaría demostrar igualdad exacta.

---

## 13. Incorporar un cambio de fuente

Inserta:

```sql
INSERT INTO DB_CURSO.CURATED.VENTAS_MART_BASE
VALUES (
    7027,
    903,
    '2026-03-29',
    'MARKETPLACE',
    105.00,
    'EUR',
    'COMPLETADA',
    '2026-03-29 12:00:00'
);
```

Ejecuta los controles de calidad. Deben seguir en `OK`.

Vuelve a ejecutar la sentencia CTAS.

Comprueba:

```sql
SELECT
    COUNT(*) AS filas,
    SUM(num_ventas) AS ventas,
    SUM(importe_total) AS importe_total
FROM DB_CURSO.MARTS.VENTAS_MES_SEGMENTO_CANAL;
```

Resultado:

| FILAS | VENTAS | IMPORTE_TOTAL |
|---:|---:|---:|
| 16 | 22 | 3795.00 |

Comprueba la nueva combinación:

```sql
SELECT *
FROM DB_CURSO.MARTS.VENTAS_MES_SEGMENTO_CANAL
WHERE mes = '2026-03-01'
  AND segmento = 'PYME'
  AND canal = 'MARKETPLACE';
```

Resultado esperado:

```text
NUM_VENTAS = 1
CLIENTES_UNICOS = 1
IMPORTE_TOTAL = 105.00
TICKET_MEDIO = 105.00
```

---

## 14. Repetir la reconstrucción tras el cambio

Ejecuta una vez más la misma CTAS.

Comprueba:

```sql
SELECT
    COUNT(*) AS filas,
    SUM(num_ventas) AS ventas,
    SUM(importe_total) AS importe_total
FROM DB_CURSO.MARTS.VENTAS_MES_SEGMENTO_CANAL;
```

Debe seguir mostrando:

```text
16 filas
22 ventas
3795.00
```

Comprueba duplicados:

```sql
SELECT
    mes,
    segmento,
    canal,
    COUNT(*) AS apariciones
FROM DB_CURSO.MARTS.VENTAS_MES_SEGMENTO_CANAL
GROUP BY mes, segmento, canal
HAVING COUNT(*) > 1;
```

No debe devolver filas.

---

## 15. Cuándo utilizar esta estrategia

### Reconstrucción completa con CTAS

Adecuada cuando:

- El mart es pequeño o mediano.
- La consulta puede ejecutarse dentro de la ventana disponible.
- La lógica completa es fácil de recalcular.
- Se prioriza simplicidad y reproducibilidad.
- No existen streams dependientes del objeto reemplazado.

### Proceso incremental

Preferible cuando:

- La tabla es muy grande.
- Solo cambia una pequeña fracción.
- Recalcular todo es costoso.
- Existe una clave y un versionado fiables.
- Puede implementarse deduplicación y `MERGE`.
- Se necesita conservar el objeto sin reemplazarlo.

---

## 16. Advertencia sobre streams y CREATE OR REPLACE

Snowflake implementa `CREATE OR REPLACE TABLE` como el reemplazo atómico del objeto.

Sin embargo:

- El objeto anterior se elimina y se crea uno nuevo.
- El change data de la tabla se pierde.
- Los streams que dependan de la tabla pueden quedar obsoletos.
- También pueden quedar obsoletos streams sobre views que usen la tabla.

Por eso, en el siguiente módulo, donde se trabajará con Streams, no debe reemplazarse alegremente una tabla que sea su origen.

---

## 17. Consultar el historial del ejercicio

```sql
SELECT
    query_id,
    query_text,
    start_time,
    total_elapsed_time,
    rows_produced,
    execution_status
FROM TABLE(
    INFORMATION_SCHEMA.QUERY_HISTORY_BY_SESSION(
        RESULT_LIMIT => 100
    )
)
WHERE query_tag = 'M06_E03_MART_IDEMPOTENTE'
ORDER BY start_time;
```

---

## 18. Limpieza opcional

No elimines los objetos si quieres reutilizar el mart.

```sql
DROP TABLE IF EXISTS DB_CURSO.MARTS.VENTAS_MES_INSERT_PRUEBA;
DROP TABLE IF EXISTS DB_CURSO.MARTS.VENTAS_MES_SEGMENTO_CANAL;
DROP VIEW IF EXISTS DB_CURSO.CURATED.V_VENTAS_ENRIQUECIDAS_MART;
DROP TABLE IF EXISTS DB_CURSO.CURATED.VENTAS_MART_BASE;
DROP TABLE IF EXISTS DB_CURSO.CURATED.CLIENTES_MART;

ALTER SESSION UNSET QUERY_TAG;
```

No elimines `DB_CURSO`, `CURATED`, `MARTS` ni `WH_DEV`.

---

## 19. Errores frecuentes

### El control de huérfanos devuelve cero con el cliente 999

Comprueba que utilizas:

```sql
LEFT JOIN clientes
```

y cuentas:

```sql
c.id_cliente IS NULL
```

Un `INNER JOIN` ocultaría la venta huérfana.

---

### El mart contiene 26 ventas

Falta el filtro:

```sql
WHERE es_publicable
```

Solo las ventas completadas deben publicarse.

---

### La segunda ejecución duplica filas

Se está utilizando `INSERT…SELECT` en lugar de:

```sql
CREATE OR REPLACE TABLE ... AS SELECT
```

---

### MINUS devuelve diferencias tras una reejecución

Comprueba que el mart no incluye:

```sql
CURRENT_TIMESTAMP()
```

u otra expresión no determinista.

También comprueba que no modificaste las fuentes entre ambas ejecuciones.

---

### COPY GRANTS produce un error de posición

La sintaxis correcta coloca `COPY GRANTS` antes de `AS`:

```sql
CREATE OR REPLACE TABLE nombre
COPY GRANTS
AS
SELECT ...;
```

---

### COUNT_IF devuelve NULL

Utiliza:

```sql
COALESCE(COUNT_IF(condicion), 0)
```

cuando el control deba mostrar explícitamente cero.

---

## 20. Respuestas a las preguntas de reflexión

### 1. ¿Qué es la granularidad?

Es qué representa una fila. Aquí, una fila representa una combinación de mes, segmento y canal.

### 2. ¿Por qué comprobar unicidad?

Porque dos filas con la misma granularidad harían ambiguas o duplicarían las métricas.

### 3. ¿Por qué reconciliar?

Para demostrar que el proceso no pierde ni duplica ventas o importes.

### 4. ¿Idempotencia técnica y de negocio?

La técnica significa que repetir la operación no produce efectos adicionales. La de negocio significa que las métricas publicadas permanecen coherentes para la misma entrada.

### 5. ¿Por qué evitar un timestamp de ejecución?

Porque cambia en cada ejecución aunque los datos sean idénticos y hace que una comparación exacta falle.

### 6. ¿Ventajas y costes de reconstruir?

Es simple, reproducible y fácil de auditar, pero vuelve a procesar todos los datos y puede consumir más cómputo.

### 7. ¿Controles para BI?

Como mínimo:

- Unicidad de granularidad.
- Nulos en dimensiones.
- Rangos válidos.
- Reconciliación de filas e importes.
- Watermark.
- Frescura.
- Desviaciones frente a periodos anteriores.
- Permisos y políticas de acceso.

---

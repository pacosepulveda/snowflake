# Módulo 4 · Ejercicio 3

# Solución guiada: diseñar un modelo de pedidos

## Resultado que se va a construir

Crearemos un pequeño modelo de pedidos que permita comprobar de forma práctica:

- El ciclo de vida de tablas permanentes, transitorias y temporales.
- La elección de tipos exactos para dinero y tipos temporales para fechas e instantes.
- La generación de identificadores mediante una sequence.
- La posibilidad de que una sequence contenga huecos.
- La diferencia entre constraints declarativos y constraints aplicados por Snowflake.
- El aislamiento de una tabla temporal por sesión.

El modelo utilizará:

```text
DB_CURSO.MODELO.CLIENTES
DB_CURSO.MODELO.PEDIDOS
DB_CURSO.MODELO.PEDIDOS_STAGING
DB_CURSO.MODELO.RESUMEN_SESION
DB_CURSO.MODELO.SEQ_PEDIDO
```

---

# 1. Preparar el entorno

## 1.1. Crear el warehouse

Abre un SQL File nuevo "M4_E3_MODELO_A.sql" en Snowsight.

```sql
USE ROLE SYSADMIN;

CREATE WAREHOUSE IF NOT EXISTS WH_M4_MODELO
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE;
```

### Explicación

- `XSMALL` es suficiente para un ejercicio con pocas filas.
- `AUTO_SUSPEND = 60` limita el consumo cuando el alumno deja de ejecutar consultas.
- `AUTO_RESUME = TRUE` permite reanudar el warehouse automáticamente.
- `INITIALLY_SUSPENDED = TRUE` evita consumo antes de la primera consulta.

---

## 1.2. Crear la base de datos y el esquema

```sql
USE WAREHOUSE WH_M4_MODELO;

CREATE DATABASE IF NOT EXISTS DB_CURSO;
CREATE SCHEMA IF NOT EXISTS DB_CURSO.MODELO;

USE DATABASE DB_CURSO;
USE SCHEMA MODELO;
```

---

## 1.3. Configurar la zona horaria

```sql
ALTER SESSION SET TIMEZONE = 'Europe/Madrid';
```

Comprobamos el contexto:

```sql
SELECT
    CURRENT_ROLE() AS ROL_ACTIVO,
    CURRENT_WAREHOUSE() AS WAREHOUSE_ACTIVO,
    CURRENT_DATABASE() AS BASE_ACTIVA,
    CURRENT_SCHEMA() AS ESQUEMA_ACTIVO,
    CURRENT_TIMESTAMP() AS INSTANTE_ACTUAL,
    CURRENT_SESSION() AS SESSION_ID;
```

Consulta además el parámetro de zona horaria:

```sql
SHOW PARAMETERS LIKE 'TIMEZONE' IN SESSION;
```

### Resultado esperado

| Campo | Valor esperado |
|---|---|
| `ROL_ACTIVO` | `SYSADMIN` |
| `WAREHOUSE_ACTIVO` | `WH_M4_MODELO` |
| `BASE_ACTIVA` | `DB_CURSO` |
| `ESQUEMA_ACTIVO` | `MODELO` |
| `INSTANTE_ACTUAL` | Timestamp mostrado con el offset de la sesión |
| `SESSION_ID` | Identificador de la sesión |
| Parámetro `TIMEZONE` | `Europe/Madrid` |

---

# 2. Crear la sequence

```sql
CREATE OR REPLACE SEQUENCE DB_CURSO.MODELO.SEQ_PEDIDO
    START = 1000
    INCREMENT = 1
    ORDER
    COMMENT = 'Identificadores técnicos de pedidos del laboratorio';
```

## ¿Por qué se especifica ORDER?

`ORDER` hace que los valores se generen en orden creciente para facilitar la observación del ejercicio. No convierte la sequence en una numeración sin huecos.

Incluso con `ORDER`:

- Un valor solicitado y no utilizado queda consumido.
- Un rollback no obliga a reutilizar valores.
- Snowflake no garantiza una secuencia contigua.

La sequence es adecuada para una **clave técnica**, pero no para numeraciones que legalmente deban ser consecutivas y auditables.

Comprobación:

```sql
SHOW SEQUENCES LIKE 'SEQ_PEDIDO'
IN SCHEMA DB_CURSO.MODELO;
```

---

# 3. Crear las tablas permanentes

## 3.1. Tabla CLIENTES

```sql
CREATE OR REPLACE TABLE DB_CURSO.MODELO.CLIENTES (
    ID_CLIENTE NUMBER(10,0) NOT NULL,
    NOMBRE VARCHAR(100) NOT NULL,
    PAIS CHAR(2) NOT NULL,
    FECHA_ALTA DATE NOT NULL,

    CONSTRAINT PK_CLIENTES
        PRIMARY KEY (ID_CLIENTE)
);
```

### Decisiones de diseño

- `NUMBER(10,0)` representa un entero exacto.
- `DATE` es apropiado porque la fecha de alta no necesita hora ni zona horaria.
- La tabla es permanente porque representa datos maestros que deben conservarse.
- `NOT NULL` se declara expresamente para que Snowflake rechace valores nulos.

---

## 3.2. Tabla PEDIDOS

```sql
CREATE OR REPLACE TABLE DB_CURSO.MODELO.PEDIDOS (
    ID_PEDIDO NUMBER(18,0)
        DEFAULT DB_CURSO.MODELO.SEQ_PEDIDO.NEXTVAL
        NOT NULL,

    ID_CLIENTE NUMBER(10,0) NOT NULL,
    FECHA_FACTURA DATE NOT NULL,
    INSTANTE_EVENTO TIMESTAMP_LTZ NOT NULL,
    IMPORTE NUMBER(12,2) NOT NULL,
    ESTADO VARCHAR(20) NOT NULL,
    CREADO_EN TIMESTAMP_LTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),

    CONSTRAINT PK_PEDIDOS
        PRIMARY KEY (ID_PEDIDO),

    CONSTRAINT FK_PEDIDOS_CLIENTES
        FOREIGN KEY (ID_CLIENTE)
        REFERENCES DB_CURSO.MODELO.CLIENTES(ID_CLIENTE),

    CONSTRAINT CK_PEDIDOS_IMPORTE
        CHECK (IMPORTE >= 0),

    CONSTRAINT CK_PEDIDOS_ESTADO
        CHECK (ESTADO IN ('PENDIENTE', 'PAGADO', 'CANCELADO'))
);
```

### Explicación de los tipos

#### ID_PEDIDO

Es una clave técnica exacta. La sequence proporciona un valor por defecto cuando el `INSERT` no incluye la columna.

#### FECHA_FACTURA

Una factura corresponde a una fecha de negocio. No necesita zona horaria, por lo que se utiliza `DATE`.

#### INSTANTE_EVENTO

Representa un momento real en el que ocurrió una operación. `TIMESTAMP_LTZ` guarda el instante y lo muestra utilizando la zona horaria de la sesión.

#### IMPORTE

`NUMBER(12,2)` almacena un valor decimal exacto con dos posiciones decimales. No usamos `FLOAT`, ya que su representación binaria puede introducir aproximaciones.

#### CREADO_EN

Se completa automáticamente con el instante actual de Snowflake.

---

# 4. Crear la tabla transitoria de staging

```sql
CREATE OR REPLACE TRANSIENT TABLE DB_CURSO.MODELO.PEDIDOS_STAGING (
    ID_EXTERNO VARCHAR,
    ID_CLIENTE_TEXTO VARCHAR,
    FECHA_TEXTO VARCHAR,
    INSTANTE_TEXTO VARCHAR,
    IMPORTE_TEXTO VARCHAR,
    ESTADO_TEXTO VARCHAR
)
DATA_RETENTION_TIME_IN_DAYS = 1;
```

## ¿Por qué es transitoria?

Los datos de staging:

- Pueden reconstruirse desde el sistema origen.
- Deben persistir entre sesiones mientras se procesan.
- No necesitan los siete días de Fail-safe de una tabla permanente.

Una tabla transitoria persiste hasta que se elimina, pero no dispone de Fail-safe. Esto reduce el almacenamiento asociado a recuperación para datos que pueden recrearse.

No debe confundirse con una tabla temporal: la tabla de staging debe poder ser utilizada por diferentes sesiones y procesos.

---

# 5. Inspeccionar los objetos y su definición

## 5.1. Mostrar las tablas

```sql
SHOW TABLES IN SCHEMA DB_CURSO.MODELO;
```

En el resultado deben aparecer:

- `CLIENTES`.
- `PEDIDOS`.
- `PEDIDOS_STAGING`.

La interfaz muestra información como el tipo o `kind` y el tiempo de retención.

Para consultar el resultado de `SHOW TABLES` mediante SQL:

```sql
SELECT
    "name" AS NOMBRE,
    "kind" AS TIPO,
    "retention_time" AS RETENCION_DIAS
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
ORDER BY NOMBRE;
```

> Los nombres de columnas devueltos por `SHOW` se escriben entre comillas porque se exponen en minúsculas.

---

## 5.2. Describir PEDIDOS

```sql
DESC TABLE DB_CURSO.MODELO.PEDIDOS;
```

Comprueba especialmente:

- `ID_PEDIDO` como `NUMBER` y con expresión por defecto.
- `FECHA_FACTURA` como `DATE`.
- `INSTANTE_EVENTO` y `CREADO_EN` como `TIMESTAMP_LTZ`.
- `IMPORTE` como `NUMBER(12,2)`.

---

## 5.3. Mostrar las claves

```sql
SHOW PRIMARY KEYS
IN TABLE DB_CURSO.MODELO.PEDIDOS;
```

```sql
SHOW IMPORTED KEYS
IN TABLE DB_CURSO.MODELO.PEDIDOS;
```

Estas instrucciones muestran que las constraints existen en los metadatos. Que una constraint esté declarada no significa necesariamente que Snowflake la aplique en una tabla estándar.

---

## 5.4. Mostrar los CHECK

```sql
SELECT
    CONSTRAINT_NAME,
    CHECK_CLAUSE
FROM DB_CURSO.INFORMATION_SCHEMA.CHECK_CONSTRAINTS
WHERE CONSTRAINT_SCHEMA = 'MODELO'
  AND CONSTRAINT_NAME IN (
      'CK_PEDIDOS_IMPORTE',
      'CK_PEDIDOS_ESTADO'
  )
ORDER BY CONSTRAINT_NAME;
```

---

## 5.5. Recuperar el DDL

```sql
SELECT GET_DDL(
    'TABLE',
    'DB_CURSO.MODELO.PEDIDOS'
) AS DDL_PEDIDOS;
```

`GET_DDL` resulta útil para:

- Revisar la definición efectiva del objeto.
- Comparar entornos.
- Generar scripts de despliegue.
- Auditar defaults y constraints.

---

# 6. Insertar datos válidos

## 6.1. Clientes

```sql
INSERT INTO DB_CURSO.MODELO.CLIENTES (
    ID_CLIENTE,
    NOMBRE,
    PAIS,
    FECHA_ALTA
)
VALUES
    (1, 'Bicicletas Sierra', 'ES', '2026-07-01'),
    (2, 'Ciclos do Atlântico', 'PT', '2026-07-02'),
    (3, 'Vélos du Rhône', 'FR', '2026-07-03');
```

Comprobación:

```sql
SELECT *
FROM DB_CURSO.MODELO.CLIENTES
ORDER BY ID_CLIENTE;
```

---

## 6.2. Pedidos

No incluimos `ID_PEDIDO`, de modo que Snowflake utilizará el valor por defecto asociado a la sequence.

```sql
INSERT INTO DB_CURSO.MODELO.PEDIDOS (
    ID_CLIENTE,
    FECHA_FACTURA,
    INSTANTE_EVENTO,
    IMPORTE,
    ESTADO
)
VALUES
    (
        1,
        '2026-07-10',
        '2026-07-10 08:15:00 +00:00',
        1499.90,
        'PAGADO'
    ),
    (
        2,
        '2026-07-10',
        '2026-07-10 10:30:00 +00:00',
        820.50,
        'PENDIENTE'
    ),
    (
        1,
        '2026-07-11',
        '2026-07-11 14:45:00 +00:00',
        215.75,
        'PAGADO'
    );
```

Consulta:

```sql
SELECT
    ID_PEDIDO,
    ID_CLIENTE,
    FECHA_FACTURA,
    INSTANTE_EVENTO,
    IMPORTE,
    ESTADO,
    CREADO_EN
FROM DB_CURSO.MODELO.PEDIDOS
ORDER BY ID_PEDIDO;
```

### Resultado esperado

- Los tres pedidos reciben identificadores generados automáticamente.
- Con `ORDER`, los primeros valores deberían comenzar en `1000` y aumentar.
- `IMPORTE` conserva dos decimales.
- `INSTANTE_EVENTO` se presenta en `Europe/Madrid`.
- `CREADO_EN` se rellena automáticamente.

Los offsets mostrados dependen de la fecha y de las reglas de horario de verano aplicables a la zona de sesión.

---

# 7. Demostrar los saltos de una sequence

## 7.1. Consultar el máximo actual

```sql
SELECT MAX(ID_PEDIDO) AS MAXIMO_ANTES
FROM DB_CURSO.MODELO.PEDIDOS;
```

Anota el resultado.

---

## 7.2. Consumir un valor sin insertarlo

```sql
SELECT DB_CURSO.MODELO.SEQ_PEDIDO.NEXTVAL
    AS VALOR_CONSUMIDO_SIN_INSERTAR;
```

Ese valor ha sido generado, aunque no se haya almacenado en `PEDIDOS`.

---

## 7.3. Insertar otro pedido

```sql
INSERT INTO DB_CURSO.MODELO.PEDIDOS (
    ID_CLIENTE,
    FECHA_FACTURA,
    INSTANTE_EVENTO,
    IMPORTE,
    ESTADO
)
VALUES (
    3,
    '2026-07-12',
    '2026-07-12 09:00:00 +00:00',
    1250.00,
    'PAGADO'
);
```

Consulta los identificadores:

```sql
SELECT
    ID_PEDIDO,
    ID_CLIENTE,
    IMPORTE,
    ESTADO
FROM DB_CURSO.MODELO.PEDIDOS
ORDER BY ID_PEDIDO;
```

## Conclusión

El valor obtenido mediante `NEXTVAL` no se reutiliza. Por tanto, aparece un hueco entre los identificadores almacenados.

Una sequence garantiza valores técnicos únicos bajo sus condiciones normales de uso, pero Snowflake no garantiza que sean contiguos.

### ¿Sirve para una numeración fiscal sin huecos?

No. Una numeración legal o regulada necesita una estrategia transaccional y de auditoría específica. La sequence es adecuada para claves técnicas, no para prometer ausencia de huecos.

---

# 8. Comprobar los constraints

Ejecuta cada prueba de forma independiente.

## 8.1. Insertar una clave primaria duplicada

```sql
INSERT INTO DB_CURSO.MODELO.PEDIDOS (
    ID_PEDIDO,
    ID_CLIENTE,
    FECHA_FACTURA,
    INSTANTE_EVENTO,
    IMPORTE,
    ESTADO
)
SELECT
    MIN(ID_PEDIDO),
    1,
    '2026-07-13',
    '2026-07-13 10:00:00 +00:00',
    99.90,
    'PAGADO'
FROM DB_CURSO.MODELO.PEDIDOS;
```

### Resultado esperado

La operación se completa.

En una tabla estándar, la clave primaria se conserva como metadato, pero no se aplica para impedir duplicados.

---

## 8.2. Insertar una clave foránea inexistente

```sql
INSERT INTO DB_CURSO.MODELO.PEDIDOS (
    ID_CLIENTE,
    FECHA_FACTURA,
    INSTANTE_EVENTO,
    IMPORTE,
    ESTADO
)
VALUES (
    9999,
    '2026-07-13',
    '2026-07-13 11:00:00 +00:00',
    450.00,
    'PENDIENTE'
);
```

### Resultado esperado

La operación se completa aunque no exista el cliente `9999`.

En tablas estándar, la clave foránea es declarativa y no aplica integridad referencial.

---

## 8.3. Probar NOT NULL

```sql
INSERT INTO DB_CURSO.MODELO.PEDIDOS (
    ID_CLIENTE,
    FECHA_FACTURA,
    INSTANTE_EVENTO,
    IMPORTE,
    ESTADO
)
VALUES (
    NULL,
    '2026-07-13',
    '2026-07-13 12:00:00 +00:00',
    120.00,
    'PAGADO'
);
```

### Resultado esperado

La operación falla porque `ID_CLIENTE` está definido como `NOT NULL`.

---

## 8.4. Probar el CHECK del importe

```sql
INSERT INTO DB_CURSO.MODELO.PEDIDOS (
    ID_CLIENTE,
    FECHA_FACTURA,
    INSTANTE_EVENTO,
    IMPORTE,
    ESTADO
)
VALUES (
    1,
    '2026-07-13',
    '2026-07-13 13:00:00 +00:00',
    -10.00,
    'PAGADO'
);
```

### Resultado esperado

La operación falla al violar `CK_PEDIDOS_IMPORTE`.

---

## 8.5. Probar el CHECK del estado

```sql
INSERT INTO DB_CURSO.MODELO.PEDIDOS (
    ID_CLIENTE,
    FECHA_FACTURA,
    INSTANTE_EVENTO,
    IMPORTE,
    ESTADO
)
VALUES (
    1,
    '2026-07-13',
    '2026-07-13 14:00:00 +00:00',
    75.00,
    'ENVIADO'
);
```

### Resultado esperado

La operación falla porque `ENVIADO` no pertenece al conjunto permitido por `CK_PEDIDOS_ESTADO`.

---

## 8.6. Tabla de resultados

| Prueba | Resultado esperado | Motivo |
|---|---|---|
| Clave primaria duplicada | Aceptada | `PRIMARY KEY` no se aplica en tablas estándar |
| Clave foránea inexistente | Aceptada | `FOREIGN KEY` no se aplica en tablas estándar |
| `NOT NULL` | Rechazada | `NOT NULL` sí se aplica |
| `CHECK` de importe | Rechazada | `CHECK` sí se aplica actualmente |
| `CHECK` de estado | Rechazada | `CHECK` sí se aplica actualmente |

Este comportamiento es diferente del de las Hybrid Tables, donde las claves primaria, única y foránea sí se aplican. Las Hybrid Tables no están disponibles actualmente en las cuentas trial y no se utilizan en este laboratorio.

---

# 9. Detectar problemas de calidad

## 9.1. Identificadores duplicados

```sql
SELECT
    ID_PEDIDO,
    COUNT(*) AS NUM_FILAS
FROM DB_CURSO.MODELO.PEDIDOS
GROUP BY ID_PEDIDO
HAVING COUNT(*) > 1
ORDER BY ID_PEDIDO;
```

La consulta debe detectar el identificador duplicado introducido en la prueba.

---

## 9.2. Pedidos huérfanos

```sql
SELECT
    P.ID_PEDIDO,
    P.ID_CLIENTE,
    P.FECHA_FACTURA,
    P.IMPORTE
FROM DB_CURSO.MODELO.PEDIDOS AS P
LEFT JOIN DB_CURSO.MODELO.CLIENTES AS C
    ON P.ID_CLIENTE = C.ID_CLIENTE
WHERE C.ID_CLIENTE IS NULL
ORDER BY P.ID_PEDIDO;
```

Debe aparecer el pedido del cliente `9999`.

## Lección de diseño

En tablas estándar, declarar claves ayuda a documentar el modelo y a determinadas herramientas, pero no sustituye:

- La validación en pipelines.
- Las pruebas de calidad.
- La reconciliación con sistemas origen.
- Los controles de duplicados y relaciones huérfanas.

---

# 10. Comparar NUMBER y FLOAT

Ejecuta:

```sql
SELECT
    0.1::FLOAT + 0.2::FLOAT
        AS RESULTADO_FLOAT,

    0.1::NUMBER(38,2) + 0.2::NUMBER(38,2)
        AS RESULTADO_NUMBER,

    (0.1::FLOAT + 0.2::FLOAT) = 0.3::FLOAT
        AS FLOAT_ES_IGUAL_A_03;
```

### Resultado esperado

- `RESULTADO_FLOAT` puede mostrar una aproximación como `0.30000000000000004`.
- `RESULTADO_NUMBER` devuelve exactamente `0.30`.
- La comparación exacta del `FLOAT` puede devolver `FALSE`.

## Explicación

`FLOAT` utiliza representación binaria IEEE 754. Muchos decimales habituales no pueden representarse exactamente en binario.

Los errores pequeños pueden acumularse en:

- Sumas de millones de filas.
- Cálculo de intereses.
- Impuestos.
- Conciliaciones.
- Comparaciones exactas.

Para dinero y saldos se utiliza normalmente un tipo fijo como `NUMBER(p,s)` con la escala que requiera el negocio.

---

# 11. Observar TIMESTAMP_LTZ

## 11.1. Consulta en Europe/Madrid

```sql
ALTER SESSION SET TIMEZONE = 'Europe/Madrid';

SELECT
    ID_PEDIDO,
    FECHA_FACTURA,
    INSTANTE_EVENTO,
    CREADO_EN
FROM DB_CURSO.MODELO.PEDIDOS
ORDER BY ID_PEDIDO;
```

Anota la representación de `INSTANTE_EVENTO`.

---

## 11.2. Consulta en UTC

```sql
ALTER SESSION SET TIMEZONE = 'UTC';

SELECT
    ID_PEDIDO,
    FECHA_FACTURA,
    INSTANTE_EVENTO,
    CREADO_EN
FROM DB_CURSO.MODELO.PEDIDOS
ORDER BY ID_PEDIDO;
```

### Qué debe observarse

- `FECHA_FACTURA` no cambia, porque es un `DATE` sin hora ni zona.
- `INSTANTE_EVENTO` cambia su representación al pasar de Madrid a UTC.
- `CREADO_EN`, también `TIMESTAMP_LTZ`, se muestra en la nueva zona.
- El instante lógico almacenado no cambia; cambia la forma de presentarlo según la zona de sesión.

---

## 11.3. Restaurar la zona

```sql
ALTER SESSION SET TIMEZONE = 'Europe/Madrid';
```

## ¿Cuándo usar TIMESTAMP_NTZ?

`TIMESTAMP_NTZ` es apropiado cuando se quiere conservar una fecha y hora de calendario sin convertirla según la zona de sesión, por ejemplo:

- La hora local planificada de apertura de una tienda.
- Una cita expresada deliberadamente como hora local sin zona.
- Un dato heredado cuyo origen no contiene información de zona.

Para un evento real ocurrido en un instante concreto, `TIMESTAMP_LTZ` suele ser una elección más segura.

---

# 12. Crear la tabla temporal

Esta parte se realiza en dos SQL Files.

## 12.1. SQL File A: crear la tabla

Confirma el identificador de sesión:

```sql
SELECT CURRENT_SESSION() AS SESSION_A;
```

Crea la tabla temporal:

```sql
CREATE OR REPLACE TEMPORARY TABLE
    DB_CURSO.MODELO.RESUMEN_SESION AS
SELECT
    ESTADO,
    COUNT(*) AS NUM_PEDIDOS,
    SUM(IMPORTE) AS IMPORTE_TOTAL
FROM DB_CURSO.MODELO.PEDIDOS
GROUP BY ESTADO;
```

Consulta el resultado:

```sql
SELECT *
FROM DB_CURSO.MODELO.RESUMEN_SESION
ORDER BY ESTADO;
```

La tabla existe únicamente dentro de esta sesión.

---

## 12.2. SQL File B: intentar acceder desde otra sesión

Abre un nuevo SQL File "M4_E3_MODELO_B.sql" y ejecuta:

```sql
USE ROLE SYSADMIN;
USE WAREHOUSE WH_M4_MODELO;
USE DATABASE DB_CURSO;
USE SCHEMA MODELO;

SELECT CURRENT_SESSION() AS SESSION_B;
```

El identificador debe ser diferente del obtenido en el SQL File A.

Intenta consultar:

```sql
SELECT *
FROM DB_CURSO.MODELO.RESUMEN_SESION;
```

### Resultado esperado

Snowflake devuelve un error equivalente a:

```text
Object does not exist or not authorized
```

La tabla temporal no es visible fuera de la sesión que la creó.

---

## 12.3. Volver a la SQL File A

```sql
SELECT *
FROM DB_CURSO.MODELO.RESUMEN_SESION
ORDER BY ESTADO;
```

La tabla continúa disponible porque la sesión A sigue activa.

Para eliminarla explícitamente:

```sql
DROP TABLE IF EXISTS DB_CURSO.MODELO.RESUMEN_SESION;
```

Aunque Snowflake la eliminaría al terminar la sesión, el borrado explícito evita mantener almacenamiento temporal innecesario durante sesiones largas.

---

# 13. Recomendación de arquitectura resuelta

Una posible respuesta sería:

> `CLIENTES` y `PEDIDOS` son tablas permanentes porque contienen información maestra y transaccional que debe conservarse y beneficiarse de Time Travel y Fail-safe. `PEDIDOS_STAGING` es transitoria porque sus datos persisten entre sesiones, pero pueden reconstruirse desde el origen y no necesitan Fail-safe. `RESUMEN_SESION` es temporal porque solo sirve como resultado intermedio privado de una sesión. Los importes usan `NUMBER(12,2)` para mantener exactitud decimal y evitar errores acumulativos de `FLOAT`. Los eventos usan `TIMESTAMP_LTZ` porque representan instantes reales que deben mostrarse en la zona horaria del consumidor, mientras que las fechas de factura usan `DATE`. La sequence genera claves técnicas, pero puede producir huecos y no debe emplearse como garantía de numeración legal consecutiva. En tablas estándar, las claves primaria y foránea son declarativas, por lo que deben complementarse con controles de calidad; `NOT NULL` y `CHECK`, en cambio, sí rechazan actualmente datos que no cumplen sus reglas.

---

# 14. Errores frecuentes

## Error: no active warehouse selected

```sql
USE WAREHOUSE WH_M4_MODELO;
```

---

## Error: object does not exist

Comprueba:

```sql
SELECT
    CURRENT_DATABASE(),
    CURRENT_SCHEMA();
```

Utiliza nombres cualificados:

```text
DB_CURSO.MODELO.OBJETO
```

---

## Error al crear la clave foránea

Asegúrate de que:

- `CLIENTES` se ha creado antes que `PEDIDOS`.
- `CLIENTES.ID_CLIENTE` está declarado como clave primaria o única.
- Ambos campos utilizan tipos compatibles.

---

## El ID generado no coincide con el esperado

No bases la solución en un número concreto cuando el ejercicio se ha ejecutado más de una vez. Una sequence conserva su estado hasta que se reemplaza.

El script usa `CREATE OR REPLACE SEQUENCE`, por lo que reinicia la sequence al repetir la preparación completa. No ejecutes ese comando después de haber creado pedidos que quieras conservar.

---

## La tabla temporal aparece en el segundo SQL File

Comprueba los identificadores:

```sql
SELECT CURRENT_SESSION();
```

La prueba requiere dos sesiones diferentes. Si la herramienta reutiliza la misma sesión, abre una nueva conexión independiente o una ventana de incógnito y autentícate de nuevo.

---

## La prueba de clave primaria duplicada falla inesperadamente

Comprueba que se trata de una tabla estándar y no de una Hybrid Table:

```sql
SHOW TABLES LIKE 'PEDIDOS'
IN SCHEMA DB_CURSO.MODELO;
```

Las Hybrid Tables aplican las claves, pero no están disponibles en cuentas trial.

---

## La prueba CHECK no se comporta como material antiguo

La documentación actual de Snowflake indica que los `CHECK` se aplican en tablas estándar. Materiales antiguos pueden afirmar que solo `NOT NULL` se aplicaba; esa afirmación ya no refleja el comportamiento documentado actual.

---


## Precisión importante sobre CHECK

La documentación vigente establece que, en tablas estándar:

- `PRIMARY KEY`: opcional y no enforced.
- `UNIQUE`: opcional y no enforced.
- `FOREIGN KEY`: opcional y no enforced.
- `NOT NULL`: enforced.
- `CHECK`: enforced.

También existe una limitación actual que debe considerarse en módulos posteriores: `COPY INTO` no admite como destino tablas estándar que tengan `CHECK` constraints. Por esa razón, la tabla `PEDIDOS` de este ejercicio no debería reutilizarse como destino directo de la práctica de carga batch del módulo 5.

---

# 15. Control de costes y limpieza

El volumen de datos es mínimo. El coste principal procede del tiempo de actividad del warehouse.

Suspende el warehouse al terminar:

```sql
ALTER WAREHOUSE WH_M4_MODELO SUSPEND;
```

La tabla temporal puede eliminarse explícitamente:

```sql
DROP TABLE IF EXISTS DB_CURSO.MODELO.RESUMEN_SESION;
```

Conserva estos objetos para los siguientes ejercicios del módulo:

```text
DB_CURSO.MODELO.CLIENTES
DB_CURSO.MODELO.PEDIDOS
DB_CURSO.MODELO.PEDIDOS_STAGING
DB_CURSO.MODELO.SEQ_PEDIDO
```

---

# Referencias oficiales

- Tablas temporales y transitorias:  
  https://docs.snowflake.com/en/user-guide/tables-temp-transient

- CREATE SEQUENCE:  
  https://docs.snowflake.com/en/sql-reference/sql/create-sequence

- Uso y semántica de sequences:  
  https://docs.snowflake.com/en/user-guide/querying-sequences

- Constraints y diferencias entre tablas estándar e Hybrid Tables:  
  https://docs.snowflake.com/en/sql-reference/constraints-overview

- Tipos numéricos:  
  https://docs.snowflake.com/en/sql-reference/data-types-numeric

- Tipos de fecha y hora:  
  https://docs.snowflake.com/en/sql-reference/data-types-datetime

- Cuentas trial y limitaciones actuales:  
  https://docs.snowflake.com/en/user-guide/admin-trial-account

# Módulo 2 - Ejercicio 1 - Solución guiada

## Preparación y validación de un entorno de trabajo en Snowflake

**Cuenta prevista:** Snowflake Trial, edición Enterprise  
**Interfaz:** Snowsight  
**Fecha de validación documental:** 16 de julio de 2026

---

## 1. Resultado que vamos a construir

Al finalizar tendremos esta estructura:

```text
WH_LAB_M2

DB_CURSO
├── STAGING
├── CURATED
│   └── VENTAS
└── MARTS
    └── V_VENTAS_DIARIAS
```

El warehouse será X-Small, tendrá reanudación automática y se suspenderá después de 60 segundos de inactividad.

> Snowflake es un servicio SaaS con actualizaciones continuas. No se selecciona manualmente una versión del motor. Durante el ejercicio consultaremos `CURRENT_VERSION()` para identificar la versión que está ejecutando la cuenta en ese momento.

---

## 2. Crear y nombrer el SQL File

1. Accede a Snowsight.
2. Abre **Projects** -> **Workspaces**.
3. Crea un SQL File.
4. Cámbiale el nombre a `M2_E1_PREPARACION_ENTORNO`.

La ubicación exacta de algunos botones puede cambiar porque Snowsight evoluciona, pero todo el ejercicio se realiza mediante SQL y no depende de asistentes gráficos.

---

## 3. Seleccionar el rol de trabajo

Ejecuta:

```sql
USE ROLE SYSADMIN;
```

Comprueba el rol activo:

```sql
SELECT CURRENT_ROLE() AS ROL_ACTUAL;
```

Resultado esperado:

```text
SYSADMIN
```

### Explicación

`SYSADMIN` es el rol del sistema pensado para crear y administrar warehouses y objetos de datos. Evitamos trabajar habitualmente con `ACCOUNTADMIN` porque tiene privilegios administrativos muy amplios.

Si aparece un error al seleccionar `SYSADMIN`, comprueba que has iniciado sesión con el usuario administrador creado durante el alta de la cuenta trial.

---

## 4. Crear el virtual warehouse

Ejecuta:

```sql
CREATE WAREHOUSE IF NOT EXISTS WH_LAB_M2
    WAREHOUSE_SIZE = XSMALL
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE
    COMMENT = 'Warehouse del laboratorio del modulo 2';
```

Selecciona explícitamente el warehouse:

```sql
USE WAREHOUSE WH_LAB_M2;
```

Comprueba cuál está activo:

```sql
SELECT CURRENT_WAREHOUSE() AS WAREHOUSE_ACTUAL;
```

### Qué significa cada propiedad

- `WAREHOUSE_SIZE = XSMALL`: utiliza el tamaño más pequeño adecuado para este laboratorio.
- `AUTO_SUSPEND = 60`: solicita la suspensión después de 60 segundos sin actividad.
- `AUTO_RESUME = TRUE`: una consulta puede reanudar automáticamente el warehouse.
- `INITIALLY_SUSPENDED = TRUE`: el warehouse se crea sin empezar a consumir cómputo inmediatamente.
- `COMMENT`: documenta la finalidad del objeto.

Snowflake comprueba periódicamente la inactividad, por lo que la suspensión no tiene por qué producirse exactamente en el segundo 60.

### Verificación

```sql
SHOW WAREHOUSES LIKE 'WH_LAB_M2';
```

En la cuadrícula de resultados comprueba, al menos:

- `name`: `WH_LAB_M2`
- `size`: `X-Small`
- `auto_suspend`: `60`
- `auto_resume`: `true`

> El primer `INSERT` o `SELECT` que necesite cómputo reanudará automáticamente el warehouse.

---

## 5. Crear la base de datos y los esquemas

Ejecuta:

```sql
CREATE DATABASE IF NOT EXISTS DB_CURSO
    COMMENT = 'Base de datos utilizada en el curso de Snowflake';

CREATE SCHEMA IF NOT EXISTS DB_CURSO.STAGING
    COMMENT = 'Datos recibidos desde los sistemas de origen';

CREATE SCHEMA IF NOT EXISTS DB_CURSO.CURATED
    COMMENT = 'Datos limpios y preparados para su uso';

CREATE SCHEMA IF NOT EXISTS DB_CURSO.MARTS
    COMMENT = 'Objetos orientados al consumo analitico';
```

### Explicación

La jerarquía principal es:

```text
DATABASE → SCHEMA → TABLE/VIEW
```

La separación en `STAGING`, `CURATED` y `MARTS` permite distinguir la función de cada objeto y facilita que los módulos posteriores reutilicen el mismo entorno.

### Verificación

```sql
SHOW SCHEMAS IN DATABASE DB_CURSO;
```

Además de los tres esquemas creados, también verás normalmente:

- `PUBLIC`
- `INFORMATION_SCHEMA`

Son esquemas que Snowflake crea automáticamente.

---

## 6. Fijar el contexto de sesión

Aunque utilizaremos nombres totalmente cualificados en los puntos importantes, es una buena práctica fijar el contexto al principio de cada worksheet.

```sql
USE ROLE SYSADMIN;
USE WAREHOUSE WH_LAB_M2;
USE DATABASE DB_CURSO;
USE SCHEMA CURATED;
```

Comprueba el contexto completo:

```sql
SELECT
    CURRENT_USER()      AS USUARIO_ACTUAL,
    CURRENT_ROLE()      AS ROL_ACTUAL,
    CURRENT_WAREHOUSE() AS WAREHOUSE_ACTUAL,
    CURRENT_DATABASE()  AS BASE_DATOS_ACTUAL,
    CURRENT_SCHEMA()    AS ESQUEMA_ACTUAL,
    CURRENT_VERSION()   AS VERSION_SNOWFLAKE;
```

Resultado esperado para las columnas de contexto:

| Columna | Valor esperado |
|---|---|
| `ROL_ACTUAL` | `SYSADMIN` |
| `WAREHOUSE_ACTUAL` | `WH_LAB_M2` |
| `BASE_DATOS_ACTUAL` | `DB_CURSO` |
| `ESQUEMA_ACTUAL` | `CURATED` |

El usuario y la versión dependerán de cada cuenta.

### Por qué conviene fijar el contexto

Sin un contexto explícito, una instrucción como:

```sql
SELECT * FROM VENTAS;
```

podría buscar la tabla en una base de datos o un esquema diferentes. El nombre totalmente cualificado evita esa ambigüedad:

```sql
SELECT * FROM DB_CURSO.CURATED.VENTAS;
```

---

## 7. Crear la tabla de ventas

Ejecuta:

```sql
CREATE OR REPLACE TABLE DB_CURSO.CURATED.VENTAS (
    ID_VENTA NUMBER(18,0) NOT NULL,
    FECHA    DATE         NOT NULL,
    CLIENTE  VARCHAR(100) NOT NULL,
    REGION   VARCHAR(50)  NOT NULL,
    IMPORTE  NUMBER(12,2) NOT NULL
)
COMMENT = 'Ventas de prueba utilizadas en los laboratorios del curso';
```

### Explicación de los tipos

- `NUMBER(18,0)`: número entero con capacidad suficiente para un identificador.
- `DATE`: almacena una fecha sin componente horario.
- `VARCHAR`: texto de longitud variable.
- `NUMBER(12,2)`: número decimal exacto con dos posiciones decimales, apropiado para importes.
- `NOT NULL`: impide insertar un valor nulo en la columna.

No añadimos todavía una clave primaria. Las restricciones y su comportamiento específico en Snowflake se tratarán con más detalle en el módulo de modelo de datos.

### Comprobar la definición

```sql
DESCRIBE TABLE DB_CURSO.CURATED.VENTAS;
```

Verifica los nombres, tipos y valores de la columna `null?`.

---

## 8. Insertar los datos de prueba

Ejecuta:

```sql
INSERT INTO DB_CURSO.CURATED.VENTAS
    (ID_VENTA, FECHA, CLIENTE, REGION, IMPORTE)
VALUES
    (1, '2026-07-01', 'Alba Norte SL',      'NORTE',  245.50),
    (2, '2026-07-01', 'Comercial Levante',  'ESTE',   890.00),
    (3, '2026-07-01', 'Sur Distribuciones', 'SUR',    120.75),
    (4, '2026-07-02', 'Alba Norte SL',      'NORTE', 1350.00),
    (5, '2026-07-02', 'Centro Market',      'CENTRO', 475.25),
    (6, '2026-07-03', 'Costa Retail',       'ESTE',   620.40),
    (7, '2026-07-03', 'Sur Distribuciones', 'SUR',    310.00),
    (8, '2026-07-03', 'Meseta Online',      'CENTRO', 780.10);
```

Snowflake debe mostrar que se han insertado ocho filas.

### Comprobar los datos

```sql
SELECT *
FROM DB_CURSO.CURATED.VENTAS
ORDER BY FECHA, ID_VENTA;
```

---

## 9. Validar las condiciones del enunciado

### 9.1 Número total de filas

```sql
SELECT COUNT(*) AS NUMERO_VENTAS
FROM DB_CURSO.CURATED.VENTAS;
```

Resultado esperado:

```text
8
```

### 9.2 Importe total

```sql
SELECT SUM(IMPORTE) AS IMPORTE_TOTAL
FROM DB_CURSO.CURATED.VENTAS;
```

Resultado esperado:

```text
4792.00
```

### 9.3 Total por región

```sql
SELECT
    REGION,
    COUNT(*)     AS NUMERO_VENTAS,
    SUM(IMPORTE) AS IMPORTE_TOTAL
FROM DB_CURSO.CURATED.VENTAS
GROUP BY REGION
ORDER BY REGION;
```

Resultado esperado:

| Región | Número de ventas | Importe total |
|---|---:|---:|
| CENTRO | 2 | 1255.35 |
| ESTE | 2 | 1510.40 |
| NORTE | 2 | 1595.50 |
| SUR | 2 | 430.75 |

### 9.4 Ventas superiores a 500

```sql
SELECT
    ID_VENTA,
    FECHA,
    CLIENTE,
    REGION,
    IMPORTE
FROM DB_CURSO.CURATED.VENTAS
WHERE IMPORTE > 500
ORDER BY IMPORTE DESC;
```

Resultado esperado: cuatro filas, encabezadas por la venta de `1350.00`.

### 9.5 Validación adicional de diversidad

```sql
SELECT
    COUNT(DISTINCT FECHA)   AS FECHAS_DIFERENTES,
    COUNT(DISTINCT REGION)  AS REGIONES_DIFERENTES,
    COUNT(DISTINCT CLIENTE) AS CLIENTES_DIFERENTES,
    MAX(IMPORTE)            AS IMPORTE_MAXIMO
FROM DB_CURSO.CURATED.VENTAS;
```

Resultado esperado:

| Fechas | Regiones | Clientes | Importe máximo |
|---:|---:|---:|---:|
| 3 | 4 | 6 | 1350.00 |

---

## 10. Crear la vista analítica

Ejecuta:

```sql
CREATE OR REPLACE VIEW DB_CURSO.MARTS.V_VENTAS_DIARIAS AS
SELECT
    FECHA,
    COUNT(*)          AS NUMERO_VENTAS,
    SUM(IMPORTE)      AS IMPORTE_TOTAL,
    AVG(IMPORTE)      AS IMPORTE_MEDIO
FROM DB_CURSO.CURATED.VENTAS
GROUP BY FECHA;
```

### Explicación

La vista no almacena una copia independiente de los datos. Conserva la definición de la consulta y obtiene el resultado a partir de `CURATED.VENTAS` cuando se consulta.

El objeto se crea en `MARTS` porque está orientado al consumo analítico, mientras que los datos detallados permanecen en `CURATED`.

### Consultar la vista

```sql
SELECT
    FECHA,
    NUMERO_VENTAS,
    IMPORTE_TOTAL,
    ROUND(IMPORTE_MEDIO, 2) AS IMPORTE_MEDIO
FROM DB_CURSO.MARTS.V_VENTAS_DIARIAS
ORDER BY FECHA;
```

Resultado esperado:

| Fecha | Número de ventas | Importe total | Importe medio |
|---|---:|---:|---:|
| 2026-07-01 | 3 | 1256.25 | 418.75 |
| 2026-07-02 | 2 | 1825.25 | 912.63 |
| 2026-07-03 | 3 | 1710.50 | 570.17 |

La suma de los importes diarios debe coincidir con el total global de `4792.00`.

---

## 11. Verificar los objetos

### 11.1 Warehouse

```sql
SHOW WAREHOUSES LIKE 'WH_LAB_M2';
```

### 11.2 Esquemas

```sql
SHOW SCHEMAS IN DATABASE DB_CURSO;
```

### 11.3 Tablas del esquema CURATED

```sql
SHOW TABLES IN SCHEMA DB_CURSO.CURATED;
```

Debe aparecer `VENTAS`.

### 11.4 Vistas del esquema MARTS

```sql
SHOW VIEWS IN SCHEMA DB_CURSO.MARTS;
```

Debe aparecer `V_VENTAS_DIARIAS`.

### 11.5 Estructura de la tabla

```sql
DESCRIBE TABLE DB_CURSO.CURATED.VENTAS;
```

---

## 12. Suspender el warehouse

Cuando hayas terminado:

```sql
ALTER WAREHOUSE WH_LAB_M2 SUSPEND;
```

Verifica su estado:

```sql
SHOW WAREHOUSES LIKE 'WH_LAB_M2';
```

El estado debe aparecer como `SUSPENDED`.

No elimines `DB_CURSO`, sus esquemas, la tabla ni la vista, porque se reutilizarán en los módulos siguientes.

---

## 13. Script completo

El siguiente bloque permite reproducir el ejercicio de principio a fin. Se incluye como referencia después de haber trabajado cada paso por separado.

```sql
USE ROLE SYSADMIN;

CREATE WAREHOUSE IF NOT EXISTS WH_LAB_M2
    WAREHOUSE_SIZE = XSMALL
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE
    COMMENT = 'Warehouse del laboratorio del modulo 2';

USE WAREHOUSE WH_LAB_M2;

CREATE DATABASE IF NOT EXISTS DB_CURSO
    COMMENT = 'Base de datos utilizada en el curso de Snowflake';

CREATE SCHEMA IF NOT EXISTS DB_CURSO.STAGING
    COMMENT = 'Datos recibidos desde los sistemas de origen';

CREATE SCHEMA IF NOT EXISTS DB_CURSO.CURATED
    COMMENT = 'Datos limpios y preparados para su uso';

CREATE SCHEMA IF NOT EXISTS DB_CURSO.MARTS
    COMMENT = 'Objetos orientados al consumo analitico';

USE DATABASE DB_CURSO;
USE SCHEMA CURATED;

SELECT
    CURRENT_USER()      AS USUARIO_ACTUAL,
    CURRENT_ROLE()      AS ROL_ACTUAL,
    CURRENT_WAREHOUSE() AS WAREHOUSE_ACTUAL,
    CURRENT_DATABASE()  AS BASE_DATOS_ACTUAL,
    CURRENT_SCHEMA()    AS ESQUEMA_ACTUAL,
    CURRENT_VERSION()   AS VERSION_SNOWFLAKE;

CREATE OR REPLACE TABLE DB_CURSO.CURATED.VENTAS (
    ID_VENTA NUMBER(18,0) NOT NULL,
    FECHA    DATE         NOT NULL,
    CLIENTE  VARCHAR(100) NOT NULL,
    REGION   VARCHAR(50)  NOT NULL,
    IMPORTE  NUMBER(12,2) NOT NULL
)
COMMENT = 'Ventas de prueba utilizadas en los laboratorios del curso';

INSERT INTO DB_CURSO.CURATED.VENTAS
    (ID_VENTA, FECHA, CLIENTE, REGION, IMPORTE)
VALUES
    (1, '2026-07-01', 'Alba Norte SL',      'NORTE',  245.50),
    (2, '2026-07-01', 'Comercial Levante',  'ESTE',   890.00),
    (3, '2026-07-01', 'Sur Distribuciones', 'SUR',    120.75),
    (4, '2026-07-02', 'Alba Norte SL',      'NORTE', 1350.00),
    (5, '2026-07-02', 'Centro Market',      'CENTRO', 475.25),
    (6, '2026-07-03', 'Costa Retail',       'ESTE',   620.40),
    (7, '2026-07-03', 'Sur Distribuciones', 'SUR',    310.00),
    (8, '2026-07-03', 'Meseta Online',      'CENTRO', 780.10);

CREATE OR REPLACE VIEW DB_CURSO.MARTS.V_VENTAS_DIARIAS AS
SELECT
    FECHA,
    COUNT(*)     AS NUMERO_VENTAS,
    SUM(IMPORTE) AS IMPORTE_TOTAL,
    AVG(IMPORTE) AS IMPORTE_MEDIO
FROM DB_CURSO.CURATED.VENTAS
GROUP BY FECHA;

SELECT *
FROM DB_CURSO.CURATED.VENTAS
ORDER BY FECHA, ID_VENTA;

SELECT
    REGION,
    COUNT(*)     AS NUMERO_VENTAS,
    SUM(IMPORTE) AS IMPORTE_TOTAL
FROM DB_CURSO.CURATED.VENTAS
GROUP BY REGION
ORDER BY REGION;

SELECT
    FECHA,
    NUMERO_VENTAS,
    IMPORTE_TOTAL,
    ROUND(IMPORTE_MEDIO, 2) AS IMPORTE_MEDIO
FROM DB_CURSO.MARTS.V_VENTAS_DIARIAS
ORDER BY FECHA;

SHOW WAREHOUSES LIKE 'WH_LAB_M2';
SHOW SCHEMAS IN DATABASE DB_CURSO;
SHOW TABLES IN SCHEMA DB_CURSO.CURATED;
SHOW VIEWS IN SCHEMA DB_CURSO.MARTS;
DESCRIBE TABLE DB_CURSO.CURATED.VENTAS;

ALTER WAREHOUSE WH_LAB_M2 SUSPEND;
```

---

## 14. Problemas frecuentes

### `Insufficient privileges`

Causa probable: la worksheet está usando un rol distinto de `SYSADMIN`.

```sql
USE ROLE SYSADMIN;
```

### `No active warehouse selected in the current session`

```sql
USE WAREHOUSE WH_LAB_M2;
```

### `Object does not exist or not authorized`

Comprueba el contexto:

```sql
SELECT
    CURRENT_ROLE(),
    CURRENT_WAREHOUSE(),
    CURRENT_DATABASE(),
    CURRENT_SCHEMA();
```

También puedes utilizar el nombre completo del objeto:

```sql
SELECT * FROM DB_CURSO.CURATED.VENTAS;
```

### El warehouse tarda en quedar suspendido

`AUTO_SUSPEND` no funciona como un cronómetro exacto. Snowflake revisa periódicamente la inactividad. Para terminar el laboratorio sin esperar:

```sql
ALTER WAREHOUSE WH_LAB_M2 SUSPEND;
```

### El `INSERT` se ejecuta dos veces

La tabla contendrá filas duplicadas. Para restaurar el estado del ejercicio:

```sql
TRUNCATE TABLE DB_CURSO.CURATED.VENTAS;
```

Después, vuelve a ejecutar una sola vez el `INSERT`.

---

## 15. Confirmación de compatibilidad con la cuenta trial

Este ejercicio es compatible con una cuenta Snowflake Trial y con la plataforma actual por las siguientes razones:

1. La documentación oficial de cuentas trial confirma que permiten iniciar virtual warehouses, cargar datos y ejecutar consultas mientras exista saldo de uso gratuito.
2. Todos los objetos utilizados son básicos: warehouse, database, schema, table y view.
3. No se utiliza ninguna característica restringida a una cuenta de pago ni ninguna integración externa.
4. La sintaxis actual de `CREATE WAREHOUSE` admite `XSMALL`, `AUTO_SUSPEND`, `AUTO_RESUME` e `INITIALLY_SUSPENDED`.
5. `SYSADMIN` dispone por defecto del privilegio para crear warehouses; el usuario administrador de una cuenta trial puede seleccionar este rol.
6. El volumen de datos es mínimo y el warehouse se suspende automáticamente, por lo que el consumo del saldo trial es muy pequeño.
7. El ejercicio funcionaría también en una trial Standard; la edición Enterprise indicada para el curso no introduce ninguna incompatibilidad.

La trial finaliza cuando se alcanza su fecha de caducidad o se agota el saldo gratuito, lo que ocurra primero. El importe promocional exacto puede depender de la oferta aplicada al crear la cuenta; en este curso se parte de cuentas que muestran 400 USD de crédito.

---

## 16. Referencias oficiales consultadas

- [Snowflake Documentation - Trial accounts](https://docs.snowflake.com/en/user-guide/admin-trial-account)
- [Snowflake Documentation - CREATE WAREHOUSE](https://docs.snowflake.com/en/sql-reference/sql/create-warehouse)
- [Snowflake Documentation - CREATE DATABASE](https://docs.snowflake.com/en/sql-reference/sql/create-database)
- [Snowflake Documentation - CURRENT_ROLE](https://docs.snowflake.com/en/sql-reference/functions/current_role)
- [Snowflake Documentation - CURRENT_WAREHOUSE](https://docs.snowflake.com/en/sql-reference/functions/current_warehouse)


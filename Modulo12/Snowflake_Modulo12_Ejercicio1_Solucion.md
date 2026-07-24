# Módulo 12 · Ejercicio 1

## Solución guiada: Secure Data Sharing y Native Apps

> **Cuenta:** trial actual de Snowflake

---

# 1. Preparar el warehouse y guardar el usuario

```sql
SET LAB_USER = CURRENT_USER();

USE ROLE SYSADMIN;

CREATE WAREHOUSE IF NOT EXISTS WH_M12_ECOSYSTEM
    WAREHOUSE_SIZE = XSMALL
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE;

ALTER SESSION SET QUERY_TAG = 'M12_E01_DATA_PRODUCTS';
```

---

# Parte 1. Consumer de datos compartidos

## 2. Crear el rol consumidor

```sql
USE ROLE SECURITYADMIN;

CREATE ROLE IF NOT EXISTS M12_SHARED_DATA_CONSUMER;

GRANT ROLE M12_SHARED_DATA_CONSUMER
TO USER IDENTIFIER($LAB_USER);

GRANT USAGE
ON WAREHOUSE WH_M12_ECOSYSTEM
TO ROLE M12_SHARED_DATA_CONSUMER;
```

Concede acceso a la imported database:

```sql
USE ROLE ACCOUNTADMIN;

GRANT IMPORTED PRIVILEGES
ON DATABASE SNOWFLAKE_SAMPLE_DATA
TO ROLE M12_SHARED_DATA_CONSUMER;
```

Si la base no existe:

```sql
CREATE DATABASE SNOWFLAKE_SAMPLE_DATA
FROM SHARE SFC_SAMPLES.SAMPLE_DATA;
```

Después repite el grant.

---

## 3. Consultar datos compartidos

```sql
USE ROLE M12_SHARED_DATA_CONSUMER;
USE SECONDARY ROLES NONE;
USE WAREHOUSE WH_M12_ECOSYSTEM;
```

```sql
SELECT
    c_custkey,
    c_name,
    c_mktsegment,
    c_acctbal
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.CUSTOMER
ORDER BY c_custkey
LIMIT 10;
```

Comprueba el origen:

```sql
SHOW DATABASES LIKE 'SNOWFLAKE_SAMPLE_DATA'
->>
SELECT
    "name",
    "origin",
    "owner",
    "comment"
FROM $1;
```

`ORIGIN` identifica al provider de la imported database.

Prueba negativa:

```sql
UPDATE SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.CUSTOMER
SET c_comment = 'NO'
WHERE c_custkey = 1;
```

Debe fallar porque una imported database es de solo lectura.

Interpretación:

```text
Provider
    conserva y paga el almacenamiento compartido

Consumer
    paga el warehouse que ejecuta las consultas

Copia local creada con CTAS
    sí consume almacenamiento del consumer
```

---

# Parte 2. Crear el producto de datos

## 4. Crear la base provider

```sql
USE ROLE SYSADMIN;
USE WAREHOUSE WH_M12_ECOSYSTEM;

DROP DATABASE IF EXISTS DB_M12_PROVIDER;

CREATE DATABASE DB_M12_PROVIDER;
CREATE SCHEMA DB_M12_PROVIDER.PRIVATE;
CREATE SCHEMA DB_M12_PROVIDER.PUBLISHED;
```

Tabla:

```sql
CREATE TABLE DB_M12_PROVIDER.PRIVATE.VENTAS (
    id_venta       NUMBER(18,0),
    fecha          DATE,
    region         VARCHAR(20),
    cliente_email  VARCHAR(200),
    producto       VARCHAR(50),
    importe        NUMBER(12,2),
    coste_interno  NUMBER(12,2),
    estado         VARCHAR(20)
);
```

Datos:

```sql
INSERT INTO DB_M12_PROVIDER.PRIVATE.VENTAS
SELECT
    column1::NUMBER,
    column2::DATE,
    column3::VARCHAR,
    column4::VARCHAR,
    column5::VARCHAR,
    column6::NUMBER(12,2),
    column7::NUMBER(12,2),
    column8::VARCHAR
FROM VALUES
    (30001, '2026-07-01', 'NORTE', 'ana@example.com',
     'PORTATIL', 120.00, 80.00, 'COMPLETADA'),

    (30002, '2026-07-01', 'SUR', 'bea@example.com',
     'MONITOR', 250.00, 180.00, 'COMPLETADA'),

    (30003, '2026-07-02', 'ESTE', 'carlos@example.com',
     'TECLADO', 80.00, 45.00, 'COMPLETADA'),

    (30004, '2026-07-02', 'OESTE', 'diana@example.com',
     'PORTATIL', 310.00, 220.00, 'COMPLETADA'),

    (30005, '2026-07-03', 'NORTE', 'elena@example.com',
     'MONITOR', 150.00, 100.00, 'COMPLETADA'),

    (30006, '2026-07-03', 'SUR', 'fernando@example.com',
     'TECLADO', 95.00, 55.00, 'COMPLETADA'),

    (30007, '2026-07-04', 'ESTE', 'gema@example.com',
     'MONITOR', 180.00, 125.00, 'COMPLETADA'),

    (30008, '2026-07-04', 'OESTE', 'hugo@example.com',
     'PORTATIL', 220.00, 150.00, 'COMPLETADA');
```

Valida:

```sql
SELECT
    COUNT(*) AS ventas,
    COUNT(DISTINCT region) AS regiones,
    SUM(importe) AS importe_total
FROM DB_M12_PROVIDER.PRIVATE.VENTAS;
```

Resultado:

```text
8
4
1405.00
```

---

## 5. Crear la secure view

```sql
CREATE SECURE VIEW
    DB_M12_PROVIDER.PUBLISHED.V_VENTAS_REGION
AS
SELECT
    region,
    COUNT(*) AS num_ventas,
    SUM(importe)::NUMBER(20,2) AS importe_total,
    AVG(importe)::NUMBER(12,2) AS ticket_medio
FROM DB_M12_PROVIDER.PRIVATE.VENTAS
WHERE estado = 'COMPLETADA'
GROUP BY region;
```

```sql
SELECT *
FROM DB_M12_PROVIDER.PUBLISHED.V_VENTAS_REGION
ORDER BY region;
```

La view expone el contrato analítico, no emails, costes ni filas individuales.

---

## 6. Crear el database role

```sql
CREATE DATABASE ROLE
    DB_M12_PROVIDER.DR_SHARED_ANALYST;
```

```sql
GRANT USAGE
ON SCHEMA DB_M12_PROVIDER.PUBLISHED
TO DATABASE ROLE
    DB_M12_PROVIDER.DR_SHARED_ANALYST;
```

```sql
GRANT SELECT
ON VIEW DB_M12_PROVIDER.PUBLISHED.V_VENTAS_REGION
TO DATABASE ROLE
    DB_M12_PROVIDER.DR_SHARED_ANALYST;
```

No añadas future grants: un database role concedido a un share no los admite.

---

## 7. Validar localmente

```sql
USE ROLE SECURITYADMIN;

CREATE ROLE IF NOT EXISTS M12_SHARE_VALIDATOR;

GRANT ROLE M12_SHARE_VALIDATOR
TO USER IDENTIFIER($LAB_USER);

GRANT USAGE
ON WAREHOUSE WH_M12_ECOSYSTEM
TO ROLE M12_SHARE_VALIDATOR;
```

Conecta el database role:

```sql
USE ROLE SYSADMIN;

GRANT DATABASE ROLE
    DB_M12_PROVIDER.DR_SHARED_ANALYST
TO ROLE M12_SHARE_VALIDATOR;
```

Prueba:

```sql
USE ROLE M12_SHARE_VALIDATOR;
USE SECONDARY ROLES NONE;
USE WAREHOUSE WH_M12_ECOSYSTEM;
```

Permitido:

```sql
SELECT *
FROM DB_M12_PROVIDER.PUBLISHED.V_VENTAS_REGION
ORDER BY region;
```

Debe fallar:

```sql
SELECT *
FROM DB_M12_PROVIDER.PRIVATE.VENTAS;
```

---

## 8. Crear el share

Las trials actuales pueden compartir directamente con cuentas concretas, aunque no pueden publicar en Marketplace.

```sql
USE ROLE ACCOUNTADMIN;

DROP SHARE IF EXISTS SHARE_M12_VENTAS;

CREATE SHARE SHARE_M12_VENTAS
    COMMENT = 'Producto regional de ventas M12';
```

Incluye la base y el database role:

```sql
GRANT USAGE
ON DATABASE DB_M12_PROVIDER
TO SHARE SHARE_M12_VENTAS;
```

```sql
GRANT DATABASE ROLE
    DB_M12_PROVIDER.DR_SHARED_ANALYST
TO SHARE SHARE_M12_VENTAS;
```

Comprueba:

```sql
SHOW SHARES LIKE 'SHARE_M12_VENTAS';

DESCRIBE SHARE SHARE_M12_VENTAS;

SHOW GRANTS TO SHARE SHARE_M12_VENTAS;

SHOW GRANTS OF SHARE SHARE_M12_VENTAS;
```

No añadas cuentas inventadas.

---

# Parte 3. Native App

## 9. Crear los roles de la app

```sql
USE ROLE SECURITYADMIN;

CREATE ROLE IF NOT EXISTS M12_NATIVE_APP_PROVIDER;
CREATE ROLE IF NOT EXISTS M12_APP_CONSUMER;

GRANT ROLE M12_NATIVE_APP_PROVIDER
TO ROLE SYSADMIN;

GRANT ROLE M12_NATIVE_APP_PROVIDER
TO USER IDENTIFIER($LAB_USER);

GRANT ROLE M12_APP_CONSUMER
TO USER IDENTIFIER($LAB_USER);

GRANT USAGE
ON WAREHOUSE WH_M12_ECOSYSTEM
TO ROLE M12_NATIVE_APP_PROVIDER;

GRANT USAGE
ON WAREHOUSE WH_M12_ECOSYSTEM
TO ROLE M12_APP_CONSUMER;
```

Privilegios de desarrollo:

```sql
USE ROLE ACCOUNTADMIN;

GRANT CREATE APPLICATION PACKAGE
ON ACCOUNT
TO ROLE M12_NATIVE_APP_PROVIDER;

GRANT CREATE APPLICATION
ON ACCOUNT
TO ROLE M12_NATIVE_APP_PROVIDER;
```

---

## 10. Crear el package y los stages

```sql
USE ROLE M12_NATIVE_APP_PROVIDER;
USE SECONDARY ROLES NONE;

DROP APPLICATION IF EXISTS APP_M12_SALES_INSIGHTS;

DROP APPLICATION PACKAGE IF EXISTS
    PKG_M12_SALES_INSIGHTS;
```

```sql
CREATE APPLICATION PACKAGE
    PKG_M12_SALES_INSIGHTS;

CREATE SCHEMA
    PKG_M12_SALES_INSIGHTS.STAGE_CONTENT;
```

```sql
CREATE STAGE
    PKG_M12_SALES_INSIGHTS.STAGE_CONTENT.APP_STAGE_V1
    DIRECTORY = (ENABLE = TRUE);

CREATE STAGE
    PKG_M12_SALES_INSIGHTS.STAGE_CONTENT.APP_STAGE_V2
    DIRECTORY = (ENABLE = TRUE);
```

Descomprime el ZIP y sube a la raíz de `APP_STAGE_V1`:

```text
manifest.yml
setup.sql
README.md
```

Comprueba:

```sql
LIST
@PKG_M12_SALES_INSIGHTS.STAGE_CONTENT.APP_STAGE_V1;
```

---

## 11. Instalar V1

```sql
CREATE APPLICATION APP_M12_SALES_INSIGHTS
FROM APPLICATION PACKAGE PKG_M12_SALES_INSIGHTS
USING
    '@PKG_M12_SALES_INSIGHTS.STAGE_CONTENT.APP_STAGE_V1'
DEBUG_MODE = FALSE;
```

Comprueba:

```sql
SHOW APPLICATIONS LIKE 'APP_M12_SALES_INSIGHTS';

SHOW APPLICATION ROLES
IN APPLICATION APP_M12_SALES_INSIGHTS;

SHOW PRIVILEGES
IN APPLICATION APP_M12_SALES_INSIGHTS;
```

La app no solicita privilegios globales.

---

## 12. Conceder el application role

```sql
GRANT APPLICATION ROLE
    APP_M12_SALES_INSIGHTS.APP_USER
TO ROLE M12_APP_CONSUMER;
```

El application role publica privilegios internos de la app. El account role representa al equipo consumer.

---

## 13. Probar V1

```sql
USE ROLE M12_APP_CONSUMER;
USE SECONDARY ROLES NONE;
USE WAREHOUSE WH_M12_ECOSYSTEM;
```

Versión:

```sql
SELECT *
FROM APP_M12_SALES_INSIGHTS.APP_CODE.V_APP_VERSION;
```

Objetivos:

```sql
SELECT *
FROM APP_M12_SALES_INSIGHTS.APP_CODE.V_REGION_TARGETS
ORDER BY region;
```

Función:

```sql
SELECT
    APP_M12_SALES_INSIGHTS.APP_CODE
        .ATTAINMENT_PCT(930, 1000)
        AS attainment_pct;
```

Resultado:

```text
93.0
```

Guarda una nota:

```sql
CALL APP_M12_SALES_INSIGHTS.APP_CODE.SET_NOTE(
    'NORTE',
    'Revisar campaña del canal WEB'
);
```

```sql
SELECT *
FROM APP_M12_SALES_INSIGHTS.APP_CODE.V_NOTES;
```

---

## 14. Pruebas negativas

Ejecuta individualmente.

Tabla interna:

```sql
SELECT *
FROM APP_M12_SALES_INSIGHTS.APP_DATA.REGION_TARGETS;
```

Insert directo:

```sql
INSERT INTO
    APP_M12_SALES_INSIGHTS.APP_DATA.CONSUMER_NOTES
VALUES (
    'SUR',
    'No autorizado',
    CURRENT_TIMESTAMP()
);
```

Crear objeto:

```sql
CREATE TABLE
    APP_M12_SALES_INSIGHTS.APP_CODE.NO_PERMITIDA (
        id NUMBER
    );
```

Todas deben fallar. El consumer utiliza únicamente la interfaz concedida a `APP_USER`.

---

# Ampliación: upgrade a V2

## 15. Subir y aplicar V2

Sube los tres ficheros de `v2/` a `APP_STAGE_V2`.

```sql
USE ROLE M12_NATIVE_APP_PROVIDER;
USE SECONDARY ROLES NONE;
```

```sql
ALTER APPLICATION APP_M12_SALES_INSIGHTS
UPGRADE USING
    '@PKG_M12_SALES_INSIGHTS.STAGE_CONTENT.APP_STAGE_V2';
```

---

## 16. Validar V2

```sql
USE ROLE M12_APP_CONSUMER;
USE SECONDARY ROLES NONE;
USE WAREHOUSE WH_M12_ECOSYSTEM;
```

```sql
SELECT *
FROM APP_M12_SALES_INSIGHTS.APP_CODE.V_APP_VERSION;
```

Debe devolver `2.0`.

```sql
SELECT *
FROM APP_M12_SALES_INSIGHTS.APP_CODE.V_REGION_TARGETS
ORDER BY region;
```

Comprueba `PRIORITY` y `GAP_FROM_REFERENCE`.

```sql
SELECT
    APP_M12_SALES_INSIGHTS.APP_CODE
        .RECOMMEND_ACTION(930, 1050)
        AS escenario_1,

    APP_M12_SALES_INSIGHTS.APP_CODE
        .RECOMMEND_ACTION(1100, 1050)
        AS escenario_2;
```

Resultados:

```text
ACTION_REQUIRED
MAINTAIN
```

La nota debe continuar:

```sql
SELECT *
FROM APP_M12_SALES_INSIGHTS.APP_CODE.V_NOTES;
```

La tabla de notas utiliza `CREATE TABLE IF NOT EXISTS`, por lo que no se reemplaza durante el upgrade.

---

# 17. Comparar mecanismos

| Mecanismo | Distribución | Compute |
|---|---|---|
| Direct share | Datos de solo lectura entre cuentas | Consumer |
| Listing | Datos o apps con catálogo y términos | Consumer |
| Reader account | Datos a usuarios sin cuenta propia | Provider |
| Native App | Datos, lógica e interfaz controlada | Normalmente consumer |

Una trial puede compartir directamente con cuentas concretas, pero no publicar una listing en Marketplace.

---

# Limpieza

```sql
USE ROLE M12_NATIVE_APP_PROVIDER;

DROP APPLICATION IF EXISTS APP_M12_SALES_INSIGHTS;

DROP APPLICATION PACKAGE IF EXISTS
    PKG_M12_SALES_INSIGHTS;
```

```sql
USE ROLE ACCOUNTADMIN;

DROP SHARE IF EXISTS SHARE_M12_VENTAS;
```

```sql
USE ROLE SECURITYADMIN;

DROP ROLE IF EXISTS M12_APP_CONSUMER;
DROP ROLE IF EXISTS M12_NATIVE_APP_PROVIDER;
DROP ROLE IF EXISTS M12_SHARE_VALIDATOR;
DROP ROLE IF EXISTS M12_SHARED_DATA_CONSUMER;
```

```sql
USE ROLE SYSADMIN;

ALTER WAREHOUSE WH_M12_ECOSYSTEM SUSPEND;

ALTER SESSION UNSET QUERY_TAG;
```

---

# Referencias oficiales

- [About Secure Data Sharing](https://docs.snowflake.com/en/user-guide/data-sharing-intro)
- [Consume imported data](https://docs.snowflake.com/en/user-guide/data-share-consumers)
- [Share secure database objects](https://docs.snowflake.com/en/user-guide/data-sharing-gs)
- [GRANT DATABASE ROLE TO SHARE](https://docs.snowflake.com/en/sql-reference/sql/grant-database-role-share)
- [Use listings as a provider](https://docs.snowflake.com/en/collaboration/provider-becoming)
- [Create an application package](https://docs.snowflake.com/en/developer-guide/native-apps/creating-app-package)
- [ALTER APPLICATION](https://docs.snowflake.com/en/sql-reference/sql/alter-application)

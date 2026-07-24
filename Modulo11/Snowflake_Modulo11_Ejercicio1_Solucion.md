# Módulo 11 · Ejercicio 1

## Solución guiada: RBAC y protección de datos

> **Edición necesaria:** Enterprise Edition o superior

---

# 1. Modelo final

```text
ACCOUNT ROLES
SYSADMIN
    ↑
M11_DATA_PLATFORM_ADMIN
    ├── M11_DATA_ENGINEER
    ├── M11_ANALYST
    ├── M11_AUDITOR
    └── M11_GOVERNANCE_ADMIN

DATABASE ROLES
DR_ANALYTICS_READER
        ↓
DR_PIPELINE_ENGINEER
```

Los account roles representan funciones de la cuenta.

Los database roles empaquetan privilegios de `DB_M11_SECURITY`.

El warehouse es un objeto de cuenta y se concede a account roles.

---

# Parte 1. Preparar el entorno

## 2. Guardar el usuario y limpiar

```sql
SET LAB_USER = CURRENT_USER();

SELECT
    $LAB_USER AS usuario,
    CURRENT_ROLE() AS rol_actual,
    CURRENT_SECONDARY_ROLES() AS roles_secundarios;
```

Elimina primero los objetos que pueden estar owned por los roles:

```sql
USE ROLE SYSADMIN;

DROP DATABASE IF EXISTS DB_M11_SECURITY;
DROP WAREHOUSE IF EXISTS WH_M11_SECURITY;
```

Elimina los roles:

```sql
USE ROLE SECURITYADMIN;

DROP ROLE IF EXISTS M11_DATA_PLATFORM_ADMIN;
DROP ROLE IF EXISTS M11_DATA_ENGINEER;
DROP ROLE IF EXISTS M11_ANALYST;
DROP ROLE IF EXISTS M11_AUDITOR;
DROP ROLE IF EXISTS M11_GOVERNANCE_ADMIN;
```

---

## 3. Crear los account roles

```sql
USE ROLE SECURITYADMIN;

CREATE ROLE M11_DATA_PLATFORM_ADMIN;
CREATE ROLE M11_DATA_ENGINEER;
CREATE ROLE M11_ANALYST;
CREATE ROLE M11_AUDITOR;
CREATE ROLE M11_GOVERNANCE_ADMIN;
```

Jerarquía:

```sql
GRANT ROLE M11_DATA_ENGINEER
TO ROLE M11_DATA_PLATFORM_ADMIN;

GRANT ROLE M11_ANALYST
TO ROLE M11_DATA_PLATFORM_ADMIN;

GRANT ROLE M11_AUDITOR
TO ROLE M11_DATA_PLATFORM_ADMIN;

GRANT ROLE M11_GOVERNANCE_ADMIN
TO ROLE M11_DATA_PLATFORM_ADMIN;

GRANT ROLE M11_DATA_PLATFORM_ADMIN
TO ROLE SYSADMIN;
```

La dirección es:

```text
GRANT ROLE hijo TO ROLE padre
```

El padre hereda los privilegios del hijo.

Asigna temporalmente los roles al usuario actual:

```sql
GRANT ROLE M11_DATA_PLATFORM_ADMIN
TO USER IDENTIFIER($LAB_USER);

GRANT ROLE M11_DATA_ENGINEER
TO USER IDENTIFIER($LAB_USER);

GRANT ROLE M11_ANALYST
TO USER IDENTIFIER($LAB_USER);

GRANT ROLE M11_AUDITOR
TO USER IDENTIFIER($LAB_USER);

GRANT ROLE M11_GOVERNANCE_ADMIN
TO USER IDENTIFIER($LAB_USER);
```

---

## 4. Crear el warehouse y la base

```sql
USE ROLE SYSADMIN;

CREATE WAREHOUSE WH_M11_SECURITY
    WAREHOUSE_SIZE = XSMALL
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE;

CREATE DATABASE DB_M11_SECURITY;
```

Esquemas:

```sql
CREATE SCHEMA DB_M11_SECURITY.RAW;

CREATE SCHEMA DB_M11_SECURITY.CURATED
    WITH MANAGED ACCESS;

CREATE SCHEMA DB_M11_SECURITY.GOVERNANCE
    WITH MANAGED ACCESS;
```

Concede al rol de gobierno acceso al contenedor:

```sql
GRANT USAGE
ON DATABASE DB_M11_SECURITY
TO ROLE M11_GOVERNANCE_ADMIN;

GRANT USAGE
ON SCHEMA DB_M11_SECURITY.CURATED
TO ROLE M11_GOVERNANCE_ADMIN;
```

Transfiere el ownership del esquema de gobierno:

```sql
GRANT OWNERSHIP
ON SCHEMA DB_M11_SECURITY.GOVERNANCE
TO ROLE M11_GOVERNANCE_ADMIN
COPY CURRENT GRANTS;
```

---

## 5. Crear y cargar las tablas

```sql
USE WAREHOUSE WH_M11_SECURITY;
```

RAW:

```sql
CREATE TABLE DB_M11_SECURITY.RAW.CLIENTES_STAGING (
    id_cliente       NUMBER(18,0),
    nombre           VARCHAR(100),
    email            VARCHAR(200),
    telefono         VARCHAR(30),
    region           VARCHAR(20),
    estado           VARCHAR(20),
    limite_credito   NUMBER(12,2),
    cargado_en       TIMESTAMP_LTZ
);
```

CURATED:

```sql
CREATE TABLE DB_M11_SECURITY.CURATED.CLIENTES
LIKE DB_M11_SECURITY.RAW.CLIENTES_STAGING;
```

Carga:

```sql
INSERT INTO DB_M11_SECURITY.RAW.CLIENTES_STAGING
SELECT
    column1::NUMBER,
    column2::VARCHAR,
    column3::VARCHAR,
    column4::VARCHAR,
    column5::VARCHAR,
    column6::VARCHAR,
    column7::NUMBER(12,2),
    CURRENT_TIMESTAMP()
FROM VALUES
    (101, 'Ana Torres',     'ana.torres@example.com',
     '600111101', 'NORTE', 'ACTIVO', 10000.00),

    (102, 'Beatriz Ruiz',   'beatriz.ruiz@example.com',
     '600111102', 'SUR', 'ACTIVO', 25000.00),

    (103, 'Carlos Martín',  'carlos.martin@example.com',
     '600111103', 'ESTE', 'ACTIVO', 12000.00),

    (104, 'Diana López',    'diana.lopez@example.com',
     '600111104', 'OESTE', 'INACTIVO', 30000.00);
```

```sql
INSERT INTO DB_M11_SECURITY.CURATED.CLIENTES
SELECT *
FROM DB_M11_SECURITY.RAW.CLIENTES_STAGING;
```

Valida:

```sql
SELECT
    COUNT(*) AS filas,
    COUNT(DISTINCT region) AS regiones
FROM DB_M11_SECURITY.CURATED.CLIENTES;
```

Resultado:

```text
4 filas
4 regiones
```

---

# Parte 2. Configurar RBAC

## 6. Crear los database roles

```sql
USE ROLE SYSADMIN;

CREATE DATABASE ROLE
    DB_M11_SECURITY.DR_ANALYTICS_READER;

CREATE DATABASE ROLE
    DB_M11_SECURITY.DR_PIPELINE_ENGINEER;
```

El rol de ingeniería hereda al lector:

```sql
GRANT DATABASE ROLE
    DB_M11_SECURITY.DR_ANALYTICS_READER
TO DATABASE ROLE
    DB_M11_SECURITY.DR_PIPELINE_ENGINEER;
```

---

## 7. Configurar el lector

```sql
GRANT USAGE
ON SCHEMA DB_M11_SECURITY.CURATED
TO DATABASE ROLE
    DB_M11_SECURITY.DR_ANALYTICS_READER;
```

Tablas actuales:

```sql
GRANT SELECT
ON ALL TABLES IN SCHEMA DB_M11_SECURITY.CURATED
TO DATABASE ROLE
    DB_M11_SECURITY.DR_ANALYTICS_READER;
```

Tablas futuras:

```sql
GRANT SELECT
ON FUTURE TABLES IN SCHEMA DB_M11_SECURITY.CURATED
TO DATABASE ROLE
    DB_M11_SECURITY.DR_ANALYTICS_READER;
```

---

## 8. Configurar ingeniería

```sql
GRANT USAGE
ON SCHEMA DB_M11_SECURITY.RAW
TO DATABASE ROLE
    DB_M11_SECURITY.DR_PIPELINE_ENGINEER;
```

```sql
GRANT SELECT, INSERT, UPDATE, DELETE
ON ALL TABLES IN SCHEMA DB_M11_SECURITY.RAW
TO DATABASE ROLE
    DB_M11_SECURITY.DR_PIPELINE_ENGINEER;
```

```sql
GRANT SELECT, INSERT, UPDATE, DELETE
ON FUTURE TABLES IN SCHEMA DB_M11_SECURITY.RAW
TO DATABASE ROLE
    DB_M11_SECURITY.DR_PIPELINE_ENGINEER;
```

Creación:

```sql
GRANT CREATE TABLE
ON SCHEMA DB_M11_SECURITY.RAW
TO DATABASE ROLE
    DB_M11_SECURITY.DR_PIPELINE_ENGINEER;

GRANT CREATE TABLE
ON SCHEMA DB_M11_SECURITY.CURATED
TO DATABASE ROLE
    DB_M11_SECURITY.DR_PIPELINE_ENGINEER;
```

---

## 9. Conectar database roles y account roles

```sql
GRANT DATABASE ROLE
    DB_M11_SECURITY.DR_ANALYTICS_READER
TO ROLE M11_ANALYST;

GRANT DATABASE ROLE
    DB_M11_SECURITY.DR_ANALYTICS_READER
TO ROLE M11_AUDITOR;

GRANT DATABASE ROLE
    DB_M11_SECURITY.DR_PIPELINE_ENGINEER
TO ROLE M11_DATA_ENGINEER;
```

---

## 10. Conceder warehouse

```sql
USE ROLE SECURITYADMIN;

GRANT USAGE
ON WAREHOUSE WH_M11_SECURITY
TO ROLE M11_ANALYST;

GRANT USAGE
ON WAREHOUSE WH_M11_SECURITY
TO ROLE M11_AUDITOR;

GRANT USAGE
ON WAREHOUSE WH_M11_SECURITY
TO ROLE M11_DATA_ENGINEER;

GRANT USAGE
ON WAREHOUSE WH_M11_SECURITY
TO ROLE M11_GOVERNANCE_ADMIN;
```

El warehouse no puede incluirse en un database role porque no pertenece a una base de datos.

---

## 11. Probar el analista

```sql
USE ROLE M11_ANALYST;
USE SECONDARY ROLES NONE;
USE WAREHOUSE WH_M11_SECURITY;
```

Permitido:

```sql
SELECT COUNT(*) AS filas
FROM DB_M11_SECURITY.CURATED.CLIENTES;
```

Resultado:

```text
4
```

Ejecuta individualmente. Debe fallar:

```sql
SELECT *
FROM DB_M11_SECURITY.RAW.CLIENTES_STAGING;
```

Debe fallar:

```sql
INSERT INTO DB_M11_SECURITY.CURATED.CLIENTES
SELECT *
FROM DB_M11_SECURITY.CURATED.CLIENTES
LIMIT 1;
```

---

## 12. Probar ingeniería

```sql
USE ROLE M11_DATA_ENGINEER;
USE SECONDARY ROLES NONE;
USE WAREHOUSE WH_M11_SECURITY;
```

Lectura heredada:

```sql
SELECT COUNT(*) AS filas
FROM DB_M11_SECURITY.CURATED.CLIENTES;
```

DML permitido en RAW:

```sql
UPDATE DB_M11_SECURITY.RAW.CLIENTES_STAGING
SET estado = 'REVISADO'
WHERE id_cliente = 101;
```

Restaura el dato:

```sql
UPDATE DB_M11_SECURITY.RAW.CLIENTES_STAGING
SET estado = 'ACTIVO'
WHERE id_cliente = 101;
```

---

# Parte 3. Future grants y managed access

## 13. Crear una tabla futura

Crea la tabla después de definir el future grant:

```sql
USE ROLE SYSADMIN;
USE WAREHOUSE WH_M11_SECURITY;

CREATE TABLE DB_M11_SECURITY.CURATED.RESUMEN_REGION AS
SELECT
    region,
    COUNT(*) AS clientes
FROM DB_M11_SECURITY.CURATED.CLIENTES
GROUP BY region;
```

Prueba el acceso automático:

```sql
USE ROLE M11_ANALYST;
USE SECONDARY ROLES NONE;
USE WAREHOUSE WH_M11_SECURITY;

SELECT *
FROM DB_M11_SECURITY.CURATED.RESUMEN_REGION
ORDER BY region;
```

No fue necesario conceder un grant nuevo.

> El future grant concede privilegios. No aplica automáticamente Row Access Policies, masking policies ni tags.

---

## 14. Demostrar managed access

Como ingeniería:

```sql
USE ROLE M11_DATA_ENGINEER;
USE SECONDARY ROLES NONE;
USE WAREHOUSE WH_M11_SECURITY;

CREATE TABLE DB_M11_SECURITY.CURATED.PRUEBA_MANAGED (
    id NUMBER
);
```

El rol primario es owner de la tabla.

Ejecuta individualmente. Debe fallar:

```sql
GRANT SELECT
ON TABLE DB_M11_SECURITY.CURATED.PRUEBA_MANAGED
TO ROLE M11_GOVERNANCE_ADMIN;
```

Aunque ingeniería es owner, el esquema es managed access.

Solo pueden decidir grants:

- El owner del esquema.
- Un rol con `MANAGE GRANTS`.

Elimina la prueba:

```sql
DROP TABLE DB_M11_SECURITY.CURATED.PRUEBA_MANAGED;
```

---

# Parte 4. Gobierno de datos

## 15. Conceder privilegios de gobierno

```sql
USE ROLE ACCOUNTADMIN;

GRANT APPLY ROW ACCESS POLICY
ON ACCOUNT
TO ROLE M11_GOVERNANCE_ADMIN;

GRANT APPLY MASKING POLICY
ON ACCOUNT
TO ROLE M11_GOVERNANCE_ADMIN;

GRANT APPLY TAG
ON ACCOUNT
TO ROLE M11_GOVERNANCE_ADMIN;
```

Estos privilegios permiten administrar asociaciones, pero no conceden `SELECT`.

---

## 16. Crear la tabla de mapeo

```sql
USE ROLE M11_GOVERNANCE_ADMIN;
USE SECONDARY ROLES NONE;
USE WAREHOUSE WH_M11_SECURITY;
USE DATABASE DB_M11_SECURITY;
USE SCHEMA GOVERNANCE;
```

```sql
CREATE TABLE ROL_REGION_MAP (
    role_name VARCHAR(100),
    region    VARCHAR(20)
);
```

```sql
INSERT INTO ROL_REGION_MAP
VALUES
    ('M11_ANALYST', 'NORTE'),
    ('M11_ANALYST', 'ESTE');
```

---

## 17. Crear la Row Access Policy

```sql
CREATE ROW ACCESS POLICY RAP_CLIENTES_REGION
AS (fila_region VARCHAR)
RETURNS BOOLEAN ->
       IS_ROLE_IN_SESSION('M11_DATA_ENGINEER')
    OR IS_ROLE_IN_SESSION('M11_AUDITOR')
    OR IS_ROLE_IN_SESSION('M11_DATA_PLATFORM_ADMIN')
    OR EXISTS (
        SELECT 1
        FROM DB_M11_SECURITY.GOVERNANCE.ROL_REGION_MAP mapa
        WHERE mapa.region = fila_region
          AND IS_ROLE_IN_SESSION(mapa.role_name)
    );
```

`IS_ROLE_IN_SESSION` evalúa el rol primario, los roles secundarios activos y la jerarquía correspondiente.

Aplica:

```sql
ALTER TABLE DB_M11_SECURITY.CURATED.CLIENTES
ADD ROW ACCESS POLICY
    DB_M11_SECURITY.GOVERNANCE.RAP_CLIENTES_REGION
ON (region);
```

---

## 18. Crear el tag

```sql
CREATE TAG TAG_CLASIFICACION
    ALLOWED_VALUES
        'INTERNAL',
        'PII',
        'RESTRICTED';
```

---

## 19. Crear la masking policy de texto

```sql
CREATE MASKING POLICY MP_TAG_STRING
AS (valor VARCHAR)
RETURNS VARCHAR ->
CASE
    WHEN valor IS NULL THEN NULL

    WHEN IS_ROLE_IN_SESSION('M11_DATA_ENGINEER')
      OR IS_ROLE_IN_SESSION('M11_DATA_PLATFORM_ADMIN')
        THEN valor

    WHEN SYSTEM$GET_TAG_ON_CURRENT_COLUMN(
        'DB_M11_SECURITY.GOVERNANCE.TAG_CLASIFICACION'
    ) = 'INTERNAL'
        THEN valor

    WHEN SYSTEM$GET_TAG_ON_CURRENT_COLUMN(
        'DB_M11_SECURITY.GOVERNANCE.TAG_CLASIFICACION'
    ) = 'PII'
        THEN '***MASKED***'

    ELSE '***RESTRICTED***'
END;
```

---

## 20. Crear la masking policy numérica

```sql
CREATE MASKING POLICY MP_TAG_NUMBER
AS (valor NUMBER(12,2))
RETURNS NUMBER(12,2) ->
CASE
    WHEN IS_ROLE_IN_SESSION('M11_DATA_ENGINEER')
      OR IS_ROLE_IN_SESSION('M11_DATA_PLATFORM_ADMIN')
        THEN valor
    ELSE NULL
END;
```

Un tag puede tener una masking policy por cada tipo de dato.

---

## 21. Asociar las policies al tag

```sql
ALTER TAG TAG_CLASIFICACION
SET MASKING POLICY MP_TAG_STRING;
```

```sql
ALTER TAG TAG_CLASIFICACION
SET MASKING POLICY MP_TAG_NUMBER;
```

---

## 22. Clasificar las columnas

```sql
ALTER TABLE DB_M11_SECURITY.CURATED.CLIENTES
MODIFY COLUMN nombre
SET TAG DB_M11_SECURITY.GOVERNANCE.TAG_CLASIFICACION
    = 'INTERNAL';
```

```sql
ALTER TABLE DB_M11_SECURITY.CURATED.CLIENTES
MODIFY COLUMN email
SET TAG DB_M11_SECURITY.GOVERNANCE.TAG_CLASIFICACION
    = 'PII';
```

```sql
ALTER TABLE DB_M11_SECURITY.CURATED.CLIENTES
MODIFY COLUMN telefono
SET TAG DB_M11_SECURITY.GOVERNANCE.TAG_CLASIFICACION
    = 'PII';
```

```sql
ALTER TABLE DB_M11_SECURITY.CURATED.CLIENTES
MODIFY COLUMN limite_credito
SET TAG DB_M11_SECURITY.GOVERNANCE.TAG_CLASIFICACION
    = 'RESTRICTED';
```

No se aplica masking a `REGION`, porque forma parte de la firma de la Row Access Policy.

---

## 23. Crear la policy directa de email

```sql
CREATE MASKING POLICY MP_EMAIL_DIRECTA
AS (valor VARCHAR)
RETURNS VARCHAR ->
CASE
    WHEN valor IS NULL THEN NULL

    WHEN IS_ROLE_IN_SESSION('M11_DATA_ENGINEER')
      OR IS_ROLE_IN_SESSION('M11_DATA_PLATFORM_ADMIN')
        THEN valor

    WHEN IS_ROLE_IN_SESSION('M11_ANALYST')
        THEN
            LEFT(valor, 1)
            || '***'
            || SUBSTR(
                valor,
                POSITION('@' IN valor)
            )

    ELSE '***MASKED***'
END;
```

Aplica:

```sql
ALTER TABLE DB_M11_SECURITY.CURATED.CLIENTES
MODIFY COLUMN email
SET MASKING POLICY
    DB_M11_SECURITY.GOVERNANCE.MP_EMAIL_DIRECTA;
```

La policy directa prevalece sobre el masking asociado al tag.

---

# Parte 5. Validación

## 24. Analista

```sql
USE ROLE M11_ANALYST;
USE SECONDARY ROLES NONE;
USE WAREHOUSE WH_M11_SECURITY;
```

```sql
SELECT
    id_cliente,
    nombre,
    email,
    telefono,
    limite_credito,
    region
FROM DB_M11_SECURITY.CURATED.CLIENTES
ORDER BY id_cliente;
```

Resultado conceptual:

```text
2 filas
NORTE y ESTE
email parcial
telefono = ***MASKED***
limite_credito = NULL
```

---

## 25. Auditor

```sql
USE ROLE M11_AUDITOR;
USE SECONDARY ROLES NONE;
USE WAREHOUSE WH_M11_SECURITY;
```

```sql
SELECT
    id_cliente,
    email,
    telefono,
    limite_credito,
    region
FROM DB_M11_SECURITY.CURATED.CLIENTES
ORDER BY id_cliente;
```

Resultado:

```text
4 filas
email = ***MASKED***
telefono = ***MASKED***
limite_credito = NULL
```

---

## 26. Ingeniería

```sql
USE ROLE M11_DATA_ENGINEER;
USE SECONDARY ROLES NONE;
USE WAREHOUSE WH_M11_SECURITY;
```

```sql
SELECT
    id_cliente,
    email,
    telefono,
    limite_credito,
    region
FROM DB_M11_SECURITY.CURATED.CLIENTES
ORDER BY id_cliente;
```

Resultado:

```text
4 filas
valores originales
```

---

## 27. Separación de funciones

```sql
USE ROLE M11_GOVERNANCE_ADMIN;
USE SECONDARY ROLES NONE;
USE WAREHOUSE WH_M11_SECURITY;
```

Ejecuta individualmente. Debe fallar:

```sql
SELECT *
FROM DB_M11_SECURITY.CURATED.CLIENTES;
```

`APPLY POLICY` y `APPLY TAG` no conceden acceso a los datos.

---

# Parte 6. Auditoría

## 28. Roles y grants

```sql
SHOW ROLES LIKE 'M11_%';
```

```sql
SHOW GRANTS TO DATABASE ROLE
    DB_M11_SECURITY.DR_ANALYTICS_READER;
```

```sql
SHOW FUTURE GRANTS TO DATABASE ROLE
    DB_M11_SECURITY.DR_ANALYTICS_READER;
```

---

## 29. Policies

```sql
SHOW ROW ACCESS POLICIES
IN SCHEMA DB_M11_SECURITY.GOVERNANCE;
```

```sql
SHOW MASKING POLICIES
IN SCHEMA DB_M11_SECURITY.GOVERNANCE;
```

Asociaciones:

```sql
SELECT *
FROM TABLE(
    DB_M11_SECURITY.INFORMATION_SCHEMA.POLICY_REFERENCES(
        POLICY_NAME =>
          'DB_M11_SECURITY.GOVERNANCE.RAP_CLIENTES_REGION'
    )
);
```

```sql
SELECT *
FROM TABLE(
    DB_M11_SECURITY.INFORMATION_SCHEMA.POLICY_REFERENCES(
        POLICY_NAME =>
          'DB_M11_SECURITY.GOVERNANCE.MP_EMAIL_DIRECTA'
    )
);
```

---

## 30. Tags

```sql
SHOW TAGS
IN SCHEMA DB_M11_SECURITY.GOVERNANCE;
```

```sql
SELECT *
FROM TABLE(
    DB_M11_SECURITY.INFORMATION_SCHEMA.TAG_REFERENCES(
        'DB_M11_SECURITY.CURATED.CLIENTES',
        'TABLE'
    )
);
```

---

# Ampliación opcional

## 31. Ownership conservando grants

```sql
USE ROLE SYSADMIN;

GRANT OWNERSHIP
ON TABLE DB_M11_SECURITY.CURATED.RESUMEN_REGION
TO ROLE M11_DATA_PLATFORM_ADMIN
COPY CURRENT GRANTS;
```

`COPY CURRENT GRANTS` mantiene una copia de los grants salientes existentes.

---

## 32. Roles secundarios

Usa como rol primario `M11_ANALYST`.

```sql
USE ROLE M11_ANALYST;
USE SECONDARY ROLES NONE;
```

RAW debe estar denegado.

Activa los roles secundarios:

```sql
USE SECONDARY ROLES ALL;
```

El usuario puede combinar privilegios de roles que tenga asignados.

Sin embargo, el ownership de un objeto nuevo se asigna al rol primario que ejecuta el `CREATE`.

---

## 33. Precedencia de future grants

Si existen future grants para tablas:

```text
nivel database
nivel schema
```

los grants del schema prevalecen para ese tipo de objeto y los del nivel database se ignoran en ese schema.

---

# Estado final

Conserva:

```text
DB_M11_SECURITY
WH_M11_SECURITY
roles M11_%
database roles
Row Access Policy
masking policies
tag
```

El siguiente ejercicio reutiliza el entorno.

Suspende el warehouse:

```sql
USE ROLE SYSADMIN;

ALTER WAREHOUSE WH_M11_SECURITY SUSPEND;
```

---

# Compatibilidad y correcciones aplicadas

## Enterprise Edition

Row Access Policies y Dynamic Data Masking requieren Enterprise Edition o superior.

`ACCESS_HISTORY`, utilizado en el ejercicio siguiente, también requiere Enterprise.

## Managed access

El owner de un objeto dentro de un managed access schema no puede decidir los grants del objeto. La decisión corresponde al schema owner o a un rol con `MANAGE GRANTS`.

## Future grants

Los future grants conceden privilegios a objetos nuevos. No aplican automáticamente policies ni tags.

Cuando existen future grants para el mismo tipo de objeto a nivel de database y schema, prevalecen los definidos en el schema.

## Policy owner

Una Row Access Policy que consulta una tabla de mapeo se evalúa con los privilegios del owner de la policy. El consumidor no necesita `SELECT` sobre el mapa.

## Owner de la tabla

Ser owner de una tabla no exime de Row Access Policies ni masking policies.

## Tags

Un tag admite una masking policy por tipo de dato.

Una masking policy aplicada directamente a una columna prevalece sobre la policy asociada mediante tag.

## Edición trial

Una trial Enterprise permite realizar el ejercicio.

En una trial Standard, la parte RBAC funciona, pero la creación de Row Access Policies y masking policies falla por edición.

---

# Referencias oficiales

- [Overview of access control](https://docs.snowflake.com/en/user-guide/security-access-control-overview)
- [GRANT privileges](https://docs.snowflake.com/en/sql-reference/sql/grant-privilege)
- [Understanding row access policies](https://docs.snowflake.com/en/user-guide/security-row-intro)
- [Understanding Dynamic Data Masking](https://docs.snowflake.com/en/user-guide/security-column-ddm-intro)
- [Tag-based masking policies](https://docs.snowflake.com/en/user-guide/tag-based-masking-policies)
- [IS_ROLE_IN_SESSION](https://docs.snowflake.com/en/sql-reference/functions/is_role_in_session)

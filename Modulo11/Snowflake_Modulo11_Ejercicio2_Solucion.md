# Módulo 11 · Ejercicio 2

## Solución guiada: seguridad perimetral, autenticación y auditoría

> **Edición:** Enterprise para `ACCESS_HISTORY`

---

# 1. Orden de evaluación

```text
1. Network policy
2. Authentication policy
3. Password policy, si se usa password local
4. Session policy
5. RBAC y policies de datos
```

Una conexión bloqueada por red no llega a autenticarse.

Una autenticación correcta no concede acceso a los datos por sí sola.

---

# Parte 1. Preparar el entorno

## 2. Comprobar los prerrequisitos

```sql
USE ROLE SYSADMIN;
USE SECONDARY ROLES NONE;
```

```sql
SHOW DATABASES LIKE 'DB_M11_SECURITY';
SHOW WAREHOUSES LIKE 'WH_M11_SECURITY';

SHOW TABLES LIKE 'CLIENTES'
IN SCHEMA DB_M11_SECURITY.CURATED;
```

```sql
USE WAREHOUSE WH_M11_SECURITY;

SELECT COUNT(*) AS filas
FROM DB_M11_SECURITY.CURATED.CLIENTES;
```

La visibilidad depende del rol y de la Row Access Policy creada en el ejercicio anterior.

---

## 3. Guardar el usuario

```sql
SET LAB_USER = CURRENT_USER();

SELECT
    $LAB_USER AS usuario,
    CURRENT_ROLE() AS rol;
```

---

## 4. Limpiar una ejecución anterior

No se modifica ninguna policy real de la cuenta.

Elimina solo los objetos del laboratorio:

```sql
USE ROLE ACCOUNTADMIN;

DROP NETWORK POLICY IF EXISTS NP_M11_CORPORATE;
```

```sql
USE ROLE SYSADMIN;

DROP SCHEMA IF EXISTS
    DB_M11_SECURITY.SECURITY_OPS
CASCADE;
```

```sql
USE ROLE SECURITYADMIN;

DROP ROLE IF EXISTS M11_SECURITY_OPERATIONS;
```

Si una ejecución anterior aplicó por error una policy, revísala manualmente antes de intentar eliminarla.

---

## 5. Crear el rol de seguridad

```sql
USE ROLE SECURITYADMIN;

CREATE ROLE M11_SECURITY_OPERATIONS;
```

Conecta con `SECURITYADMIN`:

```sql
GRANT ROLE M11_SECURITY_OPERATIONS
TO ROLE SECURITYADMIN;
```

Concede al usuario:

```sql
GRANT ROLE M11_SECURITY_OPERATIONS
TO USER IDENTIFIER($LAB_USER);
```

Privilegios de cuenta:

```sql
GRANT CREATE NETWORK POLICY
ON ACCOUNT
TO ROLE M11_SECURITY_OPERATIONS;
```

```sql
GRANT APPLY AUTHENTICATION POLICY
ON ACCOUNT
TO ROLE M11_SECURITY_OPERATIONS;
```

No se utilizará `APPLY AUTHENTICATION POLICY`, pero permite analizar la separación entre crear y asignar.

---

## 6. Crear SECURITY_OPS

```sql
USE ROLE SYSADMIN;

CREATE SCHEMA DB_M11_SECURITY.SECURITY_OPS;
```

```sql
GRANT USAGE
ON DATABASE DB_M11_SECURITY
TO ROLE M11_SECURITY_OPERATIONS;

GRANT USAGE
ON SCHEMA DB_M11_SECURITY.SECURITY_OPS
TO ROLE M11_SECURITY_OPERATIONS;

GRANT CREATE NETWORK RULE
ON SCHEMA DB_M11_SECURITY.SECURITY_OPS
TO ROLE M11_SECURITY_OPERATIONS;

GRANT CREATE AUTHENTICATION POLICY
ON SCHEMA DB_M11_SECURITY.SECURITY_OPS
TO ROLE M11_SECURITY_OPERATIONS;

GRANT USAGE
ON WAREHOUSE WH_M11_SECURITY
TO ROLE M11_SECURITY_OPERATIONS;
```

No se concede acceso a RAW ni CURATED.

---

# Parte 2. Revisar el estado actual

## 7. Network policies

```sql
USE ROLE SECURITYADMIN;

SHOW NETWORK POLICIES;
```

Policy de cuenta:

```sql
SHOW PARAMETERS LIKE 'NETWORK_POLICY'
IN ACCOUNT;
```

---

## 8. Authentication policies

```sql
SHOW AUTHENTICATION POLICIES IN ACCOUNT;
```

Cuenta:

```sql
SHOW AUTHENTICATION POLICIES ON ACCOUNT;
```

Usuario actual:

```sql
SET SQL_SHOW_AUTH_USER =
    'SHOW AUTHENTICATION POLICIES ON USER "'
    || $LAB_USER
    || '"';
```

```sql
EXECUTE IMMEDIATE $SQL_SHOW_AUTH_USER;
```

---

## 9. Consultar el login actual

La función devuelve actividad de los últimos siete días.

```sql
SELECT
    event_timestamp,
    user_name,
    client_ip,
    reported_client_type,
    first_authentication_factor,
    second_authentication_factor,
    is_success,
    error_code,
    error_message
FROM TABLE(
    DB_M11_SECURITY.INFORMATION_SCHEMA
        .LOGIN_HISTORY_BY_USER(
            TIME_RANGE_START =>
                DATEADD(
                    'day',
                    -1,
                    CURRENT_TIMESTAMP()
                ),
            RESULT_LIMIT => 20
        )
)
ORDER BY event_timestamp DESC;
```

La IP puede pertenecer a:

- NAT.
- VPN.
- Proxy.
- ISP doméstico.
- Gateway corporativo.

No debe utilizarse automáticamente para crear una allowlist de producción.

---

# Parte 3. Crear controles no aplicados

## 10. Crear network rules

```sql
USE ROLE M11_SECURITY_OPERATIONS;
USE SECONDARY ROLES NONE;
USE DATABASE DB_M11_SECURITY;
USE SCHEMA SECURITY_OPS;
```

Permitida:

```sql
CREATE NETWORK RULE NR_M11_CORPORATE_IPV4
    TYPE = IPV4
    MODE = INGRESS
    VALUE_LIST = (
        '192.0.2.0/24',
        '198.51.100.0/24'
    )
    COMMENT =
        'Rangos de documentación; no aplicar';
```

Bloqueada:

```sql
CREATE NETWORK RULE NR_M11_BLOCKED_IPV4
    TYPE = IPV4
    MODE = INGRESS
    VALUE_LIST = (
        '203.0.113.0/24'
    )
    COMMENT =
        'Rango de documentación bloqueado';
```

Comprueba:

```sql
SHOW NETWORK RULES
IN SCHEMA DB_M11_SECURITY.SECURITY_OPS;
```

```sql
DESC NETWORK RULE
    DB_M11_SECURITY.SECURITY_OPS.NR_M11_CORPORATE_IPV4;
```

---

## 11. Crear la network policy

```sql
CREATE NETWORK POLICY NP_M11_CORPORATE
    ALLOWED_NETWORK_RULE_LIST = (
        'DB_M11_SECURITY.SECURITY_OPS.NR_M11_CORPORATE_IPV4'
    )
    BLOCKED_NETWORK_RULE_LIST = (
        'DB_M11_SECURITY.SECURITY_OPS.NR_M11_BLOCKED_IPV4'
    )
    COMMENT =
        'Policy didáctica que no debe aplicarse';
```

Comprueba:

```sql
SHOW NETWORK POLICIES LIKE 'NP_M11_CORPORATE';

DESC NETWORK POLICY NP_M11_CORPORATE;
```

---

## 12. Confirmar que no está aplicada

Cuenta:

```sql
SHOW PARAMETERS LIKE 'NETWORK_POLICY'
IN ACCOUNT;
```

Usuario:

```sql
DESC USER IDENTIFIER($LAB_USER);
```

No ejecutar:

```sql
-- ALTER ACCOUNT
-- SET NETWORK_POLICY = NP_M11_CORPORATE;
```

```sql
-- ALTER USER <USUARIO>
-- SET NETWORK_POLICY = NP_M11_CORPORATE;
```

Los rangos reservados no incluyen la IP real.

---

## 13. Crear la authentication policy humana

```sql
CREATE AUTHENTICATION POLICY AUTH_M11_HUMAN

    AUTHENTICATION_METHODS = (
        'PASSWORD',
        'SAML'
    )

    CLIENT_TYPES = (
        'SNOWFLAKE_UI',
        'SNOWFLAKE_CLI',
        'SNOWSQL',
        'DRIVERS'
    )

    MFA_ENROLLMENT = 'REQUIRED'

    MFA_POLICY = (
        ALLOWED_METHODS = (
            'PASSKEY',
            'TOTP',
            'OTP'
        )

        ENFORCE_MFA_ON_EXTERNAL_AUTHENTICATION =
            'ALL'
    )

    COMMENT =
        'Personas: password o SSO con MFA';
```

`SNOWFLAKE_UI` debe estar permitido para que el usuario pueda completar el alta de MFA.

---

## 14. Crear la policy de servicios

```sql
CREATE AUTHENTICATION POLICY AUTH_M11_SERVICE

    AUTHENTICATION_METHODS = (
        'KEYPAIR',
        'PROGRAMMATIC_ACCESS_TOKEN',
        'WORKLOAD_IDENTITY'
    )

    CLIENT_TYPES = (
        'DRIVERS',
        'SNOWFLAKE_CLI',
        'SNOWSQL'
    )

    WORKLOAD_IDENTITY_POLICY = (
        ALLOWED_PROVIDERS = (
            AWS,
            AZURE,
            GCP,
            OIDC
        )
    )

    COMMENT =
        'Servicios sin password interactivo';
```

Elección orientativa:

| Workload | Método |
|---|---|
| AWS, Azure o GCP administrado | Workload identity |
| CI moderno | Workload identity o PAT corto |
| Aplicación tradicional | Key pair con rotación |
| Persona | SAML o password con MFA |

---

## 15. Inspeccionar las policies

```sql
SHOW AUTHENTICATION POLICIES
IN SCHEMA DB_M11_SECURITY.SECURITY_OPS;
```

```sql
DESC AUTHENTICATION POLICY
    DB_M11_SECURITY.SECURITY_OPS.AUTH_M11_HUMAN;
```

```sql
DESC AUTHENTICATION POLICY
    DB_M11_SECURITY.SECURITY_OPS.AUTH_M11_SERVICE;
```

No ejecutar:

```sql
-- ALTER ACCOUNT SET AUTHENTICATION POLICY
-- DB_M11_SECURITY.SECURITY_OPS.AUTH_M11_HUMAN
-- FOR ALL PERSON USERS;
```

```sql
-- ALTER ACCOUNT SET AUTHENTICATION POLICY
-- DB_M11_SECURITY.SECURITY_OPS.AUTH_M11_SERVICE
-- FOR ALL SERVICE USERS;
```

---

# Parte 4. Delegar auditoría

## 16. Conceder database roles de SNOWFLAKE

```sql
USE ROLE ACCOUNTADMIN;
```

```sql
GRANT DATABASE ROLE SNOWFLAKE.OBJECT_VIEWER
TO ROLE M11_AUDITOR;

GRANT DATABASE ROLE SNOWFLAKE.USAGE_VIEWER
TO ROLE M11_AUDITOR;

GRANT DATABASE ROLE SNOWFLAKE.GOVERNANCE_VIEWER
TO ROLE M11_AUDITOR;

GRANT DATABASE ROLE SNOWFLAKE.SECURITY_VIEWER
TO ROLE M11_AUDITOR;
```

Funciones principales:

| Database role | Información |
|---|---|
| `OBJECT_VIEWER` | Objetos y metadatos |
| `USAGE_VIEWER` | Uso y Query History |
| `GOVERNANCE_VIEWER` | Access History y gobierno |
| `SECURITY_VIEWER` | Login, usuarios y grants |

---

# Parte 5. Generar actividad

## 17. Lectura del analista

```sql
USE ROLE M11_ANALYST;
USE SECONDARY ROLES NONE;
USE WAREHOUSE WH_M11_SECURITY;
```

```sql
ALTER SESSION SET QUERY_TAG =
    'M11_E02_ANALYST_READ';
```

```sql
SELECT
    id_cliente,
    nombre,
    email,
    region
FROM DB_M11_SECURITY.CURATED.CLIENTES
ORDER BY id_cliente;
```

Debe devolver dos filas protegidas.

---

## 18. Denegación del analista

```sql
ALTER SESSION SET QUERY_TAG =
    'M11_E02_ANALYST_DENIED';
```

Ejecuta individualmente. Debe fallar:

```sql
SELECT *
FROM DB_M11_SECURITY.RAW.CLIENTES_STAGING;
```

---

## 19. Lectura del auditor

```sql
USE ROLE M11_AUDITOR;
USE SECONDARY ROLES NONE;
USE WAREHOUSE WH_M11_SECURITY;
```

```sql
ALTER SESSION SET QUERY_TAG =
    'M11_E02_AUDITOR_READ';
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

Debe devolver cuatro filas con masking.

---

## 20. DML de ingeniería

```sql
USE ROLE M11_DATA_ENGINEER;
USE SECONDARY ROLES NONE;
USE WAREHOUSE WH_M11_SECURITY;
```

```sql
ALTER SESSION SET QUERY_TAG =
    'M11_E02_ENGINEER_DML';
```

```sql
UPDATE DB_M11_SECURITY.RAW.CLIENTES_STAGING
SET estado = 'REVISADO'
WHERE id_cliente = 101;
```

Restaura el dato después:

```sql
UPDATE DB_M11_SECURITY.RAW.CLIENTES_STAGING
SET estado = 'ACTIVO'
WHERE id_cliente = 101;
```

---

## 21. Denegación de gobierno

```sql
USE ROLE M11_GOVERNANCE_ADMIN;
USE SECONDARY ROLES NONE;
USE WAREHOUSE WH_M11_SECURITY;
```

```sql
ALTER SESSION SET QUERY_TAG =
    'M11_E02_GOVERNANCE_DENIED';
```

Ejecuta individualmente. Debe fallar:

```sql
SELECT *
FROM DB_M11_SECURITY.CURATED.CLIENTES;
```

---

# Parte 6. Auditoría inmediata

## 22. Query History por usuario

Todas las acciones se han ejecutado con el mismo usuario y distintos roles.

```sql
USE ROLE M11_AUDITOR;
USE SECONDARY ROLES NONE;
USE WAREHOUSE WH_M11_SECURITY;
```

```sql
SELECT
    query_id,
    role_name,
    query_tag,
    execution_status,
    error_code,
    error_message,
    start_time,
    query_text
FROM TABLE(
    DB_M11_SECURITY.INFORMATION_SCHEMA
        .QUERY_HISTORY_BY_USER(
            END_TIME_RANGE_START =>
                DATEADD(
                    'hour',
                    -1,
                    CURRENT_TIMESTAMP()
                ),
            RESULT_LIMIT => 1000
        )
)
WHERE query_tag LIKE 'M11_E02_%'
ORDER BY start_time;
```

Esta fuente es adecuada para comprobación inmediata.

---

## 23. Login History inmediato

```sql
SELECT
    event_timestamp,
    user_name,
    client_ip,
    reported_client_type,
    first_authentication_factor,
    second_authentication_factor,
    is_success,
    error_code,
    error_message,
    login_details
FROM TABLE(
    DB_M11_SECURITY.INFORMATION_SCHEMA
        .LOGIN_HISTORY_BY_USER(
            TIME_RANGE_START =>
                DATEADD(
                    'day',
                    -1,
                    CURRENT_TIMESTAMP()
                ),
            RESULT_LIMIT => 20
        )
)
ORDER BY event_timestamp DESC;
```

La información de tipo y versión del cliente es declarada por el cliente y no debe tratarse como una identidad autenticada.

---

# Parte 7. Account Usage

## 24. Query History histórico

```sql
SELECT
    query_id,
    user_name,
    role_name,
    query_tag,
    execution_status,
    error_code,
    start_time,
    query_text
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE query_tag LIKE 'M11_E02_%'
  AND start_time >=
      DATEADD(
          'day',
          -1,
          CURRENT_TIMESTAMP()
      )
ORDER BY start_time;
```

Latencia máxima aproximada:

```text
45 minutos
```

---

## 25. Login History histórico

```sql
SELECT
    event_timestamp,
    user_name,
    client_ip,
    reported_client_type,
    first_authentication_factor,
    second_authentication_factor,
    is_success,
    error_code,
    error_message
FROM SNOWFLAKE.ACCOUNT_USAGE.LOGIN_HISTORY
WHERE user_name = $LAB_USER
  AND event_timestamp >=
      DATEADD(
          'day',
          -1,
          CURRENT_TIMESTAMP()
      )
ORDER BY event_timestamp DESC;
```

Latencia máxima aproximada:

```text
2 horas
```

---

## 26. Access History

`ACCESS_HISTORY` requiere Enterprise Edition y puede tardar hasta tres horas.

```sql
SELECT
    query_id,
    query_start_time,
    user_name,
    direct_objects_accessed,
    base_objects_accessed,
    objects_modified,
    policies_referenced
FROM SNOWFLAKE.ACCOUNT_USAGE.ACCESS_HISTORY
WHERE query_start_time >=
      DATEADD(
          'day',
          -1,
          CURRENT_TIMESTAMP()
      )
  AND (
      ARRAY_TO_STRING(
          direct_objects_accessed,
          ','
      ) ILIKE '%DB_M11_SECURITY%'
      OR
      ARRAY_TO_STRING(
          base_objects_accessed,
          ','
      ) ILIKE '%DB_M11_SECURITY%'
  )
ORDER BY query_start_time;
```

No esperes encontrar inmediatamente la actividad recién generada.

---

## 27. Extraer objetos con FLATTEN

Objetos base:

```sql
SELECT
    ah.query_id,
    ah.query_start_time,
    ah.user_name,
    obj.value:"objectDomain"::VARCHAR
        AS object_domain,
    obj.value:"objectName"::VARCHAR
        AS object_name,
    obj.value:"columns"
        AS columns_accessed
FROM SNOWFLAKE.ACCOUNT_USAGE.ACCESS_HISTORY ah,
LATERAL FLATTEN(
    INPUT => ah.base_objects_accessed
) obj
WHERE ah.query_start_time >=
      DATEADD(
          'day',
          -1,
          CURRENT_TIMESTAMP()
      )
  AND obj.value:"objectName"::VARCHAR
      ILIKE '%DB_M11_SECURITY%'
ORDER BY ah.query_start_time;
```

Policies:

```sql
SELECT
    ah.query_id,
    ah.query_start_time,
    ah.user_name,
    policy.value
FROM SNOWFLAKE.ACCOUNT_USAGE.ACCESS_HISTORY ah,
LATERAL FLATTEN(
    INPUT => ah.policies_referenced
) policy
WHERE ah.query_start_time >=
      DATEADD(
          'day',
          -1,
          CURRENT_TIMESTAMP()
      )
  AND ARRAY_SIZE(
      ah.policies_referenced
  ) > 0
ORDER BY ah.query_start_time;
```

Las consultas denegadas antes de acceder al objeto pueden aparecer en Query History, pero no necesariamente en Access History.

---

## 28. Auditar grants

```sql
SELECT
    created_on,
    privilege,
    granted_on,
    name,
    granted_to,
    grantee_name,
    granted_by
FROM SNOWFLAKE.ACCOUNT_USAGE.GRANTS_TO_ROLES
WHERE deleted_on IS NULL
  AND (
      grantee_name LIKE 'M11_%'
      OR name ILIKE 'DB_M11_SECURITY%'
  )
ORDER BY created_on DESC;
```

Busca especialmente:

- Grants directos a usuarios.
- Roles privilegiados.
- `MANAGE GRANTS`.
- `OWNERSHIP`.
- Privilegios `APPLY`.
- Acceso a `SNOWFLAKE` database roles.

---

# Parte 8. Informe

## 29. Plantilla de investigación

```text
Incidente:
Fecha y hora:
Usuario:
Rol:
Query ID:
Query Tag:
IP:
Cliente:
Método de autenticación:
Objeto y columnas:
Policies evaluadas:
Acción:
Resultado:
Impacto:
Medidas inmediatas:
Medidas preventivas:
```

Fuente recomendada:

| Necesidad | Fuente |
|---|---|
| Actividad inmediata | Information Schema Query History |
| Login inmediato | Information Schema Login History |
| Histórico de consultas | Account Usage Query History |
| Histórico de login | Account Usage Login History |
| Columnas y lineage | Access History |
| Policies evaluadas | Access History |
| Grants | Grants to Roles |

---

# Limpieza

## 30. Confirmar que nada está aplicado

```sql
USE ROLE SECURITYADMIN;

SHOW PARAMETERS LIKE 'NETWORK_POLICY'
IN ACCOUNT;

DESC USER IDENTIFIER($LAB_USER);
```

```sql
SHOW AUTHENTICATION POLICIES ON ACCOUNT;
```

La policy `NP_M11_CORPORATE` y las dos authentication policies no deben estar asignadas.

---

## 31. Eliminar los objetos

Primero elimina la network policy, que referencia las rules:

```sql
USE ROLE ACCOUNTADMIN;

DROP NETWORK POLICY IF EXISTS NP_M11_CORPORATE;
```

Elimina el esquema:

```sql
USE ROLE SYSADMIN;

DROP SCHEMA IF EXISTS
    DB_M11_SECURITY.SECURITY_OPS
CASCADE;
```

Revoca los database roles temporales:

```sql
USE ROLE ACCOUNTADMIN;

REVOKE DATABASE ROLE SNOWFLAKE.OBJECT_VIEWER
FROM ROLE M11_AUDITOR;

REVOKE DATABASE ROLE SNOWFLAKE.USAGE_VIEWER
FROM ROLE M11_AUDITOR;

REVOKE DATABASE ROLE SNOWFLAKE.GOVERNANCE_VIEWER
FROM ROLE M11_AUDITOR;

REVOKE DATABASE ROLE SNOWFLAKE.SECURITY_VIEWER
FROM ROLE M11_AUDITOR;
```

Elimina el rol:

```sql
USE ROLE SECURITYADMIN;

DROP ROLE IF EXISTS M11_SECURITY_OPERATIONS;
```

Restaura el Query Tag y suspende:

```sql
ALTER SESSION UNSET QUERY_TAG;

USE ROLE SYSADMIN;

ALTER WAREHOUSE WH_M11_SECURITY SUSPEND;
```

Conserva el modelo de seguridad del Ejercicio 1.

---

# Referencias oficiales

- [Network rules](https://docs.snowflake.com/en/user-guide/network-rules)
- [Network policies](https://docs.snowflake.com/en/user-guide/network-policies)
- [CREATE AUTHENTICATION POLICY](https://docs.snowflake.com/en/sql-reference/sql/create-authentication-policy)
- [Authentication policies](https://docs.snowflake.com/en/user-guide/authentication-policies)
- [QUERY_HISTORY table functions](https://docs.snowflake.com/en/sql-reference/functions/query_history)
- [LOGIN_HISTORY table functions](https://docs.snowflake.com/en/sql-reference/functions/login_history)
- [ACCESS_HISTORY](https://docs.snowflake.com/en/sql-reference/account-usage/access_history)
- [SNOWFLAKE database roles](https://docs.snowflake.com/en/sql-reference/snowflake-db-roles)

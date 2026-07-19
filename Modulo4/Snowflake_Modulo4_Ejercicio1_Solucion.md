# Módulo 4 · Ejercicio 1 · Solución

## Exposición segura de datos mediante views y secure views

---

# 1. Preparar el entorno

Abre un SQL File nuevo "M4_E1_EXPOSICION_DATOS.sql" en Snowsight y fija inicialmente el contexto administrativo.

```sql
USE ROLE SYSADMIN;

CREATE WAREHOUSE IF NOT EXISTS WH_DEV
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE;

USE WAREHOUSE WH_DEV;

CREATE DATABASE IF NOT EXISTS DB_CURSO;
CREATE SCHEMA IF NOT EXISTS DB_CURSO.M4_DATA;
CREATE SCHEMA IF NOT EXISTS DB_CURSO.M4_CONSUMO;
```

## Explicación

- `M4_DATA` será la zona restringida que contiene la información original.
- `M4_CONSUMO` será la capa que se ofrece a otros roles.
- Las vistas pueden estar en un esquema diferente al de las tablas que consultan.
- `AUTO_SUSPEND = 60` limita el consumo de créditos durante el laboratorio.

---

# 2. Crear los roles del ejercicio

La creación de roles se realiza con `USERADMIN`. La colocación de roles en una jerarquía se realiza normalmente con `SECURITYADMIN`.

```sql
USE ROLE USERADMIN;

CREATE ROLE IF NOT EXISTS M4_DATA_OWNER;
CREATE ROLE IF NOT EXISTS M4_CONSUMER;

USE ROLE SECURITYADMIN;

GRANT ROLE M4_DATA_OWNER TO ROLE SYSADMIN;
GRANT ROLE M4_CONSUMER TO ROLE SYSADMIN;
```

## Qué significa la jerarquía

Al conceder ambos roles a `SYSADMIN`:

- `SYSADMIN` hereda sus privilegios.
- Un usuario que tenga `SYSADMIN` puede utilizar los roles subordinados.
- Podemos cambiar a `M4_CONSUMER` para simular el comportamiento de un consumidor con privilegios limitados.

En este laboratorio los objetos se crean con `SYSADMIN`, que será su propietario. `M4_DATA_OWNER` queda preparado como representación del equipo responsable del dato, aunque no es imprescindible transferirle la propiedad para completar la práctica.

---

# 3. Crear y cargar la tabla sensible

```sql
USE ROLE SYSADMIN;
USE WAREHOUSE WH_DEV;

CREATE OR REPLACE TABLE DB_CURSO.M4_DATA.CLIENTES_SENSIBLES (
    ID_CLIENTE NUMBER(10,0) NOT NULL,
    NOMBRE     VARCHAR(100) NOT NULL,
    EMAIL      VARCHAR(200) NOT NULL,
    TELEFONO   VARCHAR(30),
    NIF        VARCHAR(20),
    REGION     VARCHAR(30) NOT NULL,
    ESTADO     VARCHAR(20) NOT NULL,
    SALDO      NUMBER(12,2) NOT NULL,
    FECHA_ALTA DATE NOT NULL
);

INSERT INTO DB_CURSO.M4_DATA.CLIENTES_SENSIBLES
    (ID_CLIENTE, NOMBRE, EMAIL, TELEFONO, NIF, REGION, ESTADO, SALDO, FECHA_ALTA)
VALUES
    (101, 'Ana García',    'ana.garcia@example.com',   '+34 600111222', '11111111A', 'CENTRO', 'ACTIVO',    850.25, '2024-01-15'),
    (102, 'Luis Martín',   'luis.martin@example.com',  '+34 600222333', '22222222B', 'NORTE',  'ACTIVO',   2450.00, '2023-11-03'),
    (103, 'Marta Pérez',   'marta.perez@example.com',  '+34 600333444', '33333333C', 'SUR',    'BLOQUEADO', 150.00, '2025-02-10'),
    (104, 'Carlos López',  'carlos.lopez@example.com', '+34 600444555', '44444444D', 'CENTRO', 'ACTIVO',   7800.50, '2022-07-21'),
    (105, 'Elena Torres',  'elena.torres@example.com', '+34 600555666', '55555555E', 'ESTE',   'INACTIVO', 1200.00, '2021-09-14'),
    (106, 'David Ruiz',    'david.ruiz@example.com',   '+34 600666777', '66666666F', 'SUR',    'ACTIVO',   4999.99, '2025-04-05');
```

Comprueba la carga:

```sql
SELECT COUNT(*) AS TOTAL_CLIENTES
FROM DB_CURSO.M4_DATA.CLIENTES_SENSIBLES;

SELECT ESTADO, COUNT(*) AS CLIENTES
FROM DB_CURSO.M4_DATA.CLIENTES_SENSIBLES
GROUP BY ESTADO
ORDER BY ESTADO;

SELECT *
FROM DB_CURSO.M4_DATA.CLIENTES_SENSIBLES
ORDER BY ID_CLIENTE;
```

Resultado esperado del recuento:

| Estado | Clientes |
|---|---:|
| ACTIVO | 4 |
| BLOQUEADO | 1 |
| INACTIVO | 1 |

La última consulta demuestra por qué la tabla no debe exponerse directamente: contiene nombre, correo, teléfono, NIF y saldo exacto.

---

# 4. Crear la view estándar para Soporte

```sql
CREATE OR REPLACE VIEW DB_CURSO.M4_CONSUMO.V_CLIENTES_SOPORTE AS
SELECT
    ID_CLIENTE,
    NOMBRE,
    LEFT(SPLIT_PART(EMAIL, '@', 1), 1)
        || '***@'
        || SPLIT_PART(EMAIL, '@', 2) AS EMAIL_ENMASCARADO,
    RIGHT(REGEXP_REPLACE(TELEFONO, '[^0-9]', ''), 4) AS TELEFONO_ULTIMOS_4,
    ESTADO,
    REGION
FROM DB_CURSO.M4_DATA.CLIENTES_SENSIBLES;
```

## Explicación del correo oculto

Para `ana.garcia@example.com`:

1. `SPLIT_PART(EMAIL, '@', 1)` devuelve `ana.garcia`.
2. `LEFT(..., 1)` conserva `a`.
3. `SPLIT_PART(EMAIL, '@', 2)` devuelve `example.com`.
4. La concatenación genera `a***@example.com`.

## Explicación del teléfono

```sql
REGEXP_REPLACE(TELEFONO, '[^0-9]', '')
```

elimina espacios, el símbolo `+` y cualquier carácter no numérico. Después, `RIGHT(..., 4)` conserva los cuatro últimos dígitos.

Comprueba la vista como propietario:

```sql
SELECT *
FROM DB_CURSO.M4_CONSUMO.V_CLIENTES_SOPORTE
ORDER BY ID_CLIENTE;
```

Esta view es adecuada para simplificar y limitar columnas, pero su definición SQL no está protegida frente a un usuario autorizado a inspeccionarla.

---

# 5. Crear la secure view para el partner

```sql
CREATE OR REPLACE SECURE VIEW DB_CURSO.M4_CONSUMO.SV_CLIENTES_PARTNER AS
SELECT
    SHA2(TO_VARCHAR(ID_CLIENTE), 256) AS CLIENTE_TOKEN,
    REGION,
    FECHA_ALTA,
    CASE
        WHEN SALDO < 1000 THEN 'BAJO'
        WHEN SALDO < 5000 THEN 'MEDIO'
        ELSE 'ALTO'
    END AS SEGMENTO_SALDO
FROM DB_CURSO.M4_DATA.CLIENTES_SENSIBLES
WHERE ESTADO = 'ACTIVO';
```

## Qué protege esta vista

La vista:

- Excluye clientes bloqueados e inactivos.
- Sustituye el identificador interno por un hash.
- No expone nombres, correos, teléfonos ni NIF.
- Sustituye el saldo exacto por una categoría.
- Oculta su definición a roles no autorizados.

## Qué no hace automáticamente

El uso de `SECURE` no decide qué columnas son sensibles. La seguridad depende también de la sentencia `SELECT` escrita por el propietario.

Una secure view tampoco cifra de nuevo la tabla ni copia sus datos. Sigue siendo una consulta lógica sobre la tabla base.

Comprueba su resultado como propietario:

```sql
SELECT *
FROM DB_CURSO.M4_CONSUMO.SV_CLIENTES_PARTNER
ORDER BY REGION, FECHA_ALTA;
```

Deben aparecer cuatro filas, una por cada cliente inicialmente activo.

---

# 6. Conceder acceso mínimo al consumidor

```sql
USE ROLE SYSADMIN;

GRANT USAGE ON WAREHOUSE WH_DEV
TO ROLE M4_CONSUMER;

GRANT USAGE ON DATABASE DB_CURSO
TO ROLE M4_CONSUMER;

GRANT USAGE ON SCHEMA DB_CURSO.M4_CONSUMO
TO ROLE M4_CONSUMER;

GRANT SELECT ON VIEW DB_CURSO.M4_CONSUMO.V_CLIENTES_SOPORTE
TO ROLE M4_CONSUMER;

GRANT SELECT ON VIEW DB_CURSO.M4_CONSUMO.SV_CLIENTES_PARTNER
TO ROLE M4_CONSUMER;
```

Observa lo que no se ha concedido:

```text
USAGE sobre DB_CURSO.M4_DATA
SELECT sobre DB_CURSO.M4_DATA.CLIENTES_SENSIBLES
```

Snowflake permite que un usuario consulte una vista sin tener privilegios directos sobre sus tablas subyacentes. La vista se ejecuta utilizando los privilegios del rol propietario del objeto.

---

# 7. Probar el acceso con el rol consumidor

Cambia de rol y desactiva explícitamente los roles secundarios para evitar que `SYSADMIN` aporte privilegios indirectos.

```sql
USE ROLE M4_CONSUMER;
USE SECONDARY ROLES NONE;
USE WAREHOUSE WH_DEV;
```

## 7.1 Consultar la view de Soporte

```sql
SELECT *
FROM DB_CURSO.M4_CONSUMO.V_CLIENTES_SOPORTE
ORDER BY ID_CLIENTE;
```

La consulta debe funcionar.

Comprueba que:

- El correo aparece parcialmente oculto.
- Solo se muestran cuatro dígitos del teléfono.
- No aparecen NIF ni saldo.

## 7.2 Consultar la secure view del partner

```sql
SELECT *
FROM DB_CURSO.M4_CONSUMO.SV_CLIENTES_PARTNER
ORDER BY REGION, FECHA_ALTA;
```

La consulta debe funcionar y solo debe devolver clientes activos.

## 7.3 Intentar acceder a la tabla base

```sql
SELECT *
FROM DB_CURSO.M4_DATA.CLIENTES_SENSIBLES;
```

La consulta debe fallar con un error de objeto inexistente o de privilegios insuficientes, dependiendo de la información que Snowflake pueda revelar al rol.

Este error es el resultado esperado. Demuestra que el consumidor puede utilizar el producto de datos sin acceder al origen sensible.

---

# 8. Comparar la visibilidad de las definiciones

## 8.1 Consultar Information Schema

```sql
SELECT
    TABLE_NAME,
    IS_SECURE,
    VIEW_DEFINITION
FROM DB_CURSO.INFORMATION_SCHEMA.VIEWS
WHERE TABLE_SCHEMA = 'M4_CONSUMO'
  AND TABLE_NAME IN ('V_CLIENTES_SOPORTE', 'SV_CLIENTES_PARTNER')
ORDER BY TABLE_NAME;
```

Como `M4_CONSUMER`, el resultado debe mostrar:

- `IS_SECURE = 'NO'` para `V_CLIENTES_SOPORTE`.
- `IS_SECURE = 'YES'` para `SV_CLIENTES_PARTNER`.
- La definición de la view estándar puede estar visible.
- La lógica interna de la secure view no debe quedar expuesta al consumidor.

La representación exacta puede ser `NULL`, texto redaccionado o ausencia de detalle, según el mecanismo y los privilegios efectivos.

## 8.2 Utilizar SHOW VIEWS

```sql
SHOW VIEWS IN SCHEMA DB_CURSO.M4_CONSUMO;
```

Para analizar el resultado tabular de `SHOW`:

```sql
SELECT
    "name",
    "is_secure",
    "text"
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
WHERE "name" IN ('V_CLIENTES_SOPORTE', 'SV_CLIENTES_PARTNER')
ORDER BY "name";
```

Las columnas de los resultados de `SHOW` se escriben entre comillas porque sus nombres se devuelven en minúsculas y son sensibles a mayúsculas cuando se referencian como identificadores delimitados.

## 8.3 Probar GET_DDL

```sql
SELECT GET_DDL(
    'VIEW',
    'DB_CURSO.M4_CONSUMO.V_CLIENTES_SOPORTE'
);
```

El consumidor puede llegar a ver la definición de la view estándar.

```sql
SELECT GET_DDL(
    'VIEW',
    'DB_CURSO.M4_CONSUMO.SV_CLIENTES_PARTNER'
);
```

La definición completa de la secure view no debe revelarse a un rol que no sea su propietario ni tenga privilegios administrativos específicos para inspeccionar objetos.

> Al realizar esta prueba es esencial mantener `USE SECONDARY ROLES NONE`. De lo contrario, un rol administrativo secundario podría hacer visible información que el consumidor real no tendría.

---

# 9. Comprobar que las vistas reflejan los cambios de la tabla base

## 9.1 Modificar los datos como propietario

```sql
USE ROLE SYSADMIN;
USE WAREHOUSE WH_DEV;

-- El cliente 102 deja de estar activo.
UPDATE DB_CURSO.M4_DATA.CLIENTES_SENSIBLES
SET ESTADO = 'INACTIVO'
WHERE ID_CLIENTE = 102;

-- El cliente 101 pasa del segmento BAJO al segmento ALTO.
UPDATE DB_CURSO.M4_DATA.CLIENTES_SENSIBLES
SET SALDO = 5200.00
WHERE ID_CLIENTE = 101;

-- Se incorpora un nuevo cliente activo.
INSERT INTO DB_CURSO.M4_DATA.CLIENTES_SENSIBLES
    (ID_CLIENTE, NOMBRE, EMAIL, TELEFONO, NIF, REGION, ESTADO, SALDO, FECHA_ALTA)
VALUES
    (107, 'Sofía Navarro', 'sofia.navarro@example.com',
     '+34 600777888', '77777777G', 'OESTE', 'ACTIVO', 3200.00, CURRENT_DATE());
```

## 9.2 Consultar de nuevo como consumidor

```sql
USE ROLE M4_CONSUMER;
USE SECONDARY ROLES NONE;
USE WAREHOUSE WH_DEV;

SELECT *
FROM DB_CURSO.M4_CONSUMO.V_CLIENTES_SOPORTE
ORDER BY ID_CLIENTE;

SELECT *
FROM DB_CURSO.M4_CONSUMO.SV_CLIENTES_PARTNER
ORDER BY REGION, FECHA_ALTA;
```

## Resultado esperado

En `V_CLIENTES_SOPORTE`:

- El cliente 102 sigue apareciendo, pero con estado `INACTIVO`.
- El cliente 107 aparece automáticamente.

En `SV_CLIENTES_PARTNER`:

- El cliente 102 desaparece porque ya no está activo.
- El cliente 107 aparece con segmento `MEDIO`.
- El token correspondiente al cliente 101 sigue siendo el mismo, pero su segmento cambia de `BAJO` a `ALTO`.

No ha sido necesario recrear ni refrescar las vistas. Una view normal y una secure view evalúan su consulta sobre el estado actual de las tablas cada vez que se utilizan.

---

# 10. Inspeccionar los grants finales

Vuelve a un rol administrativo y revisa los privilegios concedidos.

```sql
USE ROLE SECURITYADMIN;

SHOW GRANTS TO ROLE M4_CONSUMER;
```

Debes encontrar:

- `USAGE` sobre `WH_DEV`.
- `USAGE` sobre `DB_CURSO`.
- `USAGE` sobre `DB_CURSO.M4_CONSUMO`.
- `SELECT` sobre las dos vistas.

No debe aparecer `SELECT` sobre `CLIENTES_SENSIBLES` ni `USAGE` sobre `M4_DATA`.

---

# 11. Respuestas a las preguntas de reflexión

## 1. ¿Una secure view cifra los datos almacenados en la tabla base?

No. Snowflake cifra los datos en reposo y en tránsito como parte de la plataforma, pero la palabra `SECURE` aplicada a una vista no añade una copia cifrada nueva. Protege la definición y evita determinadas optimizaciones que podrían permitir inferencias sobre filas ocultas.

## 2. ¿Una secure view elimina automáticamente las columnas sensibles?

No. El diseñador debe seleccionar, transformar, filtrar o excluir explícitamente cada dato. Una secure view mal diseñada puede seguir mostrando información sensible.

## 3. ¿Por qué no debe utilizarse `SECURE` en todas las vistas?

Las secure views desactivan determinadas optimizaciones internas necesarias para proteger la información subyacente. Esto puede reducir el rendimiento. Deben reservarse para casos donde la privacidad y la protección de la lógica de la vista sean requisitos reales.

Una view estándar suele ser suficiente para:

- Simplificar consultas.
- Reutilizar lógica SQL no sensible.
- Presentar un modelo semántico interno.
- Ocultar tablas al consumidor cuando no existe riesgo de inferencia ni necesidad de proteger la definición.

## 4. ¿Qué privilegios mínimos necesita el consumidor?

Normalmente:

- `USAGE` sobre el warehouse que ejecutará la consulta.
- `USAGE` sobre la base de datos que contiene la vista.
- `USAGE` sobre el esquema que contiene la vista.
- `SELECT` sobre la vista.

No necesita `SELECT` sobre las tablas subyacentes.

## 5. ¿Qué riesgo tienen los identificadores secuenciales?

Aunque no muestren un nombre, los huecos o diferencias entre identificadores pueden permitir inferir el número de registros creados, la actividad del sistema o el volumen de clientes. En exposiciones sensibles es preferible no mostrar la sequence o sustituirla por un identificador aleatorio o seudonimizado.

---

# 12. Limpieza opcional

La limpieza no es obligatoria si los objetos se reutilizarán en módulos posteriores.

```sql
USE ROLE SYSADMIN;

DROP VIEW IF EXISTS DB_CURSO.M4_CONSUMO.V_CLIENTES_SOPORTE;
DROP VIEW IF EXISTS DB_CURSO.M4_CONSUMO.SV_CLIENTES_PARTNER;
DROP TABLE IF EXISTS DB_CURSO.M4_DATA.CLIENTES_SENSIBLES;
```

Para eliminar también los roles:

```sql
USE ROLE USERADMIN;
DROP ROLE IF EXISTS M4_CONSUMER;
DROP ROLE IF EXISTS M4_DATA_OWNER;
```

Suspende el warehouse al finalizar:

```sql
USE ROLE SYSADMIN;
ALTER WAREHOUSE WH_DEV SUSPEND;
```

---

## Documentación oficial de referencia

- Secure views: <https://docs.snowflake.com/en/user-guide/views-secure>
- `CREATE VIEW`: <https://docs.snowflake.com/en/sql-reference/sql/create-view>
- Trial accounts y limitaciones actuales: <https://docs.snowflake.com/en/user-guide/admin-trial-account>

---

# 13. Conclusión

El patrón implementado es:

```text
Tabla sensible
      ↓
Capa de views controlada por el propietario
      ↓
Grants mínimos al consumidor
```

La view estándar proporciona una interfaz simplificada para Soporte. La secure view añade protección de la definición y reduce el riesgo de inferencia para un consumidor externo.

Con este ejercicio queda cubierto el contenido práctico necesario del **módulo 4**:

- Tipos de tabla, datos, sequences y constraints.
- JSON, `VARIANT` y `LATERAL FLATTEN`.
- Views estándar y secure views.

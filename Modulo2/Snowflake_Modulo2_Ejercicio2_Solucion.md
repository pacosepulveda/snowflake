# Módulo 2 - Ejercicio 2 - Solución guiada

## Control de acceso con RBAC y mínimo privilegio

**Cuenta prevista:** Snowflake Trial, edición Enterprise  
**Interfaz:** Snowsight  

---

## 1. Resultado que vamos a construir

Crearemos este rol:

```text
SYSADMIN
└── ROL_ANALISTA_VENTAS
```

El rol podrá:

```text
WH_LAB_M2                         USAGE
DB_CURSO                          USAGE
DB_CURSO.CURATED                  USAGE
├── tablas existentes             SELECT
└── tablas futuras                SELECT
DB_CURSO.MARTS                    USAGE
├── vistas existentes             SELECT
└── vistas futuras                SELECT
```

El rol no tendrá acceso a:

```text
DB_CURSO.STAGING
```

Tampoco recibirá `INSERT`, `UPDATE`, `DELETE`, `CREATE`, `MODIFY`, `OPERATE` ni `OWNERSHIP`.

---

## 2. Ideas clave antes de comenzar

Snowflake combina tres elementos:

1. **Privilegios:** acciones concretas como `USAGE`, `SELECT` o `INSERT`.
2. **Roles:** reciben privilegios sobre objetos.
3. **Usuarios:** reciben roles y activan uno como rol principal de la sesión.

La relación habitual es:

```text
PRIVILEGIO → ROL → USUARIO
```

Además, los roles pueden formar una jerarquía. Cuando un rol se concede a otro, el rol superior hereda los privilegios del inferior.

En este ejercicio utilizaremos tres roles del sistema con responsabilidades diferentes:

| Rol | Uso en el ejercicio |
|---|---|
| `USERADMIN` | Crear el rol personalizado |
| `SECURITYADMIN` | Conceder el rol a `SYSADMIN` y al usuario |
| `SYSADMIN` | Conceder acceso a los objetos que administra |

Esta separación permite comprobar que administrar identidades y administrar objetos son responsabilidades distintas.

---

## 3. Crear el SQL File

1. Abre Snowsight.
2. Crea un SQL File.
3. Cámbiale el nombre a `M2_E2_RBAC_MINIMO_PRIVILEGIO`.
4. Ejecuta los bloques en el orden indicado.

Los intentos que deben fallar aparecen identificados como **pruebas negativas**. Ejecútalos uno por uno.

---

## 4. Verificar los prerrequisitos

Selecciona `SYSADMIN` y el warehouse del laboratorio:

```sql
USE ROLE SYSADMIN;
USE WAREHOUSE WH_LAB_M2;
```

Comprueba que existen los objetos del ejercicio anterior:

```sql
SHOW TABLES LIKE 'VENTAS' IN SCHEMA DB_CURSO.CURATED;
SHOW VIEWS LIKE 'V_VENTAS_DIARIAS' IN SCHEMA DB_CURSO.MARTS;
SHOW WAREHOUSES LIKE 'WH_LAB_M2';
```

También puedes hacer una comprobación funcional:

```sql
SELECT COUNT(*) AS NUMERO_VENTAS
FROM DB_CURSO.CURATED.VENTAS;

SELECT *
FROM DB_CURSO.MARTS.V_VENTAS_DIARIAS
ORDER BY FECHA;
```

Si alguno de estos objetos no existe, completa primero el ejercicio 1.

---

## 5. Identificar el usuario actual

Ejecuta:

```sql
SELECT CURRENT_USER() AS USUARIO_DEL_LABORATORIO;
```

Copia exactamente el valor devuelto. Lo utilizaremos en el `GRANT ROLE`.

Ejemplo de resultado:

```text
FRANCISCO
```

En los siguientes pasos aparecerá el marcador:

```text
<TU_USUARIO>
```

Debes sustituirlo por el valor real, sin los símbolos `<` y `>`.

Ejemplo (no ejecutes esta sentencia, porque el rol aún no está creado y fallará):

```sql
GRANT ROLE ROL_ANALISTA_VENTAS TO USER FRANCISCO;
```

Si el nombre fue creado como identificador entre comillas, contiene caracteres especiales o distingue mayúsculas y minúsculas, escríbelo entre comillas dobles exactamente como está almacenado.

---

## 6. Preparar una tabla restringida en STAGING

Esta tabla existe únicamente para comprobar que el analista no puede acceder a los datos crudos.

```sql
USE ROLE SYSADMIN;
USE WAREHOUSE WH_LAB_M2;

CREATE OR REPLACE TABLE DB_CURSO.STAGING.VENTAS_RAW_CONTROL (
    ID_LOTE         NUMBER(10,0) NOT NULL,
    FECHA_RECEPCION TIMESTAMP_NTZ NOT NULL,
    CONTENIDO_RAW   VARCHAR       NOT NULL
)
COMMENT = 'Datos crudos utilizados para validar la ausencia de acceso a STAGING';

INSERT INTO DB_CURSO.STAGING.VENTAS_RAW_CONTROL
    (ID_LOTE, FECHA_RECEPCION, CONTENIDO_RAW)
VALUES
    (1001, '2026-07-15 08:30:00', 'cliente=Alba Norte;importe=245.50'),
    (1002, '2026-07-15 08:35:00', 'cliente=Centro Market;importe=475.25');
```

Comprueba que `SYSADMIN` sí puede verla:

```sql
SELECT *
FROM DB_CURSO.STAGING.VENTAS_RAW_CONTROL
ORDER BY ID_LOTE;
```

### Por qué creamos un objeto real

Si la tabla no existiese, una consulta posterior fallaría por ausencia del objeto, no necesariamente por falta de permisos. Al crearla de antemano sabemos que el error del analista se debe al diseño de acceso.

Snowflake puede mostrar un mensaje equivalente a “objeto no existe o no autorizado”. Esta formulación evita revelar la existencia de objetos a usuarios sin privilegios.

---

## 7. Crear el rol personalizado

Cambia a `USERADMIN`:

```sql
USE ROLE USERADMIN;
```

Crea el rol:

```sql
CREATE ROLE IF NOT EXISTS ROL_ANALISTA_VENTAS
    COMMENT = 'Consulta de ventas curadas y marts sin permisos de escritura';
```

Comprueba su existencia:

```sql
SHOW ROLES LIKE 'ROL_ANALISTA_VENTAS';
```

### Explicación

`USERADMIN` dispone por defecto del privilegio global `CREATE ROLE`. El nuevo rol todavía no permite hacer nada: crear un rol y concederle privilegios son operaciones independientes.

---

## 8. Incorporar el rol a la jerarquía

Cambia a `SECURITYADMIN`:

```sql
USE ROLE SECURITYADMIN;
```

Concede el rol personalizado a `SYSADMIN`:

```sql
GRANT ROLE ROL_ANALISTA_VENTAS TO ROLE SYSADMIN;
```

La instrucción anterior significa:

```text
SYSADMIN hereda ROL_ANALISTA_VENTAS
```

No significa que el analista herede `SYSADMIN`. La dirección del grant es importante.

Ahora asigna el rol al usuario del laboratorio. Sustituye `<TU_USUARIO>`:

```sql
GRANT ROLE ROL_ANALISTA_VENTAS TO USER <TU_USUARIO>;
```

Ejemplo:

```sql
GRANT ROLE ROL_ANALISTA_VENTAS TO USER FRANCISCO;
```

Comprueba a quién se ha concedido el rol:

```sql
SHOW GRANTS OF ROLE ROL_ANALISTA_VENTAS;
```

Deberías encontrar, como mínimo:

- Una fila con `granted_to = ROLE` y `grantee_name = SYSADMIN`.
- Una fila con `granted_to = USER` y el nombre de tu usuario.

### Por qué usamos SECURITYADMIN

`SECURITYADMIN` dispone por defecto de `MANAGE GRANTS`, que permite gestionar concesiones de roles y privilegios en la cuenta.

---

## 9. Conceder privilegios mínimos sobre los objetos

Vuelve a `SYSADMIN`, que creó y administra los objetos del laboratorio:

```sql
USE ROLE SYSADMIN;
```

### 9.1 Uso del warehouse

```sql
GRANT USAGE
ON WAREHOUSE WH_LAB_M2
TO ROLE ROL_ANALISTA_VENTAS;
```

`USAGE` permite utilizar el warehouse para ejecutar consultas. No concede la capacidad de modificarlo, suspenderlo manualmente o redimensionarlo.

### 9.2 Acceso a la base de datos

```sql
GRANT USAGE
ON DATABASE DB_CURSO
TO ROLE ROL_ANALISTA_VENTAS;
```

El acceso a un objeto de un esquema requiere poder atravesar sus contenedores. Por eso `SELECT` sobre una tabla no es suficiente si falta `USAGE` sobre la base de datos o el esquema.

### 9.3 Acceso a los esquemas permitidos

```sql
GRANT USAGE
ON SCHEMA DB_CURSO.CURATED
TO ROLE ROL_ANALISTA_VENTAS;

GRANT USAGE
ON SCHEMA DB_CURSO.MARTS
TO ROLE ROL_ANALISTA_VENTAS;
```

No ejecutamos ningún grant sobre `DB_CURSO.STAGING`.

### 9.4 Tablas existentes de CURATED

```sql
GRANT SELECT
ON ALL TABLES IN SCHEMA DB_CURSO.CURATED
TO ROLE ROL_ANALISTA_VENTAS;
```

Este grant se materializa sobre cada tabla que existe en ese momento. Incluye `VENTAS`.

### 9.5 Tablas futuras de CURATED

```sql
GRANT SELECT
ON FUTURE TABLES IN SCHEMA DB_CURSO.CURATED
TO ROLE ROL_ANALISTA_VENTAS;
```

Este grant no se aplica retroactivamente. Define qué ocurrirá cuando se creen nuevas tablas. Por eso necesitamos tanto `ALL TABLES` como `FUTURE TABLES`.

### 9.6 Vistas existentes de MARTS

```sql
GRANT SELECT
ON ALL VIEWS IN SCHEMA DB_CURSO.MARTS
TO ROLE ROL_ANALISTA_VENTAS;
```

Incluye la vista `V_VENTAS_DIARIAS` creada en el ejercicio 1.

### 9.7 Vistas futuras de MARTS

```sql
GRANT SELECT
ON FUTURE VIEWS IN SCHEMA DB_CURSO.MARTS
TO ROLE ROL_ANALISTA_VENTAS;
```

Cuando se cree una nueva vista en `MARTS`, el rol recibirá `SELECT` automáticamente.

### Privilegios que deliberadamente no concedemos

No ejecutamos grants de:

```text
INSERT
UPDATE
DELETE
TRUNCATE
CREATE TABLE
CREATE VIEW
MODIFY
OPERATE
OWNERSHIP
```

El objetivo no es construir una lista de denegaciones. En Snowflake, lo que no se concede no está permitido.

---

## 10. Auditar la configuración inicial

Muestra los grants directos del rol:

```sql
SHOW GRANTS TO ROLE ROL_ANALISTA_VENTAS;
```

Deberías ver filas para:

- `USAGE` sobre `WH_LAB_M2`.
- `USAGE` sobre `DB_CURSO`.
- `USAGE` sobre `DB_CURSO.CURATED`.
- `USAGE` sobre `DB_CURSO.MARTS`.
- `SELECT` sobre los objetos existentes correspondientes.

Muestra los privilegios futuros:

```sql
SHOW FUTURE GRANTS TO ROLE ROL_ANALISTA_VENTAS;
```

Deberías encontrar:

- `SELECT` sobre futuras tablas de `DB_CURSO.CURATED`.
- `SELECT` sobre futuras vistas de `DB_CURSO.MARTS`.

También puedes inspeccionarlos por esquema:

```sql
SHOW FUTURE GRANTS IN SCHEMA DB_CURSO.CURATED;
SHOW FUTURE GRANTS IN SCHEMA DB_CURSO.MARTS;
```

> Los comandos `SHOW GRANTS` no necesitan un warehouse en ejecución. Son operaciones de metadatos gestionadas por la capa de Cloud Services.

---

## 11. Crear objetos después de los future grants

Los siguientes objetos se crean después de haber configurado los privilegios futuros.

### 11.1 Crear la tabla OBJETIVOS_REGION

```sql
USE ROLE SYSADMIN;
USE WAREHOUSE WH_LAB_M2;

CREATE OR REPLACE TABLE DB_CURSO.CURATED.OBJETIVOS_REGION (
    REGION           VARCHAR(50)  NOT NULL,
    OBJETIVO_MENSUAL NUMBER(12,2) NOT NULL
)
COMMENT = 'Objetivos mensuales de ventas por region';

INSERT INTO DB_CURSO.CURATED.OBJETIVOS_REGION
    (REGION, OBJETIVO_MENSUAL)
VALUES
    ('NORTE',  3000.00),
    ('SUR',    1500.00),
    ('ESTE',   2500.00),
    ('CENTRO', 2200.00);
```

Comprueba los datos:

```sql
SELECT *
FROM DB_CURSO.CURATED.OBJETIVOS_REGION
ORDER BY REGION;
```

### 11.2 Crear la vista V_VENTAS_REGION

```sql
CREATE OR REPLACE VIEW DB_CURSO.MARTS.V_VENTAS_REGION AS
SELECT
    V.REGION,
    COUNT(*) AS NUMERO_VENTAS,
    SUM(V.IMPORTE) AS IMPORTE_VENDIDO,
    O.OBJETIVO_MENSUAL,
    ROUND(
        SUM(V.IMPORTE) / NULLIF(O.OBJETIVO_MENSUAL, 0) * 100,
        2
    ) AS PORCENTAJE_OBJETIVO
FROM DB_CURSO.CURATED.VENTAS AS V
LEFT JOIN DB_CURSO.CURATED.OBJETIVOS_REGION AS O
    ON V.REGION = O.REGION
GROUP BY
    V.REGION,
    O.OBJETIVO_MENSUAL;
```

Consulta la vista como `SYSADMIN`:

```sql
SELECT *
FROM DB_CURSO.MARTS.V_VENTAS_REGION
ORDER BY REGION;
```

Resultados esperados con los datos del ejercicio 1:

| Región | Número de ventas | Importe vendido | Objetivo | Porcentaje aproximado |
|---|---:|---:|---:|---:|
| `CENTRO` | 2 | 1255.35 | 2200.00 | 57.06 |
| `ESTE` | 2 | 1510.40 | 2500.00 | 60.42 |
| `NORTE` | 2 | 1595.50 | 3000.00 | 53.18 |
| `SUR` | 2 | 430.75 | 1500.00 | 28.72 |

### 11.3 Confirmar que los future grants se materializaron

```sql
SHOW GRANTS ON TABLE DB_CURSO.CURATED.OBJETIVOS_REGION;
SHOW GRANTS ON VIEW DB_CURSO.MARTS.V_VENTAS_REGION;
```

En ambos resultados debe aparecer una fila con:

```text
privilege = SELECT
grantee_name = ROL_ANALISTA_VENTAS
```

No hemos ejecutado un grant específico sobre ninguno de esos dos objetos. El acceso proviene de los future grants.

---

## 12. Desactivar los roles secundarios

Este paso es esencial para que la prueba sea válida.

Un usuario puede tener varios roles concedidos. Snowflake permite activar roles secundarios además del rol principal. Si `SYSADMIN` permaneciese activo como rol secundario, algunas operaciones podrían utilizar sus privilegios y parecería que `ROL_ANALISTA_VENTAS` tiene más permisos de los que realmente posee.

Desactiva los roles secundarios:

```sql
USE SECONDARY ROLES NONE;
```

Activa el rol del analista:

```sql
USE ROLE ROL_ANALISTA_VENTAS;
```

Selecciona el contexto permitido:

```sql
USE WAREHOUSE WH_LAB_M2;
USE DATABASE DB_CURSO;
USE SCHEMA CURATED;
```

Comprueba el contexto:

```sql
SELECT
    CURRENT_USER()            AS USUARIO_ACTUAL,
    CURRENT_ROLE()            AS ROL_PRINCIPAL,
    CURRENT_SECONDARY_ROLES() AS ROLES_SECUNDARIOS,
    CURRENT_WAREHOUSE()       AS WAREHOUSE_ACTUAL,
    CURRENT_DATABASE()        AS BASE_DATOS_ACTUAL,
    CURRENT_SCHEMA()          AS ESQUEMA_ACTUAL,
    CURRENT_VERSION()         AS VERSION_SNOWFLAKE;
```

Valores esperados:

| Columna | Valor esperado |
|---|---|
| `ROL_PRINCIPAL` | `ROL_ANALISTA_VENTAS` |
| `ROLES_SECUNDARIOS` | Debe indicar `NONE` o una lista vacía |
| `WAREHOUSE_ACTUAL` | `WH_LAB_M2` |
| `BASE_DATOS_ACTUAL` | `DB_CURSO` |
| `ESQUEMA_ACTUAL` | `CURATED` |

---

## 13. Validar las operaciones permitidas

### 13.1 Consultar la tabla VENTAS

```sql
SELECT *
FROM DB_CURSO.CURATED.VENTAS
ORDER BY FECHA, ID_VENTA;
```

Debe funcionar porque el rol tiene:

```text
USAGE sobre DB_CURSO
USAGE sobre DB_CURSO.CURATED
SELECT sobre la tabla VENTAS
USAGE sobre WH_LAB_M2
```

### 13.2 Consultar la vista existente V_VENTAS_DIARIAS

```sql
SELECT *
FROM DB_CURSO.MARTS.V_VENTAS_DIARIAS
ORDER BY FECHA;
```

Debe funcionar gracias al grant sobre todas las vistas existentes de `MARTS`.

El rol no necesita `SELECT` directo sobre cada objeto subyacente de una vista para consultarla. El privilegio se concede sobre la vista como objeto de acceso.

### 13.3 Consultar la tabla futura OBJETIVOS_REGION

```sql
SELECT *
FROM DB_CURSO.CURATED.OBJETIVOS_REGION
ORDER BY REGION;
```

Debe funcionar gracias al future grant sobre tablas de `CURATED`.

### 13.4 Consultar la vista futura V_VENTAS_REGION

```sql
SELECT *
FROM DB_CURSO.MARTS.V_VENTAS_REGION
ORDER BY REGION;
```

Debe funcionar gracias al future grant sobre vistas de `MARTS`.

### 13.5 Ejecutar una consulta agregada

```sql
SELECT
    REGION,
    COUNT(*) AS NUMERO_VENTAS,
    SUM(IMPORTE) AS IMPORTE_TOTAL,
    AVG(IMPORTE) AS IMPORTE_MEDIO
FROM DB_CURSO.CURATED.VENTAS
GROUP BY REGION
ORDER BY IMPORTE_TOTAL DESC;
```

`SELECT` permite proyectar, filtrar, ordenar y agregar los datos. No significa que el rol pueda modificarlos.

---

## 14. Validar las operaciones denegadas

Ejecuta cada instrucción por separado. Los mensajes exactos pueden variar ligeramente según la versión y el contexto de la cuenta, pero todas deben ser rechazadas.

### 14.1 Prueba negativa: acceso a STAGING

```sql
SELECT *
FROM DB_CURSO.STAGING.VENTAS_RAW_CONTROL;
```

Resultado esperado: error similar a:

```text
Object does not exist or not authorized.
```

La tabla existe, pero el rol no tiene `USAGE` sobre el esquema `STAGING` ni `SELECT` sobre la tabla.

### 14.2 Prueba negativa: insertar datos

```sql
INSERT INTO DB_CURSO.CURATED.VENTAS
    (ID_VENTA, FECHA, CLIENTE, REGION, IMPORTE)
VALUES
    (999, CURRENT_DATE(), 'Cliente no autorizado', 'NORTE', 100.00);
```

Resultado esperado: error de privilegios insuficientes.

El rol tiene `SELECT`, pero no `INSERT`.

Comprueba después que la fila no se añadió:

```sql
SELECT COUNT(*) AS FILAS_ID_999
FROM DB_CURSO.CURATED.VENTAS
WHERE ID_VENTA = 999;
```

Resultado esperado:

```text
0
```

### 14.3 Prueba negativa: crear una tabla

```sql
CREATE TABLE DB_CURSO.MARTS.TABLA_NO_AUTORIZADA (
    ID NUMBER
);
```

Resultado esperado: error de privilegios insuficientes sobre el esquema.

El rol tiene `USAGE` sobre `MARTS`, pero no `CREATE TABLE`.

### 14.4 Prueba negativa: suspender el warehouse

```sql
ALTER WAREHOUSE WH_LAB_M2 SUSPEND;
```

Resultado esperado: error de privilegios insuficientes.

`USAGE` permite utilizar el warehouse. Para suspenderlo o reanudarlo manualmente se necesita un privilegio de operación más amplio, que no hemos concedido.

### Interpretación

Un diseño de mínimo privilegio no se valida únicamente demostrando lo que funciona. También hay que probar que las acciones no autorizadas fallan.

---

## 15. Volver a un contexto administrativo

Activa `SYSADMIN`:

```sql
USE ROLE SYSADMIN;
```

Restaura los roles secundarios para el funcionamiento habitual de la sesión:

```sql
USE SECONDARY ROLES ALL;
```

Comprueba el contexto:

```sql
SELECT
    CURRENT_ROLE() AS ROL_PRINCIPAL,
    CURRENT_SECONDARY_ROLES() AS ROLES_SECUNDARIOS;
```

---

## 16. Auditoría final

Para realizar una auditoría completa, utiliza `SECURITYADMIN`, que dispone por defecto de `MANAGE GRANTS`:

```sql
USE ROLE SECURITYADMIN;
```

### 16.1 Privilegios directos del rol

```sql
SHOW GRANTS TO ROLE ROL_ANALISTA_VENTAS;
```

Revisa que no aparezcan privilegios de escritura, creación o administración.

### 16.2 Future grants del rol

```sql
SHOW FUTURE GRANTS TO ROLE ROL_ANALISTA_VENTAS;
```

Deben aparecer los future grants de tablas en `CURATED` y vistas en `MARTS`.

### 16.3 Destinatarios del rol

```sql
SHOW GRANTS OF ROLE ROL_ANALISTA_VENTAS;
```

Debe estar concedido a:

- `SYSADMIN`.
- Tu usuario.

### 16.4 Grants de los objetos futuros

```sql
SHOW GRANTS ON TABLE DB_CURSO.CURATED.OBJETIVOS_REGION;
SHOW GRANTS ON VIEW DB_CURSO.MARTS.V_VENTAS_REGION;
```


---

## 17. Suspender el warehouse

Vuelve a `SYSADMIN` y suspende el warehouse:

```sql
USE ROLE SYSADMIN;
ALTER WAREHOUSE WH_LAB_M2 SUSPEND;
```

Comprueba su estado:

```sql
SHOW WAREHOUSES LIKE 'WH_LAB_M2';
```

El estado debe aparecer como `SUSPENDED`.

No elimines el rol ni los objetos creados.

---

## 18. Script completo de referencia

Sustituye `<TU_USUARIO>` antes de ejecutar el bloque correspondiente.

```sql
-- =========================================================
-- 1. PREPARACION
-- =========================================================
USE ROLE SYSADMIN;
USE WAREHOUSE WH_LAB_M2;

SELECT CURRENT_USER() AS USUARIO_DEL_LABORATORIO;

CREATE OR REPLACE TABLE DB_CURSO.STAGING.VENTAS_RAW_CONTROL (
    ID_LOTE         NUMBER(10,0) NOT NULL,
    FECHA_RECEPCION TIMESTAMP_NTZ NOT NULL,
    CONTENIDO_RAW   VARCHAR       NOT NULL
);

INSERT INTO DB_CURSO.STAGING.VENTAS_RAW_CONTROL
    (ID_LOTE, FECHA_RECEPCION, CONTENIDO_RAW)
VALUES
    (1001, '2026-07-15 08:30:00', 'cliente=Alba Norte;importe=245.50'),
    (1002, '2026-07-15 08:35:00', 'cliente=Centro Market;importe=475.25');

-- =========================================================
-- 2. CREAR Y ASIGNAR EL ROL
-- =========================================================
USE ROLE USERADMIN;

CREATE ROLE IF NOT EXISTS ROL_ANALISTA_VENTAS
    COMMENT = 'Consulta de ventas curadas y marts sin permisos de escritura';

USE ROLE SECURITYADMIN;

GRANT ROLE ROL_ANALISTA_VENTAS TO ROLE SYSADMIN;
GRANT ROLE ROL_ANALISTA_VENTAS TO USER <TU_USUARIO>;

-- =========================================================
-- 3. PRIVILEGIOS MINIMOS
-- =========================================================
USE ROLE SYSADMIN;

GRANT USAGE ON WAREHOUSE WH_LAB_M2
    TO ROLE ROL_ANALISTA_VENTAS;

GRANT USAGE ON DATABASE DB_CURSO
    TO ROLE ROL_ANALISTA_VENTAS;

GRANT USAGE ON SCHEMA DB_CURSO.CURATED
    TO ROLE ROL_ANALISTA_VENTAS;

GRANT USAGE ON SCHEMA DB_CURSO.MARTS
    TO ROLE ROL_ANALISTA_VENTAS;

GRANT SELECT ON ALL TABLES IN SCHEMA DB_CURSO.CURATED
    TO ROLE ROL_ANALISTA_VENTAS;

GRANT SELECT ON FUTURE TABLES IN SCHEMA DB_CURSO.CURATED
    TO ROLE ROL_ANALISTA_VENTAS;

GRANT SELECT ON ALL VIEWS IN SCHEMA DB_CURSO.MARTS
    TO ROLE ROL_ANALISTA_VENTAS;

GRANT SELECT ON FUTURE VIEWS IN SCHEMA DB_CURSO.MARTS
    TO ROLE ROL_ANALISTA_VENTAS;

-- =========================================================
-- 4. OBJETOS CREADOS DESPUES DE LOS FUTURE GRANTS
-- =========================================================
CREATE OR REPLACE TABLE DB_CURSO.CURATED.OBJETIVOS_REGION (
    REGION           VARCHAR(50)  NOT NULL,
    OBJETIVO_MENSUAL NUMBER(12,2) NOT NULL
);

INSERT INTO DB_CURSO.CURATED.OBJETIVOS_REGION
    (REGION, OBJETIVO_MENSUAL)
VALUES
    ('NORTE',  3000.00),
    ('SUR',    1500.00),
    ('ESTE',   2500.00),
    ('CENTRO', 2200.00);

CREATE OR REPLACE VIEW DB_CURSO.MARTS.V_VENTAS_REGION AS
SELECT
    V.REGION,
    COUNT(*) AS NUMERO_VENTAS,
    SUM(V.IMPORTE) AS IMPORTE_VENDIDO,
    O.OBJETIVO_MENSUAL,
    ROUND(
        SUM(V.IMPORTE) / NULLIF(O.OBJETIVO_MENSUAL, 0) * 100,
        2
    ) AS PORCENTAJE_OBJETIVO
FROM DB_CURSO.CURATED.VENTAS AS V
LEFT JOIN DB_CURSO.CURATED.OBJETIVOS_REGION AS O
    ON V.REGION = O.REGION
GROUP BY V.REGION, O.OBJETIVO_MENSUAL;

-- =========================================================
-- 5. PRUEBAS POSITIVAS CON EL ROL AISLADO
-- =========================================================
USE SECONDARY ROLES NONE;
USE ROLE ROL_ANALISTA_VENTAS;
USE WAREHOUSE WH_LAB_M2;
USE DATABASE DB_CURSO;
USE SCHEMA CURATED;

SELECT
    CURRENT_USER(),
    CURRENT_ROLE(),
    CURRENT_SECONDARY_ROLES(),
    CURRENT_WAREHOUSE(),
    CURRENT_DATABASE(),
    CURRENT_SCHEMA(),
    CURRENT_VERSION();

SELECT * FROM DB_CURSO.CURATED.VENTAS;
SELECT * FROM DB_CURSO.MARTS.V_VENTAS_DIARIAS;
SELECT * FROM DB_CURSO.CURATED.OBJETIVOS_REGION;
SELECT * FROM DB_CURSO.MARTS.V_VENTAS_REGION;

-- =========================================================
-- 6. PRUEBAS NEGATIVAS: EJECUTAR UNA A UNA
-- =========================================================
-- SELECT * FROM DB_CURSO.STAGING.VENTAS_RAW_CONTROL;

-- INSERT INTO DB_CURSO.CURATED.VENTAS
--     (ID_VENTA, FECHA, CLIENTE, REGION, IMPORTE)
-- VALUES
--     (999, CURRENT_DATE(), 'Cliente no autorizado', 'NORTE', 100.00);

-- CREATE TABLE DB_CURSO.MARTS.TABLA_NO_AUTORIZADA (ID NUMBER);

-- ALTER WAREHOUSE WH_LAB_M2 SUSPEND;

-- =========================================================
-- 7. AUDITORIA Y CIERRE
-- =========================================================
USE SECONDARY ROLES ALL;
USE ROLE SECURITYADMIN;

SHOW GRANTS TO ROLE ROL_ANALISTA_VENTAS;
SHOW FUTURE GRANTS TO ROLE ROL_ANALISTA_VENTAS;
SHOW GRANTS OF ROLE ROL_ANALISTA_VENTAS;
SHOW GRANTS ON TABLE DB_CURSO.CURATED.OBJETIVOS_REGION;
SHOW GRANTS ON VIEW DB_CURSO.MARTS.V_VENTAS_REGION;

USE ROLE SYSADMIN;
ALTER WAREHOUSE WH_LAB_M2 SUSPEND;
```

Las pruebas negativas están comentadas deliberadamente para que el script completo no se detenga. Deben ejecutarse por separado durante el laboratorio.

---

## 19. Errores frecuentes y resolución

### Error: el usuario no puede activar ROL_ANALISTA_VENTAS

Causa probable: el rol no se concedió directamente al usuario o se escribió mal el nombre.

Comprobación:

```sql
USE ROLE SECURITYADMIN;
SHOW GRANTS OF ROLE ROL_ANALISTA_VENTAS;
```

Solución:

```sql
GRANT ROLE ROL_ANALISTA_VENTAS TO USER <TU_USUARIO>;
```

### Error: el rol no puede utilizar WH_LAB_M2

Comprueba el grant:

```sql
USE ROLE SYSADMIN;
SHOW GRANTS ON WAREHOUSE WH_LAB_M2;
```

Debe existir `USAGE` para `ROL_ANALISTA_VENTAS`.

### Error: puede seleccionar la tabla, pero no la vista

Las tablas y las vistas son tipos de objeto diferentes. Un grant sobre tablas no cubre las vistas.

Comprueba:

```sql
SHOW GRANTS ON VIEW DB_CURSO.MARTS.V_VENTAS_DIARIAS;
```

### Error: el objeto nuevo no tiene SELECT para el rol

Comprueba que el future grant se configuró antes de crear o reemplazar el objeto:

```sql
SHOW FUTURE GRANTS TO ROLE ROL_ANALISTA_VENTAS;
```

Si faltase, vuelve a concederlo y recrea el objeto de prueba:

```sql
USE ROLE SYSADMIN;

GRANT SELECT ON FUTURE TABLES IN SCHEMA DB_CURSO.CURATED
TO ROLE ROL_ANALISTA_VENTAS;

GRANT SELECT ON FUTURE VIEWS IN SCHEMA DB_CURSO.MARTS
TO ROLE ROL_ANALISTA_VENTAS;
```

### Una prueba negativa funciona cuando debería fallar

Comprueba los roles secundarios:

```sql
SELECT CURRENT_SECONDARY_ROLES();
```

Asegúrate de haber ejecutado:

```sql
USE SECONDARY ROLES NONE;
USE ROLE ROL_ANALISTA_VENTAS;
```

También verifica que no hayas concedido accidentalmente privilegios adicionales al rol:

```sql
SHOW GRANTS TO ROLE ROL_ANALISTA_VENTAS;
```

### Error al suspender el warehouse al finalizar

La denegación es correcta mientras está activo `ROL_ANALISTA_VENTAS`. Vuelve primero a `SYSADMIN`:

```sql
USE ROLE SYSADMIN;
ALTER WAREHOUSE WH_LAB_M2 SUSPEND;
```

---

## 20. Compatibilidad con Snowflake Trial y la versión actual

Este ejercicio se ha diseñado únicamente con capacidades disponibles en una cuenta trial:

- Roles de cuenta personalizados.
- Jerarquías de roles.
- Grants a usuarios y roles.
- Privilegios sobre warehouses, bases de datos, esquemas, tablas y vistas.
- Grants sobre objetos existentes y futuros.
- `USE SECONDARY ROLES`.
- Tablas, vistas y consultas SQL estándar.
- Comandos `SHOW GRANTS` y `SHOW FUTURE GRANTS`.

La documentación oficial actual de Snowflake confirma que:

- `CREATE ROLE` continúa siendo la instrucción para crear roles de cuenta y `USERADMIN` dispone por defecto del privilegio necesario.
- `GRANT ROLE` permite conceder un rol tanto a otro rol como a un usuario.
- `GRANT ... ON ALL TABLES` y `GRANT ... ON FUTURE TABLES` siguen soportados.
- Los privilegios `USAGE` están definidos para warehouses, bases de datos y esquemas.
- `USE SECONDARY ROLES NONE` desactiva los roles secundarios y obliga a autorizar las acciones mediante el rol principal.
- Las cuentas trial permiten crear usuarios y conceder roles; estas capacidades no aparecen entre las limitaciones actuales de las cuentas de prueba.

Snowflake se actualiza como servicio SaaS. Puedes registrar la versión concreta de la cuenta ejecutando:

```sql
SELECT CURRENT_VERSION();
```

### Consumo estimado

El ejercicio utiliza:

- Un warehouse X-Small.
- Un volumen de datos de apenas unas filas.
- Operaciones de metadatos y consultas muy pequeñas.

El consumo es mínimo frente al saldo de la cuenta trial, especialmente porque `WH_LAB_M2` conserva `AUTO_SUSPEND = 60` y se suspende al terminar.

### Funciones no utilizadas

El ejercicio no depende de:

- Conectividad privada.
- Integraciones externas.
- Servicios de red externos.
- Características Business Critical.
- Funciones restringidas en cuentas trial.
- Herramientas instaladas localmente.

---

## 21. Referencias oficiales utilizadas para la validación

- Snowflake Documentation: **CREATE ROLE**.
- Snowflake Documentation: **GRANT ROLE**.
- Snowflake Documentation: **GRANT privileges TO ROLE**.
- Snowflake Documentation: **Overview of Access Control**.
- Snowflake Documentation: **USE SECONDARY ROLES**.
- Snowflake Documentation: **SHOW GRANTS**.
- Snowflake Documentation: **Trial accounts**.

# Módulo 11 · Ejercicio 1
## RBAC y protección de datos con Row Access Policies, masking y tags

> **Edición necesaria:** Enterprise Edition o superior

---

## Contexto

RetailNova necesita sustituir el uso cotidiano de roles administrativos por un modelo de seguridad mantenible.

Los requisitos son:

- Los analistas solo deben leer datos curados.
- Ingeniería debe cargar y transformar datos.
- Auditoría debe leer todas las filas, pero sin ver información sensible.
- Los permisos deben aplicarse automáticamente a nuevas tablas.
- Un analista solo debe consultar las regiones asignadas.
- Las columnas sensibles deben protegerse mediante clasificación y masking.
- El equipo de gobierno debe administrar policies sin recibir acceso general a los datos.

El laboratorio integra en un único flujo:

```text
Account roles
    ↓
Database roles
    ↓
Grants actuales y futuros
    ↓
Managed access schema
    ↓
Row Access Policy
    ↓
Tags y masking policies
```

---

## Objetivos

Al finalizar deberás ser capaz de:

- Diferenciar account roles y database roles.
- Construir una jerarquía de roles personalizados.
- Encapsular privilegios de una base mediante database roles.
- Conceder warehouse a account roles.
- Configurar grants sobre tablas actuales y futuras.
- Explicar el funcionamiento de un managed access schema.
- Aplicar mínimo privilegio.
- Crear una tabla de mapeo rol-región.
- Crear y aplicar una Row Access Policy.
- Utilizar `IS_ROLE_IN_SESSION`.
- Crear tags con valores permitidos.
- Asociar masking policies de distintos tipos a un tag.
- Aplicar clasificación a columnas.
- Demostrar la precedencia de una masking policy directa.
- Comprobar la separación de funciones.
- Auditar roles, grants, policies y tags.

---

## Prerrequisito de edición

Este ejercicio utiliza:

```text
Row Access Policies
Dynamic Data Masking
Tag-based masking
```

Estas capacidades requieren **Enterprise Edition o superior**.

El modelo RBAC, los database roles, los future grants y los managed access schemas sí pueden practicarse en Standard Edition, pero las tareas de policies fallarán.

---

## Arquitectura de roles

### Account roles

```text
SYSADMIN
    ↑
M11_DATA_PLATFORM_ADMIN
    ├── M11_DATA_ENGINEER
    ├── M11_ANALYST
    ├── M11_AUDITOR
    └── M11_GOVERNANCE_ADMIN
```

### Database roles

```text
DB_M11_SECURITY.DR_ANALYTICS_READER
        ↓ heredado por
DB_M11_SECURITY.DR_PIPELINE_ENGINEER
```

Asignaciones:

```text
DR_ANALYTICS_READER
    → M11_ANALYST
    → M11_AUDITOR

DR_PIPELINE_ENGINEER
    → M11_DATA_ENGINEER
```

---

## Objetos

| Tipo | Nombre |
|---|---|
| Base de datos | `DB_M11_SECURITY` |
| Esquema de ingesta | `RAW` |
| Esquema gobernado | `CURATED` |
| Esquema de gobierno | `GOVERNANCE` |
| Warehouse | `WH_M11_SECURITY` |
| Tabla de ingesta | `RAW.CLIENTES_STAGING` |
| Tabla protegida | `CURATED.CLIENTES` |
| Tabla futura | `CURATED.RESUMEN_REGION` |
| Tabla de mapeo | `GOVERNANCE.ROL_REGION_MAP` |
| Row Access Policy | `GOVERNANCE.RAP_CLIENTES_REGION` |
| Tag | `GOVERNANCE.TAG_CLASIFICACION` |
| Masking de texto | `GOVERNANCE.MP_TAG_STRING` |
| Masking numérico | `GOVERNANCE.MP_TAG_NUMBER` |
| Masking directo | `GOVERNANCE.MP_EMAIL_DIRECTA` |

---

## Datos

La tabla contendrá cuatro clientes ficticios:

| ID | Región | Estado |
|---:|---|---|
| 101 | NORTE | ACTIVO |
| 102 | SUR | ACTIVO |
| 103 | ESTE | ACTIVO |
| 104 | OESTE | INACTIVO |

También contendrá:

```text
NOMBRE
EMAIL
TELEFONO
LIMITE_CREDITO
```

---

## Resultado de seguridad esperado

| Rol | Filas | Email | Teléfono | Crédito |
|---|---:|---|---|---|
| `M11_ANALYST` | NORTE y ESTE | Parcial | Oculto | `NULL` |
| `M11_AUDITOR` | Todas | Oculto | Oculto | `NULL` |
| `M11_DATA_ENGINEER` | Todas | Visible | Visible | Visible |
| `M11_DATA_PLATFORM_ADMIN` | Todas | Visible | Visible | Visible |
| `M11_GOVERNANCE_ADMIN` | Sin `SELECT` | Acceso denegado | Acceso denegado | Acceso denegado |

---

## Reglas del laboratorio

- Utiliza Workspaces.
- Ejecuta las pruebas negativas individualmente.
- Antes de probar un rol:
  ```sql
  USE SECONDARY ROLES NONE;
  ```
- No concedas privilegios de datos directamente a usuarios.
- Los roles se asignarán temporalmente al usuario actual.
- No concedas `SELECT` a `M11_GOVERNANCE_ADMIN`.
- No utilices `ACCOUNTADMIN` para consultas ordinarias.
- Mantén el entorno para el ejercicio siguiente.

---

# Parte 1. Crear el modelo RBAC

## Tarea 1. Crear roles y objetos

Crea los cinco account roles y la jerarquía indicada.

Crea:

```text
WH_M11_SECURITY
DB_M11_SECURITY.RAW
DB_M11_SECURITY.CURATED
DB_M11_SECURITY.GOVERNANCE
```

Condiciones:

- Warehouse `XSMALL`.
- Auto-suspend de 60 segundos.
- `CURATED` debe ser un managed access schema.
- `GOVERNANCE` debe quedar owned por `M11_GOVERNANCE_ADMIN`.

Carga las cuatro filas en RAW y CURATED.

---

## Tarea 2. Crear database roles

Crea:

```text
DR_ANALYTICS_READER
DR_PIPELINE_ENGINEER
```

El lector recibirá:

- `USAGE` sobre `CURATED`.
- `SELECT` sobre tablas actuales de `CURATED`.
- `SELECT` sobre tablas futuras de `CURATED`.

El rol de ingeniería heredará el lector y recibirá:

- `USAGE` sobre `RAW`.
- DML sobre tablas actuales y futuras de `RAW`.
- `CREATE TABLE` sobre `RAW` y `CURATED`.

Conecta los database roles con los account roles.

Concede el warehouse a los account roles funcionales.

---

## Tarea 3. Probar mínimo privilegio

### Analista

Debe poder:

- Consultar `CURATED.CLIENTES`.

No debe poder:

- Consultar `RAW.CLIENTES_STAGING`.
- Insertar en `CURATED.CLIENTES`.
- Crear tablas.

### Ingeniería

Debe poder:

- Consultar CURATED.
- Ejecutar DML en RAW.
- Crear una tabla en CURATED.

---

## Tarea 4. Comprobar future grants y managed access

1. Crea `CURATED.RESUMEN_REGION` después de configurar los future grants.
2. Comprueba que el analista puede leerla sin un grant adicional.
3. Como ingeniería, crea `CURATED.PRUEBA_MANAGED`.
4. Intenta conceder `SELECT` sobre esa tabla a `M11_GOVERNANCE_ADMIN`.
5. Comprueba que falla porque el esquema es managed access.
6. Elimina la tabla de prueba.

Explica por qué ser owner de una tabla no permite administrar sus grants en un managed access schema.

---

# Parte 2. Aplicar gobierno de datos

## Tarea 5. Crear el mapa y la Row Access Policy

En `GOVERNANCE`, crea:

```text
ROL_REGION_MAP
```

Configuración:

```text
M11_ANALYST → NORTE
M11_ANALYST → ESTE
```

Crea una Row Access Policy que:

- Permita todas las regiones a ingeniería, auditoría y plataforma.
- Consulte la tabla de mapeo para el resto.
- Utilice `IS_ROLE_IN_SESSION`.

Aplica la policy a:

```text
CURATED.CLIENTES(REGION)
```

---

## Tarea 6. Crear tags y masking policies

Crea:

```text
TAG_CLASIFICACION
```

Valores permitidos:

```text
INTERNAL
PII
RESTRICTED
```

Crea:

- Una masking policy para `VARCHAR`.
- Una masking policy para `NUMBER`.

Lógica:

```text
Ingeniería y plataforma
    → valor original

INTERNAL
    → valor original

PII
    → ***MASKED***

RESTRICTED
    → ***RESTRICTED*** o NULL
```

Asocia ambas policies al tag.

Clasifica:

| Columna | Tag |
|---|---|
| `NOMBRE` | `INTERNAL` |
| `EMAIL` | `PII` |
| `TELEFONO` | `PII` |
| `LIMITE_CREDITO` | `RESTRICTED` |

---

## Tarea 7. Aplicar una policy directa

Crea una masking policy directa para `EMAIL`:

- Analista: email parcialmente oculto.
- Auditor: completamente oculto.
- Ingeniería y plataforma: visible.

Aplícala directamente a `EMAIL`.

Explica por qué esta policy prevalece sobre la policy asociada al tag.

---

## Tarea 8. Validar la matriz

Con roles secundarios desactivados, comprueba:

```text
M11_ANALYST
    2 filas: NORTE y ESTE
    email parcial
    teléfono oculto
    crédito NULL

M11_AUDITOR
    4 filas
    email y teléfono ocultos
    crédito NULL

M11_DATA_ENGINEER
    4 filas
    valores completos

M11_GOVERNANCE_ADMIN
    SELECT denegado
```

---

## Tarea 9. Auditar el modelo

Consulta:

- Roles y jerarquías.
- Grants de los database roles.
- Future grants.
- Row Access Policies.
- Masking policies.
- Tags.
- Asociaciones entre policies, tags y columnas.

Completa:

| Control | Finalidad |
|---|---|
| Account role |  |
| Database role |  |
| Future grant |  |
| Managed access |  |
| Row Access Policy |  |
| Masking policy |  |
| Tag-based masking |  |

---

# Ampliación opcional

## Ownership

Transfiere el ownership de una tabla mediante:

```sql
GRANT OWNERSHIP ... COPY CURRENT GRANTS;
```

Comprueba que los grants existentes se conservan.

## Roles secundarios

Compara:

```sql
USE SECONDARY ROLES NONE;
USE SECONDARY ROLES ALL;
```

Comprueba que:

- Los privilegios de acceso y DML pueden combinarse.
- La creación de objetos depende del rol primario.

## Precedencia de future grants

Documenta qué ocurre si existen future grants para el mismo tipo de objeto:

- En la base de datos.
- En un esquema concreto.

---

## Preguntas de reflexión

1. ¿Por qué no se concede el warehouse a un database role?
2. ¿Qué diferencia existe entre role hierarchy y secondary roles?
3. ¿Qué problema resuelven los future grants?
4. ¿Quién puede conceder privilegios en un managed access schema?
5. ¿Por qué el owner de la tabla no queda exento de una Row Access Policy?
6. ¿Qué ventaja aporta una tabla de mapeo?
7. ¿Por qué `IS_ROLE_IN_SESSION` es preferible a comparar solo `CURRENT_ROLE()`?
8. ¿Qué ventaja ofrece el masking basado en tags?
9. ¿Qué policy prevalece si una columna tiene masking directo y tag-based?
10. ¿Por qué future grants no sustituyen a policies ni clasificación?

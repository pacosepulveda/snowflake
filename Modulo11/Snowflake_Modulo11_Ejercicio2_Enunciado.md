# Módulo 11 · Ejercicio 2

## Seguridad perimetral, autenticación y auditoría

> **Entorno:** reutiliza el Ejercicio 1

---

## Contexto

RetailNova ya controla qué filas y columnas puede consultar cada rol. Todavía debe proteger:

- Desde qué redes se permite acceder.
- Qué métodos de autenticación se aceptan.
- Cómo se exige MFA a las personas.
- Cómo se autentican los procesos automáticos.
- Cómo se investigan consultas, denegaciones, accesos y cambios.

El laboratorio construye controles reales, pero no los aplica a la cuenta ni al usuario actual.

```text
Network rules
    ↓
Network policy no asignada

Authentication policies
    ↓
Policies no asignadas

Actividad etiquetada
    ↓
Query History y Login History
    ↓
Account Usage y Access History
```

---

## Objetivos

Al finalizar deberás ser capaz de:

- Diferenciar network rule y network policy.
- Crear reglas permitidas y bloqueadas.
- Diseñar una activación segura sin bloquear la cuenta.
- Crear authentication policies para personas y servicios.
- Diferenciar password, SAML, key pair, PAT y workload identity.
- Explicar por qué `CLIENT_TYPES` no es una frontera suficiente.
- Delegar auditoría con database roles de `SNOWFLAKE`.
- Generar actividad con Query Tags.
- Consultar Query History y Login History en tiempo próximo.
- Consultar Account Usage conociendo su latencia.
- Analizar objetos y policies mediante `ACCESS_HISTORY`.
- Auditar grants y roles.
- Elaborar un runbook de investigación.
- Eliminar los objetos de demostración.

---

## Prerrequisitos

Deben existir:

```text
DB_M11_SECURITY
DB_M11_SECURITY.RAW.CLIENTES_STAGING
DB_M11_SECURITY.CURATED.CLIENTES
DB_M11_SECURITY.GOVERNANCE
WH_M11_SECURITY
roles M11_%
```

`ACCESS_HISTORY` requiere Enterprise Edition o superior.

---

## Objetos

| Tipo | Nombre |
|---|---|
| Esquema | `DB_M11_SECURITY.SECURITY_OPS` |
| Rol | `M11_SECURITY_OPERATIONS` |
| Network rule permitida | `NR_M11_CORPORATE_IPV4` |
| Network rule bloqueada | `NR_M11_BLOCKED_IPV4` |
| Network policy | `NP_M11_CORPORATE` |
| Authentication policy humana | `AUTH_M11_HUMAN` |
| Authentication policy de servicio | `AUTH_M11_SERVICE` |

---

## Rangos de demostración

Se utilizan rangos reservados para documentación:

```text
192.0.2.0/24
198.51.100.0/24
203.0.113.0/24
```

No representan la red real del alumno.

> Si se aplicara la network policy, la sesión quedaría bloqueada.

---

## Query Tags

| Actividad | Query Tag |
|---|---|
| Lectura del analista | `M11_E02_ANALYST_READ` |
| Denegación del analista | `M11_E02_ANALYST_DENIED` |
| Lectura del auditor | `M11_E02_AUDITOR_READ` |
| DML de ingeniería | `M11_E02_ENGINEER_DML` |
| Denegación de gobierno | `M11_E02_GOVERNANCE_DENIED` |

---

## Reglas de seguridad

- No apliques la network policy.
- No apliques las authentication policies.
- No crees contraseñas ni claves privadas.
- No provoques intentos fallidos de login.
- Ejecuta las pruebas negativas individualmente.
- Utiliza `USE SECONDARY ROLES NONE`.
- Mantén una sesión administrativa independiente en un despliegue real.
- Elimina los objetos de red y autenticación al finalizar.

---

# Parte 1. Red y autenticación

## Tarea 1. Crear el rol y el esquema

Crea:

```text
M11_SECURITY_OPERATIONS
DB_M11_SECURITY.SECURITY_OPS
```

Concede al rol:

- `CREATE NETWORK POLICY` sobre la cuenta.
- `CREATE NETWORK RULE` sobre el esquema.
- `CREATE AUTHENTICATION POLICY` sobre el esquema.
- `APPLY AUTHENTICATION POLICY` sobre la cuenta.
- `USAGE` sobre el warehouse.

No concedas acceso a las tablas de negocio.

---

## Tarea 2. Revisar el estado actual

Consulta:

- Network policies existentes.
- Network policy de la cuenta.
- Network policy del usuario actual.
- Authentication policies existentes.
- Policies efectivas de cuenta y usuario.
- Login reciente del usuario actual.

No cambies ninguna asociación existente.

---

## Tarea 3. Crear network rules y policy

Crea:

```text
NR_M11_CORPORATE_IPV4
    ALLOW 192.0.2.0/24
    ALLOW 198.51.100.0/24

NR_M11_BLOCKED_IPV4
    BLOCK 203.0.113.0/24
```

Crea `NP_M11_CORPORATE` utilizando ambas rules.

Comprueba:

- DDL.
- Owner.
- Reglas permitidas.
- Reglas bloqueadas.

Confirma que no está aplicada.

---

## Tarea 4. Crear authentication policies

### Personas

Permite:

```text
PASSWORD
SAML
```

Clientes:

```text
SNOWFLAKE_UI
SNOWFLAKE_CLI
SNOWSQL
DRIVERS
```

Exige MFA y permite:

```text
PASSKEY
TOTP
OTP
```

### Servicios

Permite:

```text
KEYPAIR
PROGRAMMATIC_ACCESS_TOKEN
WORKLOAD_IDENTITY
```

Clientes:

```text
DRIVERS
SNOWFLAKE_CLI
SNOWSQL
```

No apliques ninguna policy.

---

# Parte 2. Generar evidencias

## Tarea 5. Delegar auditoría

Concede temporalmente a `M11_AUDITOR`:

```text
SNOWFLAKE.OBJECT_VIEWER
SNOWFLAKE.USAGE_VIEWER
SNOWFLAKE.GOVERNANCE_VIEWER
SNOWFLAKE.SECURITY_VIEWER
```

Explica qué tipo de vistas permite consultar cada database role.

---

## Tarea 6. Generar actividad

Ejecuta:

1. Lectura permitida con `M11_ANALYST`.
2. Intento denegado contra RAW.
3. Lectura permitida con `M11_AUDITOR`.
4. UPDATE controlado en RAW con `M11_DATA_ENGINEER`.
5. Intento denegado de `M11_GOVERNANCE_ADMIN`.

Utiliza el Query Tag correspondiente antes de cada acción.

Restaura el dato modificado por ingeniería.

---

# Parte 3. Auditar

## Tarea 7. Auditoría inmediata

Consulta:

```text
QUERY_HISTORY_BY_USER
LOGIN_HISTORY_BY_USER
```

Localiza:

- Query ID.
- Rol.
- Query Tag.
- Estado.
- Código y mensaje de error.
- IP y tipo de cliente del login.
- Factores de autenticación.

---

## Tarea 8. Auditoría histórica

Consulta:

```text
SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
SNOWFLAKE.ACCOUNT_USAGE.LOGIN_HISTORY
SNOWFLAKE.ACCOUNT_USAGE.ACCESS_HISTORY
SNOWFLAKE.ACCOUNT_USAGE.GRANTS_TO_ROLES
```

Ten en cuenta:

```text
QUERY_HISTORY     → hasta 45 minutos
LOGIN_HISTORY     → hasta 2 horas
ACCESS_HISTORY    → hasta 3 horas
```

No declares el ejercicio fallido si las vistas todavía no contienen la actividad recién generada.

---

## Tarea 9. Elaborar un informe

Incluye:

| Campo | Contenido |
|---|---|
| Usuario |  |
| Rol |  |
| Query ID |  |
| Query Tag |  |
| Objeto |  |
| Columnas |  |
| Policy evaluada |  |
| Resultado |  |
| IP y cliente |  |
| Acción recomendada |  |

Explica qué fuente utilizarías para:

- Investigación inmediata.
- Consulta histórica.
- Acceso a columnas.
- Policies evaluadas.
- Grants sensibles.
- Fallos de login.

---

# Ampliación opcional

## Access History con FLATTEN

Extrae:

- Objetos directos.
- Objetos base.
- Columnas.
- Policies evaluadas.
- Objetos modificados.

## Runbook de activación

Diseña:

1. Inventario de IP y private endpoints.
2. Usuario piloto.
3. Sesión administrativa independiente.
4. Usuario break-glass.
5. Rollback.
6. Monitorización de fallos.
7. Aplicación gradual.
8. Pruebas periódicas.

## Alertas

Propón alertas para:

- Aumento de logins fallidos.
- IP nueva.
- Uso de rol privilegiado.
- Grants directos a usuarios.
- DDL sobre policies.
- Consulta masiva de columnas sensibles.

---

# Limpieza

Al finalizar:

1. Confirma que `NP_M11_CORPORATE` no está aplicada.
2. Confirma que las authentication policies no están asignadas.
3. Elimina la network policy.
4. Elimina `SECURITY_OPS`.
5. Revoca los database roles temporales de auditoría.
6. Elimina `M11_SECURITY_OPERATIONS`.
7. Restaura la fila modificada.
8. Suspende el warehouse.

---

## Preguntas de reflexión

1. ¿Por qué una network policy se evalúa antes que la autenticación?
2. ¿Qué diferencia existe entre network rule y network policy?
3. ¿Por qué no debe activarse una allowlist sin una sesión de recuperación?
4. ¿Cuándo utilizarías workload identity en lugar de key pair?
5. ¿Por qué `CLIENT_TYPES` no debe ser el único control?
6. ¿Qué diferencia existe entre Information Schema y Account Usage?
7. ¿Qué aporta Access History frente a Query History?
8. ¿Por qué las consultas denegadas pueden no aparecer en Access History?
9. ¿Qué database role de `SNOWFLAKE` permite consultar Access History?
10. ¿Qué evidencias conservarías durante una investigación?

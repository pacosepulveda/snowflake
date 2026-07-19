# Módulo 4 · Ejercicio 1

## Exposición segura de datos mediante views y secure views

### Contexto

La empresa **Northwind Retail** mantiene en Snowflake una tabla maestra de clientes que contiene información personal y financiera. Esta tabla debe permanecer accesible únicamente para los equipos responsables del dato.

Sin embargo, dos colectivos necesitan consultar una parte de esa información:

- El equipo de **Soporte** necesita identificar al cliente, consultar un correo parcialmente oculto y conocer el estado de su cuenta.
- Un **partner externo** solo debe recibir información agregada y seudonimizada de clientes activos. No debe conocer nombres, correos, teléfonos, NIF ni saldos exactos.

Tu objetivo es construir una pequeña capa de consumo basada en vistas que permita ofrecer estos datos sin conceder acceso directo a la tabla original.

---

## Objetivos de aprendizaje

Al finalizar el ejercicio deberás ser capaz de:

- Crear y consultar una view estándar.
- Crear y consultar una secure view.
- Exponer datos sin conceder acceso a las tablas subyacentes.
- Comprobar qué información de la definición de una vista puede consultar un consumidor.
- Verificar que una vista refleja los cambios realizados sobre la tabla base.
- Explicar cuándo debe utilizarse una secure view y cuándo una view estándar es suficiente.

---

## Requisitos previos

- Cuenta trial de Snowflake con edición Enterprise.
- Acceso a Snowsight.
- Un virtual warehouse `WH_DEV` de tamaño `XSMALL` o equivalente.
- Permisos para utilizar `SYSADMIN`, `USERADMIN` y `SECURITYADMIN`.
- La base de datos `DB_CURSO`. Si no existe, deberás crearla.

---

## Escenario de datos

Deberás crear una tabla denominada:

```text
DB_CURSO.M4_DATA.CLIENTES_SENSIBLES
```

La tabla almacenará, como mínimo, los siguientes campos:

| Campo | Significado |
|---|---|
| `ID_CLIENTE` | Identificador interno del cliente |
| `NOMBRE` | Nombre completo |
| `EMAIL` | Dirección de correo electrónico |
| `TELEFONO` | Número de teléfono |
| `NIF` | Identificador fiscal |
| `REGION` | Región comercial |
| `ESTADO` | Estado de la cuenta: `ACTIVO`, `BLOQUEADO` o `INACTIVO` |
| `SALDO` | Saldo o volumen económico asociado |
| `FECHA_ALTA` | Fecha de alta del cliente |

Carga al menos **seis clientes de prueba**, repartidos entre varias regiones y estados.

---

# Tareas

## Tarea 1 · Preparar roles y esquemas

Crea dos roles personalizados:

- `M4_DATA_OWNER`: representa al equipo propietario de los datos.
- `M4_CONSUMER`: representa a los usuarios que únicamente consumirán las vistas.

Sitúa ambos roles bajo `SYSADMIN` y crea estos esquemas:

```text
DB_CURSO.M4_DATA
DB_CURSO.M4_CONSUMO
```

El primer esquema contendrá la tabla original. El segundo contendrá las vistas expuestas a los consumidores.

> No concedas al rol `M4_CONSUMER` privilegios sobre `DB_CURSO.M4_DATA`.

---

## Tarea 2 · Crear la tabla sensible

Crea `DB_CURSO.M4_DATA.CLIENTES_SENSIBLES` y carga los datos de prueba.

Comprueba:

- El número total de clientes.
- Cuántos clientes hay por estado.
- Que existen datos personales que no deberían llegar al partner.

---

## Tarea 3 · Crear una view para Soporte

Crea una view estándar denominada:

```text
DB_CURSO.M4_CONSUMO.V_CLIENTES_SOPORTE
```

Debe mostrar solamente:

- `ID_CLIENTE`
- `NOMBRE`
- Un correo parcialmente oculto
- Los cuatro últimos dígitos del teléfono
- `ESTADO`
- `REGION`

El correo debe conservar únicamente la primera letra del usuario y el dominio. Por ejemplo:

```text
ana.garcia@example.com -> a***@example.com
```

La vista no debe incluir el NIF ni el saldo.

---

## Tarea 4 · Crear una secure view para el partner

Crea una secure view denominada:

```text
DB_CURSO.M4_CONSUMO.SV_CLIENTES_PARTNER
```

Debe cumplir estas condiciones:

- Mostrar únicamente clientes con `ESTADO = 'ACTIVO'`.
- No mostrar el identificador interno.
- Generar un token mediante una función hash a partir de `ID_CLIENTE`.
- Mostrar la región y la fecha de alta.
- Sustituir el saldo exacto por una categoría:
  - `BAJO`: menos de 1.000.
  - `MEDIO`: entre 1.000 y 4.999,99.
  - `ALTO`: 5.000 o más.
- No mostrar nombre, correo, teléfono ni NIF.

---

## Tarea 5 · Conceder acceso exclusivamente a las vistas

Concede a `M4_CONSUMER`:

- Uso del warehouse `WH_DEV`.
- Uso de `DB_CURSO`.
- Uso del esquema `DB_CURSO.M4_CONSUMO`.
- `SELECT` sobre las dos vistas.

No le concedas acceso al esquema `M4_DATA` ni a la tabla sensible.

Después cambia al rol `M4_CONSUMER`, desactiva los roles secundarios y verifica que:

1. Puede consultar las dos vistas.
2. No puede consultar directamente `CLIENTES_SENSIBLES`.
3. No aparecen NIF, teléfonos completos ni saldos exactos en la secure view.

---

## Tarea 6 · Comparar visibilidad de las definiciones

Como `M4_CONSUMER`, utiliza al menos dos de estos mecanismos:

- `SHOW VIEWS`
- `GET_DDL`
- `DB_CURSO.INFORMATION_SCHEMA.VIEWS`

Compara la view estándar y la secure view.

Documenta:

- Cuál aparece marcada como segura.
- Si puedes consultar la sentencia `SELECT` utilizada para crear cada una.
- Qué diferencia observas entre ambas.

> La forma exacta de mostrar una definición protegida puede variar ligeramente entre Snowsight, `SHOW`, `GET_DDL` e Information Schema. Lo importante es comprobar que el consumidor no obtiene la lógica interna completa de la secure view.

---

## Tarea 7 · Comprobar que las vistas son dinámicas

Vuelve a `SYSADMIN` y realiza estos cambios sobre la tabla base:

1. Cambia un cliente activo a `INACTIVO`.
2. Inserta un nuevo cliente activo.
3. Modifica el saldo de otro cliente para que cambie de categoría.

Regresa a `M4_CONSUMER` y vuelve a consultar ambas vistas.

Comprueba que:

- El cliente convertido en inactivo desaparece de la secure view.
- El nuevo cliente aparece sin necesidad de recrear la vista.
- La categoría de saldo cambia automáticamente.

---

# Entregables

Entrega un documento o capturas que incluyan:

1. SQL de creación de roles, esquemas, tabla y vistas.
2. Resultado de las consultas sobre ambas vistas con `M4_CONSUMER`.
3. Error obtenido al intentar acceder a la tabla base.
4. Evidencia de que la definición de la secure view está protegida.
5. Resultado antes y después de modificar la tabla base.
6. Una respuesta razonada a estas preguntas:

### Preguntas de reflexión

1. ¿Una secure view cifra los datos almacenados en la tabla base?
2. ¿Una secure view elimina automáticamente las columnas sensibles?
3. ¿Por qué no sería recomendable convertir todas las vistas de una plataforma en secure views?
4. ¿Qué privilegios mínimos necesita un consumidor para consultar una vista situada en otra base de datos o esquema?
5. ¿Qué riesgo existe si una secure view expone identificadores secuenciales aunque oculte los nombres?

---

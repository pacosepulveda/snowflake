# Módulo 2 - Ejercicio 2

## Control de acceso con RBAC y mínimo privilegio

**Duración estimada:** 50-70 minutos  
**Modalidad:** individual  
**Herramienta:** Snowsight, mediante una SQL Worksheet  
**Cuenta:** Snowflake Trial, edición Enterprise

---

## Contexto

El entorno inicial de **Northwind Retail** ya está preparado. La base de datos `DB_CURSO` contiene datos de ventas organizados en los esquemas `STAGING`, `CURATED` y `MARTS`, y el warehouse `WH_LAB_M2` se utiliza para las consultas del laboratorio.

El equipo de Business Intelligence va a incorporar analistas que necesitan consultar:

- Los datos limpios de ventas de `CURATED`.
- Las vistas analíticas de `MARTS`.
- Los objetos que se creen en el futuro en esos dos ámbitos.

Sin embargo, un analista **no debe**:

- Acceder a los datos crudos de `STAGING`.
- Insertar, modificar o eliminar datos.
- Crear tablas o vistas.
- Suspender, redimensionar o administrar el warehouse.
- Trabajar con privilegios administrativos.

Tu tarea es diseñar, aplicar y validar un rol que cumpla el principio de **mínimo privilegio**.

---

## Objetivos de aprendizaje

Al completar el ejercicio deberás ser capaz de:

1. Diferenciar las responsabilidades de `USERADMIN`, `SECURITYADMIN` y `SYSADMIN`.
2. Crear un rol personalizado y situarlo dentro de una jerarquía de roles.
3. Conceder únicamente los privilegios necesarios sobre warehouse, base de datos, esquemas, tablas y vistas.
4. Configurar privilegios sobre objetos existentes y futuros.
5. Asignar un rol a un usuario y cambiar el rol activo de la sesión.
6. Desactivar temporalmente los roles secundarios para comprobar el aislamiento real del rol.
7. Validar tanto las operaciones permitidas como las operaciones que deben ser rechazadas.
8. Inspeccionar los grants efectivos y los future grants.

---

## Prerrequisitos

Debes haber completado el ejercicio anterior y disponer, como mínimo, de estos objetos:

```text
WH_LAB_M2

DB_CURSO
├── STAGING
├── CURATED
│   └── VENTAS
└── MARTS
    └── V_VENTAS_DIARIAS
```

No elimines ni sustituyas los objetos del ejercicio anterior.

---

## Requisitos

### 1. Preparar la worksheet

Crea una nueva SQL Worksheet en Snowsight y ponle un nombre identificable, por ejemplo:

`M2_E2_RBAC_MINIMO_PRIVILEGIO`

Conserva en ella todo el SQL utilizado, incluidos los intentos que produzcan errores esperados.

### 2. Identificar el usuario de la cuenta

Obtén el nombre exacto del usuario con el que has iniciado sesión y consérvalo. Lo necesitarás para asignarle el nuevo rol.

### 3. Preparar un objeto restringido en STAGING

Trabajando con `SYSADMIN`, crea en `DB_CURSO.STAGING` una tabla llamada:

`VENTAS_RAW_CONTROL`

La tabla debe contener, como mínimo:

- Un identificador de lote.
- Una fecha de recepción.
- Un texto que represente el contenido crudo recibido.

Inserta dos filas de prueba. Esta tabla servirá para confirmar posteriormente que el analista no puede acceder a `STAGING`.

### 4. Crear el rol del analista

Crea un rol de cuenta llamado:

`ROL_ANALISTA_VENTAS`

La creación del rol debe realizarse con el rol de sistema adecuado para administrar usuarios y roles.

Añade un comentario que describa su finalidad.

### 5. Incorporar el rol a la jerarquía

Sitúa `ROL_ANALISTA_VENTAS` por debajo de `SYSADMIN`, de manera que `SYSADMIN` herede sus privilegios y pueda administrarlo dentro de la jerarquía recomendada.

Asigna también `ROL_ANALISTA_VENTAS` al usuario con el que estás realizando el laboratorio.

Utiliza para estas operaciones el rol de sistema apropiado para gestionar grants.

### 6. Conceder privilegios mínimos

Concede a `ROL_ANALISTA_VENTAS` únicamente los privilegios necesarios para:

- Utilizar `WH_LAB_M2` para ejecutar consultas.
- Acceder a `DB_CURSO`.
- Acceder a los esquemas `CURATED` y `MARTS`.
- Consultar todas las tablas que ya existan en `CURATED`.
- Consultar todas las tablas que se creen en el futuro en `CURATED`.
- Consultar todas las vistas que ya existan en `MARTS`.
- Consultar todas las vistas que se creen en el futuro en `MARTS`.

No concedas acceso al esquema `STAGING`.

No concedas privilegios de escritura, creación, modificación, ownership, operación o administración.

### 7. Crear objetos después de los future grants

Una vez configurados los privilegios futuros, trabaja de nuevo con `SYSADMIN` y crea:

#### Tabla futura

En `DB_CURSO.CURATED`, crea una tabla llamada:

`OBJETIVOS_REGION`

Debe contener:

- Región.
- Objetivo mensual de ventas.

Inserta objetivos para las regiones `NORTE`, `SUR`, `ESTE` y `CENTRO`.

#### Vista futura

En `DB_CURSO.MARTS`, crea una vista llamada:

`V_VENTAS_REGION`

La vista debe mostrar, al menos:

- Región.
- Número de ventas.
- Importe total vendido.
- Objetivo mensual.
- Porcentaje del objetivo alcanzado.

Estos objetos se crean **después** de los future grants para comprobar que el rol recibe acceso automáticamente.

### 8. Activar el rol del analista de forma aislada

Antes de validar el rol:

1. Desactiva los roles secundarios de la sesión.
2. Activa `ROL_ANALISTA_VENTAS` como rol principal.
3. Selecciona `WH_LAB_M2`.
4. Selecciona `DB_CURSO` y el esquema `CURATED`.
5. Consulta el contexto de sesión, incluyendo los roles secundarios activos.

La prueba debe realizarse sin que otro rol del usuario aporte privilegios adicionales.

### 9. Validar las operaciones permitidas

Con `ROL_ANALISTA_VENTAS`, demuestra que puedes:

1. Consultar `DB_CURSO.CURATED.VENTAS`.
2. Consultar `DB_CURSO.MARTS.V_VENTAS_DIARIAS`.
3. Consultar `DB_CURSO.CURATED.OBJETIVOS_REGION`.
4. Consultar `DB_CURSO.MARTS.V_VENTAS_REGION`.
5. Ejecutar una consulta agregada de ventas por región.

Las consultas sobre `OBJETIVOS_REGION` y `V_VENTAS_REGION` deben funcionar sin conceder grants adicionales después de crearlas.

### 10. Validar las operaciones denegadas

Ejecuta por separado las siguientes pruebas. Cada una debe producir un error de autorización:

1. Consultar `DB_CURSO.STAGING.VENTAS_RAW_CONTROL`.
2. Insertar una nueva fila en `DB_CURSO.CURATED.VENTAS`.
3. Crear una tabla en `DB_CURSO.MARTS`.
4. Suspender `WH_LAB_M2` manualmente.

No corrijas estas denegaciones: son el resultado esperado del diseño de seguridad.

> Ejecuta cada prueba negativa individualmente para que un error no impida continuar con las demás.

### 11. Auditar los privilegios

Vuelve a un rol administrativo y utiliza comandos de inspección para comprobar:

- Todos los privilegios concedidos a `ROL_ANALISTA_VENTAS`.
- Los future grants concedidos al rol.
- Los usuarios y roles a los que se ha asignado `ROL_ANALISTA_VENTAS`.
- Los grants existentes sobre `OBJETIVOS_REGION`.
- Los grants existentes sobre `V_VENTAS_REGION`.

### 12. Finalizar el laboratorio

Al terminar:

- Restaura el uso normal de roles secundarios.
- Vuelve a `SYSADMIN`.
- Suspende `WH_LAB_M2` para evitar consumo innecesario.

No elimines el rol ni los objetos creados, porque podrán reutilizarse en ejercicios posteriores.

---

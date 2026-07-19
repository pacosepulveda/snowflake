# Módulo 2 - Ejercicio 1

## Preparación y validación de un entorno de trabajo en Snowflake

**Herramienta:** Snowsight, mediante un SQL File
**Cuenta:** Snowflake Trial, edición Enterprise

---

## Contexto

Te incorporas al equipo de datos de **Northwind Retail**, una empresa que está realizando una prueba de concepto con Snowflake.

Antes de comenzar a cargar grandes volúmenes de información, el equipo necesita preparar un entorno básico que permita:

- Ejecutar consultas con un consumo controlado.
- Organizar los objetos siguiendo una arquitectura por capas.
- Almacenar un pequeño conjunto de ventas de prueba.
- Comprobar que el contexto de sesión es correcto.
- Verificar que la cuenta está preparada para los siguientes módulos del curso.

Tu tarea consiste en construir y validar este entorno desde una worksheet de Snowsight.

---

## Objetivos de aprendizaje

Al completar el ejercicio deberás ser capaz de:

1. Trabajar con un SQL File de Snowsight.
2. Seleccionar explícitamente el rol, el warehouse, la base de datos y el esquema de una sesión.
3. Crear y configurar un virtual warehouse con medidas básicas de control de coste.
4. Crear una base de datos, esquemas, una tabla y una vista.
5. Insertar y consultar datos mediante SQL.
6. Verificar los objetos creados y suspender el warehouse al terminar.

---

## Requisitos

### 1. Preparar el SQL File

Crea un nuevo SQL File en el workspace por defecto en Snowsight y ponle un nombre identificable, por ejemplo:

`M2_E1_PREPARACION_ENTORNO`

Trabaja con el rol `SYSADMIN`. No utilices `ACCOUNTADMIN` para las operaciones normales del ejercicio.

### 2. Crear un warehouse de laboratorio

Crea un virtual warehouse llamado:

`WH_LAB_M2`

Debe cumplir estas condiciones:

- Tamaño X-Small.
- Suspensión automática tras 60 segundos de inactividad.
- Reanudación automática al recibir una consulta.
- Creación inicial en estado suspendido.

Después, selecciónalo como warehouse activo de la sesión.

### 3. Crear la estructura de datos

Crea una base de datos llamada:

`DB_CURSO`

Dentro de ella, crea los siguientes esquemas:

- `STAGING`
- `CURATED`
- `MARTS`

La finalidad prevista de cada esquema es:

- `STAGING`: datos recibidos desde los sistemas de origen.
- `CURATED`: datos limpios y preparados para su uso.
- `MARTS`: vistas y datos orientados al consumo analítico.

### 4. Fijar y comprobar el contexto de sesión

Configura la sesión para trabajar con:

- Rol: `SYSADMIN`
- Warehouse: `WH_LAB_M2`
- Base de datos: `DB_CURSO`
- Esquema: `CURATED`

Ejecuta una consulta que muestre, al menos:

- Usuario actual.
- Rol actual.
- Warehouse actual.
- Base de datos actual.
- Esquema actual.
- Versión actual de Snowflake.

### 5. Crear una tabla de ventas

En el esquema `CURATED`, crea la tabla `VENTAS` con las columnas siguientes:

| Columna | Tipo lógico esperado | Requisito |
|---|---|---|
| `ID_VENTA` | Número entero | No puede ser nulo |
| `FECHA` | Fecha | No puede ser nula |
| `CLIENTE` | Texto | No puede ser nulo |
| `REGION` | Texto | No puede ser nulo |
| `IMPORTE` | Número decimal con dos decimales | No puede ser nulo |

### 6. Insertar datos de prueba

Inserta al menos **ocho ventas** que cumplan estas condiciones:

- Deben existir ventas de, como mínimo, tres fechas diferentes.
- Deben aparecer, como mínimo, tres regiones diferentes.
- Deben aparecer, como mínimo, cinco clientes diferentes.
- Al menos una venta debe tener un importe superior a 1.000.

### 7. Consultar y validar los datos

Realiza consultas que permitan obtener:

1. El número total de filas almacenadas.
2. El importe total de todas las ventas.
3. El importe total vendido por región.
4. Las ventas con importe superior a 500, ordenadas de mayor a menor importe.

### 8. Crear una vista analítica

En el esquema `MARTS`, crea una vista llamada:

`V_VENTAS_DIARIAS`

La vista debe devolver una fila por fecha con:

- Fecha.
- Número de ventas.
- Importe total vendido.
- Importe medio de venta.

Consulta la vista y ordena el resultado cronológicamente.

### 9. Verificar los objetos creados

Utiliza comandos de inspección de Snowflake para comprobar:

- La configuración de `WH_LAB_M2`.
- Los esquemas existentes en `DB_CURSO`.
- La tabla creada en `CURATED`.
- La vista creada en `MARTS`.
- La definición y las columnas de la tabla `VENTAS`.

### 10. Finalizar sin consumo innecesario

Suspende explícitamente el warehouse `WH_LAB_M2` al terminar.

No elimines la base de datos ni los esquemas: se reutilizarán en ejercicios posteriores.



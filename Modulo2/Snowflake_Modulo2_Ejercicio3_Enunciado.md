# Módulo 2 - Ejercicio 3

## Diagnóstico operativo y trazabilidad de consultas en Snowflake

**Modalidad:** individual  
**Herramienta:** Snowsight, mediante un SQL File y Query History  
**Cuenta:** Snowflake Trial, edición Enterprise

---

## Contexto

El equipo de datos de **Northwind Retail** ya dispone de un entorno básico en Snowflake y de un modelo de acceso de solo lectura para los analistas.

Durante las primeras pruebas, algunos usuarios informan de problemas como estos:

- Una consulta que funcionaba deja de ejecutarse porque el warehouse está suspendido.
- Una tabla parece no existir, aunque otro compañero confirma que sí está creada.
- No queda claro qué rol, warehouse, base de datos y esquema estaban activos cuando se produjo un error.
- Resulta difícil localizar en el historial todas las consultas relacionadas con una prueba concreta.
- El equipo ejecuta comandos `SHOW`, pero no sabe cómo filtrar programáticamente sus resultados.

Tu tarea consiste en reproducir varios incidentes de forma controlada, diagnosticarlos y corregirlos. Después deberás utilizar las capacidades de trazabilidad de Snowflake para reconstruir lo ocurrido.

> En este ejercicio algunos comandos deben fallar. Los errores forman parte del laboratorio y deben conservarse como evidencia.

---

## Objetivos de aprendizaje

Al completar el ejercicio deberás ser capaz de:

1. Identificar el contexto efectivo de una sesión de Snowflake.
2. Utilizar un `QUERY_TAG` para agrupar las consultas de una actividad.
3. Comprobar y modificar el estado y las propiedades de un virtual warehouse.
4. Diagnosticar un fallo causado por un warehouse suspendido con `AUTO_RESUME` desactivado.
5. Diagnosticar un fallo causado por un esquema incorrecto.
6. Diferenciar el uso de nombres cortos y nombres totalmente cualificados.
7. Obtener el identificador de una consulta con `LAST_QUERY_ID()`.
8. Reutilizar resultados anteriores con `RESULT_SCAN()`.
9. Consultar el historial de la sesión mediante `INFORMATION_SCHEMA`.
10. Localizar consultas correctas y fallidas desde Query History en Snowsight.

---

## Prerrequisitos

Debes haber completado los ejercicios anteriores y disponer, como mínimo, de estos objetos:

```text
WH_LAB_M2

DB_CURSO
├── STAGING
│   └── VENTAS_RAW_CONTROL
├── CURATED
│   ├── VENTAS
│   └── OBJETIVOS_REGION
└── MARTS
    ├── V_VENTAS_DIARIAS
    └── V_VENTAS_REGION
```

El ejercicio se realizará principalmente con `SYSADMIN`, porque será necesario cambiar propiedades y estado del warehouse.

---

## Requisitos

### 1. Preparar el SQL File y etiquetar la sesión

Crea un nuevo SQL File y asígnale un nombre identificable, por ejemplo:

`M2_E3_DIAGNOSTICO_TRAZABILIDAD`

Selecciona el rol `SYSADMIN` y configura en la sesión el siguiente query tag:

`M2_E3_DIAGNOSTICO`

Comprueba que el tag está activo antes de continuar.

### 2. Registrar el contexto inicial

Ejecuta una única consulta que devuelva, al menos:

- Usuario actual.
- Rol actual.
- Roles secundarios activos.
- Warehouse actual.
- Base de datos actual.
- Esquema actual.
- Identificador de sesión.
- Versión actual de Snowflake.

Después fija explícitamente este contexto:

- Rol: `SYSADMIN`
- Warehouse: `WH_LAB_M2`
- Base de datos: `DB_CURSO`
- Esquema: `CURATED`

Vuelve a consultar el contexto y confirma que coincide con lo solicitado.

### 3. Inspeccionar programáticamente el warehouse

Ejecuta un comando `SHOW` para obtener la configuración de `WH_LAB_M2`.

Sin volver a consultar directamente el warehouse, procesa el resultado del `SHOW` con `RESULT_SCAN()` y devuelve únicamente estas propiedades:

- Nombre.
- Estado.
- Tamaño.
- Suspensión automática.
- Reanudación automática.
- Rol propietario.

Conserva el identificador de la consulta `SHOW`.

### 4. Reproducir un incidente de warehouse suspendido

Trabajando con `SYSADMIN`:

1. Desactiva temporalmente la reutilización de resultados almacenados en la sesión.
2. Desactiva temporalmente `AUTO_RESUME` en `WH_LAB_M2`.
3. Suspende explícitamente el warehouse.
4. Selecciona `WH_LAB_M2` como warehouse de la sesión.
5. Intenta leer varias columnas de `DB_CURSO.CURATED.VENTAS` y ordenar las filas por importe descendente.

La consulta debe fallar porque requiere cómputo, el warehouse está suspendido y no puede reanudarse automáticamente. Desactivar la reutilización de resultados evita que una ejecución anterior sea atendida desde el resultado persistido sin arrancar el warehouse.

Registra el mensaje de error, pero no cambies de warehouse.

### 5. Diagnosticar y resolver el incidente del warehouse

Comprueba el estado y la propiedad `AUTO_RESUME` de `WH_LAB_M2`.

Después:

1. Reanuda manualmente el warehouse.
2. Vuelve a activar `AUTO_RESUME`.
3. Confirma que `AUTO_SUSPEND` sigue establecido en 60 segundos.
4. Repite la consulta de detalle ordenada sobre ventas.

La segunda ejecución debe completarse correctamente.

### 6. Reproducir un incidente de contexto de esquema

Cambia el esquema activo a `DB_CURSO.STAGING` y ejecuta esta consulta utilizando un nombre corto:

```sql
SELECT * FROM VENTAS;
```

La consulta debe fallar porque Snowflake intentará resolver `VENTAS` dentro del esquema activo.

Sin cambiar todavía el contexto, consulta la misma tabla utilizando su nombre totalmente cualificado. Esta segunda consulta debe funcionar.

### 7. Corregir el contexto de esquema

Consulta el contexto actual para demostrar que el esquema activo es `STAGING`.

Cambia después al esquema `DB_CURSO.CURATED` y repite:

```sql
SELECT * FROM VENTAS;
```

Comprueba que ahora el nombre corto se resuelve correctamente.

Explica brevemente en el SQL File por qué la misma instrucción falla o funciona dependiendo del esquema activo.

### 8. Identificar y reutilizar el resultado de una consulta

Ejecuta una consulta que calcule por región:

- Número de ventas.
- Importe total vendido.
- Importe medio.

Ordena el resultado por importe total descendente.

A continuación:

1. Obtén el identificador de esa consulta con `LAST_QUERY_ID()`.
2. Conserva el identificador.
3. Utiliza `RESULT_SCAN()` para reutilizar el resultado sin volver a escribir la agregación.
4. Filtra el resultado reutilizado para mostrar únicamente las regiones cuyo importe total sea superior a 1.000.

### 9. Consultar el historial de la sesión mediante SQL

Utiliza la función de historial de consultas de `INFORMATION_SCHEMA` para recuperar las consultas recientes de la sesión actual.

Muestra, al menos, estas columnas:

- Hora de inicio.
- Query ID.
- Query tag.
- Tipo de consulta.
- Warehouse.
- Base de datos y esquema.
- Estado de ejecución.
- Código y mensaje de error.
- Tiempo total transcurrido.
- Texto SQL.

Filtra el resultado para mostrar únicamente las consultas etiquetadas con:

`M2_E3_DIAGNOSTICO`

Identifica en el resultado:

- La consulta que falló por el warehouse suspendido.
- La consulta que falló por utilizar el esquema incorrecto.
- Las ejecuciones correctas posteriores a cada corrección.

### 10. Revisar Query History en Snowsight

Abre la página de Query History de Snowsight y filtra por:

- Tu usuario.
- El warehouse `WH_LAB_M2` cuando resulte aplicable.
- El query tag `M2_E3_DIAGNOSTICO`.
- Estado correcto y estado fallido.

Abre el detalle de, al menos, una consulta correcta y una fallida. Comprueba:

- Query ID.
- Estado.
- Query tag.
- Usuario.
- Warehouse.
- Duración.
- Texto SQL.
- Mensaje de error, cuando exista.

### 11. Dejar el entorno en un estado seguro

Al terminar:

1. Restaura la configuración de `WH_LAB_M2` a:
   - Tamaño X-Small.
   - `AUTO_SUSPEND = 60`.
   - `AUTO_RESUME = TRUE`.
2. Suspende el warehouse.
3. Restaura el uso normal de resultados almacenados en la sesión.
4. Elimina el query tag de la sesión para recuperar el valor predeterminado.

No elimines la base de datos, los esquemas, las tablas, las vistas ni los roles creados en ejercicios anteriores.

---

## Criterios de finalización

El ejercicio estará completado cuando puedas demostrar que:

- Las consultas del laboratorio aparecen asociadas al query tag solicitado.
- Has procesado el resultado de un comando `SHOW` mediante `RESULT_SCAN()`.
- La consulta de detalle sobre `VENTAS` falla con el warehouse suspendido, `AUTO_RESUME` desactivado y la reutilización de resultados deshabilitada.
- La misma consulta funciona después de reanudar y corregir el warehouse.
- El nombre corto `VENTAS` falla desde `STAGING` y funciona desde `CURATED`.
- El nombre totalmente cualificado funciona independientemente del esquema activo.
- Has recuperado y reutilizado el resultado de una consulta anterior.
- El historial SQL contiene tanto las ejecuciones correctas como las fallidas.
- Has localizado las mismas consultas desde Query History en Snowsight.
- El warehouse queda suspendido y con su configuración original.

---

## Evidencias que debes conservar

Guarda en el SQL File o mediante capturas:

1. El contexto inicial y el contexto corregido.
2. El resultado filtrado del comando `SHOW WAREHOUSES`.
3. El error producido por el warehouse suspendido.
4. La consulta correcta después de reanudarlo.
5. El error producido por el esquema incorrecto.
6. La consulta correcta utilizando el nombre totalmente cualificado.
7. El Query ID de la agregación por región.
8. El resultado filtrado obtenido mediante `RESULT_SCAN()`.
9. El historial SQL filtrado por query tag.
10. El detalle en Snowsight de una consulta correcta y otra fallida.

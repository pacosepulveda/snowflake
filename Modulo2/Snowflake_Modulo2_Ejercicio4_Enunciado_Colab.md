# Módulo 2 - Ejercicio 4

## Conexión programática y consumo seguro de datos con Python desde Google Colab

**Modalidad:** individual  
**Herramientas:** Snowflake Workspaces, SQL Files y Google Colab  
**Cliente:** Snowflake Connector for Python  
**Cuenta:** Snowflake Trial, edición Enterprise  
**Autenticación utilizada en el laboratorio:** usuario y contraseña, sin MFA

---

## Contexto

El entorno de **Northwind Retail** ya dispone de datos de ventas, un warehouse de laboratorio y un rol de solo lectura para el equipo de analítica.

Hasta ahora, las operaciones se han realizado desde **SQL Files** dentro de Snowflake Workspaces. El siguiente paso consiste en comprobar que una aplicación Python situada fuera de Snowflake puede conectarse a la plataforma y consumir datos de forma segura.

Los equipos de los alumnos no permiten instalar Python, crear entornos virtuales ni añadir paquetes. Por este motivo, el cliente se desarrollará y ejecutará en **Google Colab**, un entorno Jupyter alojado al que se accede desde el navegador.

La cuenta utilizada en este laboratorio no tiene MFA habilitado ni una política que lo exija. Por tanto, la conexión se realizará mediante:

```text
Identificador de cuenta + usuario + contraseña
```

No se solicitará un código TOTP ni se configurarán parámetros de MFA en el conector.

El equipo quiere construir un pequeño cliente Python que:

- Instale el conector oficial dentro del runtime temporal de Colab.
- Se conecte a Snowflake sin guardar la contraseña en el notebook.
- Utilice el rol de mínimo privilegio creado para los analistas.
- Establezca explícitamente el warehouse, la base de datos y el esquema.
- Ejecute una consulta parametrizada.
- Recupere los resultados como estructuras de Python.
- Exporte un informe a un fichero CSV.
- Permita descargar el CSV al ordenador del alumno.
- Registre un `QUERY_TAG` para facilitar la trazabilidad.
- Capture de forma controlada un error de autorización.
- Cierre correctamente la sesión.

Tu tarea consiste en desarrollar, ejecutar y validar ese cliente desde Google Colab.

> No escribas la contraseña directamente en ninguna celda del notebook. El programa debe solicitarla mediante una entrada oculta.

---

## Objetivos de aprendizaje

Al completar el ejercicio deberás ser capaz de:

1. Obtener desde un SQL File los parámetros necesarios para conectar una aplicación a Snowflake.
2. Preparar un runtime Python alojado sin instalar software en el ordenador.
3. Instalar y comprobar Snowflake Connector for Python desde Google Colab.
4. Crear una conexión indicando cuenta, usuario, rol, warehouse, base de datos y esquema.
5. Autenticarse mediante usuario y contraseña cuando la cuenta no exige MFA.
6. Configurar un `QUERY_TAG` desde el cliente.
7. Comprobar el contexto efectivo de la sesión abierta por la aplicación.
8. Desactivar los roles secundarios para validar el mínimo privilegio.
9. Ejecutar SQL utilizando parámetros enlazados en lugar de concatenar entradas.
10. Recuperar resultados mediante un cursor de diccionarios.
11. Guardar los resultados en un fichero CSV y descargarlo desde Colab.
12. Obtener el Query ID de una consulta y localizarla en Query History.
13. Capturar un error de Snowflake mediante `ProgrammingError`.
14. Cerrar cursores y conexiones de forma segura.
15. Diferenciar el almacenamiento persistente del notebook del almacenamiento temporal del runtime.

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

ROL_ANALISTA_VENTAS
```

El usuario con el que realizas el laboratorio debe tener asignado `ROL_ANALISTA_VENTAS`.

También necesitas:

- Un navegador con acceso a Snowsight y Google Colab.
- Una cuenta de Google para guardar una copia individual del notebook.
- Acceso a Internet desde el runtime de Colab.
- Permiso para descargar el fichero CSV generado.
- La contraseña del usuario de la cuenta trial.

No es necesario disponer de:

- Python instalado localmente.
- Permisos de administrador en el ordenador.
- Visual Studio Code, PyCharm u otro IDE.
- Un entorno virtual local.
- SnowSQL o Snowflake CLI.
- Una aplicación de autenticación TOTP.

---

## Consideraciones de seguridad

Google Colab es un entorno de ejecución externo a Snowflake. Para este laboratorio:

- Utiliza únicamente las credenciales de la cuenta trial del curso.
- No utilices credenciales de producción ni de una cuenta corporativa salvo autorización expresa.
- Introduce la contraseña mediante `getpass()`.
- No escribas secretos en celdas de código, celdas de texto, comentarios ni nombres de fichero.
- No guardes la contraseña en Google Drive.
- No compartas un notebook mientras conserve resultados que no deban divulgarse.
- Cierra la conexión de Snowflake cuando termine la ejecución.
- Desconecta y elimina el runtime de Colab al finalizar.

El notebook se guarda de forma persistente en Google Drive. Sin embargo, los paquetes instalados y los ficheros creados en el sistema de archivos del runtime son temporales. Debes descargar el CSV antes de que el runtime se reinicie o se elimine.

---

## Requisitos

### 1. Preparar un SQL File de apoyo

En Snowsight:

1. Accede a **Projects → Workspaces**.
2. Abre tu workspace.
3. Selecciona **Add new → SQL File**.
4. Asigna al archivo un nombre identificable, por ejemplo:

```text
M2_E4_CONEXION_COLAB.sql
```

Utiliza este SQL File para obtener y conservar:

- El identificador de cuenta recomendado para clientes y drivers.
- El nombre exacto del usuario actual.
- La región de la cuenta.
- La versión actual de Snowflake.
- La comprobación de que `ROL_ANALISTA_VENTAS` está asignado al usuario.
- La comprobación de que el rol puede utilizar `WH_LAB_M2`.
- La comprobación de que el rol puede consultar `DB_CURSO.CURATED.VENTAS`.

No incluyas ninguna contraseña en el SQL File.

### 2. Crear una copia individual del notebook

Accede a Google Colab y crea un notebook nuevo, o abre el notebook base proporcionado por el instructor.

Guarda una copia individual con un nombre identificable, por ejemplo:

```text
M2_E4_CLIENTE_SNOWFLAKE_APELLIDO.ipynb
```

No trabajes directamente sobre una copia compartida por toda la clase.

### 3. Preparar el runtime de Colab

En la primera celda de código:

1. Instala la versión más reciente disponible de `snowflake-connector-python`.
2. Comprueba la versión de Python.
3. Comprueba la versión instalada del conector.
4. Verifica que `snowflake.connector` se importa sin errores.

La instalación se realizará dentro del runtime temporal. No debe instalar nada en el ordenador del alumno.

### 4. Organizar el cliente en el notebook

El notebook debe contener, como mínimo, bloques claramente separados para:

- Instalación y comprobación del conector.
- Importaciones y constantes.
- Funciones auxiliares.
- Solicitud de parámetros.
- Apertura de la conexión.
- Validación del contexto.
- Consulta parametrizada.
- Presentación y exportación de resultados.
- Prueba negativa de seguridad.
- Cierre de la conexión.
- Descarga del CSV.

El código puede estar distribuido en varias celdas, pero debe poder ejecutarse de arriba abajo de forma reproducible.

### 5. Solicitar los datos de ejecución

El cliente debe solicitar de forma interactiva:

- Identificador de cuenta.
- Usuario.
- Contraseña, sin mostrarla en pantalla.
- Importe mínimo que se utilizará como filtro.

No debes escribir credenciales fijas dentro del notebook.

No solicites un código TOTP, ya que MFA no está habilitado ni es obligatorio en esta cuenta.

### 6. Abrir la conexión

La conexión debe establecer explícitamente este contexto:

- Rol: `ROL_ANALISTA_VENTAS`
- Warehouse: `WH_LAB_M2`
- Base de datos: `DB_CURSO`
- Esquema: `CURATED`

Configura también este query tag al abrir la conexión:

```text
M2_E4_COLAB_CONNECTOR
```

Utiliza autenticación con usuario y contraseña.

No configures en el conector:

- `authenticator="username_password_mfa"`
- `passcode`
- `passcode_in_password`

### 7. Aislar el rol utilizado por la aplicación

Nada más abrir la sesión, desactiva los roles secundarios.

El objetivo es comprobar que el programa funciona únicamente con los privilegios de `ROL_ANALISTA_VENTAS` y no gracias a otro rol administrativo asignado al mismo usuario.

### 8. Comprobar el contexto de la sesión

Ejecuta una consulta que devuelva, como mínimo:

- Usuario actual.
- Rol actual.
- Roles secundarios activos.
- Warehouse actual.
- Base de datos actual.
- Esquema actual.
- Región actual.
- Versión actual de Snowflake.
- Identificador de la sesión.

Muestra los valores de forma legible en la salida del notebook.

El cliente debe detener el flujo normal con un mensaje claro si el rol, warehouse, base de datos o esquema no coinciden con los solicitados.

### 9. Ejecutar una consulta parametrizada

Solicita al usuario un importe mínimo y ejecuta una consulta sobre:

```text
DB_CURSO.CURATED.VENTAS
```

La consulta debe devolver, para cada región que tenga ventas iguales o superiores al importe indicado:

- Región.
- Número de ventas.
- Importe total.
- Importe medio.
- Importe máximo.

Ordena las regiones por importe total descendente.

El importe mínimo debe enviarse como parámetro enlazado. No construyas la sentencia mediante concatenación de texto, f-strings o `str.format()`.

### 10. Recuperar y mostrar los resultados

Utiliza un cursor que permita acceder a cada columna por su nombre.

Muestra en la salida del notebook:

- El Query ID asignado por Snowflake.
- El número de regiones recuperadas.
- Una tabla sencilla con los resultados.

Si no existe ninguna región que cumpla el filtro, el cliente debe mostrar un mensaje informativo y continuar sin fallar.

### 11. Exportar y descargar el informe

Guarda el resultado de la consulta en un fichero temporal llamado:

```text
informe_ventas_region.csv
```

El fichero debe:

- Incluir una fila de cabecera.
- Contener las mismas columnas mostradas en la salida.
- Codificarse en UTF-8.
- Poder abrirse con un editor de texto o una hoja de cálculo.

Muestra la ruta absoluta del fichero generado en el runtime.

Después, utiliza las capacidades de Google Colab para descargar el fichero al ordenador del alumno.

### 12. Validar el mínimo privilegio desde Python

Utilizando la misma conexión y el mismo rol, intenta insertar una fila en:

```text
DB_CURSO.CURATED.VENTAS
```

La operación debe ser rechazada.

Captura el error sin finalizar bruscamente el notebook y muestra, cuando estén disponibles:

- Código de error.
- SQLSTATE.
- Query ID.
- Mensaje devuelto por Snowflake.

El cliente debe indicar claramente que el fallo es el resultado esperado de la prueba de seguridad.

> No cambies a `SYSADMIN` para conseguir que el `INSERT` funcione. La denegación es parte del ejercicio.

La prueba debe estar protegida por una transacción y un `ROLLBACK`, de modo que la fila no quede almacenada aunque el rol tenga por error permisos adicionales.

### 13. Cerrar correctamente los recursos

Asegúrate de que:

- Los cursores se cierran aunque se produzca un error.
- La conexión se cierra al terminar.
- La contraseña no se imprime ni se escribe en el CSV.
- Los errores esperados y no esperados se distinguen claramente.
- La salida informa de que la conexión ha sido cerrada.

No es necesario suspender el warehouse desde el cliente. `ROL_ANALISTA_VENTAS` no debe tener privilegios para operarlo y `WH_LAB_M2` ya dispone de suspensión automática.

### 14. Validar la trazabilidad en Snowsight

Después de ejecutar el notebook, abre Query History y localiza las consultas mediante:

```text
M2_E4_COLAB_CONNECTOR
```

Comprueba, al menos:

- La instrucción que desactiva los roles secundarios.
- La consulta de contexto.
- La consulta agregada por región.
- El intento de `INSERT` rechazado.
- El Query ID mostrado por el notebook.
- El usuario, rol y warehouse empleados.

### 15. Verificar que no se modificaron los datos

Desde un SQL File de Snowsight, trabajando con `SYSADMIN`, comprueba que la tabla `VENTAS` conserva el mismo número de filas que tenía antes de ejecutar el cliente.

El intento de escritura denegado no debe haber añadido ninguna fila.

### 16. Finalizar el trabajo en Colab

Al terminar:

1. Comprueba que el CSV se ha descargado correctamente.
2. Conserva el notebook como evidencia del trabajo.
3. No guardes salidas que contengan información que no deba compartirse.
4. Desconecta y elimina el runtime para liberar los recursos temporales.
5. Suspende `WH_LAB_M2` desde un SQL File si continúa activo.

---

## Criterios de finalización

El ejercicio estará completado cuando puedas demostrar que:

- El conector se instala dentro del runtime y puede importarse correctamente.
- No se ha instalado software en el ordenador del alumno.
- El notebook se conecta a la cuenta trial mediante usuario y contraseña.
- No se solicita ni utiliza un código TOTP.
- La sesión utiliza `ROL_ANALISTA_VENTAS` con los roles secundarios desactivados.
- El contexto efectivo coincide con `WH_LAB_M2`, `DB_CURSO` y `CURATED`.
- La consulta utiliza un parámetro enlazado.
- El cliente recupera y muestra resultados por región.
- Se genera y descarga `informe_ventas_region.csv`.
- El Query ID de la consulta se muestra y puede localizarse en Snowsight.
- El intento de `INSERT` es rechazado y el error se gestiona correctamente.
- Los datos de `VENTAS` no se modifican.
- La conexión se cierra al finalizar.
- El runtime temporal se desconecta después de conservar las evidencias.

---

## Evidencias que debes conservar

Conserva las siguientes evidencias:

1. La salida que muestra las versiones de Python y del conector.
2. El SQL File que devuelve el identificador de cuenta y el usuario.
3. La salida del contexto efectivo de la sesión Python.
4. El código de la consulta parametrizada.
5. El Query ID de la consulta agregada.
6. La salida con los resultados por región.
7. El fichero descargado `informe_ventas_region.csv`.
8. El error de autorización capturado durante el `INSERT`.
9. Una captura o anotación de Query History filtrada por el query tag.
10. La consulta final que confirma que el número de filas de `VENTAS` no ha cambiado.

No incluyas como evidencia ninguna contraseña ni otro secreto de autenticación.

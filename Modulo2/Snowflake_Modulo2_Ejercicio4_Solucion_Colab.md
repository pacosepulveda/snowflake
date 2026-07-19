# Módulo 2 - Ejercicio 4 - Solución guiada

## Conexión programática y consumo seguro de datos con Python desde Google Colab

**Cuenta prevista:** Snowflake Trial, edición Enterprise  
**Entorno Python:** Google Colab  
**Cliente:** Snowflake Connector for Python  
**Autenticación utilizada:** usuario y contraseña, sin MFA  
**Interfaz Snowflake:** Workspaces y SQL Files  

---

## 1. Resultado que vamos a construir

El ejercicio creará un cliente Python ejecutado desde un runtime alojado:

```text
SQL File: obtener parámetros de conexión
                ↓
Google Colab: instalar el conector en el runtime
                ↓
Solicitar la contraseña sin mostrarla
                ↓
Conectar con ROL_ANALISTA_VENTAS
                ↓
Desactivar roles secundarios
                ↓
Validar el contexto efectivo
                ↓
Ejecutar una consulta parametrizada
                ↓
Mostrar resultados y generar un CSV temporal
                ↓
Intentar una escritura que debe ser rechazada
                ↓
Registrar el error y cerrar la conexión
                ↓
Descargar el CSV
                ↓
Snowsight: comprobar Query History y los datos
```

No se instalará ningún componente en el ordenador del alumno. El navegador actúa como interfaz y el código se ejecuta en el runtime de Colab.

El laboratorio utiliza el conector oficial y no requiere Snowpark, pandas, un bucket externo ni un compute pool de Snowflake.

---

## 2. Autenticación utilizada en este laboratorio

La cuenta trial utilizada en el curso no tiene MFA habilitado ni una política que lo exija.

La conexión se realizará con:

```text
Identificador de cuenta + usuario + contraseña
```

Por tanto, el código no debe incluir:

```python
authenticator="username_password_mfa"
```

ni:

```python
passcode=...
```

El conector utilizará su autenticador predeterminado para la autenticación nativa de Snowflake.

Si en el futuro la cuenta habilita o exige MFA, habrá que adaptar el método de conexión. Esa situación no forma parte del recorrido principal de este ejercicio.

---

## 3. Diferencias respecto a una ejecución local

La lógica de conexión es la misma que en un programa Python local, pero cambia la preparación del entorno:

| Ejecución local | Google Colab |
|---|---|
| Instalar Python | El runtime ya incluye Python |
| Crear un entorno virtual | No es necesario |
| Instalar paquetes en el equipo | Se instalan en el runtime temporal |
| Crear un archivo `.py` | Se trabaja en un notebook `.ipynb` |
| Guardar CSV en una carpeta local | Se genera en `/content` y se descarga |
| Cerrar la terminal | Se desconecta el runtime |

El notebook guardado en Google Drive es persistente. En cambio, los paquetes instalados y los ficheros creados en `/content` pueden desaparecer cuando se reinicia o elimina el runtime.

---

## 4. Consideraciones de seguridad

El runtime de Colab es externo a Snowflake. Aplica estas reglas:

1. Utiliza únicamente credenciales de la cuenta trial del curso.
2. No utilices credenciales corporativas o de producción sin autorización.
3. No escribas la contraseña en el código.
4. No guardes la contraseña en Google Drive.
5. No conectes Google Drive al sistema de archivos del runtime para este ejercicio.
6. Introduce la contraseña mediante `getpass()`.
7. Cierra la conexión en un bloque `finally`.
8. Desconecta y elimina el runtime al terminar.

`getpass()` evita que la contraseña aparezca en la salida de la celda o quede escrita en el notebook. La contraseña existirá temporalmente en la memoria del proceso mientras se abre la conexión.

---

## 5. Crear el SQL File de apoyo

En la interfaz actual de Snowflake no utilizaremos una Worksheet heredada.

En Snowsight:

1. Accede a **Projects → Workspaces**.
2. Abre tu workspace.
3. Selecciona **Add new → SQL File**.
4. Ponle el nombre:

```text
M2_E4_CONEXION_COLAB.sql
```

Selecciona un rol administrativo para comprobar los prerrequisitos:

```sql
USE SECONDARY ROLES ALL;
USE ROLE SYSADMIN;
```

Comprueba los objetos principales:

```sql
SHOW WAREHOUSES LIKE 'WH_LAB_M2';
SHOW TABLES LIKE 'VENTAS' IN SCHEMA DB_CURSO.CURATED;
SHOW ROLES LIKE 'ROL_ANALISTA_VENTAS';
```

Comprueba el usuario actual:

```sql
SELECT CURRENT_USER() AS USUARIO_ACTUAL;
```

Copia exactamente el valor devuelto y utilízalo en:

```sql
SHOW GRANTS TO USER <TU_USUARIO>;
```

Ejemplo:

```sql
SHOW GRANTS TO USER ALUMNO01;
```

Busca una fila que indique que el usuario tiene concedido:

```text
ROL_ANALISTA_VENTAS
```

### Comprobar el acceso real del rol

Aísla el rol antes de probarlo:

```sql
USE SECONDARY ROLES NONE;
USE ROLE ROL_ANALISTA_VENTAS;
USE WAREHOUSE WH_LAB_M2;
USE DATABASE DB_CURSO;
USE SCHEMA CURATED;

SELECT COUNT(*) AS NUMERO_FILAS
FROM DB_CURSO.CURATED.VENTAS;
```

La consulta debe funcionar.

Después restaura el contexto administrativo:

```sql
USE SECONDARY ROLES ALL;
USE ROLE SYSADMIN;
```

Si la consulta con el rol de analista falla, revisa los grants del ejercicio 2 antes de continuar.

---

## 6. Obtener los parámetros de conexión

Desde el mismo SQL File, ejecuta:

```sql
SELECT
    CURRENT_ORGANIZATION_NAME() || '-' || CURRENT_ACCOUNT_NAME()
        AS ACCOUNT_IDENTIFIER,
    CURRENT_ACCOUNT()            AS ACCOUNT_LOCATOR,
    CURRENT_ACCOUNT_NAME()       AS ACCOUNT_NAME,
    CURRENT_ORGANIZATION_NAME()  AS ORGANIZATION_NAME,
    CURRENT_USER()               AS USUARIO,
    CURRENT_REGION()             AS REGION,
    CURRENT_VERSION()            AS VERSION_SNOWFLAKE;
```

Conserva especialmente:

- `ACCOUNT_IDENTIFIER`
- `USUARIO`

El identificador recomendado tendrá una forma similar a:

```text
MIORGANIZACION-MICUENTA
```

Para el parámetro `account` del conector:

- Utiliza el identificador de cuenta.
- No añadas `https://`.
- No añadas `.snowflakecomputing.com`.
- No copies la URL completa de Snowsight.

También puedes consultar los parámetros desde la opción de Snowsight equivalente a **Connect a tool to Snowflake**.

> En la mayoría de los laboratorios, `CURRENT_USER()` coincide con el nombre que debe introducirse. Si el administrador configuró un `LOGIN_NAME` diferente, utiliza el nombre de inicio de sesión indicado por él.

---

## 7. Crear el notebook de Google Colab

Accede a Google Colab y crea un notebook nuevo.

Cámbiale el nombre, por ejemplo:

```text
M2_E4_CLIENTE_SNOWFLAKE_ALUMNO.ipynb
```

No necesitas GPU ni TPU. El runtime estándar de CPU es suficiente.

---

## 8. Celda 1: instalar y comprobar el conector

Ejecuta:

```python
%pip install -q --upgrade snowflake-connector-python
```

La orden instala el paquete dentro del entorno Python asociado al kernel del notebook.

Después ejecuta:

```python
import sys
import snowflake.connector

print("Versión de Python:", sys.version.split()[0])
print("Versión del conector:", snowflake.connector.__version__)
print("Importación completada correctamente.")
```

Debes obtener:

- Una versión de Python.
- Una versión del conector.
- Ningún error de importación.

Las versiones pueden variar entre alumnos porque Colab y el conector se actualizan de forma independiente.

> Si el runtime se reinicia, tendrás que volver a ejecutar la instalación.

---

## 9. Celda 2: importaciones, constantes y funciones auxiliares

Ejecuta esta celda:

```python
from __future__ import annotations

import csv
from decimal import Decimal, InvalidOperation
from getpass import getpass
from pathlib import Path
from typing import Any

import snowflake.connector
from snowflake.connector import DictCursor, ProgrammingError


ROLE = "ROL_ANALISTA_VENTAS"
WAREHOUSE = "WH_LAB_M2"
DATABASE = "DB_CURSO"
SCHEMA = "CURATED"
QUERY_TAG = "M2_E4_COLAB_CONNECTOR"
OUTPUT_FILE = Path("/content/informe_ventas_region.csv")


def solicitar_texto(mensaje: str) -> str:
    """Solicita un valor obligatorio y elimina espacios laterales."""
    while True:
        valor = input(mensaje).strip()
        if valor:
            return valor
        print("El valor no puede estar vacío.")


def solicitar_importe() -> Decimal:
    """Solicita y valida el importe mínimo."""
    while True:
        texto = input("Importe mínimo de la venta [500]: ").strip() or "500"

        try:
            importe = Decimal(texto.replace(",", "."))
        except InvalidOperation:
            print("Introduce un número válido, por ejemplo 500 o 750.50.")
            continue

        if importe < 0:
            print("El importe no puede ser negativo.")
            continue

        return importe


def imprimir_contexto(contexto: dict[str, Any]) -> None:
    print("\nContexto efectivo de la sesión")
    print("-" * 44)

    for clave, valor in contexto.items():
        print(f"{clave:24}: {valor}")


def validar_contexto(contexto: dict[str, Any]) -> None:
    esperado = {
        "ROL_ACTUAL": ROLE,
        "WAREHOUSE_ACTUAL": WAREHOUSE,
        "BASE_DATOS_ACTUAL": DATABASE,
        "ESQUEMA_ACTUAL": SCHEMA,
    }

    errores: list[str] = []

    for columna, valor_esperado in esperado.items():
        valor_real = contexto.get(columna)

        if str(valor_real).upper() != valor_esperado:
            errores.append(
                f"{columna}: esperado={valor_esperado}, obtenido={valor_real}"
            )

    if errores:
        detalle = "\n".join(f"- {error}" for error in errores)
        raise RuntimeError(
            "El contexto efectivo no coincide con el solicitado:\n" + detalle
        )


def mostrar_resultados(filas: list[dict[str, Any]]) -> None:
    print("\nInforme de ventas por región")
    print("-" * 88)

    if not filas:
        print("Ninguna región tiene ventas que cumplan el filtro indicado.")
        return

    encabezado = (
        f"{'REGION':<15} {'NUM_VENTAS':>12} {'TOTAL':>16} "
        f"{'MEDIA':>16} {'MAXIMO':>16}"
    )

    print(encabezado)
    print("-" * len(encabezado))

    for fila in filas:
        print(
            f"{str(fila['REGION']):<15} "
            f"{int(fila['NUM_VENTAS']):>12} "
            f"{str(fila['IMPORTE_TOTAL']):>16} "
            f"{str(fila['IMPORTE_MEDIO']):>16} "
            f"{str(fila['IMPORTE_MAXIMO']):>16}"
        )


def exportar_csv(
    filas: list[dict[str, Any]],
    destino: Path,
) -> None:
    columnas = [
        "REGION",
        "NUM_VENTAS",
        "IMPORTE_TOTAL",
        "IMPORTE_MEDIO",
        "IMPORTE_MAXIMO",
    ]

    with destino.open("w", newline="", encoding="utf-8") as fichero:
        escritor = csv.DictWriter(fichero, fieldnames=columnas)
        escritor.writeheader()
        escritor.writerows(filas)


def mostrar_error_snowflake(error: ProgrammingError) -> None:
    print(f"Código de error : {getattr(error, 'errno', None)}")
    print(f"SQLSTATE        : {getattr(error, 'sqlstate', None)}")
    print(f"Query ID        : {getattr(error, 'sfqid', None)}")
    print(f"Mensaje         : {getattr(error, 'msg', str(error))}")
```

Esta celda contiene:

- Las constantes del contexto esperado.
- La validación del importe.
- La presentación del contexto y de los resultados.
- La exportación mediante la biblioteca estándar `csv`.
- La presentación controlada de errores.

No contiene credenciales.

---

## 10. Celda 3: cliente completo

Ejecuta la siguiente celda:

```python
def ejecutar_laboratorio() -> tuple[bool, Path | None]:
    print("Cliente de laboratorio para Snowflake")
    print("=" * 44)
    print(f"Versión del conector: {snowflake.connector.__version__}\n")

    account = solicitar_texto("Identificador de cuenta: ")
    user = solicitar_texto("Usuario de Snowflake: ")
    importe_minimo = solicitar_importe()

    # getpass evita que la contraseña aparezca en la salida.
    password = getpass("Contraseña de Snowflake: ")

    connection = None

    try:
        print("\nAbriendo la conexión...")

        connection = snowflake.connector.connect(
            account=account,
            user=user,
            password=password,
            role=ROLE,
            warehouse=WAREHOUSE,
            database=DATABASE,
            schema=SCHEMA,
            session_parameters={"QUERY_TAG": QUERY_TAG},
            login_timeout=30,
            network_timeout=60,
        )

        # Reducimos el tiempo durante el que conservamos esta referencia.
        password = None

        print("Conexión establecida correctamente.")

        with connection.cursor(DictCursor) as cursor:
            # Impide que otros roles del usuario aporten privilegios.
            cursor.execute("USE SECONDARY ROLES NONE")

            consulta_contexto = """
                SELECT
                    CURRENT_USER()            AS USUARIO_ACTUAL,
                    CURRENT_ROLE()            AS ROL_ACTUAL,
                    CURRENT_SECONDARY_ROLES() AS ROLES_SECUNDARIOS,
                    CURRENT_WAREHOUSE()       AS WAREHOUSE_ACTUAL,
                    CURRENT_DATABASE()        AS BASE_DATOS_ACTUAL,
                    CURRENT_SCHEMA()          AS ESQUEMA_ACTUAL,
                    CURRENT_REGION()          AS REGION_ACTUAL,
                    CURRENT_VERSION()         AS VERSION_SNOWFLAKE,
                    CURRENT_SESSION()         AS ID_SESION
            """

            cursor.execute(consulta_contexto)
            contexto = cursor.fetchone()

            if contexto is None:
                raise RuntimeError(
                    "Snowflake no devolvió el contexto de sesión."
                )

            imprimir_contexto(contexto)
            validar_contexto(contexto)
            print("\nContexto validado correctamente.")

            consulta_ventas = """
                SELECT
                    REGION,
                    COUNT(*)                AS NUM_VENTAS,
                    ROUND(SUM(IMPORTE), 2)  AS IMPORTE_TOTAL,
                    ROUND(AVG(IMPORTE), 2)  AS IMPORTE_MEDIO,
                    ROUND(MAX(IMPORTE), 2)  AS IMPORTE_MAXIMO
                FROM DB_CURSO.CURATED.VENTAS
                WHERE IMPORTE >= %s
                GROUP BY REGION
                ORDER BY IMPORTE_TOTAL DESC, REGION
            """

            # El importe se enlaza como parámetro.
            cursor.execute(consulta_ventas, (importe_minimo,))
            query_id_informe = cursor.sfqid
            filas = cursor.fetchall()

            print(f"\nQuery ID del informe: {query_id_informe}")
            print(f"Regiones recuperadas: {len(filas)}")

            mostrar_resultados(filas)

            exportar_csv(filas, OUTPUT_FILE)
            print(f"\nCSV generado: {OUTPUT_FILE.resolve()}")

            print("\nPrueba negativa de mínimo privilegio")
            print("-" * 44)

            # La transacción garantiza que la fila no quede confirmada
            # aunque el rol tenga por error permisos de INSERT.
            cursor.execute("BEGIN")

            try:
                cursor.execute(
                    """
                    INSERT INTO DB_CURSO.CURATED.VENTAS
                        (ID_VENTA, FECHA, CLIENTE, REGION, IMPORTE)
                    VALUES (%s, CURRENT_DATE(), %s, %s, %s)
                    """,
                    (
                        999999,
                        "CLIENTE_PRUEBA_COLAB",
                        "NORTE",
                        Decimal("1.00"),
                    ),
                )

            except ProgrammingError as error:
                connection.rollback()
                print(
                    "Resultado esperado: "
                    "Snowflake ha rechazado el INSERT."
                )
                mostrar_error_snowflake(error)

            else:
                connection.rollback()
                raise RuntimeError(
                    "La prueba de seguridad ha fallado: "
                    "el INSERT fue aceptado. "
                    "La transacción se ha revertido; revisa los grants de "
                    "ROL_ANALISTA_VENTAS."
                )

        print("\nLaboratorio completado correctamente.")
        return True, OUTPUT_FILE

    except ProgrammingError as error:
        print("\nError no esperado devuelto por Snowflake.")
        mostrar_error_snowflake(error)
        return False, None

    except Exception as error:
        print(f"\nError no esperado: {error}")
        return False, None

    finally:
        # Eliminamos la referencia aunque la conexión no llegase a abrirse.
        password = None

        if connection is not None:
            connection.close()
            print("Conexión cerrada.")


laboratorio_correcto, ruta_csv = ejecutar_laboratorio()
```

Introduce:

1. El identificador de cuenta obtenido en el SQL File.
2. El nombre exacto del usuario.
3. Un importe mínimo, por ejemplo `500`.
4. La contraseña.

No se solicita ningún código TOTP.

---

## 11. Resultado esperado

Una ejecución correcta tendrá una salida conceptualmente similar a esta:

```text
Cliente de laboratorio para Snowflake
============================================
Versión del conector: <version>

Identificador de cuenta: MIORGANIZACION-MICUENTA
Usuario de Snowflake: MI_USUARIO
Importe mínimo de la venta [500]: 500
Contraseña de Snowflake:

Abriendo la conexión...
Conexión establecida correctamente.

Contexto efectivo de la sesión
--------------------------------------------
USUARIO_ACTUAL          : MI_USUARIO
ROL_ACTUAL              : ROL_ANALISTA_VENTAS
ROLES_SECUNDARIOS       : []
WAREHOUSE_ACTUAL        : WH_LAB_M2
BASE_DATOS_ACTUAL       : DB_CURSO
ESQUEMA_ACTUAL          : CURATED
REGION_ACTUAL           : <region>
VERSION_SNOWFLAKE       : <version>
ID_SESION               : <session_id>

Contexto validado correctamente.

Query ID del informe: 01...
Regiones recuperadas: 3

Informe de ventas por región
...

CSV generado: /content/informe_ventas_region.csv

Prueba negativa de mínimo privilegio
--------------------------------------------
Resultado esperado: Snowflake ha rechazado el INSERT.
Código de error : ...
SQLSTATE        : ...
Query ID        : 01...
Mensaje         : Insufficient privileges ...

Laboratorio completado correctamente.
Conexión cerrada.
```

Los valores concretos dependerán de la cuenta, del importe mínimo y de los datos existentes.

---

## 12. Celda 4: descargar el CSV

Cuando la ejecución haya terminado correctamente, ejecuta:

```python
from google.colab import files

if laboratorio_correcto and ruta_csv is not None and ruta_csv.exists():
    files.download(str(ruta_csv))
else:
    print(
        "No existe un CSV válido para descargar. "
        "Revisa la ejecución anterior."
    )
```

El navegador iniciará la descarga de:

```text
informe_ventas_region.csv
```

Comprueba que el fichero se ha guardado antes de desconectar el runtime.

---

## 13. Examinar el CSV

El fichero tendrá una estructura similar a:

```csv
REGION,NUM_VENTAS,IMPORTE_TOTAL,IMPORTE_MEDIO,IMPORTE_MAXIMO
NORTE,2,1595.50,797.75,1350.00
ESTE,2,1510.40,755.20,890.00
CENTRO,1,780.10,780.10,780.10
```

Las filas son un ejemplo para un filtro determinado. Los resultados reales dependen de los datos y del importe mínimo.

Si ninguna venta cumple el filtro, el fichero contendrá únicamente la cabecera. Eso no representa un error.

### Por qué utilizamos `csv`

- Forma parte de Python.
- No necesita instalar pandas.
- Es suficiente para un informe pequeño.
- Mantiene el ejercicio centrado en conexión, seguridad y trazabilidad.

---

## 14. Explicación de las decisiones principales

### 14.1 Instalación con `%pip`

```python
%pip install -q --upgrade snowflake-connector-python
```

`%pip` instala el paquete en el entorno asociado al kernel actual de Jupyter. La instalación se pierde cuando se reemplaza el runtime, pero no modifica el ordenador del alumno.

### 14.2 Contraseña introducida en tiempo de ejecución

```python
password = getpass("Contraseña de Snowflake: ")
```

`getpass()` evita que la contraseña se muestre en la salida o quede escrita en el notebook.

No debemos hacer esto:

```python
PASSWORD = "MiContraseña"
```

### 14.3 Conexión sin MFA

La conexión utiliza:

```python
connection = snowflake.connector.connect(
    account=account,
    user=user,
    password=password,
    ...
)
```

No especificamos un autenticador MFA ni un `passcode` porque la cuenta del laboratorio no lo exige.

### 14.4 Contexto explícito

```python
role=ROLE,
warehouse=WAREHOUSE,
database=DATABASE,
schema=SCHEMA,
```

La aplicación no depende de los valores predeterminados del usuario. Esto evita errores de contexto como los estudiados en el ejercicio 3.

### 14.5 Query tag desde la conexión

```python
session_parameters={"QUERY_TAG": QUERY_TAG},
```

Las sentencias de la sesión quedan asociadas a:

```text
M2_E4_COLAB_CONNECTOR
```

El tag permite localizar la actividad desde Query History.

### 14.6 Aislamiento del rol

```python
cursor.execute("USE SECONDARY ROLES NONE")
```

Aunque la conexión solicita `ROL_ANALISTA_VENTAS`, el usuario puede tener otros roles concedidos. Desactivar los roles secundarios garantiza que las pruebas se autorizan únicamente mediante el rol principal y los roles que este herede.

### 14.7 Cursor de diccionarios

```python
with connection.cursor(DictCursor) as cursor:
```

Cada fila se recupera como un diccionario:

```python
fila["REGION"]
fila["IMPORTE_TOTAL"]
```

Esto es más legible que depender de posiciones numéricas.

### 14.8 Consulta parametrizada

El SQL contiene:

```sql
WHERE IMPORTE >= %s
```

Y el valor se envía por separado:

```python
cursor.execute(consulta_ventas, (importe_minimo,))
```

No se debe hacer:

```python
sql = f"""
    SELECT *
    FROM DB_CURSO.CURATED.VENTAS
    WHERE IMPORTE >= {importe_minimo}
"""
```

El binding separa el texto SQL de los valores introducidos por el usuario.

### 14.9 Query ID

Después de ejecutar la consulta:

```python
query_id_informe = cursor.sfqid
```

`sfqid` contiene el identificador asignado por Snowflake. Ese valor puede buscarse en Query History.

### 14.10 Prueba protegida por transacción

La prueba negativa se ejecuta entre:

```python
cursor.execute("BEGIN")
```

y:

```python
connection.rollback()
```

Si el `INSERT` es rechazado, se registra el error esperado.

Si se acepta debido a una configuración incorrecta, el `ROLLBACK` evita conservar la fila y el notebook informa de un fallo de seguridad.

### 14.11 Cierre seguro

El cursor utiliza un context manager:

```python
with connection.cursor(DictCursor) as cursor:
```

La conexión se cierra en:

```python
finally:
    if connection is not None:
        connection.close()
```

Así se libera la sesión tanto en una ejecución correcta como ante un error.

---

## 15. Interpretar la prueba negativa

El `INSERT` debe fallar porque `ROL_ANALISTA_VENTAS` recibió privilegios de lectura, pero no `INSERT` sobre:

```text
DB_CURSO.CURATED.VENTAS
```

La excepción esperada es:

```python
ProgrammingError
```

El bloque:

```python
except ProgrammingError as error:
```

permite registrar:

- `errno`
- `sqlstate`
- `sfqid`
- `msg`

sin producir un traceback sin controlar.

### Si el INSERT funciona

Esto indica un problema en el diseño de permisos. Posibles causas:

1. El rol recibió `INSERT` directamente.
2. El rol hereda otro rol con permisos de escritura.
3. No se desactivaron correctamente los roles secundarios.
4. Se modificaron los grants después del ejercicio 2.
5. Cambió el ownership de la tabla.

La transacción se revierte antes de informar del problema.

Revisa desde un SQL File:

```sql
USE ROLE SECURITYADMIN;

SHOW GRANTS TO ROLE ROL_ANALISTA_VENTAS;
SHOW GRANTS ON TABLE DB_CURSO.CURATED.VENTAS;
```

---

## 16. Validar Query History

Abre Query History en Snowsight.

Filtra por:

```text
M2_E4_COLAB_CONNECTOR
```

También puedes aplicar:

- Usuario.
- Warehouse `WH_LAB_M2`.
- Intervalo de tiempo.
- Estado correcto o fallido.

Debes encontrar, como mínimo:

1. `USE SECONDARY ROLES NONE`.
2. La consulta de contexto.
3. La consulta agregada sobre `VENTAS`.
4. `BEGIN`.
5. El `INSERT` fallido.
6. El `ROLLBACK`, cuando aparezca registrado.

Abre la consulta agregada y compara su Query ID con el mostrado por el notebook.

Abre el intento de `INSERT` y comprueba:

- Estado fallido.
- Usuario.
- Rol.
- Query tag.
- Query ID.
- Mensaje de autorización.
- Texto SQL.

Algunas instrucciones de sesión o transacción no necesitan utilizar el warehouse de la misma forma que la consulta sobre la tabla.

---

## 17. Verificar que no se modificaron los datos

Crea o reutiliza un SQL File y ejecuta:

```sql
USE SECONDARY ROLES ALL;
USE ROLE SYSADMIN;
USE WAREHOUSE WH_LAB_M2;

SELECT COUNT(*) AS NUMERO_FILAS_FINAL
FROM DB_CURSO.CURATED.VENTAS;
```

Compara el resultado con el número de filas anterior al ejercicio.

Con los datos mínimos del ejercicio 1, el resultado debería continuar siendo:

```text
8
```

Si los alumnos añadieron datos en ejercicios anteriores, el total puede ser distinto. Lo importante es que la ejecución del notebook no incremente el número de filas.

También puedes buscar específicamente la fila de prueba:

```sql
SELECT COUNT(*) AS FILAS_DE_PRUEBA
FROM DB_CURSO.CURATED.VENTAS
WHERE ID_VENTA = 999999;
```

Resultado esperado:

```text
0
```

Al terminar:

```sql
ALTER WAREHOUSE WH_LAB_M2 SUSPEND;
```

---

## 18. Finalizar el runtime de Colab

Después de descargar el CSV:

1. Verifica que el fichero está en el ordenador.
2. Conserva el notebook como evidencia.
3. Elimina cualquier salida que no deba compartirse.
4. Utiliza la opción de Colab para desconectar y eliminar el runtime.

Al eliminar el runtime:

- Se liberan sus recursos.
- Desaparecen los paquetes instalados.
- Desaparecen los ficheros temporales de `/content`.
- El notebook guardado en Drive se conserva.

---

## 19. Errores frecuentes y resolución

### `ModuleNotFoundError: No module named 'snowflake'`

Causa probable: la celda de instalación no se ejecutó en el runtime actual.

Solución:

```python
%pip install -q --upgrade snowflake-connector-python
```

Después, vuelve a ejecutar las celdas de importación.

### La instalación funcionó, pero el runtime se reinició

Los paquetes instalados no son persistentes. Ejecuta de nuevo la primera celda y continúa de arriba abajo.

### Error de identificador de cuenta

Síntomas posibles:

- No se resuelve el host.
- La cuenta no existe.
- Se intenta conectar a otra cuenta.

Obtén el identificador con:

```sql
SELECT
    CURRENT_ORGANIZATION_NAME() || '-' || CURRENT_ACCOUNT_NAME();
```

No incluyas el protocolo ni el dominio completo.

### Error de usuario o contraseña

Comprueba:

- El nombre exacto de inicio de sesión.
- Que la cuenta trial sigue activa.
- Que no has copiado espacios.
- Que estás utilizando la contraseña de Snowflake y no la de Google.

### La conexión solicita MFA inesperadamente

La cuenta o el usuario pueden haber cambiado desde que se redactó el laboratorio:

- El usuario puede haberse inscrito voluntariamente en MFA.
- Puede haberse aplicado una política de autenticación.
- La cuenta puede haber dejado de ser trial.
- El administrador puede haber exigido MFA para conexiones mediante drivers.

En ese caso, no añadas parámetros al azar. Confirma primero con el administrador qué método debe utilizarse y adapta el cliente a la política vigente.

### El rol no está autorizado

Comprueba que el rol está asignado:

```sql
USE ROLE SECURITYADMIN;
SHOW GRANTS TO USER <TU_USUARIO>;
```

### No se puede utilizar el warehouse

Comprueba:

```sql
USE ROLE SECURITYADMIN;
SHOW GRANTS TO ROLE ROL_ANALISTA_VENTAS;
```

El rol necesita `USAGE` sobre `WH_LAB_M2`.

### La tabla no existe o no está autorizado

Comprueba:

- `USAGE` sobre `DB_CURSO`.
- `USAGE` sobre `DB_CURSO.CURATED`.
- `SELECT` sobre `DB_CURSO.CURATED.VENTAS`.
- Que la tabla continúa existiendo.

### El contexto muestra otro rol o esquema

Revisa las constantes:

```python
ROLE = "ROL_ANALISTA_VENTAS"
WAREHOUSE = "WH_LAB_M2"
DATABASE = "DB_CURSO"
SCHEMA = "CURATED"
```

Comprueba también que el usuario tiene derecho a utilizar ese rol.

### El CSV solo contiene la cabecera

No es necesariamente un error. Puede significar que ninguna venta cumple el importe mínimo.

Vuelve a ejecutar con:

```text
0
```

### La descarga no comienza

Comprueba primero:

```python
print(ruta_csv)
print(ruta_csv.exists() if ruta_csv else False)
```

Después vuelve a ejecutar la celda de descarga.

Algunos navegadores pueden bloquear descargas automáticas y solicitar confirmación.

### El CSV desapareció

Los ficheros de `/content` son temporales. Si el runtime se reinició, vuelve a ejecutar el laboratorio y descarga el fichero antes de desconectarlo.

### La conexión desde Colab está bloqueada

Una cuenta con políticas de red restrictivas puede impedir conexiones desde las direcciones de salida de Colab.

Si existe esa restricción, el administrador debe autorizar el origen o proporcionar otro entorno alojado permitido. No desactives controles de red por tu cuenta.

### El warehouse continúa activo

La suspensión automática puede no ocurrir exactamente en el segundo configurado.

Desde un SQL File:

```sql
USE ROLE SYSADMIN;
ALTER WAREHOUSE WH_LAB_M2 SUSPEND;
```

---

## 20. Variante opcional si la cuenta habilita MFA en el futuro

Esta variante no forma parte del ejercicio principal.

Si el administrador confirma que la cuenta exige contraseña y TOTP, será necesario solicitar un código temporal y utilizar la configuración compatible con la política vigente.

Un ejemplo sería:

```python
passcode = getpass("Código TOTP actual: ")

connection = snowflake.connector.connect(
    account=account,
    user=user,
    password=password,
    authenticator="username_password_mfa",
    passcode=passcode,
    role=ROLE,
    warehouse=WAREHOUSE,
    database=DATABASE,
    schema=SCHEMA,
    session_parameters={"QUERY_TAG": QUERY_TAG},
)
```

No utilices esta variante cuando MFA no está configurado.

---

## 21. Consideraciones para producción

Google Colab es adecuado para este laboratorio, pero no es el entorno recomendado para una aplicación de producción.

En un sistema real convendría:

- Ejecutar el cliente en una plataforma controlada por la organización.
- Evitar depender de una contraseña introducida manualmente.
- Utilizar un método de autenticación programática aprobado, como par de claves, OAuth, token de acceso programático o identidad de carga de trabajo, según el escenario.
- Guardar secretos en un gestor de secretos.
- Separar usuarios humanos y usuarios de servicio.
- Mantener el rol de mínimo privilegio.
- Aplicar políticas de red.
- Registrar Query IDs, tags y errores.
- Evitar `fetchall()` para conjuntos muy grandes.
- Utilizar lotes, descarga controlada o procesamiento dentro de Snowflake.
- No utilizar `ACCOUNTADMIN` como rol de una aplicación.

El objetivo del módulo no es construir una arquitectura de aplicación completa, sino demostrar el flujo básico de conexión, contexto, consulta, seguridad y trazabilidad.

---

## 22. Script SQL final de validación

Ejecuta desde un SQL File:

```sql
USE SECONDARY ROLES ALL;
USE ROLE SYSADMIN;
USE WAREHOUSE WH_LAB_M2;
USE DATABASE DB_CURSO;
USE SCHEMA CURATED;

SELECT
    CURRENT_USER()      AS USUARIO,
    CURRENT_ROLE()      AS ROL,
    CURRENT_WAREHOUSE() AS WAREHOUSE,
    CURRENT_DATABASE()  AS BASE_DATOS,
    CURRENT_SCHEMA()    AS ESQUEMA,
    CURRENT_VERSION()   AS VERSION_SNOWFLAKE;

SELECT COUNT(*) AS NUMERO_FILAS_FINAL
FROM DB_CURSO.CURATED.VENTAS;

SELECT COUNT(*) AS FILAS_DE_PRUEBA
FROM DB_CURSO.CURATED.VENTAS
WHERE ID_VENTA = 999999;

SHOW WAREHOUSES LIKE 'WH_LAB_M2';

ALTER WAREHOUSE WH_LAB_M2 SUSPEND;
```

---

## 23. Resultado pedagógico

Al terminar los cuatro ejercicios del módulo 2, el alumno habrá recorrido este flujo:

```text
Preparar Snowflake y sus objetos
        ↓
Aplicar RBAC y mínimo privilegio
        ↓
Diagnosticar contexto, warehouses e historial
        ↓
Conectar una aplicación externa desde un entorno alojado
```

El uso de Google Colab cambia únicamente el lugar en el que se ejecuta Python. El alumno continúa utilizando el conector oficial, abre una conexión externa real, valida el contexto, utiliza parámetros enlazados, genera un fichero y comprueba los permisos efectivos.

---

## 24. Referencias oficiales

- Snowflake Documentation — Workspaces:  
  https://docs.snowflake.com/en/user-guide/ui-snowsight/workspaces

- Snowflake Documentation — Working with Workspaces and SQL Files:  
  https://docs.snowflake.com/en/user-guide/ui-snowsight/workspaces-working

- Snowflake Documentation — Installing the Python Connector:  
  https://docs.snowflake.com/en/developer-guide/python-connector/python-connector-install

- Snowflake Documentation — Connecting with the Python Connector:  
  https://docs.snowflake.com/en/developer-guide/python-connector/python-connector-connect

- Snowflake Documentation — Python Connector API:  
  https://docs.snowflake.com/en/developer-guide/python-connector/python-connector-api

- Snowflake Documentation — Authentication policies:  
  https://docs.snowflake.com/en/user-guide/authentication-policies

- Google Colab — Frequently Asked Questions:  
  https://research.google.com/colaboratory/faq.html

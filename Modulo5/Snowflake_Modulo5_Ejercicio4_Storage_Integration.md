# Laboratorio: carga de datos en Snowflake desde un stage externo en Amazon S3

## Objetivo

En este laboratorio, tres cuentas independientes de Snowflake —la del instructor y las de dos alumnos— accederán al mismo archivo CSV almacenado en una única carpeta de Amazon S3.

Cada participante:

1. Creará una `STORAGE INTEGRATION` en su propia cuenta de Snowflake.
2. Utilizará el mismo rol de AWS IAM para acceder al bucket.
3. Creará un stage externo que apunta a la misma carpeta de S3.
4. Consultará el archivo directamente desde el stage.
5. Cargará los datos en una tabla propia mediante `COPY INTO`.

Aunque las tres cuentas comparten el archivo de origen, las bases de datos, tablas y metadatos de carga permanecen separados en cada cuenta de Snowflake.

---

## Arquitectura del laboratorio

```text
Cuenta Snowflake del instructor ─────┐
Cuenta Snowflake del alumno 1 ──────┼── Rol de AWS IAM ── Bucket S3
Cuenta Snowflake del alumno 2 ──────┘                       │
                                                           └── compartido/ventas.csv
```

La autenticación se realiza mediante:

- Una `STORAGE INTEGRATION` diferente en cada cuenta de Snowflake.
- Un único rol de AWS IAM compartido.
- Un `External ID` diferente para cada integración.
- Una política IAM de solo lectura sobre la carpeta compartida.

No es necesario proporcionar a los alumnos usuarios, contraseñas, claves de acceso ni acceso a la consola de AWS.

---

## Requisitos previos

### Instructor

- Una cuenta de AWS con permisos para administrar:
  - Amazon S3.
  - Políticas de AWS IAM.
  - Roles de AWS IAM.
- Una cuenta de Snowflake Trial.
- Acceso al rol `ACCOUNTADMIN` de Snowflake.

### Alumnos

- Una cuenta de Snowflake Trial por alumno.
- Acceso al rol `ACCOUNTADMIN` de su propia cuenta.

> La creación de una `STORAGE INTEGRATION` requiere `ACCOUNTADMIN` o un rol que tenga el privilegio global `CREATE INTEGRATION`.

---

# 1. Valores que se utilizarán

Antes de comenzar, el instructor debe decidir los siguientes valores.

| Variable | Descripción | Ejemplo de nombre |
|---|---|---|
| `<AWS_ACCOUNT_ID>` | Identificador de la cuenta AWS del instructor | No se fija en esta guía |
| `<S3_BUCKET_NAME>` | Nombre globalmente único del bucket | `sf-demo-curso-<sufijo-unico>` |
| `<S3_PREFIX>` | Carpeta o prefijo compartido | `compartido` |
| `<CSV_FILE_NAME>` | Nombre del archivo | `ventas.csv` |
| `<IAM_POLICY_NAME>` | Nombre de la política IAM | `SnowflakeSharedS3ReadPolicy` |
| `<IAM_ROLE_NAME>` | Nombre del rol IAM | `SnowflakeSharedS3ReadRole` |
| `<IAM_ROLE_ARN>` | ARN completo del rol creado | Se copiará desde AWS |
| `<INTEGRATION_NAME>` | Nombre de la integración | `S3_SHARED_INT` |
| `<STAGE_NAME>` | Nombre del stage externo | `STG_S3_COMPARTIDO` |

La ruta completa de S3 tendrá este formato:

```text
s3://<S3_BUCKET_NAME>/<S3_PREFIX>/<CSV_FILE_NAME>
```

Por ejemplo, usando los nombres propuestos:

```text
s3://<S3_BUCKET_NAME>/compartido/ventas.csv
```

---

# 2. Crear el archivo CSV

Crea un archivo local llamado `ventas.csv` con el siguiente contenido:

```csv
id_venta,fecha,producto,cantidad,precio
1,2026-07-01,Teclado,2,29.90
2,2026-07-02,Raton,5,18.50
3,2026-07-03,Monitor,1,249.99
4,2026-07-04,Portatil,1,899.00
5,2026-07-05,Auriculares,3,45.75
```

Guárdalo con codificación UTF-8.

---

# 3. Crear el bucket en Amazon S3

Este apartado lo realiza únicamente el instructor.

1. Accede a la consola de AWS.
2. Abre **Amazon S3**.
3. Selecciona **Create bucket**.
4. Introduce como nombre:

   ```text
   <S3_BUCKET_NAME>
   ```

5. Selecciona la región en la que deseas crear el bucket.
6. Mantén activado **Block all public access**.
7. Mantén deshabilitadas las ACL, salvo que exista una necesidad específica de utilizarlas.
8. Crea el bucket.

El bucket no debe hacerse público.

---

# 4. Crear la carpeta y subir el archivo

Dentro del bucket:

1. Selecciona **Create folder**.
2. Introduce como nombre:

   ```text
   <S3_PREFIX>
   ```

3. Entra en la carpeta.
4. Selecciona **Upload**.
5. Carga el archivo:

   ```text
   <CSV_FILE_NAME>
   ```

Comprueba que la ruta final sea:

```text
s3://<S3_BUCKET_NAME>/<S3_PREFIX>/<CSV_FILE_NAME>
```

---

# 5. Crear la política IAM de solo lectura

Este apartado lo realiza únicamente el instructor.

La política debe conceder dos grupos de permisos diferentes:

- Permisos sobre el bucket:
  - `s3:GetBucketLocation`
  - `s3:ListBucket`
- Permisos sobre los objetos de la carpeta:
  - `s3:GetObject`
  - `s3:GetObjectVersion`

## 5.1 Crear la política

1. Abre **AWS IAM**.
2. Accede a **Policies**.
3. Selecciona **Create policy**.
4. Abre el editor **JSON**.
5. Pega la siguiente política:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ListSharedSnowflakeFolder",
      "Effect": "Allow",
      "Action": [
        "s3:GetBucketLocation",
        "s3:ListBucket"
      ],
      "Resource": "arn:aws:s3:::<S3_BUCKET_NAME>",
      "Condition": {
        "StringLike": {
          "s3:prefix": [
            "<S3_PREFIX>",
            "<S3_PREFIX>/*"
          ]
        }
      }
    },
    {
      "Sid": "ReadSharedSnowflakeFiles",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:GetObjectVersion"
      ],
      "Resource": "arn:aws:s3:::<S3_BUCKET_NAME>/<S3_PREFIX>/*"
    }
  ]
}
```

6. Sustituye:
   - `<S3_BUCKET_NAME>` por el nombre real del bucket.
   - `<S3_PREFIX>` por el nombre real de la carpeta.
7. Continúa hasta crear la política.
8. Asigna como nombre:

   ```text
   <IAM_POLICY_NAME>
   ```

## 5.2 Diferencia entre los ARN del bucket y de los objetos

Para `s3:ListBucket`, se usa el ARN del bucket:

```text
arn:aws:s3:::<S3_BUCKET_NAME>
```

Para `s3:GetObject`, se usa el ARN de los objetos:

```text
arn:aws:s3:::<S3_BUCKET_NAME>/<S3_PREFIX>/*
```

Usar únicamente el ARN del bucket no concede permiso para leer los archivos.

---

# 6. Crear el rol IAM compartido

Este apartado lo realiza únicamente el instructor.

El rol tendrá:

1. Una **política de permisos**, que permite leer el archivo de S3.
2. Una **política de confianza**, que determina qué identidades de Snowflake pueden asumirlo.

Estas dos políticas cumplen funciones diferentes.

## 6.1 Crear inicialmente el rol

1. En **AWS IAM**, abre **Roles**.
2. Selecciona **Create role**.
3. Selecciona como entidad de confianza una **AWS account**.
4. Elige la opción para confiar en otra cuenta AWS.
5. Introduce temporalmente:

   ```text
   <AWS_ACCOUNT_ID>
   ```

6. Activa la opción para requerir un **External ID**.
7. Introduce un valor provisional, por ejemplo:

   ```text
   TEMPORAL
   ```

8. Continúa al apartado de permisos.
9. Adjunta la política:

   ```text
   <IAM_POLICY_NAME>
   ```

10. Asigna al rol el nombre:

    ```text
    <IAM_ROLE_NAME>
    ```

11. Crea el rol.

> La relación de confianza provisional se sustituirá más adelante por los valores generados por las tres cuentas de Snowflake.

## 6.2 Comprobar que la política de permisos está adjunta

Abre:

```text
IAM → Roles → <IAM_ROLE_NAME> → Permissions
```

Comprueba que aparece:

```text
<IAM_POLICY_NAME>
```

Este paso es imprescindible. Crear una política IAM no la adjunta automáticamente al rol.

## 6.3 Copiar el ARN del rol

En la página del rol, copia su ARN completo:

```text
<IAM_ROLE_ARN>
```

Su estructura general será:

```text
arn:aws:iam::<AWS_ACCOUNT_ID>:role/<IAM_ROLE_NAME>
```

Este ARN se proporcionará a los tres participantes.

---

# 7. Crear la integración en cada cuenta de Snowflake

Este apartado debe ejecutarse tres veces:

- En la cuenta del instructor.
- En la cuenta del alumno 1.
- En la cuenta del alumno 2.

Cada participante abre un worksheet de Snowflake y ejecuta:

```sql
USE ROLE ACCOUNTADMIN;

CREATE STORAGE INTEGRATION <INTEGRATION_NAME>
    TYPE = EXTERNAL_STAGE
    STORAGE_PROVIDER = 'S3'
    ENABLED = TRUE
    STORAGE_AWS_ROLE_ARN = '<IAM_ROLE_ARN>'
    STORAGE_ALLOWED_LOCATIONS = (
        's3://<S3_BUCKET_NAME>/<S3_PREFIX>/'
    );
```

Sustituye todos los marcadores por los valores proporcionados por el instructor.

Ejemplo sin identificadores reales:

```sql
USE ROLE ACCOUNTADMIN;

CREATE STORAGE INTEGRATION S3_SHARED_INT
    TYPE = EXTERNAL_STAGE
    STORAGE_PROVIDER = 'S3'
    ENABLED = TRUE
    STORAGE_AWS_ROLE_ARN =
        'arn:aws:iam::<AWS_ACCOUNT_ID>:role/SnowflakeSharedS3ReadRole'
    STORAGE_ALLOWED_LOCATIONS = (
        's3://<S3_BUCKET_NAME>/compartido/'
    );
```

## Advertencia sobre `CREATE OR REPLACE`

No utilices:

```sql
CREATE OR REPLACE STORAGE INTEGRATION ...
```

una vez configurada la relación de confianza en AWS.

Al recrear una integración sin fijar expresamente el `External ID`, Snowflake puede generar uno nuevo. En ese caso, será necesario actualizar de nuevo la política de confianza del rol IAM.

---

# 8. Obtener los valores de cada integración

En cada cuenta de Snowflake, ejecuta:

```sql
DESC INTEGRATION <INTEGRATION_NAME>;
```

A continuación, sin ejecutar otra consulta entre medias:

```sql
SELECT
    "property",
    "property_value"
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
WHERE "property" IN (
    'STORAGE_AWS_IAM_USER_ARN',
    'STORAGE_AWS_EXTERNAL_ID'
)
ORDER BY "property";
```

Cada participante debe entregar al instructor estos dos valores:

```text
STORAGE_AWS_IAM_USER_ARN
STORAGE_AWS_EXTERNAL_ID
```

El instructor puede recopilarlos en esta tabla:

| Participante | `STORAGE_AWS_IAM_USER_ARN` | `STORAGE_AWS_EXTERNAL_ID` |
|---|---|---|
| Instructor | `<SNOWFLAKE_IAM_USER_ARN_INSTRUCTOR>` | `<EXTERNAL_ID_INSTRUCTOR>` |
| Alumno 1 | `<SNOWFLAKE_IAM_USER_ARN_ALUMNO_1>` | `<EXTERNAL_ID_ALUMNO_1>` |
| Alumno 2 | `<SNOWFLAKE_IAM_USER_ARN_ALUMNO_2>` | `<EXTERNAL_ID_ALUMNO_2>` |

Copia los valores exactamente, respetando todos los caracteres.

---

# 9. Configurar la política de confianza del rol

Este apartado lo realiza únicamente el instructor.

1. En AWS, abre:

   ```text
   IAM → Roles → <IAM_ROLE_NAME>
   ```

2. Accede a **Trust relationships**.
3. Selecciona **Edit trust policy**.
4. Sustituye la política provisional por la siguiente:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "SnowflakeInstructor",
      "Effect": "Allow",
      "Principal": {
        "AWS": "<SNOWFLAKE_IAM_USER_ARN_INSTRUCTOR>"
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": {
          "sts:ExternalId": "<EXTERNAL_ID_INSTRUCTOR>"
        }
      }
    },
    {
      "Sid": "SnowflakeAlumno1",
      "Effect": "Allow",
      "Principal": {
        "AWS": "<SNOWFLAKE_IAM_USER_ARN_ALUMNO_1>"
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": {
          "sts:ExternalId": "<EXTERNAL_ID_ALUMNO_1>"
        }
      }
    },
    {
      "Sid": "SnowflakeAlumno2",
      "Effect": "Allow",
      "Principal": {
        "AWS": "<SNOWFLAKE_IAM_USER_ARN_ALUMNO_2>"
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": {
          "sts:ExternalId": "<EXTERNAL_ID_ALUMNO_2>"
        }
      }
    }
  ]
}
```

5. Sustituye los seis marcadores por los valores obtenidos en Snowflake.
6. Guarda los cambios.

## Política de confianza frente a política de permisos

La política de confianza permite que Snowflake ejecute:

```text
sts:AssumeRole
```

La política de permisos concede al rol las acciones sobre S3:

```text
s3:ListBucket
s3:GetBucketLocation
s3:GetObject
s3:GetObjectVersion
```

Que Snowflake consiga asumir el rol no implica que el rol tenga permiso para leer el archivo. Ambas configuraciones deben ser correctas.

---

# 10. Validar la integración

Cada participante ejecuta en su propia cuenta de Snowflake:

```sql
SELECT SYSTEM$VALIDATE_STORAGE_INTEGRATION(
    '<INTEGRATION_NAME>',
    's3://<S3_BUCKET_NAME>/<S3_PREFIX>/',
    '<CSV_FILE_NAME>',
    'read'
);
```

Ejemplo:

```sql
SELECT SYSTEM$VALIDATE_STORAGE_INTEGRATION(
    'S3_SHARED_INT',
    's3://<S3_BUCKET_NAME>/compartido/',
    'ventas.csv',
    'read'
);
```

El resultado debe indicar:

```json
{
  "status": "success"
}
```

Si la validación falla, consulta la sección **Resolución de errores**.

---

# 11. Crear los objetos de trabajo en cada cuenta

Cada participante ejecuta el siguiente bloque en su propia cuenta.

```sql
USE ROLE ACCOUNTADMIN;

CREATE WAREHOUSE IF NOT EXISTS DEMO_WH
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE;

CREATE DATABASE IF NOT EXISTS DEMO_S3;
CREATE SCHEMA IF NOT EXISTS DEMO_S3.CARGAS;

USE WAREHOUSE DEMO_WH;
USE DATABASE DEMO_S3;
USE SCHEMA CARGAS;
```

---

# 12. Crear el formato de archivo

```sql
CREATE OR REPLACE FILE FORMAT FF_VENTAS_CSV
    TYPE = CSV
    FIELD_DELIMITER = ','
    SKIP_HEADER = 1
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    TRIM_SPACE = TRUE
    EMPTY_FIELD_AS_NULL = TRUE
    NULL_IF = ('NULL', 'null', '');
```

---

# 13. Crear el stage externo

Cada participante crea en su cuenta un stage que apunta a la misma ubicación de S3:

```sql
CREATE OR REPLACE STAGE <STAGE_NAME>
    URL = 's3://<S3_BUCKET_NAME>/<S3_PREFIX>/'
    STORAGE_INTEGRATION = <INTEGRATION_NAME>
    FILE_FORMAT = FF_VENTAS_CSV;
```

Ejemplo:

```sql
CREATE OR REPLACE STAGE STG_S3_COMPARTIDO
    URL = 's3://<S3_BUCKET_NAME>/compartido/'
    STORAGE_INTEGRATION = S3_SHARED_INT
    FILE_FORMAT = FF_VENTAS_CSV;
```

---

# 14. Listar los archivos del stage

```sql
LIST @<STAGE_NAME>;
```

Ejemplo:

```sql
LIST @STG_S3_COMPARTIDO;
```

Los tres participantes deben ver el mismo archivo de S3.

Resultado esperado:

```text
s3://<S3_BUCKET_NAME>/<S3_PREFIX>/<CSV_FILE_NAME>
```

---

# 15. Consultar el archivo directamente

Antes de cargar los datos en una tabla, consulta el CSV desde el stage:

```sql
SELECT
    $1 AS ID_VENTA,
    $2 AS FECHA,
    $3 AS PRODUCTO,
    $4 AS CANTIDAD,
    $5 AS PRECIO
FROM @<STAGE_NAME>/<CSV_FILE_NAME>;
```

Ejemplo:

```sql
SELECT
    $1 AS ID_VENTA,
    $2 AS FECHA,
    $3 AS PRODUCTO,
    $4 AS CANTIDAD,
    $5 AS PRECIO
FROM @STG_S3_COMPARTIDO/ventas.csv;
```

Resultado esperado:

```text
1 | 2026-07-01 | Teclado     | 2 | 29.90
2 | 2026-07-02 | Raton       | 5 | 18.50
3 | 2026-07-03 | Monitor     | 1 | 249.99
4 | 2026-07-04 | Portatil    | 1 | 899.00
5 | 2026-07-05 | Auriculares | 3 | 45.75
```

---

# 16. Crear la tabla de destino

```sql
CREATE OR REPLACE TABLE VENTAS (
    ID_VENTA NUMBER(10,0),
    FECHA DATE,
    PRODUCTO VARCHAR(100),
    CANTIDAD NUMBER(10,0),
    PRECIO NUMBER(10,2)
);
```

Comprueba que inicialmente está vacía:

```sql
SELECT *
FROM VENTAS;
```

---

# 17. Validar la carga sin insertar filas

```sql
COPY INTO VENTAS
FROM @<STAGE_NAME>
FILES = ('<CSV_FILE_NAME>')
VALIDATION_MODE = 'RETURN_ERRORS';
```

Ejemplo:

```sql
COPY INTO VENTAS
FROM @STG_S3_COMPARTIDO
FILES = ('ventas.csv')
VALIDATION_MODE = 'RETURN_ERRORS';
```

Si el archivo y la tabla son compatibles, no se devolverán errores de validación.

---

# 18. Cargar los datos

```sql
COPY INTO VENTAS
FROM @<STAGE_NAME>
FILES = ('<CSV_FILE_NAME>')
ON_ERROR = 'ABORT_STATEMENT';
```

Ejemplo:

```sql
COPY INTO VENTAS
FROM @STG_S3_COMPARTIDO
FILES = ('ventas.csv')
ON_ERROR = 'ABORT_STATEMENT';
```

El resultado debe mostrar cinco filas cargadas y ningún error.

---

# 19. Comprobar el resultado

```sql
SELECT *
FROM VENTAS
ORDER BY ID_VENTA;
```

También puedes obtener un resumen:

```sql
SELECT
    COUNT(*) AS NUM_FILAS,
    SUM(CANTIDAD) AS UNIDADES,
    SUM(CANTIDAD * PRECIO) AS IMPORTE_TOTAL
FROM VENTAS;
```

Las tres cuentas obtendrán los mismos datos, pero cada una los habrá cargado en su propia tabla.

---

# 20. Demostrar la independencia de las cuentas

Los tres participantes leen:

```text
s3://<S3_BUCKET_NAME>/<S3_PREFIX>/<CSV_FILE_NAME>
```

Sin embargo, cada cuenta tiene sus propios objetos:

```text
Cuenta del instructor
└── DEMO_S3.CARGAS.VENTAS

Cuenta del alumno 1
└── DEMO_S3.CARGAS.VENTAS

Cuenta del alumno 2
└── DEMO_S3.CARGAS.VENTAS
```

La carga realizada en una cuenta no modifica las tablas ni el historial de carga de las otras cuentas.

---

# 21. Repetir la carga

Snowflake registra los archivos cargados para evitar que un mismo archivo vuelva a insertarse accidentalmente en la misma tabla.

Si se ejecuta otra vez:

```sql
COPY INTO VENTAS
FROM @STG_S3_COMPARTIDO
FILES = ('ventas.csv');
```

Snowflake normalmente no volverá a cargar el archivo.

Para repetir el laboratorio desde cero:

```sql
TRUNCATE TABLE VENTAS;
```

Después, vuelve a ejecutar:

```sql
COPY INTO VENTAS
FROM @STG_S3_COMPARTIDO
FILES = ('ventas.csv')
ON_ERROR = 'ABORT_STATEMENT';
```

También existe la opción:

```sql
COPY INTO VENTAS
FROM @STG_S3_COMPARTIDO
FILES = ('ventas.csv')
FORCE = TRUE;
```

Sin embargo, `FORCE = TRUE` puede generar duplicados si la tabla no se vacía previamente.

---

# 22. Resolución de errores

## 22.1 Snowflake no puede asumir el rol

Mensajes habituales:

```text
Failed to assume AWS_ROLE
```

o errores relacionados con `sts:AssumeRole`.

### Comprobaciones

1. El valor de `STORAGE_AWS_ROLE_ARN` coincide exactamente con el ARN del rol.
2. La política de confianza contiene el `STORAGE_AWS_IAM_USER_ARN` correcto.
3. La condición contiene el `STORAGE_AWS_EXTERNAL_ID` correcto.
4. Los valores pertenecen a la integración y a la cuenta de Snowflake que se está probando.
5. La integración no se ha recreado después de configurar la política de confianza.

### Acción recomendada

Ejecuta de nuevo:

```sql
DESC INTEGRATION <INTEGRATION_NAME>;
```

Obtén los valores actuales y compáralos con la política de confianza de AWS.

---

## 22.2 Snowflake asume el rol, pero recibe `s3:GetObject AccessDenied`

Ejemplo de mensaje:

```text
assumed-role/<IAM_ROLE_NAME>/snowflake is not authorized to perform:
s3:GetObject on resource:
arn:aws:s3:::<S3_BUCKET_NAME>/<S3_PREFIX>/<CSV_FILE_NAME>
because no identity-based policy allows the s3:GetObject action
```

Este error significa:

- La política de confianza funciona.
- Snowflake ha asumido correctamente el rol.
- El rol no tiene un permiso efectivo `s3:GetObject` sobre el archivo.

### Comprobaciones

Abre:

```text
IAM → Roles → <IAM_ROLE_NAME> → Permissions
```

Comprueba que la política `<IAM_POLICY_NAME>` está adjunta al rol.

La política debe incluir:

```json
{
  "Effect": "Allow",
  "Action": [
    "s3:GetObject",
    "s3:GetObjectVersion"
  ],
  "Resource": "arn:aws:s3:::<S3_BUCKET_NAME>/<S3_PREFIX>/*"
}
```

Errores frecuentes:

- La política se creó, pero no se adjuntó al rol.
- La política se adjuntó a otro rol con un nombre parecido.
- Se utilizó otro nombre de bucket.
- Se utilizó otro prefijo.
- Solo se incluyó el ARN del bucket y no el ARN de sus objetos.
- Hay diferencias de mayúsculas y minúsculas en el nombre del rol o del prefijo.

No es necesario modificar la política de confianza si Snowflake ya consigue asumir el rol.

---

## 22.3 `LIST` devuelve `AccessDenied`

Comprueba que la política del rol contiene:

```json
{
  "Effect": "Allow",
  "Action": [
    "s3:GetBucketLocation",
    "s3:ListBucket"
  ],
  "Resource": "arn:aws:s3:::<S3_BUCKET_NAME>"
}
```

Si se utiliza una condición por prefijo, debe incluir la ruta correcta:

```json
"Condition": {
  "StringLike": {
    "s3:prefix": [
      "<S3_PREFIX>",
      "<S3_PREFIX>/*"
    ]
  }
}
```

---

## 22.4 `Location is not allowed by integration`

La URL del stage debe estar incluida en `STORAGE_ALLOWED_LOCATIONS`.

Integración:

```sql
STORAGE_ALLOWED_LOCATIONS = (
    's3://<S3_BUCKET_NAME>/<S3_PREFIX>/'
);
```

Stage:

```sql
URL = 's3://<S3_BUCKET_NAME>/<S3_PREFIX>/'
```

Comprueba:

- Nombre del bucket.
- Nombre del prefijo.
- Barra `/` final.
- Ausencia de espacios adicionales.

---

## 22.5 Solo funciona una de las tres cuentas

Comprueba que la política de confianza contiene tres entradas:

- Instructor.
- Alumno 1.
- Alumno 2.

Cada entrada debe utilizar el par correcto:

```text
STORAGE_AWS_IAM_USER_ARN + STORAGE_AWS_EXTERNAL_ID
```

No mezcles el ARN de una cuenta con el `External ID` de otra.

---

## 22.6 La integración dejó de funcionar después de recrearla

Al ejecutar:

```sql
CREATE OR REPLACE STORAGE INTEGRATION ...
```

Snowflake puede generar un nuevo `STORAGE_AWS_EXTERNAL_ID`.

Solución:

1. Ejecuta `DESC INTEGRATION`.
2. Obtén el nuevo `External ID`.
3. Actualiza la política de confianza en AWS.

---

## 22.7 El segundo `COPY INTO` no carga filas

Es el comportamiento esperado. Snowflake evita volver a cargar en la misma tabla un archivo que ya figura en su historial de carga.

Para repetir la práctica:

```sql
TRUNCATE TABLE VENTAS;
```

---

## 22.8 El archivo está cifrado con una clave KMS administrada por el cliente

Si el objeto de S3 utiliza SSE-KMS con una clave administrada por el cliente, el rol también puede necesitar permiso para descifrar mediante AWS KMS y la política de la clave debe permitir el acceso.

Para una demostración inicial, utiliza la configuración de cifrado predeterminada del bucket y evita añadir una clave KMS personalizada, salvo que el uso de KMS forme parte de los objetivos del laboratorio.

---

# 23. Limpieza del laboratorio

## En cada cuenta de Snowflake

```sql
USE ROLE ACCOUNTADMIN;

DROP DATABASE IF EXISTS DEMO_S3;
DROP WAREHOUSE IF EXISTS DEMO_WH;
DROP STORAGE INTEGRATION IF EXISTS <INTEGRATION_NAME>;
```

## En AWS

El instructor puede eliminar:

1. El archivo de S3.
2. La carpeta o prefijo.
3. El bucket, una vez vacío.
4. El rol IAM.
5. La política IAM.

> No elimines los recursos si se van a reutilizar en otros laboratorios.

---

# 24. Resumen del orden de ejecución

## Preparación del instructor en AWS

1. Crear `ventas.csv`.
2. Crear el bucket.
3. Crear la carpeta compartida.
4. Subir el archivo.
5. Crear la política IAM de solo lectura.
6. Crear el rol IAM.
7. Adjuntar la política de permisos al rol.
8. Copiar el ARN del rol.

## Trabajo en las tres cuentas de Snowflake

9. Crear una `STORAGE INTEGRATION` por cuenta.
10. Obtener `STORAGE_AWS_IAM_USER_ARN`.
11. Obtener `STORAGE_AWS_EXTERNAL_ID`.
12. Entregar ambos valores al instructor.

## Configuración final del instructor en AWS

13. Actualizar la política de confianza con las tres cuentas.

## Demostración en las tres cuentas de Snowflake

14. Validar la integración.
15. Crear warehouse, base de datos y esquema.
16. Crear el formato de archivo.
17. Crear el stage externo.
18. Ejecutar `LIST`.
19. Consultar el archivo desde el stage.
20. Crear la tabla.
21. Validar `COPY INTO`.
22. Cargar los datos.
23. Consultar los resultados.
24. Comprobar el control de cargas duplicadas.

---

# 25. Referencias oficiales

- Snowflake: configuración de una storage integration para Amazon S3  
  <https://docs.snowflake.com/en/user-guide/data-load-s3-config-storage-integration>

- Snowflake: `CREATE STORAGE INTEGRATION`  
  <https://docs.snowflake.com/en/sql-reference/sql/create-storage-integration>

- Snowflake: `SYSTEM$VALIDATE_STORAGE_INTEGRATION`  
  <https://docs.snowflake.com/en/sql-reference/functions/system_validate_storage_integration>

- Snowflake: creación de un stage externo para S3  
  <https://docs.snowflake.com/en/user-guide/data-load-s3-create-stage>

- Snowflake: `COPY INTO <table>`  
  <https://docs.snowflake.com/en/sql-reference/sql/copy-into-table>

- AWS: acceso de terceros mediante roles y `External ID`  
  <https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_common-scenarios_third-party.html>

- AWS: actualización de la política de confianza de un rol  
  <https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_update-role-trust-policy.html>

- AWS: permisos y políticas de Amazon S3  
  <https://docs.aws.amazon.com/AmazonS3/latest/userguide/access-policy-language-overview.html>

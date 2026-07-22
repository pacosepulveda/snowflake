# Módulo 3 - Ejercicio 4 - Solución guiada

## Diagnóstico, resolución y prevención de bloqueos y deadlocks

**Cuenta prevista:** Snowflake Trial, edición Enterprise  
**Interfaz:** Snowsight  

---

## 1. Qué vamos a demostrar

Este laboratorio reproduce dos incidentes diferentes.

### Incidente 1: bloqueo entre escritores

```text
SESIÓN A                              SESIÓN B
BEGIN
UPDATE CENTRO 1
mantiene el bloqueo
                                      UPDATE CENTRO 1
                                      queda esperando

                    SESIÓN C
       SHOW TRANSACTIONS + SHOW LOCKS
       QUERY_HISTORY + diagnóstico
       SYSTEM$ABORT_TRANSACTION
```

La sesión C identificará:

- La consulta que espera.
- La transacción que mantiene el bloqueo.
- El recurso afectado.
- El tiempo bloqueado.
- La sesión responsable.

Después abortará de forma controlada la transacción bloqueadora.

### Incidente 2: espera circular y deadlock

```text
SESIÓN A                              SESIÓN B
bloquea CENTROS                       bloquea RUTAS
espera RUTAS                          espera CENTROS

              dependencia circular
                     DEADLOCK
```

Snowflake documenta que detecta deadlocks, pero también advierte que la detección puede tardar. Por ello, el laboratorio no utilizará la aparición de un error automático como criterio de éxito. Construiremos el ciclo, lo identificaremos mediante `SHOW LOCKS` y seleccionaremos manualmente una transacción víctima antes de que venza `LOCK_TIMEOUT`.

Por último repetiremos el escenario usando un orden consistente:

```text
CENTROS → RUTAS
```

Esto no elimina necesariamente todas las esperas, pero evita la dependencia circular.

---

## 2. Consideraciones importantes antes de comenzar

### Tres SQL Files, tres sesiones

Crea:

```text
M3_E3_SESION_A
M3_E3_SESION_B
M3_E3_DIAGNOSTICO
```

Las tres sesiones deben utilizar el mismo usuario.

Una transacción pertenece a una sesión. No ejecutes todo el laboratorio como un único script.

### Diagnóstico inmediato e histórico

Para el diagnóstico en tiempo real utilizaremos:

- `SHOW TRANSACTIONS`.
- `SHOW LOCKS`.
- Las funciones `QUERY_HISTORY` de `INFORMATION_SCHEMA`.

La vista:

```text
SNOWFLAKE.ACCOUNT_USAGE.LOCK_WAIT_HISTORY
```

es útil para análisis histórico, pero puede presentar una latencia de hasta varias horas. No debe utilizarse como requisito para resolver el incidente en directo.

### No cambiar parámetros dentro de una transacción

Configura `QUERY_TAG`, `LOCK_TIMEOUT` y `TRANSACTION_ABORT_ON_ERROR` antes de ejecutar `BEGIN`.

Evita ejecutar comandos de configuración entre el primer DML y el `COMMIT` o `ROLLBACK`.

---

# Parte A - Preparación

## 3. Preparar la sesión A

En `M3_E3_SESION_A` ejecuta:

```sql
USE ROLE SYSADMIN;
USE WAREHOUSE WH_M3_ANALITICA;
USE DATABASE DB_CURSO;
USE SCHEMA ARQUITECTURA;

ALTER SESSION SET USE_CACHED_RESULT = FALSE;
ALTER SESSION SET LOCK_TIMEOUT = 120;
ALTER SESSION SET TRANSACTION_ABORT_ON_ERROR = FALSE;
ALTER SESSION SET QUERY_TAG = 'M3_E3_SESION_A';

SELECT
    CURRENT_USER()      AS USUARIO,
    CURRENT_ROLE()      AS ROL,
    CURRENT_WAREHOUSE() AS WAREHOUSE,
    CURRENT_DATABASE()  AS BASE_DATOS,
    CURRENT_SCHEMA()    AS ESQUEMA,
    CURRENT_SESSION()   AS ID_SESION;
```

Guarda el Session ID de A.

### Por qué usamos `LOCK_TIMEOUT = 120`

El valor predeterminado de `LOCK_TIMEOUT` es 43.200 segundos, es decir, 12 horas.

En un laboratorio no queremos una espera indefinida. Dos minutos ofrecen tiempo suficiente para alternar entre las sesiones y diagnosticar el bloqueo.

No esperaremos a que se agote ese tiempo: liberaremos el recurso antes.

### Por qué forzamos `TRANSACTION_ABORT_ON_ERROR = FALSE`

Queremos observar que un error de sentencia —por ejemplo, un timeout o una detección automática de deadlock— no tiene por qué cerrar por sí solo toda la transacción.

Este comportamiento es fundamental para entender por qué pueden seguir existiendo bloqueos después del error y por qué todavía puede ser necesario ejecutar `ROLLBACK` o `SYSTEM$ABORT_TRANSACTION`.

---

## 4. Preparar la sesión B

En `M3_E3_SESION_B` ejecuta:

```sql
USE ROLE SYSADMIN;
USE WAREHOUSE WH_M3_ANALITICA;
USE DATABASE DB_CURSO;
USE SCHEMA ARQUITECTURA;

ALTER SESSION SET USE_CACHED_RESULT = FALSE;
ALTER SESSION SET LOCK_TIMEOUT = 120;
ALTER SESSION SET TRANSACTION_ABORT_ON_ERROR = FALSE;
ALTER SESSION SET QUERY_TAG = 'M3_E3_SESION_B';

SELECT
    CURRENT_USER()      AS USUARIO,
    CURRENT_ROLE()      AS ROL,
    CURRENT_WAREHOUSE() AS WAREHOUSE,
    CURRENT_DATABASE()  AS BASE_DATOS,
    CURRENT_SCHEMA()    AS ESQUEMA,
    CURRENT_SESSION()   AS ID_SESION;
```

Guarda el Session ID de B.

Debe ser diferente del Session ID de A.

---

## 5. Preparar la sesión C

En `M3_E3_DIAGNOSTICO` ejecuta:

```sql
USE ROLE SYSADMIN;
USE WAREHOUSE WH_M3_ANALITICA;
USE DATABASE DB_CURSO;
USE SCHEMA ARQUITECTURA;

ALTER SESSION SET USE_CACHED_RESULT = FALSE;
ALTER SESSION SET QUERY_TAG = 'M3_E3_DIAGNOSTICO';

SELECT
    CURRENT_USER()      AS USUARIO,
    CURRENT_ROLE()      AS ROL,
    CURRENT_WAREHOUSE() AS WAREHOUSE,
    CURRENT_DATABASE()  AS BASE_DATOS,
    CURRENT_SCHEMA()    AS ESQUEMA,
    CURRENT_SESSION()   AS ID_SESION;
```

El Session ID de C debe ser diferente de A y B.

---

## 6. Crear las tablas del laboratorio

Ejecuta desde la sesión A:

```sql
ALTER SESSION SET QUERY_TAG = 'M3_E3_PREPARACION';

CREATE OR REPLACE TRANSIENT TABLE DB_CURSO.ARQUITECTURA.M3_CENTROS_POSTALES (
    ID_CENTRO            NUMBER(10,0)  NOT NULL,
    CENTRO                VARCHAR(100)  NOT NULL,
    CAPACIDAD_DIARIA      NUMBER(10,0)  NOT NULL,
    CAPACIDAD_DISPONIBLE  NUMBER(10,0)  NOT NULL,
    ACTUALIZADO_EN        TIMESTAMP_LTZ NOT NULL
);

INSERT INTO DB_CURSO.ARQUITECTURA.M3_CENTROS_POSTALES
    (
        ID_CENTRO,
        CENTRO,
        CAPACIDAD_DIARIA,
        CAPACIDAD_DISPONIBLE,
        ACTUALIZADO_EN
    )
VALUES
    (1, 'Centro Madrid',   1000, 1000, CURRENT_TIMESTAMP()),
    (2, 'Centro Barcelona', 900,  900, CURRENT_TIMESTAMP()),
    (3, 'Centro Valencia',  700,  700, CURRENT_TIMESTAMP());

CREATE OR REPLACE TRANSIENT TABLE DB_CURSO.ARQUITECTURA.M3_RUTAS_POSTALES (
    ID_RUTA           NUMBER(10,0)  NOT NULL,
    ID_CENTRO         NUMBER(10,0)  NOT NULL,
    ZONA              VARCHAR(100)  NOT NULL,
    ENVIOS_ASIGNADOS  NUMBER(10,0)  NOT NULL,
    ESTADO            VARCHAR(30)   NOT NULL,
    ACTUALIZADO_EN    TIMESTAMP_LTZ NOT NULL
);

INSERT INTO DB_CURSO.ARQUITECTURA.M3_RUTAS_POSTALES
    (
        ID_RUTA,
        ID_CENTRO,
        ZONA,
        ENVIOS_ASIGNADOS,
        ESTADO,
        ACTUALIZADO_EN
    )
VALUES
    (101, 1, 'Madrid Norte', 200, 'PLANIFICADA', CURRENT_TIMESTAMP()),
    (102, 1, 'Madrid Sur',   180, 'PLANIFICADA', CURRENT_TIMESTAMP()),
    (201, 2, 'Barcelona',    160, 'PLANIFICADA', CURRENT_TIMESTAMP());
```

Comprueba:

```sql
SELECT *
FROM DB_CURSO.ARQUITECTURA.M3_CENTROS_POSTALES
ORDER BY ID_CENTRO;

SELECT *
FROM DB_CURSO.ARQUITECTURA.M3_RUTAS_POSTALES
ORDER BY ID_RUTA;
```

Datos relevantes:

```text
CENTRO 1
CAPACIDAD_DISPONIBLE = 1000

RUTA 101
ENVIOS_ASIGNADOS = 200
```

---

# Parte B - Incidente 1: bloqueo entre escritores

## 7. Sesión A: iniciar la transacción bloqueadora

En la sesión A configura el tag antes de abrir la transacción:

```sql
ALTER SESSION SET QUERY_TAG = 'M3_E3_A_BLOQUEADOR';
```

Ejecuta únicamente este bloque:

```sql
BEGIN TRANSACTION;

UPDATE DB_CURSO.ARQUITECTURA.M3_CENTROS_POSTALES
SET
    CAPACIDAD_DISPONIBLE = CAPACIDAD_DISPONIBLE - 200,
    ACTUALIZADO_EN = CURRENT_TIMESTAMP()
WHERE ID_CENTRO = 1;

SELECT
    ID_CENTRO,
    CENTRO,
    CAPACIDAD_DISPONIBLE,
    ACTUALIZADO_EN
FROM DB_CURSO.ARQUITECTURA.M3_CENTROS_POSTALES
WHERE ID_CENTRO = 1;

SELECT CURRENT_TRANSACTION() AS TRANSACCION_A;
```

No ejecutes todavía `COMMIT` ni `ROLLBACK`.

Resultado visible en A:

```text
CAPACIDAD_DISPONIBLE = 800
```

### Qué está ocurriendo

La sesión A ve sus propios cambios pendientes.

La reducción de 200 unidades todavía no está confirmada para otras sesiones, pero la transacción mantiene el recurso necesario para modificar esa parte de la tabla.

Anota el valor de:

```text
TRANSACCION_A
```

---

## 8. Sesión B: provocar la espera

En la sesión B ejecuta primero:

```sql
ALTER SESSION SET QUERY_TAG = 'M3_E3_B_BLOQUEADA';
```

Después ejecuta solamente este `UPDATE`:

```sql
UPDATE DB_CURSO.ARQUITECTURA.M3_CENTROS_POSTALES
SET
    CAPACIDAD_DISPONIBLE = CAPACIDAD_DISPONIBLE - 50,
    ACTUALIZADO_EN = CURRENT_TIMESTAMP()
WHERE ID_CENTRO = 1;
```

La consulta debe permanecer ejecutándose.

No la canceles.

### Por qué se bloquea

La sesión B intenta escribir sobre el mismo recurso que está siendo modificado por una transacción todavía abierta en A.

MVCC permite que otras sesiones lean una versión confirmada, pero no permite que dos escritores creen simultáneamente cambios incompatibles sobre el mismo recurso sin coordinación.

---

## 9. Sesión C: consultar las transacciones activas

Mientras B sigue esperando, en C ejecuta:

```sql
SHOW TRANSACTIONS;
```

Inmediatamente después consulta el resultado:

```sql
SELECT
    "id"         AS TRANSACTION_ID,
    "user"       AS USUARIO,
    "session"    AS SESSION_ID,
    "name"       AS NOMBRE,
    "started_on" AS INICIADA_EN,
    "state"      AS ESTADO
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
ORDER BY "started_on";
```

Deberías localizar al menos:

- La transacción explícita iniciada en A.
- La transacción asociada al `UPDATE` de B que está esperando.

La transacción de A comenzó antes y será la candidata a bloqueadora.

---

## 10. Sesión C: consultar los bloqueos

Ejecuta:

```sql
SHOW LOCKS;
```

Después:

```sql
SELECT
    "resource"               AS RECURSO,
    "type"                   AS TIPO,
    "transaction"            AS TRANSACTION_ID,
    "transaction_started_on" AS TRANSACCION_INICIADA_EN,
    "status"                 AS ESTADO,
    "acquired_on"            AS ADQUIRIDO_EN,
    "query_id"               AS QUERY_ID
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
ORDER BY "resource", "status";
```

El patrón esperado es similar a:

```text
RECURSO                                      ESTADO
DB_CURSO.ARQUITECTURA.M3_CENTROS_POSTALES   HOLDING
DB_CURSO.ARQUITECTURA.M3_CENTROS_POSTALES   WAITING
```

### Interpretación

La fila `HOLDING` identifica:

- La transacción que mantiene el bloqueo.
- El recurso que está reteniendo.

La fila `WAITING` identifica:

- La transacción que espera.
- El Query ID de la sentencia bloqueada.

No asumas que la consulta más larga es siempre la bloqueadora. Debes comprobar el estado del bloqueo.

---

## 11. Sesión C: consultar Query History en tiempo real

Ejecuta:

```sql
SELECT
    QUERY_ID,
    SESSION_ID,
    QUERY_TAG,
    EXECUTION_STATUS,
    TRANSACTION_ID,
    TOTAL_ELAPSED_TIME,
    EXECUTION_TIME,
    TRANSACTION_BLOCKED_TIME,
    START_TIME,
    END_TIME,
    ERROR_MESSAGE,
    QUERY_TEXT
FROM TABLE(
    DB_CURSO.INFORMATION_SCHEMA.QUERY_HISTORY(
        END_TIME_RANGE_START => DATEADD(
            'MINUTE',
            -30,
            CURRENT_TIMESTAMP()
        ),
        RESULT_LIMIT => 200
    )
)
WHERE QUERY_TAG IN (
    'M3_E3_A_BLOQUEADOR',
    'M3_E3_B_BLOQUEADA'
)
ORDER BY START_TIME;
```

La consulta de B debería mostrar:

```text
QUERY_TAG                  = M3_E3_B_BLOQUEADA
EXECUTION_STATUS           = BLOCKED
TRANSACTION_BLOCKED_TIME   > 0
```

El valor de `TRANSACTION_BLOCKED_TIME` está expresado en milisegundos y puede aumentar mientras la consulta continúa esperando.

### Correlación completa

Relaciona la información:

```text
SHOW LOCKS
    QUERY_ID de WAITING
        ↓
QUERY_HISTORY
    texto, tag, sesión, tiempo bloqueado
        ↓
SHOW TRANSACTIONS
    Transaction ID, Session ID, hora de inicio
```

---

## 12. Elaborar el diagnóstico

Un diagnóstico correcto debería parecerse a:

```text
CONSULTA BLOQUEADA:
UPDATE de la sesión B etiquetado como M3_E3_B_BLOQUEADA

TRANSACCIÓN BLOQUEADA:
Transaction ID asociado a la fila WAITING

SESIÓN BLOQUEADA:
Session ID de B

TRANSACCIÓN BLOQUEADORA:
Transaction ID asociado a la fila HOLDING

SESIÓN BLOQUEADORA:
Session ID de A

RECURSO:
DB_CURSO.ARQUITECTURA.M3_CENTROS_POSTALES

CAUSA:
La sesión A mantiene una transacción explícita sin COMMIT ni ROLLBACK
después de modificar el centro 1.
```

### Por qué no basta con cancelar B

Cancelar la consulta de B eliminaría la espera visible, pero A seguiría manteniendo:

- La transacción abierta.
- El cambio pendiente.
- El bloqueo.

La causa raíz continuaría presente y otra operación podría volver a quedar bloqueada.

---

## 13. Abortar la transacción bloqueadora

Copia desde `SHOW LOCKS` el Transaction ID de la fila `HOLDING`.

Desde C ejecuta, sustituyendo el valor:

```sql
SELECT SYSTEM$ABORT_TRANSACTION(<TRANSACTION_ID_BLOQUEADORA>);
```

Ejemplo de formato:

```sql
SELECT SYSTEM$ABORT_TRANSACTION(1234567890123456789);
```

No utilices el número del ejemplo. Debes copiar el ID real de tu sesión A.

### Permisos

La función puede ser ejecutada:

- Por el usuario que inició la transacción.
- Por un administrador de cuenta.

Como A y C utilizan el mismo usuario, C puede abortar la transacción iniciada en A.

### Qué ocurre en A

La transacción se revierte.

La reducción:

```text
1000 → 800
```

no se confirma.

Si intentas ejecutar `COMMIT` después, ya no existe la transacción original que confirmar.

### Qué ocurre en B

Al liberarse el recurso, el `UPDATE` de B puede continuar.

Como B ejecutó un DML con autocommit y no había abierto una transacción explícita, el cambio se confirma al finalizar correctamente:

```text
1000 → 950
```

---

## 14. Verificar la recuperación

En B o C ejecuta:

```sql
SELECT
    ID_CENTRO,
    CENTRO,
    CAPACIDAD_DIARIA,
    CAPACIDAD_DISPONIBLE,
    ACTUALIZADO_EN
FROM DB_CURSO.ARQUITECTURA.M3_CENTROS_POSTALES
WHERE ID_CENTRO = 1;
```

Resultado esperado:

```text
CAPACIDAD_DISPONIBLE = 950
```

Desde C:

```sql
SHOW TRANSACTIONS;
```

```sql
SHOW LOCKS;
```

No deberían aparecer transacciones ni bloqueos del primer incidente.

### Revisar el historial final

```sql
SELECT
    QUERY_ID,
    SESSION_ID,
    QUERY_TAG,
    EXECUTION_STATUS,
    TRANSACTION_ID,
    TOTAL_ELAPSED_TIME,
    TRANSACTION_BLOCKED_TIME,
    ERROR_MESSAGE,
    QUERY_TEXT
FROM TABLE(
    DB_CURSO.INFORMATION_SCHEMA.QUERY_HISTORY(
        END_TIME_RANGE_START => DATEADD(
            'MINUTE',
            -30,
            CURRENT_TIMESTAMP()
        ),
        RESULT_LIMIT => 300
    )
)
WHERE QUERY_TAG IN (
    'M3_E3_A_BLOQUEADOR',
    'M3_E3_B_BLOQUEADA'
)
ORDER BY START_TIME;
```

La consulta de B puede aparecer ahora como `SUCCESS`, pero conservará el tiempo que pasó bloqueada.

---

# Parte C - Incidente 2: espera circular y deadlock

## 15. Qué vamos a validar realmente

La documentación de Snowflake indica que los deadlocks pueden producirse en transacciones explícitas con varias sentencias y que Snowflake selecciona como víctima la sentencia más reciente implicada. También indica que la detección puede tardar. Snowflake podría detectar automáticamente el deadlock, pero el tiempo necesario no está garantizado. Si no lo detecta antes del timeout, el laboratorio continúa mediante diagnóstico y resolución manual.

Esto tiene una consecuencia importante para el laboratorio:

```text
LOCK_TIMEOUT puede vencer antes de que aparezca un error explícito de deadlock.
```

Por tanto, no esperaremos a que Snowflake resuelva automáticamente el ciclo. El objetivo práctico será:

1. Crear la dependencia circular.
2. Demostrarla con cuatro filas `HOLDING`/`WAITING`.
3. Seleccionar una víctima con criterio operativo.
4. Abortar su transacción desde la sesión de diagnóstico.
5. Confirmar únicamente la transacción que debe conservarse.

Este enfoque es más determinista y más parecido a una intervención real de operaciones.

---

## 16. Restaurar el estado y ampliar temporalmente el timeout

Asegúrate primero de que no hay transacciones activas.

Desde C:

```sql
SHOW TRANSACTIONS;
SHOW LOCKS;
```

Después, desde A o C:

```sql
UPDATE DB_CURSO.ARQUITECTURA.M3_CENTROS_POSTALES
SET
    CAPACIDAD_DISPONIBLE = 1000,
    ACTUALIZADO_EN = CURRENT_TIMESTAMP()
WHERE ID_CENTRO = 1;

UPDATE DB_CURSO.ARQUITECTURA.M3_RUTAS_POSTALES
SET
    ENVIOS_ASIGNADOS = 200,
    ACTUALIZADO_EN = CURRENT_TIMESTAMP()
WHERE ID_RUTA = 101;
```

Comprueba:

```sql
SELECT
    C.ID_CENTRO,
    C.CAPACIDAD_DISPONIBLE,
    R.ID_RUTA,
    R.ENVIOS_ASIGNADOS
FROM DB_CURSO.ARQUITECTURA.M3_CENTROS_POSTALES C
JOIN DB_CURSO.ARQUITECTURA.M3_RUTAS_POSTALES R
    ON R.ID_CENTRO = C.ID_CENTRO
WHERE C.ID_CENTRO = 1
  AND R.ID_RUTA = 101;
```

Resultado:

```text
CAPACIDAD_DISPONIBLE = 1000
ENVIOS_ASIGNADOS     = 200
```

Antes de abrir nuevas transacciones, ejecuta en A y B:

```sql
ALTER SESSION SET LOCK_TIMEOUT = 300;
```

No pretendemos esperar 300 segundos. El valor solo evita que el timeout de 120 segundos interrumpa el diagnóstico demasiado pronto.

---

## 17. Sesión A: adquirir CENTROS

Antes de `BEGIN`, ejecuta:

```sql
ALTER SESSION SET QUERY_TAG = 'M3_E3_DEADLOCK_A';
```

Después:

```sql
BEGIN TRANSACTION;

UPDATE DB_CURSO.ARQUITECTURA.M3_CENTROS_POSTALES
SET
    CAPACIDAD_DISPONIBLE = CAPACIDAD_DISPONIBLE - 10,
    ACTUALIZADO_EN = CURRENT_TIMESTAMP()
WHERE ID_CENTRO = 1;

SELECT CURRENT_TRANSACTION() AS TRANSACCION_DEADLOCK_A;
```

Anota el Transaction ID de A y no ejecutes `COMMIT` ni `ROLLBACK`.

A mantiene:

```text
M3_CENTROS_POSTALES
CAPACIDAD_DISPONIBLE pendiente = 990
```

---

## 18. Sesión B: adquirir RUTAS

Antes de `BEGIN`, ejecuta:

```sql
ALTER SESSION SET QUERY_TAG = 'M3_E3_DEADLOCK_B';
```

Después:

```sql
BEGIN TRANSACTION;

UPDATE DB_CURSO.ARQUITECTURA.M3_RUTAS_POSTALES
SET
    ENVIOS_ASIGNADOS = ENVIOS_ASIGNADOS + 10,
    ACTUALIZADO_EN = CURRENT_TIMESTAMP()
WHERE ID_RUTA = 101;

SELECT CURRENT_TRANSACTION() AS TRANSACCION_DEADLOCK_B;
```

Anota el Transaction ID de B y no ejecutes `COMMIT` ni `ROLLBACK`.

B mantiene:

```text
M3_RUTAS_POSTALES
ENVIOS_ASIGNADOS pendiente = 210
```

Todavía no existe un ciclo:

```text
A mantiene CENTROS
B mantiene RUTAS
```

---

## 19. Sesión A: esperar por RUTAS

En A ejecuta únicamente:

```sql
UPDATE DB_CURSO.ARQUITECTURA.M3_RUTAS_POSTALES
SET
    ENVIOS_ASIGNADOS = ENVIOS_ASIGNADOS + 20,
    ACTUALIZADO_EN = CURRENT_TIMESTAMP()
WHERE ID_RUTA = 101;
```

La sentencia queda esperando porque B mantiene el recurso de rutas.

Situación:

```text
A mantiene CENTROS
A espera RUTAS
B mantiene RUTAS
```

Todavía existe una espera en una única dirección.

---

## 20. Sesión B: cerrar el ciclo

Mientras A continúa esperando, ejecuta en B:

```sql
UPDATE DB_CURSO.ARQUITECTURA.M3_CENTROS_POSTALES
SET
    CAPACIDAD_DISPONIBLE = CAPACIDAD_DISPONIBLE - 20,
    ACTUALIZADO_EN = CURRENT_TIMESTAMP()
WHERE ID_CENTRO = 1;
```

Ahora las dos sentencias quedan esperando:

```text
A mantiene CENTROS y espera RUTAS
B mantiene RUTAS y espera CENTROS
```

No esperes a que aparezca un error. Cambia inmediatamente a la sesión C.

---

## 21. Sesión C: demostrar la espera circular

Ejecuta:

```sql
SHOW LOCKS;
```

Filtra el resultado:

```sql
SELECT
    "resource"               AS RECURSO,
    "type"                   AS TIPO,
    "transaction"            AS TRANSACTION_ID,
    "transaction_started_on" AS TRANSACCION_INICIADA_EN,
    "status"                 AS ESTADO,
    "acquired_on"            AS ADQUIRIDO_EN,
    "query_id"               AS QUERY_ID
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
WHERE "resource" IN (
    'DB_CURSO.ARQUITECTURA.M3_CENTROS_POSTALES',
    'DB_CURSO.ARQUITECTURA.M3_RUTAS_POSTALES'
)
ORDER BY "resource", "status";
```

Mientras las dos sentencias siguen esperando, el patrón esperado es:

| Recurso | Transaction ID | Estado | Interpretación |
|---|---:|---|---|
| `M3_CENTROS_POSTALES` | A | `HOLDING` | A mantiene CENTROS |
| `M3_CENTROS_POSTALES` | B | `WAITING` | B espera CENTROS |
| `M3_RUTAS_POSTALES` | B | `HOLDING` | B mantiene RUTAS |
| `M3_RUTAS_POSTALES` | A | `WAITING` | A espera RUTAS |

A continuación:

```sql
SHOW TRANSACTIONS;
```

```sql
SELECT
    "id"         AS TRANSACTION_ID,
    "user"       AS USUARIO,
    "session"    AS SESSION_ID,
    "started_on" AS INICIADA_EN,
    "state"      AS ESTADO
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
ORDER BY "started_on";
```

### Validación crítica

Comprueba que:

```text
WAITING sobre RUTAS   usa el mismo Transaction ID que A HOLDING sobre CENTROS
WAITING sobre CENTROS usa el mismo Transaction ID que B HOLDING sobre RUTAS
```

Si no coinciden, no existe un ciclo entre las dos transacciones originales. Alguna sentencia se ejecutó desde una sesión diferente.

### Consultar Query History

```sql
SELECT
    QUERY_ID,
    SESSION_ID,
    QUERY_TAG,
    EXECUTION_STATUS,
    TRANSACTION_ID,
    TOTAL_ELAPSED_TIME,
    TRANSACTION_BLOCKED_TIME,
    START_TIME,
    ERROR_CODE,
    ERROR_MESSAGE,
    QUERY_TEXT
FROM TABLE(
    DB_CURSO.INFORMATION_SCHEMA.QUERY_HISTORY(
        END_TIME_RANGE_START => DATEADD(
            'MINUTE',
            -30,
            CURRENT_TIMESTAMP()
        ),
        RESULT_LIMIT => 400
    )
)
WHERE QUERY_TAG IN (
    'M3_E3_DEADLOCK_A',
    'M3_E3_DEADLOCK_B'
)
ORDER BY START_TIME;
```

Los dos últimos `UPDATE` deben aparecer ejecutándose o bloqueados y acumular `TRANSACTION_BLOCKED_TIME`.

### Grafo de espera

```text
TRANSACCIÓN A
  mantiene CENTROS
  espera RUTAS
  bloqueada por B

TRANSACCIÓN B
  mantiene RUTAS
  espera CENTROS
  bloqueada por A

A → B → A
```

Este ciclo es el deadlock, aunque todavía no haya aparecido un mensaje automático con esa palabra.

---

## 22. Por qué no esperamos al detector automático

Snowflake puede detectar el deadlock y elegir como víctima la sentencia más reciente, pero no documenta un tiempo máximo de detección.

`LOCK_TIMEOUT`, en cambio, sí aborta una sentencia cuando alcanza el número de segundos configurado.

Por eso pueden darse dos comportamientos válidos:

```text
A. El detector actúa antes y una sentencia recibe un error de deadlock.
B. LOCK_TIMEOUT vence antes y las sentencias reciben errores de espera agotada.
```

El laboratorio debe funcionar en ambos casos. El criterio de éxito es haber demostrado el ciclo con los Transaction ID, no recibir una redacción concreta de error.

---

## 23. Sesión C: seleccionar y abortar la víctima

Elegiremos B como víctima porque:

- Su segunda solicitud se ejecutó después.
- Solo tiene un cambio previo pendiente en este laboratorio.
- Al revertir B, A puede completar las dos operaciones relacionadas.

Copia el Transaction ID de B y ejecuta desde C:

```sql
SELECT SYSTEM$ABORT_TRANSACTION(<TRANSACTION_ID_B>);
```

Ejemplo de formato:

```sql
SELECT SYSTEM$ABORT_TRANSACTION(1234567890123456789);
```

Utiliza el ID real, no el ejemplo.

### Efectos esperados

En B:

- La sentencia bloqueada termina con error.
- Se revierte también su primer `UPDATE` sobre rutas.
- Se libera el bloqueo de `M3_RUTAS_POSTALES`.

En A:

- El segundo `UPDATE` puede adquirir el recurso de rutas.
- La sentencia termina correctamente.
- La transacción A continúa abierta hasta ejecutar `COMMIT`.

### Si Snowflake ya eligió una víctima automáticamente

Si el segundo `UPDATE` de B ya falló antes de ejecutar `SYSTEM$ABORT_TRANSACTION`, comprueba si la transacción B sigue activa.

En ese caso ejecuta en B:

```sql
ROLLBACK;
```

O aborta desde C el Transaction ID de B. No confirmes parcialmente esa transacción.

---

## 24. Confirmar la transacción A

Espera a que el segundo `UPDATE` de A finalice y ejecuta en A:

```sql
COMMIT;
```

A confirma conjuntamente:

```text
CENTRO 1
1000 → 990

RUTA 101
200 → 220
```

Comprueba desde C:

```sql
SELECT
    C.ID_CENTRO,
    C.CAPACIDAD_DISPONIBLE,
    R.ID_RUTA,
    R.ENVIOS_ASIGNADOS
FROM DB_CURSO.ARQUITECTURA.M3_CENTROS_POSTALES C
JOIN DB_CURSO.ARQUITECTURA.M3_RUTAS_POSTALES R
    ON R.ID_CENTRO = C.ID_CENTRO
WHERE C.ID_CENTRO = 1
  AND R.ID_RUTA = 101;
```

Resultado esperado:

```text
CAPACIDAD_DISPONIBLE = 990
ENVIOS_ASIGNADOS     = 220
```

El incremento de 10 realizado inicialmente por B no aparece porque toda la transacción B fue abortada.

---

## 25. Verificar la recuperación y revisar el historial

Desde C:

```sql
SHOW TRANSACTIONS;
SHOW LOCKS;
```

No deben quedar transacciones ni bloqueos del segundo incidente.

Consulta de nuevo Query History:

```sql
SELECT
    QUERY_ID,
    SESSION_ID,
    QUERY_TAG,
    EXECUTION_STATUS,
    TRANSACTION_ID,
    TOTAL_ELAPSED_TIME,
    TRANSACTION_BLOCKED_TIME,
    ERROR_CODE,
    ERROR_MESSAGE,
    QUERY_TEXT
FROM TABLE(
    DB_CURSO.INFORMATION_SCHEMA.QUERY_HISTORY(
        END_TIME_RANGE_START => DATEADD(
            'MINUTE',
            -30,
            CURRENT_TIMESTAMP()
        ),
        RESULT_LIMIT => 400
    )
)
WHERE QUERY_TAG IN (
    'M3_E3_DEADLOCK_A',
    'M3_E3_DEADLOCK_B'
)
ORDER BY START_TIME;
```

El texto del error dependerá de qué mecanismo actuó primero:

- Aborto manual de la transacción.
- Detección automática del deadlock.
- `LOCK_TIMEOUT`, si el diagnóstico se demoró demasiado.

La causa raíz es la misma:

```text
Los dos procesos adquirieron los mismos recursos en distinto orden.
```

---

# Parte D - Prevención práctica

## 26. Restaurar los valores

Ejecuta desde C:

```sql
UPDATE DB_CURSO.ARQUITECTURA.M3_CENTROS_POSTALES
SET
    CAPACIDAD_DISPONIBLE = 1000,
    ACTUALIZADO_EN = CURRENT_TIMESTAMP()
WHERE ID_CENTRO = 1;

UPDATE DB_CURSO.ARQUITECTURA.M3_RUTAS_POSTALES
SET
    ENVIOS_ASIGNADOS = 200,
    ACTUALIZADO_EN = CURRENT_TIMESTAMP()
WHERE ID_RUTA = 101;
```

Comprueba que no hay transacciones activas:

```sql
SHOW TRANSACTIONS;
SHOW LOCKS;
```

---

## 27. Sesión A: usar el orden CENTROS → RUTAS

Antes de abrir la transacción:

```sql
ALTER SESSION SET QUERY_TAG = 'M3_E3_ORDEN_A';
```

Después:

```sql
BEGIN TRANSACTION;

UPDATE DB_CURSO.ARQUITECTURA.M3_CENTROS_POSTALES
SET
    CAPACIDAD_DISPONIBLE = CAPACIDAD_DISPONIBLE - 10,
    ACTUALIZADO_EN = CURRENT_TIMESTAMP()
WHERE ID_CENTRO = 1;
```

Mantén A abierta.

---

## 28. Sesión B: utilizar el mismo primer recurso

Antes de abrir la transacción:

```sql
ALTER SESSION SET QUERY_TAG = 'M3_E3_ORDEN_B';
```

Después:

```sql
BEGIN TRANSACTION;

UPDATE DB_CURSO.ARQUITECTURA.M3_CENTROS_POSTALES
SET
    CAPACIDAD_DISPONIBLE = CAPACIDAD_DISPONIBLE - 20,
    ACTUALIZADO_EN = CURRENT_TIMESTAMP()
WHERE ID_CENTRO = 1;
```

B queda esperando porque A mantiene el centro.

La situación es:

```text
A mantiene CENTROS
B espera CENTROS
```

No existe un ciclo porque B todavía no mantiene `RUTAS`.

---

## 29. Sesión A: actualizar RUTAS y confirmar

Mientras B espera, en A ejecuta:

```sql
UPDATE DB_CURSO.ARQUITECTURA.M3_RUTAS_POSTALES
SET
    ENVIOS_ASIGNADOS = ENVIOS_ASIGNADOS + 10,
    ACTUALIZADO_EN = CURRENT_TIMESTAMP()
WHERE ID_RUTA = 101;

COMMIT;
```

A confirma:

```text
CAPACIDAD_DISPONIBLE = 990
ENVIOS_ASIGNADOS     = 210
```

Al liberar el centro, el primer `UPDATE` de B puede finalizar:

```text
CAPACIDAD_DISPONIBLE = 970
```

---

## 30. Sesión B: actualizar RUTAS y confirmar

Cuando el primer `UPDATE` de B haya terminado, ejecuta:

```sql
UPDATE DB_CURSO.ARQUITECTURA.M3_RUTAS_POSTALES
SET
    ENVIOS_ASIGNADOS = ENVIOS_ASIGNADOS + 20,
    ACTUALIZADO_EN = CURRENT_TIMESTAMP()
WHERE ID_RUTA = 101;

COMMIT;
```

Comprueba:

```sql
SELECT
    C.ID_CENTRO,
    C.CAPACIDAD_DISPONIBLE,
    R.ID_RUTA,
    R.ENVIOS_ASIGNADOS
FROM DB_CURSO.ARQUITECTURA.M3_CENTROS_POSTALES C
JOIN DB_CURSO.ARQUITECTURA.M3_RUTAS_POSTALES R
    ON R.ID_CENTRO = C.ID_CENTRO
WHERE C.ID_CENTRO = 1
  AND R.ID_RUTA = 101;
```

Resultado:

```text
CAPACIDAD_DISPONIBLE = 970
ENVIOS_ASIGNADOS     = 230
```

### Qué ha cambiado

En el diseño original:

```text
A: CENTROS → RUTAS
B: RUTAS   → CENTROS
```

En el diseño corregido:

```text
A: CENTROS → RUTAS
B: CENTROS → RUTAS
```

B puede esperar, pero no mantiene el segundo recurso mientras espera el primero.

No se forma una dependencia circular.

### Una espera no es un deadlock

```text
ESPERA:
A mantiene un recurso.
B espera.
A puede continuar y liberar el recurso.

DEADLOCK:
A espera un recurso de B.
B espera un recurso de A.
Ninguna puede avanzar por sí sola.
```

---

## 31. Medidas preventivas

### 31.1 Orden consistente de adquisición

Todos los procesos que necesiten modificar centros y rutas deben utilizar:

```text
CENTROS → RUTAS
```

El orden puede ser otro, pero debe ser compartido por todos los procesos.

### 31.2 Transacciones cortas

Evita:

```sql
BEGIN;

UPDATE ...;

/* llamada externa */
/* espera humana */
/* procesamiento largo */
/* lectura de ficheros */

UPDATE ...;

COMMIT;
```

Realiza el trabajo preparatorio antes de abrir la transacción.

La transacción debe contener únicamente las operaciones que necesiten confirmarse o revertirse como una unidad.

### 31.3 `LOCK_TIMEOUT` adecuado

El valor predeterminado es 12 horas.

Un proceso interactivo puede necesitar un timeout corto. Una carga crítica puede necesitar un valor mayor.

Ejemplo:

```sql
ALTER SESSION SET LOCK_TIMEOUT = 30;
```

No existe un valor universal. Debe elegirse en función de:

- Duración normal del proceso.
- Capacidad de reintento.
- Impacto sobre los usuarios.
- Objetivos de servicio.
- Riesgo de ejecutar dos veces la operación.

### 31.4 Query Tags útiles

No utilices tags genéricos como:

```text
UPDATE
PROCESO
PRUEBA
```

Utiliza información que permita localizar el origen:

```sql
ALTER SESSION SET QUERY_TAG =
    'APP=CLASIFICACION;PROCESO=ASIGNACION_RUTAS;VERSION=2';
```

Esto permite filtrar Query History por:

- Aplicación.
- Job.
- Pipeline.
- Versión.
- Equipo responsable.

### 31.5 Reintentos controlados

Un timeout o un deadlock pueden ser errores transitorios.

La aplicación puede reintentar, pero debe:

- Aplicar un número máximo de intentos.
- Introducir una espera progresiva.
- Registrar cada intento.
- Evitar ejecutar dos veces una operación ya confirmada.
- Distinguir errores transitorios de errores permanentes.

### 31.6 Operaciones idempotentes

Una operación idempotente puede repetirse sin duplicar el efecto.

Es preferible registrar:

```text
ID_OPERACION
ID_LOTE
ESTADO
```

y comprobar si el lote ya fue aplicado antes de reintentarlo.

### 31.7 `TRANSACTION_ABORT_ON_ERROR`

Con:

```sql
ALTER SESSION SET TRANSACTION_ABORT_ON_ERROR = TRUE;
```

un error de sentencia puede provocar el aborto de la transacción.

Puede reducir el riesgo de dejar una transacción parcialmente activa, pero no sustituye:

- El control de errores.
- Los `ROLLBACK` explícitos.
- El orden consistente.
- El diseño idempotente.

La aplicación debe conocer qué comportamiento espera.

### 31.8 Abortar solo después de diagnosticar

`SYSTEM$ABORT_TRANSACTION` es una herramienta de recuperación, no una política normal de concurrencia.

Antes de utilizarla debes revisar:

- Usuario y sesión.
- Hora de inicio.
- Sentencias ejecutadas en la transacción.
- Objeto bloqueado.
- Impacto de perder los cambios pendientes.
- Responsable del proceso.

---

# Parte E - Análisis e informe

## 32. Consulta inmediata de operaciones bloqueadas

Durante o inmediatamente después del ejercicio:

```sql
SELECT
    QUERY_ID,
    SESSION_ID,
    QUERY_TAG,
    EXECUTION_STATUS,
    TRANSACTION_ID,
    TOTAL_ELAPSED_TIME,
    EXECUTION_TIME,
    TRANSACTION_BLOCKED_TIME,
    START_TIME,
    END_TIME,
    ERROR_MESSAGE,
    QUERY_TEXT
FROM TABLE(
    DB_CURSO.INFORMATION_SCHEMA.QUERY_HISTORY(
        END_TIME_RANGE_START => DATEADD(
            'HOUR',
            -1,
            CURRENT_TIMESTAMP()
        ),
        RESULT_LIMIT => 1000
    )
)
WHERE QUERY_TAG LIKE 'M3_E3_%'
ORDER BY START_TIME;
```

### Métricas principales

#### `TOTAL_ELAPSED_TIME`

Tiempo total transcurrido para la consulta.

Puede incluir más elementos que la espera por bloqueos.

#### `TRANSACTION_BLOCKED_TIME`

Tiempo en milisegundos durante el que la consulta estuvo bloqueada por un DML concurrente.

Permite diferenciar:

```text
consulta lenta por ejecución
consulta lenta por espera transaccional
```

#### `EXECUTION_STATUS`

Puede mostrar estados como:

```text
RUNNING
BLOCKED
SUCCESS
FAILED_WITH_ERROR
```

#### `TRANSACTION_ID`

Permite agrupar las sentencias que pertenecen a la misma transacción.

---

## 33. Análisis histórico opcional

La siguiente vista no es adecuada para comprobar el incidente inmediatamente porque `ACCOUNT_USAGE` tiene latencia.

Horas después, un rol con permisos sobre la base `SNOWFLAKE` puede ejecutar:

```sql
SELECT
    REQUESTED_AT,
    ACQUIRED_AT,
    QUERY_ID,
    TRANSACTION_ID,
    DATABASE_NAME,
    SCHEMA_NAME,
    OBJECT_NAME,
    LOCK_TYPE,
    BLOCKER_QUERIES
FROM SNOWFLAKE.ACCOUNT_USAGE.LOCK_WAIT_HISTORY
WHERE REQUESTED_AT >= DATEADD(
    'DAY',
    -1,
    CURRENT_TIMESTAMP()
)
ORDER BY REQUESTED_AT DESC;
```

`BLOCKER_QUERIES` es un valor `VARIANT` que contiene información sobre las transacciones bloqueadoras.

Para investigar una transacción bloqueadora concreta:

```sql
SELECT
    QUERY_ID,
    TRANSACTION_ID,
    SESSION_ID,
    USER_NAME,
    QUERY_TAG,
    EXECUTION_STATUS,
    START_TIME,
    END_TIME,
    TRANSACTION_BLOCKED_TIME,
    ERROR_MESSAGE,
    QUERY_TEXT
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE TRANSACTION_ID = <TRANSACTION_ID>
ORDER BY START_TIME;
```

Sustituye el placeholder por el Transaction ID real.

### Uso recomendado

```text
SHOW LOCKS + SHOW TRANSACTIONS
    Diagnóstico en directo

INFORMATION_SCHEMA.QUERY_HISTORY
    Historial inmediato del ejercicio

ACCOUNT_USAGE.LOCK_WAIT_HISTORY
    Postmortem, tendencias y análisis histórico
```

---

## 34. Ejemplo de informe de incidente

| Campo | Bloqueo simple | Espera circular / deadlock |
|---|---|---|
| Consulta afectada | `UPDATE` de B sobre el centro 1 | Segundo `UPDATE` de B y segundo `UPDATE` de A |
| Query Tag | `M3_E3_B_BLOQUEADA` | `M3_E3_DEADLOCK_A/B` |
| Transacción bloqueada | Transaction ID de B | A espera RUTAS; B espera CENTROS |
| Transacción bloqueadora | Transaction ID de A | Ambas forman el ciclo |
| Recurso | `M3_CENTROS_POSTALES` | `M3_CENTROS_POSTALES` y `M3_RUTAS_POSTALES` |
| Síntoma | B permanece en estado `BLOCKED` | Dos transacciones se bloquean mutuamente; el error puede ser aborto manual, deadlock automático o timeout |
| Causa raíz | A dejó una transacción sin cerrar | Los procesos adquieren recursos en distinto orden |
| Recuperación | Abortar la transacción A | Abortar B desde C y ejecutar `COMMIT` en A |
| Resultado | Capacidad final 950 | Centro 990 y ruta 220 |
| Prevención | Cerrar transacciones y controlar timeout | Orden consistente `CENTROS → RUTAS` |

---

# Parte F - Limpieza

## 35. Cerrar cualquier transacción pendiente

En A:

```sql
SELECT CURRENT_TRANSACTION() AS TRANSACCION_ACTIVA_A;
```

Si devuelve un valor, ejecuta:

```sql
ROLLBACK;
```

En B:

```sql
SELECT CURRENT_TRANSACTION() AS TRANSACCION_ACTIVA_B;
```

Si devuelve un valor, ejecuta:

```sql
ROLLBACK;
```

Desde C:

```sql
SHOW TRANSACTIONS;
SHOW LOCKS;
```

No continúes hasta que no queden transacciones del laboratorio.

---

## 36. Restaurar parámetros

### Sesión A

```sql
ALTER SESSION SET USE_CACHED_RESULT = TRUE;
ALTER SESSION UNSET LOCK_TIMEOUT;
ALTER SESSION UNSET TRANSACTION_ABORT_ON_ERROR;
ALTER SESSION UNSET QUERY_TAG;
```

### Sesión B

```sql
ALTER SESSION SET USE_CACHED_RESULT = TRUE;
ALTER SESSION UNSET LOCK_TIMEOUT;
ALTER SESSION UNSET TRANSACTION_ABORT_ON_ERROR;
ALTER SESSION UNSET QUERY_TAG;
```

### Sesión C

```sql
ALTER SESSION SET USE_CACHED_RESULT = TRUE;
ALTER SESSION UNSET QUERY_TAG;
```

`UNSET` elimina el valor establecido en la sesión y vuelve a aplicar el valor heredado.

---

## 37. Eliminar los objetos

Desde A, B o C:

```sql
USE ROLE SYSADMIN;
USE DATABASE DB_CURSO;
USE SCHEMA ARQUITECTURA;

DROP TABLE IF EXISTS DB_CURSO.ARQUITECTURA.M3_RUTAS_POSTALES;
DROP TABLE IF EXISTS DB_CURSO.ARQUITECTURA.M3_CENTROS_POSTALES;
```

---

## 38. Suspender el warehouse

```sql
ALTER WAREHOUSE WH_M3_ANALITICA SUSPEND;

SHOW WAREHOUSES LIKE 'WH_M3_ANALITICA';
```

El estado final debe ser:

```text
SUSPENDED
```

---

# Respuestas a las preguntas de reflexión

## 1. ¿Por qué cancelar únicamente la consulta que espera no elimina necesariamente la causa del bloqueo?

Porque la consulta que espera no mantiene el recurso que originó el incidente.

La transacción bloqueadora puede seguir abierta y volver a bloquear otras operaciones.

---

## 2. ¿Qué diferencia existe entre una consulta bloqueada y una transacción bloqueadora?

La consulta bloqueada intenta adquirir un recurso y no puede continuar.

La transacción bloqueadora ya adquirió ese recurso y todavía no lo ha liberado mediante `COMMIT`, `ROLLBACK` o aborto.

---

## 3. ¿Por qué un deadlock requiere una dependencia circular y no solo una espera?

Una espera normal puede resolverse cuando la transacción que mantiene el recurso continúa y lo libera.

En un deadlock, cada participante espera un recurso que mantiene otro participante del ciclo. Ninguno puede avanzar por sí solo.

---

## 4. ¿Por qué no debe basarse un procedimiento operativo únicamente en esperar a que Snowflake detecte automáticamente el deadlock?

Porque Snowflake indica que la detección puede tardar y no publica un tiempo máximo. Un `LOCK_TIMEOUT` corto puede vencer antes.

El procedimiento debe identificar el ciclo mediante los Transaction ID y disponer de una política para seleccionar y abortar una víctima.

---

## 5. ¿Qué riesgo existe al abortar una transacción sin revisar primero sus sentencias anteriores?

Se perderán todos los cambios no confirmados de la transacción, no únicamente la sentencia que parece estar causando el bloqueo.

El impacto puede afectar a varias tablas o pasos de un proceso.

---

## 6. ¿Por qué un orden consistente puede evitar deadlocks aunque no elimine todas las esperas?

Dos procesos todavía pueden competir por el mismo primer recurso.

Sin embargo, el segundo proceso espera antes de adquirir otros recursos que puedan crear un ciclo.

---

## 7. ¿Qué aporta `TRANSACTION_BLOCKED_TIME`?

Mide específicamente el tiempo pasado esperando por un DML concurrente.

`TOTAL_ELAPSED_TIME` puede incluir compilación, ejecución, aprovisionamiento y otras esperas.

---

## 8. ¿Por qué pueden seguir apareciendo bloqueos `HOLDING` después de un timeout de sentencia?

Porque el timeout aborta la sentencia que estaba esperando, pero una transacción explícita puede continuar activa. Los cambios realizados por sentencias anteriores siguen pendientes y sus bloqueos se mantienen hasta `COMMIT`, `ROLLBACK` o aborto de la transacción.

---

## 9. ¿Por qué `ACCOUNT_USAGE` es más apropiado para análisis histórico?

Sus vistas ofrecen retención y correlación a escala de cuenta, pero presentan latencia.

Para una incidencia en curso son más adecuados `SHOW LOCKS`, `SHOW TRANSACTIONS` e `INFORMATION_SCHEMA.QUERY_HISTORY`.

---

# Guion rápido de coordinación

| Paso | Sesión A | Sesión B | Sesión C | Resultado |
|---:|---|---|---|---|
| 1 | Crear tablas | Preparar contexto | Preparar contexto | Datos listos |
| 2 | `BEGIN` + actualizar centro | — | — | A mantiene CENTROS |
| 3 | Mantener abierta | Actualizar mismo centro | — | B queda bloqueada |
| 4 | — | Mantener esperando | Diagnosticar y abortar A | Centro termina en 950 |
| 5 | `BEGIN` + actualizar CENTROS | `BEGIN` + actualizar RUTAS | — | Cada sesión mantiene un recurso |
| 6 | Intentar actualizar RUTAS | — | — | A espera a B |
| 7 | Mantener esperando | Intentar actualizar CENTROS | — | Se forma A → B → A |
| 8 | Sigue esperando | Sigue esperando | `SHOW LOCKS`, `SHOW TRANSACTIONS`, Query History | Ciclo demostrado |
| 9 | El `UPDATE` continúa | Transacción abortada | Abortar B | B libera RUTAS |
| 10 | `COMMIT` | — | Verificar | Centro 990, ruta 220 |
| 11 | Orden CENTROS → RUTAS | Orden CENTROS → RUTAS | Observar | Espera sin ciclo |
| 12 | `COMMIT` | `COMMIT` | Verificar | Centro 970, ruta 230 |
| 13 | Restaurar parámetros | Restaurar parámetros | Eliminar tablas y suspender | Entorno limpio |

---

# Resolución de problemas

## `SHOW LOCKS` no devuelve filas

Comprueba:

1. A ejecutó `BEGIN`.
2. A ejecutó el primer `UPDATE`.
3. A no ejecutó `COMMIT` ni `ROLLBACK`.
4. B está ejecutando realmente el `UPDATE`.
5. Las dos sesiones modifican `ID_CENTRO = 1`.
6. Las sesiones utilizan el mismo objeto completamente cualificado.
7. Has esperado unos segundos antes de consultar.

---

## El `UPDATE` de B termina inmediatamente

Las causas más habituales son:

- A ya confirmó o revirtió.
- A y B no son sesiones independientes.
- Se modificaron objetos diferentes.
- No se ejecutó el `BEGIN` de A.
- El primer `UPDATE` de A no afectó a ninguna fila.

Comprueba:

```sql
SELECT CURRENT_SESSION();
SELECT CURRENT_TRANSACTION();
```

---

## No aparece un error automático de deadlock

No es un fallo del ejercicio. Snowflake documenta que la detección puede tardar y `LOCK_TIMEOUT` puede actuar antes.

Verifica el orden exacto:

```text
1. A BEGIN + UPDATE CENTROS
2. B BEGIN + UPDATE RUTAS
3. A UPDATE RUTAS y queda esperando
4. B UPDATE CENTROS y queda esperando
```

Después comprueba en C que existen estas cuatro filas lógicas:

```text
CENTROS: A HOLDING / B WAITING
RUTAS:   B HOLDING / A WAITING
```

La existencia del ciclo en los mismos dos Transaction ID demuestra el deadlock. No es necesario esperar un mensaje concreto.

---

## Después del timeout solo quedan dos filas `HOLDING`

Este resultado significa que los dos segundos `UPDATE` dejaron de esperar, pero las transacciones explícitas originales siguen abiertas:

```text
A conserva el bloqueo de CENTROS
B conserva el bloqueo de RUTAS
```

Con `TRANSACTION_ABORT_ON_ERROR = FALSE`, el error de sentencia no revierte automáticamente todos los cambios anteriores de la transacción.

Recupera el entorno con `ROLLBACK` en A y B o abortando sus Transaction ID desde C antes de repetir el incidente.

---

## A continúa esperando después de un error automático en B

La sentencia víctima de B puede haber fallado sin cerrar toda la transacción. Su primer `UPDATE` sigue pendiente y puede continuar manteniendo RUTAS.

Ejecuta en B:

```sql
ROLLBACK;
```

O aborta su Transaction ID desde C.

---

## `SYSTEM$ABORT_TRANSACTION` devuelve un error de permisos

Comprueba que:

- C utiliza el mismo usuario que inició A.
- Has copiado el Transaction ID de la fila `HOLDING`.
- La transacción todavía está activa.
- No has copiado el Query ID en lugar del Transaction ID.

En un entorno con distintos usuarios se necesita un administrador de cuenta para abortar una transacción ajena.

---

# Referencias oficiales

- [Transactions](https://docs.snowflake.com/en/sql-reference/transactions)
- [SHOW LOCKS](https://docs.snowflake.com/en/sql-reference/sql/show-locks)
- [SHOW TRANSACTIONS](https://docs.snowflake.com/en/sql-reference/sql/show-transactions)
- [SYSTEM$ABORT_TRANSACTION](https://docs.snowflake.com/en/sql-reference/functions/system_abort_transaction)
- [QUERY_HISTORY functions](https://docs.snowflake.com/en/sql-reference/functions/query_history)
- [LOCK_WAIT_HISTORY](https://docs.snowflake.com/en/sql-reference/account-usage/lock_wait_history)
- [Snowflake parameters: LOCK_TIMEOUT](https://docs.snowflake.com/en/sql-reference/parameters)

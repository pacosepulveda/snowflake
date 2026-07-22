# Módulo 3 - Ejercicio 4

## Diagnóstico, resolución y prevención de bloqueos y deadlocks

**Modalidad:** individual, coordinando tres sesiones de Snowflake  
**Herramientas:** Snowsight y SQL  
**Cuenta:** Snowflake Trial, edición Enterprise  

---

## Contexto

El equipo de operaciones de **Red Postal Iberia** mantiene dos procesos que se ejecutan durante las ventanas de clasificación:

- Un proceso actualiza la capacidad disponible de los centros postales.
- Otro proceso asigna envíos a las rutas de reparto.

Durante las horas de mayor actividad se han detectado operaciones que permanecen ejecutándose durante demasiado tiempo. En algunos casos, una consulta termina con un error; en otros, continúa esperando sin que el operador pueda determinar fácilmente qué sesión está provocando el problema.

El equipo necesita un procedimiento práctico para responder a estas preguntas:

> «¿Qué consulta está bloqueada? ¿Qué transacción mantiene el bloqueo? ¿Sobre qué recurso? ¿Cómo podemos resolver el incidente sin actuar a ciegas?»

También se sospecha que dos procesos actualizan los mismos recursos en distinto orden, lo que podría generar una dependencia circular:

```text
PROCESO A                          PROCESO B
mantiene CENTROS                   mantiene RUTAS
espera RUTAS                       espera CENTROS

                 DEADLOCK
```

Tu misión consiste en reproducir dos incidentes controlados:

1. Un bloqueo entre escritores.
2. Una espera circular entre dos transacciones explícitas, es decir, un deadlock.

Después deberás diagnosticar ambos incidentes, seleccionar de forma razonada qué transacción debe abortarse y validar una modificación del diseño que evite que la dependencia circular vuelva a producirse. El ejercicio no dependerá de que el detector automático de Snowflake actúe antes que `LOCK_TIMEOUT`.

---

## Objetivos de aprendizaje

Al completar el ejercicio deberás ser capaz de:

1. Crear y coordinar transacciones explícitas desde varias sesiones.
2. Provocar de forma controlada un bloqueo entre dos operaciones DML.
3. Diferenciar una consulta bloqueada de la transacción que mantiene el bloqueo.
4. Utilizar `SHOW TRANSACTIONS` para localizar transacciones activas.
5. Utilizar `SHOW LOCKS` para identificar recursos, estados `HOLDING` y `WAITING`.
6. Correlacionar bloqueos con Query History mediante Query ID, Transaction ID, Session ID y Query Tag.
7. Interpretar `EXECUTION_STATUS` y `TRANSACTION_BLOCKED_TIME`.
8. Resolver un bloqueo abortando de forma controlada la transacción bloqueadora.
9. Reproducir una espera circular mediante dos transacciones que adquieren recursos en distinto orden.
10. Construir e interpretar el grafo de espera a partir de las filas `HOLDING` y `WAITING`.
11. Distinguir entre detección automática, timeout de sentencia y resolución manual del incidente.
12. Seleccionar y abortar de forma controlada una transacción víctima.
13. Recuperar el sistema y confirmar únicamente la transacción que debe conservarse.
14. Evitar dependencias circulares aplicando un orden consistente de acceso a los recursos.
15. Aplicar medidas preventivas relacionadas con duración de las transacciones, `LOCK_TIMEOUT` y `QUERY_TAG`.
16. Dejar el entorno sin transacciones ni objetos temporales al finalizar.

---

## Prerrequisitos

Debes disponer de:

```text
DB_CURSO.ARQUITECTURA
WH_M3_ANALITICA
```

Utiliza un usuario que pueda trabajar con el rol `SYSADMIN` y tenga permisos para:

- Usar `WH_M3_ANALITICA`.
- Crear y eliminar tablas en `DB_CURSO.ARQUITECTURA`.
- Consultar su propio historial de consultas.
- Ejecutar `SYSTEM$ABORT_TRANSACTION` sobre una transacción iniciada por ese mismo usuario.

El ejercicio creará temporalmente:

```text
DB_CURSO.ARQUITECTURA.M3_CENTROS_POSTALES
DB_CURSO.ARQUITECTURA.M3_RUTAS_POSTALES
```

> Las tres sesiones deben estar abiertas con el mismo usuario. De esta forma podrás observar y administrar desde una sesión las transacciones iniciadas por las otras.

---

# Parte A - Preparación del entorno

## 1. Crear tres SQL Files

Crea y mantén abiertos simultáneamente los siguientes SQL Files:

```text
M3_E3_SESION_A
M3_E3_SESION_B
M3_E3_DIAGNOSTICO
```

Cada SQL File debe utilizar una sesión independiente.

Comprueba que los tres identificadores devueltos por `CURRENT_SESSION()` son diferentes.

No ejecutes las partes de concurrencia como un único script. Tendrás que alternar manualmente entre las sesiones.

---

## 2. Establecer el contexto

En las tres sesiones configura explícitamente:

```text
Rol:        SYSADMIN
Warehouse:  WH_M3_ANALITICA
Base:       DB_CURSO
Esquema:    ARQUITECTURA
```

En las sesiones A y B:

- Desactiva la reutilización de resultados almacenados.
- Configura `LOCK_TIMEOUT` con un valor suficiente para diagnosticar el incidente, pero muy inferior al valor predeterminado.
- Configura `TRANSACTION_ABORT_ON_ERROR` para que un error de sentencia no cierre automáticamente toda la transacción.

Asigna un Query Tag inicial diferente a cada sesión.

Comprueba en las tres sesiones:

- Usuario.
- Rol.
- Warehouse.
- Base de datos.
- Esquema.
- Session ID.

---

## 3. Crear los datos del laboratorio

Desde la sesión A crea dos tablas transitorias.

### Tabla de centros

`M3_CENTROS_POSTALES` debe incluir:

- Identificador del centro.
- Nombre del centro.
- Capacidad diaria.
- Capacidad disponible.
- Fecha y hora de actualización.

Crea al menos tres centros. El centro con `ID_CENTRO = 1` debe comenzar con:

```text
CAPACIDAD_DIARIA     = 1000
CAPACIDAD_DISPONIBLE = 1000
```

### Tabla de rutas

`M3_RUTAS_POSTALES` debe incluir:

- Identificador de la ruta.
- Centro al que pertenece.
- Zona.
- Número de envíos asignados.
- Estado.
- Fecha y hora de actualización.

Crea al menos tres rutas. La ruta con `ID_RUTA = 101` debe comenzar con:

```text
ID_CENTRO        = 1
ENVIOS_ASIGNADOS = 200
ESTADO            = PLANIFICADA
```

Comprueba los datos iniciales antes de continuar.

---

# Parte B - Incidente 1: bloqueo entre escritores

## 4. Sesión A: mantener una transacción abierta

En la sesión A:

1. Asigna el Query Tag `M3_E3_A_BLOQUEADOR`.
2. Inicia una transacción explícita.
3. Reduce en 200 unidades la capacidad disponible del centro 1.
4. Actualiza su marca de tiempo.
5. Consulta el centro desde la propia sesión.
6. Recupera el identificador de la transacción actual.
7. No ejecutes todavía `COMMIT` ni `ROLLBACK`.

La sesión A debe observar temporalmente:

```text
CAPACIDAD_DISPONIBLE = 800
```

---

## 5. Sesión B: ejecutar una operación competidora

En la sesión B:

1. Asigna el Query Tag `M3_E3_B_BLOQUEADA`.
2. Intenta reducir en 50 unidades la capacidad disponible del mismo centro.
3. Actualiza su marca de tiempo.
4. Ejecuta únicamente el `UPDATE`.

La sentencia debe permanecer esperando mientras la transacción A mantenga el recurso.

No canceles todavía la consulta y no cierres ninguna sesión.

---

## 6. Sesión C: diagnosticar el bloqueo en tiempo real

Desde `M3_E3_DIAGNOSTICO`:

1. Ejecuta `SHOW TRANSACTIONS`.
2. Conserva y analiza su resultado mediante `RESULT_SCAN`.
3. Ejecuta `SHOW LOCKS`.
4. Conserva y analiza su resultado mediante `RESULT_SCAN`.
5. Consulta el historial reciente mediante una función `QUERY_HISTORY` de `INFORMATION_SCHEMA`.
6. Filtra las consultas mediante los Query Tags del ejercicio.

Identifica:

- Query ID de la operación bloqueada.
- Transaction ID de la operación bloqueada.
- Transaction ID de la transacción bloqueadora.
- Session ID de ambas transacciones.
- Recurso afectado.
- Estado `HOLDING`.
- Estado `WAITING`.
- Tiempo que la consulta lleva bloqueada.
- Texto SQL de la operación que está esperando.

Completa este diagnóstico:

```text
CONSULTA BLOQUEADA:
TRANSACCIÓN BLOQUEADA:
SESIÓN BLOQUEADA:
TRANSACCIÓN BLOQUEADORA:
SESIÓN BLOQUEADORA:
RECURSO:
TIEMPO BLOQUEADO:
CAUSA:
```

---

## 7. Resolver el incidente

No abortes una transacción hasta haber identificado correctamente:

- Qué operación está esperando.
- Qué transacción mantiene el bloqueo.
- Qué cambios pendientes se perderían.

Desde la sesión C:

1. Copia el Transaction ID de la fila `HOLDING`.
2. Aborta esa transacción mediante `SYSTEM$ABORT_TRANSACTION`.
3. Observa qué ocurre con el `UPDATE` de la sesión B.
4. Comprueba el valor confirmado del centro 1.
5. Ejecuta de nuevo `SHOW TRANSACTIONS` y `SHOW LOCKS`.

El valor final esperado es:

```text
CAPACIDAD_DISPONIBLE = 950
```

Explica por qué no se confirmó la reducción de 200 unidades de A, pero sí la reducción de 50 unidades de B.

---

# Parte C - Incidente 2: espera circular y deadlock

## 8. Restaurar los valores de partida

Antes del segundo incidente:

- Restaura la capacidad disponible del centro 1 a 1000.
- Restaura los envíos asignados de la ruta 101 a 200.
- Confirma que no quedan transacciones abiertas.
- Confirma que `SHOW LOCKS` no devuelve bloqueos del laboratorio.
- Configura temporalmente `LOCK_TIMEOUT = 300` en las sesiones A y B.

El objetivo no es esperar cinco minutos. El valor se amplía únicamente para disponer de tiempo suficiente para construir y diagnosticar el ciclo antes de que una sentencia finalice por timeout.

---

## 9. Adquirir los recursos en distinto orden

### Sesión A

En la sesión A:

1. Asigna el Query Tag `M3_E3_DEADLOCK_A`.
2. Inicia una transacción explícita.
3. Reduce en 10 unidades la capacidad disponible del centro 1.
4. Anota el Transaction ID.
5. Mantén la transacción abierta.

### Sesión B

En la sesión B:

1. Asigna el Query Tag `M3_E3_DEADLOCK_B`.
2. Inicia una transacción explícita.
3. Aumenta en 10 los envíos asignados de la ruta 101.
4. Anota el Transaction ID.
5. Mantén la transacción abierta.

En este punto:

```text
A mantiene un recurso de M3_CENTROS_POSTALES
B mantiene un recurso de M3_RUTAS_POSTALES
```

---

## 10. Crear la dependencia circular

Ejecuta las siguientes acciones en el orden indicado.

### Primero, sesión A

Intenta aumentar en 20 los envíos asignados de la ruta 101.

La sentencia A debe quedar esperando porque B mantiene una modificación pendiente sobre esa ruta.

### Después, sesión B

Mientras A continúa esperando, intenta reducir en 20 unidades la capacidad disponible del centro 1.

Ahora se forma el ciclo:

```text
A mantiene CENTROS y espera RUTAS
B mantiene RUTAS y espera CENTROS
```

No esperes a que aparezca un error automático. Pasa inmediatamente a la sesión C.

---

## 11. Diagnosticar el ciclo antes del timeout

Desde la sesión C:

1. Ejecuta `SHOW LOCKS`.
2. Filtra los recursos `M3_CENTROS_POSTALES` y `M3_RUTAS_POSTALES` mediante `RESULT_SCAN`.
3. Ejecuta `SHOW TRANSACTIONS` y relaciona cada Transaction ID con su Session ID.
4. Consulta Query History para localizar los dos `UPDATE` que están esperando.
5. Comprueba que el Transaction ID de cada sentencia `WAITING` coincide con la transacción que ya mantiene el otro recurso.

Debes identificar cuatro relaciones:

```text
CENTROS: A HOLDING
CENTROS: B WAITING
RUTAS:   B HOLDING
RUTAS:   A WAITING
```

Completa este grafo:

```text
TRANSACCIÓN A:
  mantiene:
  espera:
  bloqueada por:

TRANSACCIÓN B:
  mantiene:
  espera:
  bloqueada por:

CICLO DETECTADO:
```

> Si los Transaction ID de las filas `WAITING` no coinciden con las transacciones originales de A y B, no existe un deadlock real: alguna sentencia se ha ejecutado desde una sesión diferente.

---

## 12. Seleccionar y abortar una víctima

No esperes a que `LOCK_TIMEOUT` o el detector automático decidan por ti.

Desde la sesión C:

1. Selecciona la transacción B como víctima del laboratorio.
2. Justifica la decisión teniendo en cuenta qué cambios pendientes perderá.
3. Aborta la transacción B mediante `SYSTEM$ABORT_TRANSACTION`.
4. Observa el error recibido por la sentencia que estaba esperando en B.
5. Comprueba si el segundo `UPDATE` de A puede continuar.

La transacción B debe perder su incremento pendiente de 10 envíos y liberar el recurso de rutas.

> Si Snowflake detecta automáticamente el deadlock antes de que ejecutes el aborto, la sentencia víctima puede fallar, pero su transacción puede continuar activa. En ese caso, ejecuta `ROLLBACK` en esa sesión o aborta su Transaction ID desde C antes de continuar.

---

## 13. Completar la recuperación

Para finalizar correctamente el incidente:

1. Espera a que el segundo `UPDATE` de A termine.
2. Ejecuta `COMMIT` en la sesión A.
3. Consulta los valores finales.
4. Ejecuta `SHOW TRANSACTIONS` y `SHOW LOCKS`.
5. Consulta Query History para revisar el tiempo bloqueado y el error de la transacción abortada.

Valores esperados:

```text
CENTRO 1
CAPACIDAD_DISPONIBLE = 990

RUTA 101
ENVIOS_ASIGNADOS = 220
```

Explica por qué el incremento de 10 envíos realizado inicialmente por B no aparece en el resultado final.

---

# Parte D - Prevención práctica

## 14. Aplicar un orden consistente

Restaura de nuevo:

```text
CAPACIDAD_DISPONIBLE = 1000
ENVIOS_ASIGNADOS     = 200
```

Modifica la secuencia de ambos procesos para que los dos adquieran los recursos en este orden:

```text
1. M3_CENTROS_POSTALES
2. M3_RUTAS_POSTALES
```

Valida el diseño con esta coordinación:

1. A inicia una transacción y actualiza el centro.
2. B inicia una transacción e intenta actualizar el mismo centro.
3. B queda temporalmente esperando.
4. A actualiza la ruta y ejecuta `COMMIT`.
5. La primera sentencia de B puede finalizar.
6. B actualiza la ruta y ejecuta `COMMIT`.

Comprueba que:

- Puede existir una espera temporal.
- No se forma una dependencia circular.
- No se produce un deadlock.
- Las dos transacciones pueden terminar correctamente.

Valores finales esperados:

```text
CAPACIDAD_DISPONIBLE = 970
ENVIOS_ASIGNADOS     = 230
```

---

## 15. Elaborar medidas preventivas

Propón al menos cuatro medidas para un entorno productivo.

Incluye obligatoriamente:

- Orden consistente de acceso a tablas o recursos.
- Transacciones cortas.
- Valor de `LOCK_TIMEOUT` adecuado para el tipo de proceso.
- Uso de `QUERY_TAG` para identificar aplicaciones, jobs o pipelines.

Valora también:

- Reintentos controlados en la aplicación.
- Operaciones idempotentes.
- Evitar esperas humanas dentro de una transacción.
- Supervisión de `TRANSACTION_BLOCKED_TIME`.
- Uso prudente de `SYSTEM$ABORT_TRANSACTION`.
- Comportamiento deseado de `TRANSACTION_ABORT_ON_ERROR`.

---

# Parte E - Informe y limpieza

## 16. Informe de incidente

Entrega un informe breve con este formato:

| Campo | Bloqueo simple | Espera circular / deadlock |
|---|---|---|
| Consulta afectada |  |  |
| Query Tag |  |  |
| Transaction ID bloqueada |  |  |
| Transaction ID bloqueadora |  |  |
| Recurso |  |  |
| Síntoma |  |  |
| Causa raíz |  |  |
| Acción de recuperación |  |  |
| Resultado |  |  |
| Medida preventiva principal |  |  |

---

## 17. Limpieza obligatoria

Al finalizar:

1. Comprueba que no queda ninguna transacción abierta en A ni en B.
2. Ejecuta `SHOW TRANSACTIONS` desde C.
3. Ejecuta `SHOW LOCKS` desde C.
4. Restaura los parámetros modificados en las sesiones A y B.
5. Elimina los Query Tags.
6. Elimina las dos tablas transitorias.
7. Suspende `WH_M3_ANALITICA`.
8. Comprueba el estado final del warehouse.

No finalices el ejercicio mientras aparezca una transacción del laboratorio en estado activo.

---

## Preguntas de reflexión

1. ¿Por qué cancelar únicamente la consulta que espera no elimina necesariamente la causa del bloqueo?
2. ¿Qué diferencia existe entre una consulta bloqueada y una transacción bloqueadora?
3. ¿Por qué un deadlock requiere una dependencia circular y no solo una espera?
4. ¿Por qué no debe basarse un procedimiento operativo únicamente en esperar a que Snowflake detecte automáticamente el deadlock?
5. ¿Qué riesgo existe al abortar una transacción sin revisar primero sus sentencias anteriores?
6. ¿Por qué un orden consistente puede evitar deadlocks aunque no elimine todas las esperas?
7. ¿Qué información aporta `TRANSACTION_BLOCKED_TIME` que no puede obtenerse observando solo la duración total?
8. ¿Por qué, después de un timeout de sentencia, pueden seguir apareciendo bloqueos `HOLDING` asociados a la transacción?
9. ¿Por qué las vistas de `ACCOUNT_USAGE` son más apropiadas para un análisis histórico que para diagnosticar este laboratorio en tiempo real?

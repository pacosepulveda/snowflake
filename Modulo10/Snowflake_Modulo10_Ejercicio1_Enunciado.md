# Módulo 10 · Ejercicio 1

## Recuperación de incidentes con Time Travel y UNDROP

> **Entorno:** cuenta trial actual de Snowflake

---

## Contexto

RetailNova mantiene una tabla permanente con el estado de sus pedidos. Durante una operación de mantenimiento se producen tres incidentes:

1. Un `UPDATE` masivo modifica importes y estados incorrectamente.
2. Un `DELETE` elimina varios pedidos pendientes.
3. La tabla se elimina y otra tabla ocupa su nombre antes de recuperarla.

El objetivo es recuperar la información utilizando las capacidades nativas de Snowflake, sin restaurar un backup externo.

---

## Objetivos

Al finalizar el ejercicio deberás ser capaz de:

- Configurar y comprobar la retención de **Time Travel**.
- Consultar datos históricos mediante `AT` y `BEFORE`.
- Utilizar referencias `TIMESTAMP`, `STATEMENT` y `OFFSET`.
- Capturar el Query ID de una operación.
- Crear un clone de un estado histórico.
- Restaurar datos con `INSERT OVERWRITE` sin reemplazar la tabla.
- Recuperar únicamente las filas eliminadas.
- Recuperar una tabla con `UNDROP`.
- Resolver un conflicto de nombre antes de ejecutar `UNDROP`.
- Diferenciar tablas permanentes, tablas transitorias, Time Travel y Fail-safe.

---

## Objetos utilizados

| Objeto | Nombre |
|---|---|
| Base de datos | `DB_M10_RECOVERY` |
| Esquema operativo | `OPERACIONES` |
| Esquema de recuperación | `RECOVERY` |
| Warehouse | `WH_M10_RECOVERY` |
| Tabla permanente | `PEDIDOS_OPERATIVOS` |
| Tabla transitoria | `EVENTOS_REPROCESABLES` |
| Snapshot histórico | `PEDIDOS_PRE_UPDATE` |

> El laboratorio utiliza `DATA_RETENTION_TIME_IN_DAYS = 1` para funcionar tanto en cuentas Standard como Enterprise.

---

# Parte 1. Preparar el laboratorio

## Tarea 1. Crear los objetos

Crea:

- Un warehouse `XSMALL` con `AUTO_SUSPEND = 60`.
- La base de datos `DB_M10_RECOVERY`.
- Los esquemas `OPERACIONES` y `RECOVERY`.
- Una tabla permanente `PEDIDOS_OPERATIVOS`.
- Una tabla transitoria `EVENTOS_REPROCESABLES`.

Configura un día de retención y utiliza el rol `SYSADMIN`.

La tabla de pedidos debe contener estos datos:

| ID | Fecha | Importe | Estado |
|---:|---|---:|---|
| 10001 | 2026-07-01 | 120.00 | COMPLETADA |
| 10002 | 2026-07-01 | 250.00 | PENDIENTE |
| 10003 | 2026-07-02 | 80.00 | COMPLETADA |
| 10004 | 2026-07-02 | 310.00 | COMPLETADA |
| 10005 | 2026-07-03 | 150.00 | CANCELADA |
| 10006 | 2026-07-03 | 95.00 | PENDIENTE |
| 10007 | 2026-07-04 | 180.00 | COMPLETADA |
| 10008 | 2026-07-04 | 220.00 | PENDIENTE |

Estado inicial esperado:

```text
8 pedidos
importe total = 1405.00
4 COMPLETADA
3 PENDIENTE
1 CANCELADA
```

---

## Tarea 2. Comprobar la protección

Utiliza `SHOW TABLES` para comprobar:

- El tipo de cada tabla.
- El periodo de retención.
- El número de filas.
- El propietario.

Completa:

| Tabla | Tipo | Time Travel | Fail-safe |
|---|---|---:|---:|
| `PEDIDOS_OPERATIVOS` |  |  |  |
| `EVENTOS_REPROCESABLES` |  |  |  |

---

# Parte 2. Recuperar un UPDATE incorrecto

## Tarea 3. Registrar un punto de recuperación

1. Guarda `CURRENT_TIMESTAMP()` en una variable de sesión.
2. Espera seis segundos con `SYSTEM$WAIT`.
3. Ejecuta un `UPDATE` sobre los pedidos desde el 3 de julio:

```sql
WHERE fecha_pedido >= '2026-07-03'
```

El error debe:

- Establecer `importe = 0`.
- Establecer `estado = 'CANCELADA'`.
- Actualizar `actualizado_en`.

Guarda inmediatamente el Query ID mediante `LAST_QUERY_ID()`.

Estado dañado esperado:

```text
8 pedidos
importe total = 760.00
```

---

## Tarea 4. Consultar el pasado

Consulta el estado anterior mediante:

1. `AT (TIMESTAMP => ...)`.
2. `BEFORE (STATEMENT => ...)`.
3. `AT (STATEMENT => ...)`.
4. `AT (OFFSET => -5)`.

Responde:

- ¿Qué diferencia observas entre `AT` y `BEFORE`?
- ¿Por qué `BEFORE (STATEMENT)` es la referencia más segura para este incidente?
- ¿Por qué no debes depender de un resultado exacto con `OFFSET`?

---

## Tarea 5. Restaurar la tabla

1. Crea una tabla transitoria `RECOVERY.PEDIDOS_PRE_UPDATE` mediante un clone del estado anterior al `UPDATE`.
2. Comprueba que contiene ocho filas y un total de `1405.00`.
3. Restaura `PEDIDOS_OPERATIVOS` con `INSERT OVERWRITE`.
4. No utilices `CREATE OR REPLACE TABLE`.
5. Comprueba que la tabla vuelve al estado inicial.

---

# Parte 3. Recuperar filas eliminadas

## Tarea 6. Simular y recuperar un DELETE

1. Elimina los pedidos cuyo estado sea `PENDIENTE`.
2. Guarda el Query ID del `DELETE`.
3. Comprueba que quedan:

```text
5 pedidos
importe total = 840.00
```

4. Utiliza `BEFORE (STATEMENT => query_id)` para insertar únicamente las filas que ya no existen.
5. Comprueba que no se han creado duplicados.

Resultado final esperado:

```text
8 pedidos
importe total = 1405.00
3 pedidos PENDIENTE
```

---

# Parte 4. Recuperar una tabla eliminada

## Tarea 7. Resolver un conflicto de nombre

Realiza esta secuencia:

1. Elimina `PEDIDOS_OPERATIVOS`.
2. Crea otra tabla con el mismo nombre y una única fila ficticia.
3. Consulta `SHOW TABLES HISTORY`.
4. Intenta ejecutar `UNDROP TABLE` y observa el error.
5. Renombra la tabla nueva como `PEDIDOS_OPERATIVOS_REEMPLAZO`.
6. Ejecuta de nuevo `UNDROP TABLE`.
7. Comprueba:
   - La tabla original contiene ocho filas.
   - La tabla de reemplazo contiene una fila.
8. Elimina la tabla de reemplazo.

---

# Parte 5. Interpretación

## Tarea 8. Time Travel y Fail-safe

Completa:

| Situación | Mecanismo recomendado |
|---|---|
| `UPDATE` conocido |  |
| `DELETE` parcial |  |
| `DROP TABLE` |  |
| Datos fuera de Time Travel |  |
| Pérdida completa de la cuenta |  |

Responde brevemente:

1. ¿Qué tabla dispone de Fail-safe?
2. ¿Por qué la tabla transitoria no debería contener información crítica no reproducible?
3. ¿Quién puede intentar una recuperación desde Fail-safe?
4. ¿Por qué Fail-safe no sustituye a un backup o a una estrategia de disaster recovery?
5. ¿Qué efecto tiene aumentar la retención sobre el almacenamiento?

---

# Ampliación opcional

## Recuperar un esquema y una base de datos

Repite el patrón `DROP` → `SHOW ... HISTORY` → `UNDROP` con:

```text
DB_M10_RECOVERY.LAB_SCHEMA_DROP
DB_M10_UNDROP_DEMO
```

Cada objeto debe contener una tabla hija para comprobar que también se recupera.

---

## Preguntas de reflexión

1. ¿Cuándo utilizarías `TIMESTAMP` en lugar de `STATEMENT`?
2. ¿Qué diferencia existe entre restaurar todas las filas y recuperar solo las ausentes?
3. ¿Qué riesgo introduce `CREATE OR REPLACE TABLE` durante una recuperación?
4. ¿Por qué conviene conservar Query ID, usuario, rol, Query Tag y número de filas afectadas?

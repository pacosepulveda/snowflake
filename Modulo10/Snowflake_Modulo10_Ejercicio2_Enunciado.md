# Módulo 10 · Ejercicio 2

## Entornos DEV y QA con Zero-Copy Cloning

> **Entorno:** cuenta trial actual de Snowflake

---

## Contexto

RetailNova necesita crear un entorno de desarrollo con datos similares a producción, probar una migración y volver rápidamente al estado anterior si algo falla.

El equipo utilizará **Zero-Copy Cloning** para:

1. Crear DEV desde PROD.
2. Comprobar que ambos entornos evolucionan de forma independiente.
3. Revisar vistas, streams, tasks y grants después del clone.
4. Crear un estado histórico para QA.
5. Recuperar DEV completo después de una migración fallida.

---

## Objetivos

Al finalizar el ejercicio deberás ser capaz de:

- Crear un clone de una base de datos.
- Explicar Zero-Copy y copy-on-write.
- Comprobar la independencia entre origen y clone.
- Identificar referencias locales y referencias fijadas a producción.
- Comprobar el comportamiento de tasks y streams clonados.
- Revisar los grants heredados y los grants del contenedor.
- Crear un clone histórico con Time Travel.
- Crear un snapshot previo a una migración.
- Recuperar una base completa mediante `RENAME` y un nuevo clone.
- Relacionar la divergencia con el coste de almacenamiento.

---

## Arquitectura

```text
DB_M10_PROD
    │
    ├── clone actual ─────────→ DB_M10_DEV
    │                              │
    │                              ├── cambios independientes
    │                              └── snapshot pre-migración
    │
    └── clone histórico ──────→ DB_M10_QA_HISTORICO
```

---

## Objetos

| Objeto | Nombre |
|---|---|
| Producción | `DB_M10_PROD` |
| Desarrollo | `DB_M10_DEV` |
| Snapshot | `DB_M10_DEV_PRE_MIGRACION` |
| Entorno fallido | `DB_M10_DEV_FALLIDA` |
| QA histórico | `DB_M10_QA_HISTORICO` |
| Warehouse | `WH_M10_CLONE` |
| Rol lector | `M10_PROD_READER` |

> Se utiliza un día de Time Travel para que el ejercicio funcione tanto en cuentas Standard como Enterprise.

---

# Parte 1. Preparar producción

## Tarea 1. Crear los objetos

Crea:

```text
DB_M10_PROD
├── CORE
│   ├── PEDIDOS
│   └── V_PEDIDOS_LOCAL
├── MARTS
│   └── V_PEDIDOS_PROD
└── OPS
    ├── PEDIDOS_STREAM
    ├── TASK_LOG
    └── TASK_AUDITAR_PEDIDOS
```

La tabla `CORE.PEDIDOS` contendrá inicialmente seis pedidos.

Después de crear el stream, inserta el pedido `20007`.

Estado esperado antes del clone:

```text
7 pedidos
importe total = 1080.00
```

---

## Tarea 2. Crear dos vistas

Crea:

### Vista local

```text
DB_M10_PROD.CORE.V_PEDIDOS_LOCAL
```

Debe estar en el mismo esquema que `PEDIDOS` y utilizar:

```sql
FROM PEDIDOS
```

### Vista fijada a producción

```text
DB_M10_PROD.MARTS.V_PEDIDOS_PROD
```

Debe utilizar:

```sql
FROM DB_M10_PROD.CORE.PEDIDOS
```

Ambas mostrarán inicialmente el mismo resultado.

---

## Tarea 3. Preparar stream, task y grants

1. Crea un stream sobre `CORE.PEDIDOS`.
2. Inserta el pedido `20007` para dejar un cambio pendiente.
3. Crea una task que escriba un resumen en `OPS.TASK_LOG`.
4. Reanuda la task antes de clonar.
5. Crea el rol `M10_PROD_READER` y concédele:
   - `USAGE` sobre la base.
   - `USAGE` sobre `CORE`.
   - `SELECT` sobre `CORE.PEDIDOS`.

No esperes a que la task se ejecute.

---

# Parte 2. Crear y revisar DEV

## Tarea 4. Clonar producción

Crea:

```sql
CREATE DATABASE DB_M10_DEV CLONE DB_M10_PROD;
```

Comprueba:

- Siete pedidos y `1080.00`.
- La task clonada está suspendida.
- El stream de PROD contiene el cambio pendiente.
- El stream de DEV no expone ese cambio anterior.
- El grant `SELECT` de la tabla se conserva.
- El grant `USAGE` de la base clonada debe concederse de nuevo.

Suspende después la task de producción.

---

## Tarea 5. Provocar divergencia

En DEV:

1. Cambia el pedido `20002` de `250.00` a `260.00`.
2. Inserta el pedido de prueba `29999` por `1.00`.

Resultado:

```text
DEV:  8 pedidos y 1091.00
PROD: 7 pedidos y 1080.00
```

Después:

1. Guarda un timestamp.
2. Inserta en PROD el pedido `20008` por `400.00`.

Resultado:

```text
PROD: 8 pedidos y 1480.00
DEV:  8 pedidos y 1091.00
```

Consulta en DEV:

```text
CORE.V_PEDIDOS_LOCAL
MARTS.V_PEDIDOS_PROD
```

Resultado esperado:

```text
V_PEDIDOS_LOCAL → 1091.00
V_PEDIDOS_PROD  → 1480.00
```

Explica por qué la segunda vista rompe el aislamiento del entorno.

---

# Parte 3. QA histórico y rollback

## Tarea 6. Crear QA histórico

Utiliza el timestamp guardado antes de insertar el pedido `20008`:

```text
DB_M10_QA_HISTORICO
```

Comprueba:

```text
QA histórico: 7 pedidos y 1080.00
PROD actual:   8 pedidos y 1480.00
```

Comprueba también si la task aparece en el clone histórico.

---

## Tarea 7. Crear un snapshot y simular una migración fallida

Crea:

```text
DB_M10_DEV_PRE_MIGRACION
```

como clone de DEV.

En `DB_M10_DEV`:

1. Añade la columna `importe_migrado`.
2. Multiplica por diez los importes de la región `SUR`.
3. Elimina `CORE.V_PEDIDOS_LOCAL`.

La validación debe detectar:

```text
importe total = 4286.00
vista local ausente
esquema distinto al esperado
```

---

## Tarea 8. Recuperar DEV completo

Realiza:

```text
DB_M10_DEV → DB_M10_DEV_FALLIDA
DB_M10_DEV_PRE_MIGRACION → nuevo clone DB_M10_DEV
```

Reasigna los grants del contenedor y comprueba:

```text
8 pedidos
importe total = 1091.00
V_PEDIDOS_LOCAL presente
importe_migrado ausente
task suspendida
```

Elimina después `DB_M10_DEV_FALLIDA`.

Explica qué ocurre con el backlog de un stream cuando la recuperación se realiza mediante otro clone.

---

# Parte 4. Interpretación

## Tarea 9. Completar el runbook

| Situación | Acción recomendada |
|---|---|
| Crear DEV desde PROD |  |
| Vista con referencia a PROD |  |
| Task clonada |  |
| Stream clonado |  |
| Grants del nuevo contenedor |  |
| Migración fallida |  |
| Reproducir un estado histórico |  |
| Clone antiguo |  |

Responde:

1. ¿Qué significa realmente Zero-Copy?
2. ¿Cuándo comienza DEV a utilizar almacenamiento propio?
3. ¿Por qué un clone no es un backup externo?
4. ¿Por qué no deben reanudarse tasks sin revisar su definición?
5. ¿Qué riesgo tienen las referencias completamente cualificadas?
6. ¿Por qué deben eliminarse los clones temporales antiguos?

---

# Ampliación opcional

## Analizar almacenamiento

Con `ACCOUNTADMIN`, consulta `TABLE_STORAGE_METRICS` para las tablas `PEDIDOS` de PROD, DEV y el snapshot.

Localiza:

- `ID`.
- `CLONE_GROUP_ID`.
- `ACTIVE_BYTES`.
- `TIME_TRAVEL_BYTES`.
- `FAILSAFE_BYTES`.
- `RETAINED_FOR_CLONE_BYTES`.

Explica por qué las métricas pueden tardar en reflejar los cambios.

---

## Preguntas de reflexión

1. ¿Qué diferencia existe entre un clone actual y un clone histórico?
2. ¿Qué objetos deben revisarse siempre después de clonar una base?
3. ¿Qué ventaja aporta un snapshot pre-migración frente a restaurar tablas individualmente?
4. ¿Cómo tratarías datos personales antes de entregar un clone a desarrollo?
5. ¿Por qué copy-on-write no significa almacenamiento gratuito para siempre?

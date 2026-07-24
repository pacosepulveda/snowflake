# Módulo 10 · Ejercicio 3

## Backup lógico, backup nativo y recuperación ante desastres

> **Entorno:** cuenta trial actual de Snowflake

---

## Contexto

RetailNova ya utiliza Time Travel y Zero-Copy Cloning, pero necesita una estrategia que cubra también:

- Restauración en otra base de datos.
- Conservación de copias no modificables.
- Portabilidad fuera de Snowflake.
- Pérdida de datos entre dos backups.
- Recuperación ante un fallo regional.

En este laboratorio crearás dos capas de protección:

```text
Backup lógico
    snapshot consistente
    → Parquet
    → manifest
    → restore lógico

Backup nativo
    backup set
    → backup manual
    → restore de la base
    → reparación de producción
```

La replicación y el failover se analizarán como ampliación de diseño.

---

## Objetivos

Al finalizar deberás ser capaz de:

- Diferenciar RPO y RTO.
- Crear un punto consistente para exportar varias tablas.
- Descargar datos a Parquet con Snappy.
- Crear un manifest con conteos, importes y checksum.
- Restaurar Parquet mediante `MATCH_BY_COLUMN_NAME`.
- Validar el restore con conteos, sumas, `HASH_AGG` y `MINUS`.
- Demostrar que un backup periódico tiene un RPO distinto de cero.
- Crear un backup set y un backup nativo manual.
- Restaurar una base de datos desde un backup nativo.
- Identificar objetos incluidos y excluidos.
- Reparar producción sin reemplazar la identidad de la tabla.
- Diferenciar backup, réplica y failover.
- Limpiar recursos que continúan reteniendo almacenamiento.

---

## Objetos

| Objeto | Nombre |
|---|---|
| Base fuente | `DB_M10_PROD` |
| Repositorio | `DB_M10_BACKUP_REPO` |
| Snapshot consistente | `DB_M10_BACKUP_SNAPSHOT` |
| Restore lógico | `DB_M10_LOGICAL_RESTORE` |
| Restore nativo | `DB_M10_NATIVE_RESTORE` |
| Stage lógico | `STG_LOGICAL_BACKUP` |
| Manifest | `BACKUP_MANIFEST` |
| Backup set | `BS_DB_M10_PROD` |
| Warehouse | `WH_M10_DR` |

> El laboratorio utiliza un día de Time Travel para funcionar tanto en cuentas Standard como Enterprise.

---

# Parte 1. Preparar la fuente

## Tarea 1. Crear producción

Crea:

```text
DB_M10_PROD
├── CORE
│   ├── CLIENTES
│   ├── PEDIDOS
│   └── V_PEDIDOS_RESUMEN
└── OPS
    ├── PEDIDOS_STREAM
    ├── TASK_LOG
    ├── TASK_AUDITAR_PEDIDOS
    └── STG_INTERNO_PRUEBA
```

Carga:

```text
3 clientes
6 pedidos
importe total = 1005.00
```

La columna técnica de `PEDIDOS` será:

```sql
actualizado_en TIMESTAMP_NTZ(3)
```

La task debe quedar suspendida.

---

# Parte 2. Backup y restore lógico

## Tarea 2. Crear un snapshot consistente

1. Guarda un timestamp.
2. Crea `DB_M10_BACKUP_SNAPSHOT` como clone histórico de `DB_M10_PROD`.
3. Comprueba que contiene tres clientes, seis pedidos y `1005.00`.

Explica por qué exportar las dos tablas desde el mismo snapshot evita que representen instantes distintos.

---

## Tarea 3. Descargar datos y crear el manifest

Crea en `DB_M10_BACKUP_REPO`:

```text
CATALOG.STG_LOGICAL_BACKUP
CATALOG.BACKUP_MANIFEST
NATIVE
```

Descarga desde el snapshot:

```text
logical_v1/clientes/
logical_v1/pedidos/
```

Utiliza:

- Parquet.
- Snappy.
- `HEADER = TRUE`.
- `SINGLE = TRUE`.
- `OVERWRITE = TRUE`.

Registra en el manifest:

- Tabla.
- Ruta.
- Número de filas.
- Importe total, cuando proceda.
- `HASH_AGG`.
- Timestamp del backup.

Exporta también el manifest a:

```text
logical_v1/manifest/
```

---

## Tarea 4. Restaurar y validar

Crea `DB_M10_LOGICAL_RESTORE` con DDL explícito.

Carga los Parquet con:

```sql
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
```

Comprueba:

```text
3 clientes
6 pedidos
1005.00
0 pedidos sin cliente
```

Valida el restore mediante:

- Conteo y suma.
- Checksum del manifest.
- `MINUS` en ambos sentidos.
- Integridad referencial.

Mide el tiempo aproximado de restauración y validación.

---

## Tarea 5. Demostrar el RPO

Después del backup lógico, inserta en producción:

```text
pedido 20007
importe 180.00
```

Resultado:

```text
Producción:      7 pedidos y 1185.00
Restore lógico:  6 pedidos y 1005.00
```

Explica:

- Qué dato se perdería si se restaurara ese backup.
- Por qué esto representa el RPO.
- Por qué el RPO no depende del tiempo que tarde el restore.

---

# Parte 3. Backup y restore nativo

## Tarea 6. Crear un backup nativo

Crea:

```text
DB_M10_BACKUP_REPO.NATIVE.BS_DB_M10_PROD
```

para la base `DB_M10_PROD`.

Añade un backup manual:

```sql
ALTER BACKUP SET ... ADD BACKUP;
```

Obtén y conserva el `backup_id`.

No utilices retention lock ni legal hold.

---

## Tarea 7. Simular el incidente

Después del backup, modifica todos los pedidos de la región `SUR`:

```text
importe = 0
estado = CANCELADA
```

Estado dañado esperado:

```text
7 pedidos
importe total = 840.00
```

---

## Tarea 8. Restaurar y reparar

Crea:

```text
DB_M10_NATIVE_RESTORE
```

desde el backup identificado por su UUID.

Comprueba:

```text
7 pedidos
importe total = 1185.00
```

Inspecciona:

| Objeto | Resultado esperado |
|---|---|
| Tablas | Incluidas |
| View | Incluida |
| Task | Incluida y suspendida |
| Stream | No incluido |
| Internal stage | No incluido |

Repara `DB_M10_PROD.CORE.PEDIDOS` mediante:

```sql
INSERT OVERWRITE
```

No reemplaces la tabla.

Recrea después el stream y deja la task suspendida.

---

# Parte 4. Interpretación

## Tarea 9. Comparar las capas

Completa:

| Característica | Parquet lógico | Backup nativo |
|---|---|---|
| Portable fuera de Snowflake |  |  |
| Conserva tablas y tipos |  |  |
| Conserva views |  |  |
| Conserva tasks |  |  |
| Conserva streams y stages |  |  |
| Requiere reconstruir DDL |  |  |
| Restore rápido dentro de Snowflake |  |  |
| Protege por sí solo de un fallo regional |  |  |

Completa también:

| Escenario | Mecanismo principal |
|---|---|
| `UPDATE` accidental reciente |  |
| Restauración en otra plataforma |  |
| Copia no modificable en Snowflake |  |
| Fallo regional |  |
| Pérdida completa de la cuenta |  |

---

## Tarea 10. RPO y RTO

Propón valores para:

| Capa | RPO | RTO |
|---|---:|---:|
| Pedidos operativos |  |  |
| Clientes |  |  |
| Datos RAW reproducibles |  |  |
| MARTS reconstruibles |  |  |

Responde:

1. ¿Qué mide el RPO?
2. ¿Qué mide el RTO?
3. ¿Por qué un internal stage no es una copia externa?
4. ¿Por qué un backup nativo no sustituye por sí solo al failover regional?
5. ¿Por qué deben probarse periódicamente los restores?

---

# Ampliación opcional

## Diseñar replicación y failover

Sin ejecutar el DDL:

1. Diseña un replication group que incluya:
   - `DB_M10_PROD`.
   - `DB_M10_BACKUP_REPO`.
2. Diseña un failover group para:
   - Bases de datos.
   - Roles y usuarios.
   - Warehouses.
   - Resource Monitors.
   - Network policies.
3. Explica:
   - Qué edición necesitarías.
   - Qué objetos serían de solo lectura.
   - Cómo comprobarías el último refresh.
   - Cómo evitarías escrituras simultáneas durante la promoción.

---

# Limpieza

Al terminar:

1. Comprueba que producción contiene siete pedidos y `1185.00`.
2. Elimina los restores y el snapshot.
3. Elimina los ficheros de `logical_v1/`.
4. Elimina el backup mediante su UUID.
5. Elimina el backup set.
6. Suspende la task y el warehouse.

> Un backup manual olvidado puede seguir reteniendo almacenamiento.

---

# Criterios de finalización

El ejercicio está completado cuando puedas demostrar que:

- El backup lógico procede de un punto consistente.
- Existen Parquet de clientes y pedidos y un manifest.
- El restore lógico contiene seis pedidos y `1005.00`.
- Las validaciones no detectan diferencias.
- El pedido posterior demuestra un RPO no nulo.
- Se creó un backup set y se obtuvo un UUID.
- El incidente reduce el total a `840.00`.
- El restore nativo recupera siete pedidos y `1185.00`.
- La task restaurada está suspendida.
- El stream y el internal stage no se restauran.
- Producción vuelve a `1185.00`.
- Los recursos temporales quedan eliminados o suspendidos.

---

## Preguntas de reflexión

1. ¿Por qué Parquet es apropiado para un backup lógico?
2. ¿Qué metadatos no conserva una exportación de datos?
3. ¿Qué ventaja ofrece un backup nativo frente a un clone?
4. ¿Qué objetos importantes deben reconstruirse tras restaurar una base?
5. ¿Qué mecanismo utilizarías para recuperar datos fuera de Snowflake?
6. ¿Qué mecanismo ofrece menor RTO ante un fallo regional?

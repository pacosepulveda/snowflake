# Módulo 8 · Ejercicio 1

## Dimensionamiento de warehouses, caché local y políticas de suspensión

### Contexto

El equipo de datos de **RetailNova** ha creado un único warehouse para desarrollo, transformación y consultas analíticas. Algunos usuarios solicitan aumentar permanentemente su tamaño porque determinadas consultas tardan varios segundos, mientras que el equipo FinOps sospecha que gran parte del coste procede de warehouses que permanecen activos sin trabajo.

Antes de cambiar la configuración, debes realizar un experimento controlado que permita separar cuatro factores:

1. El tamaño del warehouse.
2. El tiempo de aprovisionamiento al reanudarlo.
3. La caché local del warehouse.
4. La caché de resultados persistidos.

Compararás un warehouse `XSMALL` y otro `SMALL`, ambos de generación 1 y con Query Acceleration Service desactivado, para que la diferencia observada proceda principalmente del tamaño del warehouse.

---

## Objetivos

Al finalizar el ejercicio deberás ser capaz de:

1. Crear warehouses reproducibles mediante SQL.
2. Distinguir tamaño, generación y Query Acceleration Service.
3. Explicar la facturación por segundo y el mínimo por reanudación.
4. Crear una carga de datos sintética para pruebas.
5. Desactivar la caché de resultados persistidos.
6. Diferenciar result cache y caché local del warehouse.
7. Comparar ejecuciones frías y calientes.
8. Identificar tiempo de aprovisionamiento, compilación y ejecución.
9. Observar la pérdida de caché local después de suspender un warehouse.
10. Comparar rendimiento y coste teórico de `XSMALL` y `SMALL`.
11. Verificar `AUTO_SUSPEND` y `AUTO_RESUME`.
12. Proponer una configuración distinta para desarrollo y BI.
13. Evitar conclusiones basadas en una única ejecución.

---

## Convenciones

| Objeto | Nombre |
|---|---|
| Base de datos | `DB_CURSO` |
| Esquema | `PERFORMANCE` |
| Warehouse pequeño | `WH_M08_XS` |
| Warehouse ampliado | `WH_M08_S` |
| Tabla sintética | `VENTAS_RENDIMIENTO` |
| View de benchmark | `V_BENCHMARK_VENTAS` |
| Fichero SQL del workspace | `M08_E01_DIMENSIONAMIENTO.sql` |

---

## Condiciones del experimento

Los dos warehouses deben utilizar:

- Tipo `STANDARD`.
- `GENERATION = '1'`.
- Un único clúster.
- `AUTO_RESUME = TRUE`.
- `AUTO_SUSPEND = 60`.
- `INITIALLY_SUSPENDED = TRUE`.
- Query Acceleration Service desactivado.

Tamaños:

```text
WH_M08_XS → XSMALL → 1 crédito por hora en Gen1
WH_M08_S  → SMALL  → 2 créditos por hora en Gen1
```

No cambies estas propiedades durante las pruebas.

> Snowflake utiliza actualmente Gen2 como valor predeterminado en muchas regiones. En este ejercicio se fija Gen1 explícitamente para comparar dos tamaños con una escala de créditos conocida. No debe interpretarse como una recomendación general de usar Gen1 en producción.

---

## Tareas

### Tarea 1. Preparar Workspaces

En **Workspaces**, crea un fichero SQL llamado:

```text
M8_E01_DIMENSIONAMIENTO.sql
```

Configura:

- Rol.
- Base de datos.
- Esquema.
- Un `QUERY_TAG` inicial.

Crea el esquema `PERFORMANCE` si todavía no existe.

---

### Tarea 2. Crear los warehouses

Crea `WH_M08_XS` y `WH_M08_S` con las condiciones indicadas.

Comprueba mediante `SHOW WAREHOUSES` y `DESC WAREHOUSE`:

- Estado inicial.
- Tamaño.
- Generación.
- Auto-suspend.
- Auto-resume.
- Número mínimo y máximo de clústeres.
- Estado de Query Acceleration.

Explica por qué se desactiva QAS durante este benchmark.

---

### Tarea 3. Crear el conjunto de datos

Utiliza `WH_M08_XS` para crear una tabla transitoria con **10.000.000 de ventas sintéticas**.

La tabla debe contener:

- `id_venta`
- `fecha`
- `region`
- `canal`
- `id_cliente`
- `id_producto`
- `importe`
- `descuento`
- `estado`

Los datos deben:

- Cubrir 365 días.
- Incluir cinco regiones.
- Incluir tres canales.
- Incluir 500.000 clientes.
- Contener ventas `COMPLETADA`, `PENDIENTE` y `CANCELADA`.
- Ser deterministas para que todos los alumnos obtengan el mismo número de filas.

Comprueba el conteo y las fechas mínima y máxima.

Suspende el warehouse al terminar la creación para retirar de su caché local los bloques leídos o escritos durante el CTAS.

---

### Tarea 4. Crear la consulta de benchmark

Crea una view que:

1. Seleccione únicamente ventas completadas.
2. Calcule el importe neto.
3. Agregue primero por mes, región, canal y cliente.
4. Calcule después:
   - Clientes activos.
   - Número de ventas.
   - Importe total.
   - Importe medio por cliente.
   - Percentil 90 del importe por cliente.

La consulta final debe devolver un conjunto pequeño, pero procesar una parte significativa de la tabla.

---

### Tarea 5. Desactivar la result cache

Configura:

```text
USE_CACHED_RESULT = FALSE
```

Comprueba el valor del parámetro.

Explica por qué esta opción no desactiva la caché local del warehouse.

---

### Tarea 6. Ejecutar el benchmark en XSMALL

Ejecuta la consulta con `WH_M08_XS` tres veces:

1. **XS_COLD**: primera ejecución después de reanudar un warehouse suspendido.
2. **XS_WARM**: segunda ejecución inmediata en el mismo warehouse.
3. **XS_AFTER_SUSPEND**:
   - Suspende el warehouse.
   - Reanúdalo mediante la propia consulta.
   - Ejecuta otra vez el benchmark.

Asigna un `QUERY_TAG` diferente a cada ejecución.

No cambies la consulta entre pruebas.

---

### Tarea 7. Ejecutar el benchmark en SMALL

Ejecuta la misma consulta con `WH_M08_S`:

1. **S_COLD**: primera ejecución.
2. **S_WARM**: repetición inmediata.

Mantén desactivada la result cache y utiliza tags diferentes.

---

### Tarea 8. Analizar Query History

Construye un informe con las cinco ejecuciones y estas métricas:

- Warehouse.
- Tamaño.
- Tiempo total.
- Tiempo de compilación.
- Tiempo de ejecución.
- Tiempo en cola por aprovisionamiento.
- Bytes escaneados.
- Porcentaje leído de la caché local.
- Particiones escaneadas.
- Bytes derramados a almacenamiento local o remoto.
- Filas escritas al resultado.

No confundas:

```text
TOTAL_ELAPSED_TIME
EXECUTION_TIME
QUEUED_PROVISIONING_TIME
```

---

### Tarea 9. Interpretar la caché

Responde utilizando tus resultados:

1. ¿Fue `XS_WARM` más rápida que `XS_COLD`?
2. ¿Aumentó el porcentaje leído de la caché local?
3. ¿Qué ocurrió después de suspender el warehouse?
4. ¿Por qué `USE_CACHED_RESULT = FALSE` no impidió una ejecución caliente?
5. ¿Por qué no debes comparar `TOTAL_ELAPSED_TIME` sin revisar el aprovisionamiento?

Los valores exactos pueden variar entre cuentas y ejecuciones. Debes razonar con las métricas observadas, no esperar una duración fija.

---

### Tarea 10. Comparar tamaño y coste

Para cada ejecución fría, calcula:

```text
créditos teóricos de ejecución
= segundos de ejecución × créditos/hora ÷ 3600
```

Compara:

- `WH_M08_XS`: 1 crédito/hora.
- `WH_M08_S`: 2 créditos/hora.

Calcula también el mínimo facturable asociado a una reanudación aislada:

```text
XSMALL → 1/60 crédito
SMALL  → 2/60 créditos
```

Explica por qué el coste real del warehouse no puede atribuirse exactamente a una consulta corta mediante esta fórmula.

---

### Tarea 11. Verificar auto-suspend y auto-resume

Después de terminar una consulta:

1. No ejecutes nada durante aproximadamente 90 segundos.
2. Utiliza `SHOW WAREHOUSES` para comprobar que el warehouse se suspendió.
3. Ejecuta de nuevo el benchmark.
4. Comprueba que se reanudó automáticamente.
5. Localiza el tiempo de aprovisionamiento de esa ejecución.

`SHOW WAREHOUSES` no necesita utilizar el warehouse y no debería reanudarlo.

---

### Tarea 12. Separar workloads

Propón una configuración razonada para:

#### Desarrollo

- Consultas esporádicas.
- Prioridad de coste.
- Baja concurrencia.

#### BI interactivo

- Consultas frecuentes durante horario laboral.
- Sensibilidad a latencia.
- Reutilización de caché local.

Tu propuesta debe indicar:

- Tamaño inicial.
- Auto-suspend.
- Auto-resume.
- Si compartirías o separarías warehouses.
- Qué métricas revisarías antes de aumentar el tamaño.

---

### Tarea 13. Restaurar y detener recursos

Al finalizar:

- Restaura `USE_CACHED_RESULT`.
- Suspende ambos warehouses.
- Comprueba su estado.
- No elimines todavía la tabla, porque puede reutilizarse en ejercicios posteriores.

---

## Resultados que no son fijos

No se exige que `SMALL` sea exactamente el doble de rápido.

El resultado depende de:

- Región y disponibilidad de cómputo.
- Generación del warehouse.
- Compresión y micro-particiones.
- Estado de la caché local.
- Aprovisionamiento.
- Optimizaciones del servicio.
- Variación normal entre ejecuciones.

Una conclusión válida debe utilizar varias ejecuciones y separar tiempo de consulta, colas y caché.

---

## Preguntas de reflexión

1. ¿Por qué aumentar el tamaño no garantiza reducir el coste?
2. ¿Qué significa que cada reanudación tenga un mínimo facturable?
3. ¿Por qué un auto-suspend excesivamente agresivo puede aumentar coste y latencia?
4. ¿Qué diferencia existe entre escalar verticalmente y añadir clústeres?
5. ¿Por qué multi-cluster no aceleraría esta consulta individual?
6. ¿Qué riesgo tendría realizar el benchmark con QAS activado?
7. ¿Qué métrica te indicaría que el problema es concurrencia y no potencia por consulta?
8. ¿Qué warehouse utilizarías para desarrollo y cuál para BI?

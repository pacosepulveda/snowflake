# Módulo 12 · Ejercicio 1

## Distribución de un producto de datos con Secure Data Sharing y Native Apps

> **Entorno:** cuenta trial actual de Snowflake

---

## Contexto

RetailNova quiere distribuir información analítica sin entregar sus tablas internas ni exportar ficheros.

El producto se publicará de dos formas:

```text
Secure Data Sharing
    → datos actualizados y de solo lectura
    → secure view
    → database role
    → share

Snowflake Native App
    → datos y lógica instalados dentro de una application
    → application role
    → views, función y procedimiento
    → actualización conservando estado
```

El objetivo es comprender qué problema resuelve cada mecanismo y cómo limitar la superficie expuesta al consumidor.

---

## Objetivos

Al finalizar deberás ser capaz de:

- Reconocer una imported database.
- Explicar quién paga almacenamiento y compute en Secure Data Sharing.
- Comprobar que los datos compartidos son de solo lectura.
- Separar datos privados y objetos publicados.
- Crear una secure view que oculte PII y costes internos.
- Empaquetar permisos mediante un database role.
- Crear un outbound share sin añadir cuentas desconocidas.
- Diferenciar direct share, listing, reader account y Native App.
- Diferenciar application package y application.
- Instalar una Native App desde staged files.
- Conceder un application role a un account role.
- Utilizar una interfaz pública sin acceder a objetos internos.
- Guardar estado mediante un procedimiento.
- Actualizar la aplicación conservando el estado del consumidor.

---

## Objetos

| Tipo | Nombre |
|---|---|
| Warehouse | `WH_M12_ECOSYSTEM` |
| Rol consumidor de datos | `M12_SHARED_DATA_CONSUMER` |
| Rol validador | `M12_SHARE_VALIDATOR` |
| Base provider | `DB_M12_PROVIDER` |
| Esquema privado | `PRIVATE` |
| Esquema publicado | `PUBLISHED` |
| Secure view | `PUBLISHED.V_VENTAS_REGION` |
| Database role | `DB_M12_PROVIDER.DR_SHARED_ANALYST` |
| Share | `SHARE_M12_VENTAS` |
| Rol provider de app | `M12_NATIVE_APP_PROVIDER` |
| Rol consumer de app | `M12_APP_CONSUMER` |
| Application package | `PKG_M12_SALES_INSIGHTS` |
| Application | `APP_M12_SALES_INSIGHTS` |

---

## Recursos proporcionados

```text
Snowflake_Modulo12_Ejercicio1_Recursos_NativeApp.zip
```

Contiene:

```text
v1/
    manifest.yml
    setup.sql
    README.md

v2/
    manifest.yml
    setup.sql
    README.md
```

Descomprime el ZIP antes de subir los ficheros.

---

## Reglas

- Utiliza Workspaces.
- No añadas cuentas desconocidas al share.
- No publiques una listing.
- No crees un reader account.
- No instales productos de pago.
- Ejecuta las pruebas negativas de una en una.
- Sube V1 y V2 a stages distintos.
- Elimina el share, la app y el package al finalizar.

---

# Parte 1. Consumir datos compartidos

## Tarea 1. Preparar el entorno

Crea:

```text
WH_M12_ECOSYSTEM
M12_SHARED_DATA_CONSUMER
```

El warehouse debe ser `XSMALL`, con `AUTO_SUSPEND = 60`.

Concede al rol consumidor:

- `USAGE` sobre el warehouse.
- `IMPORTED PRIVILEGES` sobre `SNOWFLAKE_SAMPLE_DATA`.

---

## Tarea 2. Comprobar el modelo consumer

Como `M12_SHARED_DATA_CONSUMER`:

1. Consulta `SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.CUSTOMER`.
2. Comprueba el `ORIGIN` de la base.
3. Intenta actualizar una fila.
4. Explica:
   - Por qué el `UPDATE` falla.
   - Dónde permanecen los datos.
   - Quién paga el warehouse.
   - Cuándo una tabla derivada sí ocuparía almacenamiento local.

---

# Parte 2. Construir el producto del provider

## Tarea 3. Crear los datos privados

Crea:

```text
DB_M12_PROVIDER.PRIVATE.VENTAS
DB_M12_PROVIDER.PUBLISHED
```

La tabla debe contener ocho ventas, cuatro regiones y un total de `1405.00`.

Incluye columnas privadas:

```text
CLIENTE_EMAIL
COSTE_INTERNO
```

---

## Tarea 4. Publicar una secure view

Crea:

```text
DB_M12_PROVIDER.PUBLISHED.V_VENTAS_REGION
```

Debe:

- Ser `SECURE`.
- Publicar solo ventas completadas.
- Agregar por región.
- Mostrar ventas, importe total y ticket medio.
- No incluir emails, costes ni filas individuales.

Resultado:

| Región | Ventas | Importe |
|---|---:|---:|
| NORTE | 2 | 270.00 |
| SUR | 2 | 345.00 |
| ESTE | 2 | 260.00 |
| OESTE | 2 | 530.00 |

---

## Tarea 5. Crear y validar el contrato

Crea:

```text
DB_M12_PROVIDER.DR_SHARED_ANALYST
M12_SHARE_VALIDATOR
```

El database role recibirá únicamente:

- `USAGE` sobre `PUBLISHED`.
- `SELECT` sobre la secure view.

Como `M12_SHARE_VALIDATOR`:

- Consulta la secure view.
- Intenta consultar `PRIVATE.VENTAS`.
- Comprueba que el acceso privado está denegado.

No configures future grants en el database role compartible.

---

## Tarea 6. Crear el outbound share

Crea:

```text
SHARE_M12_VENTAS
```

Añade:

- `USAGE` sobre `DB_M12_PROVIDER`.
- `DR_SHARED_ANALYST`.

Comprueba:

```text
SHOW SHARES
DESCRIBE SHARE
SHOW GRANTS TO SHARE
SHOW GRANTS OF SHARE
```

No añadas cuentas consumer durante el laboratorio.

---

# Parte 3. Instalar una Native App

## Tarea 7. Crear package y stages

Crea:

```text
M12_NATIVE_APP_PROVIDER
M12_APP_CONSUMER
PKG_M12_SALES_INSIGHTS
PKG_M12_SALES_INSIGHTS.STAGE_CONTENT.APP_STAGE_V1
PKG_M12_SALES_INSIGHTS.STAGE_CONTENT.APP_STAGE_V2
```

Los stages deben tener directory table habilitada.

Carga los tres ficheros de `v1/` en `APP_STAGE_V1`.

---

## Tarea 8. Instalar y consumir V1

Instala:

```text
APP_M12_SALES_INSIGHTS
```

desde `APP_STAGE_V1`.

Concede:

```text
APP_M12_SALES_INSIGHTS.APP_USER
    → M12_APP_CONSUMER
```

Como consumer:

1. Consulta la versión.
2. Consulta los objetivos regionales.
3. Ejecuta:
   ```text
   ATTAINMENT_PCT(930, 1000)
   ```
4. Guarda una nota para `NORTE`.
5. Comprueba que la nota aparece en `V_NOTES`.

Resultados:

```text
APP_VERSION = 1.0
ATTAINMENT_PCT = 93.0
1 nota guardada
```

---

## Tarea 9. Probar el aislamiento

Como `M12_APP_CONSUMER`, intenta individualmente:

- Consultar `APP_DATA.REGION_TARGETS`.
- Insertar directamente en `APP_DATA.CONSUMER_NOTES`.
- Crear una tabla dentro de la application.
- Reemplazar una view pública.

Todas deben fallar.

---

# Ampliación opcional

## Actualizar a V2

1. Carga `v2/` en `APP_STAGE_V2`.
2. Ejecuta el upgrade desde staged files.
3. Comprueba:
   - `APP_VERSION = 2.0`.
   - Existe `RECOMMEND_ACTION`.
   - Aparecen `PRIORITY` y `GAP_FROM_REFERENCE`.
   - La nota de `NORTE` sigue existiendo.
   - No es necesario volver a conceder `APP_USER`.

---

# Interpretación

Completa:

| Mecanismo | Qué distribuye | Consumer necesita cuenta | Compute |
|---|---|---|---|
| Direct share |  |  |  |
| Listing |  |  |  |
| Reader account |  |  |  |
| Native App |  |  |  |

Responde:

1. ¿Por qué una secure view es preferible a compartir la tabla privada?
2. ¿Por qué un database role compartido no debe tener future grants?
3. ¿Qué diferencia existe entre application package y application?
4. ¿Qué protege un application role?
5. ¿Por qué `CREATE TABLE IF NOT EXISTS` ayuda durante un upgrade?
6. ¿Por qué una trial puede probar direct sharing, pero no publicar en Marketplace?

---

# Limpieza

Al finalizar:

1. Elimina `APP_M12_SALES_INSIGHTS`.
2. Elimina `PKG_M12_SALES_INSIGHTS`.
3. Elimina `SHARE_M12_VENTAS`.
4. Elimina los roles temporales de la app.
5. Suspende `WH_M12_ECOSYSTEM`.
6. Conserva `DB_M12_PROVIDER` solo si se utilizará después.

---

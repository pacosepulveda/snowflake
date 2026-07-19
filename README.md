# Laboratorios prácticos de Snowflake

Repositorio de ejercicios prácticos para aprender a trabajar con **Snowflake** mediante escenarios guiados.

Cada ejercicio incluye:

- Un **enunciado**, con el contexto, los objetivos y las tareas que debe realizar el alumno.
- Una **solución guiada**, con el procedimiento completo, explicaciones y resultados esperados.

Los ejercicios están pensados para realizarse de forma progresiva. Algunos reutilizan objetos, datos o configuraciones creados en actividades anteriores.

---

## Organización del repositorio

Los ejercicios se organizan en carpetas. Cada carpeta principal corresponde a una parte del curso y contiene subcarpetas para los distintos ejercicios.

Estructura recomendada:

```text
.
├── README.md
├── modulo-01/
│   ├── ejercicio-01/
│   │   ├── enunciado.md
│   │   └── solucion.md
│   └── ejercicio-02/
│       ├── enunciado.md
│       └── solucion.md
├── modulo-02/
│   └── ...
└── recursos/
```
---

## Cómo utilizar los ejercicios

1. Lee el enunciado completo antes de comenzar.
2. Comprueba los prerrequisitos indicados.
3. Realiza las tareas en el orden propuesto.
4. Conserva las consultas, resultados y errores solicitados como evidencia.
5. Consulta la solución únicamente después de intentar resolver el ejercicio.
6. Comprueba al finalizar que los recursos quedan en el estado indicado.

Algunos ejercicios contienen operaciones que **deben fallar**. Estas pruebas negativas forman parte del laboratorio y permiten comprobar permisos, configuraciones o condiciones de seguridad.

---

## Requisitos generales

Dependiendo del ejercicio, puede ser necesario disponer de:

- Una cuenta de Snowflake destinada a formación.
- Acceso a Snowsight.
- Permisos para utilizar los roles indicados.
- Un navegador con acceso a Internet.
- Google Colab para los ejercicios con Python.
- Credenciales de una cuenta de laboratorio.

No utilices cuentas, credenciales o datos de producción salvo autorización expresa.

---

## Seguridad

No almacenes en el repositorio:

- Contraseñas.
- Tokens.
- Claves privadas.
- Códigos MFA.
- Ficheros `.env`.
- Credenciales de cuentas reales.
- Datos confidenciales.
- Notebooks con secretos o salidas sensibles.

Cuando un ejercicio utilice Python:

- Solicita la contraseña mediante una entrada oculta.
- Utiliza consultas parametrizadas.
- Trabaja con roles de mínimo privilegio.
- Cierra correctamente cursores y conexiones.
- Elimina o desconecta los entornos temporales al terminar.

---

## Control de costes

Los laboratorios deben realizarse utilizando recursos pequeños y configuraciones que eviten consumo innecesario.

Buenas prácticas recomendadas:

- Utilizar warehouses de tamaño `X-Small` cuando sea suficiente.
- Configurar `AUTO_SUSPEND`.
- Mantener `AUTO_RESUME` únicamente cuando sea necesario.
- Suspender explícitamente los warehouses al finalizar.
- Eliminar los recursos temporales que ya no se necesiten.
- Revisar siempre el rol, warehouse, base de datos y esquema activos.

---

## Compatibilidad

Snowflake es un servicio SaaS que se actualiza continuamente. La ubicación de algunas opciones de Snowsight, ciertos mensajes de error o pequeños detalles de la interfaz pueden cambiar.

En caso de diferencias:

1. Comprueba el contexto de sesión.
2. Revisa los privilegios efectivos.
3. Consulta Query History.
4. Prioriza el objetivo técnico del ejercicio.
5. Contrasta el comportamiento con la documentación oficial de Snowflake.

---

## Aviso

Este repositorio contiene material educativo independiente. No constituye documentación oficial de Snowflake ni sustituye las políticas de seguridad, arquitectura o gobierno aplicables a un entorno real.

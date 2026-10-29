# Dónde probar las políticas de RLS — recomendación

Hoy **no hay staging: la app local pega contra producción.** Eso alcanzó para todo lo que se
hizo hasta ahora, porque los cambios eran de pantalla y de cálculo: si algo salía mal se
veía raro y se arreglaba. Las políticas de RLS no se portan así.

---

## 1. Por qué esta vez sí hace falta

Tres razones, en orden de gravedad:

**Una política mal escrita no se ve, se sufre.** Si una política de `pagos` queda mal, la
app **no muestra un error**: muestra la tabla vacía, y los saldos salen inflados con cara de
dato correcto (está explicado en `auth_fase1_diseno.md`, punto 6.1). El cobrador saldría a
cobrar con números que no son. En el otro extremo, una política demasiado estricta deja a
alguien sin poder cargar un remito y ahí sí se enteran todos, de golpe.

**El calendario no perdona.** Jueves, viernes y sábado son días de reparto. Un error de
política un jueves a la mañana es el negocio parado en el peor momento. Y no se puede
"probar un lunes y listo": son **29 tablas** y la matriz tiene cuatro roles, así que hay
muchas combinaciones que nadie va a ejercitar a mano una sola vez.

**No hay cómo probar un rol que no es el tuyo.** Para ver lo que ve el Encargado de
Depósito hay que entrar con su cuenta, y la única forma de hacerlo contra producción es
pedirle la contraseña o crearse un usuario de prueba más. Con un proyecto aparte se entra
con cualquier rol, sin pedirle nada a nadie.

---

## 2. Qué recomiendo: dos cosas, no una

### 2.1 Un segundo proyecto de Supabase, con esquema real y datos inventados

Es donde se escriben las políticas, se rompen, se arreglan y se vuelven a romper.

- **Esquema igual al de producción**, sacado de un dump de esquema (ver punto 4).
- **Datos inventados, NO una copia de producción.** Esto es importante y es lo contrario de
  lo que uno haría por comodidad: copiar los 108 clientes y los 1871 pagos reales a un
  segundo proyecto sería **duplicar exactamente el problema que esta fase vino a cerrar** —
  otra base con los datos de la gente adentro, con su propia publishable key, con RLS
  apagado al principio y sin nadie mirándola. Alcanza con: 2 vendedores, 5 clientes, unos
  10 remitos, 5 pagos, 1 proveedor con 2 cargas, 1 lista de reparto.
- **Un usuario por rol**: un admin, una secretaria, un cobrador, un encargado de depósito.
  Esto es más de la mitad del valor del staging: poder mirar la app con los cuatro ojos
  distintos en diez minutos.
- La app local se apunta ahí con `--dart-define` o cambiando la URL y la key en `main.dart`
  mientras se trabaja. (Que esos dos valores estén **hardcodeados en `main.dart`** es, de
  paso, la razón por la que hoy no hay staging: no hay forma de apuntar la app a otra base
  sin editar código. Pasarlos a `AppConfig` con `--dart-define`, como ya se hace con
  `version` y `clienteNombre`, es media hora de trabajo y es prerequisito práctico de todo
  esto.)

### 2.2 Un ensayo en transacción contra producción, antes de cada encendido

El staging prueba que la política hace lo que se quiere. Esto prueba que hace lo que se
quiere **con los datos y las identidades de verdad** — que es otra cosa, porque los datos de
producción tienen filas raras que ningún dato inventado va a tener.

En Postgres el DDL es transaccional, así que se puede encender RLS, crear la política,
mirar qué devuelve, y **deshacer todo** sin dejar rastro:

```sql
begin;

alter table pagos enable row level security;
create policy pagos_select on pagos for select
  using (tiene_permiso('ver_consultas') or tiene_permiso('crear_pago'));

-- Hacerse pasar por Arturo (el cobrador): su auth_id sale de
-- select auth_id from usuarios where usuario = 'artur';
set local role authenticated;
set local request.jwt.claims = '{"sub":"<auth_id de artur>","role":"authenticated"}';

select count(*) from pagos;          -- tiene que dar 1871
reset role;

-- Y ahora el encargado de depósito, que NO tiene que ver pagos
set local role authenticated;
set local request.jwt.claims = '{"sub":"<auth_id de rocio_cejas>","role":"authenticated"}';
select count(*) from pagos;          -- tiene que dar 0
reset role;

rollback;   -- nada de esto quedó
```

**El caveat, que es real:** `ALTER TABLE … ENABLE ROW LEVEL SECURITY` toma un lock exclusivo
sobre la tabla, y ese lock dura hasta el `rollback`. Mientras la transacción está abierta,
**cualquier consulta de la app a esa tabla espera**. Así que: una tabla por vez, la
transacción corta (copiar y pegar todo junto, no escribirlo en vivo), y **lunes a la
mañana**, nunca un día de reparto. Si te distraés con la transacción abierta, la app se
cuelga para todos — así que no dejarla abierta.

Las dos cosas juntas cubren lo que ninguna cubre sola. Costo de la segunda: **$0** y cinco
minutos por tabla.

---

## 3. Qué cuesta mantener el segundo proyecto

### En plata

Los números de abajo son de búsqueda pública al 28/10/2026 y **hay que confirmarlos en
`supabase.com/pricing`** antes de decidir: las fuentes son blogs de terceros y no coinciden
entre sí en los detalles.

| Si el proyecto de Don Chacho está en… | Lo que costaría el segundo proyecto |
|---|---|
| **Free** | **$0.** El plan Free permite **2 proyectos activos** (el límite cuenta sobre todas las organizaciones donde seas Owner o Admin, así que abrir otra organización no suma cupo). El límite técnico que importa es 500 MB de base, y esta base entra holgada: las tablas más grandes son 1871 pagos y 1087 remitos con sus ítems. |
| **Pro ($25/mes por organización)** | **unos +$10/mes**: el plan incluye $10 de crédito de compute, que alcanza para una instancia Micro, y el segundo proyecto suma otra Micro (~$10). Las fuentes no coinciden en si ese crédito es por organización o por proyecto — si es por proyecto, el segundo también sale $0. |

**Lo barato tiene una trampa:** un proyecto Free **se pausa solo después de 7 días sin
actividad**. Para un staging eso es casi una ventaja (no gastás nada y nadie le pega), pero
hay que saberlo: el día que lo necesitás, lo despausás a mano desde el dashboard y tarda un
par de minutos en levantar. Lo que **no** hay que hacer es poner un cron a pingearlo para
mantenerlo vivo: es gastar para nada.

**A chequear antes de crear el proyecto:** hay un cambio de Supabase sobre los permisos de
Postgres que necesita PostgREST, que afectaría a los **proyectos nuevos** (una fuente lo
ubica a partir del 30/05/2026, y a los proyectos Free existentes desde el 30/10/2026 — o
sea, pasado mañana). Si el proyecto nuevo no contesta por REST recién creado, es por ahí y
hay que agregar los `GRANT` a mano. Es un dato de una sola fuente secundaria: vale
chequearlo en el changelog de Supabase, no asumirlo.

### En trabajo — que es el costo que importa

La plata es lo de menos. Lo que cuesta de verdad es que **el esquema de staging no se
desincronice**, y eso hoy no es trivial por cómo se vinieron corriendo las migraciones: son
22 archivos `.sql` en la raíz del repo, corridos a mano en orden, y **algunos cambios nunca
fueron archivo** (las columnas `saldo_anterior` / `saldo_nuevo` de `pagos` están
documentadas como "agregar manualmente en el SQL Editor"). Replayear los 22 archivos en un
proyecto nuevo **no** reconstruye producción.

| Tarea | Cuánto | Cada cuánto |
|---|---|---|
| Sacar el esquema de producción (`supabase db dump --schema-only`, o `pg_dump --schema-only` por el pooler) y guardarlo en el repo como `supabase_schema_completo.sql` | 30 min | una vez |
| Crear el proyecto, correr el esquema y un `supabase_seed_staging.sql` con los datos inventados y los 4 usuarios | 1 h | una vez |
| Pasar la URL y la key de Supabase de `main.dart` a `AppConfig` con `--dart-define` | 30 min | una vez |
| **Correr cada migración nueva primero en staging** | 2 min | por migración |
| Volver a sacar el esquema cuando se haya desincronizado | 15 min | cada varios meses |

**Total de arranque: unas 2 horas.** Mantenerlo: 2 minutos por migración, que es menos de lo
que cuesta un solo error de RLS descubierto en producción un viernes.

Y hay un rédito que va más allá de esta fase: tener el esquema completo en un archivo
versionado arregla el agujero de las migraciones corridas a mano. Hoy, si el proyecto de
Supabase se perdiera, reconstruirlo exigiría arqueología sobre 22 archivos y la
documentación. Ese archivo es, de hecho, el backup del esquema.

---

## 4. Lo que NO recomiendo, y por qué

- **Copiar los datos de producción a staging.** Ya dicho: es duplicar la exposición. Si
  alguna vez hace falta volumen real para probar performance, se copia **anonimizado**
  (nombres y teléfonos reemplazados), nunca tal cual.
- **Probar RLS encendiéndolo "un rato" en producción y mirando qué pasa.** Es la tentación
  obvia y es la peor opción: el "rato" en que algo no funciona es gente que no puede
  trabajar, y el síntoma (tabla vacía) no grita. Si se va a tocar producción, se toca
  **dentro de una transacción que termina en `rollback`**, como el punto 2.2.
- **Supabase local (`supabase start`, Docker).** Sirve para desarrollar y es gratis, pero
  no reemplaza a un proyecto en la nube: no tiene las particularidades del entorno real
  (pooler, límites de PostgREST, la configuración de Auth del dashboard) y es justo ahí
  donde aparecen las sorpresas. Como complemento del punto 2.1 está bien; como reemplazo,
  no.
- **Esperar a tener staging para hacer la Fase 1.** La Fase 1 es aditiva y tiene rollback
  en cada paso (`auth_fase1_runbook.md`): se puede hacer ya. Staging es condición de la
  **Fase 2**, no de esta.

---

## Fuentes de los precios

Precios y límites consultados el 28/10/2026, todos de terceros — **confirmar en
`supabase.com/pricing`**:

- [Supabase Pricing in 2026: What You'll Actually Pay](https://makerkit.dev/blog/saas/supabase-pricing)
- [Supabase Pricing: 2026 Guide to Plans, Limits, and Real-World Costs](https://www.jetadmin.io/blog/supabase-pricing-2026-guide-to-plans-limits-and-real-world-costs/)
- [Supabase Pricing 2026: Free vs Pro ($25) vs Team ($599)](https://www.nocode.mba/articles/supabase-pricing)
- [Supabase Pricing 2026: What $25 Really Gets You](https://selfhost.dev/blog/supabase-pricing-explained/)
- [What are the Supabase free tier limits in 2026?](https://automationatlas.io/answers/supabase-free-tier-limits-2026/)

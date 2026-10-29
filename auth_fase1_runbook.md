# Runbook — migrar las 6 cuentas a Supabase Auth (Fase 1)

Para Mili. Todo se hace a mano desde el dashboard de Supabase y la app; nada de esto lo
corre el agente.

**Lo que hay que tener a mano antes de empezar**

- El dashboard del proyecto: `https://supabase.com/dashboard/project/svgvyukjqfjkxtypgobq`
- El archivo `supabase_migration_auth_identidad.sql` abierto
- Un lugar donde anotar las 6 contraseñas temporales para pasárselas (y después borrarlo)
- **El diseño leído**, aunque sea el punto 3: `auth_fase1_diseno.md`

**Cuándo hacerlo.** Un **lunes, martes o miércoles**, a la mañana. Jueves, viernes y sábado
son días de reparto: si algo sale mal, ese es el peor momento posible. Esta fase no enciende
RLS, así que el riesgo es bajo, pero el día importa igual porque el **deploy** sí cambia el
login de todos.

**Cuánto lleva.** Unos 40 minutos de trabajo, más el tiempo que tarden los 6 en entrar y
cambiar su contraseña (eso puede llevar días y no bloquea nada).

**Las contraseñas viejas no se migran.** Eran SHA-256 sin sal; Supabase Auth usa bcrypt. No
hay conversión posible y no hay que buscarla: esas contraseñas están quemadas. Cada uno
arranca con una temporal y la cambia.

---

## Lo que estás por hacer, en una frase

Crear 6 cuentas de acceso en Supabase, vincularlas con los 6 perfiles que ya existen, y
deployar la app que usa esas cuentas para entrar. El login viejo sigue funcionando como red
durante todo el proceso.

---

## PASO 0 — Foto de cómo está hoy (2 min)

Dashboard → **SQL Editor** → correr esto y **guardar el resultado** (captura o copiar y
pegar en un archivo). Es contra qué vas a comparar si algo sale raro:

```sql
select u.usuario, u.nombre_completo, r.nombre as rol, u.activo
from usuarios u join roles r on r.id = u.rol_id
order by u.usuario;
```

Tienen que salir 6 filas: `admin`, `artur`, `mili`, `rocio_cejas`, `rociolopez`,
`solealcala`. Si sale otra cosa, **pará acá** y avisá: el diseño se escribió contra esas 6.

---

## PASO 1 — Correr la migración, bloques 1 a 4 (5 min)

Dashboard → **SQL Editor** → **New query**. Copiar de
`supabase_migration_auth_identidad.sql` **desde el principio hasta donde termina el bloque
`-- ── 4. tiene_permiso(text)`** (incluidos los dos `GRANT EXECUTE` que están al final de
ese bloque). **No** copiar todavía los bloques 5, 6 y 7.

Qué hace: agrega `usuarios.auth_id` (vacía, nullable), el índice, y crea las dos funciones.

**Verificar** (en el mismo SQL Editor):

```sql
select public.es_admin(), public.tiene_permiso('crear_pago');
```

Las dos tienen que devolver **false**. En el SQL Editor no hay usuario logueado, así que
`auth.uid()` es NULL y false es la respuesta correcta. Si devuelve error, la función no se
creó.

```sql
select count(*) as sin_cuenta from usuarios where auth_id is null;
```

Tiene que decir **6**.

**La app sigue funcionando normal en este punto.** Nadie nota nada.

> **Si falla:** lo más probable es un error de permisos sobre `auth.users` al crear la
> foreign key. El SQL Editor del dashboard corre como `postgres` y puede, así que si pasa,
> fijate que estés en el SQL Editor y no en otra consola. Para volver atrás: `drop function
> if exists public.tiene_permiso(text); drop function if exists public.es_admin(); drop
> index if exists idx_usuarios_auth_id; alter table usuarios drop column if exists auth_id;`

---

## PASO 2 — Crear las 6 cuentas de acceso (15 min)

Dashboard → **Authentication** → **Users** → botón **Add user** → **Create new user**.

Para cada una de las 6: poner el **Email** exacto de la tabla, una contraseña temporal, y
**tildar "Auto Confirm User"**.

> **"Auto Confirm User" es obligatorio.** Sin eso, Supabase deja la cuenta pendiente de
> confirmar por mail — y estos mails no existen, así que esa confirmación no va a llegar
> nunca y la persona no podría entrar.

| # | Email | Quién es | Contraseña temporal |
|---|---|---|---|
| 1 | `mili@donchacho.local` | Mili Prueba (tu cuenta de prueba) | la que quieras |
| 2 | `admin@donchacho.local` | Administrador (Joaco) | elegir una |
| 3 | `rociolopez@donchacho.local` | Rocio Lopez | elegir una |
| 4 | `solealcala@donchacho.local` | soledad Alcalá | elegir una |
| 5 | `artur@donchacho.local` | Arturo Aguilera | elegir una |
| 6 | `rocio_cejas@donchacho.local` | Rocio Cejas | elegir una |

**Empezá por `mili`, a propósito:** es la cuenta de prueba, así que es con la que conviene
descubrir cualquier problema antes de tocar las de la gente que trabaja.

**Sobre las contraseñas temporales:** mínimo 8 caracteres (es lo que valida la app). Que
sean **distintas entre sí** y fáciles de dictar por WhatsApp. No reusar ninguna contraseña
vieja del sistema: están quemadas.

Al terminar, en **Authentication → Users** tienen que aparecer 6 usuarios, los 6 con el
mail `@donchacho.local` y **sin** el cartelito de "Waiting for verification".

---

## PASO 3 — Vincular cada cuenta con su perfil (2 min)

SQL Editor → copiar y correr **el bloque 5** de `supabase_migration_auth_identidad.sql` (el
`UPDATE usuarios … FROM auth.users …`).

Es el paso que une las dos mitades: el perfil que ya existía (con su rol y su historia) y la
cuenta nueva. Lo hace solo, por el mail: nadie copia UUIDs a mano.

**Verificar** — correr el chequeo que está comentado en el bloque 7 de la migración:

```sql
select u.usuario, u.nombre_completo, r.nombre as rol, u.activo,
       case when u.auth_id is null then 'SIN CUENTA' else 'vinculado' end as identidad,
       a.email
from usuarios u
join roles r on r.id = u.rol_id
left join auth.users a on a.id = u.auth_id
order by u.usuario;
```

**Las 6 filas tienen que decir `vinculado`.** Si alguna dice `SIN CUENTA`, el mail de esa
cuenta está mal escrito: andá a Authentication → Users, corregilo, y volvé a correr el
bloque 5 (es seguro re-correrlo, no repisa los vínculos ya hechos).

**La app sigue funcionando normal.** Todavía está deployada la versión vieja, que ni sabe que
la columna existe.

---

## PASO 4 — Correr el bloque 6: el bucket de soporte (1 min)

SQL Editor → copiar y correr **el bloque 6** (las policies de `soporte-adjuntos`).

Por qué: las policies del bucket están escritas para el rol `anon`, que es como se conectaba
la app hasta hoy. Con las cuentas nuevas las consultas llegan como `authenticated` y esas
policies dejarían de servir — **adjuntar la foto de un reclamo de soporte y poder verla
dejarían de funcionar** justo después del deploy. Esto las deja andando para los dos casos.

Esto **tiene que correrse antes del PASO 5**.

---

## PASO 5 — Deployar la app (10 min)

Recién acá cambia algo para los usuarios.

```bash
cd /Users/milifernandezsabate/Projects/matarife-system/don_chacho
./build_web.sh
```

```bash
cd /Users/milifernandezsabate/Projects/matarife-system/don_chacho/build/web && vercel --prod
```

(El procedimiento completo, con el chequeo del `.vercel` y del `app_version.json`, está en
`don_chacho/CLAUDE.md` → "PROCEDIMIENTO DE ACTUALIZACIÓN / DEPLOY". Acordate de subir
`AppConfig.version` antes de buildear.)

**Probar vos primera, con `mili`:**

1. Entrar a la app, cerrar sesión si estabas adentro.
2. Entrar como `mili` con la contraseña **temporal** nueva → tiene que dejarte entrar.
3. `+` → **Cambiar contraseña** → poner la temporal y una nueva → tiene que decir
   "Contraseña cambiada".
4. Cerrar sesión y entrar de nuevo con la **nueva** → tiene que dejarte entrar.
5. Recargar la página estando adentro → **no** te tiene que pedir el login otra vez (la
   sesión de Supabase se guarda sola).
6. `+` → **Reportar un problema**, adjuntando una foto → tiene que guardar y mostrarse (eso
   prueba el PASO 4).

Si los 6 puntos andan, el camino nuevo funciona.

---

## PASO 6 — Pasarles la contraseña a los 5 (el tiempo que lleve)

Mandarle a cada uno, por separado:

> Cambió la forma de entrar a la app. Tu usuario es el mismo de siempre (`____`), pero la
> contraseña es nueva: `____`. Entrá, tocá el botón `+`, elegí **Cambiar contraseña** y
> ponete una tuya. Si no te deja entrar, avisame antes de seguir intentando.

**Importante:** la contraseña vieja de cada uno **todavía funciona** (es la red del login
legacy). Así que si alguien no llega a cambiarla, no se queda afuera. Pero eso es temporal:
mientras entre con la vieja, **no** está usando su cuenta nueva.

Ir marcando quién ya entró con la nueva. Para chequearlo por SQL:

```sql
-- password_hash vacío = esta persona ya cambió su contraseña por la app
select usuario, nombre_completo,
       case when coalesce(password_hash, '') = '' then 'ya la cambió' else 'todavía no' end
from usuarios order by usuario;
```

---

## PASO 7 — Apagar el login viejo (5 min, cuando los 6 estén)

**Recién cuando las 6 filas digan "ya la cambió".**

En `don_chacho/lib/services/auth_service.dart`:

```dart
static const permitirLoginLegacy = false;
```

Buildear y deployar igual que el PASO 5.

**Por qué no se puede saltear.** Un login legacy **no abre sesión de Supabase**, así que
para la base ese usuario sigue siendo nadie. Cuando se encienda RLS (Fase 2), a ese usuario
no le va a dar un error: le va a devolver **todas las tablas vacías**, y la app le va a
mostrar saldos inflados con cara de dato correcto. Apagar el legacy es la condición de
entrada de la Fase 2.

---

## Cómo volver atrás si algo falla a mitad

El orden de los pasos está pensado justo para esto: **hasta el PASO 4 inclusive, la app que
está en producción no se enteró de nada.** Todo lo de la base es aditivo (una columna
vacía, un índice, dos funciones nuevas, dos policies ampliadas): nada reemplaza ni borra
nada de lo que ya andaba.

| Si falla en… | Qué hacer | Qué ve el usuario |
|---|---|---|
| **PASO 1** (migración) | Correr el `drop` de la caja del PASO 1 y parar. | Nada. La app sigue igual. |
| **PASO 2** (crear cuentas) | Seguir en otro momento, o borrar las que creaste (Authentication → el usuario → Delete user). Las que queden creadas y sin vincular **no molestan a nadie**. | Nada. |
| **PASO 3** (vínculo) | Si quedó a medias, se arregla re-corriendo el bloque 5. Para desvincular todo: `update usuarios set auth_id = null;` (el perfil y la cuenta quedan intactos, solo se corta el puente). | Nada. |
| **PASO 4** (bucket) | Para volver a como estaba: las dos policies originales están en `supabase_migration_soporte.sql`, bloque 3. Correrlas de nuevo. | Nada. |
| **PASO 5** (deploy) y la app no deja entrar a nadie | **Rollback del deploy**: Vercel → Deployments → el deployment anterior (`web-99unb7xxw`, v19.15) → **Promote to Production**. Vuelve el login viejo, que nunca dejó de funcionar porque los `password_hash` siguen ahí. | Unos minutos de login raro. Después, todo como antes. |
| **PASO 5** y entra alguno pero no otro | **No hace falta rollback.** El que no entra, entra con su contraseña **vieja** (red del legacy). Revisar en Authentication → Users que su mail esté bien escrito y volver a correr el bloque 5. | Entra con la contraseña de siempre. |
| **PASO 6** y alguien perdió su contraseña temporal | Authentication → Users → el usuario → **Reset password** (o Delete user y crearlo de nuevo, y volver a correr el bloque 5). | Entra con la contraseña vieja mientras tanto. |
| **PASO 7** y alguien queda afuera | Volver `permitirLoginLegacy = true`, buildear y deployar. O más rápido: rollback del deploy en Vercel. | Vuelve a entrar con la contraseña vieja. |

**El rollback que NO hay que hacer:** borrar `usuarios.auth_id` con la app nueva deployada.
Ahí sí nadie entra por el camino nuevo, y si además apagaste el legacy, nadie entra por
ningún lado. Si hay que tocar la columna, **primero** rollback del deploy en Vercel.

---

## Chequeo final (cuando todo terminó)

```sql
-- Los 6 vinculados y los 6 con la contraseña cambiada
select usuario,
       case when auth_id is null then 'SIN CUENTA' else 'vinculado' end as identidad,
       case when coalesce(password_hash, '') = '' then 'ya la cambió' else 'todavía no' end as pass
from usuarios order by usuario;
```

Las 6 filas: `vinculado` + `ya la cambió`. Más `permitirLoginLegacy = false` deployado.

Con eso la Fase 1 está cerrada y se puede empezar a escribir las políticas — leyendo antes
el punto 6 de `auth_fase1_diseno.md`, que es donde están las tres cosas que van a doler.

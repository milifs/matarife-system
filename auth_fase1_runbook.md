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

## PASO 4 bis — Correr la migración del dueño del ticket (2 min)

SQL Editor → correr `supabase_migration_soporte_reportado_por_id.sql` **completa** (la
columna, el índice y el backfill; son las secciones 1 y 2).

Por qué acá: **el bundle de v19.16 manda siempre `reportado_por_id` al dar de alta un
ticket**, así que sin esta columna reportar un problema empieza a fallar en cuanto deployes.
Es el mismo patrón que las migraciones 18 y 19 del depósito: la lectura tolera que la
columna no esté, la escritura no.

Después del backfill, correr la verificación de la sección 3:

```sql
SELECT CASE WHEN reportado_por_id IS NULL
            THEN 'sin vincular' ELSE 'vinculado' END AS estado,
       count(*)
FROM soportes
GROUP BY 1;
```

Si aparece algún **"sin vincular"**, mirá con qué nombre quedó guardado (la segunda consulta
de esa sección) y asignalo a mano. No se pierde — vos lo seguís viendo en la bandeja, y ahí
figura como "(no lo ve en su lista)" — pero **a su autor deja de aparecerle en "mis últimos
reclamos"**, porque desde v19.16 esa lista filtra por el id y ya no por el nombre.

Esto también **tiene que correrse antes del PASO 5**.

---

## PASO 4 ter — Correr el permiso de los kg (1 min)

**Solo si la PR #24 entró en este deploy.** Esta no es de auth: viene de la rama
`feat/kg-semana-secretaria`, que sale en el mismo v19.16. Si todavía no se mergeó, el archivo
no está en el repo y este paso se saltea. Para saberlo, desde la raíz:

```bash
ls supabase_migration_permiso_kg_semana.sql
```

SQL Editor → correr `supabase_migration_permiso_kg_semana.sql` **completa** (el permiso en el
catálogo y sus filas de `rol_permisos`).

Por qué acá: el bundle de v19.16 le muestra las dos tarjetas de kg del Inicio a un no-admin
que tenga el permiso `ver_kg_semana`. Sin la fila en `permisos` el checkbox no aparece en
Gestión de Usuarios, y sin las de `rol_permisos` **la secretaria sigue viendo el Inicio sin
plata**.

Verificación:

```sql
select r.nombre as rol
from rol_permisos rp
join roles r on r.id = rp.rol_id
join permisos p on p.id = rp.permiso_id
where p.nombre = 'ver_kg_semana'
order by 1;
```

Tienen que aparecer el rol de admin y **Secretaria**. Si Secretaria no aparece, en esta
instalación el rol está con otro nombre: la migración lo busca **por nombre** y no por su id
fijo, a propósito, así que mirá cómo se llama y corré esa parte a mano.

**Esta es la única de las tres que no rompe nada si falta**, y por eso es la más fácil de
pasar por alto: no toca ninguna tabla de datos, nadie recibe un error y la app anda igual.
Lo que pasa es que deployás y **el pedido de Joaquín queda sin hacer**, en silencio. Si te
diste cuenta después del deploy, corrés la migración y listo: no hace falta buildear de nuevo.

---

## PASO 5 — Deployar la app (10 min)

Recién acá cambia algo para los usuarios.

**Antes de buildear, que estas tres estén corridas.** Las dos primeras no son opcionales: la
app nueva ya cuenta con ellas y sin ellas una pantalla falla.

| Tiene que estar corrida | Si falta | |
|---|---|---|
| El **bloque 6** del PASO 4 (policies del bucket de soporte) | adjuntar una foto a un reclamo, y verla, dejan de andar | **rompe** |
| La **24**, `soportes.reportado_por_id` (PASO 4 bis) | reportar un problema deja de andar — justo la pantalla que se usa cuando algo anda mal | **rompe** |
| La **27**, `ver_kg_semana` (PASO 4 ter), si la PR #24 entró | la secretaria sigue viendo el Inicio sin plata | no rompe, **y no avisa** |

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

El orden de los pasos está pensado justo para esto: **hasta el PASO 4 ter inclusive, la app
que está en producción no se enteró de nada.** Todo lo de la base es aditivo (dos columnas
vacías, dos índices, dos funciones nuevas, dos policies ampliadas y las filas del permiso
nuevo): nada reemplaza ni borra nada de lo que ya andaba.

| Si falla en… | Qué hacer | Qué ve el usuario |
|---|---|---|
| **PASO 1** (migración) | Correr el `drop` de la caja del PASO 1 y parar. | Nada. La app sigue igual. |
| **PASO 2** (crear cuentas) | Seguir en otro momento, o borrar las que creaste (Authentication → el usuario → Delete user). Las que queden creadas y sin vincular **no molestan a nadie**. | Nada. |
| **PASO 3** (vínculo) | Si quedó a medias, se arregla re-corriendo el bloque 5. Para desvincular todo: `update usuarios set auth_id = null;` (el perfil y la cuenta quedan intactos, solo se corta el puente). | Nada. |
| **PASO 4** (bucket) | Para volver a como estaba: las dos policies originales están en `supabase_migration_soporte.sql`, bloque 3. Correrlas de nuevo. | Nada. |
| **PASO 4 bis** (dueño del ticket) | Es aditivo: la columna vacía y un índice. Para volver atrás: `drop index if exists idx_soportes_reportado_por_id;` y `alter table soportes drop column if exists reportado_por_id;`. **Pero si ya deployaste, no la borres**: sin la columna el alta de tickets falla. Primero rollback del deploy. | Nada, mientras no hayas deployado. |
| **PASO 4 ter** (permiso de los kg) | Es la más fácil de deshacer: `delete from rol_permisos where permiso_id = (select id from permisos where nombre = 'ver_kg_semana');` y después `delete from permisos where nombre = 'ver_kg_semana';`. Se puede hacer con la app nueva deployada sin romper nada — la secretaria vuelve a ver el Inicio sin plata, que es lo que ve hoy. | Nada. |
| **PASO 5** (deploy) y la app no deja entrar a nadie | **Rollback del deploy**: Vercel → Deployments → el deployment anterior (`web-99unb7xxw`, v19.15) → **Promote to Production**. Vuelve el login viejo, que nunca dejó de funcionar porque los `password_hash` siguen ahí. | Unos minutos de login raro. Después, todo como antes. |
| **PASO 5** y entra alguno pero no otro | **No hace falta rollback.** El que no entra, entra con su contraseña **vieja** (red del legacy). Revisar en Authentication → Users que su mail esté bien escrito y volver a correr el bloque 5. | Entra con la contraseña de siempre. |
| **PASO 6** y alguien perdió su contraseña temporal | Authentication → Users → el usuario → **Reset password** (o Delete user y crearlo de nuevo, y volver a correr el bloque 5). | Entra con la contraseña vieja mientras tanto. |
| **PASO 7** y alguien queda afuera | Volver `permitirLoginLegacy = true`, buildear y deployar. O más rápido: rollback del deploy en Vercel. | Vuelve a entrar con la contraseña vieja. |

**Los dos rollbacks que NO hay que hacer:** borrar `usuarios.auth_id` con la app nueva deployada.
Ahí sí nadie entra por el camino nuevo, y si además apagaste el legacy, nadie entra por
ningún lado. Y borrar `soportes.reportado_por_id` con la app nueva deployada: ahí nadie
puede reportar un problema, que es justo la pantalla que se usa cuando algo anda mal. En los
dos casos, si hay que tocar la columna, **primero** rollback del deploy en Vercel.

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

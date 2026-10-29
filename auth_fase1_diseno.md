# Identidad de Supabase Auth — diseño (Fase 1)

Estado: **escrito, nada corrido todavía**. La migración la corre Mili y el deploy también.
Fecha: 28/10/2026. Verificado contra producción ese día.

---

## 1. Qué arregla esta fase y qué no

**El problema.** La base no sabe quién pregunta. La app se conecta siempre con la
publishable key (que viaja dentro de `main.dart.js` y es pública), el login es propio
(`usuarios.password_hash`, SHA-256 **sin sal**) y la sesión es el id del usuario guardado
en el navegador. Para Postgres todas las consultas llegan como el mismo rol `anon`, sin
nombre y sin dueño: `auth.uid()` devuelve NULL siempre. **Sin eso no hay política de RLS
posible** — no se puede escribir "el cobrador ve los pagos" si la base no puede saber que
el que pregunta es el cobrador.

Hoy, además, todas las tablas de negocio tienen RLS **deshabilitado**: con la key sola, por
la API REST, se leen 108 clientes, 1871 pagos, 1087 remitos, cargas, notas de crédito y
débito, y los tickets de soporte. Y como RLS está apagado, también se puede escribir y
borrar. Los gates de permisos que ya existen (v19.14) tapan botones, no datos.

**Lo que hace esta fase.** Le da a cada usuario una identidad real de `auth.users`, cambia
el login para que la sesión sea la de Supabase, y deja escritas las dos funciones que las
políticas de la fase siguiente van a usar para traducir "quién sos" a "qué podés hacer".

**Lo que NO hace esta fase, a propósito: no enciende RLS en ninguna tabla.** Encender RLS y
crear las identidades el mismo día no deja red: si una política sale mal, el negocio queda
sin poder trabajar y no hay forma de saber si el problema es la política o la identidad.
Primero todos entran con su cuenta nueva y se verifica que entran; después se escriben las
políticas. Y hay un agravante de calendario: **jueves, viernes y sábado son días de
reparto**. Ver `auth_fase1_staging.md`.

---

## 2. Mapeo de cada usuario a una identidad de Supabase Auth

Los 6 usuarios de `usuarios` al 28/10/2026, leídos de producción:

| Usuario | Nombre completo | Rol | Activo | Mail sintético de la cuenta |
|---|---|---|---|---|
| `admin` | Administrador | Administrador (`es_admin`) | sí | `admin@donchacho.local` |
| `rociolopez` | Rocio Lopez | Secretaria | sí | `rociolopez@donchacho.local` |
| `solealcala` | soledad Alcalá | Secretaria | sí | `solealcala@donchacho.local` |
| `artur` | Arturo Aguilera | Cobrador | sí | `artur@donchacho.local` |
| `mili` | Mili Prueba | Secretaria | sí | `mili@donchacho.local` |
| `rocio_cejas` | Rocio Cejas | Encargado de Deposito | sí | `rocio_cejas@donchacho.local` |

> **Corrección a lo que se venía diciendo:** son 6 usuarios y **los 6 están activos**. No hay
> ninguno inactivo. El que no es una persona del negocio es `mili` / "Mili Prueba", que es la
> cuenta de prueba de la desarrolladora. El runbook la trata aparte: conviene usarla como
> **conejillo de indias** (es la primera que se migra y la primera que entra), y decidir
> después si se da de baja o se queda como cuenta de prueba.

**La regla del mapeo, en una línea:** el nombre de usuario tal como se escribe hoy en el
login, en minúscula, más `@donchacho.local`.

**Por qué un mail sintético y no pedirles el mail de verdad.** Joaco y las chicas escriben
"rociolopez", no un mail; cambiar eso sería cambiarles el login, que es la única cosa de la
app que hacen todos los días sin pensar. Supabase Auth necesita un identificador con forma
de mail, así que se le da uno: `<usuario>@donchacho.local`. El dominio `.local` **no existe
en internet** a propósito (está reservado para redes locales), así que no son casillas:
nadie puede mandarles un mail, ni pedir un recupero de contraseña por ahí, ni confundirlas
con una dirección real. El `auth_id` que devuelve Auth se guarda en `usuarios.auth_id`.

**Qué pasa con las contraseñas: no se migran.** Hoy son SHA-256 sin sal del password crudo;
Supabase Auth guarda bcrypt. No hay forma de convertir una en la otra (es justamente de lo
que se trata un hash), y no hay que intentarlo: un SHA-256 sin sal de una contraseña corta
se recupera de una tabla arcoíris, así que esas contraseñas hay que dar por **quemadas**,
no por migradas. Cada usuario arranca con una **temporal** que le pasa Mili y la cambia la
primera vez que entra. Ver `auth_fase1_runbook.md`.

---

## 3. Cómo queda el login

### 3.1 La pantalla no cambia

Sigue pidiendo **usuario y contraseña**. Ni Joaco ni las chicas ven la diferencia: adentro,
`AuthService.login` arma el mail sintético y llama a `signInWithPassword`.

### 3.2 El camino nuevo

```
login("rociolopez", "…")
  └─ signInWithPassword("rociolopez@donchacho.local", "…")
       ├─ anduvo  → busca el PERFIL por usuarios.auth_id = auth.uid()
       │             ├─ perfil activo → adentro (rol + permisos cargados)
       │             └─ no hay perfil, o está inactivo → signOut y afuera
       └─ falló   → login legacy (transitorio, ver 3.4)
```

Dos decisiones que importan:

- **La identidad y el perfil están separados.** `auth.users` dice *quién sos*;
  `usuarios` + `roles` + `rol_permisos` siguen diciendo *qué podés hacer*. El catálogo de
  permisos no se toca: son los mismos 14 de siempre y Gestión de Usuarios sigue siendo la
  pantalla donde se asignan.
- **Identidad sin perfil activo = afuera, con la sesión cerrada.** Si alguien tiene cuenta
  de Auth pero nadie la vinculó, o el admin lo dio de baja, no se lo deja entrar a medias:
  una sesión sin rol es una sesión que no sabe decir qué puede hacer. Y dar de baja a
  alguien en Gestión de Usuarios tiene que cerrarle la puerta de verdad, no esconderle los
  botones (las funciones SQL del punto 4 chequean `activo` por lo mismo).

### 3.3 La sesión pasa a ser la de Supabase

- `AuthService.restaurarSesion()` mira `auth.currentSession` (el SDK la persiste y la
  refresca solo) y de ahí saca el perfil por `auth_id`. Ya no lee el id del usuario de
  SharedPreferences.
- `main.dart` se suscribe a `AuthService.cambiosDeSesion` (`onAuthStateChange`) y, cuando
  llega `signedOut`, saca al usuario a la pantalla de login. Eso cubre el token revocado,
  el vencido que no se pudo refrescar y el cierre de sesión desde otra pestaña — tres casos
  en los que antes la app se quedaba adentro, mostrando datos viejos, sin poder leer nada
  nuevo.
- `AuthService.cerrarSesion()` hace `signOut()` y además limpia la clave vieja de
  SharedPreferences.

### 3.4 El login legacy, y por qué sigue ahí unos días

`AuthService.permitirLoginLegacy` es una constante en `true`. Mientras valga `true`, un
usuario **sin** cuenta de Auth todavía puede entrar con su contraseña vieja.

Está por una razón concreta: **crear las 6 cuentas y deployar la app no pueden pasar en el
mismo instante.** Entre una cosa y la otra hay una ventana de minutos u horas; sin la red
del legacy, cualquiera que intente entrar en esa ventana se queda afuera. Con la red, la
migración se puede hacer de a un usuario, en orden, verificando.

**Hay que apagarlo antes de encender RLS, y es importante entender por qué.** Un login
legacy no abre sesión de Supabase: `auth.uid()` queda NULL. Con RLS encendido ese usuario
no recibiría un error — recibiría **todas las tablas vacías**, y la app le mostraría saldos
inflados (ver punto 6). El runbook tiene el paso de apagarlo y es condición de entrada de
la Fase 2.

### 3.5 Cambio de contraseña

`AuthService.cambiarPassword(perfil, actual, nueva)`:

1. Verifica la actual con un `signInWithPassword` — `updateUser` **no** la pide, y sin esa
   vuelta cualquiera que agarre un celular desbloqueado se queda con la cuenta.
2. `auth.updateUser(password: nueva)`.
3. **Borra el `password_hash` viejo** (lo deja en `''`). Deja de servir para algo y deja de
   ser un dato robable: `usuarios` se lee con la publishable key sola. Un hash vacío no
   coincide con ningún SHA-256, así que además le cierra a ese usuario la puerta del login
   legacy — cada usuario que cambia su contraseña apaga su propia retaguardia.

Devuelve un `ResultadoCambioPassword` y no un bool, porque "la actual está mal" y "tu
cuenta todavía no existe" se arreglan de formas distintas y el usuario tiene que poder leer
cuál de las dos le pasó.

**Pantalla nueva: "Cambiar contraseña"**, en el menú del `+`, **para todos los roles**
(mismo criterio que Soporte). Hasta ahora `cambiarPassword` existía en el servicio y
**ninguna pantalla lo llamaba**: era código muerto. Sin esta pantalla, la contraseña
temporal del runbook no se podría cambiar nunca.

### 3.6 Alta de usuarios: queda en dos pasos

Crear una identidad de Auth necesita la **service key**, y una service key dentro de un
bundle web sería una llave maestra pública — mucho peor que el problema que esto vino a
arreglar. Así que:

- **La app** crea y edita el **perfil** (nombre, usuario, rol, activo). El campo de
  contraseña **se fue** del editor; en su lugar hay un aviso con el mail exacto de la
  cuenta que hay que crear.
- **El dashboard de Supabase** crea la **cuenta de acceso**, y el bloque 5 de la migración
  la vincula sola por el mail (nadie copia UUIDs a mano).
- En la lista de usuarios, el que no tiene cuenta vinculada aparece marcado **SIN CUENTA**
  en naranja. Hoy eso significa "entra por el legacy"; cuando se encienda RLS va a
  significar "no puede trabajar", así que conviene que se vea.

Automatizar el alta en un paso es posible con una Edge Function que tenga la service key.
Queda anotado para la Fase 3: son 6 usuarios y el alta de uno nuevo pasa cada varios meses,
así que no justifica una función más para mantener ahora.

---

## 4. Las funciones que van a usar las políticas

`supabase_migration_auth_identidad.sql` deja dos, las dos `SECURITY DEFINER` y `STABLE`:

| Función | Devuelve |
|---|---|
| `es_admin()` | `true` si el que consulta es un usuario **activo** con rol `es_admin` |
| `tiene_permiso(text)` | `true` si el que consulta es un usuario **activo** cuyo rol tiene ese permiso del catálogo (el admin tiene todos) |

Las dos resuelven por `auth.uid()` contra `usuarios` y, sin sesión, devuelven **false**.

Cuatro detalles que no son de adorno:

- **`SECURITY DEFINER` evita una recursión infinita.** En la Fase 2, `usuarios` y `roles`
  también van a tener RLS. Una política de `pagos` que llame a `tiene_permiso()` tendría
  que leer `usuarios`, lo que dispara la política de `usuarios`, que vuelve a preguntar
  quién es... Es el error clásico de RLS en Supabase. Con `SECURITY DEFINER` la función
  corre como su dueño y saltea las políticas de las tablas que lee.
- **`STABLE` la hace barata.** Postgres la llama una vez por consulta en vez de una vez por
  fila: con 1871 pagos la diferencia es entre una llamada y 1871.
- **`SET search_path` es obligatorio con `SECURITY DEFINER`.** Sin él, quien pueda crear un
  esquema planta una tabla `usuarios` propia y hace que la función conteste lo que le
  convenga.
- **`es_admin` tiene que decir lo mismo que la app.** En Dart, `Rol.tienePermiso` devuelve
  true a cualquier permiso si el rol es admin, sin necesidad de la fila en `rol_permisos`.
  La función hace lo mismo (`r.es_admin OR EXISTS …`). Si no coincidieran, el dueño vería
  un botón que la base le rechaza.

También: un índice **UNIQUE** en `usuarios(auth_id)`. Unique y no común porque dos perfiles
con la misma identidad harían que `es_admin()` dependa de cuál fila devuelve Postgres
primero, y eso es exactamente el tipo de permiso que no se puede dejar al azar. En Postgres
un índice UNIQUE deja pasar todos los NULL que haga falta, así que los perfiles sin cuenta
todavía no se estorban.

---

## 5. Matriz de rol × tabla

Esta es la matriz que la **Fase 2** va a implementar como políticas. Sale del catálogo de
permisos que ya existe: **no hay ningún permiso nuevo acá**. Lo único que se agrega es la
columna "permiso que manda", que dice de dónde sale cada celda.

Es una **propuesta revisable**, no algo ya corrido: escribirla antes de las políticas es
justamente para poder discutirla sin que nadie se quede sin trabajar.

**Leyenda**

| Código | Significa |
|---|---|
| `—` | Nada: ni lee ni escribe |
| `L` | Solo lectura |
| `L+A` | Lee y da de alta (insert) |
| `L+AM` | Lee, alta y modifica (update) |
| `L+AMB` | Todo, incluida la baja (delete) |

**Roles** (los de producción hoy): **ADM** Administrador (`es_admin`) · **SEC** Secretaria ·
**COB** Cobrador · **DEP** Encargado de Depósito.

Permisos de cada rol, tal como están en `rol_permisos` hoy:

- **ADM**: los 14 (y `es_admin`, que le da todos por definición)
- **SEC**: `crear_remito`, `editar_remito`, `crear_pago`, `gestionar_clientes`,
  `gestionar_vendedores`, `ver_consultas`, `gestionar_proveedores`, `gestionar_deposito`
- **COB**: `crear_pago`, `editar_pago`, `gestionar_clientes`, `gestionar_vendedores`,
  `ver_consultas`
- **DEP**: `gestionar_deposito` (uno solo)

### 5.1 Circuito comercial

| Tabla | ADM | SEC | COB | DEP | Permiso que manda |
|---|---|---|---|---|---|
| `vendedores` | L+AMB | L+AMB | L+AMB | L | Lectura: cualquier usuario (los nombres salen en filtros y en el reparto). Escritura: `gestionar_vendedores` |
| `clientes` | L+AMB | L+AMB | L+AMB | L | Lectura: cualquier usuario (la Lista de reparto es para todos y necesita los nombres). Escritura: `gestionar_clientes` |
| `remitos` | L+AMB | L+AM | L | **—** | Lectura: **regla del saldo** (abajo) ∨ `crear_remito`. Alta: `crear_remito` ∨ `confirmar_remito` (confirmar una NDP **crea** un remito). Modif.: `editar_remito` ∨ `confirmar_remito`. Baja: `eliminar_remito` |
| `remito_items` | L+AMB | L+AM | L | **—** | Sigue a `remitos` (los ítems no tienen vida propia) |
| `pagos` | L+AMB | L+A | L+AB | **—** | Lectura: **regla del saldo** (abajo). Alta: `crear_pago`. Baja: `editar_pago`. **No hay modificación: los pagos no se editan** (generaba errores de saldo) |
| `pago_medios` | L+AMB | L+A | L+AB | **—** | Sigue a `pagos` |
| `notas_credito_debito` | L+AMB | L+A | L+AB | **—** | Igual que `pagos`: mueve el saldo de un cliente. Lectura: **regla del saldo**. Alta: `crear_pago` (gate de la pantalla desde v19.14). Baja: `editar_pago` |
| `notas_pedido` | L+AMB | L+AMB | L | — | Lectura: `crear_remito` ∨ `confirmar_remito` ∨ `ver_consultas`. Alta: `crear_remito`. Modif.: `editar_remito` ∨ `confirmar_remito`. Baja: `editar_remito` |
| `nota_pedido_items` | L+AMB | L+AMB | L | — | Sigue a `notas_pedido` |
| `costos_semana` | L+AMB | — | — | — | `gestionar_costos` (lectura incluida: el costo es margen, y Ganancias y el dashboard ya son solo del dueño desde v19.14) |

#### La regla del saldo

> **Todo permiso que abra una pantalla donde se vea un saldo tiene que dar lectura sobre
> las TRES tablas de las que el saldo está hecho** — `remitos`, `pagos` y
> `notas_credito_debito` (más sus tablas de ítems) — porque
> `saldo = remitos confirmados − pagos ± notas`. Hoy eso son cuatro permisos:
>
> ```
> ver_consultas  ∨  crear_pago  ∨  gestionar_clientes  ∨  gestionar_vendedores
> ```
>
> Los dos últimos no son obvios y es justamente por eso que la regla se escribe acá en vez
> de repetir una lista en cada fila: la pestaña **Clientes** (gate `gestionar_clientes`)
> muestra el saldo de cada cliente en pesos, y la pestaña **Vendedores** (gate
> `gestionar_vendedores`) muestra el saldo de cada vendedor. Un rol con `gestionar_clientes`
> y **sin** `ver_consultas` vería esa columna de pesos con `pagos` denegado, o sea mal, sin
> que nada avise.
>
> Con los cuatro roles que existen hoy esto no se nota, porque los tres que llegan a esas
> pestañas tienen además `ver_consultas`. **Pero los roles son configurables**: el admin
> crea roles con permisos a la carta desde Gestión de Usuarios, así que un rol armado
> mañana puede caer exactamente en ese hueco. Una política no se escribe para los roles que
> hay, se escribe para los que el admin puede armar.
>
> Corolario para la Fase 2: si alguna vez hay que esconderle de verdad la deuda de la
> cartera a un rol, **no alcanza con sacarle `ver_consultas`** — hay que sacarle también la
> pestaña que muestra el saldo. Es el mismo criterio que ya está escrito para Saldos en
> `CLAUDE.md`: el camino es un permiso nuevo, no estirar uno existente.

### 5.2 Compras y depósito

| Tabla | ADM | SEC | COB | DEP | Permiso que manda |
|---|---|---|---|---|---|
| `proveedores` | L+AMB | L+AMB | — | **—** | `gestionar_proveedores`. Ver la nota de la PR #20 abajo |
| `cargas` | L+AMB | L+AMB | — | **—** | `gestionar_proveedores`. Ver la nota de la PR #20 abajo |
| `carga_pagos` | L+AMB | L+AMB | — | — | `gestionar_proveedores` (el depósito no mira la plata que se le paga al proveedor) |
| `deposito_config` | L+AMB | L+AMB | — | L+AMB | `gestionar_deposito` |
| `deposito_movimientos` | L+AMB | L+AMB | — | L+AMB | `gestionar_deposito` |

> **Estas cuatro celdas dependen de la PR #20** ("el depósito es el registro de lo que hay,
> no se reconcilia contra remitos"). Ahí `cargarDeposito` pasó a leer **solo**
> `deposito_config` y `deposito_movimientos`: ya no lee `cargas`, ni `proveedores`, ni
> `remitos`. Verificado en esa rama.
>
> Es un recorte real y bienvenido: **el Encargado de Depósito queda sin acceso a nada del
> circuito comercial.** Su acceso completo pasa a ser `deposito_*`, `reparto_*`, `clientes`
> y `vendedores` (para los nombres), `soportes` (los propios) y su propia fila de `usuarios`.
>
> **Si la PR #20 no se mergeara**, hay que devolverle la lectura de esas cuatro tablas o el
> módulo se rompe. Los `ALTER POLICY` exactos están en el encabezado de la sección 4 de
> `supabase_migration_rls_politicas.sql`, y `test/lectura_permitida_test.dart` tiene el caso
> que se pone rojo si una de las dos puntas se mueve sin la otra.

### 5.3 Auditoría — se escribe una vez y no se toca nunca más

| Tabla | ADM | SEC | COB | DEP | Permiso que manda |
|---|---|---|---|---|---|
| `remitos_eliminados` | L+A | L | L | — | Lectura: `ver_consultas`. Alta: `eliminar_remito`. **Modificación y baja: nadie** |
| `pagos_eliminados` | L+A | L | L+A | — | Lectura: `ver_consultas`. Alta: `editar_pago`. **Modif. y baja: nadie** |
| `notas_pedido_eliminadas` | L+A | L+A | L | — | Lectura: `ver_consultas`. Alta: `editar_remito`. **Modif. y baja: nadie** |
| `notas_cd_eliminadas` | L+A | L | L+A | — | Lectura: `ver_consultas`. Alta: `editar_pago`. **Modif. y baja: nadie** |
| `cargas_eliminadas` | L+A | L+A | — | — | `gestionar_proveedores`. **Modif. y baja: nadie** |
| `carga_pagos_eliminados` | L+A | L+A | — | — | `gestionar_proveedores`. **Modif. y baja: nadie** |
| `deposito_movimientos_eliminados` | L+A | L+A | — | L+A | `gestionar_deposito`. **Modif. y baja: nadie** |

**Nadie puede modificar ni borrar una fila de auditoría, el admin incluido.** Una auditoría
que se puede editar no es una auditoría. El módulo de depósito existe justamente porque una
media res salió de la cámara y nadie pudo decir dónde estaba: el rastro de los borrados es
el que contesta esa pregunta. Si alguna vez hay que limpiar una fila, se hace por SQL desde
el dashboard y queda registrado ahí.

### 5.4 Logística, soporte y el propio sistema de permisos

| Tabla | ADM | SEC | COB | DEP | Permiso que manda |
|---|---|---|---|---|---|
| `reparto_listas` | L+AMB | L+AMB | L+AMB | L+AMB | **Cualquier usuario, a propósito**: es logística sin plata. No tiene gate hoy y no debería tenerlo |
| `reparto_items` | L+AMB | L+AMB | L+AMB | L+AMB | Igual |
| `soportes` | L+AM | L+A | L+A | L+A | Alta: cualquier usuario. Lectura: los **propios** tickets, o todos con `es_admin`. Modificación (respuesta y estado): **solo `es_admin`** (la bandeja de triage ya es solo del admin). Baja: nadie. **Ojo: ver 6.2** |
| `permisos` | L | L | L | L | Catálogo fijo de 14. **Nadie escribe por la app**: se toca por SQL, como se tocó al agregar `gestionar_proveedores` y `gestionar_deposito` |
| `roles` | L+AMB | L | L | L | Lectura: cualquier usuario (la app carga el rol propio al entrar). Escritura: `gestionar_usuarios` |
| `rol_permisos` | L+AMB | L | L | L | Igual que `roles` |
| `usuarios` | L+AMB | L† | L† | L† | Escritura: `gestionar_usuarios`. **† Lectura: solo la fila propia** (el perfil que la app necesita para saber su rol); todas las filas con `gestionar_usuarios`. **Y `password_hash` tiene que dejar de ser legible: ver 6.3** |

---

## 6. Lo que va a doler en la Fase 2 (anotado ahora, a propósito)

### 6.1 `cargarDatos()` trae todo, y bajo RLS una tabla denegada vuelve VACÍA, no con error

**Es el problema más grave de la fase que viene y hay que resolverlo antes de encender nada.**

`AppProvider.cargarDatos()` trae once tablas de una (vendedores, clientes, remitos, pagos,
pagos eliminados, remitos eliminados, notas de pedido, notas de pedido eliminadas, costos
de la semana, todos los costos, notas de crédito/débito) y después calcula los saldos.

Bajo RLS, una tabla que el rol no puede leer **no devuelve un error: devuelve una lista
vacía**. Y los saldos se calculan así:

```
saldo del cliente = suma de sus remitos confirmados − suma de sus pagos
```

Con `pagos` vacío, esa resta se convierte en "saldo = todo lo que se le remitió alguna vez".
**Todos los saldos se mostrarían inflados**, con cara de dato correcto.

**Ya pasó algo así**: en v18.22 el límite de 1000 filas de PostgREST cortó la lista de pagos
y los saldos aparecieron mal sin que nada avisara. La diferencia es que esta vez el recorte
sería sistemático y por rol.

**Hoy el peligro está latente, no a la vista — y conviene no confundir las dos cosas.** Con
los cuatro roles que existen, el único al que la matriz le niega `pagos` es el Encargado de
Depósito, y resulta que **no entra a ninguna pantalla que muestre un saldo**: su rol tiene
un solo permiso, así que ve la pestaña Inicio y nada más, y desde v19.14 Inicio sin ser
admin es un saludo sin plata (`home_screen.dart:102`). Las ocho pantallas que muestran
saldos están todas detrás de `gestionar_clientes`, `gestionar_vendedores`, `crear_pago`,
`ver_consultas` o `es_admin`.

Así que el saldo inflado **no se vería** el día que se enciendan las políticas. Lo que lo
hace peligroso es otra cosa, y es peor: está a **un tilde de distancia**. Alcanza con que
alguien le dé a ese rol `ver_consultas` para mirar algo, o que se cree un rol nuevo (ver la
regla del saldo en 5.1), y los números salen mal sin ninguna señal. Y conviene recordar que
hasta **v19.14, hace una versión**, ese mismo rol **sí** veía el saldo total a cobrar y la
deuda de cada vendedor en el dashboard. Lo que hoy tapa el agujero es un gate de UI de una
semana, no una propiedad del sistema.

Por eso esto se arregla antes y no después: el costo de arreglarlo ahora es un rato de
provider, y el de arreglarlo cuando se note es un cobrador que salió a cobrar con números
que no eran.

Lo que hay que hacer en la Fase 2, en este orden:

1. **El provider tiene que distinguir "sin permiso" de "sin datos".** Hoy no puede: las dos
   cosas llegan como `[]`. Lo más barato es que cada carga se acompañe de lo que el perfil
   tiene permitido (`tienePermiso('…')` ya está en el provider) y que una tabla que el rol
   **no** puede leer quede marcada como *no disponible*, no como vacía.
2. **Un número que depende de una tabla no disponible no se muestra.** No se muestra un cero
   ni un saldo a medias: se muestra "no disponible". Un número que parece exacto y no lo es
   es peor que no mostrarlo — es el mismo criterio que ya se usó con los kilos del depósito
   (`mediasSinPesar`).
3. **No pedir lo que no se puede leer.** Es más rápido y evita el falso vacío de entrada.
   Hoy `cargarDatos()` le trae pagos y notas de crédito al Encargado de Depósito, que no
   entra a ninguna pantalla que los use.

### 6.2 `soportes` no tiene con qué identificar al dueño del ticket

La política "cada uno ve sus propios tickets" necesita comparar contra algo estable, y hoy
`soportes.reportado_por` es **texto con el nombre completo** (`"Rocio Lopez"`), no un id:
`soporte_form_screen.dart:63` filtra con `getTicketsSoporte(reportadoPor:
usuario.nombreCompleto)`.

Hoy eso **funciona** — los seis nombres completos son distintos, Rocio Lopez y Rocio Cejas
incluidas. Pero no aguanta una política, por tres razones:

- **`nombre_completo` no es único** y nada impide que lo sea: son dos personas escribiendo
  un nombre en un formulario. El día que se repita, cada una ve los tickets de la otra.
- **Renombrar a alguien le borra su historia.** Cambiarle el nombre completo en Gestión de
  Usuarios le hace perder todos sus tickets anteriores, sin aviso.
- **Depende de tildes y mayúsculas.** `"soledad Alcalá"` está guardado así, con minúscula y
  con tilde. Cualquier corrección cosmética de ese nombre rompe el match.

La Fase 2 tiene que agregar `soportes.reportado_por_id UUID REFERENCES usuarios(id)` (o
directamente el `auth_id`), backfillear lo que se pueda por nombre y dejar la columna de
texto para lo viejo. Es una migración chica, pero tiene que estar **antes** de la política.

### 6.3 `usuarios.password_hash` tiene que desaparecer

Mientras el login legacy exista, el hash tiene que seguir siendo legible para poder
comparar. Pero `usuarios` se lee con la publishable key sola y el hash es SHA-256 **sin
sal**: una contraseña débil se recupera de una tabla arcoíris en segundos.

Secuencia: los 6 usuarios cambian su contraseña (y `cambiarPassword` va borrando los hashes
de a uno) → se apaga `permitirLoginLegacy` y se deploya → **se borra la columna**
(`ALTER TABLE usuarios DROP COLUMN password_hash`) y se saca `hashPassword` del código. Eso
cierra el agujero del todo, y no antes.

### 6.4 Lo que ya cambia en esta fase: el bucket de soporte

Las policies del bucket `soporte-adjuntos` (v18.36) están escritas `TO anon`, porque hasta
hoy la app se conectaba siempre como `anon`. **Con sesión de Supabase Auth las consultas
pasan a llegar como `authenticated` y esas policies dejan de matchear**: adjuntar la foto de
un reclamo y firmar el link para verla fallarían el día del deploy.

El bloque 6 de la migración las reescribe `TO anon, authenticated`. Los dos roles: `anon`
para los que todavía entren por el legacy, `authenticated` para los que ya tengan cuenta.
Esto no contradice el "no se habilita RLS en esta fase" — `storage.objects` tiene RLS
siempre encendido porque es de Supabase, no del negocio; es mantener funcionando lo que ya
estaba.

### 6.5 Las Edge Functions no se tocan (y siguen abiertas)

`resolver-maps` y `parse-reparto` se llaman con `http` crudo y la publishable key
hardcodeada, **no** con el JWT de la sesión (está comentado así en
`ruta_cobranza_service.dart` y en `reparto_ia_service.dart`). Así que el cambio de login no
las afecta: siguen andando igual.

Dicho eso: cualquiera con la key puede llamarlas, y `parse-reparto` consume la
ANTHROPIC_API_KEY del proyecto. No es de esta fase, pero queda anotado — pasarlas al JWT de
sesión es trabajo de la Fase 3.

---

## 7. El plan completo, por fases

| Fase | Qué hace | Estado |
|---|---|---|
| **1 — Identidad** | `auth_id` + `es_admin()` + `tiene_permiso()`, login por Supabase Auth, 6 cuentas creadas y vinculadas, contraseñas temporales cambiadas, legacy apagado | **esta PR** (SQL escrita sin correr) |
| **2 — Políticas** | Arreglar `cargarDatos()` (6.1) y `soportes.reportado_por_id` (6.2); escribir las políticas de la matriz del punto 5, **con la regla del saldo de 5.1 y no fila por fila**; encender RLS **tabla por tabla**, empezando por las que no bloquean el reparto, nunca un jueves, viernes o sábado | pendiente |
| **3 — Cerrar lo que queda** | Borrar `password_hash` (6.3); alta de usuarios en un paso con Edge Function; Edge Functions con JWT de sesión (6.5); revisar si `mili` sigue existiendo | pendiente |

**Condiciones para empezar la Fase 2** (las tres, no dos de tres):

1. Los 6 usuarios entran con su cuenta de Auth y ya cambiaron la contraseña temporal.
2. `permitirLoginLegacy` está en `false` y deployado.
3. Hay dónde probar las políticas sin tocar producción. Ver `auth_fase1_staging.md`.

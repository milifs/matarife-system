# GRANJA DON CHACHO — Módulo Matarife / Venta de Medias Reses a Terceros

## CONTEXTO

App Flutter Web para gestionar la venta de medias reses a carnicerías terceras. Joaco es el dueño, está en Buenos Aires, Argentina. No es desarrollador — necesita instrucciones paso a paso. Comunicación en español argentino informal (vos/tenés). Sin emoticones. Respuestas concisas.

## STACK TÉCNICO

- **Flutter web** (Dart) — NO Android/iOS nativo (Flutter 3.41.8)
- **Supabase** (PostgreSQL + Storage + Edge Functions)
- **Edge Function `resolver-maps`** (runtime nuevo `withSupabase`): resuelve links cortos de Google Maps (`maps.app.goo.gl`) del lado del servidor para la ruta de cobranza (v18.16)
- **Edge Function `ocr-remito`**: sigue deployada en Supabase pero **YA NO SE USA** (el OCR de remitos por foto fue eliminado del cliente en v18.17). Se puede borrar del dashboard cuando se quiera.
- **Vercel** para deploy (PWA instalable en iPhone)
- **Paquetes**: supabase_flutter, provider, intl ^0.20.2, uuid, pdf, printing, url_launcher, http, crypto, shared_preferences, image_picker (`image_picker` se había **removido** en v18.17 con el OCR y **volvió en v18.36** para adjuntar la foto del reclamo de soporte)

## CREDENCIALES

- Supabase URL: `https://svgvyukjqfjkxtypgobq.supabase.co`
- Supabase publishable key: `sb_publishable_NQBeEO7_QtErbs056UE1Wg_kJKHZjbf`
- ANTHROPIC_API_KEY: configurada como secret en Supabase Edge Functions
- Proyecto Windows: `C:\App Joaco\don_chacho_v17\don_chacho` (fuera de OneDrive)
- Flutter instalado en: `C:\Users\admin\Flutter\flutter\bin`
- App en producción: `https://web-six-indol-svg13avcfl.vercel.app`

## REGLAS DE NEGOCIO

- **Vendedores** = comisionistas independientes SIN comisión, solo organizan cartera de clientes
- **Saldo vendedor** = suma de deudas de todos sus clientes
- **Efectivo/cheque**: entran al 100%
- **Transferencia**: descuento interno 6.2% (5% rentas + 1.2% CyD) — NO aparece en recibos ni PDFs para el cliente
- **Tipos de carne (v18.17)**: catálogo fijo en el dropdown de remito y de NDP → `Novillo`, `Cerdo`, `Pierna mocha`, `Pierna pistola`, `Plancha de asado`, `Octavo`, `1/4 delantero`. Los cinco cortes son todos **de Novillo**.
- **Agrupación Novillo/Cerdo para reportes (v18.17)**: dashboard, Ganancias y Comisiones separan en dos baldes por costo. Regla: **solo "Cerdo" cuenta como Cerdo; todo el resto (Novillo y sus cortes) computa como Novillo**. Ver `_normalizarTipo` en app_provider y `costoPorTipo` en models.
- **Auto-sugerencia por peso**: en el formulario de remito manual, al cargar los kg de una media se **sugiere** el tipo (>60kg = Novillo, ≤60kg = Cerdo), pero es editable con el dropdown.
- **Formato pesos**: $100.000 sin decimales, sin abreviar (no "K"/"M")
- **FIFO**: pagos se aplican a remitos del más viejo al más nuevo
- **Solo remitos con estado 'confirmado' cuentan para saldos** (los pendientes/rechazados no afectan)
- **Costo por kg**: carga manual semanal, separado Novillo vs Cerdo. Se usa para calcular ganancia.

## SISTEMA DE USUARIOS Y PERMISOS

### Login
- Usuario + contraseña. **La identidad la pone Supabase Auth** (Fase 1 de auth, rama `feat/auth-identidad-supabase`): el usuario se traduce a un **mail sintético** `<usuario>@donchacho.local` y se entra con `signInWithPassword`. El rol y los permisos siguen viviendo en `usuarios` / `roles` / `rol_permisos`, y `usuarios.auth_id` une las dos mitades.
- **La sesión es la de Supabase** (`onAuthStateChange`), no el id guardado en SharedPreferences. Un token revocado o vencido saca al usuario a la pantalla de login.
- **Login legacy transitorio**: `AuthService.permitirLoginLegacy` (en `true`) deja entrar con la contraseña vieja (SHA-256) a quien todavía no tenga cuenta de Auth. **Hay que apagarlo antes de encender RLS**: un login legacy no abre sesión, así que `auth.uid()` queda NULL y bajo RLS ese usuario vería **todas las tablas vacías**, no un error.
- **Las contraseñas viejas no se migran** (SHA-256 sin sal vs. bcrypt). Cada usuario arranca con una temporal y la cambia desde `+` → **Cambiar contraseña** (pantalla nueva, para todos los roles). Al cambiarla, `cambiarPassword` **borra el `password_hash` viejo**: deja de servir y deja de ser robable.
- **El alta de usuarios queda en dos pasos**: la app crea el perfil (nombre, rol, activo) y el dashboard de Supabase la cuenta de acceso — crear una identidad de Auth necesita la service key, que no puede viajar en un bundle web. El editor ya no pide contraseña; muestra el mail que hay que crear, y la lista marca **SIN CUENTA** a quien no esté vinculado.
- Documentación de la fase: `auth_fase1_diseno.md` (diseño + matriz rol × tabla), `auth_fase1_runbook.md` (migración de las 6 cuentas, paso por paso y cómo volver atrás), `auth_fase1_staging.md` (dónde probar las políticas). Todo en la raíz del repo.
- Usuario inicial: `admin` / `admin123`
- **IMPORTANTE**: Las tablas `usuarios`, `roles`, `rol_permisos`, `permisos` tienen RLS deshabilitado. Se corrió en Supabase:
```sql
ALTER TABLE usuarios DISABLE ROW LEVEL SECURITY;
ALTER TABLE roles DISABLE ROW LEVEL SECURITY;
ALTER TABLE rol_permisos DISABLE ROW LEVEL SECURITY;
ALTER TABLE permisos DISABLE ROW LEVEL SECURITY;
```

### 14 Permisos (catálogo fijo en tabla `permisos`)
`crear_remito`, `usar_ocr`, `confirmar_remito`, `editar_remito`, `eliminar_remito`, `crear_pago`, `editar_pago`, `gestionar_clientes`, `gestionar_vendedores`, `gestionar_costos`, `ver_consultas`, `gestionar_usuarios`, `gestionar_proveedores`, `gestionar_deposito`
- **`usar_ocr` quedó obsoleto en v18.17** (el OCR fue eliminado). Sigue en el catálogo pero ya no controla ninguna UI. Se puede borrar del catálogo cuando se quiera.
- **`gestionar_proveedores` (v19)** habilita la tab Proveedores (compra de animales vivos + pagos al proveedor). Es el permiso de la cajera.
- **`gestionar_deposito` (v19.5)** habilita Depósito (stock de medias reses) en el menú del FAB. La migración lo asigna a los roles admin **y** a los que ya tenían `gestionar_proveedores`: es la misma persona, la cajera carga la compra y es la que saca la carne de la cámara.

### Qué tapa cada gate (v19.14)
- **El dashboard entero** (`home_screen`) pide `esAdmin`. No es por permiso sino por rol, igual que los tabs de plata de Consultas (v19.2/v19.3): es la plata del negocio de conjunto.
- **La Nota de crédito / débito** pide `crear_pago`. Mueve el saldo de un cliente igual que un pago y la pantalla muestra el saldo actual; estaba **sin ningún gate** desde v18.21. `crear_pago` la deja donde estaba (admin, Secretaria, Cobrador) y la saca del Encargado de Depósito.
- **La Lista de reparto y Soporte siguen sin gate**, a propósito: la primera es logística sin plata y la segunda tiene que estar para todos, que es justamente de lo que se quejaría el que no puede trabajar.
- **Ojo: todos estos gates son de UI.** Las tablas tienen RLS deshabilitado y la app se conecta con la publishable key, así que los datos igual viajan al navegador y cualquiera con la key los puede leer por la API REST. El gate frena al usuario común, no a alguien que quiera mirar. Cerrar eso de verdad es RLS + auth de Supabase, que es otro proyecto.

### Roles
- Flexibles: el admin puede crear roles personalizados con permisos a la carta
- Default: **Administrador** (es_admin=true, todos los permisos) y **Secretaria** (crear_remito + ver_consultas — ver_consultas se asigna manualmente desde Gestión de Usuarios)
- No se puede borrar/desactivar el propio usuario admin (protección contra auto-lockout)

### Flujo de confirmación de remitos
1. Admin crea remito → queda directamente `confirmado` → afecta saldos
2. Secretaria carga Nota de Pedido (NDP) → queda `pendiente` → NO afecta saldos
3. Admin ve bandeja → puede **confirmar** (convierte NDP en Remito R-XXXX), **editar** o **rechazar** (con motivo)
4. Solo remitos `confirmado` cuentan para saldos y ganancias

## ESTRUCTURA DEL PROYECTO (~12.500 líneas, 26 archivos .dart — `ocr_service.dart` eliminado en v18.17)

```
don_chacho/lib/
├── main.dart                          # Login + sesión + tabs dinámicas por permisos + menú de acciones del FAB (admin: remito + NDP; secretaria: NDP)
├── models/models.dart                 # Vendedor, Cliente, Remito, RemitoItem, Pago, PagoMedio, CostoSemanal, NotaPedido, NotaPedidoItem, NotaCreditoDebito, RepartoLista, RepartoItem, Permiso, Rol, Usuario, RemitoEliminado, PagoEliminado, Proveedor, Carga, CargaPago, CargaEliminada, CargaPagoEliminado
├── providers/app_provider.dart        # Estado global, FIFO, saldos, permisos, usuarioActual, NDPs
├── services/
│   ├── auth_service.dart              # Login SHA-256, sesión persistente SharedPreferences, CRUD usuarios/roles
│   ├── database_service.dart          # CRUD Supabase para todo + confirmarNotaPedido (convierte a remito) + getRepartoLista/getRepartoListaOPlantilla/guardarReparto
│   ├── estado_cuenta_service.dart     # PDF estado de cuenta + reporte vendedor + reporte cliente (movimientos) + PDF nota de pedido + comisión
│   ├── reparto_service.dart           # PDF de la lista de reparto para el repartidor. **Uno por mercadería** (v19.12): se le pasa el `tipo` y arma la hoja de CARNE o la de CERDO, con TOTAL MEDIAS, SOBRANTE DEPÓSITO y las notas del día — v18.24
│   ├── recibo_service.dart            # PDF recibo de pago con detalle deuda FIFO
│   ├── carga_pdf_service.dart         # PDF de una carga de proveedor (v19)
│   └── ruta_cobranza_service.dart     # Ruta de cobranza: extrae coords (incl. DMS), GPS web, resuelve links cortos vía Edge Function resolver-maps, orden vecino-cercano, URL Google Maps multi-parada (v18.14, ampliado v18.16)
├── screens/
│   ├── login_screen.dart              # Usuario + contraseña
│   ├── home_screen.dart               # Dashboard KPIs por tipo carne, navegación semanal < >, botón costos (con permiso)
│   ├── detalle_kg_semana_screen.dart  # Desglose de la tarjeta de kg del dashboard (v19.10): a qué clientes fue esa carne, medias, kg e importe, con los remitos de cada uno
│   ├── vendedores_screen.dart         # Lista vendedores
│   ├── vendedor_detalle_screen.dart   # Detalle + reporte PDF vendedor; tap en cliente abre ClienteDetalleScreen; muestra "N remitos vencidos" por cliente
│   ├── clientes_screen.dart           # Lista clientes; muestra "N remitos vencidos" por cliente (rojo si >0)
│   ├── cliente_detalle_screen.dart    # Todos los remitos (sin límite), stat "Vencidos" en resumen, estado de cuenta, clickeable para editar. Teléfono = link directo a WhatsApp (v18.23)
│   ├── remito_form_screen.dart        # Carga manual (OCR eliminado en v18.17), solo para admin. Dropdown de tipo de carne (7 opciones)
│   ├── nota_pedido_form_screen.dart   # Carga NDP para secretaria: filas dinámicas con kg/media, cliente de lista o texto libre. Dropdown de tipo de carne por fila (v18.17, reemplazó la descripción libre)
│   ├── pago_form_screen.dart          # Múltiples medios, búsqueda cliente A→Z, ver/eliminar (NO editar — genera errores de saldo)
│   ├── nota_cd_form_screen.dart       # Registrar Nota de Crédito / Débito (v18.21): SegmentedButton tipo, búsqueda cliente, saldo actual→resultante, monto, motivo. Botón "Guardar + Enviar" que comparte el comprobante PDF al registrar (v18.31). Accesible desde el FAB por todos los roles
│   ├── consultas_screen.dart          # 5 tabs: Vencidos (1°), Ganancias, Saldos, Historial (remitos+pagos+NDPs), Directorio. Vencidos: lista todos los remitos vencidos con FIFO, resumen count+deuda total. Historial: onTap guarda por permiso (editar_remito/editar_pago); Saldos: tap a pago requiere crear_pago
│   ├── costos_semana_screen.dart      # Historial costos, editar con alerta semana vieja
│   ├── gestion_usuarios_screen.dart   # CRUD usuarios + roles con permisos checkboxes
│   ├── bandeja_remitos_screen.dart    # 3 tabs: Notas de Pedido (1°) / Remitos pendientes / Rechazados
│   ├── reparto_screen.dart            # Lista de reparto semanal (Jueves/Viernes/Sábado, v19.11): navegación semanal < >, **dos tablas por día** (CARNE y CERDO) que se ven **de a una, con su propio selector** (v19.12), cada una con su TOTAL MEDIAS manual, sus clientes y su SOBRANTE auto; notas del día y **un PDF por tabla** (v19.12). Se precarga con la lista de la semana anterior si la semana está vacía (v18.30). Módulo logístico aparte (sin plata). Accesible desde el FAB (v18.24)
│   ├── soporte_form_screen.dart       # Reportar un problema (v18.36): módulo del sistema, descripción, switch "no puedo seguir trabajando", foto adjunta. Al guardar muestra un diálogo con botón "Abrir WhatsApp" (v18.37: el launch tiene que salir de un toque, si no el navegador lo bloquea). Lista los últimos 5 reclamos propios con estado y respuesta. Accesible desde el FAB por todos los roles
│   ├── proveedores_screen.dart        # Tab Proveedores (v19, permiso gestionar_proveedores): resumen "se le debe a proveedores", filtro por proveedor, lista de cargas PP-XXXX con A pagar / Pagado / Falta pagar. Ícono en el AppBar → ABM de proveedores. Carga los datos con lazy load (cargarProveedores)
│   ├── gestion_proveedores_screen.dart # ABM de proveedores (v19): nombre + tipo novillo/cerdo (v19.1) + desvaste % + precio kg vivo + rinde asegurado % (los tres numéricos son los DEFAULTS que se copian a la carga; el tipo NO) + switch activo. No se puede borrar un proveedor con cargas: hay que desactivarlo
│   ├── carga_form_screen.dart         # Alta/edición de carga (v19) = bloque Faena del Excel. Al elegir proveedor copia sus defaults (solo en alta). Panel en vivo con kg neto / rinde / TOTAL A PAGAR. Eliminar exige motivo (queda en cargas_eliminadas)
│   ├── carga_detalle_screen.dart      # Detalle de carga (v19) espejo del Excel: FAENA (con atajo "Cargar faena" para el kg media res) / PAGOS (saldo anterior arrastrado → pagos → SALDO) / DIFERENCIA DE RINDE. Registrar pago en bottom sheet (fecha, medio, monto); tap a un pago lo edita o lo elimina con motivo
│   ├── deposito_screen.dart       # Depósito (v19.5, reescrito en v19.16): libro de stock de medias por tipo con el desglose (arranque + entradas − salidas), veredicto del recuento (faltan / sobran / dan redondos), botones Entrada y Salida, recuento físico e historial. **No mira cargas ni remitos.** Lazy (`cargarDeposito`)
│   └── bandeja_soporte_screen.dart    # Bandeja de soporte (v18.36, solo admin): 3 tabs Abiertos / En revisión / Resueltos con contadores. Detalle con foto (link firmado), campo de respuesta y botones de estado
└── utils/
    ├── app_config.dart                # Config por deploy vía --dart-define (v18.36): version, clienteNombre, soporteWhatsapp
    ├── lectura_permitida.dart         # Qué tablas puede leer un rol (Fase 2 de auth). Decisión PURA y testeable, como version_check.dart. **Espejo de las políticas SQL**
    ├── formatters.dart                # formatPesos, formatKg, formatPorcentaje, formatFecha, formatFechaHora, formatRangoSemana, MilesInputFormatter/parseNumero/textoMiles
    └── theme.dart                     # AppTheme + StatusPill widget + StatusType enum
```

## BASE DE DATOS (Supabase PostgreSQL)

### Tablas principales
- `vendedores` (id, nombre, apellido, telefono, creado_en)
- `clientes` (id, vendedor_id, nombre_razon_social, telefono, plazo_pago_dias, ubicacion, ubicacion_url, creado_en)
- `remitos` (id, cliente_id, fecha, numero, foto_url, total_kg, total_pesos, estado, creado_por, confirmado_por, confirmado_en, motivo_rechazo, creado_en)
- `remito_items` (id, remito_id, tipo_carne, cantidad_medias, kg_total, precio_por_kg)
- `pagos` (id, cliente_id, fecha, numero, monto_total, neto_recibido, `saldo_anterior` [nullable], `saldo_nuevo` [nullable], creado_en) — saldo_anterior/saldo_nuevo se guardan al crear el pago para que los recibos PDF reimpresos muestren los saldos históricos correctos (v18.11)
- `pago_medios` (id, pago_id, medio, monto, neto_recibido)
- `costos_semana` (id, semana_inicio, costo_por_kg [nullable legacy], costo_por_kg_novillo, costo_por_kg_cerdo, creado_en)

### Tablas de auditoría (eliminados, v18.11)
- `remitos_eliminados` (id UUID PK, remito_id, cliente_id, fecha, numero, total_kg, total_pesos, eliminado_en, eliminado_por TEXT) — RLS deshabilitado
- `pagos_eliminados` (id UUID PK, pago_id, cliente_id, fecha, numero, monto_total, medios JSONB, observacion, eliminado_en, eliminado_por) — RLS deshabilitado
- Al eliminar un remito o pago, antes de borrarlo se inserta una fila en la tabla de auditoría correspondiente (consultable en Consultas > Eliminados)

### Tablas de permisos (v17)
- `permisos` (id TEXT PK, nombre, descripcion) — 12 permisos predefinidos
- `roles` (id UUID, nombre UNIQUE, es_admin BOOLEAN, creado_en)
- `rol_permisos` (rol_id, permiso_id) — relación N:N con CASCADE
- `usuarios` (id UUID, usuario UNIQUE, password_hash, rol_id FK, nombre_completo, activo, creado_en, **`auth_id` UUID nullable REFERENCES auth.users ON DELETE SET NULL** con índice UNIQUE — Fase 1 de auth). `password_hash` queda solo para el login legacy y **se borra en la Fase 3**.
- **Funciones `security definer` para las políticas de la Fase 2**: `es_admin()` y `tiene_permiso(text)`, que resuelven por `auth.uid()` contra `usuarios`. Son `SECURITY DEFINER` para evitar la recursión infinita (una política de `pagos` que lea `usuarios` dispararía la política de `usuarios`, que vuelve a preguntar quién es) y `STABLE` para que Postgres las llame una vez por consulta y no una por fila. **La Fase 1 NO habilita RLS en ninguna tabla.**

### Tablas Notas de Pedido (v18)
- `notas_pedido` (id UUID PK, numero INT, fecha DATE, cliente_id UUID nullable FK, cliente_nombre_libre TEXT nullable, estado TEXT pendiente/confirmado/rechazado, motivo_rechazo, creado_por, confirmado_por, confirmado_en, remito_id UUID nullable FK, total_kg, total_pesos, creado_en)
- `nota_pedido_items` (id UUID PK, nota_pedido_id FK CASCADE, descripcion TEXT, cantidad_medias INT, kgs_por_media JSONB array, precio_por_media NUMERIC, total_kg, total_pesos)
- Ambas tablas con RLS deshabilitado

### Tablas Notas de Crédito / Débito (v18.21)
- `notas_credito_debito` (id UUID PK, cliente_id UUID FK, tipo TEXT CHECK IN ('credito','debito'), fecha DATE, numero INT, monto NUMERIC, motivo TEXT, registrado_por TEXT, creado_en TIMESTAMPTZ) — index en cliente_id, RLS deshabilitado
- `notas_cd_eliminadas` (auditoría de notas borradas) — RLS deshabilitado
- **NC** resta al saldo (a favor del cliente, como un pago); **ND** suma (cargo extra, como un remito). Numeración NC-XXXX / ND-XXXX, secuencia separada por tipo.

### Migraciones SQL (ya corridas en Supabase, en orden)
1. `supabase_schema.sql` — esquema inicial
2. `supabase_migration_fase2.sql` — pagos + medios
3. `supabase_migration_numeracion.sql` — campo numero en remitos y pagos
4. `supabase_fix_costo_nullable.sql` — columna costo_por_kg nullable + default 0
5. `supabase_migration_v17_usuarios.sql` — usuarios, roles, permisos, estado remitos, RLS disabled
6. `supabase_migration_v18_notas_pedido.sql` — tablas notas_pedido + nota_pedido_items
7. `supabase_migration_indices.sql` — 6 índices de performance (v18.10)
8. Columnas `saldo_anterior` / `saldo_nuevo` en `pagos` (v18.11) — agregar manualmente en SQL Editor si no existen
9. Tabla `pagos_eliminados` (v18.11) — auditoría de pagos borrados
10. `supabase_migration_remitos_eliminados.sql` — tabla `remitos_eliminados` de auditoría (v18.11, en raíz del repo)
11. `supabase_migration_ndp_tipo_carne.sql` — columna `tipo_carne` en `nota_pedido_items` (v18.19)
12. `supabase_migration_notas_credito_debito.sql` — tablas `notas_credito_debito` + `notas_cd_eliminadas` (v18.21)
13. `supabase_migration_reparto.sql` — tablas `reparto_listas` + `reparto_items` (v18.24, en raíz del repo)
14. `supabase_migration_soporte.sql` — tabla `soportes` + bucket `soporte-adjuntos` + policies (v18.36, en raíz del repo). Ya corrida el 07/10/2026.
15. `supabase_migration_proveedores.sql` — tablas `proveedores` + `cargas` + `carga_pagos` + auditoría, y el permiso `gestionar_proveedores` (v19, en raíz del repo). Ya corrida el 20/10/2026.
16. `supabase_migration_proveedor_tipo.sql` — columna `tipo` (`novillo` / `cerdo`) en `proveedores` + CHECK + índice (v19.1, en raíz del repo). Ya corrida el 20/10/2026.
17. `supabase_migration_deposito.sql` — tablas `deposito_config` + `deposito_movimientos` + auditoría, y el permiso `gestionar_deposito` (v19.5, en raíz del repo). Ya corrida el 26/10/2026.
18. `supabase_migration_deposito_kg.sql` — columna `kgs_por_media` JSONB en `deposito_movimientos` y en su tabla de auditoría (v19.6, en raíz del repo). **Hay que correrla ANTES de deployar v19.6**: desde v19.6 el `toMap()` manda siempre esa columna, así que sin la migración todo alta de movimiento falla.
19. `supabase_migration_deposito_arranque_kg.sql` — columnas `kg_novillo` / `kg_cerdo` en `deposito_config` (v19.9, en raíz del repo). Ya corrida el 28/10/2026. Era **prerequisito del deploy de v19.9**: igual que la anterior, `DepositoConfig.toMap()` manda siempre esas columnas, así que sin la migración guardar el arranque falla.
20. `supabase_reset_deposito.sql` — **no es una migración, es un reset de una sola vez** (raíz del repo): borra todos los movimientos de depósito y su auditoría y deja el arranque en 0 medias / 0 kg con fecha de hoy, para empezar la carga de nuevo. No toca remitos ni cargas: el depósito no guarda stock, lo deriva, así que mover la fecha de arranque alcanza para que lo viejo deje de contar. Se corrió DESPUÉS de la 19, el 28/10/2026.
21. `supabase_migration_reparto_sabado_tipo.sql` — el día `'sabado'` en el CHECK de `reparto_listas` y la columna `tipo` en `reparto_items`, con el backfill que parte en dos las filas que traían carne y cerdo juntos (v19.11, en raíz del repo). **Prerequisito del deploy de v19.11**: desde v19.11 `RepartoItem.toMap()` manda siempre `tipo` y la pantalla guarda el sábado, así que sin la migración guardar el reparto falla.
22. `supabase_migration_reparto_columnas_extra.sql` — `columnas_extra` JSONB en `reparto_listas` y `extras` JSONB en `reparto_items` (v19.13, en raíz del repo). **Prerequisito del deploy de v19.13**: desde v19.13 el `toMap()` de los dos manda siempre esas columnas.
23. `supabase_migration_auth_identidad.sql` — **NO CORRIDA TODAVÍA**. Fase 1 de auth: `usuarios.auth_id` + índice UNIQUE + `es_admin()` + `tiene_permiso(text)`, el vínculo perfil ↔ cuenta por el mail sintético, y las policies del bucket `soporte-adjuntos` ampliadas a `authenticated`. **No se corre de una**: tiene bloques que van antes y después de crear las cuentas a mano en el dashboard. El orden exacto está en `auth_fase1_runbook.md`. **No habilita RLS.**
24. `supabase_migration_soporte_reportado_por_id.sql` — **NO CORRIDA TODAVÍA**. Fase 2: columna `reportado_por_id UUID REFERENCES usuarios(id)` en `soportes` + índice + backfill por nombre completo **solo cuando el nombre identifica a una sola persona**. Prerequisito de la política `soportes_select`: el dueño del ticket no puede ser un campo de texto que la gente edita.
25. `supabase_migration_rls_politicas.sql` — **NO CORRIDA TODAVÍA**. Fase 2: las políticas de las 29 tablas (la matriz del punto 5 de `auth_fase1_diseno.md`) más las funciones `es_usuario_activo()` y `puede_ver_saldo()`. **Crea las políticas y NO enciende RLS**: en Postgres una política sobre una tabla con RLS apagado existe y se ignora, así que se puede dejar todo creado, ensayarlo y encender después. Los `ENABLE` están **comentados** al final, en cuatro grupos por riesgo.

### Tablas Depósito (v19.5)
- `deposito_config` (id UUID PK, **unica BOOLEAN UNIQUE CHECK (unica)**, fecha_inicio DATE, medias_novillo NUMERIC(12,4), medias_cerdo NUMERIC(12,4), **kg_novillo / kg_cerdo NUMERIC(12,2) DEFAULT 0** (v19.9), registrado_por, actualizado_en) — RLS off. **Una sola fila**, garantizado por el truco de `unica`: es UNIQUE y el CHECK la obliga a ser TRUE, así que un segundo INSERT rebota. El upsert va `onConflict: 'unica'`.
- `deposito_movimientos` (id UUID PK, **numero INT GENERATED BY DEFAULT AS IDENTITY** → `D-0001`, tipo TEXT CHECK IN ('novillo','cerdo'), clase TEXT CHECK IN ('entrada','salida','recuento'), medias NUMERIC(12,4) CHECK >= 0, **kgs_por_media JSONB DEFAULT '[]'** (v19.6), espera_remito BOOLEAN, fecha DATE, observacion, registrado_por, creado_en) — índices en `creado_en DESC` y en (tipo, clase), RLS off.
- `deposito_movimientos_eliminados` — auditoría con `observacion` **obligatoria**. Un movimiento que desaparece sin motivo sería el mismo agujero que el módulo vino a tapar.
- `medias` va **siempre en positivo**: el signo lo pone la `clase`.
- **`espera_remito` quedó sin uso en v19.16** y la app ya no la escribe: se llena con su `DEFAULT TRUE`. Era la marca de "esta salida todavía no tiene remito", que existía solo para el cierre por FIFO contra los remitos. **No se borró la columna** para no pedir una migración por un campo que no molesta; si algún día se limpia, va junto con `usar_ocr` y lo demás que quedó colgado.

### Depósito — el libro de stock (v19.5, reescrito en v19.16)
**Por qué existe**: desde la cámara sacaron dos medias para un cliente y nadie podía decir dónde estaban. Plata perdida. El módulo es el **libro de lo que hay en la cámara**: se carga a mano lo que entra y lo que sale, y el recuento físico dice si el libro y la cámara coinciden.

```
stock = medias del arranque
      + entradas    (lo que llega del proveedor, devoluciones, ajustes)
      − salidas     (se las llevó un cliente, merma, consumo propio)

diferencia = stock al momento del recuento − recuento
  > 0  faltan medias: salieron y nadie las registró
  < 0  hay medias de más que el libro no conoce
  = 0  los números dan redondos
```

- **No cruza NADA con el resto del sistema.** Hasta v19.15 la cuenta sumaba las cargas de proveedores (animales × 2, por el `tipo` del proveedor) y restaba los remitos confirmados convertidos por una tabla de equivalencias de cortes, y avisaba cuando las tres cosas no cerraban. **Eso se sacó en v19.16 por decisión del usuario**: el depósito registra lo que hay, no lo reconcilia con lo que se compró ni con lo que se facturó.
- **Qué se fue con la reconciliación**, porque colgaba de los remitos: la tabla `equivalenciasMedia` y `equivalenciaEnMedias`, `stockDeTipoCarne`, `mediasPorAnimal`, `partesDeCorte` / `CortesVendidos` / `labelParte` (el panel "DISPONIBLE PARA VENDER"), las salidas que esperaban remito con su cierre por FIFO (`_salidasPendientes`, `_remitidasCargadasDespuesDe`) y el atajo "Cargar el remito" de la pantalla.
- **Nada se persiste**: el stock se deriva del arranque + `deposito_movimientos`, así que corregir un movimiento viejo **reacomoda todo solo**. Está en `app_provider`: `stockDeposito` / `_componentesDeposito` / `_ultimoRecuento`.
- **Una sola clase de salida.** Antes una salida era "pendiente de remito" o "definitiva" y la cuenta las trataba distinto. Ahora todas descuentan igual y el motivo vive en la **observación**: sin remitos que las cierren, la distinción no significaba nada.
- **Dos stocks separados** (novillo / cerdo), igual que la Lista de reparto: una media de cerdo no puede tapar un faltante de novillo. El tipo lo elige la cajera en el movimiento (`SegmentedButton`), ya no lo deduce de ningún proveedor ni tipo de carne.
- **El recuento es lo único que sigue siendo una comparación, y se queda.** Es lo que delata a la media que salió sin que nadie la registre, y para eso no hacen falta remitos: alcanza con lo contado a mano contra lo que dice el libro. Se compara contra el stock **DE SU MOMENTO** (`teoricoAlRecuento`, cortando por `creado_en`), no contra el de hoy: si no, un movimiento posterior al último recuento aparecería como diferencia — se cuentan 10 el viernes, el lunes entran 200 y el sistema gritaría "sobran 200 medias".
- **`toleranciaMedias = 0,02`**: las medias se cargan con decimales y la BD las guarda con cuatro, así que una resta puede dejar un resto de coma flotante. Sin ese margen una diferencia de 0,0000000001 encendería la alerta.
- **El stock puede dar negativo y se muestra así.** Físicamente imposible, pero es lo honesto: significa que se cargó una salida sin su entrada. Taparlo con un cero escondería el error de carga, que es justo lo que hay que ver. (`kgTeorico` sí se recorta en 0 — ver más abajo: ahí un negativo significaría otra cosa.)
- **El arranque es obligatorio** (`deposito_config`): se cuenta a mano lo que hay en la cámara un día y esa fecha es el corte; los movimientos anteriores no cuentan. Desde v19.16 **ya no importa qué remitos se cargaron ese día**, así que elegir la fecha dejó de tener trampa (ver "Cómo se carga el arranque").
- **Kg por media (v19.6)**: cada movimiento guarda un array `kgsPorMedia` con un kilo por media, mismo patrón que `nota_pedido_items.kgs_por_media` — un array y no un total, porque dos medias pueden diferenciarse en 40 kg y lo que importa es saber cuál salió y cuál entró. El total (`DepositoMovimiento.totalKg`) se deriva, no se guarda.
  - **Son opcionales a propósito.** Si el campo frenara el registro cuando la cajera no tiene la balanza a mano, no registraría la salida — que es justo el agujero que este módulo vino a tapar. Nada valida que la lista tenga tantos valores como `medias`; `mediasSinPesar` avisa cuántas faltan y la UI lo muestra, pero no bloquea.
  - **Son informativos: el stock cuenta MEDIAS.** Los kilos se muestran pero no disparan la alerta.
  - La lectura (`_leerKgs`) tolera que la columna no exista y que traiga basura: devuelve lista vacía en vez de romper la pantalla.
  - Los campos se generan solos según las medias tipeadas, con tope `_maxCamposKg = 120` para que un error de tipeo ("1000" por "10") no cuelgue la pantalla generando mil campos.
- **Kilos del stock (v19.9)**: la tarjeta muestra los kilos de lo que debería haber en la cámara, con la **misma cuenta que las medias pero en peso**: arranque (`deposito_config.kg_novillo/kg_cerdo`) + kg de las entradas − kg de las salidas. Desde v19.16 no entran ni la faena de las cargas ni los kg de los remitos.
  - **Siguen siendo informativos**: el veredicto sale de las MEDIAS.
  - **El kilaje puede estar incompleto** y se dice en pantalla: `StockDeposito.mediasSinPesar` cuenta las medias de la cuenta que nadie pesó (un movimiento sin balanza, un arranque sin pesar) y la tarjeta muestra "faltan pesar N medias". Un número de kilos que parece exacto y no lo es es peor que no mostrarlo.
  - `kgTeorico` **nunca devuelve negativo**: con los kilos incompletos un negativo no sería un faltante sino lo que falta pesar. Es la diferencia con las medias, donde el negativo sí informa.
  - El único kg que se pesó de verdad es `StockDeposito.kgRecuento` (lo del último recuento); por eso se muestra aparte.
- **Solapamiento con la Lista de reparto**: `reparto_screen` pide el TOTAL MEDIAS **a mano** y calcula SOBRANTE DEPÓSITO = total − repartido. Ese número y el del depósito pueden no coincidir. Precargar el TOTAL MEDIAS desde el stock quedó pendiente, y desde v19.16 tiene más sentido que antes: los dos módulos cuentan ahora lo mismo (medias cargadas a mano) y ninguno mira remitos.

### Tablas Lista de reparto (v18.24, ampliada en v19.11)
- `reparto_listas` (id UUID PK, semana_inicio DATE, dia TEXT CHECK IN ('jueves','viernes',**'sabado'**), total_medias_carne INT, total_medias_cerdo INT, notas TEXT, **columnas_extra JSONB** (v19.13), creado_en, **UNIQUE (semana_inicio, dia)**) — RLS off
- `reparto_items` (id UUID PK, lista_id UUID FK CASCADE, cliente_id UUID FK clientes, **tipo TEXT CHECK IN ('carne','cerdo')** (v19.11), medias_carne INT, medias_cerdo INT, **extras JSONB** (v19.13), sucursal TEXT, orden INT, creado_en) — index en lista_id, RLS off
- **Módulo 100% logístico, aparte del flujo comercial: NO toca plata, saldos ni remitos.** Solo qué carne (novillo=CARNE / cerdo=CERDO) va a cada cliente por semana.
- **El sábado se guarda sin acento** (`'sabado'`), como el resto de los valores de la columna; el acento lo pone `labelDiaReparto` al mostrarlo.
- **Una fila pertenece a UNA tabla** (v19.11): la de `tipo='carne'` usa `medias_carne` y deja `medias_cerdo` en 0, y al revés. Un cliente que lleva de las dos tiene **dos filas**. Las columnas viejas se mantienen para no romper lo que ya estaba guardado, pero la verdad es `tipo` + la columna que le corresponde (`RepartoItem.medias`).
  - **Por qué hace falta la columna y no alcanza con mirar los números**: una fila recién agregada está en cero (el cliente se agrega y las medias se cargan después), y con las dos columnas en 0 al releer no se sabía de qué tabla era.
  - La lectura (`RepartoItem.desdeMap`) **tolera que la columna no exista**: una fila vieja con carne y cerdo juntos se devuelve **partida en dos**, una por tabla. La escritura **no** es tolerante (`toMap()` manda siempre `tipo`), así que la migración es prerequisito del deploy.
- **Columnas extra (v19.13)**: cada tabla puede sumar hasta **dos columnas más al final**, con el encabezado escrito a mano, para lo que se vende suelto y no es una media (una pierna, grasa). `reparto_listas.columnas_extra` guarda los nombres por mercadería (`{"carne": ["Pierna"], "cerdo": []}`) y `reparto_items.extras` los números de cada cliente **en el mismo orden** (`[2, 0]`).
  - **Van por posición y no por nombre** a propósito: así **renombrar el encabezado no pierde** los números ya cargados.
  - **No tienen TOTAL cargado a mano ni sobrante**: no hay stock de "grasa" contra el cual contarlas, así que la fila TOTAL muestra la **suma de lo repartido** y la de SOBRANTE va con una raya. Si alguna vez hace falta un total propio, es otra columna en la lista, no un cambio de criterio.
  - **JSONB y no tablas nuevas**: son como mucho dos columnas por tabla, no se consultan ni se cruzan con nada. Mismo criterio que `kgs_por_media`.
  - La lectura (`_leerColumnas` / `_leerExtras`) tolera que la columna no exista, que venga null o que traiga basura; la escritura no, así que la migración es prerequisito del deploy.
  - **Si el `tipo` y las medias se contradicen, mandan las medias.** Entre correr la migración y deployar v19.11 hay una ventana donde la app vieja sigue guardando **sin** `tipo`, y entonces una fila de cerdo se come el `DEFAULT 'carne'` de la tabla. Leerla como fila de carne en cero haría **desaparecer esas medias de la pantalla**, así que `desdeMap` corrige el tipo mirando en qué columna están las medias. Cubierto por `test/reparto_test.dart`.

### Tabla Soporte (v18.36)
- `soportes` (id UUID PK, **numero INT GENERATED BY DEFAULT AS IDENTITY**, modulo TEXT, descripcion TEXT, bloqueante BOOLEAN, adjunto_path TEXT, estado TEXT CHECK IN ('abierto','en_revision','resuelto'), respuesta TEXT, reportado_por TEXT, rol TEXT, app_version TEXT, plataforma TEXT, creado_en, resuelto_en, resuelto_por) — índices en estado y creado_en, RLS off
- El número de ticket (`S-0001`) lo asigna la **secuencia de Postgres**, no el cliente. Por eso `TicketSoporte.toMap()` omite `numero` cuando vale 0: a diferencia de remitos/pagos/NCD (que hacen max+1 del lado del cliente y tienen carrera), acá no hay chance de duplicados.
- Bucket **privado** `soporte-adjuntos` (10 MB, mime images incl. heic/heif). En la tabla se guarda el **path**, nunca la URL: los links se firman en el momento (90 días) para que un link reenviado por WhatsApp caduque solo, mientras la bandeja siempre puede firmar uno nuevo. Las policies apuntan al rol **`anon`** porque la app se conecta con la publishable key.

### Tablas Proveedores / Cargas (v19)
- `proveedores` (id UUID PK, nombre TEXT, **tipo TEXT CHECK IN ('novillo','cerdo') DEFAULT 'novillo'** (v19.1), desvaste_porcentaje, precio_kg_vivo, rinde_asegurado, activo BOOLEAN, creado_en) — sin CUIT, sin teléfono, sin observaciones (decisión del cliente). Los tres valores numéricos son **defaults**, no la verdad histórica.
- `cargas` (id UUID PK, **numero INT GENERATED BY DEFAULT AS IDENTITY** → `PP-0001`, proveedor_id FK, fecha DATE, cantidad_animales INT, kg_vivo, desvaste_porcentaje, precio_kg_vivo, rinde_asegurado, kg_media_res NUMERIC **nullable**, observacion, registrado_por, creado_en) + 3 columnas **GENERATED ALWAYS AS ... STORED**: `kg_neto`, `total_a_pagar`, `rinde_carga`. Índices en proveedor_id y fecha DESC, RLS off.
- `carga_pagos` (id UUID PK, carga_id FK CASCADE, fecha DATE, medio TEXT CHECK IN ('efectivo','transferencia','cheque'), monto, registrado_por, creado_en) — index en carga_id, RLS off.
- `cargas_eliminadas` / `carga_pagos_eliminados` — auditoría con `observacion` **obligatoria** (la cajera tiene que escribir el motivo). `cargas_eliminadas` guarda además los pagos que se van en cascada, en una columna JSONB.
- **Una carga = una compra de animales vivos a un proveedor** (lo que en el Excel `Proveedores-Pagos.xlsx` era una hoja entera). Plata que SALE. **No tiene nada que ver con el circuito de clientes** (remitos / NDP / pagos): ahí la plata ENTRA.
- Los valores de desvaste / precio / rinde se **copian del proveedor al crear la carga y después quedan congelados y editables ahí**. Así, cuando sube el precio del kg vivo, las cargas viejas no se recalculan.
- **El `tipo` (novillo / cerdo) es la excepción: NO se copia a la carga**, se lee siempre del proveedor. La especie no cambia semana a semana, así que si se cargó mal, corregir el proveedor tiene que arreglar también las cargas viejas. Un proveedor que venda las dos cosas se carga **dos veces**. Se elige con un `SegmentedButton` en el ABM (default novillo) y se ve como pill en la lista y al lado del nombre en el dropdown del formulario de carga. El vocabulario es el mismo de `CostoSemanal.costoPorTipo` (`Proveedor.tipoLabel` → `'Novillo'`/`'Cerdo'`), así el módulo de ganancia va a poder separar **costo/kg novillo de costo/kg cerdo** agrupando las cargas por este campo. `Proveedor.fromMap` tolera que la columna no exista (cae en novillo) para que la app ande antes de correr la migración. Cubierto por `test/proveedor_test.dart`.
- Acá la transferencia **no** tiene el descuento del 6,2%: ese descuento es sobre lo que se COBRA, no sobre lo que se paga. Por eso `carga_pagos` no tiene `neto_recibido`.
- **Columnas generadas**: una columna generada de Postgres no puede referenciar otra columna generada, así que la expresión del kg neto está repetida en las tres. `rinde_carga` divide con `NULLIF(..., 0)`. `Carga.toMap()` nunca manda esas tres columnas (Postgres rechaza la escritura).

### Saldo arrastrado del proveedor (v19)
- El **SALDO A FAVOR nunca se guarda**: se recalcula en cadena, por proveedor, en orden cronológico.
  `saldo de la carga = saldo de la carga anterior del mismo proveedor + pagos de esta carga − total a pagar`
- Negativo = se le debe al proveedor (el caso normal). Positivo = saldo a favor de Joaco. Arrastra con su signo, esté saldada o no la carga anterior.
- Al no persistirlo, corregir una carga vieja o agregar un pago atrasado **reacomoda solas todas las cargas siguientes** de ese proveedor. Está en `app_provider`: `saldoAnteriorDeCarga` / `saldoDeCarga` / `saldoProveedor` / `deudaTotalProveedores`.
- `cargarProveedores({forzar})` es **lazy**: no va en `cargarDatos()`, para no hacerle más lento el login a los roles que no entran al módulo.

### Rinde y diferencia de rinde (v19)
- `kg_neto = kg_vivo × (100 − desvaste) / 100` → es lo que efectivamente se paga.
- `total_a_pagar = kg_neto × precio_kg_vivo`.
- `rinde_carga = kg_media_res × 100 / kg_neto`. **El kg de media res lo carga la cajera después de la faena**: hasta entonces queda NULL y la carga muestra "Falta faena", pero el total a pagar ya está definido.
- Diferencia de rinde contra el `rinde_asegurado` del proveedor: `kg esperados = kg_neto × rinde_asegurado / 100`, `diferencia kg = esperados − obtenidos`, valorizada al precio del kg vivo. Positivo = rindió **menos** de lo prometido. Se ve en el detalle de la carga (la cajera también la ve) y va a alimentar el módulo de ganancia.
- **PDF de la carga** (`carga_pdf_service.dart`, botón en el AppBar del detalle): espejo de la pantalla, FAENA + PAGOS + observación. **El bloque DIFERENCIA DE RINDE solo se imprime si el proveedor rindió de MENOS que el asegurado** (`debeImprimirRinde`), que es cuando hay algo para reclamar; si rindió igual o de más, no va. Ojo con el signo: `diferenciaRindeKg` es **positivo** justamente cuando rindió de menos. Dos trampas de `dart_pdf` que ya están resueltas y conviene no reintroducir: (1) las tarjetas van en `pw.Inseparable` para que no se parta un título de su contenido; (2) como las `Inseparable` no se parten, **una tarjeta más alta que la hoja hace explotar el armado**, por eso la lista de pagos se corta a mano de a 18 por tarjeta. El `pw.Divider` de dart_pdf mide **16 de alto por defecto** (no 1 como en Flutter). Todo cubierto por `test/carga_pdf_test.dart`.
- **Los kilos del bloque de rinde van sin decimales** (`redondearKg` en `models.dart`): los gramos no se discuten con el proveedor y así los tres números cierran a la vista (esperados − obtenidos = diferencia). El criterio es el de la planilla: **de 0,6 para arriba sube, de 0,5 para abajo baja** — NO es el `.round()` de Dart, que también sube el 0,5. `Carga.kgEsperados` ya viene redondeado; si algún cálculo necesita el detalle fino está `kgEsperadosExacto`. Cubierto por `test/formatters_test.dart`.

### MedioPago enum en Dart
`efectivo`, `transferencia`, `cheque`

## FUNCIONALIDADES IMPLEMENTADAS

### Login y Permisos (v17)
- Pantalla de login con usuario + contraseña
- Sesión persistente (SharedPreferences en web = localStorage)
- UI dinámica: tabs del menú inferior se ocultan según permisos
- FAB (+): admin ve "Nuevo remito" **y** "Nueva nota de pedido" (v18.11, ambas opciones); secretaria ve solo "Nueva nota de pedido". La NDP creada por admin también queda `pendiente` hasta confirmarse
- Badge del FAB incluye remitos pendientes + NDPs pendientes

### Dashboard (home_screen)
- **Es del dueño y nada más (v19.14).** Un rol que no sea admin ve un Inicio sin plata: saludo con su nombre y su rol, y a lo suyo por las pestañas o por el botón +. Antes el **saldo total a cobrar** y la **deuda de cada vendedor** los veía cualquier rol, incluido el **Encargado de Depósito**, cuyo rol tiene un solo permiso (`gestionar_deposito`) y para quien Inicio era la única pantalla a la que entraba.
- KPIs de la semana: kg vendidos (novillo/cerdo), venta bruta, ganancia neta
- Cards de kg por tipo muestran también la cantidad de medias reses ("N medias")
- **Las dos cards de kg son tocables (v19.10)**: abren `DetalleKgSemanaScreen` con el desglose de esa semana y ese tipo — clientes ordenados de mayor a menor kg, con medias, kg e importe, y los remitos de cada uno al desplegarlos. Arrastran el estado del ojo (si los valores están ofuscados en el dashboard, también lo están en el desglose)
- **Botón ojo en AppBar (v18.11)**: ofusca todos los valores monetarios y de kg (los reemplaza por `••••`). Toggle `_ofuscado` con ícono visibility/visibility_off. Útil para mostrar la pantalla sin revelar números
- Navegación `<` / `>` para ver KPIs de semanas anteriores (solo admin). `>` deshabilitado en semana actual.
- Saldo total a cobrar + contador de vencidos
- Costo/kg novillo y cerdo con botón "Cargar"
- Botón costos semanales en AppBar (solo con permiso gestionar_costos)

### OCR de remitos (ELIMINADO en v18.17)
- La carga de remitos por foto fue **removida**. Ya no existe `ocr_service.dart` ni la sección de foto en el formulario de remito, ni la dependencia `image_picker`.
- La Edge Function `ocr-remito` sigue deployada en Supabase pero nadie la llama.
- El permiso `usar_ocr` quedó obsoleto (sigue en el catálogo, no controla nada).

### Notas de Pedido (v18)
- **Formulario secretaria** (`nota_pedido_form_screen.dart`): cliente de lista existente O texto libre, fecha, filas dinámicas
- Cada fila: **dropdown de tipo de carne** (v18.17, reemplazó la descripción libre; guarda en el campo `descripcion`), cantidad medias, N campos de kg (uno por media, generados automáticamente según cantidad), precio por media, subtotal calculado
- Guarda como `pendiente` → no afecta saldos
- Soporta modo edición vía `ndpInicial`
- **Bandeja admin** (`bandeja_remitos_screen.dart`, 3 tabs):
  - Tab "Remitos": remitos pendientes de roles no-admin
  - Tab "Notas de Pedido": NDPs pendientes siempre (sin filtro de fecha) + confirmadas hasta 1 día después de `confirmadoEn`. Card muestra por ítem: descripción, total kg y precio/kg. Si el cliente era texto libre, al confirmar se muestra diálogo para asignar cliente de lista (obligatorio)
  - Tab "Rechazados": remitos + NDPs rechazados mezclados
- **Conversión NDP → Remito**: al confirmar se crean remito + remito_items. **tipo_carne = el tipo elegido en el dropdown de la NDP** (v18.17, guardado en `item.descripcion`); si viene vacío (NDPs viejas de texto libre) cae en la regla por peso (promedio kg/media >60 → Novillo, else Cerdo). precio_por_kg = (precio_media × cant_medias) / total_kg
- **PDF NDP** (`estado_cuenta_service.generarPdfNotaPedido`): tabla con columnas Descripción/Medias/Kg por media/Total kg/**Precio por kg.**/Subtotal. Total nota = sum(item.totalKg × item.precioPorMedia). Muestra estado y número de remito generado si confirmada

### PDFs generados (5 tipos)
1. **Recibo de pago** (recibo_service.dart): encabezado con **fecha + hora HH:MM** (de `creado_en`) + medios de pago + total pagado + bloque de saldos (**Saldo anterior − Pago realizado → SALDO RESTANTE TOTAL** + **Saldo vencido** siempre visible) + tabla de detalle de deuda pendiente. **NO** incluye ya la sección "Pagos aplicados" (v18.12). Los saldos son **históricos por pago**: lee `saldo_anterior`/`saldo_nuevo` guardados; si están en NULL reconstruye (remitos confirmados − pagos hasta ese inclusive). La tabla de deuda usa solo los pagos **previos** a este + el pago actual, de modo que el saldo restante, el vencido y la suma de la tabla **concuerdan** entre sí y encadenan entre recibos (saldo anterior de un pago = restante del anterior).
2. **Estado de cuenta cliente** (estado_cuenta_service.dart): remitos pendientes + pagos aplicados FIFO
3. **Reporte vendedor** (estado_cuenta_service.dart): consolidado multi-página por cliente
4. **Nota de pedido** (estado_cuenta_service.dart): detalle kg individuales por media
5. **Reporte cliente** (estado_cuenta_service.dart `generarReporteCliente`, v18.13): replica la tabla del tab Reporte — movimientos unificados (remitos/pagos) con Fecha/ID/Monto ±/Estado/Saldo acumulado, leyenda de colores y saldo pendiente. Se dispara con el botón "Exportar PDF" del tab Reporte

### Consultas (10 tabs para el admin, 6 para el resto — consultas_screen.dart)

**Los tabs se arman por rol (v19.2)**, no son una lista fija. Solo el admin (`app.esAdmin`) ve los cuatro del dueño: **Ganancias** (costo por kg y ganancia), **Cobranzas** (lo que cobró cada cobrador), **Comisiones** (venta por vendedor y liquidación) y **Reporte** (estado de cuenta completo de un cliente).

Los demás roles con `ver_consultas` ven los operativos: **Vencidos**, **Saldos**, **Historial**, **Directorio**, **Ruta** y **Eliminados**.

**`Saldos` está a la vista de todos a propósito**: es lo que mira el cobrador para armarse el recorrido, y Vencidos solo no alcanza porque no muestra al cliente que debe pero todavía está en plazo. Si alguna vez hay que esconderle la deuda de la cartera a un rol, el camino es un permiso nuevo, no mandar Saldos a este gate.
Orden: Vencidos · Ganancias · Saldos · Historial · Directorio · Ruta · Comisiones · Eliminados · Reporte
- **Vencidos** (1° tab): lista todos los remitos vencidos de todos los clientes (FIFO real). Tarjeta resumen con count + deuda total. Ordenados por días vencido desc. Tap abre remito si tiene `editar_remito`. Filtro por vendedor + link Google Maps en cada tarjeta.
- **Ganancias**: rango fechas + atajos, ganancia por tipo carne con costos históricos, ranking vendedor/cliente. Descuenta la comisión de transferencias (6.2%) de la ganancia semanal.
- **Saldos**: por vendedor expandible, FilterChip "Solo vencidos" con FIFO real
- **Historial**: remitos + pagos + NDPs unificados. Chips: Todos / Remitos / Pagos / Notas de Pedido. NDPs muestran badge "NP" y estado. PDF descargable en pagos y NDPs. Tap en pago abre vista solo-lectura (con botón eliminar). NDPs pendientes son clickeables → abre formulario de edición
- **Directorio**: clientes con ubicación y link Google Maps. Filtro por vendedor.
- **Ruta (v18.15)**: arma la **ruta de cobranza**. Filtros: búsqueda por cliente, dropdown por vendedor, FilterChips "Con saldo pendiente" y "Solo vencidos". La lista resultante es de selección (CheckboxListTile por cliente con ubicación; los sin ubicación aparecen deshabilitados con "Sin ubicación cargada"), con "Todos/Ninguno". Botón **"Armar recorrido (N)"**: pide el GPS del navegador, ordena los clientes elegidos por cercanía (vecino más cercano) y abre un panel con la lista numerada de paradas + botón "Abrir en Google Maps" (link `dir/?api=1` con origin=GPS, waypoints y destino). Avisa si hay más de 10 paradas (Maps puede truncar). Reemplaza la versión previa que estaba embebida en Directorio (v18.14).
- **Comisiones**: selección de vendedor + rango fechas, % comisión con cálculo automático, PDF de liquidación
- **Eliminados (v18.11)**: 2 sub-tabs (Pagos / Remitos). Lista de auditoría de pagos y remitos eliminados, con fecha, número, monto y quién/cuándo los borró. Lee de `pagos_eliminados` y `remitos_eliminados`
- **Reporte (v18.11, mejorado v18.13)**: estado de cuenta por cliente en pantalla (selector de cliente A→Z). Tabla unificada de movimientos (remitos en rojo, pagos en verde) ordenados cronológicamente, con columnas Fecha / ID / Monto / Estado / **Saldo acum.** Marca remitos Pagado/Vencido con FIFO. Sin columna Descripción (ajustado para mobile). **v18.13**: leyenda de colores (remito suma / pago resta), signos +/− en los montos, pill "Pago" en la columna Estado (antes quedaba vacía en pagos), header "Saldo" → "Saldo acum." Botón **"Exportar PDF"** arriba a la derecha que genera el mismo reporte en PDF (`generarReporteCliente`)

### Búsqueda de cliente — patrón estándar
Todas las pantallas con selector/filtro de cliente usan el mismo patrón de dos pasos:
1. **TextField "Buscar cliente"**: filtra el dropdown por `contains()` en tiempo real
2. **Dropdown "Cliente"**: lista A→Z filtrada, selección exacta

Pantallas que lo implementan: `remito_form_screen.dart`, `pago_form_screen.dart`, `nota_pedido_form_screen.dart` (modo lista), `clientes_screen.dart` (con opción "Todos"), `consultas_screen.dart` Historial.

### Registrar Pago (pago_form_screen.dart)
- TextField + Dropdown A→Z (patrón estándar, reemplazó al Autocomplete)
- Cuando viene con `clienteInicial` (desde ficha de cliente), muestra cliente fijo
- Muestra el **saldo vencido** del cliente (`app.saldoVencidoCliente`) al seleccionarlo, en rojo si > 0 (v18.11)
- Si falla el guardado del pago, muestra el error en vez de seguir silenciosamente (v18.11)

### Ver/Eliminar Pago (pago_form_screen.dart modo edición)
- **Los pagos NO se pueden editar** — editar causaba errores en saldos. Solo se pueden ver y eliminar.
- En modo edición (`pagoInicial != null`): título "Ver pago", todos los campos son solo-lectura, sin botones de guardar
- Botón eliminar en AppBar requiere permiso `editar_pago`
- Al eliminar: borra `pago_medios` + `pagos` en BD, quita de `_pagos` en memoria, llama `_recalcularSaldos()` → saldo se restaura correctamente

### Editar/Eliminar
- Remitos: desde Historial y ficha del cliente
- Pagos: **solo eliminar** desde Historial (NO editar)
- NDPs: desde Historial (si pendiente) y desde bandeja

### Costos por semana
- Lista semanas cargadas, editor modal, alerta al editar semana vieja

### Proveedores — compra de animales vivos (v19)
- **Circuito aparte del de clientes**: acá la plata SALE (se le compra el animal vivo al proveedor). Remitos, NDP, notas C/D y pagos son el otro circuito, el de los clientes de Joaco.
- Flujo de la cajera: elige el proveedor (se copian desvaste / precio / rinde como defaults editables) → carga animales y kg vivo → queda el **TOTAL A PAGAR** → registra los pagos que Joaco le va haciendo → cuando se faena, completa el **kg de media res** y recién ahí sale el rinde y la diferencia contra el rinde asegurado.
- Puede haber **varias cargas por semana y varios proveedores**. El saldo se arrastra por proveedor, no global.
- Editar y eliminar están habilitados (es la cajera, se equivoca y tiene que poder corregir), pero **toda baja pide motivo** y queda en la tabla de auditoría.

### Depósito — stock de medias reses (v19.5, reescrito en v19.16)
- **Para qué**: saber qué hay en la cámara y que no se pueda perder una media. El recuento físico avisa cuando lo contado no coincide con lo cargado. Ver "Depósito — el libro de stock".
- Flujo de la cajera: el admin fija el **arranque** (fecha + medias contadas en la cámara) → cada vez que entra carne aprieta **Entrada** → cada vez que sale aprieta **Salida** → cada tanto aprieta **Recuento** y el sistema dice si los números dan.
- **Todo se carga a mano, incluida la carne que llega del proveedor.** El módulo no lee las cargas ni los remitos (desde v19.16): si entró, hay que cargarla como Entrada.
- **Una sola clase de salida**: el motivo (se la llevó un cliente, merma, consumo propio) va en la observación y no cambia la cuenta. El switch "el remito se carga después" se fue con la reconciliación.
- Vive en el **menú del FAB**, no en una tab: la barra de abajo ya tiene 5 items y un sexto queda ilegible en el celular. Pasarlo a tab es agregar un `_TabInfo` en `main.dart`.
- Editar y eliminar están habilitados (es la cajera, se equivoca y tiene que poder corregir), pero **toda baja pide motivo** y queda en `deposito_movimientos_eliminados`.
- Cubierto por `test/deposito_test.dart` (46 casos: la cuenta, el veredicto y su tolerancia, los dos stocks, el circuito entrada → salida → recuento, los kg y que no cambien el veredicto).

### Gestión Usuarios y Roles
- CRUD usuarios + roles con permisos checkboxes, protecciones anti-lockout

## LÓGICA FIFO DETALLADA

### Cálculo de saldos (_recalcularSaldos en app_provider)
- Solo remitos con `r.esConfirmado` cuentan
- Saldo cliente = suma remitos confirmados - suma pagos
- Saldo vendedor = suma saldos de sus clientes

### Estado de Cuenta PDF
- Simulación FIFO completa: trackea `remitoRestante[id]` y `pagoRemitosCubiertos[id]`
- Nota "Cubre N remitos" cuando un pago abarca más de uno

### Filtro "Solo vencidos" (clientesConSaldoVencido)
- Aplica FIFO para encontrar el primer remito realmente pendiente (no el más antiguo saldado)
- Fix v16: antes tomaba el remito más antiguo aunque estuviera pagado

## REPOSITORIO

- **GitHub**: https://github.com/milifs/matarife-system
- **Rama principal**: `main`
- **Flujo de trabajo**: siempre crear una rama por feature/fix → Pull Request → merge a main. Nunca commitear directo a main.

```bash
# Clonar el repo (primera vez en una máquina nueva)
git clone https://github.com/milifs/matarife-system.git
cd matarife-system/don_chacho
flutter pub get

# Flujo de cambios
git checkout -b nombre-del-feature   # crear rama
# ... hacer cambios ...
git add <archivos>
git commit -m "descripción del cambio"
git push origin nombre-del-feature
# Abrir Pull Request en GitHub antes de mergear a main
```

## PROCEDIMIENTO DE ACTUALIZACIÓN / DEPLOY

```bash
# Ruta local Mac: /Users/milifernandezsabate/Projects/matarife-system/don_chacho

# 1. Setup inicial (solo la primera vez en máquina nueva)
flutter pub get

# 2. Probar local (modo desarrollo, sin compilar)
flutter run -d chrome

# 3. Compilar para producción (usar el script, NO flutter build web plano)
./build_web.sh         # Mac/Linux
# build_web.bat        # Windows

# 4. Probar build local antes de subir
cd build/web
npx serve .            # abre en http://localhost:3000

# 5. Deployar a Vercel
cd build/web
vercel --prod
```

### Aviso de versión nueva (v19.4)

La app avisa sola cuando el bundle que tiene el usuario quedó viejo: barra roja arriba de todo con **"Hay una versión nueva disponible"** + botón **Actualizar** + una X para posponer.

**Por qué hace falta.** Los headers ya estaban bien: `web/vercel.json` sirve `index.html`, `flutter_bootstrap.js` y `main.dart.js` con `no-cache`, así que una recarga SIEMPRE trae lo nuevo. El problema es que nadie recarga — la app vive como PWA en el iPhone y queda abierta días entre deploys. **No es un problema de service worker**: con `--pwa-strategy=none` el `flutter_service_worker.js` que sale pesa 0 bytes y `index.html` no registra ninguno.

**Cómo funciona.**
- `build_web.sh` escribe `build/web/app_version.json` **después** de compilar (antes se perdería, porque `flutter build web` limpia `build/web`). El valor sale del mismo `AppConfig.version` que viaja compilado adentro del bundle, leído con un grep de `app_config.dart`, así los dos números no pueden discrepar. Si no lo puede leer, **falla el build a propósito**.
- `lib/services/version_service.dart` (web-only, usa `dart:html`) pide ese archivo con `Uri.base.resolve` + un `?t=<millis>` de cache-busting. Sin el `?t=` el navegador contesta el chequeo con su propia copia vieja y no se entera nunca: es el error clásico de este mecanismo.
- `lib/utils/version_check.dart` tiene la decisión pura (`hayVersionNueva`), sin nada de web, para poder testearla. Cubierto por `test/version_check_test.dart`.
- `_MainShellState` chequea al entrar, cada 30 minutos, y **cada vez que la app vuelve del fondo** (`AppLifecycleState.resumed`), que es el momento más probable de que haya salido un deploy.
- **Actualizar** desregistra service workers y borra `caches` antes de recargar. Hoy no hay ninguno, pero los builds anteriores a v18.10 (mayo 2026) se hacían con `flutter build web` pelado, que sí registraba uno; un dispositivo de esa época puede tenerlo todavía, y ahí recargar solo no alcanza.

**La comparación es por igualdad, no por "mayor que"**: alcanza con que los strings difieran. Eso cubre también el rollback, donde la versión publicada es menor y el usuario igual tiene que recargar.

**Ante la duda no se avisa**: sin internet, 404 o JSON roto devuelven null y la barra no aparece. Recargar le tira al usuario lo que tenga a medio cargar, así que un aviso de más es peor que uno de menos.

> **IMPORTANTE**: buildear siempre con `build_web.sh` (o `build_web.bat`). Con un `flutter build web` pelado no se genera `app_version.json` y el aviso deja de funcionar — sin romper nada, pero sin avisar nunca.

### La config de cache vive SOLO en `web/vercel.json`
Existía también un `web/_headers` (formato Netlify / Cloudflare Pages, que **Vercel no lee**) heredado de v18.10, cuando el plan era deployar a Cloudflare. No hacía nada, pero **contradecía a `vercel.json`**: marcaba `main.dart.js` como `immutable` por un año, justo lo contrario del `no-cache` que se sirve de verdad. Se **borró en v19.5** para que haya una sola fuente de verdad.

Si algún día se vuelve a Cloudflare o Netlify, hay que recrearlo — pero copiando los valores de `vercel.json`, no los del archivo viejo: ese `immutable` de un año sobre `main.dart.js`, que no lleva hash en el nombre, haría que un deploy nuevo no le llegue nunca a los usuarios ya cacheados.

### Archivos PWA (web/index.html y web/manifest.json)
- `index.html` tiene splash screen inline (logo + spinner CSS rojo #C62828 + fade-out 300ms). Se oculta con evento `flutter-first-frame`, fallback 8s.
- `index.html` tiene meta tags iOS PWA: `apple-mobile-web-app-capable`, `apple-mobile-web-app-status-bar-style`, `apple-mobile-web-app-title`, viewport con `viewport-fit=cover`
- `manifest.json`: display standalone, theme_color #C62828, orientation portrait-primary
- `web/vercel.json`: los cache headers que se aplican de verdad (ver la sección de más arriba). **Es el único archivo de cache del proyecto.**
- Estos archivos se pisan con `flutter create .` → hay que volver a copiarlos después

### Problemas comunes
- **IDE muestra errores rojos al cambiar carpeta**: `flutter pub add intl:^0.20.2` + `flutter pub get` + VS Code Reload Window (Ctrl+Shift+P → "Reload Window")
- **`flutter` no reconocido en terminal**: agregar `C:\Users\admin\Flutter\flutter\bin` al PATH del sistema. Comando: `[Environment]::SetEnvironmentVariable("Path", $env:Path + ";C:\Users\admin\Flutter\flutter\bin", "User")`
- **Error costo_por_kg NOT NULL**: ya corregido con supabase_fix_costo_nullable.sql
- **RLS bloquea login**: ya deshabilitado para tablas de usuarios/roles/permisos
- **`--web-renderer`** fue eliminado en Flutter 3.41.8 — no usar, da error. El script `build_web.bat` ya no lo incluye.
- **`--pwa-strategy=none`** muestra advertencia de deprecación en Flutter 3.41.8 pero sigue funcionando. Mantener: desactiva el service worker y evita que los usuarios vean versiones viejas en caché.

## HISTORIAL DE VERSIONES

| Versión | Contenido |
|---------|-----------|
| v1-v7 | Fases 1-3: MVP (ABM vendedores/clientes, carga remitos, saldos, dashboard), Pagos+Consultas (múltiples medios, descuento transferencias, recibos PDF, ubicación clientes, costo/ganancia por tipo carne), OCR (lectura automática remitos con foto multi-filas) |
| v8-v13 | Numeración R-0001/P-0001, Estado de Cuenta PDF con FIFO resuelto, ficha cliente, reorganización Consultas, ranking clientes, filtro Solo vencidos |
| v14 | Editar/eliminar remitos+pagos, filtro rango fechas Ganancias, pantalla Costos por semana, menú inferior grande iPhone |
| v15 | Reporte PDF vendedor consolidado, recibo de pago mejorado con detalle deuda FIFO, búsqueda texto + A→Z en Historial |
| v16 | Búsqueda cliente en Crear Remito, fix filtro vencidos FIFO, "Por vencer X d." en PDFs |
| v17 | Login SHA-256 + sesión persistente, roles flexibles con permisos a la carta, confirmación de remitos (pendiente/confirmado/rechazado), UI dinámica por permisos, gestión usuarios/roles, bandeja de aprobación |
| v18 | **Nota de Pedido**: flujo completo secretaria→admin. Formulario NDP con filas dinámicas (kg por media), cliente de lista o texto libre. Bandeja con 3 tabs. Conversión NDP→Remito al confirmar. PDF de NDP. Historial unificado con chip NDP. Filtro A→Z en Registrar Pago. FAB dinámico por rol. |
| v18.10 | **Performance**: splash screen en `index.html`, build scripts (`build_web.bat`/`build_web.sh`), queries post-login en paralelo (`Future.wait`), N+1 remito items → 1 query (`getAllRemitoItems`), N+1 NDP items → 2 queries. Índices SQL en `supabase_migration_indices.sql`. |
| v18.11 (junio) | Recibo unificado con detalle de deuda + saldo vencido; saldos históricos guardados en `pagos`; tab **Reporte** (estado de cuenta por cliente con saldo acumulado); tab **Eliminados** (auditoría de remitos + pagos borrados, tablas `remitos_eliminados`/`pagos_eliminados`); ofuscar KPIs en home; filtro vendedor en Vencidos y Directorio; vendedor en bandeja/PDF de NDP; admin puede crear NDP desde el FAB; varios fixes de recibo FIFO. |
| v18.12 (01/07) | **Recibo de pago corregido y simplificado**: muestra saldo histórico por pago (no el saldo actual), con desglose Saldo anterior − Pago realizado → Saldo restante total + Saldo vencido + tabla de deuda, todo concordante entre sí. Se agrega **hora HH:MM** al encabezado y se quita la sección "Pagos aplicados". Backfill SQL (`supabase_backfill_saldos_pagos.sql`) que rellena `saldo_anterior`/`saldo_nuevo` de todos los pagos viejos. En Historial > Remitos no se puede editar un remito. Remito/NDP/Pago: todos eliminables, consultables en Eliminados y piden observación al borrar. |
| v18.13 (01/07) | **Tab Reporte más legible + exportar PDF**: leyenda de colores, signos +/− en los montos, pill "Pago" en la columna Estado (antes vacía) y header "Saldo" → "Saldo acum." Nuevo botón "Exportar PDF" que genera el reporte por cliente en PDF (`generarReporteCliente`), replicando la tabla en pantalla. Fix menor en `web/index.html` (splash con `pointer-events:none` durante el fade-out). |
| v18.14 (01/07) | **Ruta de cobranza (1ª versión)**: embebida en Consultas → Directorio, combo box (Clientes que deben / Solo remitos vencidos) + botón "Armar". Nuevo `ruta_cobranza_service.dart` (GPS, extracción de coords, orden por cercanía, URL Google Maps). Reemplazada por la tab "Ruta" en v18.15. |
| v18.15 (01/07) | **Ruta de cobranza movida a tab propia "Ruta"** en Consultas (9 tabs). Filtros: cliente (búsqueda), vendedor (dropdown), "Con saldo pendiente" y "Solo vencidos" (FilterChips). Lista con checkboxes para **seleccionar clientes** (los sin ubicación quedan deshabilitados) + "Todos/Ninguno". Botón "Armar recorrido (N)" que calcula la ruta con los elegidos (GPS + orden por cercanía) y abre el panel de paradas → Google Maps. Se quitó el bloque de ruta del Directorio. |
| v18.16 (02/07) | **Fix ubicaciones de la ruta + editar ubicación desde Directorio**: (1) `_parseCoords` reconoce ahora el formato **DMS** (`24°59'04.1"S`). (2) Nueva **Edge Function `resolver-maps`** (runtime nuevo, `withSupabase` con auth `["publishable","secret"]`) que resuelve del lado del servidor los **links cortos** `maps.app.goo.gl` (el navegador no puede por CORS): sigue el redirect y devuelve `lat/lng`, o si el link es un "compartir lugar" sin coords, devuelve la **dirección/nombre** (`q=…`). `RutaCobranzaService.construirParadas()` llama la función en lote para los clientes sin coords locales. `ParadaRuta` gana `direccionResuelta` y usa ese texto como punto ruteable. (3) En **Directorio**, botón de editar ubicación por tarjeta → bottom sheet para cargar/corregir Dirección + Link Maps (guarda con `editarCliente`). |
| v19.16 (29/10) | **El depósito dejó de reconciliarse contra remitos y cargas.** Reportado por el usuario: la pantalla mostraba **−10 medias de novillo** debiendo estar en 0. El diagnóstico fue que la cuenta le restaba un remito confirmado del día (R-1133, 10 medias a Roberto Firme) contra un arranque en cero. La corrección de fondo fue del usuario: **el depósito no tiene que cruzarse con los remitos** — es el registro de lo que hay en la cámara y nada más. Ahora `stock = arranque + entradas − salidas`, todo cargado a mano. Se fueron la tabla de equivalencias de cortes, el cierre por FIFO de las salidas que esperaban remito, el panel de partes sueltas y el atajo "Cargar el remito"; la Salida perdió el switch de "pendiente / definitiva" y el motivo pasó a la observación. **El recuento físico se queda**: es lo que delata la media que salió sin registrarse, y para eso no hacen falta remitos. Sin migración (`espera_remito` queda en la tabla, sin uso). |
| v19.15 (28/10) | **La fecha del PDF de reparto es la del día que se reparte.** El archivo salía `reparto_carne_jueves_26-10-2026` estando a 28: el nombre llevaba el **lunes de la semana** (`semanaInicio`), que no es el día en que sale el camión. El jueves de la semana del 26/10 se reparte el **29/10**. Nuevo `RepartoLista.fecha` (lunes + 3, 4 o 5 según el día), que ahora va en el nombre del archivo **y en el encabezado del PDF** ("CARNE (NOVILLO) — Reparto del Jueves 29/10/2026"), para que el repartidor lea la fecha en la hoja. Sin migración. |
| v19.14 (28/10) | **El dashboard es solo del dueño**, más dos arreglos del reparto que reportó el usuario: la celda de una columna extra **no se dejaba escribir** en un cliente agregado después de crear la columna (la fila nacía sin esos campos), y el botón volvió a decir **"Agregar cliente"** en vez de "Agregar a CARNE". Y las **flechas ↑ ↓ bajan y suben de celda** en la misma columna, para cargar la lista de corrido sin que el tabulador pase por la sucursal y por la cruz de quitar. |
| v19.14 (28/10) | **El dashboard es solo del dueño.** La Encargada de Depósito entraba a la app y la pantalla de Inicio le mostraba el **saldo total a cobrar** del negocio (122 millones) y la **deuda de cada vendedor**. Su rol tiene un solo permiso (`gestionar_deposito`), así que Inicio era su única pantalla y le mostraba justo lo que no tiene que ver. Ahora un rol que no es admin ve un Inicio sin plata. En la misma pasada se tapó un agujero más grave: la **Nota de crédito / débito** estaba en el menú del + **sin ningún gate** desde v18.21, así que ese mismo rol podía ver el saldo de cualquier cliente **y modificarlo**; ahora pide `crear_pago`. Sin migración: ningún rol cambia, cambia lo que la app muestra. |
| v19.13 (28/10) | **Columnas a medida en la lista de reparto.** Cada tabla tiene ahora un **+** que le suma hasta **dos columnas más al final**, con el encabezado escrito a mano: para cuando Joaco vende algo que no es una media (una pierna, grasa, lo que aparezca esa semana) y antes no tenía dónde anotarlo por cliente. Se tocan para renombrarlas o sacarlas, y si tienen cantidades cargadas avisa antes de borrarlas. Salen también en el PDF del repartidor. **No tienen total a mano ni sobrante**: la fila TOTAL muestra la suma de lo repartido, porque no hay stock contra el cual contarlas. Migración `supabase_migration_reparto_columnas_extra.sql` (dos columnas JSONB), prerequisito del deploy. |
| v19.12 (28/10) | **Las dos tablas del reparto, cada una en lo suyo, y la grilla que se lee.** Correcciones sobre v19.11: **líneas de grilla visibles** (horizontales y verticales, de punta a punta) y el renglón **se pinta al pasar el mouse**, con el nombre del cliente en rojo — en una lista larga es lo que dice qué renglón se está por tocar. Además, la carne y el cerdo dejaron de verse apiladas en la misma pantalla y ahora se eligen con un **selector propio**, con el mismo gesto que el día. Y el PDF pasó a ser **uno por tabla** (menú "PDF de CARNE" / "PDF de CERDO"), porque la carne y el cerdo los reparte gente distinta y cada uno se lleva su hoja; el tipo va en el nombre del archivo para distinguirlos en el celular. Las **notas son del día**, así que se ven y se editan desde las dos tablas y salen en los dos PDF. Vuelve el FAB "Agregar a CARNE/CERDO" (con una sola tabla a la vista ya no es ambiguo a cuál se agrega). Sin migración. |
| v19.11 (28/10) | **Lista de reparto: dos tablas, sábado y el día por comando en el asistente.** (1) La pantalla dejó de ser una grilla con dos columnas: ahora son **dos tablas por día**, una de CARNE (novillo) y otra de CERDO, cada una con su TOTAL MEDIAS, sus clientes y su SOBRANTE DEPÓSITO. El PDF del repartidor y la vista del asistente también. (2) El número de medias quedó **alineado con el nombre del cliente** (antes el campo flotaba más arriba por el renglón de la sucursal). (3) Se agregó el **sábado** a los días de reparto. (4) En el chatbot **se quitó el selector Jue/Vie**: el día va por comando y **por pedido**, así una sola frase puede cargar carne para el jueves y cerdo para el sábado ("agregar para Perico 3 medias de carne para el jueves y 5 medias de cerdo para el sábado"); si el comando no dice el día, el asistente lo pregunta antes de guardar en vez de adivinarlo. Columna `tipo` en `reparto_items` + `'sabado'` en el CHECK de `reparto_listas` (`supabase_migration_reparto_sabado_tipo.sql`, prerequisito del deploy). **Hay que redeployar la Edge Function `parse-reparto`.** |
| v19.10 (28/10) | **Desglose de los kg de la semana en el dashboard.** Tocar "Kg novillo semana" o "Kg cerdo semana" abre el detalle de a quién se le vendió esa carne: un cliente por fila (del que más kg se llevó al que menos) con sus medias, sus kg y lo facturado, y al desplegarlo los remitos que lo componen. Los números son **solo los del tipo que se tocó**, así que la suma de la pantalla da exactamente el número de la tarjeta; en los remitos que traen novillo y cerdo juntos se muestra aparte el total de la factura. Nuevas clases `VentaRemitoSemana` / `VentaClienteSemana` / `DesgloseSemanaTipo` y el método `desgloseVentasSemana` del provider. Sin migración. |
| v19.9 (28/10) | **Depósito: kilos a la vista, partes de la media y reset del módulo.** (1) **Kg del stock**: la tarjeta muestra los kilos de lo que debería haber en la cámara, con la misma ecuación que las medias pero en peso, y los kg de cada línea del desglose. Hasta ahora se cargaban media por media y no se mostraban nunca de vuelta. Siguen siendo **informativos** (el veredicto es por medias) y avisan cuándo están incompletos ("faltan pesar N medias"). Nuevas columnas `kg_novillo`/`kg_cerdo` en `deposito_config` para pesar el arranque (`supabase_migration_deposito_arranque_kg.sql`, prerequisito del deploy). (2) **Qué pedazo hay para vender**: la media de novillo se parte en pierna + octavo + plancha de asado, así que remitir una pierna deja un octavo y una plancha sueltos. Panel "DISPONIBLE PARA VENDER" con las medias enteras y las partes sueltas; `partesDeCorte` + `CortesVendidos` en models. El cerdo no se fracciona. (3) **Reset** del módulo a cero (`supabase_reset_deposito.sql`) para empezar la carga de nuevo. |
| v19.4 (26/10) | **Aviso de versión nueva dentro de la app.** Barra arriba de todo con "Hay una versión nueva disponible" + Actualizar + X para posponer. Chequea al entrar, cada 30 min y al volver del fondo. `build_web.sh` escribe `app_version.json` con el mismo `AppConfig.version` del bundle; la app lo pide con cache-busting y compara. **El diagnóstico viejo era equivocado**: no era el service worker (con `--pwa-strategy=none` sale de 0 bytes y nadie lo registra) ni los headers (ya eran `no-cache`) — era que nadie recarga, porque la PWA queda abierta días. Ante la duda no se avisa. Nuevo `version_service.dart` (web-only) + `utils/version_check.dart` (puro, testeado). Ver la sección "Aviso de versión nueva". |
| v19.3 (25/10) | **Comisiones y Reporte también solo para el admin.** Se suman al gate de rol que v19.2 puso sobre Ganancias y Cobranzas: los cuatro muestran la plata del negocio de conjunto. **Saldos quedó afuera a propósito** — es lo que mira el cobrador para armarse el recorrido, y Vencidos solo no alcanza porque no muestra al cliente que debe pero todavía está en plazo. Para los roles con `ver_consultas` quedan seis tabs: Vencidos, Saldos, Historial, Directorio, Ruta y Eliminados. Sin migración ni lógica nueva. |
| v19.2 (24/10) | **Cierre de jornada del cobrador + tabs de Consultas por rol.** (1) **Tab Cobranzas** (solo admin): se elige cobrador y día y se ve a quién le cobró, con total, cantidad de cobros y clientes, desglose efectivo / transferencia / cheque y el **efectivo a rendir** destacado (la única plata que pasó por la mano del cobrador). Una fila por cobro con hora, cliente, número de pago, medio y vendedor; al tocarla se abre el pago en modo ver. Botón de **PDF** (`cierre_jornada_service.dart`). Si el día no tiene cobros avisa cuál fue el último que sí tuvo. (2) Los tabs de `ConsultasScreen` se arman **por rol** en vez de estar fijos en 9: **Ganancias** y **Cobranzas** quedan solo para el admin. Antes Ganancias —costo por kg y ganancia del negocio— la veía cualquiera con `ver_consultas`, incluido el rol Cobrador. (3) `getMediosDePagos` trae los medios de varios pagos en una query (antes era N+1 por jornada). **Sin migración**: `pagos.registrado_por` ya existía. Test nuevo: `test/cierre_jornada_test.dart`. |
| v19.1 (20/10) | **Terminaciones del módulo Proveedores + tipo de animal del proveedor.** (1) **Entrada de números con separador de miles** en todos los campos del módulo: mientras se tipea aparece `10.000.000` (`MilesInputFormatter` + `parseNumero` + `textoMiles` en `formatters.dart`). (2) **Kg del bloque de rinde sin decimales**, con el criterio de la planilla (de 0,6 para arriba sube, de 0,5 para abajo baja — NO es el `.round()` de Dart): `redondearKg` en `models.dart`. (3) **PDF de la carga** desde el detalle (`carga_pdf_service.dart`), espejo de la pantalla; el bloque DIFERENCIA DE RINDE **solo se imprime si el proveedor rindió de menos** que el asegurado. (4) **`tipo` novillo / cerdo en el proveedor** (`SegmentedButton` en el ABM, pill en la lista, al lado del nombre en el dropdown de la carga): vive en el proveedor y **no** se congela en la carga, y usa el mismo vocabulario que `CostoSemanal.costoPorTipo` para que el módulo de ganancia separe costo/kg novillo de costo/kg cerdo. Migración `supabase_migration_proveedor_tipo.sql`. Tests nuevos: `test/formatters_test.dart`, `test/carga_pdf_test.dart`, `test/proveedor_test.dart`. |
| v19 (19/10) | **Módulo Proveedores (compra de animales vivos)** — reemplaza el Excel `Proveedores-Pagos.xlsx`. Tab propia para la cajera (permiso `gestionar_proveedores`). Una **carga** (`PP-0001`, numeración por secuencia de Postgres) es una compra de animales a un proveedor: animales, kg vivo, desvaste %, precio kg vivo, rinde asegurado %, y el **kg de media res que se completa después de la faena** (hasta entonces "Falta faena", pero el total a pagar ya está definido). Abajo de cada carga van los pagos a ese proveedor (efectivo / transferencia / cheque, sin más datos). El **SALDO A FAVOR se arrastra solo en cadena por proveedor** y nunca se guarda: corregir una carga vieja reacomoda todas las siguientes. Bloque de **diferencia de rinde** (esperado vs. obtenido, valorizado) visible también para la cajera. ABM de proveedores (los tres valores numéricos son defaults que se copian a la carga y ahí quedan congelados). Editar y eliminar habilitados; **eliminar exige motivo** y queda en `cargas_eliminadas` / `carga_pagos_eliminados`. **Nada que ver con el circuito de clientes** (remitos/NDP/pagos): acá la plata sale. Migración `supabase_migration_proveedores.sql`. **Arranca de cero: no se importa historia.** |
| v18.37 (07/10) | **Fix: el aviso de WhatsApp del reclamo no se abría**. El ticket se guardaba bien (quedaba `abierto` en la bandeja) pero WhatsApp no abría nunca. Dos causas: (1) `launchUrl` se llamaba después de 2-3 `await` de red (subir foto → insert → firmar link), y en web el navegador solo permite abrir una ventana nueva **durante el gesto del usuario** — pasado eso la bloquea en silencio; (2) el gate `canLaunchUrl` da falsos negativos en Flutter web y abortaba el launch sin avisar. Fix: `avisarPorWhatsapp` se partió en `uriWhatsapp(ticket)` (async, arma el link firmado y el mensaje) + `abrirWhatsapp(uri)` (solo `launchUrl`, sin `canLaunchUrl`). Al guardar, el formulario muestra un diálogo "Reclamo S-000X registrado" con botón **"Abrir WhatsApp"**: el launch sale de ese toque, que es lo que web exige. Si igual falla, snackbar avisando que el reclamo quedó registrado. |
| v18.36 (07/10) | **Módulo de Soporte**: Joaco reporta desde la app lo que no funciona en vez de contarlo suelto por chat. "Reportar un problema" en el menú del FAB (todos los roles): módulo del sistema, descripción, switch "no puedo seguir trabajando" y foto opcional de la pantalla. El ticket se guarda en Supabase (`soportes`, numeración `S-0001` por secuencia de Postgres) y recién después se abre WhatsApp con el reclamo ya escrito — si no llega a mandarlo, el reclamo igual quedó. La foto va a un bucket privado y viaja como link firmado. **"Bandeja de soporte"** (solo admin) con 3 tabs para triage, responder y marcar resuelto; la respuesta la ve el usuario en "Tus reclamos". Nuevo `utils/app_config.dart` con `--dart-define` (`SOPORTE_WHATSAPP`, `CLIENTE_NOMBRE`) para que el módulo sirva en cualquier instalación. Vuelve la dependencia `image_picker`. El FAB dejó de estar gateado por `crear_remito`/`crear_pago` (si no, un rol restringido no podía reportar nada). Migración `supabase_migration_soporte.sql`. |
| v18.31 (22/09) | **Botón "Guardar + Enviar" en Notas de Crédito/Débito**: al registrar una NC/ND, además del botón "Registrar nota de crédito/débito" hay ahora un `OutlinedButton` "Guardar + Enviar" (ícono share) que guarda la nota y **abre la hoja de compartir con el comprobante PDF** (`EstadoCuentaService.generarComprobanteNcd` → `Printing.sharePdf`), para mandárselo al cliente por WhatsApp al momento. Mismo patrón que "Guardar + Recibo" de los pagos. Nuevo método `_guardarYEnviar` en `nota_cd_form_screen.dart` (pasa el saldo ya recalculado post-nota). Sin cambios de BD ni migraciones. Rama `feat/reparto-precarga`. |
| v18.30 (16/09) | **Precarga del reparto de la semana anterior (pantalla + asistente)**: al abrir un jueves/viernes sin lista propia, se siembra con la del mismo día de la semana previa (clientes + medias + sucursal; TOTAL MEDIAS y notas quedan en blanco), porque muchos clientes piden siempre lo mismo. Nuevo `getRepartoListaOPlantilla` en `database_service.dart` como base común. `reparto_screen.dart`: banner "Precargado de la semana pasada" + una plantilla sin tocar no se auto-guarda al navegar (evita listas fantasma). Asistente (`asistente_reparto_sheet.dart`): el update/insert/delete se hace sobre esa base precargada + botón "Ver lista del día" (solo lectura). **Fix (commit `03af45a`)**: `getRepartoLista` colapsa filas idénticas al leer para evitar el bug de "todo duplicado". Rama `feat/reparto-precarga` (no mergeada a `master`). |
| v18.29 (09/09) | **Lista de reparto en orden alfabético (pantalla + PDF)**: la grilla de `reparto_screen.dart` (`_grilla`) y la tabla de clientes del PDF (`reparto_service.dart`) ahora muestran las filas ordenadas A→Z por `nombreRazonSocial`. Es solo orden de visualización: no toca el campo `orden` que se persiste ni los controllers de cada fila; las filas fijas TOTAL MEDIAS y SOBRANTE DEPÓSITO del PDF quedan intactas. Commit `2b7c858`. **`feat/reparto-voz` mergeada a `master` (fast-forward) — master y producción ahora coinciden.** |
| v18.28 (03/09) | **Detalle de NC/ND desde la ficha del cliente (modo ver)**: las tarjetas de notas C/D en `cliente_detalle_screen.dart` (agregadas en v18.27) ahora son clickeables igual que los remitos. `NotaCdFormScreen` gana un parámetro `notaInicial`: si viene, `build` renderiza `_buildSoloLectura` (título "Ver nota de crédito/débito", muestra número, tipo con pill, cliente, vendedor, fecha, monto, motivo, registrado por y saldo actual del cliente) en vez del formulario editable. Botón **"Descargar comprobante"** (reusa `EstadoCuentaService.generarComprobanteNcd`) y botón **eliminar** en el AppBar (con permiso `editar_pago`, recalcula saldo y hace `pop`). La ND abre en modo ver (antes no era clickeable); el remito sigue abriendo su form editable. |
| v18.27 (03/09) | **Notas C/D en la ficha del cliente (el saldo cuadra visualmente)**: la lista de `cliente_detalle_screen.dart` mostraba solo remitos, entonces el saldo (`remitos + débitos − pagos − créditos`) no cuadraba a la vista cuando el cliente tenía notas C/D. Ahora la lista unifica remitos + notas: las **ND** aparecen como un cargo más que suma deuda (mismo FIFO que un remito, con Saldado/Vencido/Pendiente y "Deuda restante", `Débito: $…` + motivo, no clickeable); las **NC** aparecen con borde verde, pill "Crédito" y monto en verde con signo `-` (restan al saldo). Encabezado "Remitos" → "Remitos y notas", el contador incluye todo, y "Vencidos" cuenta también las ND vencidas. El saldo en sí no cambió; solo faltaba que la lista lo explicara. |
| v18.26 (03/09) | **Asistente de reparto por IA (robot chatbox)**: botón flotante con ícono de robot (`Icons.smart_toy`) **siempre visible** en toda la app (`main.dart`, en un `Stack` que convive con el FAB central). Abre un chatbox (`asistente_reparto_sheet.dart`) donde Joaco dicta/escribe en lenguaje natural (ej: *"3 medias de cerdo y 2 de carne para Perico, sacá a La Florida del viernes"*) y arma la **lista de reparto** hablando. La frase va a la Edge Function **`parse-reparto`** (proxy a Claude, modelo `claude-sonnet-4-5-20250929`), que devuelve items estructurados (cargar/borrar, cliente, carne, cerdo, confianza). El chat resuelve nombre→clienteId (con manejo de ambigüedad/no encontrado), muestra una **propuesta** con chips CARGAR/BORRAR + checkbox por ítem, y al **Confirmar** persiste directo en `reparto_listas`/`reparto_items` vía `DatabaseService` (funciona desde cualquier pantalla, independiente de `RepartoScreen`). Módulo logístico: NO toca plata. `reparto_ia_service.dart` autentica con la publishable key (NO el JWT). Es la **Fase 2** (audio/voz) de la lista de reparto, resuelta con el micrófono del teclado iOS. |
| v18.25 (02/09) | Kg con decimales, la deuda vencida contempla notas C/D, y campo de sucursal en el reparto. |
| v18.24 (26/08) | **Lista de reparto semanal (módulo logístico, aparte de lo comercial — NO toca plata)**: nuevo módulo para armar el reparto de carne de la semana, basado en la planilla "REPARTO CERDO". Dos listas por semana (**Jueves / Viernes**), navegación semanal `< >`, columnas fijas **CARNE** (novillo) / **CERDO**. TOTAL MEDIAS se carga a mano; **SOBRANTE DEPÓSITO = TOTAL − repartido** (auto, rojo si negativo). Clientes elegidos de la lista existente (no texto libre). Campo de NOTAS SUELTAS. **PDF para el repartidor** (`reparto_service.dart`). Accesible desde el menú del FAB (sin gate de permiso). Tablas `reparto_listas` + `reparto_items` (`supabase_migration_reparto.sql`). Fase 2 pendiente: carga por audio. |
| v18.23 (26/08) | **Teléfono como link directo a WhatsApp en la ficha del cliente**: en `cliente_detalle_screen.dart` la fila del teléfono dejó de ser texto plano (`_InfoRow`) y ahora es tocable (ícono verde de chat + número subrayado en verde) → abre WhatsApp con el helper compartido `abrirWhatsApp` (importado de `consultas_screen.dart`, v18.20). Mismo comportamiento que Directorio, Vencidos y la lista de Clientes. |
| v18.22 (24/08) | **Fix crítico de saldos: paginación PostgREST (límite 1000 filas)** + notas C/D en más vistas. La tabla `pagos` superó las 1000 filas y `getPagos`/`getRemitos`/`getAllRemitoItems` traían sin paginar (`.select()` → PostgREST corta en 1000 y descarta el resto en silencio). Clientes con historial largo perdían pagos viejos → saldos inflados y remitos ya saldados reaparecían como vencidos. Fix: paginación en batches de 1000 con `.range()` + orden estable en los tres métodos de `database_service.dart`. Además, recibo PDF, ficha de cliente, estado de cuenta y reporte vendedor ahora contemplan notas C/D en el FIFO de deuda. Commits `5595059`, `ca2106c`, `fbe0db4`. |
| v18.21 (18/08) | **Notas de crédito / débito para clientes**: nueva opción para registrar NC (resta al saldo, a favor del cliente, como un pago) y ND (suma al saldo, cargo extra, como un remito). Fórmula de saldo: `remitos + débitos − pagos − créditos`. Formulario propio (`nota_cd_form_screen.dart`) accesible desde el FAB por **todos** los roles. Numeración NC-XXXX / ND-XXXX (secuencia separada por tipo). Integradas en: Historial (chip "Notas C/D", badge NC/ND, comprobante PDF, eliminar con permiso `editar_pago`), FIFO de vencidos (las ND son buckets de deuda; las NC se aplican como crédito FIFO igual que los pagos, vía `bucketsDeudaCliente`), tab Reporte + PDF de estado de cuenta. Tablas `notas_credito_debito` + `notas_cd_eliminadas` (`supabase_migration_notas_credito_debito.sql`). |
| v18.20 (20/07) | **Link a WhatsApp en las tarjetas de cliente**: cada tarjeta con teléfono muestra un acceso directo a WhatsApp (ícono verde / link), igual que el link de ubicación. Se implementó en las 3 tarjetas: Directorio y Vencidos (`consultas_screen.dart`) y lista de Clientes (`clientes_screen.dart`). Helper compartido `abrirWhatsApp` (top-level en `consultas_screen.dart`) arma `wa.me/549` + área + número (saca el `0` inicial del área). |
| v18.19 (08/07) | **Descripción libre de vuelta en la NDP (junto al Tipo de carne)**: cada fila de la nota de pedido tiene ahora **dos campos**: el dropdown "Tipo de carne" (v18.17) **y** un TextField "Descripción (opcional)" de texto libre. Nueva columna `tipo_carne` en `nota_pedido_items` (antes el tipo se guardaba en `descripcion`). La conversión NDP→Remito usa `tipo_carne` (fallback a `descripcion` para NDPs v18.17, luego regla por peso). PDF de NDP y card de bandeja muestran ambos campos. Migración `supabase_migration_ndp_tipo_carne.sql`. |
| v18.18 (08/07) | **Fix menú Opciones tapado en iPhone**: el `showModalBottomSheet` del FAB pasó a `isScrollControlled: true` + `SingleChildScrollView` con padding inferior de 80px, para que la última opción ("Cerrar sesión") no quede oculta detrás de la barra de URL de Safari cuando hay muchas opciones (admin). |
| v18.17 (08/07) | **Nuevos tipos de carne + baja del OCR + tipo de carne en NDP**: (1) Catálogo de tipos de carne (remito y NDP): Novillo, Cerdo, Pierna mocha, Pierna pistola, Plancha de asado, Octavo, 1/4 delantero. (2) **OCR eliminado**: se borró `ocr_service.dart`, la sección de foto del formulario de remito y la dependencia `image_picker`. (3) NDP: la descripción libre por fila pasó a ser un **dropdown de tipo de carne**. (4) La **conversión NDP→Remito** usa el tipo elegido en la nota (fallback a la regla de 60kg solo si viene vacío). (5) Dashboard, Ganancias y Comisiones: **solo Cerdo cuenta como Cerdo; el resto (Novillo y sus cortes) computa como Novillo**. |

## ESTADO ACTUAL (v19.15) — EN PRODUCCIÓN

Deployada el 28/10/2026 desde la rama `fix/fecha-pdf-reparto`, **ya mergeada a `master`** por el **PR #18** (merge commit `85eff1a`) — master y producción coinciden. Deploy `web-99unb7xxw`, que tomó el alias solo. **Sin migración.**

Verificado contra producción: el alias responde 200, **mismo sha256** que el build (`8cb56b6b…`), `app_version.json` dice `v19.15` y el encabezado con la fecha está compilado (`"Reparto del "+n+" "+dd/MM/yyyy`).

Trae la **fecha del día que se reparte** en el nombre del PDF y en el encabezado de la hoja (ver "Cambios v19.15"). **Sin pasada visual del desarrollador.**

### v19.16 — SIN DEPLOYAR

Rama `refactor/deposito-stock-manual`, salida de `master`. Saca la reconciliación del depósito contra cargas y remitos: el módulo pasa a ser el libro de lo que hay en la cámara. Ver "Cambios v19.16". **Sin migración.**

**Ojo con el número de versión**: la rama `feat/auth-identidad-supabase` (Fase 1 de auth, tampoco deployada) también se numeró **v19.16** en su propia documentación. Las dos salen de `master` y no se pisan en el código, pero **la que se mergee segunda tiene que renumerarse** (`AppConfig.version` + la fila del historial), porque si dos deploys distintos dicen `v19.16` el aviso de versión nueva no se entera de que el bundle cambió.

### v19.14 — deployada el 28/10/2026

Deployada el 28/10/2026 desde la rama `fix/dashboard-solo-admin`, **ya mergeada a `master`** por el **PR #17** (merge commit `dd0c0cd`). Deploy `web-7a18z6zzl`, que tomó el alias solo. **Sin migración.**

Verificado contra producción: el alias responde 200, **mismo sha256** que el build (`a218830e…`), `app_version.json` dice `v19.14` y los headers son los que espera el aviso de versión. El bundle trae el botón "Agregar cliente" (y **ya no** "Agregar a CARNE") y la pantalla de Inicio sin plata.

Trae el **gate del dashboard y de la Nota de crédito / débito**, el arreglo de la **celda muerta** de las columnas extra, el texto del botón y las **flechas ↑ ↓** entre celdas (ver "Cambios v19.14"). **Sin pasada visual del desarrollador.**

**El deploy lo corre el usuario**: el modo automático del agente bloquea `vercel --prod`. El agente deja el build hecho con su `.vercel/project.json` restaurado y pasa el comando. Este deploy salió dos veces del **mismo** build (mismo `buildeado` y mismo sha256): la segunda fue al pedo pero inofensiva, solo cambió el id del deployment.

### v19.13 — deployada el 28/10/2026

Deployada el 28/10/2026 desde la rama `feat/reparto-columnas-extra`, **ya mergeada a `master`** por el **PR #16** (merge commit `82db63d`). Deploy `web-eovr0ripg`, que **tomó el alias solo** (`web-six-indol-svg13avcfl.vercel.app`).

Verificado contra producción: **mismo sha256** que el build (`e2d9029b…`), `app_version.json` dice `v19.13`, los headers son los que espera el aviso de versión y las cadenas de la feature están en el bundle ("Agregar columna", "Ej: Pierna, Grasa").

Trae las **columnas a medida** de la lista de reparto (ver "Cambios v19.13"). La migración `supabase_migration_reparto_columnas_extra.sql` **ya se corrió** (28/10/2026): verificado por REST, `columnas_extra` responde `{}` y `extras` responde `[]` en las filas que ya existían, que es exactamente "sin columnas extra". **Sin pasada visual del desarrollador**: la mira el usuario.

### v19.12 — deployada el 28/10/2026

Deployada el 28/10/2026 desde la rama `feat/reparto-dos-tablas-sabado`, **ya mergeada a `master`** por el **PR #15** (merge commit `8b71abb`). Deploy `web-3mo72hm3z`, que **tomó el alias solo** (`web-six-indol-svg13avcfl.vercel.app`).

El PR #15 trae **v19.11 y v19.12 juntas** (las dos se deployaron desde esa rama, antes del merge).

Verificado contra producción: **mismo sha256** que el build (`bce8f09b…`), `app_version.json` dice `v19.12` y los headers son los que espera el aviso de versión.

Trae **una tabla del reparto por vez**, **un PDF por tabla** y la **grilla con líneas + el renglón que se pinta al pasar el mouse** (ver "Cambios v19.12"). **Sin migración.** **Sin pasada visual del desarrollador**: la mira el usuario.

> **Verificar el bundle por `grep` tiene dos límites** (los dos comprobados acá): dart2js **escapa los acentos** (`Sábado` queda `s\xe1bado`) y los **colores no aparecen** en ninguna forma greppable — ni `4291176488`, ni `0xffc62828`, ni `c62828`, probado contra `AppTheme.primary`, que existe desde v1. Para un cambio puramente visual, la prueba es el **sha256 igual al build**, no el grep.

### v19.11 — deployada el 28/10/2026

Deployada el 28/10/2026 desde la rama `feat/reparto-dos-tablas-sabado`. Deploy `web-kxhqo9t1j`, que **tomó el alias solo** (`web-six-indol-svg13avcfl.vercel.app`).

Verificado contra producción: **mismo sha256** que el build (`35f276df…`), `app_version.json` dice `v19.11`, el bundle trae el código nuevo y los headers son los que espera el aviso de versión (`app_version.json` e `index.html` `no-cache, no-store, must-revalidate`; `main.dart.js` `no-cache`).

Trae la **Lista de reparto en dos tablas**, el **sábado** y el **día por comando** en el asistente (ver "Cambios v19.11"). **Sin pasada visual todavía**: se deployó antes de mirarla andando.

> **Al verificar el bundle, los acentos no se buscan tal cual**: dart2js los escapa (`Sábado` queda `s\xe1bado`, `cuántas` queda `cu\xe1ntas`). Un `grep "Sábado" main.dart.js` da 0 y parece que faltara el código. Buscar el pedazo sin acento (`bado`, `ntas medias`) o el escape.

Las dos dependencias de este deploy ya estaban hechas antes de subirlo:
- `supabase_migration_reparto_sabado_tipo.sql` **corrida el 28/10/2026**. Verificado por REST: la columna `tipo` responde, no quedó ninguna fila con carne y cerdo juntos, y el backfill dejó 182 filas de carne y 85 de cerdo (267 en total), ninguna con el tipo cruzado contra la columna de medias.
- Edge Function **`parse-reparto` redeployada** por dashboard el 28/10/2026. Verificada con llamadas reales: "3 medias de carne para el jueves y 5 de cerdo para el sábado" devuelve **dos items**, cada uno con su día; una frase sin día devuelve `dia: null`; y "sacá a Perico del sábado" devuelve el borrar con su día.

### v19.10 — deployada el 28/10/2026

Deployada el 28/10/2026 desde la rama `feat/desglose-kg-semana`, **ya mergeada a `master`** por el **PR #14** (merge commit `b264df2`) — master y producción coinciden. Deploy `web-5xly6g6d8`, que **tomó el alias solo** (`web-six-indol-svg13avcfl.vercel.app`).

Verificado contra producción: **mismo sha256** que el build (`acad6772…`), `app_version.json` dice `v19.10`, el bundle trae el código nuevo (la cadena "Factura completa" del desglose está adentro) y los headers son los que espera el aviso de versión (`app_version.json` y `index.html` `no-cache, no-store, must-revalidate`; `main.dart.js` `no-cache`).

Trae el **desglose de los kg de la semana** del dashboard (ver "Cambios v19.10"). **Sin migración.** **Sin pasada visual todavía**: se deployó antes de mirarla andando.

La URL directa del deploy (`web-5xly6g6d8-mfsabate.vercel.app`) contesta "Protected by Vercel Authentication": es normal, la que es pública es el alias. Lo mismo vale para la de v19.11 (`web-kxhqo9t1j-mfsabate.vercel.app`).

### v19.9 — deployada el 28/10/2026

Deployada el 28/10/2026 desde `master`. La rama `feat/deposito-kg-partes` se mergeó por **PR #13** (merge commit `ebc7824`) — master y producción coinciden. Deploy `web-1626ei0zt`, que **tomó el alias solo** (`web-six-indol-svg13avcfl.vercel.app`).

Verificado contra producción: **mismo sha256** que el build (`05dd2a4e…`), `app_version.json` dice `v19.9` y se sirve `no-cache, no-store, must-revalidate`; `main.dart.js`, `no-cache`.

Trae los **kilos del stock de depósito**, el panel de **partes sueltas de la media** y el **reset del módulo** (ver "Cambios v19.9"). Las dos SQL **ya se corrieron el 28/10/2026**: `supabase_migration_deposito_arranque_kg.sql` (las columnas `kg_novillo` / `kg_cerdo` responden) y `supabase_reset_deposito.sql` (verificado por REST: `deposito_movimientos` y su auditoría vacías, arranque en 0 medias / 0 kg con `fecha_inicio = 2026-10-28`).

**Sigue faltando el paso manual de v19.5**, ahora con el reset encima: fijar el **arranque** del depósito con la cuenta física de la cámara. Mientras esté en 0 el módulo no miente, pero tampoco sirve: arranca de cero. **No lo puede poner el desarrollador**: es la cuenta física de la cámara.

### Cómo se carga el arranque (pendiente al 29/10/2026)

**Historia de la fecha**: el reset del 28/10 la dejó en el 28, pero ese día ya había un remito confirmado (R-1131) y la ecuación de entonces contaba los remitos **desde `fecha_inicio` inclusive**, así que contar la cámara después de que esa carne salió habría descontado dos veces. Por eso se corrió a mano al **29/10** (REST, 28/10 14:01 UTC). El 29/10 volvió a pasar lo mismo con **R-1133** (10 medias de novillo a Roberto Firme): el arranque seguía en 0 y la pantalla mostraba **−10**. Se corrió la fecha al **30/10/2026** (REST, 29/10 20:18 UTC) y ese mismo día se decidió sacar los remitos de la cuenta, que es lo que hace v19.16.

**Con v19.16 esa trampa desaparece**: la cuenta no mira remitos, así que no importa qué se facturó el día del arranque. Lo único que importa es no cargar movimientos de depósito antes de fijarlo.

1. Entrar a **Depósito** con un usuario que tenga `gestionar_deposito` (el menú del FAB) y tocar el ícono de la perilla en el AppBar.
2. La fecha va a decir 30/10/2026. **Dejarla** si se cuenta ese día; si se cuenta otro, ponerle el día en que se contó.
3. Contar la cámara y cargar **medias de novillo** y **medias de cerdo**.
4. Si las pesaron, cargar los **kg de cada stock** (v19.9). Son opcionales: sin ellos la tarjeta muestra las medias igual, pero avisa en naranja "faltan pesar N medias" en vez de inventar un kilaje.
5. Guardar. De ahí en adelante hay que cargar **cada entrada y cada salida a mano**: el módulo ya no se entera solo de ninguna compra ni de ninguna venta.

**La fecha no se puede elegir desde la app si es futura**: el `showDatePicker` del diálogo tiene `lastDate: DateTime.now()`. Para correrla hacia adelante va por SQL (`UPDATE deposito_config SET fecha_inicio = DATE 'AAAA-MM-DD';`) o por REST, como se hizo las dos veces.

### v19.8 — deployada el 27/10/2026

Deployada el 27/10/2026 desde la rama `feat/vendedores-orden-alfabetico`, **ya mergeada a `master`** por **PR #12** (merge commit `23a4620`). Deploy `web-iqaososoz`, que **tomó el alias solo** (`web-six-indol-svg13avcfl.vercel.app`).

Verificado contra producción: **mismo sha256** que el build (`5ef3d0ff…`), `app_version.json` dice `v19.8` y se sirve `no-cache, no-store, must-revalidate`.

Trae el **orden alfabético de la lista de vendedores** y de los dos filtros por vendedor, con el mismo `compararNombres` de los clientes, y el **getter `vendedores` blindado** con `UnmodifiableListView`. Sin migración: es solo orden de visualización.

### v19.7 — deployada el 27/10/2026

Deployada el 27/10/2026 desde `master`. La rama `feat/clientes-orden-alfabetico` se mergeó por **PR #11** (merge commit `9339305`), más el commit del bump. Deploy `web-dk7371nd4`, alias `web-six-indol-svg13avcfl.vercel.app` apuntando ahí.

Verificado contra producción: **mismo sha256** que el build (`0859b74a…`), `app_version.json` y el bundle dicen los dos `v19.7`, y los headers de cache son los que espera el aviso de versión.

Trae el **orden alfabético único de los listados de clientes** (`compararNombres`, que ignora mayúsculas y acentos) y el **getter `clientes` blindado** con `UnmodifiableListView`.

### v19.6 — deployada el 26/10/2026

Deployada el 26/10/2026 desde `master`. La rama `feat/deposito-kg` se mergeó por **PR #10** (merge commit `c24ba25`). Deploy `web-4e6wf9hnd`, alias `web-six-indol-svg13avcfl.vercel.app` apuntando ahí.

Verificado contra producción: **mismo sha256** que el build (`739a166f…`), `app_version.json` y el bundle dicen los dos `v19.6`, el código de los kg está arriba y `app_version.json` se sirve `no-cache, no-store, must-revalidate`.

Trae los **kg por media** en los movimientos de depósito. La migración `supabase_migration_deposito_kg.sql` **ya se corrió** (26/10/2026): la columna responde en las dos tablas.

**Sigue faltando el paso manual de v19.5**: fijar el **arranque** del depósito (fecha + las medias contadas a mano en la cámara). Hasta que no esté, la pantalla muestra "Falta el arranque" y no calcula nada.

### `flutter clean` rompe el deploy si no se restaura el `.vercel` (v19.7)
**`flutter clean` borra `build/` entero**, y ahí adentro vive `build/web/.vercel`, que es lo que vincula el directorio con el proyecto de Vercel. Como el procedimiento de deploy arranca justamente con `flutter clean`, **el vínculo se pierde en cada deploy**.

Sin él, `vercel --prod --yes` **crea un proyecto nuevo** en vez de deployar al de siempre (con `--yes` ni siquiera pregunta). Hay que recrearlo antes de deployar:

```bash
mkdir -p build/web/.vercel && cat > build/web/.vercel/project.json <<'JSON'
{"projectId":"prj_uiYOfzx8bjMe6fqYiPKL4mNx3G2V","orgId":"team_b3upaAAwW3dLsrxJvc8fHXVu","projectName":"web"}
JSON
```

Los dos ids salen de `vercel project ls` (el proyecto se llama **`web`**, bajo el scope **`mfsabate`**, usuario `milifsabate`). Pasa siempre, no solo cuando se buildea desde un worktree aparte.

**La cuenta se llamaba `jaguilera`** y la doc lo decía así hasta v19.10: el usuario le cambió los nombres en Vercel. Es el mismo proyecto de siempre — los ids no cambian con el renombre, por eso el `project.json` de más arriba sigue sirviendo. Lo único que se nota es que el deploy ahora sale con `-mfsabate` en la URL.

### Buildear sin pisar trabajo sin commitear (v19.6)
En este deploy el working tree tenía 13 archivos modificados sin commitear, de otro trabajo en curso (el helper `compararNombres` para ordenar clientes A→Z). Para no tocarlos, el build salió de un **worktree aparte** en el commit de merge:

```bash
git worktree add --detach /tmp/deploy c24ba25
cd /tmp/deploy/don_chacho && flutter pub get && ./build_web.sh
# El build nuevo NO tiene el vínculo a Vercel: hay que copiarlo
cp -R <repo>/don_chacho/build/web/.vercel /tmp/deploy/don_chacho/build/web/.vercel
cd /tmp/deploy/don_chacho/build/web && vercel --prod --yes
```

**El `cp` del `.vercel` no es opcional**: sin él, `vercel --prod --yes` en un directorio sin vincular crea un **proyecto nuevo** en vez de deployar al de siempre.

### v19.5 — deployada el 26/10/2026 (reemplazada por v19.6 el mismo día)

Deployada el 26/10/2026 desde `master`. La rama `feat/deposito` se mergeó por **PR #9** (merge commit `7cddec7`). Deploy `web-h9kscw2ik`, alias `web-six-indol-svg13avcfl.vercel.app` apuntando ahí.

Verificado contra producción: **mismo sha256** que el build local (`71fc7e8e…`), `app_version.json` y el bundle dicen los dos `v19.5` (coinciden, así que no hay aviso falso), `app_version.json` se sirve `no-cache, no-store, must-revalidate` y `main.dart.js` `no-cache`. La app carga sin errores de consola.

Trae el **módulo Depósito** (ver más arriba). La migración `supabase_migration_deposito.sql` **ya se corrió** (26/10/2026): las tres tablas responden y el permiso `gestionar_deposito` quedó en los roles **Administrador** y **Secretaria**, no en Cobrador.

**FALTA UN PASO MANUAL**: entrar a Depósito con el admin y fijar el **arranque** (fecha + las medias contadas a mano en la cámara). Hasta que eso no esté, la pantalla no calcula nada y muestra el cartel "Falta el arranque". No lo puede poner el desarrollador: es la cuenta física de la cámara.

### v19.4 — deployada el 26/10/2026 (reemplazada por v19.5 el mismo día)

Deployada el 26/10/2026 desde `master`. La rama `feat/aviso-version` se mergeó por **PR #8** (merge commit `f1f685c`), más el commit `6ee9365` del bump. Deploy `web-jzix7znrz`, alias `web-six-indol-svg13avcfl.vercel.app` apuntando ahí. Verificado: mismo sha256 que el build local, el bundle dice `v19.4`, `app_version.json` dice `v19.4` (coinciden, así que no hay aviso falso) y se sirve `no-cache, no-store, must-revalidate`. **Sin migración.**

Trae el **aviso de versión nueva** (ver la sección de más arriba). **Este deploy todavía no se ve**: los usuarios que estaban en v19.3 no tienen el código del chequeo, así que la barra recién va a aparecer con el deploy siguiente. Para probar que anda de verdad hay que mirar el próximo.

**De acá en más el deploy tiene un orden obligatorio**: subir `AppConfig.version` **antes** de buildear, porque `build_web.sh` lee ese valor para escribir `app_version.json`. Si se buildea primero y se sube la versión después, el JSON queda con la versión vieja.

### v19.3 — deployada el 25/10/2026

Deployada el 25/10/2026 desde `master`. La rama `feat/gate-tabs-admin` se mergeó por **PR #7** (merge commit `6045fa0`), más el commit `8226099` que sube la versión. Deploy `web-efgytddq1`, alias `web-six-indol-svg13avcfl.vercel.app` apuntando ahí (verificado: mismo sha256 que el build local, y el bundle dice `v19.3`). **Sin migración**: es solo visibilidad de tabs.

Suma **Comisiones** y **Reporte** al gate de admin que v19.2 había puesto sobre Ganancias y Cobranzas. **Saldos quedó deliberadamente afuera** (ver "Consultas" más arriba): lo necesita el cobrador.

### v19.2 — deployada el 24/10/2026

Deployada el 24/10/2026 desde `master`. Las ramas `docs/v19-1-deploy` (PR #5) y `feat/cierre-jornada` (PR #6) se mergearon en ese orden, más el commit `ca267aa` que sube la versión a `v19.2` — master y producción coinciden. Deploy `web-9xpuud48c`, alias `web-six-indol-svg13avcfl.vercel.app` apuntando ahí (verificado: el `main.dart.js` que sirve el alias tiene el mismo sha256 que el build local). **Sin migración**: el cierre de jornada se apoya en `pagos.registrado_por`, que ya existía.

Trae el **tab Cobranzas** (cierre de jornada del cobrador) y el gate de admin sobre **Ganancias** (ver "Cambios v19.2"). **Probado con datos reales el 24/10/2026**: el total de Arturo del 23/10 y el desglose por medio coinciden.

Ojo con el `vercel --prod --yes`: en la CLI 64.0.2 el deploy **tomó el alias solo**, a diferencia de lo que decía esta doc para versiones anteriores. Igual conviene verificar el sha256 después.

### v19.1 — deployada el 20/10/2026

Deployada el 20/10/2026 desde `master`. La rama `feat/proveedores` se mergeó por **PR #4** (merge commit `9e24dc2`) — master y producción coinciden, y **ninguna otra rama tiene commits fuera de master** (verificado con `git rev-list --count origin/master..<rama>` sobre todas). Deploy `web-f8bi14j2f`, alias `web-six-indol-svg13avcfl.vercel.app` apuntando ahí (verificado: el `main.dart.js` que sirve el alias tiene el mismo sha256 que el build local). Las dos migraciones del módulo (`supabase_migration_proveedores.sql` y `supabase_migration_proveedor_tipo.sql`) ya se corrieron.

Trae el **módulo Proveedores** completo (ver "Cambios v19"). **Sin pasada de prueba manual todavía**: se deployó antes de recorrer el circuito end-to-end. Lo primero a mirar con datos reales es el **saldo arrastrado entre dos cargas del mismo proveedor**, que es la parte con más lógica y la que el Excel hacía a mano.

### v18.37 — deployada el 07/10/2026

Deployada desde la rama `fix/soporte-whatsapp`, **ya mergeada a `master`** (PR #2, merge commit `d457360`). Deploy `web-2f6u8cxou`. Arregla el aviso de WhatsApp del módulo de Soporte, que no abría nunca (ver fila v18.37 del historial). **Probado desde el celular el 07/10/2026: el flujo completo anda** (reclamo → diálogo → "Abrir WhatsApp" → chat con el mensaje escrito).

### v18.36 — deployada el 07/10/2026

Deployada desde la rama `feat/soporte`, **ya mergeada a `master`** (PR #1, merge commit `6760477`). Deploy `web-5gub63yg0`. La migración `supabase_migration_soporte.sql` ya se corrió: tabla `soportes` verificada por REST y bucket `soporte-adjuntos` verificado en el dashboard. `AppConfig.soporteWhatsapp` quedó en `5493874159555` (WhatsApp de Mili, la desarrolladora).

### v18.31 — deployada el 22/09/2026

Deployada el 22/09/2026. Login funciona con admin/admin123. Flutter 3.41.8. URL: `https://web-six-indol-svg13avcfl.vercel.app`. Salió de la rama `feat/reparto-precarga` (que acumulaba v18.30 + v18.31); **esa rama ya está mergeada a `master`** — en su momento no lo estaba y la doc quedó desactualizada hasta el 20/10/2026.

> **v19.16 junta tres cambios que se mergearon por separado y salen en UN SOLO deploy**: la
> identidad de Auth (PR #19), el depósito sin reconciliación (PR #20) y las políticas de RLS
> sin encender (PR #21, ver "CAMBIOS PENDIENTES → Auth — Fase 2"). Las tres ramas habían
> subido la versión a `v19.16` por su cuenta; como ninguna llegó a producción, no hace falta
> un número para cada una — en producción sigue corriendo `v19.15`, así que un solo `v19.16`
> ya le dispara el aviso de versión nueva a todo el mundo. Lo que sí importa es que **el
> deploy de v19.16 lleva las tres cosas**: no se puede deployar el depósito sin llevarse la
> Fase 1 de auth, y por eso el orden del `auth_fase1_runbook.md` manda. De la PR #21 no sale
> ningún cambio de comportamiento: `AppProvider.rlsEncendido` está en `false`.

### Cambios v19.16 — Identidad de Supabase Auth (Fase 1 de auth) · **SIN DEPLOYAR**

Rama `feat/auth-identidad-supabase`, **ya mergeada a `master`** (PR #19, merge commit
`7196ebd`). **No está en producción y no se puede deployar sola**:
antes hay que correr la migración y crear las 6 cuentas (ver `auth_fase1_runbook.md`).

El objetivo de la fase es que la base **sepa quién pregunta**. Hasta hoy no podía: la app se
conecta con la publishable key, el login es propio y la sesión es un id en el navegador, así
que `auth.uid()` es NULL y **no se puede escribir ninguna política de RLS**. Esta fase pone
la identidad; las políticas son la fase siguiente.

- **`usuarios.auth_id`** (nullable, FK a `auth.users`, índice UNIQUE) + las funciones
  `security definer` `es_admin()` y `tiene_permiso(text)` que van a usar las políticas.
  **No se habilita RLS en ninguna tabla.**
- **El login pide lo mismo de siempre** (usuario + contraseña) pero adentro arma un mail
  sintético `<usuario>@donchacho.local` y hace `signInWithPassword`. La sesión pasa a ser la
  de Supabase (`onAuthStateChange`).
- **Login legacy transitorio** (`AuthService.permitirLoginLegacy`): red para la ventana
  entre crear las cuentas y deployar. **Hay que apagarlo antes de la Fase 2.**
- **Pantalla nueva "Cambiar contraseña"** en el menú del `+`, para todos los roles. Las
  contraseñas viejas no se migran (SHA-256 sin sal vs. bcrypt), así que cada uno arranca con
  una temporal. `cambiarPassword` **borra el hash viejo** al cambiarla. Hasta ahora el método
  existía en el servicio y ninguna pantalla lo llamaba: era código muerto.
- **El alta de usuarios queda en dos pasos**: el editor ya no pide contraseña (crear una
  identidad de Auth necesita la service key, que no puede viajar en un bundle web) y muestra
  el mail que hay que crear en el dashboard. La lista marca **SIN CUENTA** a quien no esté
  vinculado.
- **Las policies del bucket `soporte-adjuntos` se amplían a `authenticated`**: estaban
  escritas `TO anon` y con sesión de verdad las consultas llegan como `authenticated` —
  adjuntar la foto de un reclamo habría dejado de funcionar el día del deploy.
- Cubierto por `test/auth_identidad_test.dart` (mail sintético + el vínculo `auth_id`, con el
  caso de que la columna no exista todavía).

### Cambios v19.16 (29/10/2026) — El depósito, sin reconciliación · **SIN DEPLOYAR**

Rama `refactor/deposito-stock-manual`, **ya mergeada a `master`** (PR #20).

Lo abrió un reporte del usuario: *"Deposito quedó con -10 medias de carne, debería estar en 0"*.

1. **El diagnóstico.** No era un bug: el arranque estaba en 0 medias (los ceros que dejó `supabase_reset_deposito.sql`, nunca se cargó la cuenta física) y la ecuación le restaba **R-1133**, confirmado el 29/10, 10 medias de Novillo a Roberto Firme. `0 + 0 + 0 − 10 = −10`. Verificado por REST contra producción: `deposito_movimientos` vacía, ninguna carga desde el 29/10, un solo remito.
2. **El arreglo inmediato** (datos, no código): se corrió `fecha_inicio` del 29/10 al **30/10/2026** por REST, con lo que R-1133 dejó de contar y el stock quedó en 0.
3. **La corrección de fondo, del usuario**: el depósito **no tiene que hacer ningún cálculo en relación a los remitos**. Es el registro de lo que hay en la cámara. Preguntado explícitamente si salían solo los remitos o también las cargas de proveedor, eligió **las dos**: el stock sale 100% de lo que se carga a mano.
4. **`lib/models/models.dart`**: `StockDeposito` pasa de doce componentes a tres (`inicial`, `entradas`, `salidas`) más los kg de cada uno, el recuento y `mediasSinPesar`. `teorico = inicial + entradas − salidas`. Se **borraron** `equivalenciasMedia`, `equivalenciaEnMedias`, `stockDeTipoCarne`, `mediasPorAnimal`, `_tercio`, `partePierna` / `parteOctavo` / `partePlancha`, `partesDeCorte`, `CortesVendidos` y `labelParte`, y de `StockDeposito` los getters `totalDisponible`, `hayPendientes`, `kgPendientes`, `mediasSueltas`, `mediasEnteras` y `hayPartesSueltas`. `DepositoMovimiento` y `DepositoMovimientoEliminado` pierden `esperaRemito`, `esSalidaPendienteDeRemito` y `esSalidaDefinitiva`.
5. **`lib/providers/app_provider.dart`**: `_componentesDeposito` recorre **una sola colección**, `_depositoMovimientos`; se fueron el bucle de `_cargas`, el de `_remitos` y los métodos `_salidasPendientes` y `_remitidasCargadasDespuesDe` (unas 170 líneas). `cargarDeposito` **ya no precarga proveedores** — eran dos queries de más en cada apertura, que existían solo porque el stock leía las cargas. `hayAlertaDeposito` queda en `faltan` a secas.
6. **`lib/screens/deposito_screen.dart`**: el desglose de la tarjeta pasa a tres líneas (Al arranque / Entradas / Salidas). Se fueron el panel "DISPONIBLE PARA VENDER" (`_PartesSueltas`), el aviso de salidas sin remito (`_Pendientes`), el atajo "Cargar el remito" (`_cargarRemitoFaltante` y el import de `remito_form_screen.dart`), el switch "el remito se carga después" y el cartelito de "si el remito ya está cargado, no registres la salida". Los textos del veredicto hablan del libro y no de lo remitido.
7. **El recuento no se tocó y es deliberado.** Era la parte del módulo que más se parecía a lo que se sacó, pero comparar lo contado a mano contra lo cargado **no necesita remitos** y es exactamente lo que delata la media que sale sin registrarse: el agujero original. Sigue comparando contra el stock **de su momento** (`teoricoAlRecuento`).
8. **Una sola clase de salida.** `espera_remito` separaba "todavía no tiene remito" de "definitiva"; sin remitos que cierren nada, la distinción no significa nada. El motivo pasó a la **observación**, que es texto libre y dice más ("se las llevó Firme" vs. "merma").
9. **El stock negativo se muestra.** Antes un negativo era casi siempre la reconciliación funcionando mal; ahora solo puede significar una salida cargada sin su entrada, y eso hay que verlo. `kgTeorico` **sigue recortado en 0**, porque ahí un negativo significaría otra cosa (kilos sin pesar) y no un faltante.
10. **Sin migración.** `espera_remito` queda en las dos tablas con su `DEFAULT TRUE` y la app simplemente dejó de escribirla; `fromMap` la ignora si una fila vieja la trae. Borrar la columna habría pedido una migración por un campo que no molesta.
11. **`test/deposito_test.dart` reescrito**: de 58 casos a **46**. Se fueron los de equivalencias, partes de la media, lo suelto y el circuito FIFO de la salida pendiente; se sumaron el arranque en cero dando 0 (el caso del reporte), el stock negativo, que el recuento no mueva el stock, que todas las salidas descuenten igual y que `toMap` ya no mande `espera_remito`. El proyecto queda en **155 tests en verde** y `flutter analyze` sin errores.
12. **`lib/utils/app_config.dart`**: `version` de `'v19.15'` a `'v19.16'`. Era el mismo número que había puesto la rama de auth; se resolvió dejando **un solo v19.16 con las dos cosas** (ver la nota arriba).
13. **Lo que esto cuesta, dicho explícitamente**: el módulo ya no puede decir "salieron dos medias y no hay remito que las respalde", que era el caso que lo hizo nacer en v19.5. Lo más cerca que queda es el recuento, que avisa que faltan pero no contra qué. Fue una decisión del usuario, tomada sabiendo eso.
14. **Pendiente**: el arranque sigue sin cargarse (ver "Cómo se carga el arranque"). Hasta que esté, el módulo muestra 0 y no sirve, pero tampoco miente.

### Cambios v19.15 (28/10/2026) — La fecha del PDF de reparto

Lo reportó el usuario: el PDF salía `reparto_carne_jueves_26-10-2026` estando a 28 de octubre.

1. **No era la fecha de hoy la que estaba mal, era otra fecha.** El nombre llevaba `semanaInicio`, que es el **lunes de la semana** — el dato con el que se guarda la lista (`UNIQUE (semana_inicio, dia)`). El jueves de la semana del 26/10 se reparte el **29/10**, y un archivo que dice 26 se lee como la fecha equivocada.
2. **`lib/models/models.dart`**: `offsetDiaReparto` (jueves 3, viernes 4, sábado 5, sacado del orden de `diasReparto`) y `RepartoLista.fecha`, que es el lunes más ese offset. Se arma con `DateTime(año, mes, día + offset)` y no sumando una `Duration`, así cruza bien el fin de mes y el fin de año.
3. **`lib/services/reparto_service.dart`**: el nombre del archivo usa esa fecha, y el encabezado del PDF pasa a decir "CARNE (NOVILLO) — **Reparto del Jueves 29/10/2026**". El repartidor lee la hoja, no el nombre del archivo, así que la fecha tiene que estar adentro también.
4. **La semana sigue apareciendo** abajo del título: es el dato con el que se busca la lista en la app.
5. **Deploy**: 28/10/2026 desde la rama `fix/fecha-pdf-reparto` (commit `83fa16e`). Deploy `web-99unb7xxw`, que tomó el alias solo.
6. **`test/reparto_test.dart`**: 5 casos nuevos (**167 en el proyecto**) — los tres días, que nunca dé el lunes, y los cruces de fin de mes y de fin de año (la semana del 28/12/2026 tiene el jueves en 2026 y el sábado ya en 2027).

### Cambios v19.14 (28/10/2026) — El dashboard es solo del dueño

Lo reportó el usuario con una captura: la Encargada de Depósito, entrando con su usuario, veía el saldo total a cobrar y la lista de vendedores con su deuda.

1. **`lib/screens/home_screen.dart`**: `if (!app.esAdmin) return _inicioSinPlata(app);` **antes de calcular nada**. El corte va arriba de todo y no card por card: así no queda ninguna tarjeta suelta sin gate, ni ahora ni cuando se agregue la próxima. Los `if (app.esAdmin)` que había adentro quedaron redundantes.
2. **`_inicioSinPlata`**: saludo con el nombre y el rol, y una línea que manda a las pestañas o al botón +. Para la Encargada de Depósito, Inicio es la única pestaña que tiene.
3. **`lib/main.dart`**: la **Nota de crédito / débito** pasó a pedir `crear_pago`. Es el agujero más grave de los dos, porque no era solo mirar: desde ahí se le puede **cambiar el saldo a cualquier cliente**. `crear_pago` la deja donde ya estaba (admin, Secretaria, Cobrador) y la saca del Encargado de Depósito, sin migración ni permiso nuevo.
4. **Por qué `esAdmin` y no un permiso nuevo**: es el mismo criterio de v19.2/v19.3 con Ganancias, Cobranzas, Comisiones y Reporte. Un permiso nuevo habría que acordarse de no dárselo a nadie.
5. **Lo que NO cambió, a propósito**: la Lista de reparto y Soporte siguen sin gate (logística sin plata, y el soporte tiene que estar para todos). Consultas ya estaba gateada por `ver_consultas`, que este rol no tiene.
6. **`test/permisos_home_test.dart`** (nuevo, 4 casos): que el Encargado de Depósito no sea admin, que tenga un solo permiso, que no tenga `crear_pago`, y —la otra mitad del gate— que Secretaria, Cobrador y admin **sí** lo tengan, para que tapar a uno no se lo saque a los que la usan. **160 tests en verde**.
7. **Los roles de producción quedaron como estaban**: esto no toca la base. Verificado por REST al diagnosticar (`roles`, `rol_permisos`, `usuarios`).
8. **Sigue siendo un gate de UI.** Las tablas tienen RLS off y la app usa la publishable key: los datos viajan igual al navegador. Ver "Qué tapa cada gate".

**Arreglos del reparto que entraron en la misma versión:**

9. **BUG: la celda de una columna extra no se dejaba escribir.** Agregar columna → agregar cliente → la celda nueva aparecía vacía y muerta. `_agregarCliente` creaba el `_Fila` **sin pasarle `columnas`**, así que nacía sin esos controllers y la grilla dibujaba un hueco. Cubierto por test.
10. **El botón dice "Agregar cliente"** y no "Agregar a CARNE": con una sola tabla a la vista, a cuál se agrega ya se ve arriba.
11. **Flechas ↑ ↓ entre celdas** (`_moverFoco`): bajan y suben en la **misma columna**, que es como se carga una planilla. El tabulador no servía porque pasa por el campo de sucursal y por la cruz de quitar. El salto usa **el mismo orden A→Z que la grilla** (`_filasOrdenadas`, compartido): con otro orden, la flecha bajaría a una fila que no es la de abajo. Al llegar, el número queda **seleccionado**, para tipear encima sin borrar antes.
12. **Deploy**: 28/10/2026 desde la rama `fix/dashboard-solo-admin` (commits `d4117f4` y `ae0c1b1`). Deploy `web-7a18z6zzl`, que tomó el alias solo. Sin migración.
13. **El `Focus` de la flecha va ARRIBA del campo**: la tecla sube desde el que tiene el foco hacia sus padres, así que llega ahí antes que a los atajos de edición de texto de Flutter. En un campo de una línea la flecha vertical no hace nada útil, así que no se le saca nada al usuario. Va con `canRequestFocus: false` para no meterse en el recorrido del tabulador.

### Cambios v19.13 (28/10/2026) — Columnas a medida en el reparto

A veces Joaco vende algo que no es una media: una pierna, grasa, lo que aparezca. No tenía dónde anotarlo por cliente y terminaba en las notas sueltas, sin cantidad.

1. **`supabase_migration_reparto_columnas_extra.sql`** (raíz del repo): `columnas_extra` JSONB en `reparto_listas` y `extras` JSONB en `reparto_items`. **Prerequisito del deploy.** Ver "Tablas Lista de reparto".
2. **`lib/models/models.dart`**: `maxColumnasExtra = 2`, `RepartoLista.columnasExtra` / `columnasDe` / `repartidoExtra`, `RepartoItem.extras` / `extraEn`, y los lectores tolerantes `_leerColumnas` / `_leerExtras`.
3. **Los números van por POSICIÓN, no por nombre.** Si la celda se guardara como `{"Pierna": 2}`, renombrar el encabezado perdería lo cargado. El array y el orden de `columnas_extra` son lo que los ata.
4. **Una fila vieja partida en dos se lleva los extras una sola vez** (la de carne): dárselos también a la de cerdo los contaría dos veces en el total. Cubierto por test.
5. **`lib/screens/reparto_screen.dart`**: el `+` en la barra de título de cada tabla (deshabilitado al llegar a dos), `_columnas` con un controller por encabezado, y los campos de cada fila que se suman y se sacan solos cuando la tabla gana o pierde una columna (`_Fila.ajustarColumnas` / `quitarColumna`).
6. **El encabezado se edita en un diálogo y no en la celda**: la celda mide 56 y no entra un campo de texto con su botón de borrar al lado. Cancelar deshace lo tipeado, porque el diálogo edita **el mismo controller** que vive en la grilla.
7. **Quitar una columna con cantidades cargadas pregunta antes**, diciendo a cuántos clientes les borra el número.
8. **`lib/services/reparto_service.dart`**: el PDF arma las columnas extra con su encabezado, la suma en la fila TOTAL y una raya en SOBRANTE. El ancho de columnas se calcula según cuántas haya.
9. **Las celdas de la grilla pasaron de 64 a 56 de ancho**: con dos columnas más, a 64 el nombre del cliente no entraba en el celular.
10. **`lib/services/database_service.dart`**: la plantilla de la semana siguiente **se siembra con las columnas y sus números** (si la semana pasada hubo "Pierna", lo más probable es que esta también), y el colapso de filas idénticas mira también los extras.
11. **El asistente no sabe de columnas extra**: carga medias. Lo que ya está cargado en esas columnas **no se pierde** cuando el asistente toca esa fila, porque muta el item leído de la base.
12. **`test/reparto_test.dart`**: 8 casos nuevos (26 en el archivo, **156 en el proyecto**) — el tope de dos, que cada tabla tenga las suyas, los números por posición, la celda nunca cargada, la suma de la columna, la tolerancia de la lectura, que la fila partida no duplique los extras, y el PDF con columnas.
13. **`lib/utils/app_config.dart`**: `version` de `'v19.12'` a `'v19.13'`.
14. **Deploy**: 28/10/2026 desde la rama `feat/reparto-columnas-extra` (commit `39e3176`). Deploy `web-eovr0ripg`, que tomó el alias solo. La migración se corrió **antes** del build.

### Cambios v19.12 (28/10/2026) — Una tabla a la vez y un PDF por tabla

Corrección del usuario sobre v19.11: las dos tablas apiladas en la misma pantalla no servían, y el PDF tiene que ser uno por mercadería.

1. **`lib/screens/reparto_screen.dart`**: nuevo `_selectorTipo()` (`SegmentedButton` Carne / Cerdo, **el mismo gesto que el selector de día**) y el campo `_tipo` con la tabla visible. El body muestra **una sola tabla**. Cambiar de tabla **no toca la base**: las dos son la misma lista del día y se guardan juntas, así que es un `setState` y nada más — a diferencia del día, que sí recarga.
2. **Vuelve el FAB** "Agregar a CARNE/CERDO" y se fue el botón que estaba dentro de cada tabla. El botón de adentro existía porque con las dos tablas a la vista el FAB no decía a cuál agregaba; con una sola, el FAB alcanza y es más cómodo en el celular.
3. **`lib/services/reparto_service.dart`**: `generarYCompartir` y `generarPdf` toman `tipo` y arman **una sola tabla**. El título del PDF pasa a `CARNE (NOVILLO) — Reparto del Jueves`, y el nombre del archivo lleva el tipo (`reparto_carne_jueves_26-10-2026.pdf`): en el celular los dos PDF del mismo día quedan uno al lado del otro y hay que poder distinguirlos.
4. **Las notas son del día, no de la mercadería**: se editan desde las dos tablas (es el mismo texto, el label pasó a "Notas sueltas del día") y salen en los **dos** PDF. Una nota como "buscar morcillas de La Florida" es del reparto, no de la carne.
5. **El PDF se elige con un menú** en el AppBar ("PDF de CARNE" / "PDF de CERDO") en vez de un botón directo: así los dos se sacan sin tener que cambiar de tabla primero.
6. **`test/reparto_test.dart`**: los smoke tests del PDF arman **los dos** documentos de cada caso, y se sumó el de la tabla vacía — un día puede no tener cerdo y la hoja igual tiene que salir, con su TOTAL MEDIAS y su sobrante. **148 tests en verde**.
7. **`lib/utils/app_config.dart`**: `version` de `'v19.11'` a `'v19.12'`. **Sin migración**: no cambia nada de la base.
8. **La vista de solo lectura del asistente sigue mostrando las dos tablas juntas**, a propósito: ahí se mira de un vistazo cómo quedó el día, no se edita.

**Líneas de grilla y resaltado del renglón** (segunda corrección, mismo día):

9. **Todas las filas pasan por el helper `_filaGrilla`** (encabezado, TOTAL MEDIAS, clientes y SOBRANTE). Es lo que hace que las **líneas verticales queden alineadas de punta a punta**: si cada fila se dibujara por su cuenta, la columna de medias se correría y la grilla dejaría de leerse. Antes la fila de cliente tenía un `SizedBox(width: 8)` de más y el ancho lo ponía cada campo.
10. **`IntrinsicHeight` + `CrossAxisAlignment.stretch`** en la fila: sin eso las líneas verticales salen **cortadas** en las filas más altas, que son las que tienen sucursal cargada.
11. **La tarjeta recorta con `Clip.antiAlias`**: las líneas llegan hasta el borde y sin el recorte se pasan de las esquinas redondeadas.
12. **`lib/utils/theme.dart`**: `gridLine` (`0xFFC9C3B9`, más marcada que `border` a propósito) y `gridHover` (`0xFFFFF3E0`).
13. **`_FilaCliente` pasó a ser un widget con estado propio**, y no un método de la pantalla, por el hover: así el mouse repinta **un renglón** y no la lista entera en cada movimiento, que con los campos de texto adentro se notaría.
14. **El nombre cambia de color, no de grosor**: con `FontWeight` el texto se mueve solo al pasarle el mouse por arriba.
15. **Sin pasada visual del desarrollador**: las líneas y el hover los mira el usuario (la app local pega contra producción).
16. **Deploy**: 28/10/2026 desde la rama `feat/reparto-dos-tablas-sabado` (commits `33ca844` y `de7cff6`). Deploy `web-3mo72hm3z`, que tomó el alias solo. Sin migración.

### Cambios v19.11 (28/10/2026) — Lista de reparto: dos tablas, sábado y día por comando

Cinco pedidos del usuario sobre la Lista de reparto, más lo que arrastraban en el asistente.

1. **`supabase_migration_reparto_sabado_tipo.sql`** (raíz del repo): `'sabado'` en el CHECK de `reparto_listas.dia` y columna `tipo` en `reparto_items`, con el backfill que **parte en dos** las filas viejas que traían carne y cerdo juntos. **Prerequisito del deploy.**
2. **`lib/models/models.dart`**: `diasReparto` (los tres días, en orden) + `labelDiaReparto` (`'sabado'` → `'Sábado'`), `tiposReparto` / `tipoRepartoCarne` / `tipoRepartoCerdo` + `labelTipoReparto`. `RepartoItem` pasa de `mediasCarne`/`mediasCerdo` a **`tipo` + `medias`** (las dos columnas viejas quedan como getters derivados, para seguir escribiendo lo mismo en la base). `RepartoItem.desdeMap` devuelve **una lista**: una fila vieja sin `tipo` con las dos mercaderías se lee como dos filas. `RepartoLista` gana `itemsDe` / `totalDe` / `repartidoDe` / `sobranteDe` por tabla.
3. **`lib/screens/reparto_screen.dart`**: reescrita en **dos tablas** (CARNE y CERDO), cada una con su encabezado, su TOTAL MEDIAS, sus filas, su SOBRANTE y su propio botón "Agregar cliente a …" (el FAB único no servía: no decía a qué tabla iba el cliente). Selector de día con **tres opciones**. **La alineación**: la fila del cliente pasó a `CrossAxisAlignment.center`, así el campo de medias queda centrado contra el bloque nombre + sucursal en vez de flotar arriba.
4. **`lib/services/reparto_service.dart`** (PDF del repartidor): dos tablas, con columnas CLIENTES / SUCURSAL / MEDIAS. `generarPdf` pasó a ser **público** para poder armar el documento en los tests. Las tablas van como **widgets sueltos del `MultiPage`, no dentro de un `Column`**: una `Table` se parte sola entre páginas, un `Column` no, y una lista larga de clientes haría explotar el armado.
5. **`supabase_functions/parse-reparto/index.ts`**: el día pasó a ser un campo **de cada item** (`"dia": "jueves" | "viernes" | "sabado" | null`) en vez de uno solo para toda la frase, y el prompt pide explícitamente **un item por día** cuando la frase toca varios. `dia_actual` quedó aceptado por compatibilidad pero la app ya no lo manda. **Se redeploya por dashboard** (el CLI local está logueado en otra cuenta).
6. **`lib/services/reparto_ia_service.dart`**: `RepartoParseItem.dia`, `interpretar` sin `diaActual`, y `_diaValido` que tolera "Sábado" con acento o en mayúsculas. El día suelto a nivel respuesta (formato viejo) se sigue leyendo como respaldo de los items que no traigan el suyo.
7. **`lib/screens/asistente_reparto_sheet.dart`**: **fuera el `SegmentedButton` Jue/Vie**. Cada ítem de la propuesta muestra su día en un chip tocable; si el comando no lo dijo, el chip dice **"¿Qué día?" en rojo** y el ítem no se puede confirmar hasta elegirlo — adivinar el día mandaría carne a la lista equivocada. `_aplicar` **agrupa por día** y guarda una lista por día. Una carga sin medias tampoco es aplicable: sin cantidad no se sabe a qué tabla va ("Falta decir cuántas medias"). "Ver lista del día" pasó a ser un menú con los tres días, y la vista de solo lectura también muestra las dos tablas.
8. **Al cargar, solo se toca la tabla que el pedido nombra**: si dice "3 de carne para Perico", la fila de cerdo de Perico queda como estaba en vez de pisarse en cero.
9. **`test/reparto_test.dart`** (nuevo, 16 casos): los tres días y el sábado sin acento, que una fila pertenezca a una sola tabla, que una fila sin medias igual sepa cuál es la suya, el partido en dos de las filas viejas, los totales y el sobrante por tabla, y tres smoke tests del PDF (incluida una lista de 160 filas que se parte en varias páginas). El proyecto pasa a **146 tests en verde**.
10. **`lib/utils/app_config.dart`**: `version` de `'v19.10'` a `'v19.11'`.
11. **Deploy**: 28/10/2026 desde la rama `feat/reparto-dos-tablas-sabado` (commits `1ad1694` y `9db7e5c`), **sin mergear a `master` todavía**. `flutter clean` + `flutter pub get` + `./build_web.sh`, se recreó `build/web/.vercel/project.json` (el clean se lo lleva puesto) y `vercel --prod --yes` desde `build/web`. Deploy `web-kxhqo9t1j`, que tomó el alias solo. La migración y el redeploy de `parse-reparto` se hicieron **antes** del build.

### Cambios v19.10 (28/10/2026) — Desglose de los kg de la semana

El dashboard decía "560,5 kg · 6 medias" y ahí se terminaba: para saber a quién se le vendió esa carne había que ir a Consultas y cruzarlo a mano. Ahora la tarjeta se toca y se ve.

1. **`lib/models/models.dart`**: `VentaRemitoSemana` (un remito visto desde un solo tipo de carne, con el flag `tieneOtrosTipos` y `totalFactura`), `VentaClienteSemana` (lo que se llevó un cliente, con los remitos ya ordenados cronológicamente) y `DesgloseSemanaTipo` (el desglose completo, con los clientes ordenados de mayor a menor kg y desempate alfabético por `compararNombres`). El archivo pasa a importar `compararNombres` de `utils/formatters.dart`.
2. **`lib/providers/app_provider.dart`**: `desgloseVentasSemana(tipo, [semana])`. Recorre **los mismos remitos y con el mismo `_normalizarTipo`** que `kgVendidosSemanasPorTipo` — si los dos no dan igual, uno está mal. Un remito sin items del tipo buscado se saltea entero.
3. **`lib/screens/detalle_kg_semana_screen.dart`** (nuevo): tarjeta de totales (kg / medias / facturado), contador de clientes y remitos, y un `ExpansionTile` por cliente con sus remitos (número, fecha, medias, kg e importe).
4. **`lib/screens/home_screen.dart`**: `_KpiCard` gana `onTap` — y cuando lo tiene, el chevron al lado del título, para que se note que se puede tocar. Las dos tarjetas de kg navegan al desglose pasándole `_semanaRef` y `_ofuscado`.
5. **Decisión: los números son solo los del tipo consultado.** Un remito puede traer novillo y cerdo juntos; si el desglose de novillo sumara el remito entero, la suma de la pantalla no daría el número de la tarjeta que se tocó. El total de la factura se muestra aparte y solo en esos remitos, que son los únicos donde los dos valores difieren.
6. **El ojo del dashboard viaja al desglose**: si los valores están ofuscados allá, también lo están acá. El toggle existe para mostrar la pantalla sin revelar números, y una pantalla hija que los muestre igual lo haría inútil.
7. **`test/desglose_semana_test.dart`** (nuevo, 11 casos): las sumas, el orden por kg, el desempate alfabético sin acentos, el remito mezclado y la semana vacía. El proyecto pasa a **130 tests en verde**.
8. **`lib/utils/app_config.dart`**: `version` de `'v19.9'` a `'v19.10'`.
9. **Sin migración**: sale todo de `remitos` + `remito_items`, que ya estaban en memoria.
10. **Deploy**: 28/10/2026 desde la rama `feat/desglose-kg-semana` (PR #14, merge commit `b264df2`). `flutter clean` + `flutter pub get` + `./build_web.sh`, se recreó `build/web/.vercel/project.json` (el clean se lo lleva puesto) y `vercel --prod --yes` desde `build/web`. Deploy `web-5xly6g6d8`, que tomó el alias solo.

### Cambios v19.9 (28/10/2026) — Depósito: kilos, partes de la media y reset

Los tres pedidos del usuario sobre el módulo Depósito: empezar la carga de cero, **ver los kilos** de lo que hay en la cámara (se cargaban y no se mostraban nunca) y **ver qué pedazo** quedó cuando se remite un corte.

1. **`supabase_migration_deposito_arranque_kg.sql`** (raíz del repo): `kg_novillo` / `kg_cerdo` en `deposito_config`. **Prerequisito del deploy**: `DepositoConfig.toMap()` manda siempre esas columnas.
2. **`supabase_reset_deposito.sql`** (raíz del repo, de una sola vez): borra `deposito_movimientos` y `deposito_movimientos_eliminados` y deja el arranque en 0 medias / 0 kg con fecha de hoy. No toca remitos ni cargas — el depósito deriva el stock, así que mover la fecha de arranque alcanza. **Ojo**: los remitos confirmados con fecha de HOY cuentan igual (la ecuación corta desde `fecha_inicio` inclusive); para arrancar limpio desde mañana, `CURRENT_DATE + 1`.
3. **`lib/models/models.dart`**: `DepositoConfig.kgNovillo` / `kgCerdo` + `kgInicialDe`. Las constantes `partePierna` / `parteOctavo` / `partePlancha`, el helper `partesDeCorte` (qué parte se lleva cada tipo de carne; el `1/4 delantero` se lleva dos) y `labelParte` (singular/plural). La clase **`CortesVendidos`**: medias abiertas = máximo de las tres cuentas, sueltas = lo que sobra de ese máximo. En `StockDeposito`, los seis componentes de kg + `mediasSinPesar` + `cortes`, y los getters `kgTeorico` (nunca negativo), `kgIncompleto`, `tieneKg`, `mediasSueltas`, `mediasEnteras` y `hayPartesSueltas`.
4. **`lib/providers/app_provider.dart`** (`_componentesDeposito`): junto a cada componente de medias se acumula el kg que le corresponde — `cargas.kg_media_res` (null hasta la faena, y ahí la carga suma medias pero todavía no kilos), `remito_items.kg_total`, `movimiento.totalKg` — y lo que no tiene kilos se suma a `sinPesar`. Los kg de las salidas que esperan remito van **a prorrata** de lo que sigue abierto. En el mismo recorrido de los remitos se cuentan los cortes (piernas / octavos / planchas).
5. **`lib/screens/deposito_screen.dart`**: widget `_KgEnCamara` (los kilos bajo el número grande, en naranja cuando están incompletos) y `_PartesSueltas` (panel "DISPONIBLE PARA VENDER" con las medias enteras y lo suelto). `_Fila` gana el parámetro `kg`, que va **abajo del label** y no en una tercera columna: en el celular tres columnas de números quedan ilegibles. El diálogo del arranque suma los dos campos de kg (opcionales).
6. **`test/deposito_test.dart`**: 17 casos nuevos (58 en el archivo, 121 en el proyecto) — la tabla de partes, el caso textual del usuario (una pierna remitida deja un octavo y una plancha), que tres piernas abran tres medias, que **enteras + sueltas den exactamente el stock**, que el cerdo no se fraccione, la ecuación de los kg, que `kgTeorico` no dé negativo y que **los kilos no cambien el veredicto**.
7. **`lib/utils/app_config.dart`**: `version` de `'v19.8'` a `'v19.9'`.
8. **Decisión mantenida de v19.6**: los kilos son **informativos**. La alerta de faltantes sigue siendo por medias; lo que cambió es que ahora los kilos se ven.

### Cambios v19.8 (27/10/2026) — Orden alfabético de los vendedores

Es la contracara de v19.7: lo mismo que se hizo con los clientes, ahora con los vendedores.

1. **`lib/providers/app_provider.dart`**: `_ordenarVendedores()` (mismo `compararNombres` que los clientes) deja `_vendedores` A→Z **al cargar, al agregar y al editar** — el nombre puede cambiar, así que editar también reordena. El getter `vendedores` pasa a `UnmodifiableListView`: desde que su orden es la fuente de verdad de todos los listados, un `app.vendedores.sort(...)` desde una pantalla lo rompería en silencio y lejos del lugar del error. Los 18 usos de hoy son de solo lectura, así que no cambia ningún comportamiento: cambia el costo de equivocarse de acá en adelante.
2. **`lib/screens/clientes_screen.dart`** y **`lib/screens/consultas_screen.dart`**: se sacaron los dos `..sort` que quedaron de más (los chips de filtro por vendedor y el dropdown de Historial). Ordenaban con `compareTo` crudo, que manda minúsculas y acentos al final.
3. **Sin migración ni modelo nuevo**: es solo orden de visualización.
4. **`lib/utils/app_config.dart`**: `version` de `'v19.7'` a `'v19.8'`.

### Cambios v19.6 (26/10/2026) — Kg por media en el depósito

Saber que hay 8 medias en la cámara no dice cuánto hay: dos medias pueden diferenciarse en 40 kg.

1. **`supabase_migration_deposito_kg.sql`** (raíz del repo): columna `kgs_por_media` JSONB en `deposito_movimientos` y en `deposito_movimientos_eliminados`. **Prerequisito del deploy** (ver el estado actual).
2. **`lib/models/models.dart`**: `DepositoMovimiento.kgsPorMedia` (`List<double>`, un valor por media, mismo patrón que `NotaPedidoItem`), más los getters `totalKg`, `tieneKg` y `mediasSinPesar`. La auditoría también se los lleva, para poder reconstruir un movimiento borrado entero. `StockDeposito.kgRecuento` y `kgPendientes`. El helper `_leerKgs` tolera que la columna no exista y que traiga basura.
3. **`lib/screens/deposito_screen.dart`**: widget `_CamposKg` — campos "Media 1", "Media 2"… que aparecen solos según las medias tipeadas, con el total al pie y cuántas faltan pesar. Va en Entrada, Salida y Recuento (el Recuento pasó a `StatefulBuilder` para poder reaccionar al tipeo). Los kg se muestran en el historial, en el aviso de salidas sin remito, en el diálogo de baja y en la tarjeta de stock (los del último recuento).
4. **`lib/providers/app_provider.dart`**: `stockDeposito` pasa los kg del último recuento.
5. **`test/deposito_test.dart`**: 11 casos nuevos (41 en el archivo, 100 en el proyecto) — el total, el conteo de las que faltan pesar, la tolerancia del `fromMap`, que la baja se lleve los kilos y, sobre todo, **que los kg NO cambien el veredicto**, que sigue siendo por medias.
6. **Decisiones del usuario**: un kg por cada media (no un total); los kg **solo se muestran**, no entran en la ecuación.
7. **Decisión del desarrollador**: los kg son **opcionales**. Un campo obligatorio que frena a la cajera cuando no tiene la balanza a mano haría que no registre la salida, reabriendo el agujero que el módulo vino a tapar.

### Cambios v19.5 (26/10/2026) — Módulo Depósito

> **Desactualizado a propósito**: la ecuación que describe esta sección (cargas + remitos + equivalencias + FIFO) **se sacó en v19.16**. Queda como registro de cómo nació el módulo. Lo que vale hoy está en "Depósito — el libro de stock" y en "Cambios v19.16".

**El problema que lo motivó**: desde el depósito sacaron dos medias para un cliente y la cajera se olvidó de cargar el remito. Joaquín preguntaba dónde estaban esas dos medias y nadie podía decirlo: plata perdida.

1. **`supabase_migration_deposito.sql`** (raíz del repo, **sin correr todavía**): `deposito_config`, `deposito_movimientos`, `deposito_movimientos_eliminados`, los índices, el RLS off y el `INSERT` del permiso `gestionar_deposito` (asignado a los roles `es_admin` **y** a los que ya tenían `gestionar_proveedores`). Ver "Tablas Depósito (v19.5)".
2. **`lib/models/models.dart`**: `DepositoConfig`, `DepositoMovimiento`, `DepositoMovimientoEliminado` y `StockDeposito` (el resultado de la ecuación, con cada componente expuesto por separado: si Joaco no ve de dónde sale cada número, no le cree a la alerta). Más los helpers top-level `equivalenciasMedia`, `equivalenciaEnMedias`, `stockDeTipoCarne`, `mediasPorAnimal` y `toleranciaMedias`.
3. **`lib/services/database_service.dart`**: CRUD de las tres tablas. `getDepositoConfig` y `getDepositoMovimientos` son **tolerantes a que la tabla no exista** (null / lista vacía) para que la app ande antes de correr la migración. El upsert de la config va `onConflict: 'unica'`.
4. **`lib/providers/app_provider.dart`**: `cargarDeposito({forzar})` lazy — y que **primero se asegura de que los proveedores estén cargados**, porque el stock sale de las cargas y esas también son lazy. Los getters `stockNovillo` / `stockCerdo` / `hayAlertaDeposito`, el cálculo en `stockDeposito` + `_componentesDeposito` + `_salidasPendientes` + `_remitidasCargadasDespuesDe` + `_ultimoRecuento`, y el ABM (`guardarDepositoConfig`, `registrarMovimientoDeposito`, `eliminarMovimientoDeposito`). Las bajas escriben primero la fila de auditoría con el motivo y después borran.
5. **`lib/screens/deposito_screen.dart`** (nuevo): una tarjeta por tipo con el número grande ("lo que debería haber en la cámara"), el desglose completo, el veredicto en cartel de color y la lista de salidas que esperan remito. Botones **Entrada** y **Salida**, "Registrar recuento" por tipo, arranque editable desde el AppBar e historial donde cada movimiento se puede borrar con motivo.
6. **`lib/main.dart`**: item "Depósito" en el menú del FAB (ícono `inventory_2`), gateado por `tiene('gestionar_deposito')`, después de "Lista de reparto".
7. **`lib/utils/formatters.dart`**: `formatMedias` (`8` / `10,5` / `0,33`) y `formatMediasConUnidad` (`1 media` / `8 medias`).
8. **`lib/services/soporte_service.dart`**: al catálogo de módulos se le agregaron **'Depósito'** y **'Proveedores'** (este último faltaba desde v19, así que un reclamo de ese módulo caía en "Otro").
9. **`test/deposito_test.dart`** (nuevo, 30 casos): la tabla de equivalencias (incluido que pierna + octavo + plancha den **una media justa**), los dos stocks separados, el veredicto con su tolerancia y el circuito completo de la salida sin remito — incluida la trampa de que, cargado el remito, las 2 medias **no se cuenten dos veces**.
10. **`lib/utils/app_config.dart`**: `version` de `'v19.4'` a `'v19.5'`.
11. **Decisiones del circuito** (acordadas con el usuario antes de implementar): arranque **de cero** en una fecha configurada (contar todo desde siempre daría cualquier cosa, porque hay remitos de hace meses y cargas recién desde octubre); **tabla de equivalencias** para los cortes con la media de novillo partida en tres; **dos stocks separados** novillo/cerdo; cierre de las salidas pendientes **automático por FIFO** (sin elegir cliente).
12. **`test/widget_test.dart` reescrito**: venía del scaffold de `flutter create` y pumpeaba una clase `MyApp` que **nunca existió** en este proyecto (la raíz es `DonChachoApp`), así que no compilaba y `flutter test` daba rojo entero, tapando regresiones de los otros archivos. Pumpear `DonChachoApp` tampoco sirve de smoke test: construye un `AppProvider` (→ `DatabaseService` → `Supabase.instance.client`) y `AppWrapper.initState` llama a `AuthService.restaurarSesion()`; sin `Supabase.initialize` revienta, y con él el test saldría a la red contra producción. Ahora prueba `StatusPill` (el pill de estados que usan remitos, NDP, soporte y proveedores): el mapeo tipo → par de colores y que fondo y letra nunca sean el mismo color. Con esto el proyecto pasa a tener **89 tests en verde** y `flutter analyze` sin un solo error.
13. **Pendiente**: precargar el TOTAL MEDIAS de la Lista de reparto desde el stock del depósito (hoy se tipea a mano y los dos números pueden no coincidir).

### Cambios v19 (19/10/2026) — Módulo Proveedores (en producción desde el 20/10/2026)
1. **`supabase_migration_proveedores.sql`** (raíz del repo, ya corrida el 20/10/2026): `proveedores`, `cargas`, `carga_pagos`, `cargas_eliminadas`, `carga_pagos_eliminados`, los índices, el RLS off y el `INSERT` del permiso `gestionar_proveedores` (asignado automáticamente a los roles con `es_admin = TRUE`). Ver "Tablas Proveedores / Cargas (v19)".
2. **`lib/models/models.dart`**: `Proveedor`, `Carga`, `CargaPago`, `CargaEliminada`, `CargaPagoEliminado`. En `Carga` la aritmética está duplicada en Dart (`kgNeto`, `totalAPagar`, `rindeCarga`, `kgEsperados`, `diferenciaRindeKg/Pesos`) para calcular en vivo en el formulario; los valores que devuelve Postgres quedan aparte en `kgNetoServidor` / `totalAPagarServidor` / `rindeCargaServidor`. `toMap()` omite `numero` cuando vale 0 (lo pone la secuencia) y **nunca** manda las columnas generadas.
3. **`lib/services/database_service.dart`**: CRUD de las cinco tablas. Todas las lecturas completas usan el helper `_paginado`. `insertCarga` hace `.select().single()` para recuperar el número y las columnas generadas. `contarCargasDeProveedor` es lo que impide borrar un proveedor con historia.
4. **`lib/providers/app_provider.dart`**: `cargarProveedores({forzar})` lazy (3 queries en `Future.wait`), los getters de saldo en cadena, y el ABM (`guardarProveedor`, `eliminarProveedor`, `crearCarga`, `actualizarCarga`, `eliminarCarga`, `guardarPagoCarga`, `eliminarPagoCarga`). Las bajas escriben primero la fila de auditoría con la observación y después borran.
5. **Pantallas nuevas**: `proveedores_screen.dart`, `gestion_proveedores_screen.dart`, `carga_form_screen.dart`, `carga_detalle_screen.dart` (ver la estructura del proyecto).
6. **`lib/main.dart`**: tab "Proveedores" (ícono camión) entre Clientes y Consultas, gateada por `tiene('gestionar_proveedores')`.
7. **`lib/utils/formatters.dart`**: nuevo `formatPorcentaje` (`58%` / `55,49%`) y la **entrada de números con separador de miles**: `MilesInputFormatter` (pone los puntos mientras se escribe: `10.000.000`), `parseNumero` (lee ese texto: los puntos son miles, la coma es el decimal) y `textoMiles` (precarga un controller ya formateado). Todos los campos numéricos del módulo Proveedores lo usan. **Si se agrega un campo numérico ahí, tiene que usar los tres juntos**: con `MilesInputFormatter` puesto, un `double.tryParse` común lee `10.000.000` como `0`. Cubierto por `test/formatters_test.dart`.
8. **v19.1 — tipo de animal del proveedor (novillo / cerdo)**: migración `supabase_migration_proveedor_tipo.sql` (ya corrida) con la columna `tipo` + CHECK + índice. En `Proveedor`: constantes `tipoNovillo`/`tipoCerdo`, campo `tipo`, getters `esCerdo` y `tipoLabel`. Se elige en el ABM con un `SegmentedButton` ("¿Qué vende?", default Novillo) y se muestra como pill en la lista y pegado al nombre en el dropdown de `carga_form_screen`. **Vive en el proveedor, no se congela en la carga** (ver la sección de tablas). Existe para que el módulo de ganancia separe costo/kg novillo de costo/kg cerdo.
9. **`lib/utils/app_config.dart`**: `version` pasó de `'v18.37'` a `'v19.1'` (el string viaja en cada ticket de soporte, así se sabe contra qué build se reportó el problema — acordarse de subirlo en cada deploy).
10. **Deploy**: PR #4 mergeada a `master` (merge commit `9e24dc2`). Build con `flutter clean` + `flutter pub get` + `./build_web.sh` + `vercel --prod --yes` desde `build/web`, y después `vercel alias set <deploy> web-six-indol-svg13avcfl.vercel.app` (el deploy nuevo **no** toma el alias solo). Deploy `web-f8bi14j2f`.
11. **Pendiente**: el **módulo de ganancia del admin** queda para después. Va a necesitar los costos del viaje (achuras, costo de faena, VEP, flete vivo, sueldo del camionero, lavadero, combustible) más la diferencia de rinde que ya calcula este módulo, y el `tipo` del proveedor para separar costo/kg novillo de costo/kg cerdo.

### Cambios v18.36 (07/10/2026) — Módulo de Soporte
1. **`supabase_migration_soporte.sql`** (raíz del repo, ya corrida): tabla `soportes` + bucket privado `soporte-adjuntos` + policies de insert/select para el rol `anon`. Ver "Tabla Soporte (v18.36)".
2. **`lib/utils/app_config.dart`** (nuevo): `version`, `clienteNombre` y `soporteWhatsapp` vía `String.fromEnvironment` (`--dart-define`). `soporteWhatsapp` **arranca vacío**: hasta que tenga un número, el ticket se guarda igual pero no se abre WhatsApp y el botón del formulario dice "Registrar el problema" en vez de "Enviar a soporte" (getter `tieneWhatsappSoporte`). Formato internacional sin `+` ni espacios (Argentina celular: `549` + área sin 0 + número). Existe para que el módulo sirva en otras instalaciones sin tocar código.
3. **`lib/models/models.dart`**: clase `TicketSoporte` (modulo, descripcion, bloqueante, adjuntoPath, estado, respuesta, reportadoPor, rol, appVersion, plataforma, resueltoEn/Por). Getters `numeroFormateado` (`S-0001`), `estadoLabel`, `tieneAdjunto`, `esAbierto/esEnRevision/esResuelto`. `toMap()` **omite `numero` cuando es 0** para que lo asigne la secuencia de Postgres.
4. **`lib/services/database_service.dart`**: `getTicketsSoporte({reportadoPor})` (usa el helper `_paginado`, ordena bloqueantes primero y después por fecha desc), `insertTicketSoporte` (`.select().single()` para recuperar el número asignado) y `updateTicketSoporte` (estado, respuesta, resuelto_en/por).
5. **`lib/services/soporte_service.dart`** (nuevo): catálogo `modulos` (las 15 partes del sistema), `plataforma` (`kIsWeb` + `defaultTargetPlatform`, sin dependencia de `dart:html`), `subirAdjunto` (path `uuid.ext` en el bucket, mime por extensión), `urlAdjunto` (link firmado 90 días) y `avisarPorWhatsapp` (arma el texto del reclamo y abre `wa.me`; devuelve false si no hay número configurado o el dispositivo no puede abrir el link). **wa.me no puede adjuntar archivos** — por eso la foto va a Storage y viaja como link.
6. **`lib/screens/soporte_form_screen.dart`** (nuevo): el envío se habilita con módulo elegido + descripción de 10 caracteres o más. Si falla la subida de la foto avisa y manda el reclamo igual (la foto es un plus, el reclamo no se pierde). Sección "Tus reclamos" con los últimos 5 del usuario, su estado y la respuesta.
7. **`lib/screens/bandeja_soporte_screen.dart`** (nuevo, solo admin): 3 tabs con contadores, `RefreshIndicator`, y un estado de error que pregunta explícitamente si se corrió la migración (es el fallo esperable hasta que exista la tabla). El detalle firma la URL al abrir y tiene botón "Abrir la foto" porque los HEIC de iPhone no se renderizan en el navegador.
8. **`lib/main.dart`**: items "Reportar un problema" (todos los roles) y "Bandeja de soporte" (solo admin) en el menú del FAB, antes de "Cerrar sesión". Se **quitó el gate `tieneFab`** (`crear_remito || crear_pago`): con él, un rol restringido no habría podido reportar nada, y ya contradecía a NC/D y Reparto, que son para todos.
9. **`lib/utils/formatters.dart`**: nuevo `formatFechaHora` (`dd/MM/yyyy HH:mm`).
10. **`pubspec.yaml`**: vuelve `image_picker: ^1.1.2` (se había sacado en v18.17 con el OCR). Tras esto conviene `flutter clean` antes de buildear, por el `web_plugin_registrant.dart` cacheado.

### Cambios v18.31 (22/09/2026) — "Guardar + Enviar" en Notas de Crédito/Débito
1. **`lib/screens/nota_cd_form_screen.dart`**: debajo del botón "Registrar nota de crédito/débito" se agregó un `OutlinedButton.icon` "Guardar + Enviar" (ícono `Icons.share`), deshabilitado con las mismas condiciones (`_guardando || _clienteId == null || _monto <= 0`). Llama al nuevo método `_guardarYEnviar`, que construye la `NotaCreditoDebito`, la guarda con `app.agregarNotaCreditoDebito` y, si hay cliente, genera y comparte el comprobante con `EstadoCuentaService.generarComprobanteNcd` (pasa `saldoActual: app.getSaldoCliente(...)` ya recalculado post-nota, que internamente hace `Printing.sharePdf` → abre la hoja de compartir para enviarlo por WhatsApp). Al terminar muestra snackbar y hace `pop(context, nota)`. Mismo patrón que "Guardar + Recibo" del formulario de pagos (`pago_form_screen.dart` → `_guardarYCompartir`).
2. **Sin cambios de BD ni migraciones.** Solo UI.
3. **Deploy**: rama `feat/reparto-precarga`. Build con `flutter clean` + `flutter pub get` + `build_web.sh` + `vercel --prod --yes` desde `build/web`.

### Cambios v18.30 (16/09/2026) — Precarga del reparto de la semana anterior
1. **`lib/services/database_service.dart`** — nuevo `getRepartoListaOPlantilla(semanaInicio, dia)`: devuelve `({RepartoLista lista, bool precargado})`. Si ya existe la lista guardada de esa semana/día la devuelve tal cual (`precargado: false`); si no, arma una **plantilla nueva sembrada con los items de la semana anterior** (mismo día) — copia solo `clienteId`, `mediasCarne`, `mediasCerdo`, `sucursal` y `orden`; el TOTAL MEDIAS y las notas quedan en blanco por ser propios de cada semana. `precargado: true` solo si la semana previa tenía items. **Base común** que usan la pantalla y el asistente para que ambos hagan update/insert/delete sobre lo mismo. No toca la BD ni el modelo.
2. **`lib/screens/reparto_screen.dart`**:
   - `_cargar()` ahora usa `getRepartoListaOPlantilla` (reemplazó al `getRepartoLista` directo) y guarda el flag en el nuevo campo `bool _precargado`.
   - Banner `_bannerPrecargado()` ("Precargado de la semana pasada. Revisá y tocá guardar para confirmar la lista de esta semana.") visible mientras `_precargado && !_cargando`.
   - **Anti-listas-fantasma**: `_cambiarSemana`/`_cambiarDia` solo auto-guardan si `_hayContenido && !_precargado` (una plantilla sin tocar no se persiste solo por navegar). Helper `_marcarModificado()` (baja `_precargado`) llamado desde los `onChanged` de los campos numéricos, sucursal y notas, y desde agregar/quitar cliente. `_persistir` (y por ende Guardar / Generar PDF) pone `_precargado = false`.
3. **`lib/screens/asistente_reparto_sheet.dart`** (chatbox del robot):
   - `_aplicar()` carga la base con `getRepartoListaOPlantilla(_semana, prop.dia).lista` en vez de crear una lista vacía → el update/insert/delete del asistente se hace **sobre la lista precargada** (los clientes que repiten de la semana anterior), no sobre una lista en blanco.
   - Botón nuevo **"Ver lista del día"** en el encabezado (ícono `receipt_long`, al lado del selector Jue/Vie): `_verLista()` lee `getRepartoListaOPlantilla` y abre un `showModalBottomSheet` con el widget `_VistaLista` (solo lectura): TOTAL MEDIAS, clientes A→Z con carne/cerdo y sucursal, y SOBRANTE DEPÓSITO. Avisa si es plantilla precargada. Se relee de la BD en cada apertura (refleja lo recién aplicado).
4. **Deploy**: rama `feat/reparto-precarga` (commit `239c795`). Build con `flutter clean` + `flutter pub get` + `build_web.sh` + `vercel --prod --yes` desde `build/web`. Alias `web-six-indol-svg13avcfl.vercel.app` apuntando al nuevo deploy (`web-7uz45r5gp…`).
5. **Fix duplicados (commit `03af45a`)** — `lib/services/database_service.dart` (`getRepartoLista`): al leer una lista se **colapsan filas exactamente idénticas** (mismo `clienteId` + `sucursal` + `mediasCarne` + `mediasCerdo`) con un `Set` de claves vistas. Corrige el bug de "todo duplicado" reportado tras la precarga; **auto-repara la BD** al volver a guardar la semana y **no toca las filas legítimas por sucursal** (esas difieren entre sí). Redeploy a prod desde `build/web`.

### Cambios v18.29 (09/09/2026) — Lista de reparto en orden alfabético
1. **`lib/screens/reparto_screen.dart`** (`_grilla`): arma `filasOrdenadas = [..._filas]..sort(...)` comparando `app.clientePorId(fila.clienteId)?.nombreRazonSocial` en minúsculas, y el `for` de filas de cliente itera esa copia en vez de `_filas` por índice. Solo cambia el orden de visualización — el `orden` persistido y los controllers de cada `_Fila` no se tocan.
2. **`lib/services/reparto_service.dart`** (`_generarPdf`): la tabla de clientes itera `[...lista.items]..sort(...)` comparando `nombre(clienteId)` en minúsculas. Las filas fijas TOTAL MEDIAS y SOBRANTE DEPÓSITO quedan intactas.
3. **Deploy**: commit `2b7c858` en `feat/reparto-voz`, luego mergeada a `master`. Build con `flutter clean` + `flutter pub get` + `build_web.sh` + `vercel --prod --yes` desde `build/web`. Alias `web-six-indol-svg13avcfl.vercel.app` apuntando al nuevo deploy.

### Cambios v18.28 (03/09/2026) — Detalle de NC/ND desde la ficha del cliente
1. **`lib/screens/nota_cd_form_screen.dart`**: nuevo parámetro `notaInicial` (`NotaCreditoDebito?`). Si viene, la pantalla entra en **modo ver (solo lectura)** — getter `_soloLectura`; en `initState` precarga `_clienteId`, `_tipo`, `_fecha`, `_montoCtrl`, `_motivoCtrl` desde la nota; `build` retorna temprano `_buildSoloLectura` en vez del formulario editable.
   - `_buildSoloLectura`: AppBar "Ver nota de crédito/débito" con botón **eliminar** (solo con permiso `editar_pago` → `_eliminarNota`, que confirma, llama `app.eliminarNotaCreditoDebito` y hace `pop`). Card con número (NC/ND-XXXX), `StatusPill` Crédito/Débito, descripción del efecto, y filas (`_filaLectura`): Cliente, Vendedor, Fecha, Monto (verde con `-` si es crédito), Motivo, Registrado por, Saldo actual del cliente. Botón **"Descargar comprobante"** → `_descargarComprobante` (reusa `EstadoCuentaService.generarComprobanteNcd`). Se agregó el import de `estado_cuenta_service.dart`.
2. **`lib/screens/cliente_detalle_screen.dart`**: las tarjetas de notas C/D (v18.27) ahora son clickeables. Import de `nota_cd_form_screen.dart` + nuevo `_verNota(context, nota)` que hace `Navigator.push` a `NotaCdFormScreen(notaInicial: nota)`. La tarjeta **NC** se envolvió en `InkWell(onTap: _verNota)`; la **ND** cambió su `onTap` de `null` a `_verNota`. El **remito** sigue abriendo su `RemitoFormScreen` editable como antes.
3. **Deploy**: rama `feat/reparto-voz`. Build con `flutter clean` + `flutter pub get` + `build_web.sh` + `vercel --prod --yes` desde `build/web`. Alias `web-six-indol-svg13avcfl.vercel.app` apuntando al nuevo deploy.

### Cambios v18.27 (03/09/2026) — Notas C/D en la ficha del cliente
1. **`lib/screens/cliente_detalle_screen.dart`**: la lista de la ficha mostraba solo remitos, así que el saldo (`remitos + débitos − pagos − créditos`) no cuadraba a la vista cuando el cliente tenía notas C/D. Ahora se arma una lista **unificada de movimientos** (`tipo: 'remito' | 'nd' | 'nc'`) a partir de `app.bucketsDeudaCliente` + `app.notasCreditoDebito`:
   - Los **buckets** (remitos confirmados + notas de débito) se recorren igual que antes; cada uno aporta un ítem con su `deuda` restante FIFO y su `vencimiento`. Las **ND** se renderizan como un cargo más (Saldado/Vencido/Pendiente, "Deuda restante" en rojo), con `Débito: $…` + el motivo en lugar de kg. Las ND **no son clickeables** (el form de notas es solo de creación, no recibe `notaInicial`).
   - Las **NC** (créditos) se agregan aparte desde `notasCreditoDebito.where(esCredito)`: tarjeta con borde verde, pill "Crédito" (`StatusType.success`), motivo y monto en verde con signo `-`.
2. Ordenamiento por `fecha` desc sobre la lista unificada (antes se casteaba a `Remito`). El contador de "Vencidos" (`cantVencidos`) ahora cuenta remitos **y** ND vencidas (excluye NC), consistente con `saldoVencidoCliente` que ya las contemplaba (v18.25).
3. Encabezado de la sección: "Remitos" → **"Remitos y notas"**; el contador "N en total" usa `movimientosVisibles.length`.
4. El saldo/`deudaVencida` en sí **no cambiaron** (siempre fueron correctos vía provider); solo faltaba que la lista lo explicara visualmente.
5. **Deploy**: rama `feat/reparto-voz` (commit `8a1fc11`). Build con `flutter clean` + `flutter pub get` + `build_web.sh` + `vercel --prod --yes` desde `build/web`. Alias `web-six-indol-svg13avcfl.vercel.app` apuntando al nuevo deploy.

### Cambios v18.26 (03/09/2026) — Asistente de reparto por IA (robot chatbox)
1. **Edge Function `parse-reparto`** (`supabase_functions/parse-reparto/index.ts`, runtime viejo `serve`): proxy de un solo paso texto→JSON a la API de Claude. Recibe `{texto, dia_actual, clientes, model?}`, arma un prompt en español con la lista de clientes reales y devuelve `{dia, items[]}` donde cada item es `{accion:'cargar'|'borrar', cliente, carne, cerdo, sucursal, confianza:'alta'|'dudosa'}`. **Modelo por defecto `claude-sonnet-4-5-20250929`** (overridable por el campo `model` del body). CORS + OPTIONS. **Deploy por dashboard** (el CLI local está logueado en OTRA cuenta y no ve el proyecto vivo). Verify JWT ON (la publishable key lo satisface).
   - **IMPORTANTE (causa del "404" que costó diagnosticar)**: el modelo `claude-sonnet-4-20250514` que se usó primero **fue retirado por Anthropic** → la API devolvía `404 not_found_error` y la app lo mostraba como "El asistente no respondió (404)". No era Supabase, ni el slug, ni el deploy. Los modelos vigentes de la key se listan con `GET https://api.anthropic.com/v1/models`. Si en el futuro vuelve a fallar con 404, es casi seguro que el modelo se retiró: actualizar el string a uno vigente.
2. **`lib/services/reparto_ia_service.dart`** (nuevo): `RepartoIaService.interpretar({texto, diaActual, clientes})` hace POST a `$base/functions/v1/parse-reparto` (base = `supabase.rest.url` sin `/rest/v1`) con headers `apikey` + `Authorization: Bearer` usando la **publishable key** (NO el JWT). Timeout 40s. Modelos `RepartoParseItem` / `RepartoParseResult`.
3. **`lib/screens/asistente_reparto_sheet.dart`** (nuevo): chatbox autónomo. Entry point `mostrarAsistenteReparto(context)` (abre `showModalBottomSheet`). Encabezado con avatar de robot + `SegmentedButton` Jue/Vie. El usuario escribe/dicta (micrófono del teclado iOS), se llama a la IA, se arma una **propuesta** con resolución nombre→clienteId (single match auto-resuelve; ambiguo/no encontrado → `_SelectorCliente` local). Cada ítem: chip CARGAR/BORRAR + checkbox incluir + editar cliente. Al **Confirmar** (`_aplicar`): carga `getRepartoLista(semana, dia)` (o crea `RepartoLista` nueva), muta items (borrar quita por clienteId; cargar actualiza o agrega `RepartoItem`), `guardarReparto(lista)`. Persiste directo a la BD → funciona desde cualquier pantalla, independiente del estado en memoria de `RepartoScreen`.
4. **`lib/main.dart`**: `MainShell` envuelve el body en un `Stack` con el `IndexedStack` + un `Positioned(right:16, bottom:20)` con `FloatingActionButton(heroTag:'robot_asistente', Icons.smart_toy)` que llama `mostrarAsistenteReparto`. **Siempre visible** en todas las tabs; convive con el FAB central '+' sin superponerse.
5. **Decisión de UX**: la barra de dictado inline en la pantalla de Reparto se **descartó** — un solo camino, el robot flotante. `reparto_screen.dart` quedó en su estado original (sin código IA).
6. **Deploy**: rama `feat/reparto-voz`. Build con `flutter clean` + `flutter pub get` + `build_web.sh` + `vercel --prod --yes` desde `build/web`. Alias `web-six-indol-svg13avcfl.vercel.app` apuntando al nuevo deploy.

### Cambios v18.24 (26/08/2026) — Lista de reparto
1. **Migración** `supabase_migration_reparto.sql` (raíz del repo, **ya ejecutada en Supabase**): tablas `reparto_listas` (UNIQUE semana_inicio+dia) y `reparto_items` (FK a listas CASCADE + FK a clientes), ambas con RLS off. Ver "Tablas Lista de reparto (v18.24)".
2. **`lib/models/models.dart`**: nuevas clases `RepartoLista` (semanaInicio, dia `'jueves'|'viernes'`, totalMediasCarne/Cerdo, notas, items; getters `diaLabel`, `repartidoCarne/Cerdo`, `sobranteCarne/Cerdo` = total − repartido) y `RepartoItem` (clienteId, mediasCarne/Cerdo, orden, listaId).
3. **`lib/services/database_service.dart`**: `getRepartoLista(semanaInicio, dia)` (normaliza a lunes de la semana, carga items por `orden`; tolerante si la tabla no existe → null) y `guardarReparto(lista)` (reusa el id existente de (semana,dia) para no violar el UNIQUE, upsert de cabecera + delete/insert de items).
4. **`lib/services/reparto_service.dart`** (nuevo): `RepartoService.generarYCompartir({lista, clientes})` → PDF A4 con logo, título "LISTA DE REPARTO" + "Reparto del {día}" + rango de semana, tabla CLIENTES/CARNE/CERDO con fila TOTAL MEDIAS (celeste), filas por cliente en orden y fila SOBRANTE DEPOSITO, y recuadro de NOTAS si hay. `Printing.sharePdf`.
5. **`lib/screens/reparto_screen.dart`** (nuevo): `RepartoScreen`. Navegación semanal `< >` (`>` deshabilitado en semana actual), `SegmentedButton` Jueves/Viernes (auto-guarda al cambiar si hay contenido), TOTAL MEDIAS editable arriba, filas por cliente con dos campos numéricos + borrar, SOBRANTE calculado en vivo (rojo si negativo), TextField de NOTAS. FAB "Agregar cliente" (bottom sheet con búsqueda, excluye ya agregados). Acciones de AppBar: Guardar y Generar PDF (persiste antes de generar).
6. **`lib/main.dart`**: opción **"Lista de reparto"** en el menú del FAB (ícono `local_shipping`, subtítulo "Armar el reparto de la semana"), **sin gate de permiso**, hace `Navigator.push` a `RepartoScreen`.
7. **Fase 2 pendiente (explícito "después")**: carga de la lista por **audio de WhatsApp** (audio → transcripción → parseo estructurado). No implementado.
8. **Deploy**: rama `feat/notas-credito-debito`. Build con `flutter clean` + `flutter pub get` + `build_web.sh` + `vercel --prod --yes` desde `build/web`. Alias `web-six-indol-svg13avcfl.vercel.app` apuntando al nuevo deploy.

> **PWA / service worker**: la app cachea `main.dart.js`. Tras un deploy, un simple refresh (incluso Cmd+Shift+R) puede seguir mostrando la versión vieja. Para forzar la nueva: recargar 2 veces, o DevTools → Application → Service Workers → Unregister + Clear site data, o probar en Incógnito.

### Cambios v18.23 (26/08/2026)
1. **`lib/screens/cliente_detalle_screen.dart` — teléfono como link directo a WhatsApp.** La fila del teléfono en la ficha del cliente dejó de ser un `_InfoRow` de texto plano y ahora es un `InkWell` tocable: ícono verde de chat (`Icons.chat`, `0xFF25D366`) + "Teléfono: " + número subrayado en verde (`0xFF128C7E`). Al tocar llama al helper compartido `abrirWhatsApp` (top-level en `consultas_screen.dart`, v18.20; importado con `show abrirWhatsApp`). Mismo patrón visual/funcional que Directorio, Vencidos y la lista de Clientes.
2. **Deploy**: rama `feat/notas-credito-debito`. Build con `flutter clean` + `flutter pub get` + `build_web.sh` + `vercel --prod --yes` desde `build/web`. Alias `web-six-indol-svg13avcfl.vercel.app` apuntando al nuevo deploy.

### Cambios v18.22 (24/08/2026)
1. **`lib/services/database_service.dart` — fix del límite de 1000 filas de PostgREST (causa raíz de un bug de saldos en producción).** `getPagos`, `getRemitos` y `getAllRemitoItems` hacían `.select()...` sin paginar; PostgREST devuelve **máximo 1000 filas por defecto** y descarta el resto **sin error**. Cuando la tabla `pagos` pasó de 1000 filas, la app traía solo las 1000 más nuevas (orden `fecha desc`) y **perdía los pagos más viejos** → saldos inflados → remitos ya saldados reaparecían como vencidos (caso Perico). Fix: cada método pagina en batches de 1000 con `.range(from, from + pageSize - 1)` y un `.order('id')` estable como desempate, acumulando hasta que un batch venga con menos de 1000 filas. `getAllRemitoItems` ordena solo por `id`.
2. **Notas C/D en más vistas** (`estado_cuenta_service.dart`, `cliente_detalle_screen.dart`, `vendedor_detalle_screen.dart`, `recibo_service.dart`): `generarYCompartir` y `generarReporteVendedor` aceptan `List<NotaCreditoDebito> notasCD` y arman el FIFO con buckets de deuda (remitos + notas débito) y créditos (pagos + notas crédito), ordenados por fecha. La ficha de cliente usa `app.bucketsDeudaCliente`. El recibo PDF también contempla las notas C/D en el detalle de deuda.
3. **Dato de producción (no código)**: había un cliente **Perico duplicado** (uno inactivo/vacío "A" con 3 pagos huérfanos de prueba, y el activo "B" con todos los datos reales). Los 3 pagos de abril ($3.600.000 + $620.000 + $1.200.000) eran **error de carga** y se eliminan desde la app (Consultas › Historial › Pagos → botón eliminar). Tras borrarlos, Perico queda en **$4.906.800** (R-0669 $556.800 + R-0649 $4.350.000 pendientes). El duplicado vacío A se puede borrar.
4. **Deploy**: rama `feat/notas-credito-debito` (commits `5595059`, `ca2106c`, `fbe0db4`). Build con `flutter clean` + `flutter pub get` + `build_web.sh` + `vercel --prod --yes` desde `build/web`. Alias `web-six-indol-svg13avcfl.vercel.app` apuntando al nuevo deploy.

### Cambios v18.21 (18/08/2026)
1. **Modelo** `lib/models/models.dart`: nueva clase `NotaCreditoDebito` (id, clienteId, tipo `'credito'|'debito'`, fecha, numero, monto, motivo, registradoPor, creadoEn). Getters `esCredito`/`esDebito`, `numeroFormateado` (`NC-0001`/`ND-0001`), `tipoLabel`. `toMap`/`fromMap`.
2. **Migración** `supabase_migration_notas_credito_debito.sql` (raíz del repo, **ya ejecutada en Supabase**): tabla `notas_credito_debito` (RLS off) + tabla de auditoría `notas_cd_eliminadas` (RLS off).
3. **`lib/services/database_service.dart`**: `getNotasCreditoDebito()` (tolerante: devuelve `[]` si la tabla no existe todavía), `insertNotaCreditoDebito(nota)`, `deleteNotaCreditoDebito(nota, {eliminadoPor})` (best-effort: inserta en auditoría antes de borrar).
4. **`lib/providers/app_provider.dart`**: lista `_notasCD` + getter `notasCreditoDebito`, cargada en `cargarDatos` (Future.wait). `_recalcularSaldos`: `saldo = totalRemitos + totalDebitos − totalPagos − totalCreditos`. `agregarNotaCreditoDebito(nota)` (autonumera por tipo: max + 1) y `eliminarNotaCreditoDebito(id, {eliminadoPor})`. **Nuevo helper unificado `bucketsDeudaCliente(cliente)`** que arma los buckets de deuda (remitos confirmados + notas débito) ordenados por fecha y les aplica los créditos (pagos + notas crédito) en FIFO; devuelve `List<DeudaBucket>` (fecha, orden, vencimiento, remito?, notaDebito?, deuda). Se reescribieron `clientesConSaldoVencido`, `todosRemitosVencidos`, `todosRemitosNoVencidos`, `remitosVencidosCliente`, `saldoVencidoCliente` para usar este helper (antes duplicaban el FIFO). Las listas de vencidos ahora emiten entradas con `'remito'` o `'nota'` según el bucket.
5. **`lib/screens/nota_cd_form_screen.dart`** (nuevo): `NotaCdFormScreen` con `SegmentedButton` crédito/débito, búsqueda de cliente (patrón estándar), card de saldo actual → resultante, fecha, monto, motivo. Guarda con `agregarNotaCreditoDebito`.
6. **`lib/main.dart`**: opción **"Nota de crédito / débito"** en el menú del FAB (ícono `swap_vert`), **sin gate de permiso** (la ven todos: admin y cajeras/secretarias).
7. **`lib/screens/consultas_screen.dart`**:
   - **Vencidos**: las tarjetas soportan ND como bucket de deuda (leen `'remito'` o `'nota'`).
   - **Historial**: chip nuevo **"Notas C/D"** (`_filtroTipo == 'ncd'`); `_HistorialItem` gana `notaCD`; card con ícono `swap_vert` (verde crédito / rojo débito), badge NC/ND, motivo + registrado por, monto coloreado, botón de **comprobante PDF** y botón **eliminar** (requiere `editar_pago`, con confirmación). Resumen de totales incluye contador "N NC/ND".
   - **Reporte**: `_Movimiento` pasó de `esRemito` bool a `tipo` (`'remito'|'pago'|'nc'|'nd'`) con getters `sumaDeuda`/`esBucketDeuda`. El FIFO de estado ahora usa buckets = remitos + ND y créditos = pagos + NC. NC muestra pill "Nota créd.", ND participa del estado Pagado/Vencido. Leyenda actualizada.
8. **`lib/services/estado_cuenta_service.dart`**: `generarReporteCliente` acepta `notasCD` y replica el mismo FIFO/movimientos en el PDF. Nuevo `generarComprobanteNcd(nota, cliente, vendedor, saldoActual)` → PDF A4 de una página con el comprobante de la nota.
9. **Deploy**: rama `feat/notas-credito-debito` (commit `97f0391`, **no mergeada a `master` todavía**). Build con `flutter clean` + `flutter pub get` + `build_web.sh` + `vercel --prod --yes` desde `build/web` (deployada el 18/08/2026). El alias `web-six-indol-svg13avcfl.vercel.app` apunta al nuevo deploy.

### Cambios v18.20 (20/07/2026)
1. `lib/screens/consultas_screen.dart`: nueva función top-level `abrirWhatsApp(telefono)` — limpia no-dígitos, saca el `0` inicial del área y antepone `549` (celular Argentina), abre `https://wa.me/<num>` con `launchUrl`. Joaco carga los teléfonos como área + número, sin código de país.
2. `lib/screens/consultas_screen.dart` (`_DirectorioTab`): en cada tarjeta, ícono de WhatsApp (`Icons.chat`, verde `0xFF25D366`) junto al ícono de mapa + la línea del teléfono ahora es tocable (link subrayado verde) → ambos llaman `abrirWhatsApp`.
3. `lib/screens/consultas_screen.dart` (tab Vencidos): link "WhatsApp" al lado de "Ver en Maps" en cada tarjeta de remito vencido (envueltos en un `Row`).
4. `lib/screens/clientes_screen.dart`: `import 'consultas_screen.dart' show abrirWhatsApp;`. En cada tarjeta de la lista, `IconButton` de WhatsApp antes del saldo (solo si el cliente tiene teléfono).
5. **Deploy**: commit `aabcc78` directo a `master` + push; build con `flutter clean` + `build_web.sh` + `vercel --prod`. El alias `web-six-indol-svg13avcfl.vercel.app` apunta al nuevo deploy.

### Cambios v18.19 (08/07/2026)
1. `lib/models/models.dart` (`NotaPedidoItem`): nuevo campo `tipoCarne` (dropdown) **además** de `descripcion` (texto libre). Ambos en `toMap`/`fromMap` (`tipo_carne` / `descripcion`).
2. `lib/screens/nota_pedido_form_screen.dart`: la fila (`_FilaCard`) muestra el dropdown "Tipo de carne" (bind a `fila.tipoCarne`) **y** un TextField "Descripción (opcional)" (bind a `fila.descCtrl`, texto libre). `_FilaForm` pasó a tener `tipoCarne` + `descCtrl` (antes solo `descripcion` string que guardaba el tipo). `desdeItem`/`toItem`/`dispose` actualizados.
3. `lib/services/database_service.dart` (`confirmarNotaPedido`): el `tipo_carne` del remito se toma de `item.tipoCarne`; fallback a `item.descripcion` (NDPs v18.17 que guardaban el tipo ahí) y, si todo vacío, la regla por peso (`promKg > 60 ? Novillo : Cerdo`).
4. `lib/services/estado_cuenta_service.dart` (`generarPdfNotaPedido`): tabla con **7 columnas**, se agregó "Tipo de carne" separada de "Descripción". Anchos reajustados.
5. `lib/screens/bandeja_remitos_screen.dart`: la card de NDP muestra `Tipo · Descripción` (une los que no estén vacíos).
6. **Migración** `supabase_migration_ndp_tipo_carne.sql` (raíz del repo, **ya ejecutada en producción**): `ALTER TABLE nota_pedido_items ADD COLUMN tipo_carne TEXT DEFAULT ''` + backfill que mueve la `descripcion` de las NDPs v18.17 (cuando es uno de los 7 tipos del catálogo) a `tipo_carne`, dejando `descripcion` vacía. Las NDPs viejas de texto libre quedan intactas.
7. **Deploy**: commit directo a `master` + push; build con `flutter clean` + `build_web.sh` + `vercel --prod`.

### Cambios v18.18 (08/07/2026)
1. `lib/main.dart` (`_mostrarOpciones`, el `showModalBottomSheet` del FAB): agregado `isScrollControlled: true` y envuelto el contenido en `SingleChildScrollView`; el padding pasó de `EdgeInsets.all(20)` a `EdgeInsets.fromLTRB(20, 20, 20, 80)`. Motivo: en iPhone (Safari PWA), cuando el usuario es admin el menú tiene muchas opciones y la última ("Cerrar sesión") quedaba tapada por la barra de URL flotante del navegador. Ahora el sheet puede crecer/scrollear y el colchón inferior de 80px la mantiene visible.
2. **Deploy**: commit `f3adf86` directo a `master` + push; build con `flutter clean` + `build_web.sh` + `vercel --prod`. Alias `web-six-indol-svg13avcfl.vercel.app` apuntando al nuevo deploy.

### Cambios v18.17 (08/07/2026)
1. `lib/screens/remito_form_screen.dart`: catálogo de tipos de carne del dropdown ahora es `Novillo, Cerdo, Pierna mocha, Pierna pistola, Plancha de asado, Octavo, 1/4 delantero`. **OCR eliminado**: se quitaron los imports (`dart:convert`, `dart:typed_data`, `image_picker`, `supabase_flutter`, `ocr_service`), el estado OCR (`_leyendoOcr`, `_ocrError`, `_fotoBytes`, `_ocrCompletado`, `_ocrRebuildKey`), la zona de foto del `build` y los métodos `_buildFotoSection` / `_tomarFoto` / `_aplicarDatosOcr`. El form quedó solo carga manual (la auto-sugerencia por peso >60kg → Novillo sigue vigente al tipear kg).
2. `lib/services/ocr_service.dart`: **borrado**.
3. `pubspec.yaml`: se quitó `image_picker`. (Tras esto hay que correr `flutter clean` antes de `build_web.sh`, si no el `web_plugin_registrant.dart` cacheado sigue referenciando `image_picker_for_web` y el build falla.)
4. `lib/screens/nota_pedido_form_screen.dart`: la fila de NDP reemplaza el TextField "Descripción" por un **dropdown "Tipo de carne"** con la misma lista de 7 opciones (constante `_tiposCarne` en `_FilaCardState`). Se guarda en `fila.descripcion` (así fluye a bandeja y PDF sin más cambios). En edición, si la descripción vieja no está en la lista el dropdown arranca vacío. Se eliminó el `_descCtrl`.
5. `lib/services/database_service.dart` (`confirmarNotaPedido`): el `tipo_carne` del remito se toma de `item.descripcion.trim()` (tipo elegido en la NDP); si está vacío, fallback a la regla por peso (`promKg > 60 ? Novillo : Cerdo`).
6. `lib/providers/app_provider.dart` (`_normalizarTipo`): ahora **solo "cerdo" → Cerdo; todo el resto → Novillo** (antes devolvía el tipo tal cual para Pollo/otros). Afecta el agrupado del dashboard (kg/medias/venta por tipo).
7. `lib/screens/consultas_screen.dart`: en **Ganancias** (~línea 333) y **Comisiones** (~línea 2605) el check `== 'novillo'` pasó a `!contains('cerdo')`, para que los cortes nuevos sumen como Novillo y se valoricen con el costo/kg de Novillo.
8. `lib/models/models.dart` (`costoPorTipo`): ya trataba todo lo no-cerdo como Novillo (sin cambios, queda alineado).
9. **Deploy**: commiteado y pusheado a `master` (commits directos a master en esta sesión, sin PR); build con `flutter clean` + `build_web.sh` + `vercel --prod`. El alias `web-six-indol-svg13avcfl.vercel.app` apunta al nuevo deploy.

### Cambios v18.16 (02/07/2026)
1. `lib/services/ruta_cobranza_service.dart`:
   - `_parseCoords()` + nuevo `_parseDms()`: reconoce coordenadas en **formato DMS** (`24°59'04.1"S 65°22'17.8"W`, incluso url-encoded `%C2%B0`), además de los formatos previos.
   - `resolverLinks(urls)`: llama la Edge Function `resolver-maps` (POST en lote, header `apikey` + `Authorization: Bearer` con la **publishable key** — NO el JWT de sesión, que la función rechazaría). Devuelve por URL `(Coord? coord, String? direccion)`.
   - `construirParadas(clientes)`: resuelve coords localmente y, para los que no se pueden (links cortos), consulta la función en **una sola llamada de red**. Reemplaza el mapeo directo en `_armarRuta`.
   - `ParadaRuta`: nuevo campo `direccionResuelta` + getters `direccionMostrable`, `tienePunto`. `puntoUrl` prioriza coord → dirección libre → dirección resuelta.
2. `supabase_functions/resolver-maps/index.ts` (**nueva Edge Function**): runtime nuevo (`export default { fetch: withSupabase({ auth: ["publishable","secret"] }, …) }`). Sigue el redirect de `maps.app.goo.gl` del lado del servidor (User-Agent de browser, `redirect: manual` leyendo el header `location`), extrae `lat/lng` (`parseCoords`, incluye DMS) o, si es un "compartir lugar" sin coords, extrae la dirección de texto (`parseDireccion`, de `q=/query=/destination=/daddr=`). Deployada con "Verify JWT with legacy secret" ON (la publishable key la satisface). **Deploy: por dashboard** (Edge Functions → pegar el archivo). El CLI de esta máquina está logueado en OTRA cuenta de Supabase (ve `balance-system-don-chacho` etc., pero NO el proyecto vivo `svgvyukjqfjkxtypgobq` → 403).
3. `lib/screens/consultas_screen.dart` (`_DirectorioTab`): botón **editar ubicación** (`edit_location_alt_outlined`) por tarjeta → `_editarUbicacion()` abre un bottom sheet con Dirección + Link Maps y guarda con `AppProvider.editarCliente`. La hoja de ruta (`_mostrarSheetRuta`) usa `direccionMostrable`/`tienePunto`: número azul = coords, naranja = dirección resuelta, gris = sin punto.

### Cambios v18.15 (01/07/2026)
1. `lib/screens/consultas_screen.dart`: la ruta de cobranza pasa a una **tab propia "Ruta"** (Consultas ahora tiene 9 tabs, orden: …Directorio · **Ruta** · Comisiones…). Se removió el bloque `_buildRutaCobranza`/`_armarRuta`/`_mostrarSheetRuta` y el estado `_modoRuta`/`_generandoRuta` del `_DirectorioTab` (Directorio volvió a solo listado).
2. Nueva `_RutaTab` (`_RutaTabState`): filtros de **cliente** (TextField de búsqueda), **vendedor** (dropdown), **Con saldo pendiente** y **Solo vencidos** (FilterChips). `_candidatos(app)` aplica los filtros (saldo `getSaldoCliente > 0`, vencidos vía `clientesConSaldoVencido()`). Lista con `CheckboxListTile` para elegir clientes (subtítulo vendedor · "Debe $…"); los clientes **sin ubicación** aparecen deshabilitados con `location_off` + "Sin ubicación cargada". Botón "Todos/Ninguno". Contador "N de M seleccionados".
3. Botón **"Armar recorrido (N)"** (deshabilitado si no hay seleccionados): pide GPS (`RutaCobranzaService.ubicacionActual`), arma `ParadaRuta` por cliente elegido, ordena por cercanía y abre el bottom sheet con la lista numerada + "Abrir en Google Maps". Reutiliza `RutaCobranzaService` de v18.14 sin cambios.

### Cambios v18.14 (01/07/2026)
1. `lib/services/ruta_cobranza_service.dart` (nuevo): servicio de **ruta de cobranza**.
   - `ubicacionActual()`: pide el GPS del navegador vía `dart:html` (`window.navigator.geolocation.getCurrentPosition`, timeout 10s). Devuelve `Coord?` (null si se niega/no disponible).
   - `coordsDeCliente(Cliente)` / `_parseCoords()`: extrae lat,lng del `ubicacionUrl` (formatos `!3d..!4d..`, `@lat,lng`, `?q=/ll=/daddr=/destination=/center=`) o de `ubicacion` si es un par de coordenadas. Los links cortos `maps.app.goo.gl` NO traen coordenadas.
   - `ordenarPorCercania(paradas, origen)`: vecino más cercano desde el GPS (distancia equirectangular). Las paradas sin coords quedan al final. Sin origen, no reordena.
   - `construirUrl(paradas, origen)`: arma `https://www.google.com/maps/dir/?api=1&travelmode=driving` con `origin` = GPS, `waypoints` intermedios (pipe `|`) y `destination` = última parada. Cada punto es `lat,lng` si hay coords, si no la dirección de texto.
2. `lib/screens/consultas_screen.dart` (`_DirectorioTab`): tarjeta **"Ruta de cobranza"** arriba del listado. Combo box `_modoRuta` (`deben` = `getSaldoCliente > 0` / `vencidos` = `clientesConSaldoVencido()`), botón "Armar" (`_armarRuta`). Filtra por el vendedor activo del Directorio. Descarta deudores sin ubicación (avisa cuántos). `_mostrarSheetRuta`: bottom sheet con lista numerada (número azul si tiene coords, gris si no) + dirección + botón "Abrir en Google Maps". Avisos: sin GPS/sin coords → reordenar en Maps; más de 10 paradas → Maps puede truncar.
3. **Deploy**: `feat/ruta-cobranza` deployada a producción (no mergeada a master todavía; `master` quedó en v18.13). Documentar merge cuando se apruebe el PR.

### Cambios v18.13 (01/07/2026)
1. `consultas_screen.dart` (tab Reporte): tabla mejorada para legibilidad en celular — leyenda de colores (widget `_Leyenda`: remito suma / pago resta), signos `+`/`−` en la columna Monto, pill "Pago" verde en la columna Estado (antes los pagos dejaban un hueco vacío), header "Saldo" → "Saldo acum." para no confundir con el "Saldo pendiente" del pie. Anchos de columna ajustados (Fecha 78, ID 60).
2. `consultas_screen.dart` (tab Reporte) + `estado_cuenta_service.dart`: botón **"Exportar PDF"** arriba a la derecha (visible al seleccionar cliente). Nuevo método estático `generarReporteCliente(cliente, vendedor, remitos, pagos, saldoTotal)` que arma un PDF A4 multipágina replicando la tabla en pantalla: header con logo + cliente/vendedor, título "MOVIMIENTOS", leyenda, tabla Fecha/ID/Monto ±/Estado/Saldo acum. (remitos rojo, pagos verde, pills de estado) y recuadro "Saldo pendiente". Usa los mismos datos que la pantalla (remitos confirmados + pagos + `getSaldoCliente`), así el PDF coincide 1:1. Nombre de archivo `reporte_<cliente>_<fecha>.pdf`.
3. `web/index.html`: el splash agrega `pointer-events:none` al iniciar el fade-out (evita clicks fantasma sobre la capa que se está desvaneciendo).
4. Rama de trabajo: `fix-recibo-saldo-historial` (no mergeada a main).

### Cambios v18.12 (01/07/2026)
1. `recibo_service.dart` + `consultas_screen.dart` + `pago_form_screen.dart`: **recibo de pago rehecho**. El saldo del recibo es histórico (foto del momento del pago), leído de `saldo_anterior`/`saldo_nuevo` guardados (con fallback que reconstruye si están NULL). La tabla de deuda usa solo los pagos previos + el pago actual, de modo que restante, vencido y suma de la tabla concuerdan. Bloque de saldos: Saldo anterior − Pago realizado → SALDO RESTANTE TOTAL + Saldo vencido (siempre). Encabezado con **hora HH:MM** (`_formatHora` sobre `creado_en`). Eliminada la sección "Pagos aplicados".
2. SQL `supabase_backfill_saldos_pagos.sql` (raíz del repo): UPDATE con window function que rellena `saldo_anterior`/`saldo_nuevo` de todos los pagos en orden cronológico (fecha, numero). Correr una vez. **Ya ejecutado en producción.**
3. Rama de trabajo: `fix-recibo-saldo-historial` (no mergeada a main).

### Cambios v18.11 (08/06/2026 al 29/06/2026)
1. `main.dart`: el menú del FAB para admin ahora ofrece **"Nueva nota de pedido"** además de "Nuevo remito" (abre `NotaPedidoFormScreen`, queda pendiente). (29/06)
2. `recibo_service.dart` + `pago_form_screen.dart` + `models.dart`: **saldo vencido** en el formulario de pago y en el recibo PDF. Pago guarda `saldo_anterior`/`saldo_nuevo` para recibos reimpresos correctos. Fixes en el detalle de deuda FIFO del recibo: muestra estado previo al pago, descuenta el pago actual, y el saldo vencido no desaparece al pagar el monto exacto.
3. `consultas_screen.dart`: nuevos tabs **Reporte** (estado de cuenta por cliente con columna Saldo acumulado) y **Eliminados** (2 sub-tabs Pagos/Remitos). Total 8 tabs. Filtro de vendedor en Vencidos y Directorio. Link Maps en tarjetas de Vencidos. Ganancias descuenta comisión de transferencias.
4. `models.dart` + `database_service.dart` + `app_provider.dart`: modelos `RemitoEliminado` y `PagoEliminado` + métodos de auditoría. Al eliminar remito/pago se inserta primero en la tabla de auditoría. Nuevo método `saldoVencidoCliente(clienteId)`.
5. `home_screen.dart`: botón ojo para **ofuscar KPIs** (`••••`); cards de kg muestran cantidad de medias; vendedores ordenados A→Z en filtros.
6. `bandeja_remitos_screen.dart` + PDF NDP: muestran el vendedor del cliente. Ficha de cliente sin totales.
7. SQL: tablas `remitos_eliminados` (`supabase_migration_remitos_eliminados.sql`) y `pagos_eliminados`; columnas `saldo_anterior`/`saldo_nuevo` en `pagos`.

### Cambios v18.10 (12/05/2026)
1. `web/index.html`: splash screen inline — logo 120×120px con bordes redondeados, texto "Granja Don Chacho", spinner CSS rojo (#C62828), "Cargando...". Se oculta con fade-out 300ms al evento `flutter-first-frame`, fallback 8 segundos.
2. `web/_headers`: archivo de cache headers para Cloudflare Pages. `no-cache` en `index.html`, `manifest.json` y `flutter_service_worker.js`; `immutable` 1 año en JS y assets; 30 días en íconos.
3. `build_web.bat` / `build_web.sh`: scripts de build en raíz del proyecto. Comando: `flutter build web --release --tree-shake-icons --pwa-strategy=none`. Reemplaza a `flutter build web --release` plano.
4. `lib/providers/app_provider.dart` (`cargarDatos`): las 8 queries iniciales ahora corren en paralelo con `Future.wait`. El loop N+1 de items de remito reemplazado por `getAllRemitoItems()` + agrupación en memoria.
5. `lib/services/database_service.dart`: nuevo método `getAllRemitoItems()` — trae todos los items en 1 query. `getNotasPedido()` reescrito: 2 queries totales (cabeceras + todos los items) en vez de N+1.
6. `supabase_migration_indices.sql`: 6 índices para acelerar queries. **Pendiente ejecutar en Supabase Dashboard → SQL Editor.**

### Cambios v18.9 (09/05/2026)
1. `pago_form_screen.dart`: **pagos ahora son solo-lectura en modo edición**. Título cambia a "Ver pago". Se ocultan: buscador de cliente, date picker interactivo, dropdowns y TextFields de medios, botón "Agregar otro medio", "Saldo restante" y botones "Guardar pago"/"Guardar + Recibo". Solo queda visible el botón Eliminar en AppBar (requiere `editar_pago`). Razón: editar pagos generaba errores en los saldos de clientes.

### Cambios v18.8 (06/05/2026)
1. `consultas_screen.dart`: nuevo tab "Comisiones" (tab 6). Selección de vendedor + rango de fechas con atajos (esta semana / semana anterior / mes actual). Muestra N remitos, Kg Novillo, Kg Cerdo, total $ ventas. Campo de % comisión con cálculo automático del monto a pagar. Botón PDF que emite liquidación detallada.
2. `estado_cuenta_service.dart`: nuevo método estático `generarPdfComision` — PDF con encabezado, tabla de remitos del vendedor y bloque de liquidación en rojo con el monto final.
3. `cliente_detalle_screen.dart`: botón de ícono en AppBar (solo con permiso `gestionar_clientes`) para cambiar el vendedor del cliente desde un dialog con dropdown.

### Cambios v18.6 (29/04/2026)
1. `bandeja_remitos_screen.dart`: tab "Notas de Pedido" pasa a ser el primero, antes que "Remitos".

### Cambios v18.5 (29/04/2026)
1. `app_provider.dart`: nuevo método `remitosVencidosCliente(clienteId)` — cuenta remitos con deuda vencida por cliente (FIFO). Nuevo método `todosRemitosVencidos()` — lista todos los remitos vencidos de todos los clientes con contexto.
2. `cliente_detalle_screen.dart`: muestra todos los remitos (sin límite de 6). Stat "Vencidos" agregado en tarjeta de resumen (rojo si >0, verde si 0).
3. `vendedor_detalle_screen.dart`: reemplazado "Plazo: X días • teléfono" por "N remitos vencidos" en cada card de cliente (rojo si >0, gris si 0).
4. `clientes_screen.dart`: mismo cambio — "Plazo: X días" reemplazado por "N remitos vencidos" con color semafórico.
5. `consultas_screen.dart`: nuevo tab "Vencidos" como primer tab (total 5 tabs). Muestra todos los remitos vencidos con tarjeta resumen (count + deuda total vencida), ordenados por días vencido desc.
6. `estado_cuenta_service.dart` (Reporte del vendedor): celdas "Estado" y "Deuda" se pintan amarillo con texto rojo en negrita cuando el remito está vencido. Clientes con saldo ≤ $0 ya no se incluyen en el reporte.

### Cambios v18.4 (27/04/2026)
1. `consultas_screen.dart`: guards de permiso en Historial — remito requiere `editar_remito`, pago requiere `editar_pago`, NDP pendiente requiere `editar_remito` (antes usaba `crear_remito`, lo que permitía a la secretaria navegar al formulario de edición). Tap en Saldos para registrar pago requiere `crear_pago`.
2. `remito_form_screen.dart`: botón "Guardar remito" y botón eliminar se ocultan en modo edición si no tiene `editar_remito`/`eliminar_remito`.
3. `pago_form_screen.dart`: botones "Guardar pago"/"Guardar + Recibo" y botón eliminar se ocultan en modo edición si no tiene `editar_pago`.
4. `nota_pedido_form_screen.dart`: botón "Guardar cambios" y botón eliminar se ocultan en modo edición si no tiene `editar_remito`.
5. `vendedor_detalle_screen.dart`: corregido TODO — tap en cliente ahora navega a `ClienteDetalleScreen`.

URL: `https://web-six-indol-svg13avcfl.vercel.app`

### Cambios v18.1 (22/04/2026)
1. `nota_pedido_form_screen.dart`: "Total kg fila" más grande (18px bold), label renombrado a "Precio por Kg (\$)", fórmula subtotal = totalKg × precioPorKg
2. `bandeja_remitos_screen.dart`: NDPs del día muestran todos los estados (Pendiente/Aprobado/Rechazado con colores correctos), botón PDF en cada card, acciones solo visibles para pendientes
3. `home_screen.dart`: secretaria solo ve "Saldo total a cobrar" + "Vendedores - saldos pendientes"; las secciones de Kg, Costo y Ganancia solo las ve el admin

### Cambios v18.2 (23/04/2026)
1. `home_screen.dart`: convertido a `StatefulWidget` con `_semanaRef`. Botones `<` / `>` para navegar semanas. `>` deshabilitado en semana actual. Badge "Cargar" solo aparece en semana actual.
2. `app_provider.dart`: métodos `kgVendidosSemana`, `kgVendidosSemanasPorTipo`, `ventaSemanasPorTipo`, `gananciaSemanalPorTipo` aceptan `DateTime? semana` opcional. Todos filtran por `esConfirmado`. `gananciaSemanalPorTipo` usa `costoParaFecha(s)` en vez de `_costoSemanaActual` para soportar semanas históricas.

### Cambios v18.3 (25/04/2026 al 27/04/2026)
1. `estado_cuenta_service.dart`: PDF NDP columna "Precio/media" → "Precio por kg.". Total nota usa `sum(item.totalKg × item.precioPorMedia)` explícitamente.
2. `clientes_screen.dart`: agregado Dropdown "Cliente" (con opción "Todos") debajo del TextField. Añadido `_filtroClienteId`. Cambiar chip de vendedor limpia la selección de cliente.
3. `pago_form_screen.dart`: reemplazado `Autocomplete<Cliente>` por TextField + Dropdown A→Z (patrón estándar). Añadido `_busquedaCliente`.
4. `bandeja_remitos_screen.dart`: NDPs pendientes siempre visibles (sin filtro de fecha). NDPs confirmadas visibles hasta 1 día después de `confirmadoEn`. Card NDP muestra una línea por ítem con descripción, total kg y precio/kg.

## NOTAS TÉCNICAS IMPORTANTES

### Modelos NDP (v18)
- `NotaPedidoItem`: `kgsPorMedia` es `List<double>`, getter `totalKg` suma la lista, `totalPesos = totalKg * precioPorMedia` (**precio es por kg**, el campo se llama `precioPorMedia` en DB por legado pero almacena precio/kg desde v18.1)
- `NotaPedido`: `clienteId` nullable (si es texto libre), `clienteNombreLibre` nullable, `remitoId` se llena al confirmar, getter `numeroFormateado` → "NP-0001"
- En JSONB de Supabase, `kgs_por_media` se guarda como array JSON y se deserializa con cast `(e as num).toDouble()`

### AppProvider — métodos clave (v18 agregados)
- `notasPedido`: getter lista completa
- `notasPedidoPendientes`: getter filtrado
- `agregarNotaPedido(ndp, items)`: autonumera NP y guarda
- `actualizarNotaPedido(ndp, items)`: reemplaza items (delete + insert)
- `confirmarNotaPedido(ndp, clienteId, confirmadoPorId)`: crea remito, actualiza NDP, recalcula saldos, devuelve Remito
- `rechazarNotaPedido(ndpId, confirmadoPorId, motivo)`: marca rechazada
- `eliminarNotaPedido(ndpId)`: elimina NDP y sus items

### AppProvider — métodos clave (v18.5 agregados)
- `remitosVencidosCliente(String clienteId)`: cuenta remitos con deuda vencida para un cliente (FIFO)
- `todosRemitosVencidos()`: lista todos los remitos vencidos de todos los clientes con contexto (remito, cliente, vendedor, diasVencido, deuda), ordenados por días vencido desc

### AppProvider — métodos clave (v18.11 agregados)
- `saldoVencidoCliente(String clienteId)`: monto total vencido del cliente vía FIFO (suma deuda de remitos cuyo vencimiento ya pasó)
- `remitosEliminados` / `pagosEliminados`: getters de las listas de auditoría (cargadas en `cargarDatos`)
- `eliminarRemito(remitoId, {eliminadoPor})` / `eliminarPago(...)`: antes de borrar insertan una fila en la tabla de auditoría correspondiente, luego recalculan saldos

### AppProvider — métodos clave (v17)
- `tienePermiso(String)`: verifica si el usuario actual tiene un permiso
- `esAdmin`: getter shortcut
- `remitosConfirmados`: getter que filtra solo confirmados
- `confirmarRemito(id, confirmadoPorId)`: cambia estado + recalcula saldos
- `rechazarRemito(id, confirmadoPorId, motivo)`: marca rechazado
- `costoParaFecha(DateTime)`: busca el costo de la semana correspondiente

### AuthService — métodos clave
- `login(usuario, password)`: `signInWithPassword` con el mail sintético y, si anduvo, busca el perfil por `auth_id`. Si hay identidad pero no perfil activo, **cierra la sesión** y devuelve null. Si Auth falla, cae en `_loginLegacy` mientras `permitirLoginLegacy` sea `true`
- `mailDe(usuario)`: `<usuario>@donchacho.local`, normalizado igual que el login (`trim().toLowerCase()`)
- `cambiosDeSesion`: el `onAuthStateChange` de Supabase. `main.dart` lo escucha para sacar al usuario cuando llega `signedOut`
- `restaurarSesion()`: `auth.currentSession` → perfil por `auth_id`. Sin sesión de Supabase cae en la clave vieja de SharedPreferences (solo con el legacy prendido)
- `cerrarSesion()`: `auth.signOut()` + limpia SharedPreferences
- `hashPassword(String)`: SHA-256. **Solo para el login legacy** — se va con la Fase 3
- CRUD: `getUsuarios`, `crearUsuario` (**solo el perfil, no la cuenta de acceso**), `actualizarUsuario`, `eliminarUsuario`
- CRUD: `getRoles`, `crearRol`, `actualizarRol`, `eliminarRol`
- `getPermisos()`: catálogo completo
- `cambiarPassword(perfil, actual, nueva)`: verifica la actual con un `signInWithPassword` (`updateUser` no la pide), cambia la de Auth y **borra el `password_hash` viejo**. Devuelve `ResultadoCambioPassword` y no un bool: "la actual está mal" y "tu cuenta todavía no existe" se arreglan distinto
- `Usuario.authId` es de **lectura**: lo escribe el SQL del vínculo, no la app, y **no está en `toMap()`** a propósito — Gestión de Usuarios arma un `Usuario` nuevo con los campos del formulario, así que si estuviera, guardar a alguien para cambiarle el rol le borraría el vínculo en silencio. Cubierto por `test/auth_identidad_test.dart`

## CAMBIOS PENDIENTES

- **Auth — Fase 1: correr la migración y migrar las 6 cuentas.** `supabase_migration_auth_identidad.sql` está escrita y sin correr. El paso a paso (y el rollback de cada paso) está en `auth_fase1_runbook.md`. Hacerlo **lunes, martes o miércoles**: el deploy cambia el login de todos y jueves/viernes/sábado son reparto.
- **Auth — Fase 2: las políticas de RLS. EN CURSO**, ya en `master` (PR #21, mergeada el 29/10/2026). Están escritas y **sin correr**: `supabase_migration_rls_politicas.sql` (las 29 tablas, con los `ENABLE` comentados) y `supabase_migration_soporte_reportado_por_id.sql`. Y en la app, `utils/lectura_permitida.dart` + el recorte de `cargarDatos()`. Nada de esto cambia el comportamiento todavía: `AppProvider.rlsEncendido` está en `false` y ninguna tabla tiene RLS. **Lo que queda de la fase**:
  1. **Wirear las pantallas a `AppProvider.saldosConfiables`**: son las 8 que muestran un saldo. Hoy, si esa bandera es false, los saldos quedan en 0 (subestima, que es el lado seguro) pero la pantalla no dice "no disponible".
  2. **Un trigger en `usuarios`** que impida cambiarse el propio `rol_id`, `activo` o `auth_id`. La política de UPDATE de la fila propia es necesaria (`cambiarPassword` borra su hash viejo) pero no puede comparar contra el valor anterior de otra columna, así que hoy deja una escalada de privilegios por la API REST. Está anotado al pie de la sección 6 de la migración.
  3. **Encender RLS tabla por tabla**, en los cuatro grupos de la sección 7, con el ensayo en transacción primero y **nunca** un día de reparto.
  **Lo que esta rama ya resolvió** de los prerequisitos del punto 6 del diseño:
  - **`cargarDatos()` distingue "sin permiso" de "sin datos"** (`utils/lectura_permitida.dart`): lo que el rol no puede leer **no se pide**, y si falta una de las tres tablas del saldo `_recalcularSaldos` no calcula nada. Bajo RLS una tabla denegada vuelve **vacía, no con error**, y con `pagos` vacío `saldo = remitos − pagos` se convierte en "saldo = todo lo remitido": saldos inflados con cara de dato correcto (ya pasó parecido en v18.22 con el límite de 1000 filas de PostgREST). Los saldos quedan en 0, que **subestima en vez de inflar** — el lado seguro — y `saldosConfiables` es lo que la pantalla tiene que mirar.
  - **El interruptor es `AppProvider.rlsEncendido`**, hoy en `false`: mientras ninguna tabla tenga RLS, la app sigue trayendo todo como siempre. Se pone en `true` al encender la primera tabla; es un cambio de una línea a propósito.
  - **La regla del saldo** quedó en los dos lados: `puede_ver_saldo()` en SQL y `LecturaPermitida.puedeVerSaldo` en Dart. **Son dos fuentes de verdad**, y `test/lectura_permitida_test.dart` es lo que hace que se note cuando una se mueve sin la otra.
  - **`soportes.reportado_por_id`**: la migración está escrita. Falta que la app la escriba al crear el ticket y filtre por ella (hoy filtra por `nombreCompleto`).

  **El único prerequisito de la Fase 1 que sigue abierto**: apagar `permitirLoginLegacy` y deployar. Un login legacy no abre sesión de Supabase, así que `auth.uid()` queda NULL y bajo RLS ese usuario vería todas las tablas vacías.
- **Auth — Fase 3**: borrar `usuarios.password_hash` y `hashPassword`; alta de usuarios en un paso con una Edge Function que tenga la service key; pasar `resolver-maps` y `parse-reparto` al JWT de sesión (hoy van con la publishable key hardcodeada, así que cualquiera con la key las puede llamar y `parse-reparto` consume la ANTHROPIC_API_KEY); decidir si la cuenta de prueba `mili` se da de baja.
- **Staging**: hoy no hay y la app local pega contra producción. La recomendación concreta (segundo proyecto de Supabase con datos inventados + ensayo en transacción contra producción, con costos) está en `auth_fase1_staging.md`. **Es condición de entrada de la Fase 2.** Prerequisito práctico: pasar la URL y la key de Supabase de `main.dart` a `AppConfig` con `--dart-define`, porque hoy están hardcodeadas y no hay forma de apuntar la app a otra base sin editar código.
- **Soporte — mejoras no implementadas**: badge con la cantidad de tickets abiertos en el item del FAB (requiere sumar la query a `AppProvider.cargarDatos`); aviso push/mail en vez del WhatsApp manual.
- **Lista de reparto — Fase 2 (audio)**: cargar la lista por audio de WhatsApp (audio → transcripción Whisper/Gemini → parseo estructurado con Claude). Diferido explícitamente por el usuario.
- **Ejecutar `supabase_migration_indices.sql`** en Supabase Dashboard → SQL Editor (una sola vez). Agrega 6 índices para acelerar la carga inicial.
- **Borrar los 3 pagos de prueba de Perico + el cliente duplicado "A" vacío** (ver v18.22, punto 3). Se hace desde la app; verificar saldo $4.906.800 después.
- **Prevenir clientes duplicados por teléfono** (mejora ofrecida, no implementada): avisar/impedir crear un cliente con un teléfono que ya existe. Motivó el bug del Perico duplicado.

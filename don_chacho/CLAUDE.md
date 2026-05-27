# GRANJA DON CHACHO — Módulo Matarife / Venta de Medias Reses a Terceros

## CONTEXTO

App Flutter Web para gestionar la venta de medias reses a carnicerías terceras. Joaco es el dueño, está en Buenos Aires, Argentina. No es desarrollador — necesita instrucciones paso a paso. Comunicación en español argentino informal (vos/tenés). Sin emoticones. Respuestas concisas.

## STACK TÉCNICO

- **Flutter web** (Dart) — NO Android/iOS nativo (Flutter 3.41.8)
- **Supabase** (PostgreSQL + Storage + Edge Functions)
- **Claude API** (claude-sonnet-4-20250514) vía Supabase Edge Function `ocr-remito` (proxy CORS, deployada con `--no-verify-jwt`)
- **Vercel** para deploy (PWA instalable en iPhone)
- **Paquetes**: supabase_flutter, provider, intl ^0.20.2, uuid, pdf, printing, url_launcher, http, image_picker, crypto, shared_preferences

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
- **Tipo carne automático**: media >60kg = Novillo, ≤60kg = Cerdo
- **Formato pesos**: $100.000 sin decimales, sin abreviar (no "K"/"M")
- **FIFO**: pagos se aplican a remitos del más viejo al más nuevo
- **Solo remitos con estado 'confirmado' cuentan para saldos** (los pendientes/rechazados no afectan)
- **Costo por kg**: carga manual semanal, separado Novillo vs Cerdo. Se usa para calcular ganancia.

## SISTEMA DE USUARIOS Y PERMISOS

### Login
- Usuario + contraseña (SHA-256 hash)
- Sesión persistente con SharedPreferences (cierre manual)
- Usuario inicial: `admin` / `admin123`
- **IMPORTANTE**: Las tablas `usuarios`, `roles`, `rol_permisos`, `permisos` tienen RLS deshabilitado. Se corrió en Supabase:
```sql
ALTER TABLE usuarios DISABLE ROW LEVEL SECURITY;
ALTER TABLE roles DISABLE ROW LEVEL SECURITY;
ALTER TABLE rol_permisos DISABLE ROW LEVEL SECURITY;
ALTER TABLE permisos DISABLE ROW LEVEL SECURITY;
```

### 12 Permisos (catálogo fijo en tabla `permisos`)
`crear_remito`, `usar_ocr`, `confirmar_remito`, `editar_remito`, `eliminar_remito`, `crear_pago`, `editar_pago`, `gestionar_clientes`, `gestionar_vendedores`, `gestionar_costos`, `ver_consultas`, `gestionar_usuarios`

### Roles
- Flexibles: el admin puede crear roles personalizados con permisos a la carta
- Default: **Administrador** (es_admin=true, todos los permisos) y **Secretaria** (crear_remito + ver_consultas — ver_consultas se asigna manualmente desde Gestión de Usuarios)
- No se puede borrar/desactivar el propio usuario admin (protección contra auto-lockout)

### Flujo de confirmación de remitos
1. Admin crea remito → queda directamente `confirmado` → afecta saldos
2. Secretaria carga Nota de Pedido (NDP) → queda `pendiente` → NO afecta saldos
3. Admin ve bandeja → puede **confirmar** (convierte NDP en Remito R-XXXX), **editar** o **rechazar** (con motivo)
4. Solo remitos `confirmado` cuentan para saldos y ganancias

## ESTRUCTURA DEL PROYECTO (~11.500 líneas, 23 archivos .dart)

```
don_chacho/lib/
├── main.dart                          # Login + sesión + tabs dinámicas por permisos + FAB dinámico (admin→remito, secretaria→NDP)
├── models/models.dart                 # Vendedor, Cliente, Remito, RemitoItem, Pago, PagoMedio, CostoSemanal, NotaPedido, NotaPedidoItem, Permiso, Rol, Usuario
├── providers/app_provider.dart        # Estado global, FIFO, saldos, permisos, usuarioActual, NDPs
├── services/
│   ├── auth_service.dart              # Login SHA-256, sesión persistente SharedPreferences, CRUD usuarios/roles
│   ├── database_service.dart          # CRUD Supabase para todo + confirmarNotaPedido (convierte a remito)
│   ├── estado_cuenta_service.dart     # PDF estado de cuenta + reporte vendedor + PDF nota de pedido
│   ├── ocr_service.dart               # OCR con Claude API via Edge Function
│   └── recibo_service.dart            # PDF recibo de pago con detalle deuda FIFO
├── screens/
│   ├── login_screen.dart              # Usuario + contraseña
│   ├── home_screen.dart               # Dashboard KPIs por tipo carne, navegación semanal < >, botón costos (con permiso)
│   ├── vendedores_screen.dart         # Lista vendedores
│   ├── vendedor_detalle_screen.dart   # Detalle + reporte PDF vendedor; tap en cliente abre ClienteDetalleScreen; muestra "N remitos vencidos" por cliente
│   ├── clientes_screen.dart           # Lista clientes; muestra "N remitos vencidos" por cliente (rojo si >0)
│   ├── cliente_detalle_screen.dart    # Todos los remitos (sin límite), stat "Vencidos" en resumen, estado de cuenta, clickeable para editar
│   ├── remito_form_screen.dart        # Carga manual + OCR, solo para admin
│   ├── nota_pedido_form_screen.dart   # Carga NDP para secretaria: filas dinámicas con kg/media, cliente de lista o texto libre
│   ├── pago_form_screen.dart          # Múltiples medios, búsqueda cliente A→Z, ver/eliminar (NO editar — genera errores de saldo)
│   ├── consultas_screen.dart          # 5 tabs: Vencidos (1°), Ganancias, Saldos, Historial (remitos+pagos+NDPs), Directorio. Vencidos: lista todos los remitos vencidos con FIFO, resumen count+deuda total. Historial: onTap guarda por permiso (editar_remito/editar_pago); Saldos: tap a pago requiere crear_pago
│   ├── costos_semana_screen.dart      # Historial costos, editar con alerta semana vieja
│   ├── gestion_usuarios_screen.dart   # CRUD usuarios + roles con permisos checkboxes
│   └── bandeja_remitos_screen.dart    # 3 tabs: Notas de Pedido (1°) / Remitos pendientes / Rechazados
└── utils/
    ├── formatters.dart                # formatPesos, formatKg, formatFecha, formatRangoSemana
    └── theme.dart                     # AppTheme + StatusPill widget + StatusType enum
```

## BASE DE DATOS (Supabase PostgreSQL)

### Tablas principales
- `vendedores` (id, nombre, apellido, telefono, creado_en)
- `clientes` (id, vendedor_id, nombre_razon_social, telefono, plazo_pago_dias, ubicacion, ubicacion_url, creado_en)
- `remitos` (id, cliente_id, fecha, numero, foto_url, total_kg, total_pesos, estado, creado_por, confirmado_por, confirmado_en, motivo_rechazo, creado_en)
- `remito_items` (id, remito_id, tipo_carne, cantidad_medias, kg_total, precio_por_kg)
- `pagos` (id, cliente_id, fecha, numero, monto_total, neto_recibido, creado_en)
- `pago_medios` (id, pago_id, medio, monto, neto_recibido)
- `costos_semana` (id, semana_inicio, costo_por_kg [nullable legacy], costo_por_kg_novillo, costo_por_kg_cerdo, creado_en)

### Tablas de permisos (v17)
- `permisos` (id TEXT PK, nombre, descripcion) — 12 permisos predefinidos
- `roles` (id UUID, nombre UNIQUE, es_admin BOOLEAN, creado_en)
- `rol_permisos` (rol_id, permiso_id) — relación N:N con CASCADE
- `usuarios` (id UUID, usuario UNIQUE, password_hash, rol_id FK, nombre_completo, activo, creado_en)

### Tablas Notas de Pedido (v18)
- `notas_pedido` (id UUID PK, numero INT, fecha DATE, cliente_id UUID nullable FK, cliente_nombre_libre TEXT nullable, estado TEXT pendiente/confirmado/rechazado, motivo_rechazo, creado_por, confirmado_por, confirmado_en, remito_id UUID nullable FK, total_kg, total_pesos, creado_en)
- `nota_pedido_items` (id UUID PK, nota_pedido_id FK CASCADE, descripcion TEXT, cantidad_medias INT, kgs_por_media JSONB array, precio_por_media NUMERIC, total_kg, total_pesos)
- Ambas tablas con RLS deshabilitado

### Migraciones SQL (ya corridas en Supabase, en orden)
1. `supabase_schema.sql` — esquema inicial
2. `supabase_migration_fase2.sql` — pagos + medios
3. `supabase_migration_numeracion.sql` — campo numero en remitos y pagos
4. `supabase_fix_costo_nullable.sql` — columna costo_por_kg nullable + default 0
5. `supabase_migration_v17_usuarios.sql` — usuarios, roles, permisos, estado remitos, RLS disabled
6. `supabase_migration_v18_notas_pedido.sql` — tablas notas_pedido + nota_pedido_items

### MedioPago enum en Dart
`efectivo`, `transferencia`, `cheque`

## FUNCIONALIDADES IMPLEMENTADAS

### Login y Permisos (v17)
- Pantalla de login con usuario + contraseña
- Sesión persistente (SharedPreferences en web = localStorage)
- UI dinámica: tabs del menú inferior se ocultan según permisos
- FAB (+): admin ve "Nuevo remito", secretaria ve "Nueva nota de pedido"
- Badge del FAB incluye remitos pendientes + NDPs pendientes

### Dashboard (home_screen)
- KPIs de la semana: kg vendidos (novillo/cerdo), venta bruta, ganancia neta
- Navegación `<` / `>` para ver KPIs de semanas anteriores (solo admin). `>` deshabilitado en semana actual.
- Saldo total a cobrar + contador de vencidos
- Costo/kg novillo y cerdo con botón "Cargar"
- Botón costos semanales en AppBar (solo con permiso gestionar_costos)

### OCR de remitos (Fase 3)
- Foto → base64 → Supabase Edge Function `ocr-remito` → Claude API extrae filas
- Solo visible con permiso `usar_ocr`
- Edge Function: `supabase_functions/ocr-remito/index.ts`

### Notas de Pedido (v18)
- **Formulario secretaria** (`nota_pedido_form_screen.dart`): cliente de lista existente O texto libre, fecha, filas dinámicas
- Cada fila: descripción libre, cantidad medias, N campos de kg (uno por media, generados automáticamente según cantidad), precio por media, subtotal calculado
- Guarda como `pendiente` → no afecta saldos
- Soporta modo edición vía `ndpInicial`
- **Bandeja admin** (`bandeja_remitos_screen.dart`, 3 tabs):
  - Tab "Remitos": remitos pendientes de roles no-admin
  - Tab "Notas de Pedido": NDPs pendientes siempre (sin filtro de fecha) + confirmadas hasta 1 día después de `confirmadoEn`. Card muestra por ítem: descripción, total kg y precio/kg. Si el cliente era texto libre, al confirmar se muestra diálogo para asignar cliente de lista (obligatorio)
  - Tab "Rechazados": remitos + NDPs rechazados mezclados
- **Conversión NDP → Remito**: al confirmar se crean remito + remito_items. tipo_carne auto (promedio kg/media >60 → Novillo, else Cerdo). precio_por_kg = (precio_media × cant_medias) / total_kg
- **PDF NDP** (`estado_cuenta_service.generarPdfNotaPedido`): tabla con columnas Descripción/Medias/Kg por media/Total kg/**Precio por kg.**/Subtotal. Total nota = sum(item.totalKg × item.precioPorMedia). Muestra estado y número de remito generado si confirmada

### PDFs generados (4 tipos)
1. **Recibo de pago** (recibo_service.dart): medios + saldo anterior/nuevo + detalle deuda FIFO
2. **Estado de cuenta cliente** (estado_cuenta_service.dart): remitos pendientes + pagos aplicados FIFO
3. **Reporte vendedor** (estado_cuenta_service.dart): consolidado multi-página por cliente
4. **Nota de pedido** (estado_cuenta_service.dart): detalle kg individuales por media

### Consultas (5 tabs en consultas_screen.dart)
- **Vencidos** (1° tab): lista todos los remitos vencidos de todos los clientes (FIFO real). Tarjeta resumen con count + deuda total. Ordenados por días vencido desc. Tap abre remito si tiene `editar_remito`.
- **Ganancias**: rango fechas + atajos, ganancia por tipo carne con costos históricos, ranking vendedor/cliente
- **Saldos**: por vendedor expandible, FilterChip "Solo vencidos" con FIFO real
- **Historial**: remitos + pagos + NDPs unificados. Chips: Todos / Remitos / Pagos / Notas de Pedido. NDPs muestran badge "NP" y estado. PDF descargable en pagos y NDPs. Tap en pago abre vista solo-lectura (con botón eliminar). NDPs pendientes son clickeables → abre formulario de edición
- **Directorio**: clientes con ubicación y link Google Maps

### Búsqueda de cliente — patrón estándar
Todas las pantallas con selector/filtro de cliente usan el mismo patrón de dos pasos:
1. **TextField "Buscar cliente"**: filtra el dropdown por `contains()` en tiempo real
2. **Dropdown "Cliente"**: lista A→Z filtrada, selección exacta

Pantallas que lo implementan: `remito_form_screen.dart`, `pago_form_screen.dart`, `nota_pedido_form_screen.dart` (modo lista), `clientes_screen.dart` (con opción "Todos"), `consultas_screen.dart` Historial.

### Registrar Pago (pago_form_screen.dart)
- TextField + Dropdown A→Z (patrón estándar, reemplazó al Autocomplete)
- Cuando viene con `clienteInicial` (desde ficha de cliente), muestra cliente fijo

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

## PROCEDIMIENTO DE ACTUALIZACIÓN / DEPLOY

```bash
# En C:\App Joaco\don_chacho_v17\don_chacho

# 1. Setup inicial (solo la primera vez en carpeta nueva)
flutter create . --platforms=web
# Copiar index.html y manifest.json PWA a web/
flutter pub add intl:^0.20.2
flutter pub get

# 2. Probar local (modo desarrollo, sin compilar)
flutter run -d chrome

# 3. Compilar para producción (usar el script, NO flutter build web plano)
build_web.bat          # Windows
# ./build_web.sh       # Linux/Mac

# 4. Probar build local antes de subir
cd build\web
npx serve .            # abre en http://localhost:3000
# (python no está instalado en esta máquina)

# 5. Deployar a Vercel
cd build\web
vercel --prod
```

### Archivos PWA (web/index.html y web/manifest.json)
- `index.html` tiene splash screen inline (logo + spinner CSS rojo #C62828 + fade-out 300ms). Se oculta con evento `flutter-first-frame`, fallback 8s.
- `index.html` tiene meta tags iOS PWA: `apple-mobile-web-app-capable`, `apple-mobile-web-app-status-bar-style`, `apple-mobile-web-app-title`, viewport con `viewport-fit=cover`
- `manifest.json`: display standalone, theme_color #C62828, orientation portrait-primary
- `web/_headers`: cache headers para Cloudflare Pages (no-cache en index.html/service worker, immutable en assets)
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

## ESTADO ACTUAL (v18.10) — EN PRODUCCIÓN

Deployada el 12/05/2026. Login funciona con admin/admin123. Flutter 3.41.8.

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

### AppProvider — métodos clave (v17)
- `tienePermiso(String)`: verifica si el usuario actual tiene un permiso
- `esAdmin`: getter shortcut
- `remitosConfirmados`: getter que filtra solo confirmados
- `confirmarRemito(id, confirmadoPorId)`: cambia estado + recalcula saldos
- `rechazarRemito(id, confirmadoPorId, motivo)`: marca rechazado
- `costoParaFecha(DateTime)`: busca el costo de la semana correspondiente

### AuthService — métodos clave
- `login(usuario, password)`: retorna Usuario con Rol y permisos, o null
- `restaurarSesion()`: lee userId de SharedPreferences, recarga desde DB
- `cerrarSesion()`: limpia SharedPreferences
- `hashPassword(String)`: SHA-256
- CRUD: `getUsuarios`, `crearUsuario`, `actualizarUsuario`, `eliminarUsuario`
- CRUD: `getRoles`, `crearRol`, `actualizarRol`, `eliminarRol`
- `getPermisos()`: catálogo completo
- `cambiarPassword(userId, actual, nueva)`: verifica actual antes de cambiar

## CAMBIOS PENDIENTES

- **Ejecutar `supabase_migration_indices.sql`** en Supabase Dashboard → SQL Editor (una sola vez). Agrega 6 índices para acelerar la carga inicial.

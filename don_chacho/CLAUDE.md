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
- **`usar_ocr` quedó obsoleto en v18.17** (el OCR fue eliminado). Sigue en el catálogo pero ya no controla ninguna UI. Se puede borrar del catálogo cuando se quiera.

### Roles
- Flexibles: el admin puede crear roles personalizados con permisos a la carta
- Default: **Administrador** (es_admin=true, todos los permisos) y **Secretaria** (crear_remito + ver_consultas — ver_consultas se asigna manualmente desde Gestión de Usuarios)
- No se puede borrar/desactivar el propio usuario admin (protección contra auto-lockout)

### Flujo de confirmación de remitos
1. Admin crea remito → queda directamente `confirmado` → afecta saldos
2. Secretaria carga Nota de Pedido (NDP) → queda `pendiente` → NO afecta saldos
3. Admin ve bandeja → puede **confirmar** (convierte NDP en Remito R-XXXX), **editar** o **rechazar** (con motivo)
4. Solo remitos `confirmado` cuentan para saldos y ganancias

## ESTRUCTURA DEL PROYECTO (~11.000 líneas, 22 archivos .dart — `ocr_service.dart` eliminado en v18.17)

```
don_chacho/lib/
├── main.dart                          # Login + sesión + tabs dinámicas por permisos + menú de acciones del FAB (admin: remito + NDP; secretaria: NDP)
├── models/models.dart                 # Vendedor, Cliente, Remito, RemitoItem, Pago, PagoMedio, CostoSemanal, NotaPedido, NotaPedidoItem, NotaCreditoDebito, RepartoLista, RepartoItem, Permiso, Rol, Usuario, RemitoEliminado, PagoEliminado
├── providers/app_provider.dart        # Estado global, FIFO, saldos, permisos, usuarioActual, NDPs
├── services/
│   ├── auth_service.dart              # Login SHA-256, sesión persistente SharedPreferences, CRUD usuarios/roles
│   ├── database_service.dart          # CRUD Supabase para todo + confirmarNotaPedido (convierte a remito) + getRepartoLista/getRepartoListaOPlantilla/guardarReparto
│   ├── estado_cuenta_service.dart     # PDF estado de cuenta + reporte vendedor + reporte cliente (movimientos) + PDF nota de pedido + comisión
│   ├── reparto_service.dart           # PDF de la lista de reparto para el repartidor (tabla CARNE/CERDO, TOTAL MEDIAS, SOBRANTE DEPÓSITO, notas) — v18.24
│   ├── recibo_service.dart            # PDF recibo de pago con detalle deuda FIFO
│   └── ruta_cobranza_service.dart     # Ruta de cobranza: extrae coords (incl. DMS), GPS web, resuelve links cortos vía Edge Function resolver-maps, orden vecino-cercano, URL Google Maps multi-parada (v18.14, ampliado v18.16)
├── screens/
│   ├── login_screen.dart              # Usuario + contraseña
│   ├── home_screen.dart               # Dashboard KPIs por tipo carne, navegación semanal < >, botón costos (con permiso)
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
│   ├── reparto_screen.dart            # Lista de reparto semanal (Jueves/Viernes): navegación semanal < >, TOTAL MEDIAS manual, clientes de la lista, SOBRANTE auto, notas, PDF. Se precarga con la lista de la semana anterior si la semana está vacía (v18.30). Módulo logístico aparte (sin plata). Accesible desde el FAB (v18.24)
│   ├── soporte_form_screen.dart       # Reportar un problema (v18.36): módulo del sistema, descripción, switch "no puedo seguir trabajando", foto adjunta. Al guardar muestra un diálogo con botón "Abrir WhatsApp" (v18.37: el launch tiene que salir de un toque, si no el navegador lo bloquea). Lista los últimos 5 reclamos propios con estado y respuesta. Accesible desde el FAB por todos los roles
│   └── bandeja_soporte_screen.dart    # Bandeja de soporte (v18.36, solo admin): 3 tabs Abiertos / En revisión / Resueltos con contadores. Detalle con foto (link firmado), campo de respuesta y botones de estado
└── utils/
    ├── app_config.dart                # Config por deploy vía --dart-define (v18.36): version, clienteNombre, soporteWhatsapp
    ├── formatters.dart                # formatPesos, formatKg, formatFecha, formatFechaHora, formatRangoSemana
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
- `usuarios` (id UUID, usuario UNIQUE, password_hash, rol_id FK, nombre_completo, activo, creado_en)

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

### Tablas Lista de reparto (v18.24)
- `reparto_listas` (id UUID PK, semana_inicio DATE, dia TEXT CHECK IN ('jueves','viernes'), total_medias_carne INT, total_medias_cerdo INT, notas TEXT, creado_en, **UNIQUE (semana_inicio, dia)**) — RLS off
- `reparto_items` (id UUID PK, lista_id UUID FK CASCADE, cliente_id UUID FK clientes, medias_carne INT, medias_cerdo INT, orden INT, creado_en) — index en lista_id, RLS off
- **Módulo 100% logístico, aparte del flujo comercial: NO toca plata, saldos ni remitos.** Solo qué carne (novillo=CARNE / cerdo=CERDO) va a cada cliente por semana.

### Tabla Soporte (v18.36)
- `soportes` (id UUID PK, **numero INT GENERATED BY DEFAULT AS IDENTITY**, modulo TEXT, descripcion TEXT, bloqueante BOOLEAN, adjunto_path TEXT, estado TEXT CHECK IN ('abierto','en_revision','resuelto'), respuesta TEXT, reportado_por TEXT, rol TEXT, app_version TEXT, plataforma TEXT, creado_en, resuelto_en, resuelto_por) — índices en estado y creado_en, RLS off
- El número de ticket (`S-0001`) lo asigna la **secuencia de Postgres**, no el cliente. Por eso `TicketSoporte.toMap()` omite `numero` cuando vale 0: a diferencia de remitos/pagos/NCD (que hacen max+1 del lado del cliente y tienen carrera), acá no hay chance de duplicados.
- Bucket **privado** `soporte-adjuntos` (10 MB, mime images incl. heic/heif). En la tabla se guarda el **path**, nunca la URL: los links se firman en el momento (90 días) para que un link reenviado por WhatsApp caduque solo, mientras la bandeja siempre puede firmar uno nuevo. Las policies apuntan al rol **`anon`** porque la app se conecta con la publishable key.

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
- KPIs de la semana: kg vendidos (novillo/cerdo), venta bruta, ganancia neta
- Cards de kg por tipo muestran también la cantidad de medias reses ("N medias")
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

### Consultas (9 tabs en consultas_screen.dart)
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
| v18.11 (junio) | Recibo unificado con detalle de deuda + saldo vencido; saldos históricos guardados en `pagos`; tab **Reporte** (estado de cuenta por cliente con saldo acumulado); tab **Eliminados** (auditoría de remitos + pagos borrados, tablas `remitos_eliminados`/`pagos_eliminados`); ofuscar KPIs en home; filtro vendedor en Vencidos y Directorio; vendedor en bandeja/PDF de NDP; admin puede crear NDP desde el FAB; varios fixes de recibo FIFO. |
| v18.12 (01/07) | **Recibo de pago corregido y simplificado**: muestra saldo histórico por pago (no el saldo actual), con desglose Saldo anterior − Pago realizado → Saldo restante total + Saldo vencido + tabla de deuda, todo concordante entre sí. Se agrega **hora HH:MM** al encabezado y se quita la sección "Pagos aplicados". Backfill SQL (`supabase_backfill_saldos_pagos.sql`) que rellena `saldo_anterior`/`saldo_nuevo` de todos los pagos viejos. En Historial > Remitos no se puede editar un remito. Remito/NDP/Pago: todos eliminables, consultables en Eliminados y piden observación al borrar. |
| v18.13 (01/07) | **Tab Reporte más legible + exportar PDF**: leyenda de colores, signos +/− en los montos, pill "Pago" en la columna Estado (antes vacía) y header "Saldo" → "Saldo acum." Nuevo botón "Exportar PDF" que genera el reporte por cliente en PDF (`generarReporteCliente`), replicando la tabla en pantalla. Fix menor en `web/index.html` (splash con `pointer-events:none` durante el fade-out). |
| v18.14 (01/07) | **Ruta de cobranza (1ª versión)**: embebida en Consultas → Directorio, combo box (Clientes que deben / Solo remitos vencidos) + botón "Armar". Nuevo `ruta_cobranza_service.dart` (GPS, extracción de coords, orden por cercanía, URL Google Maps). Reemplazada por la tab "Ruta" en v18.15. |
| v18.15 (01/07) | **Ruta de cobranza movida a tab propia "Ruta"** en Consultas (9 tabs). Filtros: cliente (búsqueda), vendedor (dropdown), "Con saldo pendiente" y "Solo vencidos" (FilterChips). Lista con checkboxes para **seleccionar clientes** (los sin ubicación quedan deshabilitados) + "Todos/Ninguno". Botón "Armar recorrido (N)" que calcula la ruta con los elegidos (GPS + orden por cercanía) y abre el panel de paradas → Google Maps. Se quitó el bloque de ruta del Directorio. |
| v18.16 (02/07) | **Fix ubicaciones de la ruta + editar ubicación desde Directorio**: (1) `_parseCoords` reconoce ahora el formato **DMS** (`24°59'04.1"S`). (2) Nueva **Edge Function `resolver-maps`** (runtime nuevo, `withSupabase` con auth `["publishable","secret"]`) que resuelve del lado del servidor los **links cortos** `maps.app.goo.gl` (el navegador no puede por CORS): sigue el redirect y devuelve `lat/lng`, o si el link es un "compartir lugar" sin coords, devuelve la **dirección/nombre** (`q=…`). `RutaCobranzaService.construirParadas()` llama la función en lote para los clientes sin coords locales. `ParadaRuta` gana `direccionResuelta` y usa ese texto como punto ruteable. (3) En **Directorio**, botón de editar ubicación por tarjeta → bottom sheet para cargar/corregir Dirección + Link Maps (guarda con `editarCliente`). |
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

## ESTADO ACTUAL (v18.37) — EN PRODUCCIÓN

Deployada el 07/10/2026 desde la rama `fix/soporte-whatsapp` (commit `5a506d7`). Deploy `web-2f6u8cxou`, alias `web-six-indol-svg13avcfl.vercel.app` apuntando ahí. Arregla el aviso de WhatsApp del módulo de Soporte, que no abría nunca (ver fila v18.37 del historial). **Falta probarlo desde el celular**: el ticket ya se guardaba bien, lo que no funcionaba era el link.

### v18.36 — deployada el 07/10/2026

Deployada desde la rama `feat/soporte`, **ya mergeada a `master`** (PR #1, merge commit `6760477`). Deploy `web-5gub63yg0`. La migración `supabase_migration_soporte.sql` ya se corrió: tabla `soportes` verificada por REST y bucket `soporte-adjuntos` verificado en el dashboard. `AppConfig.soporteWhatsapp` quedó en `5493874159555` (WhatsApp de Mili, la desarrolladora).

### v18.31 — deployada el 22/09/2026

Deployada el 22/09/2026. Login funciona con admin/admin123. Flutter 3.41.8. URL: `https://web-six-indol-svg13avcfl.vercel.app`. **v18.31 salió de la rama `feat/reparto-precarga` (deployada a prod pero NO mergeada a `master` todavía; la rama acumula v18.30 + v18.31). La versión previa `feat/reparto-voz` sí está mergeada a `master` (v18.29).**

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
- `login(usuario, password)`: retorna Usuario con Rol y permisos, o null
- `restaurarSesion()`: lee userId de SharedPreferences, recarga desde DB
- `cerrarSesion()`: limpia SharedPreferences
- `hashPassword(String)`: SHA-256
- CRUD: `getUsuarios`, `crearUsuario`, `actualizarUsuario`, `eliminarUsuario`
- CRUD: `getRoles`, `crearRol`, `actualizarRol`, `eliminarRol`
- `getPermisos()`: catálogo completo
- `cambiarPassword(userId, actual, nueva)`: verifica actual antes de cambiar

## CAMBIOS PENDIENTES

- **Soporte — mejoras no implementadas**: badge con la cantidad de tickets abiertos en el item del FAB (requiere sumar la query a `AppProvider.cargarDatos`); aviso push/mail en vez del WhatsApp manual.
- **Lista de reparto — Fase 2 (audio)**: cargar la lista por audio de WhatsApp (audio → transcripción Whisper/Gemini → parseo estructurado con Claude). Diferido explícitamente por el usuario.
- **Ejecutar `supabase_migration_indices.sql`** en Supabase Dashboard → SQL Editor (una sola vez). Agrega 6 índices para acelerar la carga inicial.
- **Borrar los 3 pagos de prueba de Perico + el cliente duplicado "A" vacío** (ver v18.22, punto 3). Se hace desde la app; verificar saldo $4.906.800 después.
- **Prevenir clientes duplicados por teléfono** (mejora ofrecida, no implementada): avisar/impedir crear un cliente con un teléfono que ya existe. Motivó el bug del Perico duplicado.

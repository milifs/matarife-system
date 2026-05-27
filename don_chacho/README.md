# 🥩 Granja Don Chacho - Módulo Matarife Terceros

## Fase 1: MVP - ABM + Remitos + Saldos

### ¿Qué incluye esta fase?

- **ABM Vendedores**: alta, baja, modificación (nombre, apellido, teléfono)
- **ABM Clientes**: por vendedor, con plazo de pago fijo
- **Carga de remitos**: selección de cliente, fecha, múltiples items (tipo carne, medias, kg, $/kg)
- **Cálculo automático de saldos**: por cliente y por vendedor
- **Dashboard**: KPIs principales (saldo total, kg vendidos, costo semanal)
- **Carga manual de costo por kg semanal**

### Requisitos previos

1. **Flutter SDK** >= 3.2.0 ([instalación](https://docs.flutter.dev/get-started/install))
2. **Cuenta en Supabase** (gratis: [supabase.com](https://supabase.com))
3. **Editor**: VS Code con extensión Flutter o Android Studio

### Configuración paso a paso

#### 1. Crear proyecto en Supabase

1. Andá a [app.supabase.com](https://app.supabase.com) y creá un nuevo proyecto
2. Anotá la **URL** y la **anon key** (las vas a necesitar)

#### 2. Crear las tablas

1. En Supabase, andá a **SQL Editor**
2. Copiá todo el contenido del archivo `supabase_schema.sql`
3. Ejecutá el script

#### 3. Crear el bucket de fotos

1. En Supabase, andá a **Storage**
2. Creá un bucket llamado `fotos-remitos`
3. Marcalo como **público**

#### 4. Configurar la app

Abrí `lib/main.dart` y reemplazá las credenciales:

```dart
await Supabase.initialize(
  url: 'https://TU_PROYECTO.supabase.co',  // ← Tu URL
  anonKey: 'TU_ANON_KEY',                   // ← Tu anon key
);
```

#### 5. Instalar dependencias y correr

```bash
cd don_chacho
flutter pub get
flutter run            # Android/iOS
flutter run -d chrome  # Web
```

### Estructura del proyecto

```
lib/
├── main.dart                      # Entrada + navegación
├── models/
│   └── models.dart                # Vendedor, Cliente, Remito, Pago, etc.
├── providers/
│   └── app_provider.dart          # Estado global (Provider)
├── services/
│   └── database_service.dart      # CRUD Supabase
├── screens/
│   ├── home_screen.dart           # Dashboard con KPIs
│   ├── vendedores_screen.dart     # ABM vendedores
│   ├── vendedor_detalle_screen.dart # Detalle + clientes del vendedor
│   ├── clientes_screen.dart       # Lista general de clientes
│   └── remito_form_screen.dart    # Carga de remito
├── utils/
│   ├── formatters.dart            # Formato de moneda, fechas, kg
│   └── theme.dart                 # Tema visual + StatusPill
└── widgets/                       # (Componentes reutilizables)
```

### Reglas de negocio implementadas

| Regla | Implementación |
|-------|---------------|
| Saldo cliente = Σ remitos - Σ pagos | `AppProvider._recalcularSaldos()` |
| Saldo vendedor = Σ saldos de sus clientes | Calculado en tiempo real |
| Transferencia: -5% rentas -1.2% CyD = -6.2% | `PagoMedio.recalcular()` |
| Efectivo y cheque: sin descuento | Descuento = 0 |
| Plazo de pago: fijo por cliente | Campo `plazo_pago_dias` en Cliente |
| Costo por kg: manual semanal | Tabla `costos_semana` |

### Próximas fases

- **Fase 2**: Sistema de pagos con múltiples medios + recibo PDF + WhatsApp
- **Fase 3**: OCR de remitos (foto → datos automáticos)
- **Fase 4**: Consultas avanzadas, ganancia por vendedor/cliente, saldos vencidos

## Deploy a producción (Cloudflare Pages)

### Compilar para producción

En vez de `flutter build web` plano, usar los scripts incluidos:

- **Windows**: doble clic en `build_web.bat` o ejecutar en terminal desde la carpeta `don_chacho`
- **Linux / Mac**: `./build_web.sh` (si da "permission denied": `chmod +x build_web.sh` primero)

### Flags utilizadas

| Flag | Qué hace |
|------|----------|
| `--release` | Modo producción: optimizado y minificado |
| `--tree-shake-icons` | Elimina íconos Material no usados (~1.5 MB menos) |
| `--pwa-strategy=none` | Desactiva el service worker para que cada deploy se vea al instante sin borrar caché |

### Subir a Cloudflare Pages

1. Crear cuenta gratuita en [pages.cloudflare.com](https://pages.cloudflare.com)
2. Crear un nuevo proyecto:
   - **Opción A (recomendada)**: conectar el repositorio Git y configurar el build command como `flutter build web --release --tree-shake-icons --pwa-strategy=none` con output directory `build/web`
   - **Opción B**: subir manualmente la carpeta `build/web` como "Direct Upload"
3. El archivo `web/_headers` ya está incluido en `build/web` después del build y Cloudflare lo aplica automáticamente para controlar el caché de cada tipo de archivo

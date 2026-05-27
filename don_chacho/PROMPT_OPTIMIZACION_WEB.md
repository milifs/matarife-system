# Prompt para Claude Code — Optimización de Flutter Web (Don Chacho)

Copiá todo lo que está abajo de la línea `---` y pegalo como mensaje a Claude Code dentro de la carpeta `C:\App Joaco\don_chacho_v17\don_chacho`. Hace todos los cambios de una sola vez.

---

# Tarea: Optimizar la carga inicial y el cacheo de la app Flutter Web "Don Chacho"

Soy el dueño de una app Flutter Web (`don_chacho_matarife`) que está en esta carpeta. Hoy tiene dos problemas:

1. La primera carga es muy lenta (5–10 segundos en blanco).
2. Después de cada deploy, los usuarios tienen que borrar la caché del navegador para ver los cambios.

Quiero que apliques las siguientes optimizaciones, en este orden, sin tocar nada de la lógica de negocio ni de las pantallas. Trabajá solo en archivos de configuración web y build. El theme color de la app es `#C62828` (rojo) y el logo está en `web/icons/Icon-192.png`.

## Paso 1 — Modificar `web/index.html` para mostrar un splash screen propio

Reemplazá completamente el contenido de `web/index.html` para que:

- Mantenga todos los `meta` tags y links actuales (iOS PWA, viewport, manifest, favicon, apple-touch-icon).
- Mantenga el `<title>Granja Don Chacho</title>`.
- Mantenga `<base href="$FLUTTER_BASE_HREF">`.
- Mantenga el `<script src="flutter_bootstrap.js" async></script>`.
- Agregue un splash inline con:
  - Fondo blanco a pantalla completa, centrado.
  - El logo (`icons/Icon-192.png`) de 120×120 px con bordes redondeados de 24px.
  - Debajo del logo, el texto "Granja Don Chacho" en 22px, peso 600, color `#1a1a1a`.
  - Debajo del texto, un spinner CSS (un círculo girando) de 36px, color `#C62828`, animación de 1 segundo.
  - Texto pequeño "Cargando..." debajo del spinner, 13px, color gris `#6b7280`.
- Agregue un script al final del `<body>` que escuche cuando Flutter terminó de levantar y oculte el splash con fade-out de 300ms. Usá el evento `flutter-first-frame` (se dispara cuando Flutter pinta el primer frame). Como fallback, también ocultá el splash a los 8 segundos por si el evento no se dispara.
- El CSS del splash debe ir inline en un `<style>` dentro del `<head>` para que cargue antes que cualquier otra cosa.

El resto del HTML actual (los meta de iOS, viewport, apple-touch-icon, manifest, theme-color) debe quedar igual.

## Paso 2 — Crear el archivo `web/_headers` para Cloudflare Pages

Creá un archivo nuevo en `web/_headers` (sin extensión) con este contenido exacto, que controla los cache headers cuando deploye a Cloudflare Pages o Vercel:

```
/index.html
  Cache-Control: no-cache, no-store, must-revalidate

/flutter_service_worker.js
  Cache-Control: no-cache, no-store, must-revalidate

/manifest.json
  Cache-Control: no-cache, no-store, must-revalidate

/main.dart.js
  Cache-Control: public, max-age=31536000, immutable

/flutter.js
  Cache-Control: public, max-age=31536000, immutable

/canvaskit/*
  Cache-Control: public, max-age=31536000, immutable

/assets/*
  Cache-Control: public, max-age=31536000, immutable

/icons/*
  Cache-Control: public, max-age=2592000
```

## Paso 3 — Crear `build_web.bat` y `build_web.sh` en la raíz del proyecto

Creá dos scripts (uno para Windows, uno para Linux/Mac) que compilen la web con las flags optimizadas. El comando debe ser:

```
flutter build web --release --web-renderer auto --tree-shake-icons --pwa-strategy=none
```

El `.bat` para Windows debe imprimir un mensaje al terminar diciendo que el build quedó en `build/web` y recordar al usuario subir esa carpeta a Cloudflare Pages. El `.sh` debe hacer lo mismo y tener `chmod +x` implícito por el shebang `#!/usr/bin/env bash`.

## Paso 4 — Actualizar el README.md

Al final del `README.md` actual, agregá una sección nueva titulada `## Deploy a producción (Cloudflare Pages)` que explique:

1. Que para compilar para producción ahora se usa `build_web.bat` (Windows) o `./build_web.sh` (Linux/Mac), no `flutter build web` plano.
2. Las flags que se usan y qué hace cada una en una línea:
   - `--release` → modo producción, optimizado y minificado.
   - `--web-renderer auto` → renderer HTML en móvil, CanvasKit en desktop.
   - `--tree-shake-icons` → elimina íconos Material no usados (~1.5 MB menos).
   - `--pwa-strategy=none` → desactiva el service worker para que los cambios de cada deploy se vean al instante sin borrar caché.
3. Pasos para subir a Cloudflare Pages:
   - Crear cuenta gratis en `pages.cloudflare.com`.
   - Conectar el repo de Git o subir manualmente la carpeta `build/web`.
   - Que el archivo `_headers` ya está incluido y se aplica automáticamente.

No agregues secciones de Vercel ni otros hostings; con Cloudflare alcanza.

## Paso 5 — Verificación final

Cuando termines todos los cambios, mostrame:

1. Un resumen de qué archivos creaste y cuáles modificaste.
2. El comando exacto que tengo que correr para probar localmente: `flutter build web --release --web-renderer auto --tree-shake-icons --pwa-strategy=none` seguido de cómo servirlo en local para verificar el splash (usá `python -m http.server` desde `build/web` o sugerí algo equivalente).
3. Una advertencia visible si detectás que el `web/index.html` actual tenía algún customization que valga la pena preservar (por ejemplo, los meta tags de iOS PWA que ya están).

## Restricciones importantes

- No modifiques nada en `lib/`, `supabase_functions/`, ni en ningún archivo `.sql`.
- No toques `pubspec.yaml` ni `pubspec.lock`.
- No corras `flutter pub get` ni `flutter build` vos; solo dejá todo listo para que yo corra el build.
- No borres archivos existentes en `web/` (favicon.png, manifest.json, icons/, etc.).
- Si encontrás `build/web` con archivos viejos, dejalos como están; se regeneran al hacer build.

Cuando termines, decime "Listo, corré `build_web.bat` para probar" o el equivalente.

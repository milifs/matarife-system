#!/usr/bin/env bash
set -e
echo "Compilando Granja Don Chacho para produccion..."
flutter build web --release --tree-shake-icons --pwa-strategy=none

# ── app_version.json ────────────────────────────────────────────────────
# Lo consulta la app corriendo para saber si el bundle que tiene el usuario
# quedo viejo (ver lib/services/version_service.dart). Sale del MISMO
# AppConfig.version que viaja compilado adentro del bundle, asi los dos
# numeros no pueden discrepar.
#
# Se escribe DESPUES del build a proposito: flutter build web limpia
# build/web, asi que un archivo puesto antes se perderia.
VERSION=$(grep -oE "version = '[^']+'" lib/utils/app_config.dart | head -1 | cut -d"'" -f2 || true)

if [ -z "$VERSION" ]; then
  echo "ERROR: no se pudo leer la version de lib/utils/app_config.dart"
  echo "Sin app_version.json la app no puede avisar que hay version nueva."
  exit 1
fi

printf '{"version":"%s","buildeado":"%s"}\n' \
  "$VERSION" \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  > build/web/app_version.json

echo ""
echo "Build finalizado. Los archivos quedaron en build/web"
echo "Version publicada: $VERSION"
echo "Para deployar: cd build/web && vercel --prod"

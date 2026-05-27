#!/usr/bin/env bash
set -e
echo "Compilando Granja Don Chacho para produccion..."
flutter build web --release --tree-shake-icons --pwa-strategy=none
echo ""
echo "Build finalizado. Los archivos quedaron en build/web"
echo "Subir la carpeta build/web a Cloudflare Pages para deployar."

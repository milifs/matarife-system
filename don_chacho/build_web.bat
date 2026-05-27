@echo off
echo Compilando Granja Don Chacho para produccion...
"C:\Users\admin\Flutter\flutter\bin\flutter.bat" build web --release --tree-shake-icons --pwa-strategy=none

echo.
echo Aplicando cache-busting...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0cache_bust.ps1"

echo.
echo Build finalizado. Los archivos quedaron en build\web
echo Subir la carpeta build\web a Cloudflare Pages para deployar.

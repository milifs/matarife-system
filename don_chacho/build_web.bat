@echo off
echo Compilando Granja Don Chacho para produccion...
"C:\Users\admin\Flutter\flutter\bin\flutter.bat" build web --release --tree-shake-icons --pwa-strategy=none

echo.
echo Aplicando cache-busting...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0cache_bust.ps1"

echo.
echo Generando app_version.json...
rem Lo consulta la app corriendo para saber si el bundle que tiene el usuario
rem quedo viejo (ver lib\services\version_service.dart). Sale del MISMO
rem AppConfig.version que viaja compilado adentro del bundle. Tiene que
rem generarse DESPUES del build, porque flutter build web limpia build\web.
rem Si este paso falta, la app queda comparando contra un archivo viejo y
rem avisa de una version nueva que no existe.
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$v = (Select-String -Path 'lib\utils\app_config.dart' -Pattern \"version = '([^']+)'\").Matches[0].Groups[1].Value; ^
   if ([string]::IsNullOrEmpty($v)) { Write-Error 'No se pudo leer la version de app_config.dart'; exit 1 }; ^
   $t = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'); ^
   \"{\"\"version\"\":\"\"$v\"\",\"\"buildeado\"\":\"\"$t\"\"}\" | Set-Content -NoNewline -Encoding UTF8 'build\web\app_version.json'; ^
   Write-Host \"Version publicada: $v\""

echo.
echo Build finalizado. Los archivos quedaron en build\web
echo Para deployar: cd build\web ^&^& vercel --prod

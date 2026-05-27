$v = Get-Date -Format 'yyyyMMddHHmmss'

# Patch flutter_bootstrap.js: agrega ?v= al mainJsPath de main.dart.js
$fb = 'build\web\flutter_bootstrap.js'
$c = Get-Content $fb -Raw -Encoding UTF8
$c = $c -replace '"main\.dart\.js"', ('"main.dart.js?v=' + $v + '"')
[System.IO.File]::WriteAllText((Resolve-Path $fb), $c, [System.Text.Encoding]::UTF8)

# Patch index.html: agrega ?v= al src de flutter_bootstrap.js
$ih = 'build\web\index.html'
$c2 = Get-Content $ih -Raw -Encoding UTF8
$c2 = $c2 -replace 'src="flutter_bootstrap\.js"', ('src="flutter_bootstrap.js?v=' + $v + '"')
[System.IO.File]::WriteAllText((Resolve-Path $ih), $c2, [System.Text.Encoding]::UTF8)

Write-Host "Cache-busting aplicado: v=$v"

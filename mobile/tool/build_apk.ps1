# Сборка APK для GuYo с проверкой, что внутри правильный адрес сервера.
#
# Зачем проверка: один раз APK собрали без --dart-define=API_BASE_URL, и внутрь
# попал адрес по умолчанию из mobile/lib/config.dart (http://10.0.2.2:8000 --
# это эмулятор, а не боевой сервер). Сборка считалась успешной, а на телефоне
# приложение не соединялось ни с чем. Теперь такая сборка падает с ошибкой.
#
# Запуск (из папки mobile):
#   pwsh -File tool/build_apk.ps1
#   powershell -ExecutionPolicy Bypass -File tool\build_apk.ps1

$ErrorActionPreference = 'Stop'
$backend = 'https://backend-production-cda3.up.railway.app'
$host_expected = 'railway.app'

$mobile = Split-Path -Parent $PSScriptRoot
$apk = Join-Path $mobile 'build\app\outputs\flutter-apk\app-release.apk'

Write-Host "Собираю APK с адресом $backend ..."
Push-Location $mobile
try {
    flutter build apk --release "--dart-define=API_BASE_URL=$backend"
    if ($LASTEXITCODE -ne 0) { throw "flutter build apk завершился с кодом $LASTEXITCODE" }
} finally {
    Pop-Location
}

if (-not (Test-Path $apk)) { throw "APK не найден: $apk" }

# Проверка: адрес должен быть ЗАШИТ в сборку, а адрес эмулятора -- отсутствовать.
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("guyo_apk_" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
    Copy-Item $apk (Join-Path $tmp 'app.zip')
    Expand-Archive (Join-Path $tmp 'app.zip') -DestinationPath (Join-Path $tmp 'x') -Force
    $so = Get-ChildItem (Join-Path $tmp 'x\lib') -Recurse -Filter 'libapp.so' | Select-Object -First 1
    if (-not $so) { throw "В APK нет libapp.so -- проверить сборку" }

    $text = [System.Text.Encoding]::ASCII.GetString([System.IO.File]::ReadAllBytes($so.FullName))
    $good = ([regex]::Matches($text, [regex]::Escape($host_expected))).Count
    $bad = ([regex]::Matches($text, '10\.0\.2\.2')).Count

    Write-Host "Проверка адреса: '$host_expected' = $good, '10.0.2.2' = $bad"
    if ($good -lt 1) { throw "В APK НЕТ адреса $host_expected -- сборка без --dart-define=API_BASE_URL. Такой APK на телефоне не работает." }
    if ($bad -gt 0) { throw "В APK попал адрес эмулятора 10.0.2.2 -- сборка неверная." }
} finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

$size = [math]::Round((Get-Item $apk).Length / 1MB, 1)
$hash = (Get-FileHash $apk -Algorithm SHA256).Hash
Write-Host "OK: APK $size МБ, SHA-256 $hash"
Write-Host "Адрес сервера внутри: $backend"

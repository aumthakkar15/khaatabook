# Khaata Book — build the release APK.
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root
if (-not (Test-Path "android")) {
  Write-Host "Run the first-time setup first (1 - SETUP.bat)." -ForegroundColor Red
  Read-Host "Press Enter to close"; exit 1
}
Write-Host "=== Building Khaata Book APK (release) ===" -ForegroundColor Cyan
flutter build apk --release
if ($LASTEXITCODE -eq 0) {
  $apk = Join-Path $root "build\app\outputs\flutter-apk\app-release.apk"
  $out = Join-Path $root "KhaataBook.apk"
  Copy-Item $apk $out -Force
  Write-Host ""
  Write-Host "APK ready:  $out" -ForegroundColor Green
  Write-Host "Copy KhaataBook.apk to your phone and open it to install."
  explorer.exe /select,"$out"
} else {
  Write-Host "Build failed - copy the error above and send it to Claude." -ForegroundColor Red
}
Read-Host "Press Enter to close"

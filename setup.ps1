# Khaata Book — first-time setup. Double-click "1 - SETUP.bat" or run this from VS Code (Terminal > Run Task).
$ErrorActionPreference = "Continue"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root
Write-Host "=== Khaata Book: first-time setup ===" -ForegroundColor Cyan

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  Write-Host ""
  Write-Host "Flutter is not installed or not on your PATH." -ForegroundColor Red
  Write-Host "1) Download the Flutter SDK zip: https://docs.flutter.dev/get-started/install/windows/mobile"
  Write-Host "2) Extract to C:\dev\flutter"
  Write-Host "3) Add C:\dev\flutter\bin to your PATH (Windows search: 'environment variables')"
  Write-Host "4) Close and reopen VS Code, then run this again."
  Read-Host "Press Enter to close"
  exit 1
}

Write-Host "`n[1/3] Creating the Android project files..." -ForegroundColor Yellow
flutter create --org com.biztras --project-name khaata_book --platforms android .
if ($LASTEXITCODE -ne 0) { Write-Host "flutter create failed - see the message above." -ForegroundColor Red; Read-Host "Press Enter to close"; exit 1 }

Write-Host "`n[2/3] Applying Khaata Book Android settings..." -ForegroundColor Yellow
& "$root\setup_android.ps1"

Write-Host "`n[3/3] Downloading packages..." -ForegroundColor Yellow
flutter pub get
if ($LASTEXITCODE -ne 0) { Write-Host "flutter pub get failed - see the message above." -ForegroundColor Red; Read-Host "Press Enter to close"; exit 1 }

Write-Host "`nChecking your Flutter installation..." -ForegroundColor Yellow
flutter doctor

Write-Host ""
Write-Host "=== Setup complete ===" -ForegroundColor Green
Write-Host "Next: connect your phone (USB debugging on) or start an emulator, then in VS Code press F5."
Write-Host "To make the APK: double-click '2 - BUILD APK.bat' or Terminal > Run Build Task (Ctrl+Shift+B)."
Read-Host "Press Enter to close"

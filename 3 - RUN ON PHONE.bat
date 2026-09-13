@echo off
cd /d "%~dp0"
echo Connect your phone (USB debugging on) or start an emulator, then press any key...
pause >nul
flutter run
pause

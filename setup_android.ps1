# Khaata Book — one-time Android setup after "flutter create".
# Run from the project folder in PowerShell:   .\setup_android.ps1
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

if (-not (Test-Path "android")) {
  Write-Host "android folder not found. Run first:  flutter create --org com.biztras --project-name khaata_book ." -ForegroundColor Red
  exit 1
}

# 1) Copy manifest + MainActivity
Copy-Item "android_overrides\app\src\main\AndroidManifest.xml" "android\app\src\main\AndroidManifest.xml" -Force
$ktDir = "android\app\src\main\kotlin\com\biztras\khaata_book"
New-Item -ItemType Directory -Force -Path $ktDir | Out-Null
Get-ChildItem "android\app\src\main\kotlin" -Recurse -Filter "MainActivity.kt" | Remove-Item -Force
Copy-Item "android_overrides\app\src\main\kotlin\com\biztras\khaata_book\MainActivity.kt" "$ktDir\MainActivity.kt" -Force
Write-Host "Copied AndroidManifest.xml and MainActivity.kt"

# 2) Patch app/build.gradle(.kts): minSdk 23, desugaring (needed by notifications)
$kts = "android\app\build.gradle.kts"
$groovy = "android\app\build.gradle"
if (Test-Path $kts) {
  $c = Get-Content $kts -Raw
  $c = $c -replace 'minSdk\s*=\s*flutter\.minSdkVersion', 'minSdk = 23'
  $c = $c -replace 'minSdk\s*=\s*\d+', 'minSdk = 23'
  if ($c -notmatch 'isCoreLibraryDesugaringEnabled') {
    $c = $c -replace '(compileOptions\s*\{)', "`$1`n        isCoreLibraryDesugaringEnabled = true"
  }
  if ($c -notmatch 'coreLibraryDesugaring\(') {
    if ($c -match '(?m)^dependencies\s*\{') {
      $c = $c -replace '(?m)^(dependencies\s*\{)', "`$1`n    coreLibraryDesugaring(`"com.android.tools:desugar_jdk_libs:2.1.4`")"
    } else {
      $c += "`n`ndependencies {`n    coreLibraryDesugaring(`"com.android.tools:desugar_jdk_libs:2.1.4`")`n}`n"
    }
  }
  if ($c -notmatch 'applicationId\s*=\s*"com\.biztras\.khaata_book"') {
    $c = $c -replace 'applicationId\s*=\s*"[^"]+"', 'applicationId = "com.biztras.khaata_book"'
  }
  Set-Content $kts $c -NoNewline
  Write-Host "Patched android/app/build.gradle.kts"
} elseif (Test-Path $groovy) {
  $c = Get-Content $groovy -Raw
  $c = $c -replace 'minSdkVersion\s+flutter\.minSdkVersion', 'minSdkVersion 23'
  $c = $c -replace 'minSdk\s*=?\s*flutter\.minSdkVersion', 'minSdk 23'
  $c = $c -replace 'minSdkVersion\s+\d+', 'minSdkVersion 23'
  if ($c -notmatch 'coreLibraryDesugaringEnabled') {
    $c = $c -replace '(compileOptions\s*\{)', "`$1`n        coreLibraryDesugaringEnabled true"
  }
  if ($c -notmatch 'coreLibraryDesugaring ') {
    if ($c -match '(?m)^dependencies\s*\{') {
      $c = $c -replace '(?m)^(dependencies\s*\{)', "`$1`n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'"
    } else {
      $c += "`n`ndependencies {`n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'`n}`n"
    }
  }
  $c = $c -replace 'applicationId\s+"[^"]+"', 'applicationId "com.biztras.khaata_book"'
  Set-Content $groovy $c -NoNewline
  Write-Host "Patched android/app/build.gradle"
}

Write-Host ""
Write-Host "Android setup done. Next:  flutter pub get   then   flutter run   or   flutter build apk --release" -ForegroundColor Green

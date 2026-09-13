# Khaata Book — using it from VS Code (no commands to type)

## Before you start (one time only)

Flutter must be installed on the laptop — the app is built with it. If `1 - SETUP.bat` says "Flutter is not installed", do this once:

1. Download the Flutter SDK zip from https://docs.flutter.dev/get-started/install/windows/mobile and extract it to `C:\dev\flutter`.
2. Windows search → **"Edit environment variables for your account"** → select **Path** → **Edit** → **New** → type `C:\dev\flutter\bin` → OK, OK.
3. Install Android Studio from https://developer.android.com/studio (Standard setup). Open it once so it downloads the Android SDK.
4. Restart the laptop (so the PATH change is picked up everywhere).

## Step A — First-time setup (double-click)

1. Extract `khaata_book.zip` to `C:\dev\khaata_book`.
2. Double-click **`1 - SETUP.bat`** in that folder. It creates the Android project, applies the app settings and downloads packages. Takes 2–5 minutes; leave the window open until it says *Setup complete*.
   - If it asks about Android licenses, answer `y`.

## Step B — Open in VS Code

1. VS Code → **File → Open Folder** → `C:\dev\khaata_book`.
2. VS Code will suggest installing the **Flutter** extension (bottom-right pop-up) → click **Install**. (Or Ctrl+Shift+X and search "Flutter".)

## Step C — Run the app on your phone (F5)

1. Connect your Android phone by USB with **USB debugging** on (Settings → About phone → tap *Build number* 7 times → Developer options → USB debugging). Tap **Allow** on the phone.
   - Or start an emulator: in VS Code press **Ctrl+Shift+P** → type *Flutter: Launch Emulator*.
2. Look at the **bottom-right corner** of VS Code: it shows the selected device (e.g. *SM-A546E* or *Pixel 7 API 34*). Click it to change.
3. Press **F5** (or Run → Start Debugging). The app installs and opens on the phone.
   - The first run downloads Android build tools and can take 5–15 minutes. Later runs take seconds.
4. While it's running, any file you save is applied to the phone instantly (hot reload). The ⟳ button at the top restarts it.

## Step D — Make the APK file

- Press **Ctrl+Shift+B** (Run Build Task), or double-click **`2 - BUILD APK.bat`**.
- When it finishes, a file **`KhaataBook.apk`** appears in the project folder (Explorer opens on it). Send it to any phone by WhatsApp / USB / email and tap it to install.

## Useful buttons in VS Code

| What you want | Where |
|---|---|
| Run on phone | **F5** |
| Stop the app | Red ■ in the debug toolbar |
| Choose phone/emulator | Bottom-right status bar |
| Build APK | **Ctrl+Shift+B** |
| Other tasks (pub get, doctor, devices, install, clean) | **Terminal → Run Task…** |
| See app logs / errors | **Debug Console** panel at the bottom |

## Shortcuts in the folder

| File | Does |
|---|---|
| `1 - SETUP.bat` | First-time setup |
| `2 - BUILD APK.bat` | Builds `KhaataBook.apk` |
| `3 - RUN ON PHONE.bat` | Runs the app without opening VS Code |

## If something goes wrong

- Red text in the terminal → copy it and send it to Claude; it's usually a one-line fix.
- "No devices found" → check USB debugging is on, try another cable/port, or start an emulator.
- "flutter is not recognized" → Flutter isn't on PATH yet (see *Before you start*), then restart VS Code.

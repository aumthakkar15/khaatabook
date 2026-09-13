# Khaata Book — build the APK (VS Code + Flutter)

You already have Flutter set up from the earlier guide (`flutter doctor` green for Flutter, Android toolchain, VS Code).

## 1. Unzip and open

1. Extract `khaata_book.zip` to `C:\dev\khaata_book`.
2. Open VS Code → **File → Open Folder** → `C:\dev\khaata_book`.
3. Open the terminal (**Ctrl + `**). Every command below runs there.

## 2. Generate the Android project (one time)

The zip contains the app code (`lib/`), `pubspec.yaml` and Android overrides. Flutter generates the rest:

```powershell
flutter create --org com.biztras --project-name khaata_book --platforms android .
.\setup_android.ps1
flutter pub get
```

`setup_android.ps1` copies the Android manifest (permissions for fingerprint, notifications, internet) and `MainActivity.kt`, sets `minSdk 23`, and turns on desugaring (needed by notifications). If PowerShell refuses to run scripts, run once:
`Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` and try again — or make the three edits by hand as listed in `android_overrides/README.txt`.

## 3. Run on your phone (hot reload)

Phone connected with USB debugging (or emulator running):

```powershell
flutter run
```

## 4. Build the APK

```powershell
flutter build apk --release
```

Result: `build\app\outputs\flutter-apk\app-release.apk` — copy to any Android phone and install.
(`flutter build apk --debug` is quicker for testing; `flutter install` installs straight to the connected phone.)

## First run

1. **Create an account** — name, login ID, password, country (sets the base currency).
2. **Currencies → Sync now** (needs internet once) so foreign-currency entries convert; or type rates manually.
3. Add your **Accounts** (Home → Accounts): cash wallet, bank accounts, credit cards (limit, bill day, due day).
4. Tap **+** to add expenses, income and transfers. Turn on **Repeat** for recurring ones.
5. **Settings → Fingerprint login** to skip the password next time.
6. **Settings → Backup & restore** to set a backup password and turn on automatic backup.

## Where things are

| Feature | Code |
|---|---|
| Login / register / fingerprint | `lib/services/auth_service.dart`, `screens/login_screen.dart`, `register_screen.dart` |
| Currency master + online sync | `services/currency_service.dart`, `screens/currencies_screen.dart` |
| Categories + Excel import | `services/category_service.dart`, `screens/categories_screen.dart` |
| Accounts, archive, consolidated balance | `services/account_service.dart`, `screens/accounts_screen.dart` |
| Credit cards, cycles, pay card | `services/card_service.dart`, `screens/credit_card_screen.dart` |
| Loans / EMI | `services/loan_service.dart`, `screens/loans_screen.dart` |
| Transactions & transfers | `services/transaction_service.dart`, `screens/add_transaction_screen.dart` |
| Reports (list / chart / graph) | `services/report_service.dart`, `screens/reports_screen.dart` |
| Recurring | `services/recurring_service.dart`, `screens/recurring_screen.dart` |
| Backup / restore | `services/backup_service.dart`, `screens/backup_screen.dart` |
| Reminders | `services/notification_service.dart` |
| Money formatting rule (minus first, red) | `utils/money.dart`, `widgets/common.dart` (MoneyText) |

## Notes

- **Internet is used only** for currency rate sync (open.er-api.com) and when you choose to save a backup to Google Drive. Everything else is offline; all data is in a local SQLite database.
- **Google Drive**: backups are saved on the phone; after each backup (or from the Backup screen) choose *Save to Google Drive* — Android's file picker lets you pick your Drive folder. A fully automatic Drive upload needs a Google Cloud OAuth setup; tell me if you want that added later.
- **Automatic backup / EMI / recurring / card cycles** run when the app is opened (or comes to the foreground) after the scheduled time. Reminder notifications are scheduled on the phone.
- If `flutter pub get` reports a version conflict, run `flutter pub upgrade --major-versions` and send me the output.

# Khaata Book — feature list (running)

Design: Option A (navy header). Toolkit: Flutter, built from VS Code.

## 1. Authentication & onboarding
- Login screen: Login ID + password (existing users).
- Registration screen (new users): full name, login ID, password, country.
- Country selection sets the base currency for the whole app
  (e.g. India → INR, United Arab Emirates → AED). Currency preview shown on the form.
- Decision: accounts and ALL data live only on the phone. No server, no sharing, fully offline.
  Passwords stored hashed (never plain text); data in a local SQLite database.
- Password fields (Login and Register) have an eye button: tap to show/hide the typed password.

## 2. Biometric (fingerprint) login
- After the first successful password login, the app offers "Enable fingerprint login".
- Next time, Login screen shows "Sign in with fingerprint" — the phone's fingerprint sensor unlocks the app,
  no password needed. Password login stays available as fallback (and if the phone has no fingerprint set up).
- Can be turned on/off in Settings.

## 3. Multi-currency & currency master
- Currency master lists ALL world currencies (ISO 4217, ~160) with code, name, symbol, country.
- Each has a rate against the user's base currency (from registration). Base currency rate = 1.
- "Sync now" fetches live rates online (free public exchange-rate API; needs internet only for this step —
  everything else stays offline). Shows last-synced time. Optional auto-sync when app opens with internet.
- Manual override: user can edit any currency's rate. Manually set rates are marked "Manual" and are
  NOT overwritten by sync unless the user resets them to online.
- Filters: All / In use. Search by code, name or country.
- Transactions can be entered in any currency; the app stores the foreign amount + rate used and shows
  the converted base-currency amount in totals/reports.

## 4. Expense & income category master (with sub-categories)
- Two masters: Expense categories and Income categories, each with sub-categories (two levels).
- Add / edit / delete manually in the app (category name + icon + sub-category names).
- Import from Excel (.xlsx): columns Type (Expense/Income) | Category | Sub-category.
  App can share a blank template. Duplicate rows are skipped; summary shown after import.
- App ships with a sensible default set (Food & Dining, Transport, Bills, Housing, Health, Shopping…;
  Salary, Business, Rental, Interest, Other) which the user can edit.
- Add-transaction screen: pick category, then sub-category.

## 5. Accounts master (cash / bank / credit card)
- Account types: Cash, Bank account, Credit card. Fields: name, type, currency, opening balance,
  optional last-4 digits/note; credit card also: credit limit, statement/due day.
- Add / edit / archive manually. Import from Excel (.xlsx): Name | Type | Currency | Opening balance | Limit | Due day.
- Accounts screen shows balances grouped by type, net worth in base currency, credit-card used vs limit.
- Every transaction is tied to an account ("Paid by"), so balances update automatically.
- Transfer between accounts (e.g. bank → cash, bank → credit-card payment) as a transaction type.
- CONFIRMED: Transfer between accounts is a transaction type (from account, to account, amount, date, note;
  cross-currency transfers store the rate used). Available both:
  (a) manually — "Transfer" tab on the Add-transaction screen, and
  (b) via Excel import — sheet columns: Date | From account | To account | Amount | Currency | Note.

## 6. Credit card management
- Per card: total credit limit, available limit (= limit − outstanding), used amount and utilization %
  (shown as "32% · 3,200 of 10,000"), bill/statement date (day of month), payment due date (day of month).
- Billing cycle: app computes each cycle (bill date to bill date) and generates a "payment due" record
  = outstanding at bill date; shows on card screen and Home; marked paid when a payment covers it.
- Notifications: local reminder on the due date (and a heads-up a few days before — default 3 days,
  configurable in Settings). Works offline (on-device scheduled notifications).
- Pay this card (on the card screen): choose source = any bank account or another card, amount
  (with "Full due" shortcut) → reduces source balance, increases card available limit by the amount,
  recorded as a transfer transaction.

## 7. Number formatting rule (app-wide)
- Any negative balance/amount is shown in red (#C93B3B) with the minus sign FIRST, before the currency
  and amount: "- AED 3,200.00" / "-3,200.00". Never "3,200.00-" or brackets.
- Applies everywhere: account balances, net worth, credit-card outstanding, budget remaining, reports, history.
- Positive stays navy/default; income entries green with "+" first.

## 8. Loan management
- New loan: name, lender, loan amount, interest rate (% p.a.), tenure (months), start date, EMI day of month,
  "deduct from" = bank account or credit card. EMI auto-calculated (reducing-balance formula); user may override EMI.
- Full EMI schedule generated: per month principal / interest / remaining balance.
- Each month on the EMI date the app posts an expense (category "Loan EMI") against the chosen
  account/card → account balance reduces (or card outstanding increases), loan remaining balance
  reduces, EMI marked Paid. Reminder notification on EMI day; user can also mark/pay manually or prepay.
- Loan screen: remaining balance (red, minus first), progress (EMIs paid / total, %), monthly EMI,
  paid so far, interest paid, next deduction date, schedule list.
- Loans list on Accounts screen as a "Loans" group (negative balances).

## 9. Internal money transfer (confirmed & designed)
- Transfer tab on Add-transaction: From account, To account (any of cash / bank / credit card), amount, date, note.
- Saving reduces the From balance and increases the To balance by the same amount (to a credit card
  = reduces outstanding / restores available limit). Screen previews both new balances before save.
- Cross-currency: converted with the current rate, rate stored; user can adjust the received amount.
- Not counted as income or expense in reports. Also via Excel import (see feature 5).

## 10. Archive / inactive accounts
- Any account (cash, bank, credit card) can be marked Inactive (archived) from its edit screen or by
  long-press on the Accounts list. Archived accounts are hidden from pickers (Paid by, From/To, Pay from)
  and from Home totals, but their history is kept and still appears in past transactions/reports.
- Accounts screen: "Show archived" toggle at the bottom lists them greyed out with an "Archived" tag;
  tap → Reactivate. Account with a non-zero balance shows a warning before archiving.
- Deletion only allowed when the account has no transactions; otherwise archive.

## 11. Consolidated balance
- Consolidated balance = Cash + Bank balances − Credit-card outstanding − Loan remaining balances,
  all converted to base currency. Shown on Home ("Total balance") and on the Accounts screen with a
  breakdown (Cash + Bank / Card due + Loans). Negative → red, minus first.
- Accounts screen groups: Cash, Bank accounts, Credit cards, Loans. Archived accounts excluded.

## 12. Add expense / income screen — everything on one screen
- Single screen, no navigation away: type toggle (Expense / Income / Transfer), amount with currency
  picker, "Paid from / Received in" account chips (cash, bank, cards — horizontally scrollable, shows
  balance), category grid (most-used first, "All categories" opens full list), sub-category chips
  for the chosen category, date (defaults today) and note, Save.
- Income tab shows income categories/sub-categories and "Received in" account.
- Last used account and category are pre-selected next time for speed.

## 13. Expense & income reports
- Filters (one row, always visible): period (month picker or custom date range), type (Expense / Income /
  Both), category → sub-category, account, report currency (base by default; any master currency selectable).
- Views: List (grouped totals with drill-down category → sub-category → transactions),
  Chart (bars: income vs expense by month; horizontal bars by category / sub-category),
  Graph (line trend over time; pie/donut share by category).
- Currency conversion: each transaction stores its original currency + amount. Reports convert to the
  chosen report currency using the master rate. Rule: use the rate stored on the transaction at entry
  time by default, with a toggle "Use current master rates". Rounding to 2 decimals only at display;
  totals computed on full precision so sums match exactly. Footnote lists converted amounts and rates.
- Export report as Excel / PDF (share sheet).

## 14. Recurring transactions
- On Add transaction: "Repeat" option → frequency (monthly default; weekly / yearly also), day of month,
  duration = number of months (or "no end date"), category › sub-category, account, amount, note.
- Recurring screen lists all rules with amount, category › sub-category, account, schedule, progress
  (e.g. 6 of 12 posted), next date; actions Edit / Pause / Stop. Filter Active / Paused / Completed.
- Each occurrence is auto-posted on its date as a normal transaction (editable/deletable individually);
  a reminder notification is shown when it posts. Missed occurrences (app not opened) are posted on next launch.
- Monthly totals of recurring expense/income shown at top for budgeting.

## 15. Backup & restore
- Manual: "Back up now" and "Restore" (pick a file from phone or Google Drive).
- Automatic: on/off, frequency daily / weekly / monthly, time of day; runs in background; if Drive is
  chosen and no internet, saves on phone and uploads when online.
- Destinations (either or both): this phone (Documents/KhaataBook/Backups, keeps last 10) and
  Google Drive (user signs into Google once; app-private folder). Drive is the only other place the app
  touches the internet besides rate sync.
- Formats: Excel (.xlsx) — one sheet each for Transactions, Accounts, Categories, Currencies, Loans,
  Recurring, Cards: readable/editable and importable into the masters; and Khaata file (.kbk) — complete
  encrypted database snapshot for exact full restore (password-protected with the user's login password).
- Restore from .kbk = full replace (with confirmation). Restore from Excel = import into masters/transactions
  (adds/updates, shows summary).

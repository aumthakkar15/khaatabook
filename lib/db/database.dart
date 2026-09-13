import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Single SQLite database; everything lives on the phone.
class AppDb {
  AppDb._();
  static final AppDb instance = AppDb._();
  Database? _db;

  static const int version = 1;

  Future<Database> get db async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dir, 'khaata_book.db'),
      version: version,
      onConfigure: (d) => d.execute('PRAGMA foreign_keys = ON'),
      onCreate: _create,
    );
    return _db!;
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  Future<String> path() async => p.join(await getDatabasesPath(), 'khaata_book.db');

  Future<void> _create(Database d, int v) async {
    await d.execute('''
      CREATE TABLE users(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        login_id TEXT NOT NULL UNIQUE COLLATE NOCASE,
        password_hash TEXT NOT NULL,
        salt TEXT NOT NULL,
        country TEXT NOT NULL,
        base_currency TEXT NOT NULL,
        biometric INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      )''');
    await d.execute('''
      CREATE TABLE currencies(
        code TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        symbol TEXT NOT NULL,
        country TEXT NOT NULL,
        rate REAL NOT NULL DEFAULT 0,
        manual INTEGER NOT NULL DEFAULT 0,
        in_use INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT
      )''');
    await d.execute('''
      CREATE TABLE categories(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        name TEXT NOT NULL,
        icon TEXT NOT NULL DEFAULT 'tag',
        parent_id INTEGER REFERENCES categories(id) ON DELETE CASCADE,
        sort INTEGER NOT NULL DEFAULT 0,
        archived INTEGER NOT NULL DEFAULT 0
      )''');
    await d.execute('CREATE INDEX idx_cat_parent ON categories(parent_id)');
    await d.execute('''
      CREATE TABLE accounts(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        currency TEXT NOT NULL,
        opening_balance REAL NOT NULL DEFAULT 0,
        last4 TEXT,
        note TEXT,
        credit_limit REAL NOT NULL DEFAULT 0,
        bill_day INTEGER NOT NULL DEFAULT 1,
        due_day INTEGER NOT NULL DEFAULT 20,
        archived INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      )''');
    await d.execute('''
      CREATE TABLE transactions(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        date TEXT NOT NULL,
        amount REAL NOT NULL,
        currency TEXT NOT NULL,
        rate_to_base REAL NOT NULL DEFAULT 1,
        base_amount REAL NOT NULL DEFAULT 0,
        account_amount REAL NOT NULL DEFAULT 0,
        to_amount REAL NOT NULL DEFAULT 0,
        account_id INTEGER NOT NULL REFERENCES accounts(id),
        to_account_id INTEGER REFERENCES accounts(id),
        category_id INTEGER REFERENCES categories(id) ON DELETE SET NULL,
        subcategory_id INTEGER REFERENCES categories(id) ON DELETE SET NULL,
        note TEXT,
        source TEXT NOT NULL DEFAULT 'manual',
        ref_id INTEGER,
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      )''');
    await d.execute('CREATE INDEX idx_tx_date ON transactions(date)');
    await d.execute('CREATE INDEX idx_tx_account ON transactions(account_id)');
    await d.execute('CREATE INDEX idx_tx_to_account ON transactions(to_account_id)');
    await d.execute('CREATE INDEX idx_tx_cat ON transactions(category_id, subcategory_id)');
    await d.execute('''
      CREATE TABLE loans(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        lender TEXT,
        principal REAL NOT NULL,
        rate_pct REAL NOT NULL,
        months INTEGER NOT NULL,
        start_date TEXT NOT NULL,
        emi_day INTEGER NOT NULL,
        emi REAL NOT NULL,
        account_id INTEGER NOT NULL REFERENCES accounts(id),
        status TEXT NOT NULL DEFAULT 'active'
      )''');
    await d.execute('''
      CREATE TABLE loan_emis(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        loan_id INTEGER NOT NULL REFERENCES loans(id) ON DELETE CASCADE,
        no INTEGER NOT NULL,
        due_date TEXT NOT NULL,
        principal REAL NOT NULL,
        interest REAL NOT NULL,
        amount REAL NOT NULL,
        balance_after REAL NOT NULL,
        paid INTEGER NOT NULL DEFAULT 0,
        paid_date TEXT,
        transaction_id INTEGER
      )''');
    await d.execute('''
      CREATE TABLE card_cycles(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
        cycle_start TEXT NOT NULL,
        cycle_end TEXT NOT NULL,
        due_date TEXT NOT NULL,
        amount_due REAL NOT NULL,
        paid_amount REAL NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'due',
        UNIQUE(account_id, cycle_end)
      )''');
    await d.execute('''
      CREATE TABLE recurring(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        name TEXT NOT NULL,
        amount REAL NOT NULL,
        currency TEXT NOT NULL,
        account_id INTEGER NOT NULL REFERENCES accounts(id),
        to_account_id INTEGER REFERENCES accounts(id),
        category_id INTEGER REFERENCES categories(id) ON DELETE SET NULL,
        subcategory_id INTEGER REFERENCES categories(id) ON DELETE SET NULL,
        frequency TEXT NOT NULL DEFAULT 'monthly',
        day INTEGER NOT NULL DEFAULT 1,
        start_date TEXT NOT NULL,
        total_count INTEGER,
        posted_count INTEGER NOT NULL DEFAULT 0,
        next_date TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'active',
        note TEXT
      )''');
    await d.execute('''
      CREATE TABLE settings(
        key TEXT PRIMARY KEY,
        value TEXT
      )''');
  }

  // ---- settings helpers ----
  Future<String?> getSetting(String key) async {
    final rows = await (await db).query('settings', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> setSetting(String key, String? value) async {
    await (await db).insert('settings', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Wipes every table (used by full restore).
  Future<void> clearAll(Transaction t) async {
    for (final table in [
      'transactions', 'loan_emis', 'loans', 'card_cycles', 'recurring',
      'accounts', 'categories', 'currencies', 'users', 'settings',
    ]) {
      await t.delete(table);
    }
  }
}

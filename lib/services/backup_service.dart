import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../db/database.dart';
import '../models/models.dart';
import '../utils/money.dart';
import 'account_service.dart';
import 'category_service.dart';
import 'currency_service.dart';
import 'excel_io.dart';
import 'loan_service.dart';
import 'recurring_service.dart';
import 'session.dart';
import 'transaction_service.dart';

class BackupException implements Exception {
  final String message;
  BackupException(this.message);
  @override
  String toString() => message;
}

class BackupResult {
  final File excel;
  final File kbk;
  BackupResult(this.excel, this.kbk);
}

/// Feature 15: manual + automatic backups to the phone (and to Google
/// Drive / any folder through the system file picker), in Excel and in
/// the app's own encrypted .kbk format for exact restore.
class BackupService {
  BackupService._();
  static final BackupService instance = BackupService._();

  static const tables = ['users', 'currencies', 'categories', 'accounts', 'transactions', 'loans', 'loan_emis', 'card_cycles', 'recurring', 'settings'];

  Future<Directory> folder() async {
    final dir = await getApplicationDocumentsDirectory();
    final f = Directory('${dir.path}/KhaataBook/Backups');
    if (!await f.exists()) await f.create(recursive: true);
    return f;
  }

  Future<List<File>> existing() async {
    final f = await folder();
    final files = f.listSync().whereType<File>().toList()
      ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return files;
  }

  String _stamp() {
    final n = DateTime.now();
    String p(int v) => v.toString().padLeft(2, '0');
    return '${n.year}${p(n.month)}${p(n.day)}_${p(n.hour)}${p(n.minute)}';
  }

  // ---------- Excel ----------
  Future<Excel> buildExcel() async {
    final txSheets = await TransactionService.instance.exportSheets();
    final d = await AppDb.instance.db;
    final currencies = await CurrencyService.instance.all();
    final loans = await LoanService.instance.all();
    final recurring = await RecurringService.instance.all();
    final accounts = await AccountService.instance.map();
    final cats = await CategoryService.instance.map();
    final cycles = await d.query('card_cycles', orderBy: 'account_id, cycle_end');
    return ExcelIO.build({
      'Transactions': txSheets['Transactions']!,
      'Transfers': txSheets['Transfers']!,
      'Accounts': await AccountService.instance.exportRows(),
      'Categories': await CategoryService.instance.exportRows(),
      'Currencies': [
        ['Code', 'Name', 'Symbol', 'Country', 'Rate (1 ${Session.instance.base} =)', 'Manual', 'In use'],
        for (final c in currencies) [c.code, c.name, c.symbol, c.country, c.rate, c.manual ? 'Yes' : 'No', c.inUse ? 'Yes' : 'No'],
      ],
      'Loans': [
        ['Name', 'Lender', 'Loan amount', 'Interest % p.a.', 'Months', 'Start date', 'EMI day', 'EMI', 'Deduct from', 'Status', 'EMIs paid', 'Remaining'],
        for (final s in loans)
          [s.loan.name, s.loan.lender, s.loan.principal, s.loan.ratePct, s.loan.months, Dates.key(s.loan.startDate), s.loan.emiDay, s.loan.emi, s.account?.name ?? '', s.loan.status, s.paidCount, s.remaining],
      ],
      'Loan EMIs': [
        ['Loan', 'No', 'Due date', 'Principal', 'Interest', 'Amount', 'Balance after', 'Paid', 'Paid date'],
        for (final s in loans)
          for (final e in s.emis)
            [s.loan.name, e.no, Dates.key(e.dueDate), e.principal, e.interest, e.amount, e.balanceAfter, e.paid ? 'Yes' : 'No', e.paidDate == null ? '' : Dates.key(e.paidDate!)],
      ],
      'Card cycles': [
        ['Card', 'Cycle start', 'Bill date', 'Due date', 'Amount due', 'Paid', 'Status'],
        for (final r in cycles)
          [accounts[r['account_id'] as int]?.name ?? '', r['cycle_start'], r['cycle_end'], r['due_date'], r['amount_due'], r['paid_amount'], r['status']],
      ],
      'Recurring': [
        ['Name', 'Type', 'Amount', 'Currency', 'Account', 'To account', 'Category', 'Sub-category', 'Frequency', 'Day', 'Start', 'Total count', 'Posted', 'Next date', 'Status', 'Note'],
        for (final r in recurring)
          [r.name, r.type.name, r.amount, r.currency, accounts[r.accountId]?.name ?? '', accounts[r.toAccountId ?? -1]?.name ?? '', cats[r.categoryId ?? -1]?.name ?? '', cats[r.subcategoryId ?? -1]?.name ?? '', r.frequency, r.day, Dates.key(r.startDate), r.totalCount ?? '', r.postedCount, Dates.key(r.nextDate), r.status, r.note ?? ''],
      ],
    });
  }

  // ---------- .kbk (encrypted full snapshot) ----------
  enc.Key _key(String password, String salt) {
    List<int> bytes = utf8.encode('$salt|$password');
    for (var i = 0; i < 5000; i++) {
      bytes = sha256.convert(bytes).bytes;
    }
    return enc.Key(Uint8List.fromList(bytes.sublist(0, 32)));
  }

  Future<Map<String, dynamic>> _snapshot() async {
    final d = await AppDb.instance.db;
    final out = <String, dynamic>{'app': 'khaata_book', 'version': AppDb.version, 'created': DateTime.now().toIso8601String()};
    for (final t in tables) {
      out[t] = await d.query(t);
    }
    return out;
  }

  String encodeKbk(Map<String, dynamic> snapshot, String password) {
    final rnd = Random.secure();
    final salt = base64.encode(List<int>.generate(16, (_) => rnd.nextInt(256)));
    final iv = enc.IV.fromSecureRandom(16);
    final e = enc.Encrypter(enc.AES(_key(password, salt), mode: enc.AESMode.cbc));
    final cipher = e.encrypt(jsonEncode(snapshot), iv: iv);
    return jsonEncode({'format': 'kbk1', 'salt': salt, 'iv': iv.base64, 'data': cipher.base64});
  }

  Map<String, dynamic> decodeKbk(String content, String password) {
    Map<String, dynamic> wrapper;
    try {
      wrapper = jsonDecode(content) as Map<String, dynamic>;
    } catch (_) {
      throw BackupException('This is not a Khaata backup file');
    }
    if (wrapper['format'] != 'kbk1') throw BackupException('Unsupported backup format');
    try {
      final e = enc.Encrypter(enc.AES(_key(password, wrapper['salt'] as String), mode: enc.AESMode.cbc));
      final plain = e.decrypt64(wrapper['data'] as String, iv: enc.IV.fromBase64(wrapper['iv'] as String));
      final m = jsonDecode(plain) as Map<String, dynamic>;
      if (m['app'] != 'khaata_book') throw BackupException('Not a Khaata backup');
      return m;
    } on BackupException {
      rethrow;
    } catch (_) {
      throw BackupException('Wrong password for this backup file');
    }
  }

  /// Writes both files into the phone backup folder.
  Future<BackupResult> backupNow({required String password, bool auto = false}) async {
    final dir = await folder();
    final stamp = _stamp();
    final x = await buildExcel();
    final excelFile = File('${dir.path}/KhaataBook_$stamp.xlsx');
    await excelFile.writeAsBytes(x.encode()!, flush: true);
    final kbkFile = File('${dir.path}/KhaataBook_$stamp.kbk');
    await kbkFile.writeAsString(encodeKbk(await _snapshot(), password), flush: true);
    await AppDb.instance.setSetting('last_backup_at', DateTime.now().toIso8601String());
    await AppDb.instance.setSetting('last_backup_auto', auto ? '1' : '0');
    await _prune(dir);
    DataBus.instance.changed();
    return BackupResult(excelFile, kbkFile);
  }

  Future<void> _prune(Directory dir) async {
    final keep = int.tryParse(await AppDb.instance.getSetting('backup_keep') ?? '10') ?? 10;
    for (final ext in ['.xlsx', '.kbk']) {
      final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith(ext)).toList()
        ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      for (var i = keep; i < files.length; i++) {
        try {
          await files[i].delete();
        } catch (_) {}
      }
    }
  }

  // ---------- Automatic ----------
  Future<bool> autoEnabled() async => (await AppDb.instance.getSetting('backup_auto') ?? '0') == '1';
  Future<String> frequency() async => await AppDb.instance.getSetting('backup_freq') ?? 'daily';
  Future<int> hour() async => int.tryParse(await AppDb.instance.getSetting('backup_hour') ?? '2') ?? 2;
  Future<DateTime?> lastBackup() async {
    final s = await AppDb.instance.getSetting('last_backup_at');
    return s == null ? null : DateTime.tryParse(s);
  }

  /// One backup password protects every .kbk file (manual and automatic).
  /// It is kept in the app's private storage so automatic backups can run
  /// without prompting; the user types it when restoring on another phone.
  Future<String?> backupPassword() => AppDb.instance.getSetting('backup_password');
  Future<void> setBackupPassword(String p) => AppDb.instance.setSetting('backup_password', p);

  /// Called on app start/resume: runs a backup if one is due.
  Future<bool> runAutoIfDue() async {
    if (!await autoEnabled()) return false;
    final last = await lastBackup();
    final freq = await frequency();
    final h = await hour();
    final now = DateTime.now();
    final todayAt = DateTime(now.year, now.month, now.day, h);
    if (now.isBefore(todayAt)) return false;
    if (last != null) {
      final gap = switch (freq) {
        'weekly' => const Duration(days: 7),
        'monthly' => const Duration(days: 30),
        _ => const Duration(days: 1),
      };
      if (now.difference(last) < gap) return false;
    }
    final pw = await backupPassword();
    if (pw == null || pw.isEmpty) return false;
    await backupNow(password: pw, auto: true);
    return true;
  }

  // ---------- Restore ----------
  /// Picks a .kbk or .xlsx file. Returns (file bytes as string or excel).
  Future<PlatformFile?> pickBackupFile() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
    if (res == null || res.files.isEmpty) return null;
    return res.files.first;
  }

  Future<void> restoreKbk(String content, String password) async {
    var snap = _tryDecode(content, password);
    final stored = await backupPassword();
    if (snap == null && stored != null) snap = _tryDecode(content, stored);
    if (snap == null) throw BackupException('Wrong password for this backup file');
    final d = await AppDb.instance.db;
    await d.transaction((t) async {
      await AppDb.instance.clearAll(t);
      for (final table in tables) {
        final rows = (snap![table] as List?) ?? [];
        for (final r in rows) {
          await t.insert(table, Map<String, Object?>.from(r as Map));
        }
      }
    });
    // Refresh the session user from the restored data.
    final users = await d.query('users', limit: 1);
    if (users.isNotEmpty) Session.instance.update(User.fromMap(users.first));
    DataBus.instance.changed();
  }

  Map<String, dynamic>? _tryDecode(String content, String password) {
    try {
      return decodeKbk(content, password);
    } catch (_) {
      return null;
    }
  }

  /// Excel restore = import masters and transactions (adds, never wipes).
  Future<String> restoreExcel(Excel x) async {
    final parts = <String>[];
    if (x.tables.containsKey('Accounts')) {
      final s = await AccountService.instance.importExcel(_only(x, 'Accounts'));
      parts.add('Accounts: $s');
    }
    if (x.tables.containsKey('Categories')) {
      final s = await CategoryService.instance.importExcel(_only(x, 'Categories'));
      parts.add('Categories: $s');
    }
    if (x.tables.containsKey('Transactions') || x.tables.containsKey('Transfers')) {
      final s = await TransactionService.instance.importExcel(x);
      parts.add('Transactions: $s');
    }
    if (parts.isEmpty) throw BackupException('No recognised sheets (Accounts / Categories / Transactions / Transfers)');
    DataBus.instance.changed();
    return parts.join('\n');
  }

  Excel _only(Excel x, String sheet) {
    final y = Excel.createExcel();
    final def = y.getDefaultSheet();
    if (def != null) y.rename(def, sheet);
    final src = x.tables[sheet]!;
    for (final row in src.rows) {
      y[sheet].appendRow(row.map((c) => c?.value).toList());
    }
    return y;
  }
}

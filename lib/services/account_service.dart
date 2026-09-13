import 'dart:io';

import 'package:excel/excel.dart';

import '../db/database.dart';
import '../models/models.dart';
import 'category_service.dart';
import 'currency_service.dart';
import 'excel_io.dart';
import 'session.dart';

class AccountException implements Exception {
  final String message;
  AccountException(this.message);
  @override
  String toString() => message;
}

class NetWorth {
  final double cashBank; // base currency
  final double cardDue; // positive number
  final double loans; // positive number
  const NetWorth({required this.cashBank, required this.cardDue, required this.loans});
  double get total => cashBank - cardDue - loans;
  double get liabilities => cardDue + loans;
}

/// Feature 5, 10, 11: cash / bank / credit-card accounts, balances,
/// archive, Excel import and the consolidated balance.
class AccountService {
  AccountService._();
  static final AccountService instance = AccountService._();

  /// Balance formula (account currency):
  ///   opening + income + transfers-in − expense − transfers-out.
  static const _balanceSql = '''
    a.opening_balance
    + IFNULL((SELECT SUM(CASE
          WHEN t.type = 'income' AND t.account_id = a.id THEN t.account_amount
          WHEN t.type = 'expense' AND t.account_id = a.id THEN -t.account_amount
          WHEN t.type = 'transfer' AND t.account_id = a.id THEN -t.account_amount
          ELSE 0 END) FROM transactions t WHERE t.account_id = a.id), 0)
    + IFNULL((SELECT SUM(t.to_amount) FROM transactions t WHERE t.type = 'transfer' AND t.to_account_id = a.id), 0)
  ''';

  Future<List<Account>> all({bool includeArchived = false, AccountType? type}) async {
    final d = await AppDb.instance.db;
    final where = <String>[];
    final args = <Object?>[];
    if (!includeArchived) where.add('a.archived = 0');
    if (type != null) {
      where.add('a.type = ?');
      args.add(type.name);
    }
    final rows = await d.rawQuery('''
      SELECT a.*, ($_balanceSql) AS balance FROM accounts a
      ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
      ORDER BY a.archived, CASE a.type WHEN 'cash' THEN 0 WHEN 'bank' THEN 1 ELSE 2 END, a.name''', args);
    return rows.map(Account.fromMap).toList();
  }

  Future<Account?> get(int id) async {
    final d = await AppDb.instance.db;
    final rows = await d.rawQuery('SELECT a.*, ($_balanceSql) AS balance FROM accounts a WHERE a.id = ?', [id]);
    return rows.isEmpty ? null : Account.fromMap(rows.first);
  }

  Future<Map<int, Account>> map({bool includeArchived = true}) async {
    final list = await all(includeArchived: includeArchived);
    return {for (final a in list) a.id!: a};
  }

  Future<int> add(Account a) async {
    _validate(a);
    final d = await AppDb.instance.db;
    final id = await d.insert('accounts', a.toMap()..remove('id'));
    await CurrencyService.instance.markInUse(a.currency);
    DataBus.instance.changed();
    return id;
  }

  Future<void> update(Account a) async {
    _validate(a);
    final d = await AppDb.instance.db;
    await d.update('accounts', a.toMap()..remove('id'), where: 'id = ?', whereArgs: [a.id]);
    await CurrencyService.instance.markInUse(a.currency);
    DataBus.instance.changed();
  }

  void _validate(Account a) {
    if (a.name.trim().isEmpty) throw AccountException('Account name is required');
    if (a.isCard && a.creditLimit <= 0) throw AccountException('Enter the card\'s credit limit');
    if (a.isCard && (a.billDay < 1 || a.billDay > 28 || a.dueDay < 1 || a.dueDay > 28)) {
      throw AccountException('Bill and due days must be between 1 and 28');
    }
  }

  Future<void> setArchived(int id, bool archived) async {
    final d = await AppDb.instance.db;
    await d.update('accounts', {'archived': archived ? 1 : 0}, where: 'id = ?', whereArgs: [id]);
    DataBus.instance.changed();
  }

  /// Delete only when there are no transactions/loans referencing it.
  Future<bool> delete(int id) async {
    final d = await AppDb.instance.db;
    final c1 = await d.rawQuery('SELECT COUNT(*) c FROM transactions WHERE account_id = ? OR to_account_id = ?', [id, id]);
    final c2 = await d.rawQuery('SELECT COUNT(*) c FROM loans WHERE account_id = ?', [id]);
    final c3 = await d.rawQuery('SELECT COUNT(*) c FROM recurring WHERE account_id = ? OR to_account_id = ?', [id, id]);
    if ((c1.first['c'] as int) + (c2.first['c'] as int) + (c3.first['c'] as int) > 0) return false;
    await d.delete('accounts', where: 'id = ?', whereArgs: [id]);
    DataBus.instance.changed();
    return true;
  }

  /// Feature 11: consolidated balance in base currency.
  Future<NetWorth> netWorth() async {
    final accounts = await all();
    final cs = CurrencyService.instance;
    double cashBank = 0, cardDue = 0;
    for (final a in accounts) {
      double v;
      try {
        v = await cs.toBase(a.balance, a.currency);
      } catch (_) {
        v = 0; // no rate yet: excluded until synced
      }
      if (a.isCard) {
        if (v < 0) cardDue += -v;
        else cashBank += v; // credit balance on a card counts as money
      } else {
        cashBank += v;
      }
    }
    final d = await AppDb.instance.db;
    final rows = await d.rawQuery('''
      SELECT l.principal - IFNULL((SELECT SUM(e.principal) FROM loan_emis e WHERE e.loan_id = l.id AND e.paid = 1), 0) AS remaining,
             a.currency AS currency
      FROM loans l JOIN accounts a ON a.id = l.account_id WHERE l.status = 'active' ''');
    double loans = 0;
    for (final r in rows) {
      final rem = (r['remaining'] as num).toDouble();
      try {
        loans += await cs.toBase(rem, r['currency'] as String);
      } catch (_) {}
    }
    return NetWorth(cashBank: cashBank, cardDue: cardDue, loans: loans);
  }

  // ---------- Excel ----------
  static const importHeader = [
    'Name', 'Type (Cash/Bank/Card)', 'Currency', 'Opening balance', 'Last 4 digits', 'Credit limit', 'Bill day', 'Due day', 'Note'
  ];

  Future<File> template() async {
    final base = Session.instance.base;
    final x = ExcelIO.build({
      'Accounts': [
        importHeader,
        ['Wallet', 'Cash', base, 500, '', '', '', '', ''],
        ['Emirates NBD Salary', 'Bank', base, 12000, '4821', '', '', '', 'Salary account'],
        ['ADCB Visa', 'Card', base, 0, '7710', 10000, 5, 25, ''],
      ]
    });
    return ExcelIO.save(x, 'khaata_accounts_template.xlsx', subDir: 'templates');
  }

  Future<ImportSummary> importExcel(Excel x) async {
    final s = ImportSummary();
    final rows = ExcelIO.rows(x);
    final currencies = await CurrencyService.instance.map();
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      final name = ExcelIO.at(r, 0);
      if (name.isEmpty) {
        s.skipped++;
        continue;
      }
      final t = ExcelIO.at(r, 1).toLowerCase();
      final type = t.startsWith('ca') && !t.startsWith('car')
          ? AccountType.cash
          : t.startsWith('b')
              ? AccountType.bank
              : (t.startsWith('c') ? AccountType.card : null);
      if (type == null) {
        s.errors.add('Row ${i + 2}: type must be Cash, Bank or Card');
        continue;
      }
      var cur = ExcelIO.at(r, 2).toUpperCase();
      if (cur.isEmpty) cur = Session.instance.base;
      if (!currencies.containsKey(cur)) {
        s.errors.add('Row ${i + 2}: unknown currency $cur');
        continue;
      }
      final a = Account(
        name: name,
        type: type,
        currency: cur,
        openingBalance: double.tryParse(ExcelIO.at(r, 3).replaceAll(',', '')) ?? 0,
        last4: ExcelIO.at(r, 4).isEmpty ? null : ExcelIO.at(r, 4),
        creditLimit: double.tryParse(ExcelIO.at(r, 5).replaceAll(',', '')) ?? 0,
        billDay: int.tryParse(ExcelIO.at(r, 6)) ?? 1,
        dueDay: int.tryParse(ExcelIO.at(r, 7)) ?? 20,
        note: ExcelIO.at(r, 8).isEmpty ? null : ExcelIO.at(r, 8),
      );
      final d = await AppDb.instance.db;
      final dup = await d.query('accounts', where: 'name = ? COLLATE NOCASE', whereArgs: [name]);
      if (dup.isNotEmpty) {
        s.skipped++;
        continue;
      }
      try {
        await add(a);
        s.added++;
      } catch (e) {
        s.errors.add('Row ${i + 2}: $e');
      }
    }
    return s;
  }

  Future<List<List<Object?>>> exportRows() async {
    final list = await all(includeArchived: true);
    return [
      [...importHeader, 'Archived', 'Current balance'],
      for (final a in list)
        [
          a.name,
          a.type == AccountType.cash ? 'Cash' : (a.type == AccountType.bank ? 'Bank' : 'Card'),
          a.currency,
          a.openingBalance,
          a.last4 ?? '',
          a.isCard ? a.creditLimit : '',
          a.isCard ? a.billDay : '',
          a.isCard ? a.dueDay : '',
          a.note ?? '',
          a.archived ? 'Yes' : 'No',
          a.balance,
        ]
    ];
  }
}

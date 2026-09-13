import 'dart:io';

import 'package:excel/excel.dart';

import '../db/database.dart';
import '../models/models.dart';
import '../utils/money.dart';
import 'account_service.dart';
import 'category_service.dart';
import 'currency_service.dart';
import 'excel_io.dart';
import 'session.dart';

class TxException implements Exception {
  final String message;
  TxException(this.message);
  @override
  String toString() => message;
}

class TxFilter {
  DateTime? from;
  DateTime? to;
  TxType? type;
  int? accountId;
  int? categoryId;
  int? subcategoryId;
  String? currency;
  String? search;
  TxFilter({this.from, this.to, this.type, this.accountId, this.categoryId, this.subcategoryId, this.currency, this.search});
}

/// Features 9, 12: expense / income / transfer entry with exact
/// multi-currency conversion and account balance effects.
class TransactionService {
  TransactionService._();
  static final TransactionService instance = TransactionService._();

  /// Builds a fully converted transaction. [amount] is in [currency];
  /// the account effect is converted to the account's currency, and the
  /// base amount to the user's base currency, using master rates.
  Future<Tx> build({
    int? id,
    required TxType type,
    required DateTime date,
    required double amount,
    required String currency,
    required Account account,
    Account? toAccount,
    double? toAmountOverride,
    int? categoryId,
    int? subcategoryId,
    String? note,
    String source = 'manual',
    int? refId,
  }) async {
    if (amount <= 0) throw TxException('Amount must be greater than zero');
    if (type == TxType.transfer) {
      if (toAccount == null) throw TxException('Choose the destination account');
      if (toAccount.id == account.id) throw TxException('From and To accounts must be different');
    }
    final cs = CurrencyService.instance;
    final rate = await cs.rateOf(currency);
    final base = Session.instance.base;
    final baseAmount = amount / rate; // 1 base = rate units of currency
    final accountAmount = currency == account.currency ? amount : await cs.convert(amount, currency, account.currency);
    double toAmount = 0;
    if (type == TxType.transfer) {
      toAmount = toAmountOverride ??
          (currency == toAccount!.currency ? amount : await cs.convert(amount, currency, toAccount.currency));
    }
    if (currency != base) await cs.markInUse(currency);
    return Tx(
      id: id,
      type: type,
      date: DateTime(date.year, date.month, date.day),
      amount: Money.round2(amount),
      currency: currency,
      rateToBase: rate,
      baseAmount: Money.round2(baseAmount),
      accountAmount: Money.round2(accountAmount),
      toAmount: Money.round2(toAmount),
      accountId: account.id!,
      toAccountId: toAccount?.id,
      categoryId: type == TxType.transfer ? null : categoryId,
      subcategoryId: type == TxType.transfer ? null : subcategoryId,
      note: (note ?? '').trim().isEmpty ? null : note!.trim(),
      source: source,
      refId: refId,
    );
  }

  Future<int> insert(Tx t) async {
    final d = await AppDb.instance.db;
    final id = await d.insert('transactions', t.toMap()..remove('id'));
    DataBus.instance.changed();
    return id;
  }

  Future<void> update(Tx t) async {
    final d = await AppDb.instance.db;
    await d.update('transactions', t.toMap()..remove('id'), where: 'id = ?', whereArgs: [t.id]);
    DataBus.instance.changed();
  }

  Future<void> delete(int id) async {
    final d = await AppDb.instance.db;
    await d.transaction((x) async {
      // If this was a loan EMI posting, re-open the EMI.
      await x.update('loan_emis', {'paid': 0, 'paid_date': null, 'transaction_id': null},
          where: 'transaction_id = ?', whereArgs: [id]);
      await x.delete('transactions', where: 'id = ?', whereArgs: [id]);
    });
    DataBus.instance.changed();
  }

  Future<Tx?> get(int id) async {
    final d = await AppDb.instance.db;
    final rows = await d.query('transactions', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Tx.fromMap(rows.first);
  }

  Future<List<Tx>> list(TxFilter f, {int? limit}) async {
    final d = await AppDb.instance.db;
    final where = <String>[];
    final args = <Object?>[];
    if (f.from != null) {
      where.add('date >= ?');
      args.add(Dates.key(f.from!));
    }
    if (f.to != null) {
      where.add('date <= ?');
      args.add(Dates.key(f.to!));
    }
    if (f.type != null) {
      where.add('type = ?');
      args.add(f.type!.name);
    }
    if (f.accountId != null) {
      where.add('(account_id = ? OR to_account_id = ?)');
      args.addAll([f.accountId, f.accountId]);
    }
    if (f.categoryId != null) {
      where.add('category_id = ?');
      args.add(f.categoryId);
    }
    if (f.subcategoryId != null) {
      where.add('subcategory_id = ?');
      args.add(f.subcategoryId);
    }
    if (f.currency != null) {
      where.add('currency = ?');
      args.add(f.currency);
    }
    if (f.search != null && f.search!.trim().isNotEmpty) {
      where.add('note LIKE ?');
      args.add('%${f.search!.trim()}%');
    }
    final rows = await d.query('transactions',
        where: where.isEmpty ? null : where.join(' AND '),
        whereArgs: args,
        orderBy: 'date DESC, id DESC',
        limit: limit);
    return rows.map(Tx.fromMap).toList();
  }

  /// Income / expense totals in base currency for a period.
  Future<({double income, double expense})> totals(DateTime from, DateTime to) async {
    final d = await AppDb.instance.db;
    final rows = await d.rawQuery('''
      SELECT type, SUM(base_amount) s FROM transactions
      WHERE date >= ? AND date <= ? AND type IN ('income','expense') GROUP BY type''',
        [Dates.key(from), Dates.key(to)]);
    double inc = 0, exp = 0;
    for (final r in rows) {
      final v = (r['s'] as num? ?? 0).toDouble();
      if (r['type'] == 'income') inc = v;
      if (r['type'] == 'expense') exp = v;
    }
    return (income: inc, expense: exp);
  }

  // ---------- Excel: transactions ----------
  static const txHeader = [
    'Date (YYYY-MM-DD)', 'Type (Expense/Income)', 'Amount', 'Currency', 'Account', 'Category', 'Sub-category', 'Note'
  ];
  static const transferHeader = ['Date (YYYY-MM-DD)', 'From account', 'To account', 'Amount', 'Currency', 'Note'];

  Future<File> transactionsTemplate() async {
    final base = Session.instance.base;
    final x = ExcelIO.build({
      'Transactions': [
        txHeader,
        ['2026-09-01', 'Income', 18200, base, 'Emirates NBD Salary', 'Salary', 'Monthly pay', 'September'],
        ['2026-09-03', 'Expense', 245, base, 'Wallet', 'Food & Dining', 'Groceries', 'Carrefour'],
      ],
      'Transfers': [
        transferHeader,
        ['2026-09-05', 'Emirates NBD Salary', 'Wallet', 2000, base, 'Cash withdrawal'],
      ],
    });
    return ExcelIO.save(x, 'khaata_transactions_template.xlsx', subDir: 'templates');
  }

  Future<ImportSummary> importExcel(Excel x) async {
    final s = ImportSummary();
    final accounts = await AccountService.instance.all(includeArchived: true);
    Account? findAccount(String name) {
      final n = name.trim().toLowerCase();
      for (final a in accounts) {
        if (a.name.toLowerCase() == n) return a;
      }
      return null;
    }

    final cats = await CategoryService.instance.map();
    Future<(int?, int?)> resolveCat(TxType type, String cat, String sub) async {
      if (cat.trim().isEmpty) return (null, null);
      Category? c;
      for (final v in cats.values) {
        if (v.parentId == null && v.type == type && v.name.toLowerCase() == cat.trim().toLowerCase()) c = v;
      }
      int cid;
      if (c == null) {
        cid = await CategoryService.instance.add(Category(type: type, name: cat.trim()));
        cats[cid] = Category(id: cid, type: type, name: cat.trim());
      } else {
        cid = c.id!;
      }
      if (sub.trim().isEmpty) return (cid, null);
      Category? sc;
      for (final v in cats.values) {
        if (v.parentId == cid && v.name.toLowerCase() == sub.trim().toLowerCase()) sc = v;
      }
      int sid;
      if (sc == null) {
        sid = await CategoryService.instance.add(Category(type: type, name: sub.trim(), icon: 'dot', parentId: cid));
        cats[sid] = Category(id: sid, type: type, name: sub.trim(), parentId: cid);
      } else {
        sid = sc.id!;
      }
      return (cid, sid);
    }

    // Sheet 1: Transactions (or first sheet)
    if (x.tables.containsKey('Transactions') || x.tables.isNotEmpty) {
      final rows = ExcelIO.rows(x, sheet: 'Transactions');
      for (var i = 0; i < rows.length; i++) {
        final r = rows[i];
        try {
          final date = DateTime.parse(ExcelIO.at(r, 0));
          final ts = ExcelIO.at(r, 1).toLowerCase();
          final type = ts.startsWith('i') ? TxType.income : TxType.expense;
          final amount = Money.parse(ExcelIO.at(r, 2));
          var cur = ExcelIO.at(r, 3).toUpperCase();
          final acc = findAccount(ExcelIO.at(r, 4));
          if (acc == null) throw TxException('account "${ExcelIO.at(r, 4)}" not found');
          if (cur.isEmpty) cur = acc.currency;
          final (cid, sid) = await resolveCat(type, ExcelIO.at(r, 5), ExcelIO.at(r, 6));
          final t = await build(
            type: type,
            date: date,
            amount: amount,
            currency: cur,
            account: acc,
            categoryId: cid,
            subcategoryId: sid,
            note: ExcelIO.at(r, 7),
            source: 'import',
          );
          await insert(t);
          s.added++;
        } catch (e) {
          s.errors.add('Transactions row ${i + 2}: $e');
        }
      }
    }
    // Sheet 2: Transfers
    if (x.tables.containsKey('Transfers')) {
      final rows = ExcelIO.rows(x, sheet: 'Transfers');
      for (var i = 0; i < rows.length; i++) {
        final r = rows[i];
        try {
          final date = DateTime.parse(ExcelIO.at(r, 0));
          final from = findAccount(ExcelIO.at(r, 1));
          final to = findAccount(ExcelIO.at(r, 2));
          if (from == null) throw TxException('from account "${ExcelIO.at(r, 1)}" not found');
          if (to == null) throw TxException('to account "${ExcelIO.at(r, 2)}" not found');
          final amount = Money.parse(ExcelIO.at(r, 3));
          var cur = ExcelIO.at(r, 4).toUpperCase();
          if (cur.isEmpty) cur = from.currency;
          final t = await build(
            type: TxType.transfer,
            date: date,
            amount: amount,
            currency: cur,
            account: from,
            toAccount: to,
            note: ExcelIO.at(r, 5),
            source: 'import',
          );
          await insert(t);
          s.added++;
        } catch (e) {
          s.errors.add('Transfers row ${i + 2}: $e');
        }
      }
    }
    return s;
  }

  Future<Map<String, List<List<Object?>>>> exportSheets() async {
    final accounts = await AccountService.instance.map();
    final cats = await CategoryService.instance.map();
    final all = await list(TxFilter());
    final tx = <List<Object?>>[
      [...txHeader, 'Rate to base', 'Base amount', 'Source']
    ];
    final tr = <List<Object?>>[
      [...transferHeader, 'Received amount', 'Rate to base', 'Base amount']
    ];
    for (final t in all.reversed) {
      if (t.type == TxType.transfer) {
        tr.add([
          Dates.key(t.date),
          accounts[t.accountId]?.name ?? '',
          accounts[t.toAccountId ?? -1]?.name ?? '',
          t.amount,
          t.currency,
          t.note ?? '',
          t.toAmount,
          t.rateToBase,
          t.baseAmount,
        ]);
      } else {
        tx.add([
          Dates.key(t.date),
          t.type == TxType.income ? 'Income' : 'Expense',
          t.amount,
          t.currency,
          accounts[t.accountId]?.name ?? '',
          cats[t.categoryId ?? -1]?.name ?? '',
          cats[t.subcategoryId ?? -1]?.name ?? '',
          t.note ?? '',
          t.rateToBase,
          t.baseAmount,
          t.source,
        ]);
      }
    }
    return {'Transactions': tx, 'Transfers': tr};
  }
}

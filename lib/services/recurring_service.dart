import '../db/database.dart';
import '../models/models.dart';
import '../utils/money.dart';
import 'account_service.dart';
import 'currency_service.dart';
import 'session.dart';
import 'transaction_service.dart';

/// Feature 14: recurring expense / income / transfer rules that post
/// themselves as normal transactions on their dates.
class RecurringService {
  RecurringService._();
  static final RecurringService instance = RecurringService._();

  static DateTime firstDate(String frequency, int day, DateTime start) {
    final s = DateTime(start.year, start.month, start.day);
    switch (frequency) {
      case 'weekly':
        var d = s;
        while (d.weekday != day) {
          d = d.add(const Duration(days: 1));
        }
        return d;
      case 'yearly':
        var d = DateTime(s.year, s.month, day.clamp(1, 28));
        if (d.isBefore(s)) d = DateTime(s.year + 1, s.month, day.clamp(1, 28));
        return d;
      default:
        var d = Dates.onDay(s.year, s.month, day);
        if (d.isBefore(s)) d = Dates.addMonths(d, 1, day: day);
        return d;
    }
  }

  static DateTime nextAfter(Recurring r, DateTime d) {
    switch (r.frequency) {
      case 'weekly':
        return d.add(const Duration(days: 7));
      case 'yearly':
        return DateTime(d.year + 1, d.month, d.day);
      default:
        return Dates.addMonths(d, 1, day: r.day);
    }
  }

  Future<int> create(Recurring r) async {
    if (r.amount <= 0) throw TxException('Amount must be greater than zero');
    final d = await AppDb.instance.db;
    final id = await d.insert('recurring', r.toMap()..remove('id'));
    DataBus.instance.changed();
    await postDue();
    return id;
  }

  Future<void> update(Recurring r) async {
    final d = await AppDb.instance.db;
    await d.update('recurring', r.toMap()..remove('id'), where: 'id = ?', whereArgs: [r.id]);
    DataBus.instance.changed();
  }

  Future<void> setStatus(int id, String status) async {
    final d = await AppDb.instance.db;
    await d.update('recurring', {'status': status}, where: 'id = ?', whereArgs: [id]);
    DataBus.instance.changed();
  }

  Future<void> delete(int id) async {
    final d = await AppDb.instance.db;
    await d.delete('recurring', where: 'id = ?', whereArgs: [id]);
    DataBus.instance.changed();
  }

  Future<List<Recurring>> all({String? status}) async {
    final d = await AppDb.instance.db;
    final rows = await d.query('recurring',
        where: status == null ? null : 'status = ?', whereArgs: status == null ? null : [status], orderBy: 'next_date, name');
    return rows.map(Recurring.fromMap).toList();
  }

  /// Posts every occurrence whose date has arrived (catches up missed ones).
  Future<int> postDue() async {
    final d = await AppDb.instance.db;
    final today = Dates.today();
    final rules = await all(status: 'active');
    final accounts = await AccountService.instance.map();
    var n = 0;
    for (var r in rules) {
      while (!r.nextDate.isAfter(today) && (r.totalCount == null || r.postedCount < r.totalCount!)) {
        final acc = accounts[r.accountId];
        if (acc == null) break;
        final to = r.toAccountId == null ? null : accounts[r.toAccountId!];
        try {
          final t = await TransactionService.instance.build(
            type: r.type,
            date: r.nextDate,
            amount: r.amount,
            currency: r.currency,
            account: acc,
            toAccount: to,
            categoryId: r.categoryId,
            subcategoryId: r.subcategoryId,
            note: r.note ?? r.name,
            source: 'recurring',
            refId: r.id,
          );
          await TransactionService.instance.insert(t);
          n++;
        } catch (_) {
          break; // e.g. missing rate — try again next launch
        }
        r = r.copyWith(postedCount: r.postedCount + 1, nextDate: nextAfter(r, r.nextDate));
        final done = r.totalCount != null && r.postedCount >= r.totalCount!;
        r = r.copyWith(status: done ? 'completed' : 'active');
        await d.update('recurring', r.toMap()..remove('id'), where: 'id = ?', whereArgs: [r.id]);
        if (done) break;
      }
    }
    if (n > 0) DataBus.instance.changed();
    return n;
  }

  /// Monthly-equivalent totals (base currency) for the header tiles.
  Future<({double expense, double income})> monthlyTotals() async {
    final rules = await all(status: 'active');
    double e = 0, i = 0;
    for (final r in rules) {
      double perMonth = r.amount;
      if (r.frequency == 'weekly') perMonth = r.amount * 52 / 12;
      if (r.frequency == 'yearly') perMonth = r.amount / 12;
      double v;
      try {
        v = await _toBase(perMonth, r.currency);
      } catch (_) {
        v = 0;
      }
      if (r.type == TxType.expense) e += v;
      if (r.type == TxType.income) i += v;
    }
    return (expense: e, income: i);
  }

  Future<double> _toBase(double v, String cur) => CurrencyService.instance.toBase(v, cur);
}

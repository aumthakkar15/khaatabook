import 'dart:math';

import '../db/database.dart';
import '../models/models.dart';
import '../utils/money.dart';
import 'account_service.dart';
import 'category_service.dart';
import 'session.dart';
import 'transaction_service.dart';

class LoanSummary {
  final Loan loan;
  final List<LoanEmi> emis;
  final Account? account;
  LoanSummary(this.loan, this.emis, this.account);
  int get paidCount => emis.where((e) => e.paid).length;
  double get paidTotal => emis.where((e) => e.paid).fold(0.0, (s, e) => s + e.amount);
  double get interestPaid => emis.where((e) => e.paid).fold(0.0, (s, e) => s + e.interest);
  double get remaining => Money.round2(loan.principal - emis.where((e) => e.paid).fold(0.0, (s, e) => s + e.principal));
  LoanEmi? get next {
    for (final e in emis) {
      if (!e.paid) return e;
    }
    return null;
  }
  DateTime get endDate => emis.isEmpty ? loan.startDate : emis.last.dueDate;
  double get progress => emis.isEmpty ? 0 : paidCount / emis.length;
}

/// Feature 8: loans with an EMI schedule that auto-deducts from a bank
/// or credit card every month.
class LoanService {
  LoanService._();
  static final LoanService instance = LoanService._();

  /// Reducing-balance EMI. [ratePct] is % per annum.
  static double emi(double principal, double ratePct, int months) {
    if (months <= 0) return 0;
    if (ratePct <= 0) return principal / months;
    final r = ratePct / 12 / 100;
    final f = pow(1 + r, months).toDouble();
    return principal * r * f / (f - 1);
  }

  /// Full schedule; the last EMI absorbs rounding so the balance ends at 0.
  static List<LoanEmi> schedule(Loan l) {
    final out = <LoanEmi>[];
    final r = l.ratePct / 12 / 100;
    var balance = l.principal;
    var first = Dates.onDay(l.startDate.year, l.startDate.month, l.emiDay);
    if (!first.isAfter(l.startDate)) first = Dates.addMonths(first, 1, day: l.emiDay);
    for (var i = 1; i <= l.months; i++) {
      final interest = Money.round2(balance * r);
      var principal = Money.round2(l.emi - interest);
      var amount = l.emi;
      if (i == l.months || principal > balance) {
        principal = Money.round2(balance);
        amount = Money.round2(principal + interest);
      }
      balance = Money.round2(balance - principal);
      out.add(LoanEmi(
        loanId: l.id ?? 0,
        no: i,
        dueDate: Dates.addMonths(first, i - 1, day: l.emiDay),
        principal: principal,
        interest: interest,
        amount: Money.round2(amount),
        balanceAfter: balance < 0 ? 0 : balance,
      ));
      if (balance <= 0) break;
    }
    return out;
  }

  Future<int> create(Loan l) async {
    if (l.principal <= 0) throw TxException('Loan amount must be greater than zero');
    if (l.months <= 0) throw TxException('Tenure must be at least 1 month');
    final d = await AppDb.instance.db;
    late int id;
    await d.transaction((t) async {
      id = await t.insert('loans', l.toMap()..remove('id'));
      for (final e in schedule(Loan.fromMap({...l.toMap(), 'id': id}))) {
        await t.insert('loan_emis', LoanEmi(
          loanId: id, no: e.no, dueDate: e.dueDate, principal: e.principal, interest: e.interest, amount: e.amount, balanceAfter: e.balanceAfter,
        ).toMap()..remove('id'));
      }
    });
    DataBus.instance.changed();
    await postDue();
    return id;
  }

  Future<void> update(Loan l) async {
    final d = await AppDb.instance.db;
    await d.update('loans', {'name': l.name, 'lender': l.lender, 'account_id': l.accountId, 'status': l.status},
        where: 'id = ?', whereArgs: [l.id]);
    DataBus.instance.changed();
  }

  Future<void> delete(int id) async {
    final d = await AppDb.instance.db;
    await d.transaction((t) async {
      await t.delete('transactions', where: "source = 'loan' AND ref_id = ?", whereArgs: [id]);
      await t.delete('loans', where: 'id = ?', whereArgs: [id]);
    });
    DataBus.instance.changed();
  }

  Future<List<LoanSummary>> all({bool activeOnly = false}) async {
    final d = await AppDb.instance.db;
    final rows = await d.query('loans', where: activeOnly ? "status = 'active'" : null, orderBy: 'status, name');
    final accounts = await AccountService.instance.map();
    final out = <LoanSummary>[];
    for (final r in rows) {
      final l = Loan.fromMap(r);
      final emis = (await d.query('loan_emis', where: 'loan_id = ?', whereArgs: [l.id], orderBy: 'no')).map(LoanEmi.fromMap).toList();
      out.add(LoanSummary(l, emis, accounts[l.accountId]));
    }
    return out;
  }

  Future<LoanSummary?> get(int id) async {
    final list = await all();
    for (final s in list) {
      if (s.loan.id == id) return s;
    }
    return null;
  }

  Future<int> _emiCategory() async {
    final d = await AppDb.instance.db;
    final rows = await d.query('categories',
        where: "type = 'expense' AND parent_id IS NULL AND name = 'Loan EMI'", limit: 1);
    if (rows.isNotEmpty) return rows.first['id'] as int;
    return CategoryService.instance.add(const Category(type: TxType.expense, name: 'Loan EMI', icon: 'loan'));
  }

  /// Posts one EMI as an expense from the loan's account and marks it paid.
  Future<void> payEmi(LoanEmi e, {DateTime? date}) async {
    final d = await AppDb.instance.db;
    final loanRow = await d.query('loans', where: 'id = ?', whereArgs: [e.loanId]);
    if (loanRow.isEmpty) return;
    final loan = Loan.fromMap(loanRow.first);
    final account = await AccountService.instance.get(loan.accountId);
    if (account == null) throw TxException('Loan account not found');
    final catId = await _emiCategory();
    final tx = await TransactionService.instance.build(
      type: TxType.expense,
      date: date ?? e.dueDate,
      amount: e.amount,
      currency: account.currency,
      account: account,
      categoryId: catId,
      note: '${loan.name} · EMI ${e.no}',
      source: 'loan',
      refId: loan.id,
    );
    final txId = await TransactionService.instance.insert(tx);
    await d.update('loan_emis', {'paid': 1, 'paid_date': Dates.key(date ?? Dates.today()), 'transaction_id': txId},
        where: 'id = ?', whereArgs: [e.id]);
    final left = await d.rawQuery('SELECT COUNT(*) c FROM loan_emis WHERE loan_id = ? AND paid = 0', [loan.id]);
    if ((left.first['c'] as int) == 0) {
      await d.update('loans', {'status': 'closed'}, where: 'id = ?', whereArgs: [loan.id]);
    }
    DataBus.instance.changed();
  }

  /// Auto-posts every EMI whose due date has arrived. Returns how many posted.
  Future<int> postDue() async {
    final d = await AppDb.instance.db;
    final rows = await d.rawQuery('''
      SELECT e.* FROM loan_emis e JOIN loans l ON l.id = e.loan_id
      WHERE e.paid = 0 AND l.status = 'active' AND e.due_date <= ? ORDER BY e.due_date''', [Dates.key(Dates.today())]);
    var n = 0;
    for (final r in rows) {
      await payEmi(LoanEmi.fromMap(r));
      n++;
    }
    return n;
  }

  /// Upcoming EMIs within [days] (for notifications / Home).
  Future<List<(Loan, LoanEmi)>> upcoming({int days = 7}) async {
    final d = await AppDb.instance.db;
    final to = Dates.today().add(Duration(days: days));
    final rows = await d.rawQuery('''
      SELECT e.*, l.name AS loan_name FROM loan_emis e JOIN loans l ON l.id = e.loan_id
      WHERE e.paid = 0 AND l.status = 'active' AND e.due_date <= ? ORDER BY e.due_date''', [Dates.key(to)]);
    final out = <(Loan, LoanEmi)>[];
    for (final r in rows) {
      final loanRow = await d.query('loans', where: 'id = ?', whereArgs: [r['loan_id']]);
      out.add((Loan.fromMap(loanRow.first), LoanEmi.fromMap(r)));
    }
    return out;
  }
}

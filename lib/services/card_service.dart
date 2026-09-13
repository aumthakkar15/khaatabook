import '../db/database.dart';
import '../models/models.dart';
import '../utils/money.dart';
import 'account_service.dart';
import 'session.dart';
import 'transaction_service.dart';

/// Feature 6: credit-card billing cycles, due amounts, utilization and
/// "Pay this card" from a bank or another card.
class CardService {
  CardService._();
  static final CardService instance = CardService._();

  /// Card balance (negative = outstanding) as of the end of [date].
  Future<double> outstandingAt(int accountId, DateTime date) async {
    final d = await AppDb.instance.db;
    final rows = await d.rawQuery('''
      SELECT a.opening_balance
        + IFNULL((SELECT SUM(CASE
            WHEN t.type = 'income' THEN t.account_amount
            WHEN t.type = 'expense' THEN -t.account_amount
            WHEN t.type = 'transfer' THEN -t.account_amount ELSE 0 END)
          FROM transactions t WHERE t.account_id = a.id AND t.date <= ?), 0)
        + IFNULL((SELECT SUM(t.to_amount) FROM transactions t WHERE t.type='transfer' AND t.to_account_id = a.id AND t.date <= ?), 0)
        AS bal FROM accounts a WHERE a.id = ?''', [Dates.key(date), Dates.key(date), accountId]);
    final bal = (rows.first['bal'] as num? ?? 0).toDouble();
    return bal < 0 ? -bal : 0;
  }

  /// Creates the cycle record for every bill date that has already passed
  /// (since the card was created) and refreshes paid amounts.
  Future<void> generateCycles() async {
    final cards = await AccountService.instance.all(type: AccountType.card);
    final d = await AppDb.instance.db;
    final today = Dates.today();
    for (final c in cards) {
      final created = (await d.query('accounts', columns: ['created_at'], where: 'id = ?', whereArgs: [c.id])).first['created_at'] as String;
      final createdAt = DateTime.tryParse(created) ?? today;
      // First bill date on/after creation.
      var bill = Dates.onDay(createdAt.year, createdAt.month, c.billDay);
      if (!bill.isAfter(createdAt)) bill = Dates.addMonths(bill, 1, day: c.billDay);
      while (!bill.isAfter(today)) {
        final start = Dates.addMonths(bill, -1, day: c.billDay).add(const Duration(days: 1));
        var due = Dates.onDay(bill.year, bill.month, c.dueDay);
        if (!due.isAfter(bill)) due = Dates.addMonths(due, 1, day: c.dueDay);
        final existing = await d.query('card_cycles', where: 'account_id = ? AND cycle_end = ?', whereArgs: [c.id, Dates.key(bill)]);
        if (existing.isEmpty) {
          final amount = await outstandingAt(c.id!, bill);
          if (amount > 0.004) {
            await d.insert('card_cycles', CardCycle(
              accountId: c.id!, cycleStart: start, cycleEnd: bill, dueDate: due, amountDue: Money.round2(amount),
            ).toMap()..remove('id'));
          }
        }
        bill = Dates.addMonths(bill, 1, day: c.billDay);
      }
      await _refreshPaid(c.id!);
    }
  }

  /// Payments (transfers into the card) after the bill date count towards
  /// that cycle, oldest cycle first.
  Future<void> _refreshPaid(int accountId) async {
    final d = await AppDb.instance.db;
    final cycles = (await d.query('card_cycles', where: 'account_id = ?', whereArgs: [accountId], orderBy: 'cycle_end'))
        .map(CardCycle.fromMap)
        .toList();
    for (final cy in cycles) {
      final rows = await d.rawQuery('''
        SELECT IFNULL(SUM(to_amount),0) s FROM transactions
        WHERE type='transfer' AND to_account_id = ? AND date > ? AND date <= ?''',
          [accountId, Dates.key(cy.cycleEnd), Dates.key(Dates.addMonths(cy.cycleEnd, 1))]);
      final paid = (rows.first['s'] as num).toDouble();
      final status = paid + 0.004 >= cy.amountDue ? 'paid' : 'due';
      await d.update('card_cycles', {'paid_amount': Money.round2(paid), 'status': status}, where: 'id = ?', whereArgs: [cy.id]);
    }
  }

  Future<List<CardCycle>> cycles(int accountId) async {
    final d = await AppDb.instance.db;
    final rows = await d.query('card_cycles', where: 'account_id = ?', whereArgs: [accountId], orderBy: 'cycle_end DESC');
    return rows.map(CardCycle.fromMap).toList();
  }

  Future<CardCycle?> currentDue(int accountId) async {
    final d = await AppDb.instance.db;
    final rows = await d.query('card_cycles',
        where: 'account_id = ? AND status = ?', whereArgs: [accountId, 'due'], orderBy: 'due_date ASC', limit: 1);
    return rows.isEmpty ? null : CardCycle.fromMap(rows.first);
  }

  /// All unpaid cycles across cards (for Home reminders / notifications).
  Future<List<CardCycle>> allDue() async {
    final d = await AppDb.instance.db;
    final rows = await d.query('card_cycles', where: 'status = ?', whereArgs: ['due'], orderBy: 'due_date ASC');
    return rows.map(CardCycle.fromMap).toList();
  }

  /// Pay [amount] (in the SOURCE account's currency) from [source] to [card].
  /// Source balance decreases; card outstanding decreases so available limit rises.
  Future<int> pay({required Account card, required Account source, required double amount, DateTime? date, String? note}) async {
    if (!card.isCard) throw TxException('Destination must be a credit card');
    final t = await TransactionService.instance.build(
      type: TxType.transfer,
      date: date ?? DateTime.now(),
      amount: amount,
      currency: source.currency,
      account: source,
      toAccount: card,
      note: note ?? 'Card payment · ${card.name}',
      source: 'card_payment',
    );
    final id = await TransactionService.instance.insert(t);
    await _refreshPaid(card.id!);
    DataBus.instance.changed();
    return id;
  }
}

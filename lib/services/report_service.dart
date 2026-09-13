import '../models/models.dart';
import '../utils/money.dart';
import 'category_service.dart';
import 'currency_service.dart';
import 'session.dart';
import 'transaction_service.dart';

class ReportRow {
  final String label;
  final int? id;
  final double amount; // in report currency
  final int count;
  final List<ReportRow> children;
  ReportRow({required this.label, this.id, required this.amount, required this.count, this.children = const []});
}

class MonthPoint {
  final DateTime month;
  final double income;
  final double expense;
  MonthPoint(this.month, this.income, this.expense);
}

class ConversionNote {
  final String currency;
  final double original;
  final double converted;
  final double rate;
  ConversionNote(this.currency, this.original, this.converted, this.rate);
}

class Report {
  final String currency;
  final double income;
  final double expense;
  final List<ReportRow> byCategory; // for the chosen type, with sub-category children
  final List<ReportRow> byCurrency;
  final List<MonthPoint> months;
  final List<ConversionNote> notes;
  final List<Tx> transactions;
  Report({
    required this.currency,
    required this.income,
    required this.expense,
    required this.byCategory,
    required this.byCurrency,
    required this.months,
    required this.notes,
    required this.transactions,
  });
  double get net => income - expense;
}

/// Feature 13: reports with exact multi-currency conversion.
class ReportService {
  ReportService._();
  static final ReportService instance = ReportService._();

  /// [useCurrentRates] = false uses the rate stored on each transaction at
  /// entry time; true recalculates with today's master rates.
  Future<Report> build({
    required DateTime from,
    required DateTime to,
    required TxType type, // expense or income for the category breakdown
    int? categoryId,
    int? subcategoryId,
    int? accountId,
    String? reportCurrency,
    bool useCurrentRates = false,
  }) async {
    final base = Session.instance.base;
    final cur = reportCurrency ?? base;
    final cs = CurrencyService.instance;
    final reportRate = cur == base ? 1.0 : await cs.rateOf(cur); // 1 base = reportRate cur

    final txs = await TransactionService.instance.list(TxFilter(
      from: from,
      to: to,
      accountId: accountId,
      categoryId: categoryId,
      subcategoryId: subcategoryId,
    ));
    final cats = await CategoryService.instance.map();

    // Convert every transaction to the report currency at full precision.
    Future<double> inReport(Tx t) async {
      double baseAmt;
      if (useCurrentRates && t.currency != base) {
        baseAmt = await cs.toBase(t.amount, t.currency);
      } else {
        baseAmt = t.currency == base ? t.amount : t.amount / t.rateToBase;
      }
      return baseAmt * reportRate;
    }

    double income = 0, expense = 0;
    final byCat = <int?, double>{};
    final bySub = <int?, Map<int?, double>>{};
    final catCount = <int?, int>{};
    final byCur = <String, ({double orig, double conv, int n, double rate})>{};
    final monthMap = <String, List<double>>{};

    for (final t in txs) {
      if (t.type == TxType.transfer) continue;
      final v = await inReport(t);
      final mk = '${t.date.year}-${t.date.month.toString().padLeft(2, '0')}';
      monthMap.putIfAbsent(mk, () => [0, 0]);
      if (t.type == TxType.income) {
        income += v;
        monthMap[mk]![0] += v;
      } else {
        expense += v;
        monthMap[mk]![1] += v;
      }
      if (t.type == type) {
        byCat[t.categoryId] = (byCat[t.categoryId] ?? 0) + v;
        catCount[t.categoryId] = (catCount[t.categoryId] ?? 0) + 1;
        bySub.putIfAbsent(t.categoryId, () => {});
        bySub[t.categoryId]![t.subcategoryId] = (bySub[t.categoryId]![t.subcategoryId] ?? 0) + v;
        final prev = byCur[t.currency];
        final rateUsed = t.currency == base ? 1.0 : (useCurrentRates ? await cs.rateOf(t.currency) : t.rateToBase);
        byCur[t.currency] = (
          orig: (prev?.orig ?? 0) + t.amount,
          conv: (prev?.conv ?? 0) + v,
          n: (prev?.n ?? 0) + 1,
          rate: rateUsed,
        );
      }
    }

    final catRows = byCat.entries.map((e) {
      final subs = (bySub[e.key] ?? {}).entries.map((s) => ReportRow(
            label: s.key == null ? 'No sub-category' : (cats[s.key]?.name ?? 'Unknown'),
            id: s.key,
            amount: Money.round2(s.value),
            count: 0,
          )).toList()
        ..sort((a, b) => b.amount.compareTo(a.amount));
      return ReportRow(
        label: e.key == null ? 'Uncategorised' : (cats[e.key]?.name ?? 'Unknown'),
        id: e.key,
        amount: Money.round2(e.value),
        count: catCount[e.key] ?? 0,
        children: subs,
      );
    }).toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));

    final curRows = byCur.entries.map((e) => ReportRow(label: e.key, amount: Money.round2(e.value.conv), count: e.value.n)).toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));

    final notes = <ConversionNote>[
      for (final e in byCur.entries)
        if (e.key != cur) ConversionNote(e.key, Money.round2(e.value.orig), Money.round2(e.value.conv), e.value.rate)
    ];

    // Month series: fill every month in range so the chart has no gaps.
    final months = <MonthPoint>[];
    var m = DateTime(from.year, from.month);
    final end = DateTime(to.year, to.month);
    while (!m.isAfter(end)) {
      final k = '${m.year}-${m.month.toString().padLeft(2, '0')}';
      final v = monthMap[k] ?? [0, 0];
      months.add(MonthPoint(m, Money.round2(v[0]), Money.round2(v[1])));
      m = DateTime(m.year, m.month + 1);
    }

    return Report(
      currency: cur,
      income: Money.round2(income),
      expense: Money.round2(expense),
      byCategory: catRows,
      byCurrency: curRows,
      months: months,
      notes: notes,
      transactions: txs.where((t) => t.type == type).toList(),
    );
  }
}

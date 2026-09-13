import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/account_service.dart';
import '../services/category_service.dart';
import '../services/currency_service.dart';
import '../services/excel_io.dart';
import '../services/report_service.dart';
import '../services/session.dart';
import '../theme.dart';
import '../utils/money.dart';
import '../widgets/common.dart';
import 'transaction_tile.dart';

enum _View { list, chart, graph }

/// Feature 13: reports with filters, List / Chart / Graph views and
/// exact currency conversion.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime(DateTime.now().year, DateTime.now().month + 1, 0);
  bool _customRange = false;
  TxType _type = TxType.expense;
  Category? _cat;
  Category? _sub;
  Account? _account;
  String? _currency;
  bool _currentRates = false;
  _View _view = _View.chart;
  Report? _r;
  Map<int, Account> _accounts = {};
  Map<int, Category> _cats = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    DataBus.instance.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    DataBus.instance.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      _accounts = await AccountService.instance.map();
      _cats = await CategoryService.instance.map();
      // Chart view shows the 6 months ending at the selected month.
      final chartFrom = _view == _View.list || _customRange ? _from : DateTime(_to.year, _to.month - 5, 1);
      _r = await ReportService.instance.build(
        from: chartFrom,
        to: _to,
        type: _type,
        categoryId: _cat?.id,
        subcategoryId: _sub?.id,
        accountId: _account?.id,
        reportCurrency: _currency,
        useCurrentRates: _currentRates,
      );
    } catch (e) {
      if (mounted) showMsg(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickMonth() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _to,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Pick any day in the month',
    );
    if (d == null) return;
    _customRange = false;
    _from = DateTime(d.year, d.month, 1);
    _to = DateTime(d.year, d.month + 1, 0);
    _load();
  }

  Future<void> _pickRange() async {
    final r = await showDateRangePicker(context: context, firstDate: DateTime(2000), lastDate: DateTime(2100), initialDateRange: DateTimeRange(start: _from, end: _to));
    if (r == null) return;
    _customRange = true;
    _from = r.start;
    _to = r.end;
    _load();
  }

  Future<void> _pickCategory() async {
    final list = await CategoryService.instance.top(_type);
    if (!mounted) return;
    final items = <Category?>[null, ...list];
    final c = await pickFromSheet<Category?>(
      context,
      title: 'Category',
      items: items,
      tile: (c) => ListRow(leading: IconTile(c == null ? Icons.apps_rounded : CategoryIcons.of(c.icon)), title: c?.name ?? 'All categories'),
    );
    if (!mounted) return;
    _cat = c;
    _sub = null;
    if (c != null) {
      final subs = await CategoryService.instance.subs(c.id!);
      if (subs.isNotEmpty && mounted) {
        final s = await pickFromSheet<Category?>(
          context,
          title: '${c.name} · sub-category',
          items: <Category?>[null, ...subs],
          tile: (s) => ListRow(leading: const IconTile(Icons.subdirectory_arrow_right_rounded), title: s?.name ?? 'All sub-categories'),
        );
        _sub = s;
      }
    }
    _load();
  }

  Future<void> _pickCurrency() async {
    final list = (await CurrencyService.instance.all()).where((c) => c.rate > 0).toList();
    if (!mounted) return;
    final c = await pickFromSheet<Currency>(
      context,
      title: 'Report currency',
      items: list,
      tile: (c) => ListRow(leading: IconTile(Icons.currency_exchange_rounded, filled: c.inUse), title: '${c.code} · ${c.name}'),
    );
    if (c != null) {
      _currency = c.code;
      _load();
    }
  }

  Future<void> _pickAccount() async {
    final list = await AccountService.instance.all(includeArchived: true);
    if (!mounted) return;
    final a = await pickFromSheet<Account?>(
      context,
      title: 'Account',
      items: <Account?>[null, ...list],
      tile: (a) => ListRow(leading: IconTile(a == null ? Icons.apps_rounded : accountIcon(a.type)), title: a?.name ?? 'All accounts'),
    );
    _account = a;
    _load();
  }

  Future<void> _export() async {
    final r = _r;
    if (r == null) return;
    try {
      final x = ExcelIO.build({
        'Summary': [
          ['Report', _type == TxType.income ? 'Income' : 'Expense'],
          ['From', Dates.key(_from)],
          ['To', Dates.key(_to)],
          ['Currency', r.currency],
          ['Income', r.income],
          ['Expense', r.expense],
          ['Net', r.net],
        ],
        'By category': [
          ['Category', 'Sub-category', 'Amount (${r.currency})'],
          for (final c in r.byCategory) ...[
            [c.label, '', c.amount],
            for (final s in c.children) [c.label, s.label, s.amount],
          ],
        ],
        'By currency': [
          ['Currency', 'Transactions', 'Amount (${r.currency})'],
          for (final c in r.byCurrency) [c.label, c.count, c.amount],
        ],
        'By month': [
          ['Month', 'Income', 'Expense'],
          for (final m in r.months) [Dates.mY.format(m.month), m.income, m.expense],
        ],
        'Transactions': [
          ['Date', 'Category', 'Sub-category', 'Account', 'Amount', 'Currency', 'Note'],
          for (final t in r.transactions)
            [Dates.key(t.date), _cats[t.categoryId ?? -1]?.name ?? '', _cats[t.subcategoryId ?? -1]?.name ?? '', _accounts[t.accountId]?.name ?? '', t.amount, t.currency, t.note ?? ''],
        ],
      });
      final f = await ExcelIO.save(x, 'KhaataBook_report_${Dates.key(_from)}_${Dates.key(_to)}.xlsx');
      await ExcelIO.share(f, text: 'Khaata Book report');
    } catch (e) {
      if (mounted) showMsg(context, 'Export failed: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    return Column(
      children: [
        NavyHeader(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(child: Text('Reports', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: KColors.white, letterSpacing: -0.3))),
                  Pill(_currency ?? Session.instance.base, onNavy: true, icon: Icons.currency_exchange_rounded, onTap: _pickCurrency),
                  const SizedBox(width: 8),
                  HeaderButton(icon: Icons.ios_share_rounded, onTap: _export),
                ],
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    Pill(_customRange ? '${Dates.dM.format(_from)} – ${Dates.dM.format(_to)}' : Dates.mY.format(_to), onNavy: true, selected: true, icon: Icons.calendar_today_outlined, onTap: _pickMonth),
                    const SizedBox(width: 8),
                    Pill('Range', onNavy: true, icon: Icons.date_range_outlined, onTap: _pickRange),
                    const SizedBox(width: 8),
                    Pill(_type == TxType.income ? 'Income' : 'Expense', onNavy: true, icon: Icons.swap_vert_rounded, onTap: () {
                      _type = _type == TxType.income ? TxType.expense : TxType.income;
                      _cat = null;
                      _sub = null;
                      _load();
                    }),
                    const SizedBox(width: 8),
                    Pill(_sub?.name ?? _cat?.name ?? 'All categories', onNavy: true, icon: Icons.sell_outlined, onTap: _pickCategory),
                    const SizedBox(width: 8),
                    Pill(_account?.name ?? 'All accounts', onNavy: true, icon: Icons.account_balance_wallet_outlined, onTap: _pickAccount),
                    const SizedBox(width: 8),
                    Pill(_currentRates ? 'Today\'s rates' : 'Rates at entry', onNavy: true, icon: Icons.sync_rounded, onTap: () {
                      _currentRates = !_currentRates;
                      _load();
                    }),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Segmented<_View>(
                values: _View.values,
                value: _view,
                onNavy: true,
                label: (v) => switch (v) { _View.list => 'List', _View.chart => 'Chart', _View.graph => 'Graph' },
                onChanged: (v) {
                  _view = v;
                  _load();
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: r == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 100),
                  children: [
                    Row(
                      children: [
                        Expanded(child: _tile('Income', r.income, KColors.green, true)),
                        const SizedBox(width: 10),
                        Expanded(child: _tile('Expense', -r.expense, KColors.red, false)),
                        const SizedBox(width: 10),
                        Expanded(child: _tile('Net', r.net, KColors.navy, false)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_busy) const LinearProgressIndicator(minHeight: 2),
                    switch (_view) {
                      _View.list => _listView(r),
                      _View.chart => _chartView(r),
                      _View.graph => _graphView(r),
                    },
                    if (r.notes.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      KCard(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Currency conversion', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: KColors.muted)),
                            const SizedBox(height: 6),
                            for (final n in r.notes)
                              Text(
                                '${n.currency} ${Money.plain(n.original)} → ${r.currency} ${Money.plain(n.converted)} · rate ${Money.rate(n.rate)} (1 ${Session.instance.base} = ${n.currency}) · ${_currentRates ? 'today\'s master rate' : 'rate at entry'}',
                                style: const TextStyle(fontSize: 12, color: KColors.muted),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _tile(String label, double v, Color color, bool plus) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: KColors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: KColors.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: KColors.muted)),
          const SizedBox(height: 2),
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(Money.format(v, showPlus: plus), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: v < -0.004 ? KColors.red : color))),
        ],
      ),
    );
  }

  // ---------- List view ----------
  Widget _listView(Report r) {
    if (r.byCategory.isEmpty) return const KCard(child: EmptyState(icon: Icons.list_alt_rounded, title: 'No transactions for these filters'));
    return Column(
      children: [
        KCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (final c in r.byCategory)
                Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                    leading: IconTile(CategoryIcons.of(_cats[c.id ?? -1]?.icon ?? 'tag')),
                    title: Text(c.label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    subtitle: Text('${c.count} transaction${c.count == 1 ? '' : 's'} · ${(r.expense == 0 && r.income == 0) ? 0 : (c.amount / (_type == TxType.income ? r.income : r.expense) * 100).round()}%', style: const TextStyle(fontSize: 12, color: KColors.muted)),
                    trailing: Text('${r.currency} ${Money.plain(c.amount)}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    children: [
                      for (final s in c.children)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(74, 0, 16, 10),
                          child: Row(
                            children: [
                              Expanded(child: Text(s.label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                              Text(Money.plain(s.amount), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: KColors.muted)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Align(alignment: Alignment.centerLeft, child: Text('By currency', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
        const SizedBox(height: 8),
        KCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (final c in r.byCurrency)
                ListRow(
                  leading: Container(width: 46, height: 40, alignment: Alignment.center, decoration: BoxDecoration(color: KColors.tint, borderRadius: BorderRadius.circular(12)), child: Text(c.label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800))),
                  title: '${c.count} transaction${c.count == 1 ? '' : 's'}',
                  trailing: Text('${r.currency} ${Money.plain(c.amount)}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Align(alignment: Alignment.centerLeft, child: Text('Transactions', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
        const SizedBox(height: 8),
        KCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < r.transactions.length; i++) ...[
                if (i > 0) const Divider(indent: 16, endIndent: 16),
                TransactionTile(tx: r.transactions[i], accounts: _accounts, cats: _cats),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ---------- Chart view (bars) ----------
  Widget _chartView(Report r) {
    final maxY = r.months.fold<double>(0, (m, p) => [m, p.income, p.expense].reduce((a, b) => a > b ? a : b));
    return Column(
      children: [
        KCard(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Income vs expense', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                  Row(children: [_legend(KColors.green, 'Income'), const SizedBox(width: 12), _legend(KColors.navyChart, 'Expense')]),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 170,
                child: BarChart(BarChartData(
                  maxY: maxY <= 0 ? 10 : maxY * 1.15,
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (g, gi, rod, ri) => BarTooltipItem(
                        '${ri == 0 ? 'Income' : 'Expense'}\n${r.currency} ${Money.plain(rod.toY)}',
                        const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
                      ),
                    ),
                  ),
                  gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (_) => const FlLine(color: KColors.lineSoft, strokeWidth: 1)),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (v, _) {
                          final i = v.toInt();
                          if (i < 0 || i >= r.months.length) return const SizedBox();
                          return Padding(padding: const EdgeInsets.only(top: 6), child: Text(_monthShort(r.months[i].month), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: KColors.muted)));
                        },
                      ),
                    ),
                  ),
                  barGroups: [
                    for (var i = 0; i < r.months.length; i++)
                      BarChartGroupData(x: i, barsSpace: 3, barRods: [
                        BarChartRodData(toY: r.months[i].income, color: KColors.green, width: 10, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
                        BarChartRodData(toY: r.months[i].expense, color: KColors.navyChart, width: 10, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
                      ]),
                  ],
                )),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        KCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('By category · ${_type == TxType.income ? 'income' : 'expense'}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              if (r.byCategory.isEmpty) const Text('No data', style: TextStyle(color: KColors.muted)),
              for (var i = 0; i < r.byCategory.length && i < 8; i++) ...[
                _hbar(r.byCategory[i].label, r.byCategory[i].amount, r.byCategory.first.amount, i),
                const SizedBox(height: 8),
              ],
              if (_cat != null && r.byCategory.isNotEmpty && r.byCategory.first.children.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Sub-categories · ${_cat!.name}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: KColors.muted)),
                const SizedBox(height: 8),
                for (var i = 0; i < r.byCategory.first.children.length; i++) ...[
                  _hbar(r.byCategory.first.children[i].label, r.byCategory.first.children[i].amount, r.byCategory.first.children.first.amount, i),
                  const SizedBox(height: 8),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }

  static const _ramp = [KColors.navy, KColors.navyChart, Color(0xFF4F6D9A), Color(0xFF6B8AC4), Color(0xFF8FA5C6), Color(0xFF9DB3D9), Color(0xFFB8C4D6), Color(0xFFC9D3E3)];

  Widget _hbar(String label, double v, double max, int i) {
    return Row(
      children: [
        SizedBox(width: 92, child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
        const SizedBox(width: 10),
        Expanded(child: ProgressBar(max <= 0 ? 0 : v / max, height: 12, color: _ramp[i % _ramp.length], track: KColors.offWhite)),
        const SizedBox(width: 10),
        SizedBox(width: 70, child: Text(Money.plain(v), textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
      ],
    );
  }

  // ---------- Graph view (trend line + donut) ----------
  Widget _graphView(Report r) {
    final pts = r.months;
    final total = r.byCategory.fold<double>(0, (s, c) => s + c.amount);
    return Column(
      children: [
        KCard(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Trend', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                  Row(children: [_legend(KColors.green, 'Income'), const SizedBox(width: 12), _legend(KColors.navyChart, 'Expense')]),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 170,
                child: LineChart(LineChartData(
                  gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (_) => const FlLine(color: KColors.lineSoft, strokeWidth: 1)),
                  borderData: FlBorderData(show: false),
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (spots) => spots
                          .map((s) => LineTooltipItem('${s.barIndex == 0 ? 'Income' : 'Expense'} ${Money.plain(s.y)}', const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)))
                          .toList(),
                    ),
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: 1,
                        getTitlesWidget: (v, _) {
                          final i = v.toInt();
                          if (i < 0 || i >= pts.length || v != i.toDouble()) return const SizedBox();
                          return Padding(padding: const EdgeInsets.only(top: 6), child: Text(_monthShort(pts[i].month), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: KColors.muted)));
                        },
                      ),
                    ),
                  ),
                  lineBarsData: [
                    _line([for (var i = 0; i < pts.length; i++) FlSpot(i.toDouble(), pts[i].income)], KColors.green),
                    _line([for (var i = 0; i < pts.length; i++) FlSpot(i.toDouble(), pts[i].expense)], KColors.navyChart),
                  ],
                )),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        KCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Share by category · ${_type == TxType.income ? 'income' : 'expense'}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              if (total <= 0)
                const Text('No data', style: TextStyle(color: KColors.muted))
              else
                Row(
                  children: [
                    SizedBox(
                      width: 150,
                      height: 150,
                      child: PieChart(PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: 42,
                        sections: [
                          for (var i = 0; i < r.byCategory.length && i < 8; i++)
                            PieChartSectionData(
                              value: r.byCategory[i].amount,
                              color: _ramp[i % _ramp.length],
                              radius: 30,
                              showTitle: false,
                            ),
                        ],
                      )),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < r.byCategory.length && i < 8; i++)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(children: [
                                Container(width: 10, height: 10, decoration: BoxDecoration(color: _ramp[i % _ramp.length], borderRadius: BorderRadius.circular(3))),
                                const SizedBox(width: 6),
                                Expanded(child: Text(r.byCategory[i].label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                                Text('${(r.byCategory[i].amount / total * 100).round()}%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: KColors.muted)),
                              ]),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  LineChartBarData _line(List<FlSpot> spots, Color c) => LineChartBarData(
        spots: spots,
        color: c,
        barWidth: 2.5,
        isCurved: false,
        dotData: const FlDotData(show: true),
        belowBarData: BarAreaData(show: true, color: c.withOpacity(0.06)),
      );

  Widget _legend(Color c, String s) => Row(children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 5),
        Text(s, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: KColors.muted)),
      ]);

  String _monthShort(DateTime m) => const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][m.month - 1];
}

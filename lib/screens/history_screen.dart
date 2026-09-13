import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/account_service.dart';
import '../services/category_service.dart';
import '../services/session.dart';
import '../services/transaction_service.dart';
import '../theme.dart';
import '../utils/money.dart';
import '../widgets/common.dart';
import 'transaction_tile.dart';

/// Month-by-month transaction history with search and type filter.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  TxType? _type;
  String _search = '';
  bool _searching = false;
  List<Tx> _txs = [];
  Map<int, Account> _accounts = {};
  Map<int, Category> _cats = {};
  double _income = 0, _expense = 0;

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
    final from = _month;
    final to = DateTime(_month.year, _month.month + 1, 0);
    _txs = await TransactionService.instance.list(TxFilter(from: from, to: to, type: _type, search: _search));
    _accounts = await AccountService.instance.map();
    _cats = await CategoryService.instance.map();
    final t = await TransactionService.instance.totals(from, to);
    _income = t.income;
    _expense = t.expense;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final base = Session.instance.base;
    // group by date
    final groups = <String, List<Tx>>{};
    for (final t in _txs) {
      groups.putIfAbsent(Dates.key(t.date), () => []).add(t);
    }
    final keys = groups.keys.toList()..sort((a, b) => b.compareTo(a));

    return Column(
      children: [
        Container(
          color: KColors.white,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _searching
                            ? TextField(
                                autofocus: true,
                                onChanged: (v) {
                                  _search = v;
                                  _load();
                                },
                                decoration: const InputDecoration(hintText: 'Search notes', isDense: true),
                              )
                            : const Text('History', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                      ),
                      const SizedBox(width: 8),
                      HeaderButton(
                        icon: _searching ? Icons.close_rounded : Icons.search_rounded,
                        onNavy: false,
                        onTap: () => setState(() {
                          _searching = !_searching;
                          if (!_searching) {
                            _search = '';
                            _load();
                          }
                        }),
                      ),
                      const SizedBox(width: 8),
                      PopupMenuButton<String>(
                        onSelected: (v) {
                          _type = v == 'all' ? null : txTypeFrom(v);
                          _load();
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'all', child: Text('All')),
                          PopupMenuItem(value: 'expense', child: Text('Expenses')),
                          PopupMenuItem(value: 'income', child: Text('Income')),
                          PopupMenuItem(value: 'transfer', child: Text('Transfers')),
                        ],
                        child: HeaderButton(icon: _type == null ? Icons.filter_alt_outlined : Icons.filter_alt, onNavy: false),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    height: 48,
                    decoration: BoxDecoration(color: KColors.offWhite, borderRadius: BorderRadius.circular(14)),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () {
                            _month = DateTime(_month.year, _month.month - 1);
                            _load();
                          },
                          icon: const Icon(Icons.chevron_left_rounded),
                        ),
                        Expanded(child: Center(child: Text(Dates.mY.format(_month), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)))),
                        IconButton(
                          onPressed: () {
                            _month = DateTime(_month.year, _month.month + 1);
                            _load();
                          },
                          icon: const Icon(Icons.chevron_right_rounded),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: _tile('Balance', _income - _expense, KColors.navy, KColors.white, KColors.onNavyMuted, base)),
                      const SizedBox(width: 10),
                      Expanded(child: _tile('Income', _income, KColors.greenTint, KColors.navy, KColors.green, base)),
                      const SizedBox(width: 10),
                      Expanded(child: _tile('Spent', -_expense, KColors.redTint, KColors.navy, KColors.red, base)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        const Divider(),
        Expanded(
          child: _txs.isEmpty
              ? const EmptyState(icon: Icons.calendar_month_outlined, title: 'Nothing in this month', subtitle: 'Use the arrows to move between months')
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 100),
                  children: [
                    for (final k in keys) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(_dayLabel(DateTime.parse(k)), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: KColors.muted, letterSpacing: 0.4)),
                            Text(_dayTotal(groups[k]!), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: KColors.muted)),
                          ],
                        ),
                      ),
                      KCard(
                        padding: EdgeInsets.zero,
                        child: Column(
                          children: [
                            for (var i = 0; i < groups[k]!.length; i++) ...[
                              if (i > 0) const Divider(indent: 16, endIndent: 16),
                              TransactionTile(tx: groups[k]![i], accounts: _accounts, cats: _cats, showDate: false),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  String _dayLabel(DateTime d) {
    final f = Dates.friendly(d);
    return f == 'Today' || f == 'Yesterday' ? '$f · ${Dates.dM.format(d)}'.toUpperCase() : Dates.dMy.format(d).toUpperCase();
  }

  String _dayTotal(List<Tx> list) {
    double net = 0;
    for (final t in list) {
      if (t.type == TxType.income) net += t.baseAmount;
      if (t.type == TxType.expense) net -= t.baseAmount;
    }
    return Money.format(net, showPlus: true);
  }

  Widget _tile(String label, double value, Color bg, Color fg, Color labelColor, String base) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: labelColor)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(Money.format(value), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: value < -0.004 && bg != KColors.navy ? KColors.red : (bg == KColors.navy && value < -0.004 ? KColors.redOnNavy : fg))),
          ),
        ],
      ),
    );
  }
}

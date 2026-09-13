import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/account_service.dart';
import '../services/category_service.dart';
import '../services/recurring_service.dart';
import '../services/session.dart';
import '../theme.dart';
import '../utils/money.dart';
import '../widgets/common.dart';
import 'add_transaction_screen.dart';

/// Feature 14: recurring rules list with progress, Edit / Pause / Stop.
class RecurringScreen extends StatefulWidget {
  const RecurringScreen({super.key});
  @override
  State<RecurringScreen> createState() => _RecurringScreenState();
}

class _RecurringScreenState extends State<RecurringScreen> {
  String _status = 'active';
  List<Recurring> _rules = [];
  Map<int, Account> _accounts = {};
  Map<int, Category> _cats = {};
  double _mExp = 0, _mInc = 0;
  int? _expanded;

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
    _rules = await RecurringService.instance.all(status: _status);
    _accounts = await AccountService.instance.map();
    _cats = await CategoryService.instance.map();
    final t = await RecurringService.instance.monthlyTotals();
    _mExp = t.expense;
    _mInc = t.income;
    if (mounted) setState(() {});
  }

  Future<void> _edit(Recurring r) async {
    final amount = TextEditingController(text: Money.plain(r.amount));
    final name = TextEditingController(text: r.name);
    var total = r.totalCount;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('Edit recurring', style: TextStyle(fontWeight: FontWeight.w800)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(hintText: 'Name')),
            const SizedBox(height: 10),
            TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(hintText: 'Amount', prefixText: '${r.currency} ')),
            const SizedBox(height: 10),
            Row(children: [
              const Text('Total times: ', style: TextStyle(fontWeight: FontWeight.w600)),
              Expanded(
                child: TextField(
                  controller: TextEditingController(text: total?.toString() ?? ''),
                  keyboardType: TextInputType.number,
                  onChanged: (v) => total = int.tryParse(v),
                  decoration: const InputDecoration(hintText: 'blank = no end', isDense: true),
                ),
              ),
            ]),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await RecurringService.instance.update(Recurring(
      id: r.id,
      type: r.type,
      name: name.text.trim().isEmpty ? r.name : name.text.trim(),
      amount: Money.parse(amount.text) > 0 ? Money.parse(amount.text) : r.amount,
      currency: r.currency,
      accountId: r.accountId,
      toAccountId: r.toAccountId,
      categoryId: r.categoryId,
      subcategoryId: r.subcategoryId,
      frequency: r.frequency,
      day: r.day,
      startDate: r.startDate,
      totalCount: total,
      postedCount: r.postedCount,
      nextDate: r.nextDate,
      status: total != null && r.postedCount >= total! ? 'completed' : (r.status == 'completed' ? 'active' : r.status),
      note: r.note,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          NavyHeader(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              children: [
                Row(children: [
                  const BackButtonNavy(),
                  const SizedBox(width: 12),
                  const Expanded(child: Text('Recurring', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: KColors.white))),
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      _status = v;
                      _load();
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'active', child: Text('Active')),
                      PopupMenuItem(value: 'paused', child: Text('Paused')),
                      PopupMenuItem(value: 'completed', child: Text('Completed')),
                    ],
                    child: Pill(_status[0].toUpperCase() + _status.substring(1), onNavy: true, icon: Icons.expand_more_rounded),
                  ),
                ]),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(child: _chip('Monthly expense', -_mExp)),
                  const SizedBox(width: 10),
                  Expanded(child: _chip('Monthly income', _mInc, plus: true)),
                ]),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
              children: [
                if (_rules.isEmpty) KCard(child: EmptyState(icon: Icons.repeat_rounded, title: 'No $_status recurring transactions', subtitle: 'Turn on "Repeat" when adding a transaction')),
                for (final r in _rules) ...[_tile(r), const SizedBox(height: 10)],
              ],
            ),
          ),
          BottomButton(
            label: 'New recurring transaction',
            icon: Icons.repeat_rounded,
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddTransactionScreen())),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, double v, {bool plus = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.10), borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 11, color: KColors.onNavyMuted, fontWeight: FontWeight.w500)),
          const SizedBox(height: 2),
          MoneyText(v, size: 15, onNavy: true, showPlus: plus, positiveGreen: plus),
        ]),
      );

  Widget _tile(Recurring r) {
    final acc = _accounts[r.accountId];
    final to = r.toAccountId == null ? null : _accounts[r.toAccountId!];
    final cat = _cats[r.categoryId ?? -1];
    final sub = _cats[r.subcategoryId ?? -1];
    final path = r.type == TxType.transfer ? '${acc?.name ?? ''} → ${to?.name ?? ''}' : [cat?.name, sub?.name].whereType<String>().join(' › ');
    final schedule = switch (r.frequency) {
      'weekly' => 'Weekly',
      'yearly' => 'Yearly · ${Dates.dM.format(r.nextDate)}',
      _ => 'Monthly · ${r.day}${_ord(r.day)}',
    };
    final left = r.totalCount == null ? 'no end' : '${r.totalCount! - r.postedCount} left';
    final expanded = _expanded == r.id;
    final signed = r.type == TxType.expense ? -r.amount : r.amount;
    return KCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          ListRow(
            leading: IconTile(
              r.type == TxType.transfer ? Icons.swap_vert_rounded : (cat == null ? Icons.repeat_rounded : CategoryIcons.of(cat.icon)),
              filled: expanded,
              tint: r.type == TxType.income ? KColors.greenTint : null,
              iconColor: r.type == TxType.income ? KColors.green : null,
            ),
            title: r.name,
            subtitle: '$path${r.type == TxType.transfer ? '' : ' · ${acc?.name ?? ''}'}',
            trailing: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              r.type == TxType.transfer ? Text(Money.format(r.amount, code: r.currency), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: KColors.muted)) : MoneyText(signed, code: r.currency, showPlus: true, positiveGreen: true),
              Text('$schedule · $left', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: KColors.muted)),
            ]),
            onTap: () => setState(() => _expanded = expanded ? null : r.id),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Column(
                children: [
                  if (r.totalCount != null) ...[
                    ProgressBar(r.totalCount! == 0 ? 1 : r.postedCount / r.totalCount!, height: 6),
                    const SizedBox(height: 6),
                  ],
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('${r.postedCount}${r.totalCount == null ? '' : ' of ${r.totalCount}'} posted', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    Text(r.status == 'active' ? 'Next ${Dates.dMy.format(r.nextDate)}' : r.status[0].toUpperCase() + r.status.substring(1), style: const TextStyle(fontSize: 12, color: KColors.muted)),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: _btn('Edit', () => _edit(r))),
                    const SizedBox(width: 8),
                    Expanded(child: _btn(r.status == 'paused' ? 'Resume' : 'Pause', () => RecurringService.instance.setStatus(r.id!, r.status == 'paused' ? 'active' : 'paused'))),
                    const SizedBox(width: 8),
                    Expanded(child: _btn('Stop', () async {
                      final ok = await confirm(context, 'Stop this recurring transaction?', 'Already posted transactions are kept.', okLabel: 'Stop', danger: true);
                      if (ok) await RecurringService.instance.delete(r.id!);
                    }, danger: true)),
                  ]),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _btn(String label, VoidCallback onTap, {bool danger = false}) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: KColors.offWhite, borderRadius: BorderRadius.circular(12)),
          child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: danger ? KColors.red : KColors.navy)),
        ),
      );

  String _ord(int d) {
    if (d >= 11 && d <= 13) return 'th';
    return switch (d % 10) { 1 => 'st', 2 => 'nd', 3 => 'rd', _ => 'th' };
  }
}

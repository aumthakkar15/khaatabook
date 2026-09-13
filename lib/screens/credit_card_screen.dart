import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/account_service.dart';
import '../services/card_service.dart';
import '../services/session.dart';
import '../theme.dart';
import '../utils/money.dart';
import '../widgets/common.dart';
import 'account_form_screen.dart';

/// Feature 6: credit card detail — limits, utilization, bill & due dates,
/// current due, cycles, and "Pay this card".
class CreditCardScreen extends StatefulWidget {
  final int accountId;
  const CreditCardScreen({super.key, required this.accountId});
  @override
  State<CreditCardScreen> createState() => _CreditCardScreenState();
}

class _CreditCardScreenState extends State<CreditCardScreen> {
  Account? _card;
  CardCycle? _due;
  List<CardCycle> _cycles = [];
  List<Account> _sources = [];
  Account? _source;
  final _amount = TextEditingController();
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
    await CardService.instance.generateCycles();
    _card = await AccountService.instance.get(widget.accountId);
    _due = await CardService.instance.currentDue(widget.accountId);
    _cycles = await CardService.instance.cycles(widget.accountId);
    _sources = (await AccountService.instance.all()).where((a) => a.id != widget.accountId).toList();
    _source ??= _sources.where((a) => a.type == AccountType.bank).firstOrNull ?? _sources.firstOrNull;
    if (_amount.text.isEmpty) {
      final d = _due?.remaining ?? _card?.outstanding ?? 0;
      if (d > 0) _amount.text = Money.plain(d);
    }
    if (mounted) setState(() {});
  }

  Future<void> _pay() async {
    final card = _card;
    final src = _source;
    if (card == null || src == null) {
      showMsg(context, 'Choose the account to pay from', error: true);
      return;
    }
    final amt = Money.parse(_amount.text);
    if (amt <= 0) {
      showMsg(context, 'Enter the amount to pay', error: true);
      return;
    }
    final ok = await confirm(context, 'Pay ${Money.format(amt, code: src.currency)}?', 'From ${src.name} to ${card.name}. The bank balance reduces and the card\'s available limit increases.', okLabel: 'Pay');
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await CardService.instance.pay(card: card, source: src, amount: amt);
      _amount.clear();
      if (mounted) showMsg(context, 'Payment recorded');
    } catch (e) {
      if (mounted) showMsg(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _card;
    if (c == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final due = _due;
    return Scaffold(
      body: Column(
        children: [
          Container(
            color: KColors.offWhite,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Row(children: [
                  const BackButtonNavy(onNavy: false),
                  const SizedBox(width: 12),
                  Expanded(child: Text(c.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
                  HeaderButton(icon: Icons.edit_outlined, onNavy: false, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AccountFormScreen(existing: c)))),
                ]),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: [
                // Card visual
                Container(
                  padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
                  decoration: BoxDecoration(color: KColors.navy, borderRadius: BorderRadius.circular(22)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Available limit', style: TextStyle(fontSize: 12, color: KColors.onNavyMuted, fontWeight: FontWeight.w500)),
                                const SizedBox(height: 4),
                                MoneyText(c.availableLimit, code: c.currency, size: 28, weight: FontWeight.w800, onNavy: true),
                              ],
                            ),
                          ),
                          if (c.last4 != null)
                            Container(
                              height: 28,
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(color: Colors.white.withOpacity(0.14), borderRadius: BorderRadius.circular(8)),
                              child: Text('••••${c.last4}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: KColors.white)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      ProgressBar(c.utilization, color: KColors.white, track: Colors.white.withOpacity(0.16)),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('${(c.utilization * 100).round()}% used · ${Money.plain(c.outstanding)} of ${Money.plain(c.creditLimit, decimals: 0)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: KColors.white)),
                          Text('Total limit ${Money.plain(c.creditLimit, decimals: 0)}', style: const TextStyle(fontSize: 12, color: KColors.onNavyMuted, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _info('Bill date', '${_ord(c.billDay)} of month')),
                    const SizedBox(width: 12),
                    Expanded(child: _info('Payment due', '${_ord(c.dueDay)} of month')),
                  ],
                ),
                const SizedBox(height: 12),
                if (due != null)
                  KCard(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        const IconTile(Icons.notifications_active_outlined, tint: KColors.redTint, iconColor: KColors.red),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Payment due · ${Dates.dMy.format(due.dueDate)}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                              const SizedBox(height: 2),
                              Text('Cycle ${Dates.dM.format(due.cycleStart)} – ${Dates.dM.format(due.cycleEnd)} · ${_daysLeft(due.dueDate)}${due.paidAmount > 0 ? ' · paid ${Money.plain(due.paidAmount)}' : ''}', style: const TextStyle(fontSize: 12, color: KColors.muted)),
                            ],
                          ),
                        ),
                        MoneyText(-due.remaining, size: 17, weight: FontWeight.w800),
                      ],
                    ),
                  )
                else
                  KCard(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(children: [
                      const IconTile(Icons.check_circle_outline, tint: KColors.greenTint, iconColor: KColors.green),
                      const SizedBox(width: 12),
                      Expanded(child: Text(c.outstanding > 0 ? 'No statement due yet · current spend ${Money.plain(c.outstanding)}' : 'Nothing due — card is fully paid', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
                    ]),
                  ),
                const SizedBox(height: 16),
                // Pay this card
                KCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Pay this card', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 12),
                      const Text('Pay from', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: KColors.muted)),
                      const SizedBox(height: 6),
                      PickerField(
                        label: _source == null ? 'Account' : '${accountTypeLabel(_source!.type)} · balance ${Money.format(_source!.isCard ? _source!.availableLimit : _source!.balance)}',
                        value: _source?.name ?? 'Choose bank or card',
                        icon: _source == null ? Icons.account_balance_outlined : accountIcon(_source!.type),
                        highlighted: true,
                        onTap: () async {
                          final a = await pickFromSheet<Account>(
                            context,
                            title: 'Pay from',
                            items: _sources,
                            tile: (a) => ListRow(leading: IconTile(accountIcon(a.type)), title: a.name, subtitle: '${accountTypeLabel(a.type)} · ${a.currency}', trailing: MoneyText(a.isCard ? a.availableLimit : a.balance, size: 14)),
                          );
                          if (a != null) setState(() => _source = a);
                        },
                      ),
                      const SizedBox(height: 12),
                      const Text('Amount', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: KColors.muted)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _amount,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                              decoration: InputDecoration(prefixText: '${_source?.currency ?? c.currency} ', prefixStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: KColors.faint)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Pill('Full due', onTap: () => setState(() => _amount.text = Money.plain(due?.remaining ?? c.outstanding))),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: _busy ? null : _pay,
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: Text('Pay ${_source?.currency ?? c.currency} ${Money.plain(Money.parse(_amount.text))}'),
                        style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                      ),
                      const SizedBox(height: 8),
                      const Center(child: Text('Bank balance will reduce and card available limit will increase by this amount', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: KColors.faint, fontWeight: FontWeight.w500))),
                    ],
                  ),
                ),
                if (_cycles.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  const SectionLabel('Billing cycles'),
                  KCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (var i = 0; i < _cycles.length; i++) ...[
                          if (i > 0) const Divider(indent: 16, endIndent: 16),
                          ListRow(
                            leading: IconTile(_cycles[i].status == 'paid' ? Icons.check_rounded : Icons.schedule_rounded, tint: _cycles[i].status == 'paid' ? KColors.greenTint : KColors.redTint, iconColor: _cycles[i].status == 'paid' ? KColors.green : KColors.red),
                            title: 'Bill ${Dates.dMy.format(_cycles[i].cycleEnd)}',
                            subtitle: 'Due ${Dates.dMy.format(_cycles[i].dueDate)} · paid ${Money.plain(_cycles[i].paidAmount)}',
                            trailing: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                              Text(Money.plain(_cycles[i].amountDue), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                              Text(_cycles[i].status == 'paid' ? 'Paid' : 'Due', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _cycles[i].status == 'paid' ? KColors.green : KColors.red)),
                            ]),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _info(String label, String value) => KCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: KColors.muted)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ]),
      );

  String _ord(int d) {
    if (d >= 11 && d <= 13) return '${d}th';
    return switch (d % 10) { 1 => '${d}st', 2 => '${d}nd', 3 => '${d}rd', _ => '${d}th' };
  }

  String _daysLeft(DateTime d) {
    final n = d.difference(Dates.today()).inDays;
    if (n < 0) return '${-n} days overdue';
    if (n == 0) return 'due today';
    return '$n days left';
  }
}

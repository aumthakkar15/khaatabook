import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/account_service.dart';
import '../services/loan_service.dart';
import '../services/session.dart';
import '../theme.dart';
import '../utils/money.dart';
import '../widgets/common.dart';

/// Feature 8: loans list, loan form, loan detail with EMI schedule.
class LoansScreen extends StatefulWidget {
  const LoansScreen({super.key});
  @override
  State<LoansScreen> createState() => _LoansScreenState();
}

class _LoansScreenState extends State<LoansScreen> {
  List<LoanSummary> _loans = [];

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
    _loans = await LoanService.instance.all();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final base = Session.instance.base;
    final active = _loans.where((l) => l.loan.status == 'active').toList();
    final closed = _loans.where((l) => l.loan.status != 'active').toList();
    return Scaffold(
      body: Column(
        children: [
          NavyHeader(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(children: [BackButtonNavy(), SizedBox(width: 12), Text('Loans', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: KColors.white))]),
                const SizedBox(height: 16),
                Text('Total remaining · in $base', style: const TextStyle(fontSize: 13, color: KColors.onNavyMuted, fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                FutureBuilder<NetWorth>(
                  future: AccountService.instance.netWorth(),
                  builder: (_, s) => MoneyText(-(s.data?.loans ?? 0), code: base, size: 30, weight: FontWeight.w800, onNavy: true),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
              children: [
                if (_loans.isEmpty) const KCard(child: EmptyState(icon: Icons.account_balance_outlined, title: 'No loans', subtitle: 'Add a loan to track EMIs automatically')),
                for (final s in active) ...[_tile(s), const SizedBox(height: 10)],
                if (closed.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const SectionLabel('Closed'),
                  for (final s in closed) ...[_tile(s), const SizedBox(height: 10)],
                ],
              ],
            ),
          ),
          BottomButton(label: 'New loan', icon: Icons.add_rounded, onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LoanFormScreen()))),
        ],
      ),
    );
  }

  Widget _tile(LoanSummary s) {
    final cur = s.account?.currency;
    return KCard(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LoanDetailScreen(loanId: s.loan.id!))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconTile(Icons.account_balance_outlined, filled: s.loan.status == 'active'),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.loan.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  Text('${s.loan.lender.isEmpty ? '' : '${s.loan.lender} · '}${s.loan.ratePct}% p.a. · ${s.loan.months} months', style: const TextStyle(fontSize: 12, color: KColors.muted)),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                MoneyText(-s.remaining, code: cur),
                Text('EMI ${Money.plain(s.loan.emi)}', style: const TextStyle(fontSize: 11, color: KColors.muted)),
              ]),
            ],
          ),
          const SizedBox(height: 12),
          ProgressBar(s.progress, height: 6),
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('${s.paidCount} of ${s.emis.length} EMIs paid', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            Text(s.next == null ? 'Completed' : 'Next ${Dates.dMy.format(s.next!.dueDate)}', style: const TextStyle(fontSize: 12, color: KColors.muted)),
          ]),
        ],
      ),
    );
  }
}

class LoanFormScreen extends StatefulWidget {
  const LoanFormScreen({super.key});
  @override
  State<LoanFormScreen> createState() => _LoanFormScreenState();
}

class _LoanFormScreenState extends State<LoanFormScreen> {
  final _name = TextEditingController();
  final _lender = TextEditingController();
  final _amount = TextEditingController();
  final _rate = TextEditingController();
  final _months = TextEditingController();
  final _emi = TextEditingController();
  DateTime _start = Dates.today();
  int _emiDay = 5;
  Account? _account;
  List<Account> _accounts = [];
  bool _emiOverridden = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    AccountService.instance.all().then((l) {
      _accounts = l.where((a) => a.type != AccountType.cash).toList();
      _account = _accounts.firstOrNull;
      if (mounted) setState(() {});
    });
    for (final c in [_amount, _rate, _months]) {
      c.addListener(_recalc);
    }
  }

  void _recalc() {
    if (_emiOverridden) return;
    final p = Money.parse(_amount.text);
    final r = double.tryParse(_rate.text) ?? 0;
    final m = int.tryParse(_months.text) ?? 0;
    final e = LoanService.emi(p, r, m);
    _emi.text = e > 0 ? Money.plain(e) : '';
    setState(() {});
  }

  Future<void> _save() async {
    if (_account == null) {
      showMsg(context, 'Choose the bank or card the EMI is deducted from', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await LoanService.instance.create(Loan(
        name: _name.text.trim().isEmpty ? 'Loan' : _name.text.trim(),
        lender: _lender.text.trim(),
        principal: Money.parse(_amount.text),
        ratePct: double.tryParse(_rate.text) ?? 0,
        months: int.tryParse(_months.text) ?? 0,
        startDate: _start,
        emiDay: _emiDay,
        emi: Money.parse(_emi.text),
        accountId: _account!.id!,
      ));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showMsg(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Money.parse(_amount.text);
    final e = Money.parse(_emi.text);
    final m = int.tryParse(_months.text) ?? 0;
    final totalInterest = e > 0 && m > 0 ? e * m - p : 0.0;
    return Scaffold(
      backgroundColor: KColors.white,
      body: Column(
        children: [
          const NavyHeader(child: Row(children: [BackButtonNavy(), SizedBox(width: 12), Text('New loan', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: KColors.white))])),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                KTextField(controller: _name, label: 'Loan name', hint: 'e.g. Car loan', icon: Icons.label_outline, capitalization: TextCapitalization.words),
                const SizedBox(height: 14),
                KTextField(controller: _lender, label: 'Lender (optional)', hint: 'Bank or finance company', icon: Icons.account_balance_outlined, capitalization: TextCapitalization.words),
                const SizedBox(height: 14),
                KTextField(controller: _amount, label: 'Loan amount', hint: '60000', icon: Icons.payments_outlined, keyboard: const TextInputType.numberWithOptions(decimal: true)),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: KTextField(controller: _rate, label: 'Interest % per year', hint: '6.5', icon: Icons.percent_rounded, keyboard: const TextInputType.numberWithOptions(decimal: true))),
                  const SizedBox(width: 10),
                  Expanded(child: KTextField(controller: _months, label: 'Months', hint: '36', icon: Icons.calendar_month_outlined, keyboard: TextInputType.number)),
                ]),
                const SizedBox(height: 14),
                KTextField(
                  controller: _emi,
                  label: 'Monthly EMI ${_emiOverridden ? '(manual)' : '(auto-calculated)'}',
                  icon: Icons.calculate_outlined,
                  keyboard: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => _emiOverridden = true,
                  suffix: _emiOverridden
                      ? IconButton(icon: const Icon(Icons.refresh_rounded, color: KColors.muted), onPressed: () {
                          _emiOverridden = false;
                          _recalc();
                        })
                      : null,
                ),
                if (e > 0 && m > 0) ...[
                  const SizedBox(height: 6),
                  Text('Total payable ${Money.plain(e * m)} · interest ${Money.plain(totalInterest)}', style: const TextStyle(fontSize: 12, color: KColors.muted)),
                ],
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(
                    child: PickerField(
                      label: 'Start date',
                      value: Dates.dMy.format(_start),
                      icon: Icons.event_outlined,
                      onTap: () async {
                        final d = await showDatePicker(context: context, initialDate: _start, firstDate: DateTime(2000), lastDate: DateTime(2100));
                        if (d != null) setState(() => _start = DateTime(d.year, d.month, d.day));
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: PickerField(
                      label: 'EMI day of month',
                      value: 'Day $_emiDay',
                      icon: Icons.today_outlined,
                      onTap: () async {
                        final d = await pickFromSheet<int>(context, title: 'EMI day', items: List.generate(28, (i) => i + 1), tile: (d) => ListTile(title: Text('Day $d')));
                        if (d != null) setState(() => _emiDay = d);
                      },
                    ),
                  ),
                ]),
                const SizedBox(height: 14),
                const Text('Deduct EMI from', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                PickerField(
                  label: _account == null ? 'Bank account or credit card' : accountTypeLabel(_account!.type),
                  value: _account?.name ?? 'Choose account',
                  icon: _account == null ? Icons.account_balance_outlined : accountIcon(_account!.type),
                  highlighted: true,
                  onTap: () async {
                    final a = await pickFromSheet<Account>(context, title: 'Deduct EMI from', items: _accounts, tile: (a) => ListRow(leading: IconTile(accountIcon(a.type)), title: a.name, subtitle: '${accountTypeLabel(a.type)} · ${a.currency}'));
                    if (a != null) setState(() => _account = a);
                  },
                ),
                const SizedBox(height: 10),
                const Text('Each month on the EMI day an expense "Loan EMI" is posted to this account, the loan balance reduces and the EMI is marked paid. EMIs already due since the start date are posted immediately.', style: TextStyle(fontSize: 12, color: KColors.muted)),
              ],
            ),
          ),
          BottomButton(label: 'Create loan', icon: Icons.check_rounded, busy: _busy, onPressed: _save),
        ],
      ),
    );
  }
}

class LoanDetailScreen extends StatefulWidget {
  final int loanId;
  const LoanDetailScreen({super.key, required this.loanId});
  @override
  State<LoanDetailScreen> createState() => _LoanDetailScreenState();
}

class _LoanDetailScreenState extends State<LoanDetailScreen> {
  LoanSummary? _s;
  bool _all = false;

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
    _s = await LoanService.instance.get(widget.loanId);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    if (s == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final cur = s.account?.currency;
    final next = s.next;
    final emis = _all ? s.emis : _window(s);
    return Scaffold(
      body: Column(
        children: [
          NavyHeader(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const BackButtonNavy(),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(s.loan.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: KColors.white)),
                      Text('${s.loan.lender.isEmpty ? '' : '${s.loan.lender} · '}${s.loan.ratePct}% p.a. · ${s.loan.months} months', style: const TextStyle(fontSize: 12, color: KColors.onNavyMuted, fontWeight: FontWeight.w500)),
                    ]),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (v) async {
                      if (v == 'delete') {
                        final ok = await confirm(context, 'Delete loan?', 'All its EMI transactions will be removed and account balances restored.', okLabel: 'Delete', danger: true);
                        if (ok) {
                          await LoanService.instance.delete(s.loan.id!);
                          if (context.mounted) Navigator.pop(context);
                        }
                      } else if (v == 'close') {
                        await LoanService.instance.update(Loan.fromMap({...s.loan.toMap(), 'status': s.loan.status == 'active' ? 'closed' : 'active'}));
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(value: 'close', child: Text(s.loan.status == 'active' ? 'Mark as closed' : 'Reopen')),
                      const PopupMenuItem(value: 'delete', child: Text('Delete loan', style: TextStyle(color: KColors.red))),
                    ],
                    child: const HeaderButton(icon: Icons.more_horiz_rounded),
                  ),
                ]),
                const SizedBox(height: 18),
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Remaining balance', style: TextStyle(fontSize: 12, color: KColors.onNavyMuted, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 3),
                      MoneyText(-s.remaining, code: cur, size: 30, weight: FontWeight.w800, onNavy: true),
                    ]),
                  ),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    const Text('Loan amount', style: TextStyle(fontSize: 12, color: KColors.onNavyMuted, fontWeight: FontWeight.w500)),
                    Text(Money.plain(s.loan.principal), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: KColors.white)),
                  ]),
                ]),
                const SizedBox(height: 10),
                ProgressBar(s.progress, color: KColors.white, track: Colors.white.withOpacity(0.16)),
                const SizedBox(height: 8),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('${s.paidCount} of ${s.emis.length} EMIs paid · ${(s.progress * 100).round()}%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: KColors.white)),
                  Text('Ends ${Dates.mY.format(s.endDate)}', style: const TextStyle(fontSize: 12, color: KColors.onNavyMuted, fontWeight: FontWeight.w500)),
                ]),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
              children: [
                Row(children: [
                  Expanded(child: _fig('Monthly EMI', Money.plain(s.loan.emi))),
                  const SizedBox(width: 10),
                  Expanded(child: _fig('Paid so far', Money.plain(s.paidTotal), color: KColors.green)),
                  const SizedBox(width: 10),
                  Expanded(child: _fig('Interest paid', Money.plain(s.interestPaid))),
                ]),
                const SizedBox(height: 12),
                KCard(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(children: [
                    IconTile(s.account == null ? Icons.account_balance_outlined : accountIcon(s.account!.type)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Deducts from ${s.account?.name ?? 'account'}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                        Text('Every month on the ${s.loan.emiDay}${next == null ? '' : ' · next ${Dates.dMy.format(next.dueDate)}'}', style: const TextStyle(fontSize: 12, color: KColors.muted)),
                      ]),
                    ),
                    if (next != null && s.loan.status == 'active')
                      Pill('Pay now', selected: true, onTap: () async {
                        final ok = await confirm(context, 'Pay EMI ${next.no} now?', '${Money.format(next.amount, code: cur)} will be deducted from ${s.account?.name ?? 'the account'} today.', okLabel: 'Pay');
                        if (ok) await LoanService.instance.payEmi(next, date: Dates.today());
                      }),
                  ]),
                ),
                const SizedBox(height: 18),
                SectionTitle('EMI schedule', action: _all ? 'Show less' : 'View all ${s.emis.length}', onAction: () => setState(() => _all = !_all)),
                const SizedBox(height: 10),
                KCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (var i = 0; i < emis.length; i++) ...[
                        if (i > 0) const Divider(indent: 16, endIndent: 16),
                        _emiRow(emis[i], isNext: next?.id == emis[i].id),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<LoanEmi> _window(LoanSummary s) {
    final i = s.emis.indexWhere((e) => !e.paid);
    if (i < 0) return s.emis.length > 4 ? s.emis.sublist(s.emis.length - 4) : s.emis;
    final start = (i - 2).clamp(0, s.emis.length);
    final end = (i + 2).clamp(0, s.emis.length);
    return s.emis.sublist(start, end);
  }

  Widget _fig(String label, String v, {Color? color}) => KCard(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: KColors.muted)),
          const SizedBox(height: 2),
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(v, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: color ?? KColors.navy))),
        ]),
      );

  Widget _emiRow(LoanEmi e, {bool isNext = false}) {
    final future = !e.paid && !isNext;
    return Container(
      color: isNext ? const Color(0xFFF9FBFE) : null,
      child: ListRow(
        leading: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: e.paid ? KColors.greenTint : (isNext ? Colors.transparent : KColors.offWhite),
            border: isNext ? Border.all(color: KColors.navy, width: 2) : null,
          ),
          child: e.paid ? const Icon(Icons.check_rounded, size: 18, color: KColors.green) : Text('${e.no}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: future ? KColors.faint : KColors.navy)),
        ),
        title: 'EMI ${e.no} · ${Dates.dMy.format(e.dueDate)}',
        subtitle: 'Principal ${Money.plain(e.principal)} · Interest ${Money.plain(e.interest)}',
        dim: future,
        trailing: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(Money.plain(e.amount), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: future ? KColors.faint : KColors.navy)),
          Text(e.paid ? 'Paid' : (isNext ? 'Upcoming' : ''), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: e.paid ? KColors.green : KColors.amber)),
        ]),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/account_service.dart';
import '../services/currency_service.dart';
import '../services/excel_io.dart';
import '../services/loan_service.dart';
import '../services/session.dart';
import '../theme.dart';
import '../utils/money.dart';
import '../widgets/common.dart';
import 'account_form_screen.dart';
import 'credit_card_screen.dart';
import 'loans_screen.dart';

/// Features 5, 10, 11: accounts grouped by type, consolidated balance,
/// archive, Excel import.
class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});
  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  List<Account> _all = [];
  List<LoanSummary> _loans = [];
  NetWorth? _nw;
  bool _showArchived = false;

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
    _all = await AccountService.instance.all(includeArchived: true);
    _loans = await LoanService.instance.all(activeOnly: true);
    _nw = await AccountService.instance.netWorth();
    if (mounted) setState(() {});
  }

  Future<void> _import() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.upload_file_outlined), title: const Text('Import accounts from Excel'), onTap: () => Navigator.pop(c, 'import')),
          ListTile(leading: const Icon(Icons.description_outlined), title: const Text('Get the Excel template'), onTap: () => Navigator.pop(c, 'template')),
        ]),
      ),
    );
    if (choice == 'template') {
      final f = await AccountService.instance.template();
      await ExcelIO.share(f, text: 'Khaata Book – accounts template');
    } else if (choice == 'import') {
      final x = await ExcelIO.pick();
      if (x == null) return;
      final s = await AccountService.instance.importExcel(x);
      if (mounted) _showSummary(s.toString(), s.errors);
    }
  }

  void _showSummary(String summary, List<String> errors) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Import finished', style: TextStyle(fontWeight: FontWeight.w800)),
        content: SingleChildScrollView(child: Text([summary, ...errors].join('\n'))),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
      ),
    );
  }

  Future<void> _actions(Account a) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(a.name, style: const TextStyle(fontWeight: FontWeight.w800))),
          ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Edit'), onTap: () => Navigator.pop(c, 'edit')),
          ListTile(
            leading: Icon(a.archived ? Icons.unarchive_outlined : Icons.archive_outlined),
            title: Text(a.archived ? 'Reactivate' : 'Mark inactive (archive)'),
            onTap: () => Navigator.pop(c, 'archive'),
          ),
          ListTile(leading: const Icon(Icons.delete_outline, color: KColors.red), title: const Text('Delete', style: TextStyle(color: KColors.red)), onTap: () => Navigator.pop(c, 'delete')),
        ]),
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'edit':
        Navigator.push(context, MaterialPageRoute(builder: (_) => AccountFormScreen(existing: a)));
      case 'archive':
        if (!a.archived && a.balance.abs() > 0.004) {
          final ok = await confirm(context, 'Account still has a balance', '${a.name} has ${Money.format(a.balance, code: a.currency)}. Archive it anyway? History is kept and you can reactivate later.', okLabel: 'Archive');
          if (!ok) return;
        }
        await AccountService.instance.setArchived(a.id!, !a.archived);
      case 'delete':
        final ok = await confirm(context, 'Delete ${a.name}?', 'Only possible when the account has no transactions. Otherwise archive it instead.', okLabel: 'Delete', danger: true);
        if (!ok) return;
        final done = await AccountService.instance.delete(a.id!);
        if (mounted) showMsg(context, done ? 'Account deleted' : 'This account has transactions — archive it instead', error: !done);
    }
  }

  @override
  Widget build(BuildContext context) {
    final base = Session.instance.base;
    final active = _all.where((a) => !a.archived).toList();
    final archived = _all.where((a) => a.archived).toList();
    Widget group(String title, AccountType type, {bool card = false}) {
      final list = active.where((a) => a.type == type).toList();
      if (list.isEmpty) return const SizedBox();
      final sum = list.fold<double>(0, (s, a) => s + (card ? -a.outstanding : a.balance));
      final sameCur = list.every((a) => a.currency == list.first.currency);
      return Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionLabel(title, trailing: sameCur ? Text(card ? '${Money.format(sum)} due' : Money.format(sum), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: sum < -0.004 ? KColors.red : KColors.muted)) : null),
            KCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < list.length; i++) ...[
                    if (i > 0) const Divider(indent: 16, endIndent: 16),
                    _row(list[i], base),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: Column(
        children: [
          NavyHeader(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const BackButtonNavy(),
                    const SizedBox(width: 12),
                    const Expanded(child: Text('Accounts', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: KColors.white, letterSpacing: -0.3))),
                    Pill('Import Excel', onNavy: true, selected: true, icon: Icons.upload_file_outlined, onTap: _import),
                  ],
                ),
                const SizedBox(height: 14),
                Text('Consolidated balance · in $base', style: const TextStyle(fontSize: 13, color: KColors.onNavyMuted, fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                MoneyText(_nw?.total ?? 0, code: base, size: 32, weight: FontWeight.w800, onNavy: true),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(child: _chip('Cash + Bank', _nw?.cashBank ?? 0)),
                    const SizedBox(width: 10),
                    Expanded(child: _chip('Card due + Loans', -(_nw?.liabilities ?? 0))),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 100),
              children: [
                if (active.isEmpty && _loans.isEmpty)
                  const KCard(child: EmptyState(icon: Icons.account_balance_wallet_outlined, title: 'No accounts yet', subtitle: 'Add your cash wallet, bank accounts and credit cards')),
                group('Cash', AccountType.cash),
                group('Bank accounts', AccountType.bank),
                group('Credit cards', AccountType.card, card: true),
                if (_loans.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SectionLabel('Loans', trailing: GestureDetector(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LoansScreen())), child: const Text('Manage', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: KColors.navyMid)))),
                        KCard(
                          padding: EdgeInsets.zero,
                          child: Column(
                            children: [
                              for (var i = 0; i < _loans.length; i++) ...[
                                if (i > 0) const Divider(indent: 16, endIndent: 16),
                                ListRow(
                                  leading: const IconTile(Icons.account_balance_outlined),
                                  title: '${_loans[i].loan.name}${_loans[i].loan.lender.isEmpty ? '' : ' · ${_loans[i].loan.lender}'}',
                                  subtitle: '${_loans[i].paidCount} of ${_loans[i].emis.length} EMIs paid${_loans[i].next == null ? '' : ' · next ${Dates.dM.format(_loans[i].next!.dueDate)}'}',
                                  trailing: MoneyText(-_loans[i].remaining, code: _loans[i].account?.currency),
                                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LoanDetailScreen(loanId: _loans[i].loan.id!))),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                if (archived.isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InkWell(
                        onTap: () => setState(() => _showArchived = !_showArchived),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(children: [
                            Icon(_showArchived ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: KColors.muted),
                            const SizedBox(width: 6),
                            Text('${_showArchived ? 'Hide' : 'Show'} archived (${archived.length})', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: KColors.muted)),
                          ]),
                        ),
                      ),
                      if (_showArchived)
                        KCard(
                          padding: EdgeInsets.zero,
                          child: Column(
                            children: [
                              for (var i = 0; i < archived.length; i++) ...[
                                if (i > 0) const Divider(indent: 16, endIndent: 16),
                                _row(archived[i], base),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
          BottomButton(label: 'Add account', icon: Icons.add_rounded, onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AccountFormScreen()))),
        ],
      ),
    );
  }

  Widget _chip(String label, double v) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.10), borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: KColors.onNavyMuted, fontWeight: FontWeight.w500)),
          const SizedBox(height: 2),
          MoneyText(v, size: 14, onNavy: true),
        ],
      ),
    );
  }

  Widget _row(Account a, String base) {
    final sub = [accountTypeLabel(a.type), a.currency, if (a.last4 != null && a.last4!.isNotEmpty) '••••${a.last4}', if (a.archived) 'Archived'].join(' · ');
    Widget trailing;
    if (a.isCard) {
      trailing = Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          MoneyText(-a.outstanding, code: null),
          Text('${(a.utilization * 100).round()}% of ${Money.plain(a.creditLimit, decimals: 0)}', style: const TextStyle(fontSize: 11, color: KColors.muted)),
        ],
      );
    } else if (a.currency != base) {
      trailing = Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          MoneyText(a.balance, code: a.currency),
          FutureBuilder<double>(
            future: _toBase(a),
            builder: (_, s) => Text(s.hasData ? '≈ $base ${Money.plain(s.data!)}' : '', style: const TextStyle(fontSize: 11, color: KColors.muted)),
          ),
        ],
      );
    } else {
      trailing = MoneyText(a.balance);
    }
    return ListRow(
      leading: IconTile(accountIcon(a.type), filled: !a.archived && a.type == AccountType.bank && a.balance >= 0),
      title: a.name,
      subtitle: sub,
      trailing: trailing,
      dim: a.archived,
      onTap: () {
        if (a.isCard) {
          Navigator.push(context, MaterialPageRoute(builder: (_) => CreditCardScreen(accountId: a.id!)));
        } else {
          Navigator.push(context, MaterialPageRoute(builder: (_) => AccountFormScreen(existing: a)));
        }
      },
      onLongPress: () => _actions(a),
    );
  }

  Future<double> _toBase(Account a) async {
    try {
      return await CurrencyService.instance.toBase(a.balance, a.currency);
    } catch (_) {
      return 0;
    }
  }
}

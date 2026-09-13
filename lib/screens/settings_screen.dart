import 'package:flutter/material.dart';

import '../db/database.dart';
import '../services/auth_service.dart';
import '../services/excel_io.dart';
import '../services/session.dart';
import '../services/transaction_service.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'accounts_screen.dart';
import 'backup_screen.dart';
import 'categories_screen.dart';
import 'currencies_screen.dart';
import 'loans_screen.dart';
import 'recurring_screen.dart';

/// Settings: profile, fingerprint, password, reminders, masters, backup, import.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _bioAvailable = false;
  int _remindDays = 3;

  @override
  void initState() {
    super.initState();
    Session.instance.addListener(_refresh);
    _load();
  }

  @override
  void dispose() {
    Session.instance.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() => setState(() {});

  Future<void> _load() async {
    _bioAvailable = await AuthService.instance.biometricAvailable();
    _remindDays = int.tryParse(await AppDb.instance.getSetting('remind_days_before') ?? '3') ?? 3;
    if (mounted) setState(() {});
  }

  Future<void> _toggleBio(bool v) async {
    try {
      await AuthService.instance.setBiometric(v);
      if (mounted) showMsg(context, v ? 'Fingerprint login enabled' : 'Fingerprint login turned off');
    } catch (e) {
      if (mounted) showMsg(context, e.toString(), error: true);
    }
  }

  Future<void> _changePassword() async {
    final cur = await promptText(context, 'Current password', obscure: true, okLabel: 'Next');
    if (cur == null || !mounted) return;
    final next = await promptText(context, 'New password', hint: 'Minimum 6 characters', obscure: true, okLabel: 'Change');
    if (next == null || !mounted) return;
    try {
      await AuthService.instance.changePassword(cur, next);
      if (mounted) showMsg(context, 'Password changed');
    } catch (e) {
      if (mounted) showMsg(context, e.toString(), error: true);
    }
  }

  Future<void> _importTransactions() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.upload_file_outlined), title: const Text('Import transactions & transfers from Excel'), onTap: () => Navigator.pop(c, 'import')),
          ListTile(leading: const Icon(Icons.description_outlined), title: const Text('Get the Excel template'), onTap: () => Navigator.pop(c, 'template')),
        ]),
      ),
    );
    if (choice == 'template') {
      final f = await TransactionService.instance.transactionsTemplate();
      await ExcelIO.share(f, text: 'Khaata Book – transactions template');
    } else if (choice == 'import') {
      final x = await ExcelIO.pick();
      if (x == null) return;
      final s = await TransactionService.instance.importExcel(x);
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Import finished', style: TextStyle(fontWeight: FontWeight.w800)),
          content: SingleChildScrollView(child: Text([s.toString(), ...s.errors].join('\n'))),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = Session.instance.user;
    return Column(
      children: [
        NavyHeader(
          child: Row(children: [
            Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: KColors.white, borderRadius: BorderRadius.circular(16)),
              child: Text((u?.name ?? 'K').trim().isEmpty ? 'K' : u!.name.trim().substring(0, 1).toUpperCase(), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: KColors.navy)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(u?.name ?? '', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: KColors.white)),
                Text('${u?.loginId ?? ''} · ${u?.country ?? ''} · ${u?.baseCurrency ?? ''}', style: const TextStyle(fontSize: 12, color: KColors.onNavyMuted, fontWeight: FontWeight.w500)),
              ]),
            ),
          ]),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
            children: [
              const SectionLabel('Security'),
              KCard(
                padding: EdgeInsets.zero,
                child: Column(children: [
                  ListRow(
                    leading: const IconTile(Icons.fingerprint_rounded),
                    title: 'Fingerprint login',
                    subtitle: _bioAvailable ? 'Sign in without typing the password' : 'No fingerprint set up on this phone',
                    trailing: Switch(value: u?.biometric ?? false, onChanged: _bioAvailable ? _toggleBio : null),
                  ),
                  const Divider(indent: 16, endIndent: 16),
                  ListRow(leading: const IconTile(Icons.lock_outline), title: 'Change password', trailing: const Icon(Icons.chevron_right_rounded, color: KColors.faint), onTap: _changePassword),
                ]),
              ),
              const SizedBox(height: 16),
              const SectionLabel('Masters'),
              KCard(
                padding: EdgeInsets.zero,
                child: Column(children: [
                  _nav(Icons.account_balance_wallet_outlined, 'Accounts', 'Cash, bank, credit cards', const AccountsScreen()),
                  const Divider(indent: 16, endIndent: 16),
                  _nav(Icons.sell_outlined, 'Categories', 'Expense & income, sub-categories', const CategoriesScreen()),
                  const Divider(indent: 16, endIndent: 16),
                  _nav(Icons.currency_exchange_rounded, 'Currencies', 'Rates · online sync · manual', const CurrenciesScreen()),
                  const Divider(indent: 16, endIndent: 16),
                  _nav(Icons.account_balance_outlined, 'Loans', 'EMI schedules', const LoansScreen()),
                  const Divider(indent: 16, endIndent: 16),
                  _nav(Icons.repeat_rounded, 'Recurring transactions', 'Monthly, weekly, yearly', const RecurringScreen()),
                ]),
              ),
              const SizedBox(height: 16),
              const SectionLabel('Data'),
              KCard(
                padding: EdgeInsets.zero,
                child: Column(children: [
                  _nav(Icons.backup_outlined, 'Backup & restore', 'Phone · Google Drive · Excel · automatic', const BackupScreen()),
                  const Divider(indent: 16, endIndent: 16),
                  ListRow(leading: const IconTile(Icons.upload_file_outlined), title: 'Import transactions from Excel', subtitle: 'Expenses, income and transfers', trailing: const Icon(Icons.chevron_right_rounded, color: KColors.faint), onTap: _importTransactions),
                ]),
              ),
              const SizedBox(height: 16),
              const SectionLabel('Reminders'),
              KCard(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Row(children: [
                  const IconTile(Icons.notifications_outlined),
                  const SizedBox(width: 12),
                  const Expanded(child: Text('Card due reminder', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
                  for (final d in [1, 3, 5, 7]) ...[
                    Pill('${d}d', selected: _remindDays == d, onTap: () async {
                      await AppDb.instance.setSetting('remind_days_before', d.toString());
                      setState(() => _remindDays = d);
                    }),
                    const SizedBox(width: 4),
                  ],
                ]),
              ),
              const SizedBox(height: 4),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Text('Days before the due date to remind you (plus a reminder on the day). Loan EMIs and recurring postings also notify on their day.', style: TextStyle(fontSize: 12, color: KColors.muted))),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: () async {
                  final ok = await confirm(context, 'Sign out?', 'Your data stays on this phone.', okLabel: 'Sign out');
                  if (ok) AuthService.instance.signOut();
                },
                icon: const Icon(Icons.logout_rounded, size: 20),
                label: const Text('Sign out'),
              ),
              const SizedBox(height: 12),
              const Center(child: Text('Khaata Book 1.0 · all data stays on this phone', style: TextStyle(fontSize: 12, color: KColors.faint))),
            ],
          ),
        ),
      ],
    );
  }

  Widget _nav(IconData icon, String title, String subtitle, Widget screen) => ListRow(
        leading: IconTile(icon),
        title: title,
        subtitle: subtitle,
        trailing: const Icon(Icons.chevron_right_rounded, color: KColors.faint),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => screen)),
      );
}

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/account_service.dart';
import '../services/card_service.dart';
import '../services/category_service.dart';
import '../services/loan_service.dart';
import '../services/session.dart';
import '../services/transaction_service.dart';
import '../theme.dart';
import '../utils/money.dart';
import '../widgets/common.dart';
import 'accounts_screen.dart';
import 'categories_screen.dart';
import 'credit_card_screen.dart';
import 'loans_screen.dart';
import 'recurring_screen.dart';
import 'transaction_tile.dart';

/// Home (design Option A): navy header with consolidated balance,
/// income/expense card, quick actions, due reminders, recent transactions.
class DashboardScreen extends StatefulWidget {
  final VoidCallback onSeeAll;
  const DashboardScreen({super.key, required this.onSeeAll});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  NetWorth? _nw;
  double _income = 0, _expense = 0;
  List<Tx> _recent = [];
  Map<int, Account> _accounts = {};
  Map<int, Category> _cats = {};
  List<(Account, CardCycle)> _cardDue = [];
  List<(Loan, LoanEmi)> _emis = [];

  @override
  void initState() {
    super.initState();
    DataBus.instance.addListener(_load);
    Session.instance.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    DataBus.instance.removeListener(_load);
    Session.instance.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, 1);
    final to = DateTime(now.year, now.month + 1, 0);
    final nw = await AccountService.instance.netWorth();
    final t = await TransactionService.instance.totals(from, to);
    final recent = await TransactionService.instance.list(TxFilter(), limit: 5);
    final accounts = await AccountService.instance.map();
    final cats = await CategoryService.instance.map();
    final due = await CardService.instance.allDue();
    final emis = await LoanService.instance.upcoming(days: 7);
    if (!mounted) return;
    setState(() {
      _nw = nw;
      _income = t.income;
      _expense = t.expense;
      _recent = recent;
      _accounts = accounts;
      _cats = cats;
      _cardDue = [for (final c in due) if (accounts[c.accountId] != null) (accounts[c.accountId]!, c)];
      _emis = emis;
    });
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final base = Session.instance.base;
    final user = Session.instance.user;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          Stack(
            children: [
              NavyHeader(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 88),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(color: KColors.white, borderRadius: BorderRadius.circular(14)),
                          child: const Icon(Icons.menu_book_rounded, color: KColors.navy),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_greeting(), style: const TextStyle(fontSize: 13, color: KColors.onNavyMuted, fontWeight: FontWeight.w500)),
                              Text(user?.name ?? 'Khaata Book', style: const TextStyle(fontSize: 17, color: KColors.white, fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                        HeaderButton(
                          icon: Icons.repeat_rounded,
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RecurringScreen())),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Text('Total balance · ${Dates.mY.format(DateTime.now())}', style: const TextStyle(fontSize: 13, color: KColors.onNavyMuted, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 6),
                    MoneyText(_nw?.total ?? 0, code: base, size: 36, weight: FontWeight.w800, onNavy: true),
                    if (_nw != null && _nw!.liabilities > 0) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Cash + bank ${Money.plain(_nw!.cashBank)} · Cards & loans - ${Money.plain(_nw!.liabilities)}',
                        style: const TextStyle(fontSize: 12, color: KColors.onNavyMuted, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ],
                ),
              ),
              Positioned(
                left: 20,
                right: 20,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                  decoration: BoxDecoration(
                    color: KColors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: KColors.navy.withOpacity(0.12), blurRadius: 30, offset: const Offset(0, 10))],
                  ),
                  child: Row(
                    children: [
                      Expanded(child: _stat(Icons.arrow_upward_rounded, KColors.green, KColors.greenTint, 'Income', _income)),
                      Container(width: 1, height: 40, color: KColors.line),
                      const SizedBox(width: 16),
                      Expanded(child: _stat(Icons.arrow_downward_rounded, KColors.red, KColors.redTint, 'Expenses', _expense)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                _quick(Icons.account_balance_wallet_outlined, 'Accounts', () => _go(const AccountsScreen()), filled: true),
                _quick(Icons.credit_card_outlined, 'Cards', _openCards),
                _quick(Icons.account_balance_outlined, 'Loans', () => _go(const LoansScreen())),
                _quick(Icons.sell_outlined, 'Categories', () => _go(const CategoriesScreen())),
              ],
            ),
          ),
          if (_cardDue.isNotEmpty || _emis.isNotEmpty) ...[
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionTitle('Upcoming payments'),
                  const SizedBox(height: 12),
                  KCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (final (card, cy) in _cardDue)
                          ListRow(
                            leading: const IconTile(Icons.credit_card_outlined, tint: KColors.redTint, iconColor: KColors.red),
                            title: '${card.name} · card payment',
                            subtitle: 'Due ${Dates.dMy.format(cy.dueDate)} · ${_daysLeft(cy.dueDate)}',
                            trailing: MoneyText(-cy.remaining, code: card.currency),
                            onTap: () => _go(CreditCardScreen(accountId: card.id!)),
                          ),
                        for (final (loan, emi) in _emis)
                          ListRow(
                            leading: const IconTile(Icons.account_balance_outlined),
                            title: '${loan.name} · EMI ${emi.no}',
                            subtitle: 'Due ${Dates.dMy.format(emi.dueDate)} · from ${_accounts[loan.accountId]?.name ?? ''}',
                            trailing: MoneyText(-emi.amount, code: _accounts[loan.accountId]?.currency),
                            onTap: () => _go(const LoansScreen()),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionTitle('Recent transactions', action: 'See all', onAction: widget.onSeeAll),
                const SizedBox(height: 12),
                if (_recent.isEmpty)
                  const KCard(child: EmptyState(icon: Icons.receipt_long_outlined, title: 'No transactions yet', subtitle: 'Tap + to add your first expense or income'))
                else
                  KCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (var i = 0; i < _recent.length; i++) ...[
                          if (i > 0) const Divider(indent: 16, endIndent: 16),
                          TransactionTile(tx: _recent[i], accounts: _accounts, cats: _cats),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  String _daysLeft(DateTime d) {
    final n = d.difference(Dates.today()).inDays;
    if (n < 0) return 'overdue';
    if (n == 0) return 'today';
    return '$n days left';
  }

  void _go(Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w));

  Future<void> _openCards() async {
    final cards = await AccountService.instance.all(type: AccountType.card);
    if (!mounted) return;
    if (cards.isEmpty) {
      _go(const AccountsScreen());
      return;
    }
    if (cards.length == 1) {
      _go(CreditCardScreen(accountId: cards.first.id!));
      return;
    }
    final c = await pickFromSheet<Account>(
      context,
      title: 'Choose a card',
      items: cards,
      tile: (a) => ListRow(leading: const IconTile(Icons.credit_card_outlined), title: a.name, subtitle: 'Available ${Money.plain(a.availableLimit)} of ${Money.plain(a.creditLimit)}'),
    );
    if (c != null) _go(CreditCardScreen(accountId: c.id!));
  }

  Widget _stat(IconData icon, Color color, Color tint, String label, double value) {
    return Row(
      children: [
        IconTile(icon, size: 40, tint: tint, iconColor: color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 12, color: KColors.muted, fontWeight: FontWeight.w500)),
              Text(Money.plain(value), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _quick(IconData icon, String label, VoidCallback onTap, {bool filled = false}) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: filled ? KColors.navy : KColors.white,
                borderRadius: BorderRadius.circular(18),
                border: filled ? null : Border.all(color: KColors.line),
              ),
              child: Icon(icon, color: filled ? KColors.white : KColors.navy, size: 24),
            ),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

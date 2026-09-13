import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../services/account_service.dart';
import '../services/category_service.dart';
import '../services/currency_service.dart';
import '../services/recurring_service.dart';
import '../services/session.dart';
import '../services/transaction_service.dart';
import '../theme.dart';
import '../utils/money.dart';
import '../widgets/common.dart';
import 'categories_screen.dart';

/// Feature 12 (+9, 14): everything on one screen — type, amount & currency,
/// account chips, category grid, sub-category chips, date, note, repeat.
class AddTransactionScreen extends StatefulWidget {
  final Tx? existing;
  final TxType? initialType;
  const AddTransactionScreen({super.key, this.existing, this.initialType});
  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  TxType _type = TxType.expense;
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String _currency = Session.instance.base;
  List<Account> _accounts = [];
  Account? _account;
  Account? _toAccount;
  List<Category> _cats = [];
  List<Category> _subs = [];
  Category? _cat;
  Category? _sub;
  DateTime _date = Dates.today();
  bool _busy = false;
  double _entered = 0;

  // Repeat (recurring)
  bool _repeat = false;
  String _freq = 'monthly';
  int? _months;

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _type = widget.existing?.type ?? widget.initialType ?? TxType.expense;
    _amount.addListener(() => setState(() => _entered = Money.parse(_amount.text)));
    _load();
  }

  Future<void> _load() async {
    _accounts = await AccountService.instance.all();
    final prefs = await SharedPreferences.getInstance();
    if (_editing) {
      final t = widget.existing!;
      _amount.text = Money.plain(t.amount);
      _note.text = t.note ?? '';
      _currency = t.currency;
      _date = t.date;
      final all = await AccountService.instance.map();
      _account = all[t.accountId];
      _toAccount = t.toAccountId == null ? null : all[t.toAccountId!];
    } else {
      final lastId = prefs.getInt('last_account_id');
      _account = _accounts.where((a) => a.id == lastId).firstOrNull ?? _accounts.firstOrNull;
    }
    await _loadCats(keepSelection: _editing);
    if (mounted) setState(() {});
  }

  Future<void> _loadCats({bool keepSelection = false}) async {
    if (_type == TxType.transfer) return;
    _cats = await CategoryService.instance.mostUsed(_type);
    if (keepSelection && widget.existing != null) {
      final all = await CategoryService.instance.map();
      _cat = all[widget.existing!.categoryId ?? -1];
      _sub = all[widget.existing!.subcategoryId ?? -1];
    } else {
      final prefs = await SharedPreferences.getInstance();
      final lastCat = prefs.getInt('last_cat_${_type.name}');
      _cat = _cats.where((c) => c.id == lastCat).firstOrNull ?? _cats.firstOrNull;
      _sub = null;
    }
    _subs = _cat == null ? [] : await CategoryService.instance.subs(_cat!.id!);
    if (_sub != null && !_subs.any((s) => s.id == _sub!.id)) _sub = null;
  }

  Future<void> _selectCat(Category c) async {
    _cat = c;
    _sub = null;
    _subs = await CategoryService.instance.subs(c.id!);
    setState(() {});
  }

  Future<void> _pickAllCategories() async {
    final all = await CategoryService.instance.top(_type);
    if (!mounted) return;
    final c = await pickFromSheet<Category>(
      context,
      title: _type == TxType.income ? 'Income categories' : 'Expense categories',
      items: all,
      tile: (c) => ListRow(leading: IconTile(CategoryIcons.of(c.icon)), title: c.name),
    );
    if (c != null) await _selectCat(c);
  }

  Future<void> _pickCurrency() async {
    final list = await CurrencyService.instance.all();
    if (!mounted) return;
    final inUse = list.where((c) => c.inUse).toList();
    final rest = list.where((c) => !c.inUse).toList();
    final c = await pickFromSheet<Currency>(
      context,
      title: 'Currency',
      items: [...inUse, ...rest],
      tile: (c) => ListRow(
        leading: Container(
          width: 46,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: c.inUse ? KColors.navy : KColors.tint, borderRadius: BorderRadius.circular(12)),
          child: Text(c.code, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: c.inUse ? KColors.white : KColors.navy)),
        ),
        title: c.name,
        subtitle: c.rate > 0 ? '1 ${Session.instance.base} = ${Money.rate(c.rate)} ${c.code}' : 'No rate yet — sync or enter manually',
      ),
    );
    if (c != null) setState(() => _currency = c.code);
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2000), lastDate: DateTime(2100));
    if (d != null) setState(() => _date = DateTime(d.year, d.month, d.day));
  }

  Future<void> _pickAccount({bool to = false}) async {
    final a = await pickFromSheet<Account>(
      context,
      title: to ? 'To account' : (_type == TxType.income ? 'Received in' : 'Paid from'),
      items: _accounts,
      tile: (a) => ListRow(
        leading: IconTile(accountIcon(a.type)),
        title: a.name,
        subtitle: '${accountTypeLabel(a.type)} · ${a.currency}',
        trailing: a.isCard ? Text('Avail. ${Money.plain(a.availableLimit)}', style: const TextStyle(fontSize: 12, color: KColors.muted)) : MoneyText(a.balance, size: 14),
      ),
    );
    if (a != null) setState(() => to ? _toAccount = a : _account = a);
  }

  Future<void> _save() async {
    if (_account == null) {
      showMsg(context, 'Add an account first (Home → Accounts)', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final svc = TransactionService.instance;
      final tx = await svc.build(
        id: widget.existing?.id,
        type: _type,
        date: _date,
        amount: Money.parse(_amount.text),
        currency: _currency,
        account: _account!,
        toAccount: _type == TxType.transfer ? _toAccount : null,
        categoryId: _cat?.id,
        subcategoryId: _sub?.id,
        note: _note.text,
        source: widget.existing?.source ?? 'manual',
        refId: widget.existing?.refId,
      );
      if (_editing) {
        await svc.update(tx);
      } else {
        await svc.insert(tx);
        if (_repeat && (_months == null || _months! > 1)) {
          final start = RecurringService.nextAfter(
            Recurring(type: _type, name: _note.text.isEmpty ? (_cat?.name ?? 'Recurring') : _note.text, amount: tx.amount, currency: _currency, accountId: _account!.id!, day: _freq == 'weekly' ? _date.weekday : _date.day, startDate: _date, nextDate: _date, frequency: _freq),
            _date,
          );
          await RecurringService.instance.create(Recurring(
            type: _type,
            name: _note.text.isEmpty ? (_cat?.name ?? 'Recurring') : _note.text,
            amount: tx.amount,
            currency: _currency,
            accountId: _account!.id!,
            toAccountId: _toAccount?.id,
            categoryId: _cat?.id,
            subcategoryId: _sub?.id,
            frequency: _freq,
            day: _freq == 'weekly' ? _date.weekday : _date.day,
            startDate: _date,
            totalCount: _months == null ? null : _months! - 1, // first one already posted now
            postedCount: 0,
            nextDate: start,
            note: _note.text.isEmpty ? null : _note.text,
          ));
        }
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('last_account_id', _account!.id!);
      if (_cat != null) await prefs.setInt('last_cat_${_type.name}', _cat!.id!);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showMsg(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTransfer = _type == TxType.transfer;
    return Scaffold(
      backgroundColor: KColors.white,
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                children: [
                  const BackButtonNavy(onNavy: false),
                  Expanded(child: Center(child: Text(_editing ? 'Edit transaction' : 'Add transaction', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)))),
                  const SizedBox(width: 44),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(0, 16, 0, 24),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Segmented<TxType>(
                    values: TxType.values,
                    value: _type,
                    label: (t) => switch (t) { TxType.expense => 'Expense', TxType.income => 'Income', TxType.transfer => 'Transfer' },
                    onChanged: _editing
                        ? (_) {}
                        : (t) async {
                            _type = t;
                            await _loadCats();
                            setState(() {});
                          },
                  ),
                ),
                const SizedBox(height: 18),
                // Amount + currency
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      InkWell(
                        onTap: _pickCurrency,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          height: 40,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(color: KColors.tint, borderRadius: BorderRadius.circular(12)),
                          child: Row(children: [
                            Text(_currency, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                            const Icon(Icons.expand_more_rounded, size: 16, color: KColors.navy),
                          ]),
                        ),
                      ),
                      const SizedBox(width: 10),
                      IntrinsicWidth(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minWidth: 120, maxWidth: 240),
                          child: TextField(
                            controller: _amount,
                            autofocus: !_editing,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w800, letterSpacing: -1.5, color: KColors.navy),
                            decoration: const InputDecoration(
                              hintText: '0.00',
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              contentPadding: EdgeInsets.zero,
                              hintStyle: TextStyle(color: KColors.faint, fontSize: 44, fontWeight: FontWeight.w800),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Center(child: Container(width: 160, height: 3, margin: const EdgeInsets.only(top: 6), decoration: BoxDecoration(color: KColors.navy, borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 18),
                // Accounts
                if (!isTransfer) ...[
                  _label(_type == TxType.income ? 'Received in' : 'Paid from'),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 52,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      children: [
                        for (final a in _accounts) ...[
                          _accountChip(a, a.id == _account?.id, () => setState(() => _account = a)),
                          const SizedBox(width: 8),
                        ],
                        if (_accounts.isEmpty)
                          const Center(child: Text('No accounts yet — add one from Home → Accounts', style: TextStyle(color: KColors.muted, fontSize: 13))),
                      ],
                    ),
                  ),
                ] else ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      children: [
                        _transferField('From', _account, () => _pickAccount(), negative: true),
                        SizedBox(
                          height: 44,
                          child: Center(
                            child: InkWell(
                              onTap: () => setState(() {
                                final t = _account;
                                _account = _toAccount;
                                _toAccount = t;
                              }),
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                width: 40,
                                height: 40,
                                decoration: const BoxDecoration(color: KColors.navy, shape: BoxShape.circle),
                                child: const Icon(Icons.swap_vert_rounded, color: Colors.white, size: 20),
                              ),
                            ),
                          ),
                        ),
                        _transferField('To', _toAccount, () => _pickAccount(to: true), negative: false),
                      ],
                    ),
                  ),
                ],
                // Categories
                if (!isTransfer) ...[
                  const SizedBox(height: 18),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Category', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                        GestureDetector(
                          onTap: _pickAllCategories,
                          child: const Text('All categories', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: KColors.navyMid)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: GridView.count(
                      crossAxisCount: 4,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 0.95,
                      children: [
                        for (final c in _cats.take(7)) _catTile(c),
                        InkWell(
                          onTap: () async {
                            await Navigator.push(context, MaterialPageRoute(builder: (_) => CategoriesScreen(initialType: _type)));
                            await _loadCats(keepSelection: true);
                            setState(() {});
                          },
                          child: Column(children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(color: KColors.offWhite, borderRadius: BorderRadius.circular(16), border: Border.all(color: KColors.faint, style: BorderStyle.solid)),
                              child: const Icon(Icons.more_horiz_rounded, color: KColors.muted),
                            ),
                            const SizedBox(height: 6),
                            const Text('More', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: KColors.muted)),
                          ]),
                        ),
                      ],
                    ),
                  ),
                  if (_cat != null) ...[
                    const SizedBox(height: 14),
                    _label('Sub-category · ${_cat!.name}'),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 38,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        children: [
                          if (_subs.isEmpty)
                            const Center(child: Text('No sub-categories — add them in Categories', style: TextStyle(color: KColors.muted, fontSize: 13))),
                          for (final s in _subs) ...[
                            Pill(s.name, selected: s.id == _sub?.id, onTap: () => setState(() => _sub = s.id == _sub?.id ? null : s)),
                            const SizedBox(width: 8),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      InkWell(
                        onTap: _pickDate,
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          height: 52,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: KColors.line)),
                          child: Row(children: [
                            const Icon(Icons.calendar_today_outlined, size: 18, color: KColors.navy),
                            const SizedBox(width: 10),
                            Text(Dates.friendly(_date), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          ]),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SizedBox(
                          height: 52,
                          child: TextField(
                            controller: _note,
                            decoration: const InputDecoration(
                              hintText: 'Note (optional)',
                              prefixIcon: Icon(Icons.edit_outlined, size: 18, color: KColors.navy),
                              filled: false,
                              contentPadding: EdgeInsets.symmetric(horizontal: 14),
                            ),
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!_editing) ...[
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: KCard(
                      padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.repeat_rounded, size: 20, color: KColors.navy),
                              const SizedBox(width: 10),
                              const Expanded(child: Text('Repeat this transaction', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
                              Switch(value: _repeat, onChanged: (v) => setState(() => _repeat = v)),
                            ],
                          ),
                          if (_repeat)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(0, 4, 8, 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Wrap(spacing: 8, children: [
                                    for (final f in ['monthly', 'weekly', 'yearly'])
                                      Pill(f[0].toUpperCase() + f.substring(1), selected: _freq == f, onTap: () => setState(() => _freq = f)),
                                  ]),
                                  const SizedBox(height: 10),
                                  Wrap(spacing: 8, runSpacing: 8, children: [
                                    Pill('No end', selected: _months == null, onTap: () => setState(() => _months = null)),
                                    for (final n in [3, 6, 12, 24])
                                      Pill('$n times', selected: _months == n, onTap: () => setState(() => _months = n)),
                                    Pill('Custom…', selected: _months != null && ![3, 6, 12, 24].contains(_months), onTap: () async {
                                      final v = await promptText(context, 'How many times?', keyboard: TextInputType.number, hint: 'e.g. 18');
                                      final n = int.tryParse(v ?? '');
                                      if (n != null && n > 0) setState(() => _months = n);
                                    }),
                                  ]),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Posts automatically on the ${_freq == 'weekly' ? 'same weekday' : 'same day'} ${_months == null ? 'with no end date' : 'for $_months times'}.',
                                    style: const TextStyle(fontSize: 12, color: KColors.muted),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          BottomButton(
            label: _editing ? 'Save changes' : (isTransfer ? 'Save transfer' : (_type == TxType.income ? 'Save income' : 'Save expense')),
            icon: Icons.check_rounded,
            busy: _busy,
            onPressed: _save,
          ),
        ],
      ),
    );
  }

  Widget _label(String s) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Text(s, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
      );

  Widget _accountChip(Account a, bool selected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: selected ? KColors.navy : KColors.offWhite,
          borderRadius: BorderRadius.circular(14),
          border: selected ? null : Border.all(color: KColors.line),
        ),
        child: Row(
          children: [
            Icon(accountIcon(a.type), size: 18, color: selected ? KColors.white : KColors.navy),
            const SizedBox(width: 8),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a.name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: selected ? KColors.white : KColors.navy)),
                Text(
                  a.isCard ? '${Money.plain(a.availableLimit)} avail.' : Money.format(a.balance),
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: selected ? KColors.onNavyMuted : KColors.muted),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _catTile(Category c) {
    final sel = c.id == _cat?.id;
    return InkWell(
      onTap: () => _selectCat(c),
      borderRadius: BorderRadius.circular(16),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: sel ? KColors.navy : KColors.offWhite,
              borderRadius: BorderRadius.circular(16),
              border: sel ? null : Border.all(color: KColors.line),
            ),
            child: Icon(CategoryIcons.of(c.icon), size: 22, color: sel ? KColors.white : KColors.navy),
          ),
          const SizedBox(height: 6),
          Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: sel ? FontWeight.w700 : FontWeight.w600, color: sel ? KColors.navy : KColors.muted)),
        ],
      ),
    );
  }

  Widget _transferField(String label, Account? a, VoidCallback onTap, {required bool negative}) {
    String preview = '';
    if (a != null && _entered > 0) {
      final delta = negative ? -_entered : _entered;
      preview = '${Money.plain(a.balance)} → ${Money.format(a.balance + delta)}';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: KColors.muted)),
        const SizedBox(height: 6),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: 62,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: negative ? KColors.offWhite : KColors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: negative ? KColors.line : KColors.navy, width: 1.5),
            ),
            child: Row(
              children: [
                IconTile(a == null ? Icons.help_outline : accountIcon(a.type), size: 38, tint: negative ? KColors.white : KColors.tint),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(a?.name ?? 'Choose account', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                      if (a != null)
                        Text(
                          preview.isEmpty ? '${a.currency} · ${Money.format(a.balance)}' : preview,
                          style: TextStyle(fontSize: 12, color: preview.isEmpty ? KColors.muted : (negative ? KColors.red : KColors.green), fontWeight: FontWeight.w600),
                        ),
                    ],
                  ),
                ),
                const Icon(Icons.expand_more_rounded, size: 20, color: KColors.navy),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

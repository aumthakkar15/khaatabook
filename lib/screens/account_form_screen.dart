import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/account_service.dart';
import '../services/currency_service.dart';
import '../services/session.dart';
import '../theme.dart';
import '../utils/money.dart';
import '../widgets/common.dart';

/// Add / edit a cash, bank or credit-card account.
class AccountFormScreen extends StatefulWidget {
  final Account? existing;
  const AccountFormScreen({super.key, this.existing});
  @override
  State<AccountFormScreen> createState() => _AccountFormScreenState();
}

class _AccountFormScreenState extends State<AccountFormScreen> {
  final _name = TextEditingController();
  final _opening = TextEditingController();
  final _last4 = TextEditingController();
  final _note = TextEditingController();
  final _limit = TextEditingController();
  AccountType _type = AccountType.bank;
  String _currency = Session.instance.base;
  int _billDay = 5;
  int _dueDay = 25;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _name.text = e.name;
      _opening.text = Money.plain(e.openingBalance);
      _last4.text = e.last4 ?? '';
      _note.text = e.note ?? '';
      _limit.text = e.creditLimit > 0 ? Money.plain(e.creditLimit) : '';
      _type = e.type;
      _currency = e.currency;
      _billDay = e.billDay;
      _dueDay = e.dueDay;
    }
  }

  Future<void> _pickCurrency() async {
    final list = await CurrencyService.instance.all();
    if (!mounted) return;
    final c = await pickFromSheet<Currency>(
      context,
      title: 'Account currency',
      items: [...list.where((c) => c.inUse), ...list.where((c) => !c.inUse)],
      tile: (c) => ListRow(leading: IconTile(Icons.currency_exchange_rounded, filled: c.inUse), title: '${c.code} · ${c.name}', subtitle: c.country),
    );
    if (c != null) setState(() => _currency = c.code);
  }

  Future<int?> _pickDay(String title, int current) async {
    return pickFromSheet<int>(
      context,
      title: title,
      items: List.generate(28, (i) => i + 1),
      tile: (d) => ListTile(title: Text('Day $d', style: TextStyle(fontWeight: d == current ? FontWeight.w800 : FontWeight.w600))),
    );
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final a = Account(
        id: widget.existing?.id,
        name: _name.text.trim(),
        type: _type,
        currency: _currency,
        openingBalance: _type == AccountType.card ? 0 : Money.parse(_opening.text),
        last4: _last4.text.trim().isEmpty ? null : _last4.text.trim(),
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        creditLimit: _type == AccountType.card ? Money.parse(_limit.text) : 0,
        billDay: _billDay,
        dueDay: _dueDay,
        archived: widget.existing?.archived ?? false,
      );
      if (widget.existing == null) {
        await AccountService.instance.add(a);
      } else {
        await AccountService.instance.update(a);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showMsg(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCard = _type == AccountType.card;
    return Scaffold(
      backgroundColor: KColors.white,
      body: Column(
        children: [
          NavyHeader(
            child: Row(children: [
              const BackButtonNavy(),
              const SizedBox(width: 12),
              Text(widget.existing == null ? 'Add account' : 'Edit account', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: KColors.white)),
            ]),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              children: [
                const Text('Type', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Segmented<AccountType>(
                  values: AccountType.values,
                  value: _type,
                  label: accountTypeLabel,
                  onChanged: widget.existing == null ? (t) => setState(() => _type = t) : (_) {},
                ),
                const SizedBox(height: 16),
                KTextField(controller: _name, label: 'Account name', hint: isCard ? 'e.g. ADCB Visa' : 'e.g. Emirates NBD Salary', icon: accountIcon(_type), capitalization: TextCapitalization.words),
                const SizedBox(height: 14),
                const Text('Currency', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                PickerField(label: 'Currency', value: _currency, icon: Icons.currency_exchange_rounded, onTap: _pickCurrency),
                const SizedBox(height: 14),
                if (!isCard) ...[
                  KTextField(controller: _opening, label: 'Opening balance', hint: '0.00', icon: Icons.account_balance_wallet_outlined, keyboard: const TextInputType.numberWithOptions(decimal: true, signed: true)),
                  const SizedBox(height: 14),
                ],
                if (isCard) ...[
                  KTextField(controller: _limit, label: 'Total credit limit', hint: 'e.g. 10000', icon: Icons.credit_score_outlined, keyboard: const TextInputType.numberWithOptions(decimal: true)),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: PickerField(
                          label: 'Bill (statement) date',
                          value: 'Day $_billDay of month',
                          icon: Icons.receipt_long_outlined,
                          onTap: () async {
                            final d = await _pickDay('Bill date', _billDay);
                            if (d != null) setState(() => _billDay = d);
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: PickerField(
                          label: 'Payment due date',
                          value: 'Day $_dueDay of month',
                          icon: Icons.event_available_outlined,
                          onTap: () async {
                            final d = await _pickDay('Payment due date', _dueDay);
                            if (d != null) setState(() => _dueDay = d);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text('Card spending increases the outstanding amount; paying the card from a bank account restores the available limit.', style: TextStyle(fontSize: 12, color: KColors.muted)),
                  const SizedBox(height: 14),
                ],
                KTextField(controller: _last4, label: isCard ? 'Last 4 digits of card' : 'Last 4 digits of account (optional)', hint: '1234', icon: Icons.pin_outlined, keyboard: TextInputType.number, capitalization: TextCapitalization.none),
                const SizedBox(height: 14),
                KTextField(controller: _note, label: 'Note (optional)', icon: Icons.edit_outlined),
              ],
            ),
          ),
          BottomButton(label: widget.existing == null ? 'Save account' : 'Save changes', icon: Icons.check_rounded, busy: _busy, onPressed: _save),
        ],
      ),
    );
  }
}

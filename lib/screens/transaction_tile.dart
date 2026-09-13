import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/transaction_service.dart';
import '../theme.dart';
import '../utils/money.dart';
import '../widgets/common.dart';
import 'add_transaction_screen.dart';

/// One transaction row, reused by Home, History and Reports.
class TransactionTile extends StatelessWidget {
  final Tx tx;
  final Map<int, Account> accounts;
  final Map<int, Category> cats;
  final bool showDate;
  const TransactionTile({super.key, required this.tx, required this.accounts, required this.cats, this.showDate = true});

  @override
  Widget build(BuildContext context) {
    final acc = accounts[tx.accountId];
    final to = tx.toAccountId == null ? null : accounts[tx.toAccountId!];
    final cat = cats[tx.categoryId ?? -1];
    final sub = cats[tx.subcategoryId ?? -1];

    String title;
    IconData icon;
    Color tint = KColors.tint;
    Color iconColor = KColors.navy;
    double signed;
    switch (tx.type) {
      case TxType.transfer:
        title = '${acc?.name ?? '?'} → ${to?.name ?? '?'}';
        icon = Icons.swap_vert_rounded;
        signed = tx.amount; // neutral
        break;
      case TxType.income:
        title = [cat?.name ?? 'Income', if (sub != null) sub.name].join(' › ');
        icon = cat == null ? Icons.work_outline : CategoryIcons.of(cat.icon);
        tint = KColors.greenTint;
        iconColor = KColors.green;
        signed = tx.amount;
        break;
      default:
        title = [cat?.name ?? 'Expense', if (sub != null) sub.name].join(' › ');
        icon = cat == null ? Icons.sell_outlined : CategoryIcons.of(cat.icon);
        signed = -tx.amount;
    }
    final subtitleParts = <String>[
      if (showDate) Dates.friendly(tx.date),
      if (tx.type != TxType.transfer) acc?.name ?? '',
      if (tx.note != null && tx.note!.isNotEmpty) tx.note!,
    ].where((s) => s.isNotEmpty).toList();

    return ListRow(
      leading: IconTile(icon, tint: tint, iconColor: iconColor),
      title: title,
      subtitle: subtitleParts.join(' · '),
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          tx.type == TxType.transfer
              ? Text(Money.format(tx.amount, code: tx.currency), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: KColors.muted))
              : MoneyText(signed, code: tx.currency, showPlus: true, positiveGreen: true),
          if (tx.source != 'manual')
            Text(_sourceLabel(tx.source), style: const TextStyle(fontSize: 10, color: KColors.faint, fontWeight: FontWeight.w600)),
        ],
      ),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AddTransactionScreen(existing: tx))),
      onLongPress: () async {
        final ok = await confirm(context, 'Delete transaction?', 'This will reverse its effect on the account balance.', okLabel: 'Delete', danger: true);
        if (ok) await TransactionService.instance.delete(tx.id!);
      },
    );
  }

  String _sourceLabel(String s) => switch (s) {
        'recurring' => 'RECURRING',
        'loan' => 'LOAN EMI',
        'card_payment' => 'CARD PAYMENT',
        'import' => 'IMPORTED',
        _ => '',
      };
}

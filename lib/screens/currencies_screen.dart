import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/currency_service.dart';
import '../services/session.dart';
import '../theme.dart';
import '../utils/money.dart';
import '../widgets/common.dart';

/// Feature 3: currency master — every world currency, online sync,
/// manual override, All / In use filters, search.
class CurrenciesScreen extends StatefulWidget {
  const CurrenciesScreen({super.key});
  @override
  State<CurrenciesScreen> createState() => _CurrenciesScreenState();
}

class _CurrenciesScreenState extends State<CurrenciesScreen> {
  List<Currency> _list = [];
  bool _inUseOnly = false;
  String _q = '';
  String? _synced;
  bool _syncing = false;

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
    _list = await CurrencyService.instance.all(inUseOnly: _inUseOnly, search: _q);
    _synced = await CurrencyService.instance.lastSynced();
    if (mounted) setState(() {});
  }

  Future<void> _sync() async {
    setState(() => _syncing = true);
    try {
      final n = await CurrencyService.instance.syncOnline();
      if (mounted) showMsg(context, 'Updated $n currencies from online rates');
    } catch (e) {
      if (mounted) showMsg(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _edit(Currency c) async {
    final base = Session.instance.base;
    if (c.code == base) {
      showMsg(context, '$base is your base currency (rate is always 1)');
      return;
    }
    final v = await promptText(context, '1 $base = ? ${c.code}', hint: 'e.g. 22.6540', initial: c.rate > 0 ? c.rate.toString() : '', keyboard: const TextInputType.numberWithOptions(decimal: true), okLabel: 'Save');
    if (v == null) return;
    final rate = double.tryParse(v.trim());
    if (rate == null || rate <= 0) {
      if (mounted) showMsg(context, 'Enter a valid rate', error: true);
      return;
    }
    await CurrencyService.instance.setManualRate(c.code, rate);
  }

  @override
  Widget build(BuildContext context) {
    final base = Session.instance.base;
    final syncedText = _synced == null ? 'Never synced — tap Sync now (needs internet)' : 'Last synced ${Dates.friendly(DateTime.parse(_synced!))}, ${Dates.time.format(DateTime.parse(_synced!))}';
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
                  const Expanded(child: Text('Currencies', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: KColors.white))),
                  Container(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(color: KColors.white, borderRadius: BorderRadius.circular(12)),
                    child: Row(children: [
                      const Text('Base ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: KColors.muted)),
                      Text(base, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                    ]),
                  ),
                ]),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.10), borderRadius: BorderRadius.circular(18)),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Online rates', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: KColors.white)),
                        const SizedBox(height: 3),
                        Text(syncedText, style: const TextStyle(fontSize: 12, color: KColors.onNavyMuted, fontWeight: FontWeight.w500)),
                      ]),
                    ),
                    const SizedBox(width: 10),
                    InkWell(
                      onTap: _syncing ? null : _sync,
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        height: 44,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(color: KColors.white, borderRadius: BorderRadius.circular(14)),
                        child: Row(children: [
                          _syncing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync_rounded, size: 18, color: KColors.navy),
                          const SizedBox(width: 8),
                          const Text('Sync now', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                        ]),
                      ),
                    ),
                  ]),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: TextField(
                    onChanged: (v) {
                      _q = v;
                      _load();
                    },
                    decoration: const InputDecoration(hintText: 'Search currency or country', prefixIcon: Icon(Icons.search, color: KColors.faint, size: 20), isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12), fillColor: KColors.white),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Pill('All', selected: !_inUseOnly, onTap: () {
                _inUseOnly = false;
                _load();
              }),
              const SizedBox(width: 6),
              Pill('In use', selected: _inUseOnly, onTap: () {
                _inUseOnly = true;
                _load();
              }),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('CURRENCY', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: KColors.muted, letterSpacing: 0.4)),
              Text('1 $base =', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: KColors.muted, letterSpacing: 0.4)),
            ]),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              itemCount: _list.length,
              separatorBuilder: (_, __) => const Divider(indent: 16, endIndent: 16),
              itemBuilder: (_, i) {
                final c = _list[i];
                final isBase = c.code == base;
                return Container(
                  decoration: BoxDecoration(
                    color: KColors.white,
                    borderRadius: i == 0 && _list.length == 1
                        ? BorderRadius.circular(18)
                        : i == 0
                            ? const BorderRadius.vertical(top: Radius.circular(18))
                            : (i == _list.length - 1 ? const BorderRadius.vertical(bottom: Radius.circular(18)) : BorderRadius.zero),
                    border: Border.all(color: KColors.line),
                  ),
                  child: ListRow(
                    leading: Container(
                      width: 46,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: c.inUse ? KColors.navy : KColors.tint, borderRadius: BorderRadius.circular(12)),
                      child: Text(c.code, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: c.inUse ? KColors.white : KColors.navy)),
                    ),
                    title: c.name,
                    subtitle: '${c.country} · ${c.symbol}',
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text(isBase ? '1.0000' : (c.rate > 0 ? Money.rate(c.rate) : '—'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        Text(isBase ? 'Base' : (c.manual ? 'Manual' : (c.rate > 0 ? 'Synced' : 'No rate')), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isBase ? KColors.muted : (c.manual ? KColors.amber : (c.rate > 0 ? KColors.green : KColors.red)))),
                      ]),
                      const SizedBox(width: 8),
                      PopupMenuButton<String>(
                        onSelected: (v) async {
                          if (v == 'edit') await _edit(c);
                          if (v == 'reset') await CurrencyService.instance.resetToOnline(c.code);
                          if (v == 'use') await CurrencyService.instance.setInUse(c.code, !c.inUse);
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 'edit', child: Text('Set rate manually')),
                          if (c.manual) const PopupMenuItem(value: 'reset', child: Text('Use online rate again')),
                          if (!isBase) PopupMenuItem(value: 'use', child: Text(c.inUse ? 'Remove from "In use"' : 'Mark as in use')),
                        ],
                        child: const Icon(Icons.edit_outlined, size: 18, color: KColors.faint),
                      ),
                    ]),
                    onTap: () => _edit(c),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

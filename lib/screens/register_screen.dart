import 'package:flutter/material.dart';

import '../data/currencies_data.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Feature 1: new user registration; country sets the base currency.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _name = TextEditingController();
  final _id = TextEditingController();
  final _pw = TextEditingController();
  bool _show = false;
  bool _busy = false;
  CountrySeed _country = kCountries.firstWhere((c) => c.name == 'United Arab Emirates');

  CurrencySeed get _currency => kCurrencySeeds.firstWhere((c) => c.code == _country.currency, orElse: () => kCurrencySeeds.first);

  Future<void> _pickCountry() async {
    final c = await showSearchPicker<CountrySeed>(
      context,
      title: 'Select country',
      items: kCountries,
      label: (c) => c.name,
      subtitle: (c) => 'Currency: ${c.currency}',
    );
    if (c != null) setState(() => _country = c);
  }

  Future<void> _create() async {
    setState(() => _busy = true);
    try {
      await AuthService.instance.register(
        name: _name.text,
        loginId: _id.text,
        password: _pw.text,
        country: _country.name,
        baseCurrency: _country.currency,
      );
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (mounted) showMsg(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KColors.white,
      body: Column(
        children: [
          NavyHeader(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const BackButtonNavy(),
                const SizedBox(height: 22),
                const Text('Create account', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: KColors.white, letterSpacing: -0.5)),
                const SizedBox(height: 4),
                const Text('Takes less than a minute', style: TextStyle(fontSize: 14, color: KColors.onNavyMuted, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
              children: [
                KTextField(controller: _name, label: 'Full name', hint: 'Your name', icon: Icons.person_outline, capitalization: TextCapitalization.words),
                const SizedBox(height: 14),
                KTextField(controller: _id, label: 'Login ID', hint: 'Email or username', icon: Icons.alternate_email, capitalization: TextCapitalization.none),
                const SizedBox(height: 14),
                KTextField(
                  controller: _pw,
                  label: 'Password',
                  hint: 'Minimum 6 characters',
                  icon: Icons.lock_outline,
                  obscure: !_show,
                  capitalization: TextCapitalization.none,
                  suffix: IconButton(
                    icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: KColors.faint),
                    onPressed: () => setState(() => _show = !_show),
                  ),
                ),
                const SizedBox(height: 14),
                const Text('Country', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                PickerField(label: 'Country', value: _country.name, icon: Icons.public, onTap: _pickCountry, highlighted: true),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  decoration: BoxDecoration(color: KColors.tint, borderRadius: BorderRadius.circular(16)),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: KColors.navy, borderRadius: BorderRadius.circular(12)),
                        child: Text(_currency.code, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: KColors.white)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Currency: ${_currency.name} (${_currency.code})', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            const Text('Set automatically from your country', style: TextStyle(fontSize: 12, color: KColors.muted, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                ElevatedButton(
                  onPressed: _busy ? null : _create,
                  child: _busy
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                      : const Text('Create account'),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Wrap(
                    spacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text('Already have an account?', style: TextStyle(fontSize: 14, color: KColors.muted, fontWeight: FontWeight.w500)),
                      GestureDetector(
                        onTap: () => Navigator.of(context).maybePop(),
                        child: const Text('Sign in', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: KColors.navy)),
                      ),
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
}

/// Searchable full-screen picker (countries, currencies...).
Future<T?> showSearchPicker<T>(
  BuildContext context, {
  required String title,
  required List<T> items,
  required String Function(T) label,
  String Function(T)? subtitle,
}) {
  return Navigator.push<T>(
    context,
    MaterialPageRoute(builder: (_) => _SearchPicker<T>(title: title, items: items, label: label, subtitle: subtitle)),
  );
}

class _SearchPicker<T> extends StatefulWidget {
  final String title;
  final List<T> items;
  final String Function(T) label;
  final String Function(T)? subtitle;
  const _SearchPicker({required this.title, required this.items, required this.label, this.subtitle});
  @override
  State<_SearchPicker<T>> createState() => _SearchPickerState<T>();
}

class _SearchPickerState<T> extends State<_SearchPicker<T>> {
  String _q = '';
  @override
  Widget build(BuildContext context) {
    final list = widget.items.where((i) {
      if (_q.isEmpty) return true;
      final q = _q.toLowerCase();
      return widget.label(i).toLowerCase().contains(q) || (widget.subtitle?.call(i).toLowerCase().contains(q) ?? false);
    }).toList();
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: TextField(
              autofocus: true,
              onChanged: (v) => setState(() => _q = v),
              decoration: const InputDecoration(hintText: 'Search', prefixIcon: Icon(Icons.search, color: KColors.faint)),
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: list.length,
              separatorBuilder: (_, __) => const Divider(indent: 20, endIndent: 20),
              itemBuilder: (_, i) => ListTile(
                title: Text(widget.label(list[i]), style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: widget.subtitle == null ? null : Text(widget.subtitle!(list[i]), style: const TextStyle(color: KColors.muted, fontSize: 12)),
                onTap: () => Navigator.pop(context, list[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

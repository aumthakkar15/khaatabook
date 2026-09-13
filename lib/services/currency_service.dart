import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

import '../data/currencies_data.dart';
import '../db/database.dart';
import '../models/models.dart';
import 'session.dart';

class CurrencyException implements Exception {
  final String message;
  CurrencyException(this.message);
  @override
  String toString() => message;
}

/// Feature 3: currency master, online rate sync, manual overrides and
/// exact conversion. Rates are stored as "1 BASE = rate units of currency".
class CurrencyService {
  CurrencyService._();
  static final CurrencyService instance = CurrencyService._();

  Map<String, Currency> _cache = {};

  Future<void> seedIfEmpty(String base) async {
    final d = await AppDb.instance.db;
    final rows = await d.rawQuery('SELECT COUNT(*) c FROM currencies');
    if ((rows.first['c'] as int) > 0) return;
    final batch = d.batch();
    for (final s in kCurrencySeeds) {
      batch.insert('currencies', {
        'code': s.code,
        'name': s.name,
        'symbol': s.symbol,
        'country': s.country,
        'rate': s.code == base ? 1.0 : 0.0,
        'manual': 0,
        'in_use': s.code == base ? 1 : 0,
      });
    }
    await batch.commit(noResult: true);
    _cache = {};
  }

  Future<List<Currency>> all({bool inUseOnly = false, String? search}) async {
    final d = await AppDb.instance.db;
    final where = <String>[];
    final args = <Object?>[];
    if (inUseOnly) where.add('in_use = 1');
    if (search != null && search.trim().isNotEmpty) {
      where.add('(code LIKE ? OR name LIKE ? OR country LIKE ?)');
      final q = '%${search.trim()}%';
      args.addAll([q, q, q]);
    }
    final rows = await d.query('currencies',
        where: where.isEmpty ? null : where.join(' AND '), whereArgs: args, orderBy: 'in_use DESC, code ASC');
    return rows.map(Currency.fromMap).toList();
  }

  Future<Map<String, Currency>> map() async {
    if (_cache.isNotEmpty) return _cache;
    final list = await all();
    _cache = {for (final c in list) c.code: c};
    return _cache;
  }

  Future<Currency?> get(String code) async => (await map())[code];

  Future<String?> lastSynced() => AppDb.instance.getSetting('rates_synced_at');

  /// Rate of [code] against the base (1 base = x code). Base itself = 1.
  Future<double> rateOf(String code) async {
    final base = Session.instance.base;
    if (code == base) return 1.0;
    final c = await get(code);
    if (c == null || c.rate <= 0) {
      throw CurrencyException('No rate for $code. Sync rates or enter it manually in Currencies.');
    }
    return c.rate;
  }

  /// Convert [amount] in [from] to [to] using master rates (full precision).
  Future<double> convert(double amount, String from, String to) async {
    if (from == to) return amount;
    final rf = await rateOf(from);
    final rt = await rateOf(to);
    return amount / rf * rt;
  }

  Future<double> toBase(double amount, String from) async => convert(amount, from, Session.instance.base);

  Future<void> setManualRate(String code, double rate) async {
    if (rate <= 0) throw CurrencyException('Rate must be greater than zero');
    final d = await AppDb.instance.db;
    await d.update('currencies', {'rate': rate, 'manual': 1, 'in_use': 1, 'updated_at': DateTime.now().toIso8601String()},
        where: 'code = ?', whereArgs: [code]);
    _cache = {};
    DataBus.instance.changed();
  }

  /// Clears the manual flag so the next sync overwrites the rate.
  Future<void> resetToOnline(String code) async {
    final d = await AppDb.instance.db;
    await d.update('currencies', {'manual': 0}, where: 'code = ?', whereArgs: [code]);
    _cache = {};
    DataBus.instance.changed();
  }

  Future<void> markInUse(String code) async {
    final d = await AppDb.instance.db;
    await d.update('currencies', {'in_use': 1}, where: 'code = ?', whereArgs: [code]);
    _cache = {};
  }

  Future<void> setInUse(String code, bool inUse) async {
    final d = await AppDb.instance.db;
    await d.update('currencies', {'in_use': inUse ? 1 : 0}, where: 'code = ?', whereArgs: [code]);
    _cache = {};
    DataBus.instance.changed();
  }

  /// When the base currency changes (settings), re-express every rate.
  Future<void> rebase(String newBase) async {
    final m = await map();
    final nb = m[newBase];
    if (nb == null || nb.rate <= 0) throw CurrencyException('No rate for $newBase yet');
    final factor = nb.rate; // old-base → new-base
    final d = await AppDb.instance.db;
    final b = d.batch();
    for (final c in m.values) {
      if (c.rate > 0) b.update('currencies', {'rate': c.rate / factor}, where: 'code = ?', whereArgs: [c.code]);
    }
    b.update('currencies', {'rate': 1.0, 'in_use': 1}, where: 'code = ?', whereArgs: [newBase]);
    await b.commit(noResult: true);
    _cache = {};
  }

  /// Online sync. Uses a free public feed (open.er-api.com, ~160 currencies,
  /// updated daily). Manual rates are preserved. Needs internet only here.
  Future<int> syncOnline() async {
    final base = Session.instance.base;
    final uri = Uri.parse('https://open.er-api.com/v6/latest/$base');
    http.Response res;
    try {
      res = await http.get(uri).timeout(const Duration(seconds: 20));
    } catch (e) {
      throw CurrencyException('Could not reach the rate service. Check your internet connection.');
    }
    if (res.statusCode != 200) throw CurrencyException('Rate service error (${res.statusCode})');
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (body['result'] != 'success') throw CurrencyException('Rate service returned an error');
    final rates = (body['rates'] as Map<String, dynamic>);
    final d = await AppDb.instance.db;
    final now = DateTime.now().toIso8601String();
    var n = 0;
    await d.transaction((t) async {
      for (final e in rates.entries) {
        final v = (e.value as num).toDouble();
        if (v <= 0) continue;
        n += await t.update('currencies', {'rate': v, 'updated_at': now},
            where: 'code = ? AND manual = 0', whereArgs: [e.key]);
      }
      await t.update('currencies', {'rate': 1.0, 'updated_at': now}, where: 'code = ?', whereArgs: [base]);
      await t.insert('settings', {'key': 'rates_synced_at', 'value': now}, conflictAlgorithm: ConflictAlgorithm.replace);
    });
    _cache = {};
    DataBus.instance.changed();
    return n;
  }
}

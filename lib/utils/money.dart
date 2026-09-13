import 'package:intl/intl.dart';

/// App-wide number formatting rule (feature 7):
/// negative amounts are shown with the minus sign FIRST, before the currency
/// code and the number, e.g. "- AED 3,200.00".
class Money {
  static final NumberFormat _f2 = NumberFormat('#,##0.00', 'en_US');
  static final NumberFormat _f0 = NumberFormat('#,##0', 'en_US');
  static final NumberFormat _f4 = NumberFormat('#,##0.0000', 'en_US');

  /// Rounds to 2 decimals for storage/display without float drift.
  static double round2(double v) => (v * 100).roundToDouble() / 100;

  /// "3,200.00" (no sign, no currency)
  static String plain(double v, {int decimals = 2}) {
    final abs = v.abs();
    return decimals == 0 ? _f0.format(abs) : _f2.format(abs);
  }

  /// "- AED 3,200.00" / "AED 3,200.00" / "+ AED 3,200.00" (when showPlus)
  static String format(double v, {String? code, bool showPlus = false, int decimals = 2}) {
    final n = plain(v, decimals: decimals);
    final body = code == null || code.isEmpty ? n : '$code $n';
    if (v < -0.004999) return '- $body';
    if (showPlus && v > 0.004999) return '+ $body';
    return body;
  }

  /// Rate display with 4 decimals.
  static String rate(double v) => _f4.format(v);

  static double parse(String s) {
    final cleaned = s.replaceAll(',', '').replaceAll(RegExp(r'[^0-9.\-]'), '').trim();
    return double.tryParse(cleaned) ?? 0;
  }
}

class Dates {
  static final DateFormat ymd = DateFormat('yyyy-MM-dd');
  static final DateFormat dMy = DateFormat('d MMM yyyy');
  static final DateFormat dM = DateFormat('d MMM');
  static final DateFormat mY = DateFormat('MMM yyyy');
  static final DateFormat time = DateFormat('h:mm a');

  static String key(DateTime d) => ymd.format(d);
  static DateTime parse(String s) => DateTime.parse(s);
  static DateTime today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  static String friendly(DateTime d) {
    final t = today();
    final dd = DateTime(d.year, d.month, d.day);
    if (dd == t) return 'Today';
    if (dd == t.subtract(const Duration(days: 1))) return 'Yesterday';
    return dMy.format(d);
  }

  /// Same day-of-month in another month, clamped to that month's length.
  static DateTime onDay(int year, int month, int day) {
    while (month > 12) {
      month -= 12;
      year++;
    }
    while (month < 1) {
      month += 12;
      year--;
    }
    final last = DateTime(year, month + 1, 0).day;
    return DateTime(year, month, day > last ? last : day);
  }

  static DateTime addMonths(DateTime d, int months, {int? day}) =>
      onDay(d.year, d.month + months, day ?? d.day);
}

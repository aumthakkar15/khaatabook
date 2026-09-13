import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme.dart';
import '../utils/money.dart';

/// Icon keys used by categories (Feature 4) — one consistent outline set.
class CategoryIcons {
  static const map = <String, IconData>{
    'food': Icons.restaurant_outlined,
    'transport': Icons.directions_car_outlined,
    'bills': Icons.receipt_long_outlined,
    'housing': Icons.home_outlined,
    'health': Icons.favorite_outline,
    'shopping': Icons.shopping_bag_outlined,
    'education': Icons.school_outlined,
    'entertainment': Icons.movie_outlined,
    'family': Icons.family_restroom_outlined,
    'loan': Icons.account_balance_outlined,
    'fees': Icons.percent_outlined,
    'salary': Icons.work_outline,
    'business': Icons.storefront_outlined,
    'interest': Icons.trending_up_outlined,
    'travel': Icons.flight_outlined,
    'gift': Icons.card_giftcard_outlined,
    'pet': Icons.pets_outlined,
    'tag': Icons.sell_outlined,
    'dot': Icons.circle,
  };
  static IconData of(String key) => map[key] ?? Icons.sell_outlined;
  static List<String> get keys => map.keys.where((k) => k != 'dot').toList();
}

IconData accountIcon(AccountType t) => switch (t) {
      AccountType.cash => Icons.payments_outlined,
      AccountType.bank => Icons.account_balance_outlined,
      AccountType.card => Icons.credit_card_outlined,
    };

String accountTypeLabel(AccountType t) => switch (t) {
      AccountType.cash => 'Cash',
      AccountType.bank => 'Bank',
      AccountType.card => 'Credit card',
    };

/// Navy header block with rounded bottom (design Option A).
class NavyHeader extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const NavyHeader({super.key, required this.child, this.padding = const EdgeInsets.fromLTRB(20, 12, 20, 22)});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: KColors.navy,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: SafeArea(bottom: false, child: Padding(padding: padding, child: child)),
    );
  }
}

/// Round icon button used in headers (light on navy or navy on white).
class HeaderButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool onNavy;
  const HeaderButton({super.key, required this.icon, this.onTap, this.onNavy = true});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: onNavy ? Colors.white.withOpacity(0.10) : KColors.white,
          border: onNavy ? null : Border.all(color: KColors.line),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: onNavy ? KColors.white : KColors.navy, size: 22),
      ),
    );
  }
}

class BackButtonNavy extends StatelessWidget {
  final bool onNavy;
  const BackButtonNavy({super.key, this.onNavy = true});
  @override
  Widget build(BuildContext context) =>
      HeaderButton(icon: Icons.arrow_back_rounded, onNavy: onNavy, onTap: () => Navigator.of(context).maybePop());
}

/// Amount text following the app rule: negative = red, minus first.
class MoneyText extends StatelessWidget {
  final double value;
  final String? code;
  final double size;
  final FontWeight weight;
  final Color? color;
  final bool showPlus;
  final bool positiveGreen;
  final bool onNavy;
  const MoneyText(this.value,
      {super.key,
      this.code,
      this.size = 15,
      this.weight = FontWeight.w700,
      this.color,
      this.showPlus = false,
      this.positiveGreen = false,
      this.onNavy = false});
  @override
  Widget build(BuildContext context) {
    Color c;
    if (value < -0.004999) {
      c = onNavy ? KColors.redOnNavy : KColors.red;
    } else if (positiveGreen && value > 0.004999) {
      c = onNavy ? KColors.greenOnNavy : KColors.green;
    } else {
      c = color ?? (onNavy ? KColors.white : KColors.navy);
    }
    return Text(
      Money.format(value, code: code, showPlus: showPlus),
      style: TextStyle(fontSize: size, fontWeight: weight, color: c, letterSpacing: size > 24 ? -0.8 : 0),
    );
  }
}

class KCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets margin;
  final VoidCallback? onTap;
  final Color? color;
  const KCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.margin = EdgeInsets.zero, this.onTap, this.color});
  @override
  Widget build(BuildContext context) {
    final box = Container(
      margin: margin,
      decoration: BoxDecoration(
        color: color ?? KColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: KColors.line),
      ),
      child: Padding(padding: padding, child: child),
    );
    if (onTap == null) return box;
    return InkWell(onTap: onTap, borderRadius: BorderRadius.circular(18), child: box);
  }
}

class SectionLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionLabel(this.text, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(text.toUpperCase(),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: KColors.muted, letterSpacing: 0.4)),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  final String? action;
  final VoidCallback? onAction;
  const SectionTitle(this.text, {super.key, this.action, this.onAction});
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        if (action != null)
          GestureDetector(
            onTap: onAction,
            child: Text(action!, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: KColors.navyMid)),
          ),
      ],
    );
  }
}

/// Square tinted icon tile used in list rows.
class IconTile extends StatelessWidget {
  final IconData icon;
  final bool filled;
  final Color? tint;
  final Color? iconColor;
  final double size;
  const IconTile(this.icon, {super.key, this.filled = false, this.tint, this.iconColor, this.size = 42});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: filled ? KColors.navy : (tint ?? KColors.tint),
        borderRadius: BorderRadius.circular(size * 0.31),
      ),
      child: Icon(icon, size: size * 0.48, color: filled ? KColors.white : (iconColor ?? KColors.navy)),
    );
  }
}

/// Standard list row: icon tile, title, subtitle, trailing.
class ListRow extends StatelessWidget {
  final Widget leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool dim;
  const ListRow({super.key, required this.leading, required this.title, this.subtitle, this.trailing, this.onTap, this.onLongPress, this.dim = false});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: dim ? KColors.muted : KColors.navy)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: KColors.muted)),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 10), trailing!],
          ],
        ),
      ),
    );
  }
}

/// Selectable pill (filters, sub-categories, frequency).
class Pill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool onNavy;
  const Pill(this.label, {super.key, this.selected = false, this.onTap, this.icon, this.onNavy = false});
  @override
  Widget build(BuildContext context) {
    final bg = selected
        ? (onNavy ? KColors.white : KColors.navy)
        : (onNavy ? Colors.white.withOpacity(0.10) : KColors.offWhite);
    final fg = selected ? (onNavy ? KColors.navy : KColors.white) : (onNavy ? KColors.white : KColors.muted);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: selected || onNavy ? null : Border.all(color: KColors.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 16, color: fg), const SizedBox(width: 6)],
            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: fg)),
          ],
        ),
      ),
    );
  }
}

/// Segmented control (Expense / Income / Transfer etc.).
class Segmented<T> extends StatelessWidget {
  final List<T> values;
  final T value;
  final String Function(T) label;
  final ValueChanged<T> onChanged;
  final bool onNavy;
  const Segmented({super.key, required this.values, required this.value, required this.label, required this.onChanged, this.onNavy = false});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: onNavy ? Colors.white.withOpacity(0.10) : KColors.offWhite,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          for (final v in values)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(v),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  height: 44,
                  decoration: BoxDecoration(
                    color: v == value ? (onNavy ? KColors.white : KColors.navy) : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Text(label(v),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: v == value ? FontWeight.w700 : FontWeight.w600,
                        color: v == value ? (onNavy ? KColors.navy : KColors.white) : (onNavy ? KColors.onNavyMuted : KColors.muted),
                      )),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class ProgressBar extends StatelessWidget {
  final double value; // 0..1
  final double height;
  final Color? color;
  final Color? track;
  const ProgressBar(this.value, {super.key, this.height = 8, this.color, this.track});
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: LinearProgressIndicator(
        value: value.clamp(0, 1).toDouble(),
        minHeight: height,
        backgroundColor: track ?? KColors.tint,
        valueColor: AlwaysStoppedAnimation(color ?? KColors.navy),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  const EmptyState({super.key, required this.icon, required this.title, this.subtitle});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: KColors.faint),
          const SizedBox(height: 12),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, textAlign: TextAlign.center, style: const TextStyle(color: KColors.muted, fontSize: 13)),
          ],
        ],
      ),
    );
  }
}

/// Bottom primary button pinned above the safe area.
class BottomButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool busy;
  const BottomButton({super.key, required this.label, this.icon, this.onPressed, this.busy = false});
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: ElevatedButton(
          onPressed: busy ? null : onPressed,
          child: busy
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
                    Text(label),
                  ],
                ),
        ),
      ),
    );
  }
}

void showMsg(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? KColors.red : KColors.navy,
      duration: Duration(seconds: error ? 4 : 2),
    ));
}

Future<bool> confirm(BuildContext context, String title, String message, {String okLabel = 'Confirm', bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(c, true),
          style: TextButton.styleFrom(foregroundColor: danger ? KColors.red : KColors.navy),
          child: Text(okLabel),
        ),
      ],
    ),
  );
  return r ?? false;
}

Future<String?> promptText(BuildContext context, String title, {String? hint, String? initial, bool obscure = false, TextInputType? keyboard, String okLabel = 'OK'}) async {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      content: TextField(controller: c, autofocus: true, obscureText: obscure, keyboardType: keyboard, decoration: InputDecoration(hintText: hint)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(ctx, c.text), child: Text(okLabel)),
      ],
    ),
  );
}

/// Generic bottom-sheet chooser.
Future<T?> pickFromSheet<T>(BuildContext context, {required String title, required List<T> items, required Widget Function(T) tile}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    builder: (c) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      builder: (_, controller) => Column(
        children: [
          const SizedBox(height: 10),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: KColors.line, borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Align(alignment: Alignment.centerLeft, child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
          ),
          Expanded(
            child: ListView.separated(
              controller: controller,
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(indent: 16, endIndent: 16),
              itemBuilder: (_, i) => InkWell(onTap: () => Navigator.pop(c, items[i]), child: tile(items[i])),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Simple labelled value field that opens a picker on tap.
class PickerField extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;
  final bool highlighted;
  const PickerField({super.key, required this.label, required this.value, required this.icon, required this.onTap, this.highlighted = false});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: highlighted ? KColors.white : KColors.offWhite,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: highlighted ? KColors.navy : KColors.line, width: 1.5),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: KColors.navy),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontSize: 11, color: KColors.muted, fontWeight: FontWeight.w500)),
                  Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const Icon(Icons.expand_more_rounded, size: 20, color: KColors.navy),
          ],
        ),
      ),
    );
  }
}

class KTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final IconData? icon;
  final bool obscure;
  final TextInputType? keyboard;
  final Widget? suffix;
  final int maxLines;
  final ValueChanged<String>? onChanged;
  final TextCapitalization capitalization;
  const KTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.icon,
    this.obscure = false,
    this.keyboard,
    this.suffix,
    this.maxLines = 1,
    this.onChanged,
    this.capitalization = TextCapitalization.sentences,
  });
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboard,
          maxLines: maxLines,
          onChanged: onChanged,
          textCapitalization: capitalization,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: icon == null ? null : Icon(icon, size: 20, color: KColors.muted),
            suffixIcon: suffix,
          ),
        ),
      ],
    );
  }
}

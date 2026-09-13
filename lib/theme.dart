import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Khaata Book palette — navy & white (design Option A).
class KColors {
  static const navy = Color(0xFF0B2545);
  static const navyMid = Color(0xFF13315C);
  static const navyChart = Color(0xFF2F5AA8);
  static const tint = Color(0xFFE8EEF7);
  static const offWhite = Color(0xFFF4F6FA);
  static const white = Color(0xFFFFFFFF);
  static const line = Color(0xFFE5EAF2);
  static const lineSoft = Color(0xFFEEF1F6);
  static const muted = Color(0xFF6B7A90);
  static const faint = Color(0xFF98A6BC);
  static const onNavyMuted = Color(0xFFA9BBD6);
  static const green = Color(0xFF1B8A5A);
  static const greenTint = Color(0xFFE6F4EE);
  static const greenOnNavy = Color(0xFF7FD4A8);
  static const red = Color(0xFFC93B3B);
  static const redTint = Color(0xFFFBEAEA);
  static const redOnNavy = Color(0xFFFF9D9D);
  static const amber = Color(0xFFB7791F);
}

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: KColors.navy,
      primary: KColors.navy,
      surface: KColors.white,
      brightness: Brightness.light,
    ),
    scaffoldBackgroundColor: KColors.offWhite,
  );
  final text = GoogleFonts.plusJakartaSansTextTheme(base.textTheme).apply(
    bodyColor: KColors.navy,
    displayColor: KColors.navy,
  );
  return base.copyWith(
    textTheme: text,
    appBarTheme: const AppBarTheme(
      backgroundColor: KColors.navy,
      foregroundColor: KColors.white,
      elevation: 0,
      centerTitle: false,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: KColors.offWhite,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: KColors.line, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: KColors.line, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: KColors.navy, width: 1.5),
      ),
      labelStyle: const TextStyle(color: KColors.muted, fontWeight: FontWeight.w600),
      hintStyle: const TextStyle(color: KColors.faint),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: KColors.navy,
        foregroundColor: KColors.white,
        minimumSize: const Size.fromHeight(56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: KColors.navy,
        minimumSize: const Size.fromHeight(56),
        side: const BorderSide(color: KColors.navy, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: KColors.navyMid,
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    cardTheme: CardThemeData(
      color: KColors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: KColors.line),
      ),
    ),
    dividerTheme: const DividerThemeData(color: KColors.lineSoft, thickness: 1, space: 1),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: KColors.navy,
      contentTextStyle: TextStyle(color: KColors.white, fontWeight: FontWeight.w600),
      behavior: SnackBarBehavior.floating,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.all(KColors.white),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? KColors.navy : KColors.line,
      ),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: KColors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: KColors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
  );
}

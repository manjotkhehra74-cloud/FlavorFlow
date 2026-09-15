import 'package:flutter/material.dart';

/// HRMate design tokens — taken from the live webapp (hr.flavorflow.co.in).
/// FROZEN after Phase 0 (see ARCHITECTURE.md §4). Every screen uses these;
/// no feature file defines its own colours.
class HrBrand {
  static const blue = Color(0xFF1E6FE0);
  static const blueDeep = Color(0xFF1556B8);
  static const blueContainer = Color(0xFFE7F1FF);
  static const green = Color(0xFF16B878);
  static const greenContainer = Color(0xFFE1F8EF);
  static const red = Color(0xFFE5484D);
  static const redContainer = Color(0xFFFDECEC);
  static const amber = Color(0xFFF5A524);
  static const amberContainer = Color(0xFFFFF4DE);
  static const bg = Color(0xFFF4F7FB);
  static const card = Colors.white;
  static const border = Color(0xFFDDE6EF);
  static const ink = Color(0xFF172334);
  static const subInk = Color(0xFF617083);
  static const navy = Color(0xFF0B1633);

  static const radiusCard = 16.0;
  static const radiusInput = 12.0;

  static const shadow = [BoxShadow(color: Color(0x0F101828), blurRadius: 8, offset: Offset(0, 2))];
}

/// Light theme only for Phases 0–5 (dark theme is Phase 7).
ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: HrBrand.blue).copyWith(
    primary: HrBrand.blue,
    onPrimary: Colors.white,
    primaryContainer: HrBrand.blueContainer,
    onPrimaryContainer: HrBrand.blueDeep,
    secondary: HrBrand.green,
    onSecondary: Colors.white,
    secondaryContainer: HrBrand.greenContainer,
    error: HrBrand.red,
    errorContainer: HrBrand.redContainer,
    surface: HrBrand.card,
    onSurface: HrBrand.ink,
    onSurfaceVariant: HrBrand.subInk,
    outline: HrBrand.border,
    outlineVariant: HrBrand.border,
  );
  final radiusInput = BorderRadius.circular(HrBrand.radiusInput);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: HrBrand.bg,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: const AppBarTheme(
      backgroundColor: HrBrand.bg,
      foregroundColor: HrBrand.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: HrBrand.ink),
    ),
    cardTheme: CardThemeData(
      color: HrBrand.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(HrBrand.radiusCard),
        side: const BorderSide(color: HrBrand.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: radiusInput, borderSide: const BorderSide(color: HrBrand.border)),
      enabledBorder: OutlineInputBorder(borderRadius: radiusInput, borderSide: const BorderSide(color: HrBrand.border)),
      focusedBorder: OutlineInputBorder(borderRadius: radiusInput, borderSide: const BorderSide(color: HrBrand.blue, width: 1.6)),
      errorBorder: OutlineInputBorder(borderRadius: radiusInput, borderSide: const BorderSide(color: HrBrand.red)),
      labelStyle: const TextStyle(color: HrBrand.subInk),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(50),
        shape: RoundedRectangleBorder(borderRadius: radiusInput),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(50),
        shape: RoundedRectangleBorder(borderRadius: radiusInput),
        side: const BorderSide(color: HrBrand.border),
        foregroundColor: HrBrand.ink,
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    chipTheme: const ChipThemeData(
      shape: StadiumBorder(),
      side: BorderSide(color: HrBrand.border),
      backgroundColor: Colors.white,
      labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: HrBrand.ink),
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: HrBrand.blueContainer,
      height: 68,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
            fontSize: 12,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? HrBrand.blue : HrBrand.subInk,
          )),
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
            color: s.contains(WidgetState.selected) ? HrBrand.blue : HrBrand.subInk,
          )),
    ),
    dividerTheme: const DividerThemeData(color: HrBrand.border, thickness: 1, space: 1),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: radiusInput),
    ),
    textTheme: const TextTheme(
      headlineSmall: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: HrBrand.ink),
      titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: HrBrand.ink),
      titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: HrBrand.ink),
      bodyLarge: TextStyle(fontSize: 16, color: HrBrand.ink),
      bodyMedium: TextStyle(fontSize: 14, color: HrBrand.ink),
      bodySmall: TextStyle(fontSize: 12, color: HrBrand.subInk),
      labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
  );
}

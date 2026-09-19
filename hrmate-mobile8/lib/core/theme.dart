import 'package:flutter/material.dart';

/// HRMate design system — Phase 8 clean rebuild.
///
/// Tokens are extracted from the live webapp (gdfoods.duckdns.org) so the
/// native app is recognisably the SAME product: same colours, same Inter
/// typography, same card style, same navy punch card, same emerald actions.
/// Premium polish (depth, motion, spacing) is added on top — the webapp is
/// the source of truth for WHAT it looks like, this file is the only place
/// design decisions live (ARCHITECTURE.md §5).
class HrBrand {
  // --- Brand palette (webapp tokens) ---
  static const blue = Color(0xFF1E6FE0);
  static const blueDeep = Color(0xFF1556B8);
  static const blueContainer = Color(0xFFE7F1FF);
  static const green = Color(0xFF16B878);
  static const greenContainer = Color(0xFFE1F8EF);
  static const greenText = Color(0xFF06613E);
  static const emerald = Color(0xFF10B981);
  static const emeraldDeep = Color(0xFF059669);
  static const emeraldLight = Color(0xFF34D399);
  static const teal = Color(0xFF14B8A6);
  static const red = Color(0xFFEF4444);
  static const redContainer = Color(0xFFFDECEC);
  static const redText = Color(0xFFC52B35);
  static const amber = Color(0xFFF59E0B);
  static const amberContainer = Color(0xFFFFF4E0);
  static const amberText = Color(0xFFD98200);
  static const violet = Color(0xFF7C3AED);
  static const violetContainer = Color(0xFFEDE9FE);

  // --- Surfaces ---
  static const bg = Color(0xFFF4F7FB);
  static const card = Colors.white;
  static const tile = Color(0xFFF8FAFC);
  static const border = Color(0xFFDDE6EF);
  static const lineSoft = Color(0xFFE2E8F0);
  static const inputBorder = Color(0xFFC9D5E2);

  // --- Text ---
  static const ink = Color(0xFF172334);
  static const heading = Color(0xFF0F172A);
  static const subInk = Color(0xFF617083);
  static const faint = Color(0xFF94A3B8);

  // --- Navy (splash, punch card, login page) ---
  static const navy = Color(0xFF0B1633);
  static const navyDark = Color(0xFF0B132B);
  static const navyMid = Color(0xFF0F172A);
  static const navyLight = Color(0xFF1C2541);
  static const navyButton = Color(0xFF0F172A);
  static const slate = Color(0xFF1E293B); // punch-ring track
  static const ringBlue = Color(0xFF3B82F6);
  static const emeraldOnNavy = Color(0xFF6EE7B7);
  static const slateOnNavy = Color(0xFFCBD5E1);

  /// Tenant display name (webapp header subline + login company line).
  static const String company = 'GD Foods Mfg. (I) Pvt. Ltd.';

  // --- Radii (webapp: card 15–16 · field 11 · tile 14–16 · KPI 24 · punch 28 · login 32) ---
  static const radiusCard = 16.0;
  static const radiusInput = 12.0;
  static const radiusTile = 14.0;
  static const radiusKpi = 24.0;
  static const radiusPunch = 28.0;
  static const radiusLogin = 32.0;

  // --- Shadows (webapp: card `0 1.2 8 rgba(18,58,99,.10)` · pop `0 7 24 rgba(11,37,69,.14)`) ---
  static const shadow = [BoxShadow(color: Color(0x1A123A63), blurRadius: 8, offset: Offset(0, 1.2))];
  static const shadowPop = [BoxShadow(color: Color(0x240B2545), blurRadius: 24, offset: Offset(0, 7))];
  static const shadowGlow = [BoxShadow(color: Color(0x471E6FE0), blurRadius: 24, offset: Offset(0, 10))];
  static const shadowPunch = [BoxShadow(color: Color(0x6610B981), blurRadius: 20, offset: Offset(0, 4))];

  /// Navy gradient of the punch card / login page (`#0B132B → #0F172A → #1C2541`).
  static const punchGradient = [navyDark, navyMid, navyLight];
  /// Emerald gradient of the primary action (`emerald-600 → teal-500 → emerald-500`).
  static const punchButtonGradient = [emeraldDeep, teal, emerald];

  /// Premium motion — every animated widget uses these (ARCHITECTURE.md §5).
  static const fast = Duration(milliseconds: 140);
  static const base = Duration(milliseconds: 220);
  static const slow = Duration(milliseconds: 320);
}

/// Light theme mirroring the webapp. Dark theme is a later phase — the
/// webapp itself defaults to light.
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
    outline: HrBrand.inputBorder,
    outlineVariant: HrBrand.lineSoft,
  );
  final radiusInput = BorderRadius.circular(HrBrand.radiusInput);
  return ThemeData(
    useMaterial3: true,
    // Inter ships in assets/fonts (pubspec) — the webapp's typeface.
    fontFamily: 'Inter',
    colorScheme: scheme,
    scaffoldBackgroundColor: HrBrand.bg,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: const AppBarTheme(
      backgroundColor: HrBrand.card,
      foregroundColor: HrBrand.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: HrBrand.heading),
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: OutlineInputBorder(borderRadius: radiusInput, borderSide: const BorderSide(color: HrBrand.inputBorder)),
      enabledBorder: OutlineInputBorder(borderRadius: radiusInput, borderSide: const BorderSide(color: HrBrand.inputBorder)),
      focusedBorder: OutlineInputBorder(borderRadius: radiusInput, borderSide: const BorderSide(color: HrBrand.blue, width: 1.6)),
      errorBorder: OutlineInputBorder(borderRadius: radiusInput, borderSide: const BorderSide(color: HrBrand.red)),
      focusedErrorBorder: OutlineInputBorder(borderRadius: radiusInput, borderSide: const BorderSide(color: HrBrand.red, width: 1.4)),
      labelStyle: const TextStyle(fontSize: 13, color: HrBrand.subInk),
      hintStyle: const TextStyle(fontSize: 13, color: HrBrand.faint),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 46),
        shape: RoundedRectangleBorder(borderRadius: radiusInput),
        textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 44),
        shape: RoundedRectangleBorder(borderRadius: radiusInput),
        side: const BorderSide(color: HrBrand.inputBorder),
        foregroundColor: HrBrand.ink,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        foregroundColor: HrBrand.blue,
        textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
      ),
    ),
    chipTheme: const ChipThemeData(
      shape: StadiumBorder(),
      side: BorderSide(color: HrBrand.lineSoft),
      backgroundColor: Colors.white,
      labelStyle: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: HrBrand.ink),
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    dividerTheme: const DividerThemeData(color: HrBrand.lineSoft, thickness: 1, space: 1),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: radiusInput),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: HrBrand.blue, strokeWidth: 2.6),
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? HrBrand.green : HrBrand.lineSoft,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    textTheme: const TextTheme(
      headlineSmall: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: HrBrand.heading),
      titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: HrBrand.heading),
      titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: HrBrand.ink),
      titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: HrBrand.ink),
      bodyLarge: TextStyle(fontSize: 16, color: HrBrand.ink),
      bodyMedium: TextStyle(fontSize: 14, color: HrBrand.ink),
      bodySmall: TextStyle(fontSize: 12, color: HrBrand.subInk),
      labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: HrBrand.ink),
    ),
  );
}

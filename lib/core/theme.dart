import 'package:flutter/material.dart';

/// FlavorFlow ERP theme — enterprise console look (SAP Business One / Fiori inspired):
/// flat white surfaces, hairline borders, dense controls, dark navigation shell,
/// Inter typography with tabular numbers.
ThemeData buildTheme({bool dark = false}) {
  const primary = Color(0xFF1E6FE0); // logo blue
  const accent = Color(0xFF22C55E); // logo green
  final ink = dark ? const Color(0xFFE4EAF0) : const Color(0xFF1B2733);
  final subInk = dark ? const Color(0xFF9AA8B5) : const Color(0xFF5C6B7A);

  final base = ColorScheme.fromSeed(seedColor: primary, brightness: dark ? Brightness.dark : Brightness.light);
  final scheme = dark
      ? base.copyWith(
          primary: const Color(0xFF64A8E8),
          onPrimary: const Color(0xFF0B2A47),
          primaryContainer: const Color(0xFF15385C),
          onPrimaryContainer: const Color(0xFFBBD9F5),
          secondary: const Color(0xFF4ADE80),
          surface: const Color(0xFF14191F),
          onSurface: const Color(0xFFE4EAF0),
          onSurfaceVariant: const Color(0xFF9AA8B5),
          surfaceContainerLowest: const Color(0xFF0F1419),
          surfaceContainerLow: const Color(0xFF181E25),
          surfaceContainerHigh: const Color(0xFF1F262E),
          surfaceContainerHighest: const Color(0xFF262E37),
          outline: const Color(0xFF5B6875),
          outlineVariant: const Color(0xFF313A44),
          error: const Color(0xFFFF6B6B),
        )
      : base.copyWith(
    primary: primary,
    onPrimary: Colors.white,
    primaryContainer: const Color(0xFFE1EEFB),
    onPrimaryContainer: const Color(0xFF0B4E96),
    secondary: accent,
    surface: Colors.white,
    onSurface: ink,
    onSurfaceVariant: subInk,
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: const Color(0xFFF8FAFC),
    surfaceContainerHigh: const Color(0xFFF1F5F9),
    surfaceContainerHighest: const Color(0xFFE9EEF3),
    outline: const Color(0xFF94A3B8),
    outlineVariant: const Color(0xFFDDE3EA),
    error: const Color(0xFFBB0000),
  );

  const family = 'Inter';

  TextStyle txt(double size, FontWeight w, {Color? color, double? ls, double? h}) => TextStyle(
        fontFamily: family,
        fontSize: size,
        fontWeight: w,
        color: color,
        letterSpacing: ls,
        height: h,
      );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: family,
    fontFamilyFallback: const ['Roboto', 'Segoe UI', 'Arial'],
    scaffoldBackgroundColor: dark ? const Color(0xFF0F1419) : const Color(0xFFF5F8FC),
    visualDensity: VisualDensity.standard,
    textTheme: TextTheme(
      headlineSmall: txt(20, FontWeight.w700, color: ink, ls: -0.3),
      titleLarge: txt(17, FontWeight.w700, color: ink, ls: -0.2),
      titleMedium: txt(14.5, FontWeight.w600, color: ink),
      titleSmall: txt(13, FontWeight.w600, color: ink),
      bodyLarge: txt(14, FontWeight.w400, color: ink),
      bodyMedium: txt(13, FontWeight.w400, color: ink),
      bodySmall: txt(12, FontWeight.w400, color: subInk),
      labelLarge: txt(13, FontWeight.w600, color: ink),
      labelSmall: txt(11, FontWeight.w600, color: subInk, ls: 0.4),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      toolbarHeight: 54,
      titleTextStyle: txt(16.5, FontWeight.w700, color: ink, ls: -0.2),
      iconTheme: IconThemeData(color: subInk, size: 21),
    ),
    cardTheme: CardThemeData(
      color: scheme.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: dark ? const Color(0xFF2A333D) : const Color(0xFFE7EDF4)),
      ),
      shadowColor: const Color(0x140F2440),
      clipBehavior: Clip.antiAlias,
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: scheme.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFC3CEDA))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFC3CEDA))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: primary, width: 1.6)),
      labelStyle: txt(12.5, FontWeight.w500, color: subInk),
      isDense: true,
    ),
    dataTableTheme: DataTableThemeData(
      headingRowColor: WidgetStatePropertyAll(dark ? const Color(0xFF1F262E) : const Color(0xFFF5F8FB)),
      headingRowHeight: 38,
      dataRowMinHeight: 40,
      dataRowMaxHeight: 46,
      headingTextStyle: txt(11, FontWeight.w700, color: const Color(0xFF55677A), ls: 0.6),
      dataTextStyle: txt(12.8, FontWeight.w400, color: ink),
      dataRowColor: const WidgetStateProperty.fromMap({WidgetState.hovered: Color(0xFFF3F8FD)}),
      horizontalMargin: 14,
      columnSpacing: 26,
      dividerThickness: 0.6,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: scheme.onPrimary,
        disabledBackgroundColor: const Color(0xFFBCD3EA),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        minimumSize: const Size(0, 40),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: txt(13, FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ink,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        minimumSize: const Size(0, 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: const BorderSide(color: Color(0xFFC3CEDA)),
        textStyle: txt(13, FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primary,
        minimumSize: const Size(0, 34),
        textStyle: txt(13, FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: subInk, iconSize: 20),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: txt(16, FontWeight.w700, color: ink),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: primary,
      unselectedLabelColor: subInk,
      indicatorColor: primary,
      labelStyle: txt(13, FontWeight.w700),
      unselectedLabelStyle: txt(13, FontWeight.w500),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Color(0xFFE2E8EF))),
      textStyle: txt(13, FontWeight.w500, color: ink),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: ink, borderRadius: BorderRadius.circular(4)),
      textStyle: txt(11.5, FontWeight.w500, color: Colors.white),
    ),
    scrollbarTheme: const ScrollbarThemeData(
      thumbVisibility: WidgetStatePropertyAll(true),
      thickness: WidgetStatePropertyAll(6),
      radius: Radius.circular(3),
    ),
    listTileTheme: ListTileThemeData(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 1),
      titleTextStyle: txt(13, FontWeight.w500, color: ink),
      subtitleTextStyle: txt(12, FontWeight.w400, color: subInk),
    ),
    dividerTheme: const DividerThemeData(color: Color(0xFFE4E9EF), thickness: 1, space: 1),
    chipTheme: const ChipThemeData(padding: EdgeInsets.symmetric(horizontal: 4, vertical: 0)),
  );
}

/// Dark shell palette (sidebar + login brand panel).
class Shell {
  static const bg = Color(0xFF0C2135);        // deep navy
  static const bgDeep = Color(0xFF081827);    // darker footer strip
  static const groupLabel = Color(0xFF7C93A8);
  static const item = Color(0xFFC9D6E2);
  static const itemHover = Color(0x14FFFFFF);
  static const itemSelected = Color(0xFF133C63);
  static const itemSelectedBar = Color(0xFF22C55E); // logo green accent
  static const border = Color(0xFF1C3850);
}

/// Semantic colors used across dashboards.
class AppColors {
  static const green = Color(0xFF16A34A);
  static const red = Color(0xFFDC2626);
  static const amber = Color(0xFFD97706);
  static const blue = Color(0xFF1E6FE0);
  static const teal = Color(0xFF0D9488);
  static const violet = Color(0xFF7C3AED);
  static const orange = Color(0xFFEA580C);
  static const pink = Color(0xFFDB2777);
  static const cyan = Color(0xFF0891B2);
  static const slate = Color(0xFF51606F);

  static const chart = [blue, teal, amber, violet, orange, cyan, pink, green, slate];
}

Color hexColor(String? hex, {Color fallback = AppColors.blue}) {
  if (hex == null) return fallback;
  final s = hex.replaceAll('#', '');
  final v = int.tryParse(s, radix: 16);
  return v == null ? fallback : Color(0xFF000000 | v);
}

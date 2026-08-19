import 'package:flutter/material.dart';

/// FlavorFlow's visual identity, derived from the Flow Mark logo.
/// Keep brand colours here so the shell, dashboard and feature pages stay in sync.
class AppBrand {
  static const blue = Color(0xFF1E6FE0);
  static const blueDeep = Color(0xFF1556B8);
  static const green = Color(0xFF16B878);
  static const greenDeep = Color(0xFF07945D);
  static const navy = Color(0xFF081C33);

  static const gradient = LinearGradient(
    colors: [blue, Color(0xFF258FD0), green],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

/// Modern, compact ERP theme. Light and dark palettes share the Flow Mark
/// blue-to-green identity while preserving dense, readable data screens.
ThemeData buildTheme({bool dark = false}) {
  final ink = dark ? const Color(0xFFF0F5FA) : const Color(0xFF172334);
  final subInk = dark ? const Color(0xFFA7B4C2) : const Color(0xFF617083);
  final surface = dark ? const Color(0xFF151D27) : Colors.white;
  final border = dark ? const Color(0xFF2D3947) : const Color(0xFFDDE6EF);
  final fieldBorder = dark ? const Color(0xFF3B4958) : const Color(0xFFC9D5E2);

  final base = ColorScheme.fromSeed(
    seedColor: AppBrand.blue,
    brightness: dark ? Brightness.dark : Brightness.light,
  );
  final scheme = base.copyWith(
    primary: dark ? const Color(0xFF78B4FF) : AppBrand.blue,
    onPrimary: dark ? const Color(0xFF06244A) : Colors.white,
    primaryContainer: dark ? const Color(0xFF173D68) : const Color(0xFFE7F1FF),
    onPrimaryContainer: dark ? const Color(0xFFD7E9FF) : const Color(0xFF124C9D),
    secondary: dark ? const Color(0xFF51D8A3) : AppBrand.greenDeep,
    onSecondary: dark ? const Color(0xFF063625) : Colors.white,
    secondaryContainer: dark ? const Color(0xFF123E31) : const Color(0xFFE1F8EF),
    onSecondaryContainer: dark ? const Color(0xFFB6F3DB) : const Color(0xFF06613E),
    surface: surface,
    onSurface: ink,
    onSurfaceVariant: subInk,
    surfaceContainerLowest: dark ? const Color(0xFF0D131B) : Colors.white,
    surfaceContainerLow: dark ? const Color(0xFF121922) : const Color(0xFFF8FAFD),
    surfaceContainer: dark ? const Color(0xFF18212B) : const Color(0xFFF3F7FB),
    surfaceContainerHigh: dark ? const Color(0xFF202A35) : const Color(0xFFEDF3F8),
    surfaceContainerHighest: dark ? const Color(0xFF283440) : const Color(0xFFE6EDF4),
    outline: dark ? const Color(0xFF637181) : const Color(0xFF91A1B3),
    outlineVariant: border,
    error: dark ? const Color(0xFFFF7B7B) : const Color(0xFFC52B35),
  );

  const family = 'Inter';
  TextStyle txt(double size, FontWeight weight, {Color? color, double? ls, double? h}) => TextStyle(
        fontFamily: family,
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: ls,
        height: h,
      );

  OutlineInputBorder inputBorder(Color color, {double width = 1}) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: BorderSide(color: color, width: width),
      );

  return ThemeData(
    useMaterial3: true,
    brightness: dark ? Brightness.dark : Brightness.light,
    colorScheme: scheme,
    fontFamily: family,
    fontFamilyFallback: const ['Roboto', 'Segoe UI', 'Arial'],
    scaffoldBackgroundColor: dark ? const Color(0xFF0E151D) : const Color(0xFFF4F7FB),
    canvasColor: surface,
    shadowColor: const Color(0xFF0B2545).withValues(alpha: dark ? 0.28 : 0.10),
    visualDensity: VisualDensity.standard,
    textTheme: TextTheme(
      headlineSmall: txt(21, FontWeight.w700, color: ink, ls: -0.45),
      titleLarge: txt(17.5, FontWeight.w700, color: ink, ls: -0.25),
      titleMedium: txt(14.5, FontWeight.w600, color: ink),
      titleSmall: txt(13, FontWeight.w600, color: ink),
      bodyLarge: txt(14, FontWeight.w400, color: ink, h: 1.4),
      bodyMedium: txt(13, FontWeight.w400, color: ink, h: 1.35),
      bodySmall: txt(12, FontWeight.w400, color: subInk, h: 1.35),
      labelLarge: txt(13, FontWeight.w600, color: ink),
      labelSmall: txt(11, FontWeight.w600, color: subInk, ls: 0.35),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      toolbarHeight: 62,
      titleTextStyle: txt(17, FontWeight.w700, color: ink, ls: -0.25),
      iconTheme: IconThemeData(color: subInk, size: 22),
    ),
    cardTheme: CardThemeData(
      color: surface,
      surfaceTintColor: Colors.transparent,
      elevation: dark ? 0 : 1.2,
      shadowColor: const Color(0xFF123A63).withValues(alpha: 0.10),
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: BorderSide(color: border),
      ),
      clipBehavior: Clip.antiAlias,
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: dark ? const Color(0xFF111923) : Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: inputBorder(fieldBorder),
      enabledBorder: inputBorder(fieldBorder),
      focusedBorder: inputBorder(scheme.primary, width: 1.8),
      errorBorder: inputBorder(scheme.error),
      focusedErrorBorder: inputBorder(scheme.error, width: 1.8),
      labelStyle: txt(12.5, FontWeight.w500, color: subInk),
      hintStyle: txt(12.5, FontWeight.w400, color: subInk.withValues(alpha: 0.75)),
      prefixIconColor: subInk,
      suffixIconColor: subInk,
      isDense: true,
    ),
    dataTableTheme: DataTableThemeData(
      headingRowColor: WidgetStatePropertyAll(scheme.surfaceContainerLow),
      headingRowHeight: 42,
      dataRowMinHeight: 42,
      dataRowMaxHeight: 50,
      headingTextStyle: txt(10.8, FontWeight.w700, color: subInk, ls: 0.65),
      dataTextStyle: txt(12.8, FontWeight.w400, color: ink),
      dataRowColor: WidgetStateProperty.fromMap({
        WidgetState.hovered: scheme.primary.withValues(alpha: dark ? 0.08 : 0.045),
      }),
      horizontalMargin: 16,
      columnSpacing: 28,
      dividerThickness: 0.65,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: dark ? scheme.primary : AppBrand.blue,
        foregroundColor: scheme.onPrimary,
        disabledBackgroundColor: dark ? const Color(0xFF334353) : const Color(0xFFBED1E8),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        minimumSize: const Size(0, 40),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: txt(13, FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ink,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        minimumSize: const Size(0, 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: BorderSide(color: fieldBorder),
        textStyle: txt(13, FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: scheme.primary,
        minimumSize: const Size(0, 38),
        textStyle: txt(13, FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: subInk, iconSize: 20),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? const Color(0xFF273543) : AppBrand.navy,
      contentTextStyle: txt(12.8, FontWeight.w500, color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: txt(17, FontWeight.w700, color: ink),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: scheme.primary,
      unselectedLabelColor: subInk,
      indicatorColor: scheme.primary,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: border,
      labelStyle: txt(13, FontWeight.w700),
      unselectedLabelStyle: txt(13, FontWeight.w500),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? scheme.primary : null),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? Colors.white : null),
      trackColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? AppBrand.green : null),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
    popupMenuTheme: PopupMenuThemeData(
      color: surface,
      surfaceTintColor: Colors.transparent,
      elevation: 7,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13), side: BorderSide(color: border)),
      textStyle: txt(13, FontWeight.w500, color: ink),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: dark ? const Color(0xFFDFE9F2) : AppBrand.navy, borderRadius: BorderRadius.circular(7)),
      textStyle: txt(11.5, FontWeight.w500, color: dark ? AppBrand.navy : Colors.white),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbVisibility: const WidgetStatePropertyAll(true),
      thumbColor: WidgetStatePropertyAll(scheme.outline.withValues(alpha: 0.60)),
      thickness: const WidgetStatePropertyAll(6),
      radius: const Radius.circular(8),
    ),
    listTileTheme: ListTileThemeData(
      dense: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      titleTextStyle: txt(13, FontWeight.w500, color: ink),
      subtitleTextStyle: txt(12, FontWeight.w400, color: subInk),
    ),
    dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
    chipTheme: ChipThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      side: BorderSide(color: border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    ),
  );
}

/// Dark navigation shell palette.
class Shell {
  static const bg = Color(0xFF0A2037);
  static const bgDeep = Color(0xFF071827);
  static const groupLabel = Color(0xFF7892AA);
  static const item = Color(0xFFC6D5E3);
  static const itemHover = Color(0x12FFFFFF);
  static const itemSelected = Color(0xFF173D64);
  static const itemSelectedBar = AppBrand.green;
  static const border = Color(0xFF1A3A55);
  static const gradient = LinearGradient(
    colors: [Color(0xFF0B2743), Color(0xFF081C31)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

/// Semantic colours used across dashboards and charts.
class AppColors {
  static const green = Color(0xFF07945D);
  static const red = Color(0xFFDC3545);
  static const amber = Color(0xFFD98200);
  static const blue = AppBrand.blue;
  static const teal = Color(0xFF0B9F99);
  static const violet = Color(0xFF7657D6);
  static const orange = Color(0xFFE5622A);
  static const pink = Color(0xFFD84F91);
  static const cyan = Color(0xFF159CB8);
  static const slate = Color(0xFF617083);

  static const chart = [blue, green, teal, amber, violet, orange, cyan, pink, slate];
}

Color hexColor(String? hex, {Color fallback = AppColors.blue}) {
  if (hex == null) return fallback;
  final s = hex.replaceAll('#', '');
  final v = int.tryParse(s, radix: 16);
  return v == null ? fallback : Color(0xFF000000 | v);
}

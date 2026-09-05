import 'package:flutter/material.dart';

/// Shared visual tokens for the field workspace and procurement screens.
class AppColors {
  static const ink = Color(0xFF182C3B);
  static const muted = Color(0xFF586C7A);
  static const line = Color(0xFFDFE6E9);
  static const surface = Color(0xFFF3F5F4);
  static const controlSurface = Colors.white;
  static const primary = Color(0xFF183D52);
  static const controlSelected = Color(0xFFE0EDEB);
  static const teal = Color(0xFF17695D);
  static const amber = Color(0xFF98601D);
  static const danger = Color(0xFFAE3539);
}

ThemeData buildAppTheme() {
  const scheme = ColorScheme.light(
    primary: AppColors.primary,
    onPrimary: Colors.white,
    primaryContainer: Color(0xFFE3EBF0),
    onPrimaryContainer: AppColors.primary,
    secondary: AppColors.teal,
    onSecondary: Colors.white,
    secondaryContainer: AppColors.controlSelected,
    onSecondaryContainer: AppColors.teal,
    error: AppColors.danger,
    onError: Colors.white,
    surface: Colors.white,
    onSurface: AppColors.ink,
    onSurfaceVariant: AppColors.muted,
    surfaceContainerHighest: Color(0xFFEDF1F2),
    outline: Color(0xFF84959F),
    outlineVariant: AppColors.line,
  );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
  final input = OutlineInputBorder(
    borderRadius: BorderRadius.circular(10),
    borderSide: const BorderSide(color: Color(0xFFB6C3CA)),
  );
  const typography = TextTheme(
    headlineLarge: TextStyle(fontSize: 32, height: 1.2, fontWeight: FontWeight.w700, letterSpacing: -1),
    headlineMedium: TextStyle(fontSize: 28, height: 1.25, fontWeight: FontWeight.w700, letterSpacing: -0.8),
    headlineSmall: TextStyle(fontSize: 24, height: 1.3, fontWeight: FontWeight.w700, letterSpacing: -0.5),
    titleLarge: TextStyle(fontSize: 20, height: 1.3, fontWeight: FontWeight.w700, letterSpacing: -0.3),
    titleMedium: TextStyle(fontSize: 16, height: 1.4, fontWeight: FontWeight.w600),
    titleSmall: TextStyle(fontSize: 14, height: 1.4, fontWeight: FontWeight.w600),
    bodyLarge: TextStyle(fontSize: 16, height: 1.5),
    bodyMedium: TextStyle(fontSize: 14, height: 1.5),
    bodySmall: TextStyle(fontSize: 12, height: 1.5, color: AppColors.muted),
    labelLarge: TextStyle(fontSize: 14, height: 1.2, fontWeight: FontWeight.w600),
    labelMedium: TextStyle(fontSize: 12, height: 1.3, fontWeight: FontWeight.w600),
    labelSmall: TextStyle(fontSize: 11, height: 1.3, fontWeight: FontWeight.w600, letterSpacing: 0.4),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'PublicSans',
    textTheme: typography.apply(fontFamily: 'PublicSans', bodyColor: AppColors.ink, displayColor: AppColors.ink),
    scaffoldBackgroundColor: AppColors.surface,
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    iconTheme: const IconThemeData(size: 22, color: AppColors.muted),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      toolbarHeight: 64,
      titleSpacing: 20,
      titleTextStyle: TextStyle(fontFamily: 'PublicSans', color: AppColors.ink,
          fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.4),
    ),
    cardTheme: CardThemeData(
      color: Colors.white, surfaceTintColor: Colors.transparent, elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.line)),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.line, thickness: 1, space: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true, fillColor: Colors.white,
      border: input, enabledBorder: input,
      focusedBorder: input.copyWith(borderSide: const BorderSide(color: AppColors.teal, width: 2)),
      errorBorder: input.copyWith(borderSide: const BorderSide(color: AppColors.danger)),
      focusedErrorBorder: input.copyWith(borderSide: const BorderSide(color: AppColors.danger, width: 2)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      labelStyle: const TextStyle(color: AppColors.muted, fontSize: 14),
      floatingLabelStyle: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600),
      hintStyle: const TextStyle(color: AppColors.muted, fontSize: 14),
      helperStyle: const TextStyle(color: AppColors.muted, height: 1.4),
      errorMaxLines: 3,
      prefixIconColor: AppColors.muted, suffixIconColor: AppColors.muted,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(style: ElevatedButton.styleFrom(
      backgroundColor: AppColors.primary, foregroundColor: Colors.white,
      elevation: 0, minimumSize: const Size(48, 48), shape: shape,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      textStyle: const TextStyle(fontFamily: 'PublicSans', fontWeight: FontWeight.w600, fontSize: 14),
    )),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
      backgroundColor: AppColors.primary, foregroundColor: Colors.white,
      minimumSize: const Size(48, 48), shape: shape,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      textStyle: const TextStyle(fontFamily: 'PublicSans', fontWeight: FontWeight.w600, fontSize: 14),
    )),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(
      foregroundColor: AppColors.primary, backgroundColor: Colors.white,
      minimumSize: const Size(48, 48), shape: shape,
      side: const BorderSide(color: Color(0xFFB6C3CA)),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    )),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(
      foregroundColor: AppColors.primary, minimumSize: const Size(48, 48), shape: shape,
    )),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(
      minimumSize: const Size(48, 48), foregroundColor: AppColors.primary,
    )),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: AppColors.primary, foregroundColor: Colors.white,
      elevation: 3, shape: shape,
      extendedTextStyle: const TextStyle(fontFamily: 'PublicSans', fontSize: 14, fontWeight: FontWeight.w600),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.white, selectedColor: AppColors.controlSelected,
      disabledColor: const Color(0xFFF0F2F3),
      side: const BorderSide(color: AppColors.line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      labelStyle: const TextStyle(fontFamily: 'PublicSans', fontSize: 12, color: AppColors.ink, fontWeight: FontWeight.w600),
      secondaryLabelStyle: const TextStyle(fontFamily: 'PublicSans', color: AppColors.teal, fontWeight: FontWeight.w700),
      checkmarkColor: AppColors.teal,
      iconTheme: const IconThemeData(size: 18, color: AppColors.teal),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: AppColors.primary, unselectedLabelColor: AppColors.muted,
      indicatorColor: AppColors.teal, indicatorSize: TabBarIndicatorSize.label,
      dividerColor: AppColors.line,
      labelStyle: TextStyle(fontFamily: 'PublicSans', fontWeight: FontWeight.w700, fontSize: 14),
      unselectedLabelStyle: TextStyle(fontFamily: 'PublicSans', fontSize: 14),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white, surfaceTintColor: Colors.transparent,
      indicatorColor: AppColors.controlSelected, elevation: 0, height: 76,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
        fontFamily: 'PublicSans', fontSize: 11, height: 1.2,
        fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
        color: states.contains(WidgetState.selected) ? AppColors.primary : AppColors.muted,
      )),
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
        size: 23, color: states.contains(WidgetState.selected) ? AppColors.teal : AppColors.muted,
      )),
    ),
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: Colors.white, indicatorColor: AppColors.controlSelected,
      selectedIconTheme: IconThemeData(color: AppColors.teal),
      unselectedIconTheme: IconThemeData(color: AppColors.muted),
      selectedLabelTextStyle: TextStyle(fontFamily: 'PublicSans', color: AppColors.primary, fontWeight: FontWeight.w700),
      unselectedLabelTextStyle: TextStyle(fontFamily: 'PublicSans', color: AppColors.muted),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white, surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titleTextStyle: typography.titleLarge?.copyWith(fontFamily: 'PublicSans', color: AppColors.ink),
      contentTextStyle: typography.bodyMedium?.copyWith(fontFamily: 'PublicSans', color: AppColors.muted),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white, surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating, backgroundColor: AppColors.ink,
      contentTextStyle: const TextStyle(fontFamily: 'PublicSans', color: Colors.white),
      actionTextColor: const Color(0xFFA8DED2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: AppColors.muted, textColor: AppColors.ink,
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      minVerticalPadding: 12, horizontalTitleGap: 14,
      subtitleTextStyle: TextStyle(fontFamily: 'PublicSans', color: AppColors.muted, fontSize: 13, height: 1.45),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.teal),
    dataTableTheme: const DataTableThemeData(
      headingRowColor: WidgetStatePropertyAll(Color(0xFFEDF2F3)),
      headingRowHeight: 52, dataRowMinHeight: 52, dataRowMaxHeight: 88,
      columnSpacing: 28, horizontalMargin: 20,
      headingTextStyle: TextStyle(fontFamily: 'PublicSans', fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 12),
      dataTextStyle: TextStyle(fontFamily: 'PublicSans', color: AppColors.ink, fontSize: 13),
      dividerThickness: 1,
    ),
    tooltipTheme: TooltipThemeData(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(8)),
      textStyle: const TextStyle(fontFamily: 'PublicSans', color: Colors.white, fontSize: 12),
    ),
  );
}

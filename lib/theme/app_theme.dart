import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shared visual tokens for the field workspace and procurement screens.
class AppColors {
  static const ink = Color(0xFF102C37);
  static const muted = Color(0xFF60747C);
  static const line = Color(0xFFD6E1DE);
  static const surface = Color(0xFFF4F7F4);
  static const controlSurface = Colors.white;
  static const primary = Color(0xFF123F4C);
  static const primaryBright = Color(0xFF245D69);
  static const controlSelected = Color(0xFFDDF2ED);
  static const teal = Color(0xFF007B70);
  static const tealBright = Color(0xFF0B9A88);
  static const amber = Color(0xFFAD6918);
  static const gold = Color(0xFFD8AD5A);
  static const cobalt = Color(0xFF3567A9);
  static const danger = Color(0xFFB83B47);
}

/// Converts light-theme brand neutrals into readable semantic dark colors.
Color adaptiveAppColor(BuildContext context, Color color) {
  if (Theme.of(context).brightness != Brightness.dark) return color;
  final scheme = Theme.of(context).colorScheme;
  if (color == AppColors.ink) return scheme.onSurface;
  if (color == AppColors.muted) return scheme.onSurfaceVariant;
  if (color == AppColors.primary || color == AppColors.teal) {
    return scheme.primary;
  }
  return color;
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
    tertiary: AppColors.amber,
    onTertiary: Colors.white,
    tertiaryContainer: Color(0xFFFFEBCB),
    onTertiaryContainer: Color(0xFF643900),
    error: AppColors.danger,
    onError: Colors.white,
    surface: Colors.white,
    onSurface: AppColors.ink,
    onSurfaceVariant: AppColors.muted,
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: Color(0xFFF8FAF9),
    surfaceContainer: Color(0xFFEDF3F1),
    surfaceContainerHigh: Color(0xFFE6EEEC),
    surfaceContainerHighest: Color(0xFFDDE7E5),
    outline: Color(0xFF7B9095),
    outlineVariant: AppColors.line,
  );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
  final input = OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: const BorderSide(color: Color(0xFFB6C3CA)),
  );
  const typography = TextTheme(
    headlineLarge:
        TextStyle(fontSize: 32, height: 1.12, fontWeight: FontWeight.w800, letterSpacing: -0.7),
    headlineMedium:
        TextStyle(fontSize: 27, height: 1.16, fontWeight: FontWeight.w800, letterSpacing: -0.5),
    headlineSmall:
        TextStyle(fontSize: 22, height: 1.2, fontWeight: FontWeight.w800, letterSpacing: -0.25),
    titleLarge:
        TextStyle(fontSize: 20, height: 1.3, fontWeight: FontWeight.w800),
    titleMedium:
        TextStyle(fontSize: 16, height: 1.35, fontWeight: FontWeight.w700),
    titleSmall:
        TextStyle(fontSize: 14, height: 1.4, fontWeight: FontWeight.w600),
    bodyLarge: TextStyle(fontSize: 16, height: 1.5),
    bodyMedium: TextStyle(fontSize: 14, height: 1.5),
    bodySmall: TextStyle(fontSize: 12, height: 1.5, color: AppColors.muted),
    labelLarge:
        TextStyle(fontSize: 14, height: 1.2, fontWeight: FontWeight.w600),
    labelMedium:
        TextStyle(fontSize: 12, height: 1.3, fontWeight: FontWeight.w600),
    labelSmall:
        TextStyle(fontSize: 11, height: 1.3, fontWeight: FontWeight.w600),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'PublicSans',
    textTheme: typography.apply(
        fontFamily: 'PublicSans',
        bodyColor: AppColors.ink,
        displayColor: AppColors.ink),
    scaffoldBackgroundColor: AppColors.surface,
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    iconTheme: const IconThemeData(size: 22, color: AppColors.primary),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      toolbarHeight: 64,
      titleSpacing: 20,
      iconTheme: IconThemeData(color: Colors.white),
      actionsIconTheme: IconThemeData(color: Colors.white),
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: AppColors.primary,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      titleTextStyle: TextStyle(
          fontFamily: 'PublicSans',
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w800),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shadowColor: const Color(0x1F102C37),
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFCFE0DC))),
    ),
    dividerTheme:
        const DividerThemeData(color: AppColors.line, thickness: 1, space: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFFBFDFC),
      border: input,
      enabledBorder: input,
      focusedBorder: input.copyWith(
          borderSide: const BorderSide(color: AppColors.teal, width: 2)),
      errorBorder:
          input.copyWith(borderSide: const BorderSide(color: AppColors.danger)),
      focusedErrorBorder: input.copyWith(
          borderSide: const BorderSide(color: AppColors.danger, width: 2)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      labelStyle: const TextStyle(
          color: AppColors.muted, fontSize: 14, fontWeight: FontWeight.w500),
      floatingLabelStyle:
          const TextStyle(color: AppColors.teal, fontWeight: FontWeight.w700),
      hintStyle: const TextStyle(color: AppColors.muted, fontSize: 14),
      helperStyle: const TextStyle(color: AppColors.muted, height: 1.4),
      errorMaxLines: 3,
      prefixIconColor: AppColors.muted,
      suffixIconColor: AppColors.muted,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      elevation: 0,
      minimumSize: const Size(48, 48),
      shape: shape,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      textStyle: const TextStyle(
          fontFamily: 'PublicSans', fontWeight: FontWeight.w600, fontSize: 14),
    )),
    filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
      backgroundColor: AppColors.teal,
      foregroundColor: Colors.white,
      minimumSize: const Size(48, 48),
      shape: shape,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      textStyle: const TextStyle(
          fontFamily: 'PublicSans', fontWeight: FontWeight.w700, fontSize: 14),
    )),
    outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
      foregroundColor: AppColors.primary,
      backgroundColor: Colors.white,
      minimumSize: const Size(48, 48),
      shape: shape,
      side: const BorderSide(color: Color(0xFFB6C3CA)),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    )),
    textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
      foregroundColor: AppColors.primary,
      minimumSize: const Size(48, 48),
      shape: shape,
    )),
    iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
      minimumSize: const Size(48, 48),
      foregroundColor: AppColors.primary,
    )),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: AppColors.teal,
      foregroundColor: Colors.white,
      elevation: 2,
      focusElevation: 3,
      hoverElevation: 3,
      shape: shape,
      extendedTextStyle: const TextStyle(
          fontFamily: 'PublicSans', fontSize: 14, fontWeight: FontWeight.w600),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.white,
      selectedColor: AppColors.controlSelected,
      disabledColor: const Color(0xFFF0F2F3),
      side: const BorderSide(color: AppColors.line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      labelStyle: const TextStyle(
          fontFamily: 'PublicSans',
          fontSize: 12,
          color: AppColors.ink,
          fontWeight: FontWeight.w600),
      secondaryLabelStyle: const TextStyle(
          fontFamily: 'PublicSans',
          color: AppColors.teal,
          fontWeight: FontWeight.w700),
      checkmarkColor: AppColors.teal,
      iconTheme: const IconThemeData(size: 18, color: AppColors.teal),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? AppColors.primary
                : AppColors.muted),
        backgroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? AppColors.controlSelected
                : Colors.white),
        side: const WidgetStatePropertyAll(BorderSide(color: AppColors.line)),
        shape: WidgetStatePropertyAll(shape),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(
              fontFamily: 'PublicSans',
              fontWeight: FontWeight.w700,
              fontSize: 13),
        ),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? Colors.white
              : AppColors.muted),
      trackColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? AppColors.teal
              : const Color(0xFFDCE4E5)),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? AppColors.teal
              : Colors.transparent),
      checkColor: const WidgetStatePropertyAll(Colors.white),
      side: const BorderSide(color: AppColors.muted, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? AppColors.teal
              : AppColors.muted),
    ),
    badgeTheme: const BadgeThemeData(
      backgroundColor: AppColors.amber,
      textColor: Colors.white,
      textStyle: TextStyle(
          fontFamily: 'PublicSans', fontWeight: FontWeight.w700, fontSize: 11),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: AppColors.primary,
      unselectedLabelColor: AppColors.muted,
      indicatorColor: AppColors.teal,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: AppColors.line,
      labelStyle: TextStyle(
          fontFamily: 'PublicSans', fontWeight: FontWeight.w700, fontSize: 14),
      unselectedLabelStyle: TextStyle(fontFamily: 'PublicSans', fontSize: 14),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.primary,
      surfaceTintColor: Colors.transparent,
      indicatorColor: const Color(0xFF2D6470),
      elevation: 8,
      height: 80,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
            fontFamily: 'PublicSans',
            fontSize: 11,
            height: 1.2,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? Colors.white
                : const Color(0xFFB8CBD0),
          )),
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
            size: 23,
            color: states.contains(WidgetState.selected)
                ? const Color(0xFF8FE0D3)
                : const Color(0xFFB8CBD0),
          )),
    ),
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: AppColors.primary,
      indicatorColor: Color(0xFF2D6470),
      selectedIconTheme: IconThemeData(color: Color(0xFF8FE0D3)),
      unselectedIconTheme: IconThemeData(color: Color(0xFFB8CBD0)),
      selectedLabelTextStyle: TextStyle(
          fontFamily: 'PublicSans',
          color: Colors.white,
          fontWeight: FontWeight.w700),
      unselectedLabelTextStyle:
          TextStyle(fontFamily: 'PublicSans', color: Color(0xFFB8CBD0)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titleTextStyle: typography.titleLarge
          ?.copyWith(fontFamily: 'PublicSans', color: AppColors.ink),
      contentTextStyle: typography.bodyMedium
          ?.copyWith(fontFamily: 'PublicSans', color: AppColors.muted),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      textStyle: typography.bodyMedium?.copyWith(color: AppColors.ink),
    ),
    expansionTileTheme: const ExpansionTileThemeData(
      iconColor: AppColors.teal,
      collapsedIconColor: AppColors.muted,
      textColor: AppColors.ink,
      collapsedTextColor: AppColors.ink,
      tilePadding: EdgeInsets.symmetric(horizontal: 16),
      childrenPadding: EdgeInsets.fromLTRB(16, 0, 16, 16),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.ink,
      contentTextStyle:
          const TextStyle(fontFamily: 'PublicSans', color: Colors.white),
      actionTextColor: const Color(0xFFA8DED2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: AppColors.muted,
      textColor: AppColors.ink,
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      minVerticalPadding: 12,
      horizontalTitleGap: 14,
      subtitleTextStyle: TextStyle(
          fontFamily: 'PublicSans',
          color: AppColors.muted,
          fontSize: 13,
          height: 1.45),
    ),
    progressIndicatorTheme:
        const ProgressIndicatorThemeData(color: AppColors.teal),
    dataTableTheme: const DataTableThemeData(
      headingRowColor: WidgetStatePropertyAll(Color(0xFFEDF2F3)),
      headingRowHeight: 52,
      dataRowMinHeight: 52,
      dataRowMaxHeight: 88,
      columnSpacing: 28,
      horizontalMargin: 20,
      headingTextStyle: TextStyle(
          fontFamily: 'PublicSans',
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
          fontSize: 12),
      dataTextStyle: TextStyle(
          fontFamily: 'PublicSans', color: AppColors.ink, fontSize: 13),
      dividerThickness: 1,
    ),
    tooltipTheme: TooltipThemeData(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
          color: AppColors.ink, borderRadius: BorderRadius.circular(8)),
      textStyle: const TextStyle(
          fontFamily: 'PublicSans', color: Colors.white, fontSize: 12),
    ),
  );
}

ThemeData buildDarkAppTheme() {
  const scheme = ColorScheme.dark(
    primary: Color(0xFF8FE0D3),
    onPrimary: Color(0xFF063A34),
    primaryContainer: Color(0xFF244E59),
    onPrimaryContainer: Color(0xFFC9F2EA),
    secondary: Color(0xFF71D6C7),
    onSecondary: Color(0xFF063A34),
    secondaryContainer: Color(0xFF174F49),
    onSecondaryContainer: Color(0xFFC8F1EA),
    tertiary: Color(0xFFFFBC69),
    onTertiary: Color(0xFF472A00),
    tertiaryContainer: Color(0xFF664000),
    onTertiaryContainer: Color(0xFFFFDDB4),
    surface: Color(0xFF14232B),
    onSurface: Color(0xFFE7EEF0),
    surfaceContainerLowest: Color(0xFF091419),
    surfaceContainerLow: Color(0xFF101D23),
    surfaceContainer: Color(0xFF14232B),
    surfaceContainerHigh: Color(0xFF1B2C34),
    surfaceContainerHighest: Color(0xFF22343D),
    onSurfaceVariant: Color(0xFFB7C6CB),
    outline: Color(0xFF81949B),
    outlineVariant: Color(0xFF344852),
    error: Color(0xFFFFB4AB),
    onError: Color(0xFF690005),
  );
  final base = buildAppTheme();
  final darkText = base.textTheme
      .apply(
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
      )
      .copyWith(
        bodySmall:
            base.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
      );
  final input = OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: const BorderSide(color: Color(0xFF536872)),
  );
  return base.copyWith(
    brightness: Brightness.dark,
    colorScheme: scheme,
    textTheme: darkText,
    scaffoldBackgroundColor: const Color(0xFF0E1A20),
    iconTheme: const IconThemeData(size: 22, color: Color(0xFFB7C6CB)),
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: const Color(0xFF092D37),
      foregroundColor: scheme.onSurface,
      iconTheme: const IconThemeData(color: Colors.white),
      actionsIconTheme: const IconThemeData(color: Colors.white),
      systemOverlayStyle: const SystemUiOverlayStyle(
        statusBarColor: Color(0xFF092D37),
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      titleTextStyle:
          base.appBarTheme.titleTextStyle?.copyWith(color: Colors.white),
    ),
    cardTheme: base.cardTheme.copyWith(
      color: const Color(0xFF14232B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFF344852)),
      ),
    ),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      fillColor: const Color(0xFF14232B),
      border: input,
      enabledBorder: input,
      focusedBorder: input.copyWith(
        borderSide: const BorderSide(color: Color(0xFF8FE0D3), width: 2),
      ),
      labelStyle: const TextStyle(
          color: Color(0xFFB7C6CB), fontSize: 14, fontWeight: FontWeight.w500),
      floatingLabelStyle: const TextStyle(
          color: Color(0xFF8FE0D3), fontWeight: FontWeight.w700),
      hintStyle: const TextStyle(color: Color(0xFF81949B), fontSize: 14),
      helperStyle: const TextStyle(color: Color(0xFFB7C6CB), height: 1.4),
      prefixIconColor: const Color(0xFFB7C6CB),
      suffixIconColor: const Color(0xFFB7C6CB),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF8FE0D3),
        foregroundColor: const Color(0xFF063A34),
        elevation: 0,
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFF1CA392),
        foregroundColor: Colors.white,
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF8FE0D3),
        backgroundColor: const Color(0xFF14232B),
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: const BorderSide(color: Color(0xFF536872)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFF8FE0D3),
        minimumSize: const Size(48, 48),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: const Color(0xFF8FE0D3),
        minimumSize: const Size(48, 48),
      ),
    ),
    floatingActionButtonTheme: base.floatingActionButtonTheme.copyWith(
      backgroundColor: const Color(0xFF1CA392),
      foregroundColor: Colors.white,
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: const Color(0xFF14232B),
      selectedColor: const Color(0xFF174F49),
      disabledColor: const Color(0xFF1B2C34),
      side: const BorderSide(color: Color(0xFF344852)),
      labelStyle: const TextStyle(
          fontFamily: 'PublicSans',
          fontSize: 12,
          color: Color(0xFFE7EEF0),
          fontWeight: FontWeight.w600),
      secondaryLabelStyle: const TextStyle(
          fontFamily: 'PublicSans',
          color: Color(0xFF8FE0D3),
          fontWeight: FontWeight.w700),
      checkmarkColor: const Color(0xFF8FE0D3),
      iconTheme: const IconThemeData(size: 18, color: Color(0xFF8FE0D3)),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? const Color(0xFF8FE0D3)
                : const Color(0xFFB7C6CB)),
        backgroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? const Color(0xFF174F49)
                : const Color(0xFF14232B)),
        side:
            const WidgetStatePropertyAll(BorderSide(color: Color(0xFF344852))),
        shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? const Color(0xFF063A34)
              : const Color(0xFFB7C6CB)),
      trackColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? const Color(0xFF8FE0D3)
              : const Color(0xFF344852)),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? const Color(0xFF1CA392)
              : Colors.transparent),
      checkColor: const WidgetStatePropertyAll(Colors.white),
      side: const BorderSide(color: Color(0xFFB7C6CB), width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? const Color(0xFF8FE0D3)
              : const Color(0xFFB7C6CB)),
    ),
    navigationBarTheme: base.navigationBarTheme.copyWith(
      backgroundColor: const Color(0xFF14232B),
      indicatorColor: const Color(0xFF294A49),
    ),
    navigationRailTheme: base.navigationRailTheme.copyWith(
      backgroundColor: const Color(0xFF14232B),
      indicatorColor: const Color(0xFF294A49),
    ),
    dividerTheme: const DividerThemeData(color: Color(0xFF344852)),
    tabBarTheme: base.tabBarTheme.copyWith(
      labelColor: const Color(0xFF8FE0D3),
      unselectedLabelColor: const Color(0xFFB7C6CB),
      indicatorColor: const Color(0xFF8FE0D3),
      dividerColor: const Color(0xFF344852),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Color(0xFF14232B),
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
    ),
    dialogTheme: base.dialogTheme.copyWith(
      backgroundColor: const Color(0xFF14232B),
      surfaceTintColor: Colors.transparent,
      titleTextStyle: darkText.titleLarge,
      contentTextStyle:
          darkText.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: const Color(0xFF1B2C34),
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      textStyle: darkText.bodyMedium,
    ),
    expansionTileTheme: const ExpansionTileThemeData(
      iconColor: Color(0xFF8FE0D3),
      collapsedIconColor: Color(0xFFB7C6CB),
      textColor: Color(0xFFE7EEF0),
      collapsedTextColor: Color(0xFFE7EEF0),
      tilePadding: EdgeInsets.symmetric(horizontal: 16),
      childrenPadding: EdgeInsets.fromLTRB(16, 0, 16, 16),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: Color(0xFFB7C6CB),
      textColor: Color(0xFFE7EEF0),
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      minVerticalPadding: 12,
      horizontalTitleGap: 14,
      subtitleTextStyle: TextStyle(
          fontFamily: 'PublicSans',
          color: Color(0xFFB7C6CB),
          fontSize: 13,
          height: 1.45),
    ),
    dataTableTheme: const DataTableThemeData(
      headingRowColor: WidgetStatePropertyAll(Color(0xFF1B2C34)),
      headingRowHeight: 52,
      dataRowMinHeight: 52,
      dataRowMaxHeight: 88,
      columnSpacing: 28,
      horizontalMargin: 20,
      headingTextStyle: TextStyle(
          fontFamily: 'PublicSans',
          fontWeight: FontWeight.w700,
          color: Color(0xFFE7EEF0),
          fontSize: 12),
      dataTextStyle: TextStyle(
          fontFamily: 'PublicSans', color: Color(0xFFE7EEF0), fontSize: 13),
      dividerThickness: 1,
    ),
  );
}

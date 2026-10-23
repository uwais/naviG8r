import "package:flutter/material.dart";

import "ui/tokens.dart";

/// The NaviG8r design system theme, light only. MaterialApp must set
/// themeMode: ThemeMode.light and pass no darkTheme, so the phone's dark setting never
/// switches the app.
abstract final class DriverTheme {
  // Older names that screens still import, pointed at the design tokens.
  static const Color navy = NvColors.navy;
  static const Color background = NvColors.page;
  static const Color border = NvColors.line;
  static const Color muted = NvColors.slate;

  /// Secondary text on the page background. Slate is 5.0:1 on page and 5.4:1 on white
  /// cards, so one colour now passes WCAG AA on both.
  static const Color mutedOnBackground = NvColors.slate;

  static ThemeData theme() {
    final scheme = ColorScheme.fromSeed(
      seedColor: NvColors.navy,
      brightness: Brightness.light,
    ).copyWith(
      primary: NvColors.navy,
      onPrimary: NvColors.onNavy,
      surface: NvColors.page,
      onSurface: NvColors.ink,
      error: NvColors.problem,
      outline: NvColors.controlBorder,
      outlineVariant: NvColors.line,
    );
    final buttonShape = RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NvRadius.button));
    const minimumTapSize = Size(NvSpace.targetMin, NvSpace.targetMin);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: NvColors.page,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      textTheme: const TextTheme(
        displaySmall: NvText.display,
        headlineMedium: NvText.title,
        titleMedium: NvText.heading,
        bodyLarge: NvText.body,
        bodyMedium: NvText.body,
        bodySmall: NvText.caption,
        labelLarge: NvText.bodyStrong,
        labelSmall: NvText.label,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: NvColors.page,
        foregroundColor: NvColors.navyInk,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        shape: Border(bottom: BorderSide(color: NvColors.line)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: NvColors.navy,
          foregroundColor: NvColors.onNavy,
          disabledBackgroundColor: NvColors.sunken,
          disabledForegroundColor: NvColors.slate,
          minimumSize: minimumTapSize,
          padding: const EdgeInsets.symmetric(horizontal: NvSpace.s5),
          textStyle: NvText.bodyStrong,
          shape: buttonShape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: NvColors.card,
          foregroundColor: NvColors.navy,
          disabledForegroundColor: NvColors.slate,
          minimumSize: minimumTapSize,
          padding: const EdgeInsets.symmetric(horizontal: NvSpace.s5),
          side: const BorderSide(color: NvColors.controlBorder),
          textStyle: NvText.bodyStrong,
          shape: buttonShape,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: NvColors.navy,
          minimumSize: minimumTapSize,
          textStyle: NvText.bodyStrong,
          shape: buttonShape,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: NvColors.card,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        helperStyle: NvText.caption,
        errorStyle: NvText.caption
            .copyWith(color: NvColors.problem, fontWeight: FontWeight.w600),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(NvRadius.input)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(NvRadius.input),
          borderSide: const BorderSide(color: NvColors.controlBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(NvRadius.input),
          borderSide: const BorderSide(color: NvColors.focus, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(NvRadius.input),
          borderSide: const BorderSide(color: NvColors.problem, width: 2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(NvRadius.input),
          borderSide: const BorderSide(color: NvColors.problem, width: 2),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(NvRadius.input),
          borderSide: BorderSide.none,
        ),
      ),
      // The spec's zero card margin and sheet drag handle wait for the screen rewrites;
      // here they would shift spacing on screens this change must not touch.
      cardTheme: const CardTheme(
        color: NvColors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(NvRadius.card)),
          side: BorderSide(color: NvColors.line),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: NvColors.card,
        selectedColor: NvColors.navy,
        side: const BorderSide(color: NvColors.controlBorder),
        labelStyle: NvText.bodyStrong.copyWith(color: NvColors.navy),
        secondaryLabelStyle:
            NvText.bodyStrong.copyWith(color: NvColors.onNavy),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(NvRadius.pill)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: NvColors.card,
        modalBarrierColor: NvColors.scrim,
        shape: RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(NvRadius.card)),
        ),
      ),
      dividerTheme:
          const DividerThemeData(color: NvColors.line, thickness: 1, space: 1),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: NvColors.card,
        indicatorColor: NvColors.navIndicator,
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith((states) =>
            NvText.navLabel.copyWith(
                color: states.contains(WidgetState.selected)
                    ? NvColors.navy
                    : NvColors.slate)),
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? NvColors.navy
                : NvColors.slate)),
      ),
    );
  }
}

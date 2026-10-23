// REFERENCE IMPLEMENTATION, not wired in. Claude Code: adapt this into
// apps/driver_pilot/lib/driver_theme.dart (or a new navig8r_theme.dart) in PR 1.
// Every value comes from spec/design-tokens.json (NaviG8r design system).
// Fonts: bundle Poppins (600, 700) and Manrope (400, 500, 600, 700) as assets,
// declared in pubspec.yaml under the family names "Poppins" and "Manrope".
// Do not fetch fonts at runtime: drivers often have weak signal.

import "package:flutter/material.dart";

abstract final class NvColors {
  static const navy = Color(0xFF16233D);
  static const navyInk = Color(0xFF131F35);
  static const navyDeep = Color(0xFF0D1524);
  static const gold = Color(0xFFE8A33D); // only on navy
  static const slate = Color(0xFF5B6B87);
  static const page = Color(0xFFF8F7F2);
  static const card = Color(0xFFFFFFFF);
  static const sunken = Color(0xFFF0EEE6);
  static const line = Color(0xFFE4DFD3); // decorative only, < 3:1
  static const controlBorder = Color(0xFF8A8175); // 3.6:1 on page
  static const ink = Color(0xFF2B2620);
  static const onNavy = card;
  static const focus = navy;
  static const navIndicator = Color(0x1F16233D); // navy 12%
  static const good = Color(0xFF1B6A35);
  static const goodTint = Color(0xFFDEF0E2);
  static const attention = Color(0xFF845400);
  static const attentionTint = Color(0xFFFCF0D4);
  static const problem = Color(0xFF9B2C1F);
  static const problemTint = Color(0xFFF7E1DC);
  static const infoTint = Color(0xFFE6E9EF);
  static const scrim = Color(0x73131F35); // proposed addition
}

abstract final class NvSpace {
  static const s1 = 4.0, s2 = 8.0, s3 = 12.0, s4 = 16.0, s5 = 20.0, s6 = 24.0, s8 = 32.0, s12 = 48.0;
  static const gutter = s4;
  static const targetMin = 48.0; // proposed addition
  static const targetDriver = 56.0; // proposed addition
}

abstract final class NvRadius {
  static const sm = 8.0, button = 12.0, input = 14.0, card = 16.0, pill = 20.0;
}

abstract final class NvText {
  static const _display = "Poppins";
  static const _body = "Manrope";
  static const _tnum = [FontFeature.tabularFigures()];

  static const display = TextStyle(fontFamily: _display, fontSize: 32, height: 38 / 32, fontWeight: FontWeight.w700, color: NvColors.navyInk);
  static const title = TextStyle(fontFamily: _display, fontSize: 26, height: 32 / 26, fontWeight: FontWeight.w700, color: NvColors.navyInk);
  static const heading = TextStyle(fontFamily: _display, fontSize: 18, height: 24 / 18, fontWeight: FontWeight.w600, color: NvColors.navyInk);
  static const body = TextStyle(fontFamily: _body, fontSize: 15, height: 22 / 15, fontWeight: FontWeight.w400, color: NvColors.ink, fontFeatures: _tnum);
  static const bodyStrong = TextStyle(fontFamily: _body, fontSize: 15, height: 22 / 15, fontWeight: FontWeight.w600, color: NvColors.ink, fontFeatures: _tnum);
  static const caption = TextStyle(fontFamily: _body, fontSize: 13, height: 18 / 13, fontWeight: FontWeight.w400, color: NvColors.slate, fontFeatures: _tnum);
  static const label = TextStyle(fontFamily: _body, fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w600, letterSpacing: 0.96, color: NvColors.slate);
  static const navLabel = TextStyle(fontFamily: _body, fontSize: 11, height: 14 / 11, fontWeight: FontWeight.w600);
  static const id = TextStyle(fontFamily: "monospace", fontSize: 15, height: 22 / 15, fontWeight: FontWeight.w500, letterSpacing: 0.3, color: NvColors.navyInk);
  static const idDisplay = TextStyle(fontFamily: "monospace", fontSize: 30, height: 38 / 30, fontWeight: FontWeight.w600, letterSpacing: 1.2, color: NvColors.navyInk); // proposed addition
}

abstract final class NvTheme {
  /// Light only. Do not pass a darkTheme to MaterialApp and set themeMode: ThemeMode.light,
  /// so the phone's dark setting never switches the app.
  static ThemeData light() {
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
    final buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(NvRadius.button));
    const minSize = Size(NvSpace.targetMin, NvSpace.targetMin);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: NvColors.page,
      fontFamily: "Manrope",
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
          minimumSize: minSize,
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
          minimumSize: minSize,
          padding: const EdgeInsets.symmetric(horizontal: NvSpace.s5),
          side: const BorderSide(color: NvColors.controlBorder),
          textStyle: NvText.bodyStrong,
          shape: buttonShape,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: NvColors.navy,
          minimumSize: minSize,
          textStyle: NvText.bodyStrong,
          shape: buttonShape,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: NvColors.card,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        helperStyle: NvText.caption,
        errorStyle: NvText.caption.copyWith(color: NvColors.problem, fontWeight: FontWeight.w600),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(NvRadius.input)),
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
      cardTheme: const CardTheme(
        color: NvColors.card,
        elevation: 0,
        margin: EdgeInsets.zero,
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
        secondaryLabelStyle: NvText.bodyStrong.copyWith(color: NvColors.onNavy),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(NvRadius.pill)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: NvColors.card,
        modalBarrierColor: NvColors.scrim,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(NvRadius.card)),
        ),
      ),
      dividerTheme: const DividerThemeData(color: NvColors.line, thickness: 1, space: 1),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: NvColors.card,
        indicatorColor: NvColors.navIndicator,
        elevation: 0,
        labelTextStyle: MaterialStateProperty.resolveWith((states) =>
            NvText.navLabel.copyWith(
                color: states.contains(MaterialState.selected) ? NvColors.navy : NvColors.slate)),
        iconTheme: MaterialStateProperty.resolveWith((states) => IconThemeData(
            color: states.contains(MaterialState.selected) ? NvColors.navy : NvColors.slate)),
      ),
    );
  }
}

/// Status label kinds. The word always carries the meaning; colour only supports it.
enum NvStatusKind { attention, info, good, problem, ended }

extension NvStatusColors on NvStatusKind {
  Color get fg => switch (this) {
        NvStatusKind.attention => NvColors.attention,
        NvStatusKind.info => NvColors.navy,
        NvStatusKind.good => NvColors.good,
        NvStatusKind.problem => NvColors.problem,
        NvStatusKind.ended => NvColors.ink,
      };
  Color get bg => switch (this) {
        NvStatusKind.attention => NvColors.attentionTint,
        NvStatusKind.info => NvColors.infoTint,
        NvStatusKind.good => NvColors.goodTint,
        NvStatusKind.problem => NvColors.problemTint,
        NvStatusKind.ended => NvColors.sunken,
      };
}

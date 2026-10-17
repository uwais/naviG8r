import "package:flutter/material.dart";

/// Values from docs/design-mobile-app/handoff/spec/design-tokens.json.
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
  static const scrim = Color(0x73131F35);
}

abstract final class NvSpace {
  static const s1 = 4.0,
      s2 = 8.0,
      s3 = 12.0,
      s4 = 16.0,
      s5 = 20.0,
      s6 = 24.0,
      s8 = 32.0,
      s12 = 48.0;
  static const gutter = s4;
  static const targetMin = 48.0;
  static const targetDriver = 56.0;
}

abstract final class NvRadius {
  static const sm = 8.0, button = 12.0, input = 14.0, card = 16.0, pill = 20.0;
}

/// The spec names Poppins and Manrope, but they are not bundled, so every style uses the
/// platform default family. Sizes and weights are the spec's.
abstract final class NvText {
  static const _tabularFigures = [FontFeature.tabularFigures()];

  static const display = TextStyle(
      fontSize: 32,
      height: 38 / 32,
      fontWeight: FontWeight.w700,
      color: NvColors.navyInk);
  static const title = TextStyle(
      fontSize: 26,
      height: 32 / 26,
      fontWeight: FontWeight.w700,
      color: NvColors.navyInk);
  static const heading = TextStyle(
      fontSize: 18,
      height: 24 / 18,
      fontWeight: FontWeight.w600,
      color: NvColors.navyInk);
  static const body = TextStyle(
      fontSize: 15,
      height: 22 / 15,
      fontWeight: FontWeight.w400,
      color: NvColors.ink,
      fontFeatures: _tabularFigures);
  static const bodyStrong = TextStyle(
      fontSize: 15,
      height: 22 / 15,
      fontWeight: FontWeight.w600,
      color: NvColors.ink,
      fontFeatures: _tabularFigures);
  static const caption = TextStyle(
      fontSize: 13,
      height: 18 / 13,
      fontWeight: FontWeight.w400,
      color: NvColors.slate,
      fontFeatures: _tabularFigures);
  static const label = TextStyle(
      fontSize: 12,
      height: 16 / 12,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.96,
      color: NvColors.slate);
  static const navLabel =
      TextStyle(fontSize: 11, height: 14 / 11, fontWeight: FontWeight.w600);
  // "monospace" is the platform's generic mono family, already used for IDs elsewhere in the app.
  static const id = TextStyle(
      fontFamily: "monospace",
      fontSize: 15,
      height: 22 / 15,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.3,
      color: NvColors.navyInk);
  static const idDisplay = TextStyle(
      fontFamily: "monospace",
      fontSize: 30,
      height: 38 / 30,
      fontWeight: FontWeight.w600,
      letterSpacing: 1.2,
      color: NvColors.navyInk);
}

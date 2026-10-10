import 'package:flutter/material.dart';

/// The two looks: Dark Side (default: near-black, neon red) and Light Side
/// (paper white, blue), plus following the phone.
enum AppSide { dark, light, system }

extension AppSideMode on AppSide {
  ThemeMode get themeMode => switch (this) {
        AppSide.dark => ThemeMode.dark,
        AppSide.light => ThemeMode.light,
        AppSide.system => ThemeMode.system,
      };

  String get label => switch (this) {
        AppSide.dark => 'Dark Side',
        AppSide.light => 'Light Side',
        AppSide.system => 'Auto',
      };
}

/// Colors Material's scheme has no slot for: the neon glow and the tinted
/// alert chips, tuned per side so they read on both.
@immutable
class SiftColors extends ThemeExtension<SiftColors> {
  const SiftColors({
    required this.glow,
    required this.hairline,
    required this.panel,
    required this.warnBg,
    required this.warnFg,
    required this.saleBg,
    required this.saleFg,
    required this.neutralBg,
    required this.neutralFg,
  });

  /// The accent's glow: text shadows, focused-field halo, backdrop wash.
  final Color glow;

  /// 1px borders on panels and cards.
  final Color hairline;

  /// Raised panels (usual-price bar, queue rows).
  final Color panel;
  final Color warnBg;
  final Color warnFg;
  final Color saleBg;
  final Color saleFg;
  final Color neutralBg;
  final Color neutralFg;

  static SiftColors of(BuildContext context) => Theme.of(context).extension<SiftColors>()!;

  @override
  SiftColors copyWith() => this;

  @override
  SiftColors lerp(SiftColors? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return SiftColors(
      glow: l(glow, other.glow),
      hairline: l(hairline, other.hairline),
      panel: l(panel, other.panel),
      warnBg: l(warnBg, other.warnBg),
      warnFg: l(warnFg, other.warnFg),
      saleBg: l(saleBg, other.saleBg),
      saleFg: l(saleFg, other.saleFg),
      neutralBg: l(neutralBg, other.neutralBg),
      neutralFg: l(neutralFg, other.neutralFg),
    );
  }
}

const _sithRed = Color(0xFFFF2E3E);
const _jediBlue = Color(0xFF1F6BFF);

ThemeData darkSide() {
  const bg = Color(0xFF07070A);
  final scheme = ColorScheme.fromSeed(seedColor: _sithRed, brightness: Brightness.dark).copyWith(
    primary: _sithRed,
    onPrimary: Colors.white,
    secondary: const Color(0xFFFF6B75),
    surface: bg,
    onSurface: const Color(0xFFEDEDF2),
    onSurfaceVariant: const Color(0xFF9A9AA8),
    surfaceContainerLowest: const Color(0xFF050507),
    surfaceContainerLow: const Color(0xFF0E0E13),
    surfaceContainer: const Color(0xFF131319),
    surfaceContainerHigh: const Color(0xFF1A1A22),
    surfaceContainerHighest: const Color(0xFF22222C),
    outline: const Color(0xFF34343F),
    outlineVariant: const Color(0xFF24242D),
    error: const Color(0xFFFF6B6B),
  );
  return _build(
    scheme,
    const SiftColors(
      glow: Color(0xCCFF2E3E),
      hairline: Color(0x33FF2E3E),
      panel: Color(0xFF111117),
      warnBg: Color(0xFF33270A),
      warnFg: Color(0xFFFFD166),
      saleBg: Color(0xFF0D2E1C),
      saleFg: Color(0xFF6EE7A8),
      neutralBg: Color(0xFF22222B),
      neutralFg: Color(0xFFC9C9D4),
    ),
  );
}

ThemeData lightSide() {
  final scheme = ColorScheme.fromSeed(seedColor: _jediBlue, brightness: Brightness.light).copyWith(
    primary: _jediBlue,
    onPrimary: Colors.white,
    surface: const Color(0xFFF6F7FB),
    surfaceContainerLow: const Color(0xFFFFFFFF),
    surfaceContainer: const Color(0xFFFFFFFF),
    surfaceContainerHigh: const Color(0xFFEEF0F6),
    surfaceContainerHighest: const Color(0xFFE4E7F0),
  );
  return _build(
    scheme,
    const SiftColors(
      glow: Color(0x661F6BFF),
      hairline: Color(0x221F6BFF),
      panel: Color(0xFFFFFFFF),
      warnBg: Color(0xFFFFF3BF),
      warnFg: Color(0xFF6B4E00),
      saleBg: Color(0xFFD3F9D8),
      saleFg: Color(0xFF1B5E20),
      neutralBg: Color(0xFFE9ECEF),
      neutralFg: Color(0xFF343A40),
    ),
  );
}

ThemeData _build(ColorScheme scheme, SiftColors sift) {
  final base = ThemeData(colorScheme: scheme, useMaterial3: true);
  final rounded = RoundedRectangleBorder(borderRadius: BorderRadius.circular(18));
  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    extensions: [sift],
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      foregroundColor: scheme.onSurface,
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: rounded.copyWith(side: BorderSide(color: sift.hairline)),
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: scheme.surfaceContainerHigh,
      selectedColor: scheme.primary.withValues(alpha: 0.18),
      side: BorderSide(color: scheme.outlineVariant),
      shape: const StadiumBorder(),
      labelStyle: base.textTheme.labelLarge?.copyWith(color: scheme.onSurface),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1, thickness: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHigh,
      hintStyle: TextStyle(color: scheme.onSurfaceVariant),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.surfaceContainerHighest,
      contentTextStyle: TextStyle(color: scheme.onSurface),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 4)),
        textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        side: WidgetStatePropertyAll(BorderSide(color: scheme.outline)),
        backgroundColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? scheme.primary.withValues(alpha: 0.22) : Colors.transparent),
        foregroundColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? scheme.primary : scheme.onSurface),
      ),
    ),
  );
}

/// The display face for the brand and section labels. Orbitron has no ₱
/// glyph, so never use it for prices.
TextStyle brandText(BuildContext context, {double size = 20, double weight = 700, bool glow = true}) {
  final sift = SiftColors.of(context);
  return TextStyle(
    fontFamily: 'Orbitron',
    fontSize: size,
    fontVariations: [FontVariation('wght', weight)],
    letterSpacing: size * 0.08,
    color: Theme.of(context).colorScheme.onSurface,
    shadows: glow
        ? [
            Shadow(color: sift.glow, blurRadius: size * 0.6),
            Shadow(color: sift.glow.withValues(alpha: 0.4), blurRadius: size * 1.4),
          ]
        : null,
  );
}

/// Small caps-style section label ("STORES", "USUAL PRICE").
TextStyle sectionLabel(BuildContext context) => brandText(context, size: 11, weight: 600, glow: false)
    .copyWith(color: Theme.of(context).colorScheme.primary, letterSpacing: 2);

/// The faint accent wash behind the home screen, like light off a blade.
BoxDecoration backdropGlow(BuildContext context) {
  final sift = SiftColors.of(context);
  return BoxDecoration(
    gradient: RadialGradient(
      center: const Alignment(0, -1.15),
      radius: 1.25,
      colors: [sift.glow.withValues(alpha: 0.22), sift.glow.withValues(alpha: 0)],
      stops: const [0, 1],
    ),
  );
}

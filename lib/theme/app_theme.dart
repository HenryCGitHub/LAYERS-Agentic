import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // ── Dark Palette (40 · 30 · 20 · 10 Ratio · Palette A: Obsidian & Emerald) ─
  static const Color bgBase =
      Color(0xFF090C10); // 40% Dominant Base App Background (#090C10)
  static const Color bgPanel =
      Color(0xFF0D1117); // 40% Left Feature Rail & Center Steps Pane (#0D1117)
  static const Color bgSurface =
      Color(0xFF161B22); // 30% Elevated Inspector Cards & Active Rows (#161B22)
  static const Color bgSurfaceHover =
      Color(0xFF1C2128); // Hover / secondary surface (#1C2128)
  static const Color bgSurfaceActive =
      Color(0xFF21262D); // 20% Active/selected row & pill surface (#21262D)

  static const Color borderSubtle =
      Color(0xFF262C36); // Crisp 1px card & hairline divider (#262C36)
  static const Color borderBright =
      Color(0xFF30363D); // Focused / active pill & badge border (#30363D)

  static const Color textPrimary =
      Color(0xFFF0F6FC); // T1 Crisp white primary lead text (#F0F6FC)
  static const Color textSecondary =
      Color(0xFF9CA3AF); // T2 Boosted secondary contrast (#9CA3AF)
  static const Color textMuted =
      Color(0xFF8B949E); // T3 Boosted muted label / metadata contrast (#8B949E)

  // ── Light Palette (Crisp Cool Slate Paper · Deep Slate Ink & Accent) ───────
  static const Color bgBaseLight =
      Color(0xFFF8FAFC); // Main canvas backdrop (Cool Slate paper)
  static const Color bgPanelLight =
      Color(0xFFF1F5F9); // Sidebar / TitleBar / Dialogs
  static const Color bgSurfaceLight =
      Color(0xFFFFFFFF); // Document cards
  static const Color bgSurfaceHoverLight =
      Color(0xFFE2E8F0); // Hover state background

  static const Color borderSubtleLight =
      Color(0xFFCBD5E1); // Crisp 1px cool slate structural lines
  static const Color borderBrightLight =
      Color(0xFF64748B); // Focused / active borders

  static const Color textPrimaryLight =
      Color(0xFF0F172A); // Deep Slate ink primary headings
  static const Color textSecondaryLight =
      Color(0xFF475569); // Cool slate secondary text
  static const Color textMutedLight =
      Color(0xFF64748B); // Muted slate metadata text

  // ── Semantic Surface Scale (40 · 30 · 20 · 10 Depth Ladder) ───────────────
  static const Color bgSurfaceRaised =
      Color(0xFF161B22); // Elevated cards, chiclets, floating toolbars (Dark)
  static const Color bgSurfaceRecessed =
      Color(0xFF0D1117); // 20% Recessed Outliner Rail, Steps Pane & Code Well (#0D1117)
  static const Color bgSurfaceRaisedLight =
      Color(0xFFFFFFFF); // Elevated cards on light
  static const Color bgSurfaceRecessedLight =
      Color(0xFFF1F5F9); // Recessed insets on light
  static const Color bgSurfaceActiveLight =
      Color(0xFFE2E8F0); // Active/selected list item on light

  static const Color bgInset = Color(0xFF0D1117); // 20% Deep recessed code well (Dark)
  static const Color bgInsetLight = Color(0xFFF1F5F9); // Recessed insets / inner cards (Light)

  // ── Reversible Polarity Focal Accent (Crisp White in Dark ↔ Deep Slate in Light) ─
  static const Color focalAccentDark = Color(0xFFF9FAFB);
  static const Color focalAccentFgDark = Color(0xFF090A0F);
  static const Color focalAccentLight = Color(0xFF0F172A);
  static const Color focalAccentFgLight = Color(0xFFF8FAFC);

  static Color focalAccentFor(bool isDark) =>
      isDark ? focalAccentDark : focalAccentLight;
  static Color focalAccentFgFor(bool isDark) =>
      isDark ? focalAccentFgDark : focalAccentFgLight;

  // ── Dynamic Theme Helpers ─────────────────────────────────────────────────
  static Color bgBaseFor(bool isDark) => isDark ? bgBase : bgBaseLight;
  static Color bgCanvasFor(bool isDark) => bgBaseFor(isDark);
  static Color bgPanelFor(bool isDark) => isDark ? bgPanel : bgPanelLight;
  static Color bgSurfaceFor(bool isDark) => isDark ? bgSurface : bgSurfaceLight;
  static Color bgInsetFor(bool isDark) => isDark ? bgInset : bgInsetLight;
  static Color bgSurfaceRaisedFor(bool isDark) =>
      isDark ? bgSurfaceRaised : bgSurfaceRaisedLight;
  static Color bgSurfaceRecessedFor(bool isDark) =>
      isDark ? bgSurfaceRecessed : bgSurfaceRecessedLight;
  static Color bgSurfaceActiveFor(bool isDark) =>
      isDark ? bgSurfaceActive : bgSurfaceActiveLight;
  static Color bgSurfaceHoverFor(bool isDark) =>
      isDark ? bgSurfaceHover : bgSurfaceHoverLight;

  static Color borderSubtleFor(bool isDark) =>
      isDark ? borderSubtle : borderSubtleLight;
  static Color borderFor(bool isDark) => borderSubtleFor(isDark);
  static Color borderBrightFor(bool isDark) =>
      isDark ? borderBright : borderBrightLight;

  static Color textPrimaryFor(bool isDark) =>
      isDark ? textPrimary : textPrimaryLight;
  static Color textSecondaryFor(bool isDark) =>
      isDark ? textSecondary : textSecondaryLight;
  static Color textMutedFor(bool isDark) => isDark ? textMuted : textMutedLight;

  // ── Standard Radius Scale ─────────────────────────────────────────────────
  static const double radiusXs = 4.0;   // Chips, small tags, micro badges
  static const double radiusSm = 6.0;   // Buttons, inputs, small cards
  static const double radiusMd = 8.0;   // Cards, menus, dropdowns
  static const double radiusLg = 12.0;  // Modals, workstation containers, toast
  static const double radiusPill = 999.0; // Status badges, pill counters

  // ── Purposeful Semantic Accents (Monochrome Precision: Emerald & Amber Only) ─
  static const Color accentAmber = Color(0xFFFBBF24); // Guard / AI Warning Amber (Dark)
  static const Color accentAmberLight = Color(0xFFB45309); // Muted Ochre (Light)
  static Color accentAmberFor(bool isDark) => isDark ? accentAmber : accentAmberLight;

  static const Color accentBlue = Color(0xFFE2E8F0); // Monochrome Silver (Dark)
  static const Color accentBlueLight = Color(0xFF334155); // Deep Slate (Light)
  static Color accentBlueFor(bool isDark) => isDark ? accentBlue : accentBlueLight;

  static const Color accentPurple = Color(0xFFE2E8F0); // Monochrome Silver (Dark)
  static const Color accentPurpleLight = Color(0xFF334155); // Deep Slate (Light)
  static Color accentPurpleFor(bool isDark) => isDark ? accentPurple : accentPurpleLight;

  static const Color accentOrange = Color(0xFFFBBF24); // Unified Amber (Dark)
  static const Color accentOrangeLight = Color(0xFFB45309); // Muted Ochre (Light)
  static Color accentOrangeFor(bool isDark) => isDark ? accentOrange : accentOrangeLight;

  static const Color accentGreen = Color(0xFF10B981); // Crisp Emerald (--emerald: #10B981)
  static const Color accentGreenLight = Color(0xFF059669); // Emerald (Light)
  static Color accentGreenFor(bool isDark) => isDark ? accentGreen : accentGreenLight;

  static const Color accentRed = Color(0xFFF87171); // Destructive / Cut Coral (Dark)
  static const Color accentRedLight = Color(0xFFC25450); // Brick Coral (Light)
  static Color accentRedFor(bool isDark) => isDark ? accentRed : accentRedLight;

  static const Color accentCyan = Color(0xFF60A5FA); // 20% Secondary Technical Spec Ice-Blue (Dark: #60A5FA)
  static const Color accentCyanLight = Color(0xFF2563EB); // Technical Spec Blue (Light)
  static Color accentCyanFor(bool isDark) => isDark ? accentCyan : accentCyanLight;

  static const List<String> fontFallbacks = [
    'Roboto',
    '-apple-system',
    'BlinkMacSystemFont',
    'Segoe UI',
    'sans-serif',
  ];

  static TextStyle _font({
    required double fontSize,
    required FontWeight fontWeight,
    required Color color,
  }) {
    return GoogleFonts.inter(
      textStyle: const TextStyle(fontFamilyFallback: fontFallbacks),
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
    );
  }

  /// Architectural Studio Display Heading Font (`Space Grotesk`)
  static TextStyle displayFont({
    required double fontSize,
    FontWeight fontWeight = FontWeight.w700,
    required Color color,
    double letterSpacing = -0.3,
    double? height,
  }) {
    return GoogleFonts.spaceGrotesk(
      textStyle: const TextStyle(fontFamilyFallback: fontFallbacks),
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      height: height,
      color: color,
    );
  }

  static final ThemeData darkTheme = _buildDarkTheme();
  static final ThemeData lightTheme = _buildLightTheme();

  static ThemeData _buildDarkTheme() {
    return ThemeData.dark().copyWith(
      scaffoldBackgroundColor: bgBase,
      primaryColor: const Color(0xFFEDEDED),
      canvasColor: bgPanel,
      cardColor: bgSurface,
      dividerColor: borderSubtle,
      textTheme: TextTheme(
        displayLarge: displayFont(fontSize: 24, fontWeight: FontWeight.w700, color: textPrimary),
        displayMedium: displayFont(fontSize: 20, fontWeight: FontWeight.w700, color: textPrimary),
        titleLarge: displayFont(fontSize: 16.5, fontWeight: FontWeight.w700, color: textPrimary),
        titleMedium: displayFont(fontSize: 14.5, fontWeight: FontWeight.w700, color: textPrimary),
        bodyLarge: _font(fontSize: 14, fontWeight: FontWeight.w400, color: textPrimary),
        bodyMedium: _font(fontSize: 13, fontWeight: FontWeight.w400, color: textSecondary),
        bodySmall: _font(fontSize: 11.5, fontWeight: FontWeight.w400, color: textMuted),
        labelSmall: _font(fontSize: 10.5, fontWeight: FontWeight.w500, color: textMuted),
      ),
      colorScheme: const ColorScheme.dark(
        surface: bgSurface,
        primary: Color(0xFFEDEDED),
        secondary: Color(0xFFA1A1AA),
        onSurface: textPrimary,
        onSurfaceVariant: textSecondary,
        outline: borderBright,
        outlineVariant: borderSubtle,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: bgSurface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: borderSubtle),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: borderSubtle),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: Color(0xFF52525B)),
        ),
        hintStyle: GoogleFonts.inter(color: textMuted, fontSize: 13),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 300),
        showDuration: const Duration(milliseconds: 1500),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF18181B),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFF3F3F46), width: 0.8),
          boxShadow: const [
            BoxShadow(color: Colors.black54, blurRadius: 8, offset: Offset(0, 3)),
          ],
        ),
        textStyle: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: const Color(0xFFF4F4F5),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        width: 300,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: borderBright),
        ),
        backgroundColor: bgSurfaceHover,
        contentTextStyle: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: textPrimary,
        ),
        elevation: 0,
      ),
      cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
        ),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: bgPanel,
        elevation: 0,
      ),
    );
  }

  // ── Eggshell Light Theme Data ─────────────────────────────────────────────
  static ThemeData _buildLightTheme() {
    return ThemeData.light().copyWith(
      scaffoldBackgroundColor: bgBaseLight,
      primaryColor: const Color(0xFF18181B),
      canvasColor: bgPanelLight,
      cardColor: bgSurfaceLight,
      dividerColor: borderSubtleLight,
      textTheme: TextTheme(
        displayLarge: displayFont(fontSize: 24, fontWeight: FontWeight.w700, color: textPrimaryLight),
        displayMedium: displayFont(fontSize: 20, fontWeight: FontWeight.w700, color: textPrimaryLight),
        titleLarge: displayFont(fontSize: 16.5, fontWeight: FontWeight.w700, color: textPrimaryLight),
        titleMedium: displayFont(fontSize: 14.5, fontWeight: FontWeight.w700, color: textPrimaryLight),
        bodyLarge: _font(fontSize: 14, fontWeight: FontWeight.w400, color: textPrimaryLight),
        bodyMedium: _font(fontSize: 13, fontWeight: FontWeight.w400, color: textSecondaryLight),
        bodySmall: _font(fontSize: 11.5, fontWeight: FontWeight.w400, color: textMutedLight),
        labelSmall: _font(fontSize: 10.5, fontWeight: FontWeight.w500, color: textMutedLight),
      ),
      colorScheme: const ColorScheme.light(
        surface: bgSurfaceLight,
        primary: Color(0xFF18181B),
        secondary: Color(0xFF52525B),
        onSurface: textPrimaryLight,
        onSurfaceVariant: textSecondaryLight,
        outline: borderBrightLight,
        outlineVariant: borderSubtleLight,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: bgSurfaceLight,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: borderSubtleLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: borderSubtleLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: Color(0xFFA1A1AA)),
        ),
        hintStyle: GoogleFonts.inter(color: textMutedLight, fontSize: 13),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 300),
        showDuration: const Duration(milliseconds: 1500),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: bgSurfaceRaisedLight,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: borderSubtleLight, width: 0.8),
          boxShadow: const [
            BoxShadow(color: Color(0x14000000), blurRadius: 8, offset: Offset(0, 3)),
          ],
        ),
        textStyle: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: textPrimaryLight,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        width: 300,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: borderBrightLight),
        ),
        backgroundColor: bgSurfaceHoverLight,
        contentTextStyle: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: textPrimaryLight,
        ),
        elevation: 0,
      ),
      cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
        ),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: bgPanelLight,
        elevation: 0,
      ),
    );
  }
}

class AppToast {
  static final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  static void show(
    BuildContext? context,
    String message, {
    IconData? icon,
    Duration duration = const Duration(seconds: 2),
    bool isDark = true,
    Color? accentColor,
  }) {
    final messenger = (context != null && context.mounted)
        ? (ScaffoldMessenger.maybeOf(context) ?? messengerKey.currentState)
        : messengerKey.currentState;

    if (messenger == null) return;

    final effectiveColor =
        accentColor ?? AppTheme.textPrimaryFor(isDark);

    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        duration: duration,
        behavior: SnackBarBehavior.floating,
        elevation: 8,
        margin: const EdgeInsets.only(bottom: 44, left: 32, right: 32),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: AppTheme.borderSubtleFor(isDark),
            width: 1.0,
          ),
        ),
        backgroundColor: AppTheme.bgSurfaceRaisedFor(isDark),
        content: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 15, color: effectiveColor),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                message,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimaryFor(isDark),
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shared DRY theme color getters and rich-text helpers for screen State classes
/// (`ProjectPitchScreen`, `ReleasePlanGateScreen`, `ReleaseWorkbenchScreen`).
mixin WorkbenchThemeMixin {
  bool get isDark;

  Color get bgBase => AppTheme.bgBaseFor(isDark);
  Color get bgSurface => AppTheme.bgSurfaceFor(isDark);
  Color get bgRecessed => AppTheme.bgSurfaceRecessedFor(isDark);
  Color get bgActive => AppTheme.bgSurfaceActiveFor(isDark);
  Color get bgHover => AppTheme.bgSurfaceHoverFor(isDark);
  Color get borderSubtle => AppTheme.borderSubtleFor(isDark);
  Color get borderBright => AppTheme.borderBrightFor(isDark);
  Color get textPrimary => AppTheme.textPrimaryFor(isDark);
  Color get textSecondary => AppTheme.textSecondaryFor(isDark);
  Color get textMuted => AppTheme.textMutedFor(isDark);
  Color get focalAccent => AppTheme.focalAccentFor(isDark);
  Color get focalAccentFg => AppTheme.focalAccentFgFor(isDark);
  Color get accentEmerald => AppTheme.accentGreenFor(isDark);
  Color get accentCrimson => AppTheme.accentRedFor(isDark);
  Color get accentAmber => AppTheme.accentAmberFor(isDark);
  Color get accentCyan => AppTheme.accentCyanFor(isDark);
  Color get accentViolet => AppTheme.accentPurpleFor(isDark);
}

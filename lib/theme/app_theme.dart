import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // ── Dark Palette (Obsidian Slate · Crisp White Ink & Emerald Accent) ───────
  static const Color bgBase =
      Color(0xFF0D0F12); // Main app canvas & recessed step card (--bg: #0D0F12)
  static const Color bgPanel =
      Color(0xFF14171C); // Sidebar / Panel elevated background (--surface: #14171C)
  static const Color bgSurface =
      Color(0xFF14171C); // Cards, inputs, surface fills (--surface: #14171C)
  static const Color bgSurfaceHover =
      Color(0xFF1A1E24); // Hover / secondary surface (--surface-2: #1A1E24)
  static const Color bgSurfaceActive =
      Color(0xFF20252D); // Active/selected list item highlight (--surface-3: #20252D)

  static const Color borderSubtle =
      Color(0xFF262B33); // Crisp 1px slate boundary (--border: #262B33)
  static const Color borderBright =
      Color(0xFF383F4B); // Strong structural border (--border-strong: #383F4B)

  static const Color textPrimary =
      Color(0xFFF1F3F5); // Crisp neutral white primary text (--text: #F1F3F5)
  static const Color textSecondary =
      Color(0xFF9BA3AE); // Cool slate secondary text (--text-sec: #9BA3AE)
  static const Color textMuted =
      Color(0xFF636B78); // Muted slate label / metadata text (--text-muted: #636B78)

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

  // ── Semantic Surface Scale ────────────────────────────────────────────────
  static const Color bgSurfaceRaised =
      Color(0xFF1A1E24); // Elevated cards, chiclets, floating toolbars (Dark)
  static const Color bgSurfaceRecessed =
      Color(0xFF0D0F12); // Recessed insets, Step Card well (Dark)
  static const Color bgSurfaceRaisedLight =
      Color(0xFFFFFFFF); // Elevated cards on light
  static const Color bgSurfaceRecessedLight =
      Color(0xFFF1F5F9); // Recessed insets on light
  static const Color bgSurfaceActiveLight =
      Color(0xFFE2E8F0); // Active/selected list item on light

  static const Color bgInset = Color(0xFF0D0F12); // Recessed insets / inner cards (Dark)
  static const Color bgInsetLight = Color(0xFFF1F5F9); // Recessed insets / inner cards (Light)

  // ── Reversible Polarity Focal Accent (Crisp White in Dark ↔ Deep Slate in Light) ─
  static const Color focalAccentDark = Color(0xFFF1F3F5);
  static const Color focalAccentFgDark = Color(0xFF0D0F12);
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

  // ── Tier Semantic Accents ─────────────────────────────────────────────────
  static const Color tierProject = accentAmber;
  static const Color tierRelease = accentCyan;
  static const Color tierEpic = accentPurple;
  static const Color tierFeature = accentOrange;

  // ── Standard Radius Scale ─────────────────────────────────────────────────
  static const double radiusXs = 4.0;   // Chips, small tags, micro badges
  static const double radiusSm = 6.0;   // Buttons, inputs, small cards
  static const double radiusMd = 8.0;   // Cards, menus, dropdowns
  static const double radiusLg = 12.0;  // Modals, workstation containers, toast
  static const double radiusPill = 999.0; // Status badges, pill counters

  // ── Standard Button & Hit Target Heights ───────────────────────────────────
  static const double hitTargetMinimum = 32.0;    // Fitts's Law minimum touch/click target
  static const double buttonHeightToolbar = 28.0; // Header, toolbar, and card actions
  static const double buttonHeightAction = 32.0;  // Standard interactive button
  static const double buttonHeightDialog = 36.0;  // Modal dialog action buttons

  // ── Unified Theme Transition ──────────────────────────────────────────────
  static const Duration themeTransitionDuration = Duration(milliseconds: 300);
  static const Curve themeTransitionCurve = Curves.easeInOut;

  // ── Action Button Palette (Linear Strict System: Color Only for Buttons) ─
  static const Color buttonAutoFill = Color(0xFF10B981); // Emerald Green
  static const Color buttonAutoFillDarkText = Color(0xFF34D399);
  static const Color buttonBreakdown = Color(0xFF8B5CF6); // Linear Purple
  static const Color buttonBreakdownDarkText = Color(0xFFA78BFA);
  static const Color buttonDelete = Color(0xFFEF4444); // Rose Red
  static const Color buttonDeleteDarkText = Color(0xFFF87171);

  // ── Purposeful Semantic Accents (Clean Craft Scale) ───────────────────────
  static const Color accentAmber = Color(0xFFFCD34D); // Soft Gold (Dark)
  static const Color accentAmberLight = Color(0xFFA87E35); // Muted Ochre (Light)
  static Color accentAmberFor(bool isDark) => isDark ? accentAmber : accentAmberLight;

  static const Color accentAmberDarkText = Color(0xFFFCD34D);
  static const Color accentAmberLightText = Color(0xFFA87E35);
  static const Color accentAmberSubtle = Color(0x1FFCD34D);
  static const Color accentAmberBorder = Color(0x3DFCD34D);

  static const Color accentBlue = Color(0xFF60A5FA); // Soft Ice Blue (Dark)
  static const Color accentBlueLight = Color(0xFF436D99); // Muted Denim (Light)
  static Color accentBlueFor(bool isDark) => isDark ? accentBlue : accentBlueLight;

  static const Color accentPurple = Color(0xFFC084FC); // Soft Lilac (Dark)
  static const Color accentPurpleLight = Color(0xFF84689E); // Muted Heather Plum (Light)
  static Color accentPurpleFor(bool isDark) => isDark ? accentPurple : accentPurpleLight;

  static const Color accentOrange = Color(0xFFFDBA74); // Soft Peach (Dark)
  static const Color accentOrangeLight = Color(0xFFB86E47); // Terracotta Clay (Light)
  static Color accentOrangeFor(bool isDark) => isDark ? accentOrange : accentOrangeLight;

  static const Color accentGreen = Color(0xFF10B981); // Crisp Emerald (--emerald: #10B981)
  static const Color accentGreenLight = Color(0xFF059669); // Emerald (Light)
  static Color accentGreenFor(bool isDark) => isDark ? accentGreen : accentGreenLight;

  static const Color accentRed = Color(0xFFF87171); // Soft Coral (Dark)
  static const Color accentRedLight = Color(0xFFC25450); // Brick Coral (Light)
  static Color accentRedFor(bool isDark) => isDark ? accentRed : accentRedLight;

  static const Color accentCyan = Color(0xFF38BDF8); // Sky Blue (Dark)
  static const Color accentCyanLight = Color(0xFF3B72A8); // Nordic Slate (Light)
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

  static ThemeData get darkTheme {
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
  static ThemeData get lightTheme {
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
        accentColor ?? (isDark ? const Color(0xFFEDEDED) : const Color(0xFF18181B));

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
  static final RegExp _metricHighlightRegex = RegExp(
    r'\b(\d+(?:[\.\-]\d+)?(?:\s*(?:minute|minutes|min|second|seconds|sec|s|FPS|fps|key|keys|waves|wave|enemies|enemy|rooms|room|players|player|times|time|ms|%))?)\b',
    caseSensitive: false,
  );

  bool get isDark;

  Color get bgBase => AppTheme.bgBaseFor(isDark);
  Color get bgSurface => AppTheme.bgSurfaceFor(isDark);
  Color get bgRecessed => AppTheme.bgSurfaceRecessedFor(isDark);
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

  /// Highlights quantitative playtest metrics (e.g., `10-minute`, `3 escalating waves`, `60 FPS`)
  /// using a pre-compiled static regex so zero regex compilation occurs during widget builds.
  Widget buildMetricHighlightedRichText(
    String statement, {
    bool usePill = false,
    double fontSize = 13.5,
    double height = 1.48,
  }) {
    final spans = <InlineSpan>[];
    int lastEnd = 0;

    for (final match in _metricHighlightRegex.allMatches(statement)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: statement.substring(lastEnd, match.start)));
      }
      final metricText = match.group(0)!;
      if (usePill) {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
              decoration: BoxDecoration(
                color: accentEmerald.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: accentEmerald.withValues(alpha: 0.42),
                ),
              ),
              child: Text(
                metricText,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: textPrimary,
                ),
              ),
            ),
          ),
        );
      } else {
        spans.add(
          TextSpan(
            text: metricText,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: accentEmerald,
            ),
          ),
        );
      }
      lastEnd = match.end;
    }

    if (lastEnd < statement.length) {
      spans.add(TextSpan(text: statement.substring(lastEnd)));
    }

    return RichText(
      text: TextSpan(
        style: GoogleFonts.inter(
          fontSize: fontSize,
          fontWeight: FontWeight.w500,
          height: height,
          color: textPrimary,
        ),
        children: spans,
      ),
    );
  }
}

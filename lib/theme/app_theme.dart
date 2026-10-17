import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // ── Dark Palette (Deep Studio Charcoal · High-Contrast Tactile Depth) ────
  static const Color bgBase =
      Color(0xFF181A20); // Main app canvas backdrop (deep charcoal canvas)
  static const Color bgPanel =
      Color(0xFF1E2128); // Sidebar / Panel elevated background (charcoal sidebar)
  static const Color bgSurface =
      Color(0xFF22252E); // Cards, inputs, surface fills (charcoal card floor)
  static const Color bgSurfaceHover =
      Color(0xFF2C303B); // Hover state background
  static const Color bgSurfaceActive =
      Color(0xFF2C303B); // Active/selected list item highlight

  static const Color borderSubtle =
      Color(0xFF323642); // Crisp structural lines (clear boundary)
  static const Color borderBright =
      Color(0xFF454B5C); // Focused input / active structural borders

  static const Color textPrimary =
      Color(0xFFF8FAFC); // Soft crisp off-white primary text / headings (Slate-50)
  static const Color textSecondary =
      Color(0xFF94A3B8); // Clean slate secondary text (Slate-400)
  static const Color textMuted =
      Color(0xFF64748B); // Readable dimmed label / metadata text (Slate-500)

  // ── Light Palette (Warm Cashmere Paper / Non-Harsh Natural Linen) ──────────
  static const Color bgBaseLight =
      Color(0xFFE9E4DA); // Main canvas backdrop (warm unbleached linen paper)
  static const Color bgPanelLight =
      Color(0xFFF3EFE6); // Sidebar / TitleBar / Dialogs (soft cashmere cream)
  static const Color bgSurfaceLight =
      Color(0xFFF3EFE6); // Document cards (soft cashmere cream, not stark white)
  static const Color bgSurfaceHoverLight =
      Color(0xFFDFD9CC); // Hover state background (warm scooped stone)

  static const Color borderSubtleLight =
      Color(0xFFD3CCC0); // Crisp 1px warm cashmere stone sand structural lines
  static const Color borderBrightLight =
      Color(0xFFB8B0A2); // Focused / active borders

  static const Color textPrimaryLight =
      Color(0xFF343029); // Deep warm espresso charcoal ink primary headings
  static const Color textSecondaryLight =
      Color(0xFF655F54); // Warm earth secondary text
  static const Color textMutedLight =
      Color(0xFF8C8578); // Warm stone dimmed metadata text

  // ── Semantic Surface Scale ────────────────────────────────────────────────
  static const Color bgSurfaceRaised =
      Color(0xFF2F333F); // Elevated cards, chiclets, floating toolbars (Dark)
  static const Color bgSurfaceRecessed =
      Color(0xFF121419); // Recessed insets, sockets, formula chips (Dark)
  static const Color bgSurfaceRaisedLight =
      Color(0xFFFFFFFF); // Elevated cards on light (pure white stone)
  static const Color bgSurfaceRecessedLight =
      Color(0xFFE5DFD1); // Recessed insets on light (warm stone socket)
  static const Color bgSurfaceActiveLight =
      Color(0xFFE5DFD1); // Active/selected list item on light

  static const Color bgInset = Color(0xFF121419); // Recessed insets / inner cards (Dark)
  static const Color bgInsetLight = Color(0xFFE5DFD1); // Recessed insets / inner cards (Light)

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

  static const Color accentGreen = Color(0xFF4ADE80); // Soft Mint (Dark)
  static const Color accentGreenLight = Color(0xFF4B8559); // Sage Moss (Light)
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

  static ThemeData get darkTheme {
    return ThemeData.dark().copyWith(
      scaffoldBackgroundColor: bgBase,
      primaryColor: const Color(0xFFEDEDED),
      canvasColor: bgPanel,
      cardColor: bgSurface,
      dividerColor: borderSubtle,
      textTheme: TextTheme(
        displayLarge: _font(fontSize: 24, fontWeight: FontWeight.w700, color: textPrimary),
        displayMedium: _font(fontSize: 20, fontWeight: FontWeight.w600, color: textPrimary),
        titleLarge: _font(fontSize: 16, fontWeight: FontWeight.w600, color: textPrimary),
        titleMedium: _font(fontSize: 14, fontWeight: FontWeight.w600, color: textPrimary),
        bodyLarge: _font(fontSize: 14, fontWeight: FontWeight.w400, color: textPrimary),
        bodyMedium: _font(fontSize: 13, fontWeight: FontWeight.w400, color: textSecondary),
        bodySmall: _font(fontSize: 11, fontWeight: FontWeight.w400, color: textMuted),
        labelSmall: _font(fontSize: 10, fontWeight: FontWeight.w500, color: textMuted),
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
        displayLarge: _font(fontSize: 24, fontWeight: FontWeight.w700, color: textPrimaryLight),
        displayMedium: _font(fontSize: 20, fontWeight: FontWeight.w600, color: textPrimaryLight),
        titleLarge: _font(fontSize: 16, fontWeight: FontWeight.w600, color: textPrimaryLight),
        titleMedium: _font(fontSize: 14, fontWeight: FontWeight.w600, color: textPrimaryLight),
        bodyLarge: _font(fontSize: 14, fontWeight: FontWeight.w400, color: textPrimaryLight),
        bodyMedium: _font(fontSize: 13, fontWeight: FontWeight.w400, color: textSecondaryLight),
        bodySmall: _font(fontSize: 11, fontWeight: FontWeight.w400, color: textMutedLight),
        labelSmall: _font(fontSize: 10, fontWeight: FontWeight.w500, color: textMutedLight),
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

  // ── Studio Neumorphic Decorations (Light & Dark Adaptive) ─────────────────

  /// Soft raised extruded surface (Cards, Floating Dialogs, Tool Panels)
  static BoxDecoration neumorphicRaised({
    double borderRadius = 8,
    Color? surfaceColor,
    Color? highlightColor,
    Color? shadowColor,
    Border? border,
    bool isHovered = false,
    Color? accentGlow,
    bool isDark = true,
  }) {
    final effectiveSurface = surfaceColor ??
        (isDark
            ? (isHovered ? bgSurfaceHover : bgSurface)
            : (isHovered ? bgSurfaceHoverLight : bgSurfaceLight));

    return BoxDecoration(
      color: isHovered
          ? (isDark ? bgSurfaceHover : bgSurfaceHoverLight)
          : effectiveSurface,
      borderRadius: BorderRadius.circular(borderRadius),
      border: border ??
          Border.all(color: isDark ? borderSubtle : borderSubtleLight),
      boxShadow: const [],
    );
  }

  /// Debossed / Sunken recessed surface (Input fields, Search bars, Prompt chat bars, Toggle tracks)
  static BoxDecoration neumorphicInset({
    double borderRadius = 6,
    Color? surfaceColor,
    Color? borderColor,
    bool isDark = true,
  }) {
    final effectiveSurface = surfaceColor ??
        (isDark ? bgSurfaceRecessed : bgSurfaceRecessedLight);

    return BoxDecoration(
      color: effectiveSurface,
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(
          color: borderColor ?? (isDark ? borderSubtle : borderSubtleLight)),
      boxShadow: const [],
    );
  }

  /// Pure Solid Tactile Push-In / Push-Out Mechanical Depth Decoration
  /// - Zero Gradients: Pure solid physical surfaces only
  /// - Zero Color Overlays: Sunken socket uses neutral cavity floor with dimmed outline
  /// - Differentiated Instant Hover: Bright outline light-up when unpushed; dimmer subtle outline when pushed in
  /// - Push-Out (!isPushed): Solid elevated surface casting bold physical drop shadow
  /// - Push-In (isPushed): Sinks into socket with outer shadow completely collapsed to zero
  static BoxDecoration tactileSolidDecoration({
    required bool isDark,
    required bool isPushed, // true when selected or completed
    bool isHovered = false,
    double borderRadius = 6.0,
    Color? rimColor, // Optional 360° ring rim color
  }) {
    if (isPushed) {
      // ── Pushed-In (Selected or Completed: Sinks into socket) ───────────
      final cavityColor =
          isDark ? const Color(0xFF121419) : const Color(0xFFE5DFD1);
      final dimmedOutline = isHovered
          ? (isDark ? const Color(0xFF3A4052) : const Color(0xFF9E9686))
          : (isDark ? const Color(0xFF262A35) : const Color(0xFFBDB6A6));

      final effectiveBorderColor = rimColor != null
          ? rimColor.withValues(
              alpha: isHovered
                  ? (isDark ? 0.72 : 0.78)
                  : (isDark ? 0.55 : 0.65),
            )
          : dimmedOutline;

      return BoxDecoration(
        color: cavityColor,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: effectiveBorderColor,
          width: rimColor != null ? 1.6 : (isHovered ? 1.4 : 1.2),
        ),
        boxShadow: const [],
      );
    }

    // ── Push-Out / Elevated (Unselected or Pending) ─────────────────────
    final solidSurface =
        isDark ? const Color(0xFF2F333F) : const Color(0xFFFFFFFF);
    final unpushedBorder = isHovered
        ? (isDark ? const Color(0xFF68728C) : const Color(0xFFA69D8B))
        : (isDark ? const Color(0xFF444A5C) : const Color(0xFFD6CEBF));

    final effectiveBorderColor = rimColor ?? unpushedBorder;

    return BoxDecoration(
      color: solidSurface,
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(
        color: effectiveBorderColor,
        width: rimColor != null ? (isHovered ? 1.8 : 1.6) : (isHovered ? 1.5 : 1.2),
      ),
      boxShadow: isHovered
          ? [
              BoxShadow(
                color:
                    isDark ? const Color(0xF2000000) : const Color(0x38000000),
                blurRadius: 10,
                offset: const Offset(0, 4.5),
              ),
              BoxShadow(
                color:
                    isDark ? const Color(0xB8000000) : const Color(0x1C000000),
                blurRadius: 2.5,
                offset: const Offset(0, 1.5),
              ),
            ]
          : [
              BoxShadow(
                color:
                    isDark ? const Color(0xE0000000) : const Color(0x28000000),
                blurRadius: 7,
                offset: const Offset(0, 3),
              ),
              BoxShadow(
                color:
                    isDark ? const Color(0xA6000000) : const Color(0x14000000),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
    );
  }

  /// Wraps a tactile card with mechanical vertical travel (+1px pushed-in, -0.5px/-1.5px unpushed)
  /// and paints a true top/left inner cavity occlusion shadow when `isPushed` is true.
  static Widget wrapTactileSurface({
    required bool isDark,
    required bool isPushed,
    bool isHovered = false,
    double borderRadius = 6.0,
    bool enableTravel = true,
    EdgeInsetsGeometry? margin,
    required Widget child,
  }) {
    final dy = !enableTravel
        ? 0.0
        : (isPushed ? 1.0 : (isHovered ? -1.5 : -0.5));

    Widget surface = child;
    if (isPushed) {
      surface = CustomPaint(
        foregroundPainter: _InnerSocketShadowPainter(
          isDark: isDark,
          borderRadius: borderRadius,
        ),
        child: surface,
      );
    }

    if (dy != 0.0) {
      surface = Transform.translate(
        offset: Offset(0, dy),
        child: surface,
      );
    }

    if (margin != null) {
      surface = Padding(
        padding: margin,
        child: surface,
      );
    }

    return surface;
  }

  /// Backward-compatible wrapper delegating to pure tactile solid decoration
  static BoxDecoration clayChicletDecoration({
    required bool isDark,
    required bool isDone,
    Color? accentColor,
    bool isHovered = false,
    double borderRadius = 6.0,
  }) {
    return tactileSolidDecoration(
      isDark: isDark,
      isPushed: isDone,
      isHovered: isHovered,
      borderRadius: borderRadius,
    );
  }

  /// Tactile Neumorphic Button (Depresses on click/selection, glows on hover)
  static BoxDecoration neumorphicButton({
    double borderRadius = 6,
    Color? surfaceColor,
    Color? accentColor,
    bool isPressed = false,
    bool isHovered = false,
    bool isSelected = false,
    bool isDark = true,
  }) {
    final defaultSurface = isDark ? bgSurface : bgSurfaceLight;
    final defaultHover = isDark ? bgSurfaceHover : bgSurfaceHoverLight;
    final effectiveSurface = surfaceColor ?? defaultSurface;

    if (isSelected || isPressed) {
      return BoxDecoration(
        color: accentColor != null
            ? accentColor.withValues(alpha: isDark ? 0.15 : 0.12)
            : (isDark ? bgSurfaceActive : bgSurfaceActiveLight),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: accentColor ?? (isDark ? borderBright : borderBrightLight),
          width: isSelected ? 1.5 : 1.0,
        ),
        boxShadow: const [],
      );
    }

    return BoxDecoration(
      color: isHovered ? defaultHover : effectiveSurface,
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(
        color: isHovered && accentColor != null
            ? accentColor.withValues(alpha: 0.6)
            : (isDark ? borderSubtle : borderSubtleLight),
      ),
      boxShadow: const [],
    );
  }

  /// Neumorphic LED Glow (Used for tier badges and alignment score meters)
  static BoxDecoration neumorphicGlow({
    required Color glowColor,
    double borderRadius = 6,
    double intensity = 0.35,
    double blur = 8,
    bool isDark = true,
  }) {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(borderRadius),
      boxShadow: const [],
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

/// Reactive interpolated theme tokens from [AnimatedTheme]
extension AppThemeContext on BuildContext {
  Color get textPrimary => Theme.of(this).colorScheme.onSurface;
  Color get textSecondary => Theme.of(this).colorScheme.onSurfaceVariant;
  Color get textMuted =>
      Theme.of(this).textTheme.bodySmall?.color ?? AppTheme.textMuted;
  Color get bgBase => Theme.of(this).scaffoldBackgroundColor;
  Color get bgPanel => Theme.of(this).canvasColor;
  Color get bgSurface => Theme.of(this).cardColor;
  Color get bgSurfaceRaised =>
      AppTheme.bgSurfaceRaisedFor(Theme.of(this).brightness == Brightness.dark);
  Color get bgSurfaceRecessed =>
      AppTheme.bgSurfaceRecessedFor(Theme.of(this).brightness == Brightness.dark);
  Color get bgSurfaceActive =>
      AppTheme.bgSurfaceActiveFor(Theme.of(this).brightness == Brightness.dark);
  Color get borderSubtle => Theme.of(this).dividerColor;
  Color get borderBright => Theme.of(this).colorScheme.outline;
}

enum DocumentStatus {
  notStarted('Not Started'),
  inProgress('In Progress'),
  completed('Completed');

  final String label;
  const DocumentStatus(this.label);

  static DocumentStatus fromStats({
    required int progress,
    int totalItems = 0,
    int completedItems = 0,
    bool hasItems = true,
  }) {
    if (progress == 100 && (hasItems || totalItems > 0)) {
      return DocumentStatus.completed;
    }
    if (progress > 0 || completedItems > 0) {
      return DocumentStatus.inProgress;
    }
    return DocumentStatus.notStarted;
  }
}

class AppStatusPill extends StatelessWidget {
  final DocumentStatus status;
  final bool isDark;
  final VoidCallback? onTap;
  final String? tooltip;
  final EdgeInsetsGeometry padding;
  final double fontSize;

  const AppStatusPill({
    super.key,
    required this.status,
    required this.isDark,
    this.onTap,
    this.tooltip,
    this.padding = const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    this.fontSize = 11.0,
  });

  @override
  Widget build(BuildContext context) {
    final Color textColor;
    final Color bgColor;
    final Color borderColor;

    switch (status) {
      case DocumentStatus.completed:
        textColor = isDark ? const Color(0xFFEDEDED) : const Color(0xFF18181B);
        bgColor = isDark ? const Color(0xFF27272A) : const Color(0xFFE4DDD2);
        borderColor = isDark ? const Color(0xFF3F3F46) : const Color(0xFFD6CEC0);
      case DocumentStatus.inProgress:
        textColor = AppTheme.textSecondaryFor(isDark);
        bgColor = isDark ? const Color(0xFF18181B) : const Color(0xFFEFECE6);
        borderColor = AppTheme.borderSubtleFor(isDark);
      case DocumentStatus.notStarted:
        textColor = AppTheme.textMutedFor(isDark);
        bgColor = isDark ? const Color(0xFF141416) : const Color(0xFFFAF8F5);
        borderColor = AppTheme.borderSubtleFor(isDark);
    }

    Widget pill = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: borderColor, width: 0.9),
      ),
      child: Text(
        status.label,
        style: GoogleFonts.inter(
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          color: textColor,
          letterSpacing: -0.1,
        ),
      ),
    );

    if (onTap != null) {
      pill = InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        child: pill,
      );
    }

    if (tooltip != null) {
      pill = Tooltip(
        message: tooltip!,
        child: pill,
      );
    }

    return pill;
  }
}

/// Centralized Design System & Stylesheet for all Document Rendering
class DocumentStyle {
  // ── Bullet Dot Dimensions ──
  static const double dotSize = 6.0;
  static const EdgeInsets dotPadding =
      EdgeInsets.only(top: 8.5, right: 10.0, left: 2.0);
  static const EdgeInsets itemMargin = EdgeInsets.only(bottom: 8.0);
  static const EdgeInsets itemPadding =
      EdgeInsets.symmetric(horizontal: 6, vertical: 2.5);

  // ── Section Header Typography ──
  static TextStyle sectionHeader({
    required bool isDark,
    Color? activeColor,
    bool isHighlighted = false,
  }) {
    return GoogleFonts.inter(
      fontSize: 14.5,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.6,
      color: isHighlighted && activeColor != null
          ? activeColor
          : AppTheme.textPrimaryFor(isDark),
    );
  }

  // ── Eyebrow Label Typography (Stacked Milestone Keys) ──
  static TextStyle eyebrowLabel({
    required bool isDark,
    Color? activeColor,
    bool isHighlighted = false,
  }) {
    final defaultColor =
        isDark ? const Color(0xFFA1A1AA) : const Color(0xFF78716C);
    return GoogleFonts.inter(
      fontSize: 13.0,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.6,
      color:
          isHighlighted && activeColor != null ? activeColor : defaultColor,
    );
  }

  // ── Value / Description Body Typography ──
  static TextStyle bodyText({
    required bool isDark,
  }) {
    return GoogleFonts.inter(
      fontSize: 16.0,
      height: 1.50,
      letterSpacing: -0.005,
      fontWeight: FontWeight.w400,
      color: isDark ? const Color(0xFFF4F4F5) : AppTheme.textPrimaryFor(false),
    );
  }

  // ── Placeholder / Empty Typography ──
  static TextStyle placeholderText({
    required bool isDark,
  }) {
    return GoogleFonts.inter(
      fontSize: 15.5,
      height: 1.45,
      fontWeight: FontWeight.w400,
      color: AppTheme.textMutedFor(isDark).withValues(alpha: 0.65),
    );
  }

  // ── Formula & Monospace Specification Tokens ──

  /// Detects physical units (e.g. "6.0 m/s", "120ms", "10%", "30fps"),
  /// comparison numbers (e.g. "> 0.7", "< 50", "= 1.0"), and backtick code tokens (e.g. "`Vector3`").
  static final RegExp formulaRegex = RegExp(
    r'(?:[<>=]?[-+]?\d+\.\d+(?:\s*(?:m/s|ms|s|m|fps|deg|px|tris|%))?)|(?:[<>=]?[-+]?\d+(?:[°%]|(?:\s*(?:m/s|ms|fps|deg|px|tris))\b))|(?:`[^`]+`)',
  );

  /// Standard inline monospace chip renderer for formulas, variables, and physical unit tokens.
  static Widget buildFormulaChip(
    String text,
    bool isDark, {
    double fontSize = 12.0,
    EdgeInsetsGeometry? margin,
  }) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 480),
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 2.5, vertical: 1),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1B1B1E) : const Color(0xFFEFECE4),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isDark ? const Color(0xFF2E2E33) : const Color(0xFFDCD6C9),
          width: 0.8,
        ),
      ),
      child: Text(
        text.replaceAll('`', ''),
        softWrap: true,
        style: GoogleFonts.jetBrainsMono(
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          color: isDark ? const Color(0xFFEDEDED) : const Color(0xFF18181B),
          letterSpacing: -0.2,
        ),
      ),
    );
  }
}

/// Central Single Source of Truth for typography tokens across the application.
/// Enforces:
/// - `GoogleFonts.inter` for human reading copy, titles, dialogs, and goals.
/// - `GoogleFonts.jetBrainsMono` for data, code, structural labels, eyebrows, counters, and specs.
class AppTypography {
  // Document and section headings (Inter)
  static TextStyle h1(bool isDark, {Color? color}) => GoogleFonts.inter(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        height: 1.25,
        letterSpacing: -0.3,
        color: color ?? AppTheme.textPrimaryFor(isDark),
      );

  static TextStyle h2(bool isDark, {Color? color}) => GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        height: 1.3,
        letterSpacing: -0.2,
        color: color ?? AppTheme.textPrimaryFor(isDark),
      );

  static TextStyle cardTitle(
    bool isDark, {
    Color? color,
    double fontSize = 13,
    FontWeight fontWeight = FontWeight.w600,
    double height = 1.35,
  }) =>
      GoogleFonts.inter(
        fontSize: fontSize,
        fontWeight: fontWeight,
        height: height,
        color: color ?? AppTheme.textPrimaryFor(isDark),
      );

  // Body prose and goals (Inter)
  static TextStyle body(
    bool isDark, {
    Color? color,
    double fontSize = 13,
    double height = 1.5,
    FontStyle fontStyle = FontStyle.normal,
    FontWeight fontWeight = FontWeight.w400,
  }) =>
      GoogleFonts.inter(
        fontSize: fontSize,
        fontWeight: fontWeight,
        height: height,
        fontStyle: fontStyle,
        color: color ?? AppTheme.textSecondaryFor(isDark),
      );

  static TextStyle bodyStrong(
    bool isDark, {
    Color? color,
    double fontSize = 13,
    double height = 1.5,
  }) =>
      GoogleFonts.inter(
        fontSize: fontSize,
        fontWeight: FontWeight.w600,
        height: height,
        color: color ?? AppTheme.textPrimaryFor(isDark),
      );

  static TextStyle bodyMuted(
    bool isDark, {
    Color? color,
    double fontSize = 12,
    double height = 1.4,
    FontStyle fontStyle = FontStyle.normal,
    FontWeight fontWeight = FontWeight.w400,
  }) =>
      GoogleFonts.inter(
        fontSize: fontSize,
        fontWeight: fontWeight,
        height: height,
        fontStyle: fontStyle,
        color: color ?? AppTheme.textMutedFor(isDark),
      );

  // Eyebrows, Metadata & Specs (JetBrains Mono)
  static TextStyle eyebrow(
    bool isDark, {
    Color? color,
    double fontSize = 11,
    FontWeight fontWeight = FontWeight.w700,
    double letterSpacing = 0.8,
  }) =>
      GoogleFonts.jetBrainsMono(
        fontSize: fontSize,
        fontWeight: fontWeight,
        letterSpacing: letterSpacing,
        color: color ?? AppTheme.textSecondaryFor(isDark),
      );

  static TextStyle specKey(
    bool isDark, {
    Color? color,
    double fontSize = 11,
    FontWeight fontWeight = FontWeight.w600,
  }) =>
      GoogleFonts.jetBrainsMono(
        fontSize: fontSize,
        fontWeight: fontWeight,
        letterSpacing: 0.2,
        color: color ?? AppTheme.textMutedFor(isDark),
      );

  static TextStyle specValue(
    bool isDark, {
    Color? color,
    double fontSize = 11,
    FontWeight fontWeight = FontWeight.w700,
    double height = 1.4,
  }) =>
      GoogleFonts.jetBrainsMono(
        fontSize: fontSize,
        fontWeight: fontWeight,
        height: height,
        color: color ?? AppTheme.textPrimaryFor(isDark),
      );

  static TextStyle counter(
    dynamic isDarkOrColor, {
    double fontSize = 12,
    Color? color,
  }) {
    final resolvedColor = isDarkOrColor is bool
        ? (color ?? (isDarkOrColor ? AppTheme.textPrimary : AppTheme.textPrimaryLight))
        : (isDarkOrColor is Color ? isDarkOrColor : (color ?? AppTheme.textPrimary));
    return GoogleFonts.jetBrainsMono(
      fontSize: fontSize,
      fontWeight: FontWeight.w800,
      color: resolvedColor,
    );
  }

  static TextStyle badge(Color color, {double fontSize = 10}) =>
      GoogleFonts.jetBrainsMono(
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
        color: color,
      );
}

/// Paints a true CSS-equivalent `inset 0 3px 6px, inset 2px 0 4px` inner cavity occlusion shadow
/// inside a rounded rectangle when an element is pushed into its socket.
class _InnerSocketShadowPainter extends CustomPainter {
  final bool isDark;
  final double borderRadius;

  const _InnerSocketShadowPainter({
    required this.isDark,
    required this.borderRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final outerRect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      outerRect,
      Radius.circular(borderRadius),
    );

    canvas.save();
    canvas.clipRRect(rrect);

    // Primary top/left cavity occlusion shadow (inset 1.5px 3px 5px)
    final primaryHole = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(outerRect.inflate(24))
      ..addRRect(rrect.shift(const Offset(1.5, 2.8)));

    final primaryPaint = Paint()
      ..color = isDark ? const Color(0xE0000000) : const Color(0x36000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.8);

    canvas.drawPath(primaryHole, primaryPaint);

    // Crisp inner rim lip shadow (inset 0.5px 1.2px 1.5px)
    final lipHole = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(outerRect.inflate(12))
      ..addRRect(rrect.shift(const Offset(0.8, 1.2)));

    final lipPaint = Paint()
      ..color = isDark ? const Color(0xB8000000) : const Color(0x22000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.0);

    canvas.drawPath(lipHole, lipPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _InnerSocketShadowPainter oldDelegate) {
    return oldDelegate.isDark != isDark ||
        oldDelegate.borderRadius != borderRadius;
  }
}

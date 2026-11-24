import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/epic_spec.dart';
import '../../theme/app_theme.dart';

class UnrealArchitectureToggle extends StatelessWidget {
  final UnrealArchitectureMode mode;
  final bool isDark;
  final ValueChanged<UnrealArchitectureMode>? onChanged;

  const UnrealArchitectureToggle({
    super.key,
    required this.mode,
    required this.isDark,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cyan = AppTheme.accentCyanFor(isDark);
    final border = AppTheme.borderFor(isDark);
    final muted = AppTheme.textMutedFor(isDark);

    Widget buildOption({
      required Key key,
      required UnrealArchitectureMode target,
    }) {
      final selected = mode == target;
      return InkWell(
        key: key,
        onTap: onChanged == null ? null : () => onChanged!(target),
        borderRadius: BorderRadius.circular(AppTheme.radiusXs),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: selected ? cyan.withValues(alpha: 0.16) : Colors.transparent,
            borderRadius: BorderRadius.circular(AppTheme.radiusXs),
            border: selected
                ? Border.all(color: cyan.withValues(alpha: 0.45))
                : null,
          ),
          child: Text(
            target.pillLabel,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 11,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? cyan : muted,
            ),
          ),
        ),
      );
    }

    return Container(
      key: const ValueKey('stage1_architecture_toggle'),
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppTheme.bgSurfaceFor(isDark),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          buildOption(
            key: const ValueKey('stage1_mode_blueprint'),
            target: UnrealArchitectureMode.blueprint,
          ),
          const SizedBox(width: 2),
          buildOption(
            key: const ValueKey('stage1_mode_cpp_hybrid'),
            target: UnrealArchitectureMode.cppHybrid,
          ),
        ],
      ),
    );
  }
}

class Stage1SectionCard extends StatelessWidget {
  final bool isDark;
  final String code;
  final String title;
  final Widget child;
  final Widget? trailing;
  final bool isUpdated;

  const Stage1SectionCard({
    super.key,
    required this.isDark,
    required this.code,
    required this.title,
    required this.child,
    this.trailing,
    this.isUpdated = false,
  });

  @override
  Widget build(BuildContext context) {
    final cyan = AppTheme.accentCyanFor(isDark);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.bgSurfaceRaisedFor(isDark),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(
          color: isUpdated
              ? cyan.withValues(alpha: 0.55)
              : AppTheme.borderFor(isDark),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                code,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: cyan,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: AppTheme.displayFont(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimaryFor(isDark),
                  ),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing!,
              ],
              if (isUpdated)
                Container(
                  key: ValueKey('stage1_updated_badge_$code'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: cyan.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(AppTheme.radiusXs),
                    border: Border.all(color: cyan.withValues(alpha: 0.45)),
                  ),
                  child: Text(
                    'Updated',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: cyan,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class Stage1ContractRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isDark;
  final bool isLast;

  const Stage1ContractRow({
    super.key,
    required this.label,
    required this.value,
    required this.isDark,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: isLast
          ? null
          : BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppTheme.borderFor(isDark)),
              ),
            ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 132,
            child: Text(
              label,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 12,
                color: AppTheme.textMutedFor(isDark),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.textPrimaryFor(isDark),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class Stage1EmptyBlueprintOutline extends StatelessWidget {
  final bool isDark;

  const Stage1EmptyBlueprintOutline({super.key, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppTheme.textPrimaryFor(isDark);
    final textMuted = AppTheme.textMutedFor(isDark);
    final border = AppTheme.borderFor(isDark);
    final cyan = AppTheme.accentCyanFor(isDark);
      const sections = <(String, String, String)>[
        (
          '§01',
          'Core Fantasy & 30s Loop',
          '1-sentence game vision and 4 playable gameplay beats.',
        ),
        (
          '§02',
          'Unreal Engine 5 Scale & Architecture',
          'Camera framing fork (USpringArmComponent / UCameraComponent), player scale, and Enhanced Input actions.',
        ),
        (
          '§03',
          'Core Feel, Design Pillars & Conflict Trade-Offs',
          'Movement feel toggle (Snappy Arcade, Heavy Deliberate, Physics Momentum) and OVER rules.',
        ),
        (
          '§04',
          'Hard Scope Cuts (Do Not Build)',
          'Explicit exclusions keeping v0.1 free of menus, save systems, and networking bloat.',
        ),
        (
          '§05',
          'Seeded Epics & Initial v0.1 Feature Slices',
          'Large-Domain E01–E0N Epics holding playable 30–90 min v0.1 Feature slices.',
        ),
      ];

      return Container(
        key: const ValueKey('stage1_blueprint_empty_outline'),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.bgSurfaceFor(isDark),
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          border: Border.all(color: border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'PROJECT BLUEPRINT PREVIEW · §01–§05',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: textMuted,
              ),
            ),
            const SizedBox(height: 10),
            for (int i = 0; i < sections.length; i++)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: i == sections.length - 1
                    ? null
                    : BoxDecoration(
                        border: Border(bottom: BorderSide(color: border)),
                      ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 38,
                      child: Text(
                        sections[i].$1,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: cyan.withValues(alpha: 0.75),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            sections[i].$2,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            sections[i].$3,
                            style: TextStyle(fontSize: 12, color: textMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
  }
}

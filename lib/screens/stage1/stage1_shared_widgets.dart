import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/unreal_architecture_mode.dart';
import '../../theme/app_theme.dart';

/// Flat segmented text link toggle for Blueprint-First vs C++ & BP Hybrid.
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
    final border = AppTheme.borderFor(isDark);
    final focal = AppTheme.focalAccentFor(isDark);
    final textPrimary = AppTheme.textPrimaryFor(isDark);
    final textMuted = AppTheme.textMutedFor(isDark);
    final isBp = mode == UnrealArchitectureMode.blueprint;

    Widget buildTab({
      required Key key,
      required String label,
      required bool active,
      required UnrealArchitectureMode value,
    }) {
      return InkWell(
        key: key,
        onTap: onChanged == null ? null : () => onChanged!(value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: active ? focal : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              color: active ? textPrimary : textMuted,
            ),
          ),
        ),
      );
    }

    return Container(
      key: const ValueKey('stage1_architecture_toggle'),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: border, width: 1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          buildTab(
            key: const ValueKey('stage1_mode_blueprint'),
            label: 'Blueprint-First',
            active: isBp,
            value: UnrealArchitectureMode.blueprint,
          ),
          const SizedBox(width: 8),
          buildTab(
            key: const ValueKey('stage1_mode_cpp_hybrid'),
            label: 'C++ & BP Hybrid',
            active: !isBp,
            value: UnrealArchitectureMode.cppHybrid,
          ),
        ],
      ),
    );
  }
}

/// Flat plain-document section separated only by a 1px bottom header rule.
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
    final border = AppTheme.borderFor(isDark);
    final textPrimary = AppTheme.textPrimaryFor(isDark);
    final textMuted = AppTheme.textMutedFor(isDark);
    final focal = AppTheme.focalAccentFor(isDark);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: border, width: 1)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  code.startsWith('§') ? code : '§$code',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: textMuted,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title.toUpperCase(),
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.9,
                      color: textMuted,
                    ),
                  ),
                ),
                if (trailing != null) ...[
                  trailing!,
                  if (isUpdated) const SizedBox(width: 10),
                ],
                if (isUpdated)
                  Text(
                    'Updated',
                    key: ValueKey(
                      code.startsWith('§')
                          ? 'stage1_updated_badge_$code'
                          : 'stage1_updated_badge_§$code',
                    ),
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: focal,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          DefaultTextStyle(
            style: TextStyle(fontSize: 13.5, color: textPrimary, height: 1.45),
            child: child,
          ),
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
                bottom: BorderSide(color: AppTheme.borderFor(isDark), width: 1),
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
                fontSize: 11.5,
                color: AppTheme.textMutedFor(isDark),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13.5,
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

/// Compact inline key-value underline input used in Stage 1 §02 Setup editing.
class Stage1ContractEditField extends StatelessWidget {
  final Key fieldKey;
  final String label;
  final String? hintText;
  final TextEditingController controller;
  final Color border;
  final Color focal;
  final Color textPrimary;
  final Color textMuted;

  const Stage1ContractEditField({
    super.key,
    required this.fieldKey,
    required this.label,
    this.hintText,
    required this.controller,
    required this.border,
    required this.focal,
    required this.textPrimary,
    required this.textMuted,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: GoogleFonts.jetBrainsMono(fontSize: 11.5, color: textMuted),
            ),
          ),
          Expanded(
            child: TextField(
              key: fieldKey,
              controller: controller,
              style: TextStyle(fontSize: 13, color: textPrimary),
              decoration: InputDecoration(
                isDense: true,
                hintText: hintText,
                hintStyle: TextStyle(fontSize: 12, color: textMuted),
                contentPadding: const EdgeInsets.symmetric(vertical: 6),
                border: UnderlineInputBorder(
                  borderSide: BorderSide(color: border),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: focal),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

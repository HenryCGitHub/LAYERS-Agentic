part of 'project_pitch_screen.dart';

class _GodotDimensionToggle extends StatelessWidget {
  final GodotProjectDimension dimension;
  final bool isDark;
  final ValueChanged<GodotProjectDimension>? onChanged;

  const _GodotDimensionToggle({
    required this.dimension,
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
      required GodotProjectDimension target,
    }) {
      final selected = dimension == target;
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
      key: const ValueKey('stage1_dimension_toggle'),
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
            key: const ValueKey('stage1_dim_3d'),
            target: GodotProjectDimension.dim3d,
          ),
          const SizedBox(width: 2),
          buildOption(
            key: const ValueKey('stage1_dim_2d'),
            target: GodotProjectDimension.dim2d,
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final bool isDark;
  final String code;
  final String title;
  final Widget child;
  final bool isUpdated;

  const _SectionCard({
    required this.isDark,
    required this.code,
    required this.title,
    required this.child,
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

class _ContractRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isDark;
  final bool isLast;

  const _ContractRow({
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

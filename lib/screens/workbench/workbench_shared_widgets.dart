import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/epic_spec.dart';
import '../../theme/app_theme.dart';

class OutlinerReleasePill extends StatelessWidget {
  final String label;
  final String goal;
  final bool isActive;
  final bool isDark;
  final VoidCallback onTap;

  const OutlinerReleasePill({
    super.key,
    required this.label,
    required this.goal,
    required this.isActive,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final border = AppTheme.borderFor(isDark);
    final cyan = AppTheme.accentCyanFor(isDark);
    final primary = AppTheme.textPrimaryFor(isDark);
    final muted = AppTheme.textMutedFor(isDark);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? cyan.withValues(alpha: 0.1)
              : AppTheme.bgSurfaceFor(isDark),
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          border: Border.all(
            color: isActive ? cyan.withValues(alpha: 0.65) : border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 12,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                      color: primary,
                    ),
                  ),
                ),
                if (isActive)
                  Text(
                    'Active',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: cyan,
                    ),
                  ),
              ],
            ),
            if (goal.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                goal,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: muted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class HeaderPill extends StatelessWidget {
  final String label;
  final Color color;

  const HeaderPill({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppTheme.radiusXs),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: GoogleFonts.jetBrainsMono(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class EpicSectionCard extends StatelessWidget {
  final bool isDark;
  final String code;
  final String title;
  final Widget child;
  final Widget? trailing;

  const EpicSectionCard({
    super.key,
    required this.isDark,
    required this.code,
    required this.title,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.bgSurfaceRaisedFor(isDark),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.borderFor(isDark)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, cardConstraints) {
              final titleStyle = AppTheme.displayFont(
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimaryFor(isDark),
              );
              final codeWidget = Text(
                code,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.accentCyanFor(isDark),
                ),
              );
              if (trailing != null && cardConstraints.maxWidth < 420) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        codeWidget,
                        const SizedBox(width: 8),
                        Expanded(child: Text(title, style: titleStyle)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    trailing!,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  codeWidget,
                  const SizedBox(width: 8),
                  Expanded(child: Text(title, style: titleStyle)),
                  if (trailing != null) ...[
                    const SizedBox(width: 8),
                    trailing!,
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class LiveTuningChip extends StatefulWidget {
  final EpicTuningParam param;
  final bool isDark;
  final bool readOnly;
  final ValueChanged<String> onChanged;
  final Key? inputKey;

  const LiveTuningChip({
    super.key,
    this.inputKey,
    required this.param,
    required this.isDark,
    this.readOnly = false,
    required this.onChanged,
  });

  @override
  State<LiveTuningChip> createState() => LiveTuningChipState();
}

class LiveTuningChipState extends State<LiveTuningChip> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.param.value);
  }

  @override
  void didUpdateWidget(covariant LiveTuningChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.param.value != widget.param.value &&
        _controller.text.trim() != widget.param.value.trim()) {
      _controller.value = TextEditingValue(
        text: widget.param.value,
        selection: TextSelection.collapsed(offset: widget.param.value.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final border = AppTheme.borderFor(widget.isDark);
    final cyan = AppTheme.accentCyanFor(widget.isDark);
    final muted = AppTheme.textMutedFor(widget.isDark);
    final primary = AppTheme.textPrimaryFor(widget.isDark);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppTheme.bgSurfaceFor(widget.isDark),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${widget.param.key}:',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: primary,
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 56,
            child: TextField(
              key: widget.inputKey,
              controller: _controller,
              readOnly: widget.readOnly,
              textAlign: TextAlign.right,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: widget.readOnly ? muted : cyan,
              ),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              ),
              onChanged: widget.readOnly ? null : widget.onChanged,
            ),
          ),
          if (widget.param.unit.isNotEmpty) ...[
            const SizedBox(width: 4),
            Text(
              widget.param.unit,
              style: GoogleFonts.jetBrainsMono(fontSize: 11, color: muted),
            ),
          ],
        ],
      ),
    );
  }
}

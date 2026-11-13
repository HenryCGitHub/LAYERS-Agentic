import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/task_how_to_blueprint.dart';

/// Parsed row from a structured Godot 4 Markdown Inspector / Input Map / Scene Placement pipe table.
class _GodotInspectorRow {
  const _GodotInspectorRow({
    required this.rowIndex,
    required this.target,
    required this.category,
    required this.propertyName,
    required this.value,
    required this.isTransformValue,
  });

  final int rowIndex;
  final String target;
  final String category;
  final String propertyName;
  final String value;
  final bool isTransformValue;
}

/// Renders a native Godot 4 `Scene Tree` + categorized `Inspector` panel
/// with RGB `X`/`Y`/`Z` Vector2/Vector3 axis boxes, Godot boolean toggles,
/// Input Map rows, and one-click `Copy Vector` / `⧉` pills.
class GodotInspectorPanel extends StatefulWidget {
  const GodotInspectorPanel({
    super.key,
    required this.tableLines,
    required this.isDark,
    this.stepPath = '',
    this.assetName = '',
    this.parentClassLabel = '',
    this.isLevelScene = false,
    this.isInputMap = false,
    this.highlightedTokens = const {},
  });

  final List<String> tableLines;
  final bool isDark;
  final String stepPath;
  final String assetName;
  final String parentClassLabel;
  final bool isLevelScene;
  final bool isInputMap;
  final Set<String> highlightedTokens;

  @override
  State<GodotInspectorPanel> createState() => _GodotInspectorPanelState();
}

class _GodotInspectorPanelState extends State<GodotInspectorPanel> {
  String? _selectedTarget;

  @override
  Widget build(BuildContext context) {
    final parsed = _parseTable();
    if (parsed.isEmpty) return const SizedBox.shrink();

    final uniqueTargets = <String>[];
    for (final r in parsed) {
      if (r.target.isNotEmpty && !uniqueTargets.contains(r.target)) {
        uniqueTargets.add(r.target);
      }
    }
    final activeTarget = (_selectedTarget != null &&
            uniqueTargets.contains(_selectedTarget))
        ? _selectedTarget!
        : (uniqueTargets.isNotEmpty ? uniqueTargets.first : '');

    final categories = <String, List<_GodotInspectorRow>>{};
    for (final row in parsed) {
      categories.putIfAbsent(row.category, () => []).add(row);
    }

    final borderCol = widget.isDark
        ? const Color(0xFF233044)
        : Colors.black.withValues(alpha: 0.14);
    final panelBg =
        widget.isDark ? const Color(0xFF090D14) : const Color(0xFFF8FAFC);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompactWidth =
            constraints.maxWidth.isFinite && constraints.maxWidth < 420;
        return Container(
          key: const ValueKey('level_placement_table'),
          decoration: BoxDecoration(
            color: panelBg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderCol),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!widget.isInputMap)
                _buildSceneTreeDock(
                  targets: uniqueTargets,
                  activeTarget: activeTarget,
                  borderCol: borderCol,
                ),
              _buildInspectorHeader(activeTarget, borderCol),
              for (final entry in categories.entries)
                _buildCategorySection(
                  categoryName: entry.key,
                  rows: entry.value,
                  multiTarget: uniqueTargets.length > 1,
                  activeTarget: activeTarget,
                  borderCol: borderCol,
                  isCompactWidth: isCompactWidth,
                ),
            ],
          ),
        );
      },
    );
  }

  List<_GodotInspectorRow> _parseTable() {
    final rawRows = <List<String>>[];
    for (final line in widget.tableLines) {
      final trimmed = line.trim();
      if (!trimmed.startsWith('|') || !trimmed.endsWith('|')) continue;
      final cells = trimmed
          .substring(1, trimmed.length - 1)
          .split('|')
          .map((c) => c.trim())
          .toList();
      final isSeparator = cells.every(
        (c) => RegExp(r'^:?-{2,}:?$').hasMatch(c),
      );
      if (!isSeparator && cells.isNotEmpty) {
        rawRows.add(cells);
      }
    }
    if (rawRows.length < 2) return const [];

    final result = <_GodotInspectorRow>[];
    for (int r = 1; r < rawRows.length; r++) {
      final cells = rawRows[r];
      final String target;
      final String rawProp;
      final String value;

      if (cells.length == 1) {
        target = _resolveRootLabel();
        rawProp = 'Property';
        value = cells[0];
      } else if (cells.length == 2) {
        target = _resolveDefaultTargetFromPath();
        rawProp = cells[0];
        value = cells[1];
      } else {
        target = cells[0].isNotEmpty ? cells[0] : _resolveDefaultTargetFromPath();
        rawProp = cells[1];
        value = cells.sublist(2).join(' | ').trim();
      }

      final splitProp = _splitCategoryAndProperty(rawProp);
      final isTransform = value.contains('Vector') ||
          value.contains('(') ||
          value.contains('X=') ||
          RegExp(r'-?\d+(?:\.\d+)?\s*,\s*-?\d+').hasMatch(value);

      result.add(
        _GodotInspectorRow(
          rowIndex: r,
          target: target,
          category: splitProp.$1,
          propertyName: splitProp.$2,
          value: value,
          isTransformValue: isTransform,
        ),
      );
    }
    return result;
  }

  (String, String) _splitCategoryAndProperty(String rawProp) {
    final idx = rawProp.indexOf('>');
    if (idx > 0 && idx < rawProp.length - 1) {
      return (
        rawProp.substring(0, idx).trim(),
        rawProp.substring(idx + 1).trim(),
      );
    }
    return (_inferCategory(rawProp), rawProp);
  }

  String _inferCategory(String prop) {
    final lower = prop.toLowerCase();
    if (lower.contains('position') ||
        lower.contains('rotation') ||
        lower.contains('scale') ||
        lower.contains('size') ||
        lower.contains('transform')) {
      return 'Transform';
    }
    if (lower.contains('motion mode') ||
        lower.contains('speed') ||
        lower.contains('jump') ||
        lower.contains('gravity') ||
        lower.contains('floor') ||
        lower.contains('velocity')) {
      return 'CharacterBody';
    }
    if (lower.contains('camera') ||
        lower.contains('fov') ||
        lower.contains('zoom') ||
        lower.contains('spring')) {
      return 'Camera';
    }
    if (lower.contains('collision') ||
        lower.contains('layer') ||
        lower.contains('mask') ||
        lower.contains('shape') ||
        lower.contains('radius') ||
        lower.contains('height')) {
      return 'CollisionObject';
    }
    if (widget.isInputMap ||
        lower.contains('input') ||
        lower.contains('action') ||
        lower.contains('key') ||
        lower.contains('deadzone')) {
      return 'Input Map';
    }
    return 'Inspector';
  }

  String _resolveRootLabel() {
    if (widget.isLevelScene) {
      return widget.assetName.trim().isNotEmpty
          ? widget.assetName.trim()
          : 'MainLevel (.tscn)';
    }
    final pathMatch = RegExp(r'\b([A-Za-z0-9_]+\.(?:tscn|gd))\b')
        .firstMatch(widget.stepPath);
    if (pathMatch != null) return pathMatch.group(1)!;
    if (widget.assetName.trim().isNotEmpty) {
      return widget.assetName.trim();
    }
    return 'Scene Root';
  }

  String _resolveDefaultTargetFromPath() {
    final segs = widget.stepPath
        .split(RegExp(r'[→>]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (segs.isNotEmpty) return segs.last;
    return _resolveRootLabel();
  }

  Widget _buildSceneTreeDock({
    required List<String> targets,
    required String activeTarget,
    required Color borderCol,
  }) {
    final rootLabel = _resolveRootLabel();
    final headerTitle =
        widget.isLevelScene ? 'Scene Tree (Level)' : 'Scene Tree';
    final isCharacter = widget.parentClassLabel
            .toLowerCase()
            .contains('characterbody') ||
        targets.any(
          (t) =>
              t.toLowerCase().contains('characterbody') ||
              t.toLowerCase().contains('camera'),
        );
    final bool showRootCollisionShape = !widget.isLevelScene &&
        isCharacter &&
        !targets.any((t) => t.toLowerCase().contains('collision'));

    final barBg =
        widget.isDark ? const Color(0xFF0E141F) : const Color(0xFFE2E8F0);
    final mutedText =
        widget.isDark ? const Color(0xFF64748B) : const Color(0xFF475569);

    return Container(
      decoration: BoxDecoration(
        color:
            widget.isDark ? const Color(0xFF0B1018) : const Color(0xFFF1F5F9),
        border: Border(bottom: BorderSide(color: borderCol)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: barBg,
              border: Border(bottom: BorderSide(color: borderCol)),
            ),
            child: Row(
              children: [
                Text(
                  '▾ $headerTitle',
                  style: GoogleFonts.inter(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                    color: widget.isDark
                        ? const Color(0xFFCBD5E1)
                        : const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(width: 8),
                if (!widget.isLevelScene)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1.5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2563EB).withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(
                        color: const Color(0xFF3B82F6).withValues(alpha: 0.45),
                      ),
                    ),
                    child: Text(
                      '+ Add Node',
                      style: GoogleFonts.inter(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF60A5FA),
                      ),
                    ),
                  ),
                const Spacer(),
                Text(
                  'Node Type',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 9.5,
                    color: mutedText,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildTreeRow(
                  icon: widget.isLevelScene ? '🗺' : '🎬',
                  label: rootLabel,
                  typeLabel: widget.parentClassLabel.isNotEmpty
                      ? widget.parentClassLabel.replaceFirst(
                          RegExp(r'^Root Node:\s*'),
                          '',
                        )
                      : (widget.isLevelScene ? 'Node3D' : 'Node'),
                  indentLevel: 0,
                  isSelected: false,
                  isAttachedScript: !widget.isLevelScene,
                  connector: '',
                ),
                if (showRootCollisionShape)
                  _buildTreeRow(
                    icon: '⬭',
                    label: 'CollisionShape',
                    typeLabel: 'CollisionShape',
                    indentLevel: 1,
                    isSelected: false,
                    isAttachedScript: false,
                    connector: '├─',
                  ),
                for (int i = 0; i < targets.length; i++)
                  _buildTreeRow(
                    icon: _inferNodeIcon(
                      targets[i],
                      isLevel: widget.isLevelScene,
                    ),
                    label: targets[i],
                    typeLabel: _inferNodeType(
                      targets[i],
                      isLevel: widget.isLevelScene,
                    ),
                    indentLevel: 1,
                    isSelected: targets[i] == activeTarget,
                    isAttachedScript: false,
                    connector: i == targets.length - 1 ? '└─' : '├─',
                    onTap: () => setState(() => _selectedTarget = targets[i]),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTreeRow({
    required String icon,
    required String label,
    required String typeLabel,
    required int indentLevel,
    required bool isSelected,
    required bool isAttachedScript,
    required String connector,
    VoidCallback? onTap,
  }) {
    final rowWidget = Container(
      margin: const EdgeInsets.only(bottom: 1.5),
      padding: EdgeInsets.fromLTRB(
        6 + (indentLevel * 14).toDouble(),
        3.5,
        8,
        3.5,
      ),
      decoration: BoxDecoration(
        color: isSelected
            ? const Color(0xFF1D4ED8).withValues(alpha: 0.28)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        border: isSelected
            ? Border.all(
                color: const Color(0xFF38BDF8).withValues(alpha: 0.45),
              )
            : null,
      ),
      child: Row(
        children: [
          if (connector.isNotEmpty) ...[
            Text(
              connector,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 10,
                color: const Color(0xFF475569),
              ),
            ),
            const SizedBox(width: 4),
          ],
          Text(icon, style: const TextStyle(fontSize: 10.5)),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? const Color(0xFFE0F2FE)
                    : (widget.isDark
                        ? const Color(0xFFCBD5E1)
                        : const Color(0xFF1E293B)),
              ),
            ),
          ),
          if (isAttachedScript) ...[
            const SizedBox(width: 4),
            Text(
              '📜',
              style: const TextStyle(fontSize: 10),
            ),
          ],
          const SizedBox(width: 6),
          Text(
            typeLabel,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 9.5,
              color: isSelected
                  ? const Color(0xFF7DD3FC)
                  : const Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return rowWidget;
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: onTap,
      child: rowWidget,
    );
  }

  Widget _buildInspectorHeader(String activeTarget, Color borderCol) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: widget.isDark
            ? const Color(0xFF101724)
            : const Color(0xFFE2E8F0),
        border: Border(bottom: BorderSide(color: borderCol)),
      ),
      child: Row(
        children: [
          Text(
            widget.isInputMap ? '⌨ INPUT MAP' : '🎛 INSPECTOR',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: const Color(0xFF38BDF8),
            ),
          ),
          const Spacer(),
          if (activeTarget.isNotEmpty)
            Flexible(
              child: Text(
                activeTarget,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: widget.isDark
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFF475569),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCategorySection({
    required String categoryName,
    required List<_GodotInspectorRow> rows,
    required bool multiTarget,
    required String activeTarget,
    required Color borderCol,
    required bool isCompactWidth,
  }) {
    final categoryBg =
        widget.isDark ? const Color(0xFF141C2B) : const Color(0xFFEDF2F7);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
          decoration: BoxDecoration(
            color: categoryBg,
            border: Border(
              bottom: BorderSide(color: borderCol.withValues(alpha: 0.7)),
            ),
          ),
          child: Text(
            '▾ $categoryName',
            style: GoogleFonts.inter(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: widget.isDark
                  ? const Color(0xFF93C5FD)
                  : const Color(0xFF1E3A8A),
            ),
          ),
        ),
        for (int i = 0; i < rows.length; i++)
          _buildPropertyRow(
            rows[i],
            multiTarget: multiTarget,
            isFocusedTarget: rows[i].target == activeTarget,
            showBottomBorder: i < rows.length - 1,
            borderCol: borderCol,
            isCompactWidth: isCompactWidth,
          ),
      ],
    );
  }

  Widget _buildPropertyRow(
    _GodotInspectorRow row, {
    required bool multiTarget,
    required bool isFocusedTarget,
    required bool showBottomBorder,
    required Color borderCol,
    required bool isCompactWidth,
  }) {
    final isTokenHighlighted = TaskHowToBlueprint.matchesHighlightTokens(
      widget.highlightedTokens,
      '${row.target} ${row.propertyName} ${row.value}',
    );
    return Container(
      key: ValueKey(
        'godot_prop_row_${row.rowIndex}_${isTokenHighlighted ? 'glow' : 'idle'}',
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: isTokenHighlighted
            ? const Color(0xFF0EA5E9).withValues(alpha: 0.16)
            : (isFocusedTarget && multiTarget
                ? const Color(0xFF1E3A5F).withValues(alpha: 0.14)
                : Colors.transparent),
        border: Border(
          left: isTokenHighlighted
              ? const BorderSide(color: Color(0xFF38BDF8), width: 2.5)
              : BorderSide.none,
          bottom: showBottomBorder
              ? BorderSide(color: borderCol.withValues(alpha: 0.55))
              : BorderSide.none,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 42,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (multiTarget && row.target.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF38BDF8).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        row.target,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF7DD3FC),
                        ),
                      ),
                    ),
                  ),
                Text(
                  row.propertyName,
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: widget.isDark
                        ? const Color(0xFFCBD5E1)
                        : const Color(0xFF1E293B),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 58,
            child: _buildValueControl(row, isCompactWidth: isCompactWidth),
          ),
        ],
      ),
    );
  }

  Widget _buildValueControl(
    _GodotInspectorRow row, {
    required bool isCompactWidth,
  }) {
    final xyz = _extractXyz(row.value);
    final xy = xyz == null ? _extractXy(row.value) : null;
    final copyButton = row.isTransformValue
        ? Builder(
            builder: (context) => Tooltip(
              message: 'Copy Godot Transform',
              child: InkWell(
                key: ValueKey('copy_transform_btn_${row.rowIndex}'),
                borderRadius: BorderRadius.circular(4),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: row.value));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Copied Transform: ${row.value}'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: isCompactWidth ? 5 : 6,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: const Color(0xFF10B981).withValues(alpha: 0.35),
                    ),
                  ),
                  child: Text(
                    isCompactWidth ? '⧉' : '⧉ Copy Vector',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF6EE7B7),
                    ),
                  ),
                ),
              ),
            ),
          )
        : null;

    if (xyz != null) {
      return Wrap(
        spacing: 5,
        runSpacing: 5,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _buildAxisBox('X', xyz.$1, const Color(0xFFEF4444)),
          _buildAxisBox('Y', xyz.$2, const Color(0xFF22C55E)),
          _buildAxisBox('Z', xyz.$3, const Color(0xFF3B82F6)),
          if (copyButton != null) copyButton,
        ],
      );
    }

    if (xy != null) {
      return Wrap(
        spacing: 5,
        runSpacing: 5,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _buildAxisBox('X', xy.$1, const Color(0xFFEF4444)),
          _buildAxisBox('Y', xy.$2, const Color(0xFF22C55E)),
          if (copyButton != null) copyButton,
        ],
      );
    }

    final lowerVal = row.value.toLowerCase().trim();
    if (lowerVal == 'true' ||
        lowerVal == 'false' ||
        lowerVal == 'checked' ||
        lowerVal == 'unchecked' ||
        lowerVal == 'on' ||
        lowerVal == 'off' ||
        lowerVal == 'enabled' ||
        lowerVal == 'disabled') {
      final isTrue = lowerVal == 'true' ||
          lowerVal == 'checked' ||
          lowerVal == 'on' ||
          lowerVal == 'enabled';
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 15,
            height: 15,
            decoration: BoxDecoration(
              color: isTrue
                  ? const Color(0xFF2563EB)
                  : (widget.isDark
                      ? const Color(0xFF06090F)
                      : const Color(0xFFE2E8F0)),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(
                color: isTrue
                    ? const Color(0xFF60A5FA)
                    : const Color(0xFF334155),
              ),
            ),
            child: isTrue
                ? const Icon(Icons.check, size: 11, color: Colors.white)
                : null,
          ),
          const SizedBox(width: 6),
          Text(
            row.value,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isTrue
                  ? const Color(0xFF93C5FD)
                  : const Color(0xFF94A3B8),
            ),
          ),
        ],
      );
    }

    return Wrap(
      spacing: 6,
      runSpacing: 5,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
          decoration: BoxDecoration(
            color: widget.isDark
                ? const Color(0xFF06090F)
                : const Color(0xFFFFFFFF),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: widget.isDark
                  ? const Color(0xFF1E293B)
                  : const Color(0xFFCBD5E1),
            ),
          ),
          child: Text(
            row.value,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: widget.isDark
                  ? const Color(0xFFE2E8F0)
                  : const Color(0xFF0F172A),
            ),
          ),
        ),
        if (copyButton != null) copyButton,
      ],
    );
  }

  Widget _buildAxisBox(String axis, String val, Color accentColor) {
    return Container(
      decoration: BoxDecoration(
        color:
            widget.isDark ? const Color(0xFF06090F) : const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: widget.isDark
              ? const Color(0xFF1E293B)
              : const Color(0xFFCBD5E1),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 3, color: accentColor),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    axis,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: accentColor,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    val,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: widget.isDark
                          ? const Color(0xFFE2E8F0)
                          : const Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  (String, String, String)? _extractXyz(String raw) {
    final labeled = RegExp(
      r'X\s*[:=]\s*(-?\d+(?:\.\d+)?)\s*[, ]\s*Y\s*[:=]\s*(-?\d+(?:\.\d+)?)\s*[, ]\s*Z\s*[:=]\s*(-?\d+(?:\.\d+)?)',
      caseSensitive: false,
    ).firstMatch(raw);
    if (labeled != null) {
      return (labeled.group(1)!, labeled.group(2)!, labeled.group(3)!);
    }
    final tuple = RegExp(
      r'^(?:Vector3)?\(\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*\)$',
    ).firstMatch(raw.trim());
    if (tuple != null) {
      return (tuple.group(1)!, tuple.group(2)!, tuple.group(3)!);
    }
    return null;
  }

  (String, String)? _extractXy(String raw) {
    final labeled = RegExp(
      r'X\s*[:=]\s*(-?\d+(?:\.\d+)?)\s*[, ]\s*Y\s*[:=]\s*(-?\d+(?:\.\d+)?)',
      caseSensitive: false,
    ).firstMatch(raw);
    if (labeled != null && !raw.toLowerCase().contains('z')) {
      return (labeled.group(1)!, labeled.group(2)!);
    }
    final tuple = RegExp(
      r'^(?:Vector2)?\(\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*\)$',
    ).firstMatch(raw.trim());
    if (tuple != null) {
      return (tuple.group(1)!, tuple.group(2)!);
    }
    return null;
  }

  String _inferNodeIcon(String target, {required bool isLevel}) {
    final lower = target.toLowerCase();
    if (isLevel) {
      if (lower.contains('spawn') || lower.contains('marker')) return '🚩';
      if (lower.contains('light')) return '☀';
      return '🧊';
    }
    if (lower.contains('camera')) return '🎥';
    if (lower.contains('characterbody')) return '🏃';
    if (lower.contains('mesh') || lower.contains('sprite')) return '🧱';
    if (lower.contains('collision')) return '⬭';
    if (lower.contains('timer')) return '⏱';
    if (lower.contains('area')) return '🎯';
    if (lower.contains('audio') || lower.contains('sound')) return '🔊';
    return '🧩';
  }

  String _inferNodeType(String target, {required bool isLevel}) {
    final parenMatch = RegExp(r'\(([^)]+)\)\s*$').firstMatch(target);
    if (parenMatch != null) return parenMatch.group(1)!.trim();
    final lower = target.toLowerCase();
    if (isLevel) {
      if (lower.contains('spawn') || lower.contains('marker')) {
        return lower.contains('2d') ? 'Marker2D' : 'Marker3D';
      }
      if (lower.contains('light')) return 'DirectionalLight3D';
      return 'StaticBody3D';
    }
    if (lower.contains('camera2d')) return 'Camera2D';
    if (lower.contains('camera')) return 'Camera3D';
    if (lower.contains('characterbody2d')) return 'CharacterBody2D';
    if (lower.contains('characterbody')) return 'CharacterBody3D';
    if (lower.contains('collisionshape2d')) return 'CollisionShape2D';
    if (lower.contains('collision')) return 'CollisionShape3D';
    if (lower.contains('timer')) return 'Timer';
    if (lower.contains('area2d')) return 'Area2D';
    if (lower.contains('area')) return 'Area3D';
    if (lower.contains('sprite')) return 'Sprite2D';
    if (lower.contains('mesh')) return 'MeshInstance3D';
    if (lower.contains('ray')) return 'RayCast3D';
    if (lower.contains('audio')) return 'AudioStreamPlayer';
    return 'Node';
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/godot_project_contract.dart';
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

/// Renders a categorized Godot 4 `Property & Layer Sheet` panel
/// with RGB `X`/`Y`/`Z` Vector2/Vector3 axis boxes, Physics Layer toggles,
/// boolean checkboxes, Input Map rows, and one-click `Copy Vector` / `⧉` pills.
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
    this.contract,
    this.onPropertyChanged,
  });

  final List<String> tableLines;
  final bool isDark;
  final String stepPath;
  final String assetName;
  final String parentClassLabel;
  final bool isLevelScene;
  final bool isInputMap;
  final Set<String> highlightedTokens;
  final GodotProjectContract? contract;
  final void Function(String propertyKey, String newValue)? onPropertyChanged;

  @override
  State<GodotInspectorPanel> createState() => _GodotInspectorPanelState();
}

class _GodotInspectorPanelState extends State<GodotInspectorPanel> {
  String? _activeEditKey;
  final TextEditingController _inlineEditCtrl = TextEditingController();
  final FocusNode _inlineFocusNode = FocusNode();
  VoidCallback? _onActiveBlurCommit;
  bool _isFinishingInlineEdit = false;
  final Map<String, String> _localEditedValues = {};

  @override
  void initState() {
    super.initState();
    _inlineFocusNode.addListener(_handleInlineFocusChange);
    _inlineFocusNode.onKeyEvent = (node, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.escape &&
          _activeEditKey != null) {
        _cancelInlineEdit();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };
  }

  @override
  void didUpdateWidget(covariant GodotInspectorPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tableLines != widget.tableLines) {
      _localEditedValues.clear();
      _activeEditKey = null;
      _onActiveBlurCommit = null;
      _isFinishingInlineEdit = false;
    }
  }

  @override
  void dispose() {
    _inlineFocusNode.removeListener(_handleInlineFocusChange);
    _inlineFocusNode.dispose();
    _inlineEditCtrl.dispose();
    super.dispose();
  }

  void _handleInlineFocusChange() {
    if (!_inlineFocusNode.hasFocus &&
        _activeEditKey != null &&
        !_isFinishingInlineEdit &&
        mounted) {
      final blurCommit = _onActiveBlurCommit;
      _onActiveBlurCommit = null;
      blurCommit?.call();
    }
  }

  void _cancelInlineEdit() {
    _isFinishingInlineEdit = true;
    _onActiveBlurCommit = null;
    setState(() {
      _activeEditKey = null;
    });
    _isFinishingInlineEdit = false;
  }

  String _rowOverrideKey(_GodotInspectorRow row) =>
      row.target.isNotEmpty ? '${row.target}.${row.propertyName}' : row.propertyName;

  void _startInlineEdit(
    String editKey,
    String initialValue, {
    VoidCallback? onBlurCommit,
  }) {
    if (_activeEditKey != null &&
        _activeEditKey != editKey &&
        !_isFinishingInlineEdit) {
      final prevCommit = _onActiveBlurCommit;
      _onActiveBlurCommit = null;
      prevCommit?.call();
    }
    _isFinishingInlineEdit = false;
    _onActiveBlurCommit = onBlurCommit;
    setState(() {
      _activeEditKey = editKey;
      _inlineEditCtrl.text = initialValue;
      _inlineEditCtrl.selection = TextSelection(
        baseOffset: 0,
        extentOffset: initialValue.length,
      );
    });
  }

  void _commitPropertyEdit(_GodotInspectorRow row, String nextValue) {
    _isFinishingInlineEdit = true;
    _onActiveBlurCommit = null;
    final trimmed = nextValue.trim();
    if (trimmed.isEmpty) {
      setState(() => _activeEditKey = null);
      _isFinishingInlineEdit = false;
      return;
    }
    setState(() {
      _localEditedValues[_rowOverrideKey(row)] = trimmed;
      _activeEditKey = null;
    });
    _isFinishingInlineEdit = false;
    widget.onPropertyChanged?.call(row.propertyName, trimmed);
  }

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
    final activeTarget = uniqueTargets.isNotEmpty ? uniqueTargets.first : '';

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
            widget.isInputMap ? '⌨ INPUT MAP' : '🎛 PROPERTY & LAYER SHEET',
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
    final effectiveValue = _localEditedValues[_rowOverrideKey(row)] ?? row.value;
    final canEdit = widget.onPropertyChanged != null;
    final xyz = _extractXyz(effectiveValue);
    final xy = xyz == null ? _extractXy(effectiveValue) : null;
    final copyButton = row.isTransformValue
        ? Builder(
            builder: (context) => Tooltip(
              message: 'Copy Godot Transform',
              child: InkWell(
                key: ValueKey('copy_transform_btn_${row.rowIndex}'),
                borderRadius: BorderRadius.circular(4),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: effectiveValue));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Copied Transform: $effectiveValue'),
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
          _buildAxisBox(
            row: row,
            axis: 'X',
            val: xyz.$1,
            accentColor: const Color(0xFFEF4444),
            canEdit: canEdit,
            onCommitAxis: (next) => _commitPropertyEdit(
              row,
              'Vector3($next, ${xyz.$2}, ${xyz.$3})',
            ),
          ),
          _buildAxisBox(
            row: row,
            axis: 'Y',
            val: xyz.$2,
            accentColor: const Color(0xFF22C55E),
            canEdit: canEdit,
            onCommitAxis: (next) => _commitPropertyEdit(
              row,
              'Vector3(${xyz.$1}, $next, ${xyz.$3})',
            ),
          ),
          _buildAxisBox(
            row: row,
            axis: 'Z',
            val: xyz.$3,
            accentColor: const Color(0xFF3B82F6),
            canEdit: canEdit,
            onCommitAxis: (next) => _commitPropertyEdit(
              row,
              'Vector3(${xyz.$1}, ${xyz.$2}, $next)',
            ),
          ),
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
          _buildAxisBox(
            row: row,
            axis: 'X',
            val: xy.$1,
            accentColor: const Color(0xFFEF4444),
            canEdit: canEdit,
            onCommitAxis: (next) => _commitPropertyEdit(
              row,
              'Vector2($next, ${xy.$2})',
            ),
          ),
          _buildAxisBox(
            row: row,
            axis: 'Y',
            val: xy.$2,
            accentColor: const Color(0xFF22C55E),
            canEdit: canEdit,
            onCommitAxis: (next) => _commitPropertyEdit(
              row,
              'Vector2(${xy.$1}, $next)',
            ),
          ),
          if (copyButton != null) copyButton,
        ],
      );
    }

    // Physics Layer / Mask bitmask toggles backed by the Project Contract
    final contract = widget.contract;
    final lowerProp = row.propertyName.toLowerCase();
    final isLayerOrMaskProp = lowerProp.contains('collision layer') ||
        lowerProp.contains('collision mask') ||
        lowerProp == 'layer' ||
        lowerProp == 'mask';
    final parsedMask = int.tryParse(effectiveValue.trim());
    if (isLayerOrMaskProp &&
        contract != null &&
        contract.physicsLayers.isNotEmpty &&
        parsedMask != null) {
      final sortedLayers = contract.physicsLayers.keys.toList()..sort();
      return Wrap(
        spacing: 5,
        runSpacing: 5,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final layerNum in sortedLayers)
            () {
              final bitActive = (parsedMask & (1 << (layerNum - 1))) != 0;
              final label = 'L$layerNum:${contract.physicsLayers[layerNum]}';
              return InkWell(
                key: ValueKey('inspector_layer_${row.rowIndex}_$layerNum'),
                borderRadius: BorderRadius.circular(4),
                onTap: canEdit
                    ? () {
                        final nextMask = parsedMask ^ (1 << (layerNum - 1));
                        _commitPropertyEdit(row, nextMask.toString());
                      }
                    : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: bitActive
                        ? const Color(0xFF2563EB).withValues(alpha: 0.28)
                        : (widget.isDark
                            ? const Color(0xFF06090F)
                            : const Color(0xFFF1F5F9)),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: bitActive
                          ? const Color(0xFF60A5FA)
                          : (widget.isDark
                              ? const Color(0xFF1E293B)
                              : const Color(0xFFCBD5E1)),
                    ),
                  ),
                  child: Text(
                    label,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: bitActive
                          ? const Color(0xFF93C5FD)
                          : const Color(0xFF94A3B8),
                    ),
                  ),
                ),
              );
            }(),
          Text(
            '($parsedMask)',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              color: const Color(0xFF64748B),
            ),
          ),
        ],
      );
    }

    final lowerVal = effectiveValue.toLowerCase().trim();
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
      final nextVal = (lowerVal == 'on' || lowerVal == 'off')
          ? (isTrue ? 'Off' : 'On')
          : (lowerVal == 'enabled' || lowerVal == 'disabled')
              ? (isTrue ? 'disabled' : 'enabled')
              : (isTrue ? 'false' : 'true');
      return InkWell(
        key: ValueKey('inspector_bool_${row.rowIndex}'),
        borderRadius: BorderRadius.circular(4),
        onTap: canEdit ? () => _commitPropertyEdit(row, nextVal) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
          child: Row(
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
                effectiveValue,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isTrue
                      ? const Color(0xFF93C5FD)
                      : const Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final scalarEditKey = 'scalar_${row.rowIndex}';
    if (_activeEditKey == scalarEditKey && canEdit) {
      return SizedBox(
        width: 150,
        child: TextField(
          key: ValueKey('inspector_scalar_input_${row.rowIndex}'),
          controller: _inlineEditCtrl,
          focusNode: _inlineFocusNode,
          autofocus: true,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: widget.isDark
                ? const Color(0xFFE2E8F0)
                : const Color(0xFF0F172A),
          ),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
            suffixIcon: IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              icon: const Icon(Icons.check_rounded, size: 14),
              onPressed: () => _commitPropertyEdit(row, _inlineEditCtrl.text),
            ),
          ),
          onSubmitted: (val) => _commitPropertyEdit(row, val),
        ),
      );
    }

    return Wrap(
      spacing: 6,
      runSpacing: 5,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        InkWell(
          key: ValueKey('inspector_scalar_${row.rowIndex}'),
          borderRadius: BorderRadius.circular(4),
          onTap: canEdit
              ? () => _startInlineEdit(
                    scalarEditKey,
                    effectiveValue,
                    onBlurCommit: () =>
                        _commitPropertyEdit(row, _inlineEditCtrl.text),
                  )
              : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
            decoration: BoxDecoration(
              color: widget.isDark
                  ? const Color(0xFF06090F)
                  : const Color(0xFFFFFFFF),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: canEdit
                    ? const Color(0xFF283854)
                    : (widget.isDark
                        ? const Color(0xFF1E293B)
                        : const Color(0xFFCBD5E1)),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  effectiveValue,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: widget.isDark
                        ? const Color(0xFFE2E8F0)
                        : const Color(0xFF0F172A),
                  ),
                ),
                if (canEdit) ...[
                  const SizedBox(width: 5),
                  const Icon(Icons.edit_outlined, size: 10, color: Color(0xFF64748B)),
                ],
              ],
            ),
          ),
        ),
        if (copyButton != null) copyButton,
      ],
    );
  }

  Widget _buildAxisBox({
    required _GodotInspectorRow row,
    required String axis,
    required String val,
    required Color accentColor,
    required bool canEdit,
    required ValueChanged<String> onCommitAxis,
  }) {
    final axisEditKey = 'axis_${row.rowIndex}_$axis';
    final isEditingAxis = _activeEditKey == axisEditKey && canEdit;

    return InkWell(
      key: ValueKey('inspector_axis_${row.rowIndex}_$axis'),
      borderRadius: BorderRadius.circular(4),
      onTap: (canEdit && !isEditingAxis)
          ? () => _startInlineEdit(
                axisEditKey,
                val,
                onBlurCommit: () {
                  final next = _inlineEditCtrl.text.trim();
                  if (next.isEmpty) {
                    _cancelInlineEdit();
                  } else {
                    onCommitAxis(next);
                  }
                },
              )
          : null,
      child: Container(
        decoration: BoxDecoration(
          color: widget.isDark ? const Color(0xFF06090F) : const Color(0xFFFFFFFF),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isEditingAxis
                ? accentColor
                : (widget.isDark
                    ? const Color(0xFF1E293B)
                    : const Color(0xFFCBD5E1)),
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
                    if (isEditingAxis)
                      SizedBox(
                        width: 44,
                        child: TextField(
                          key: ValueKey('inspector_axis_input_${row.rowIndex}_$axis'),
                          controller: _inlineEditCtrl,
                          focusNode: _inlineFocusNode,
                          autofocus: true,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: widget.isDark
                                ? const Color(0xFFE2E8F0)
                                : const Color(0xFF0F172A),
                          ),
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(vertical: 2),
                            border: InputBorder.none,
                          ),
                          onSubmitted: (next) {
                            final trimmed = next.trim();
                            if (trimmed.isEmpty) {
                              _cancelInlineEdit();
                            } else {
                              onCommitAxis(trimmed);
                            }
                          },
                        ),
                      )
                    else
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
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../agents/project_concept_agent.dart';
import '../models/agent_blueprints.dart';
import '../constants/text_style_guide.dart';
import '../providers/workbench_provider.dart';
import '../theme/app_theme.dart';

part 'pitch_spark_and_outliner_part.dart';
part 'pitch_section_workspace_part.dart';
part 'pitch_full_review_part.dart';

final RegExp _overSplitRegex = RegExp(
  r'\s+over\s+',
  caseSensitive: false,
);
final RegExp _prioritizePrefixRegex = RegExp(
  r'^(?:Prioritize|Prefer|Favor|Choose|Focus\s+on)\s+',
  caseSensitive: false,
);
final RegExp _versionSuffixNoiseRegex = RegExp(
  r'\s+(?:in|for|from|during|until)\s+(?:v\d+(?:\.\d+)?|prototype|mvp)\.?$',
  caseSensitive: false,
);
final RegExp _tradeOffFillerWordRegex = RegExp(
  r'\b(?:immediate|instant|complex|realistic|heavy|detailed|elaborate|multi-bone|waiting\s+on|60\s*fps|clean|transparent|responsive|fast)\b\s*',
  caseSensitive: false,
);
final RegExp _exclusionLeadVerbRegex = RegExp(
  r'^(?:Cut|Defer|Exclude|Omit|Skip|Remove)\s+',
  caseSensitive: false,
);
final RegExp _leadInFillerVerbRegex = RegExp(
  r'^(?:Prioritize|Focus\s+on|Ensure)\s+',
  caseSensitive: false,
);
final RegExp _whitespaceRegex = RegExp(r'\s+');
final RegExp _dotPipeSepRegex = RegExp(r'[·|]');
final RegExp _dotPipeSplitRegex = RegExp(r'\s*[·|]\s*');
final RegExp _newlineCollapseRegex = RegExp(r'\s*\n\s*');

/// Wraps each line of text at [maxCharsPerLine] (default 80 characters),
/// breaking cleanly at the last space before column 80 (or at column 80 for
/// continuous words) while preserving manual `Shift + Enter` newlines.
class MaxColumnLineWrapFormatter extends TextInputFormatter {
  final int maxCharsPerLine;

  const MaxColumnLineWrapFormatter({this.maxCharsPerLine = 80});

  static String wrapTextAtColumn(String input, {int maxCharsPerLine = 80}) {
    if (input.isEmpty) return input;
    final rawLines = input.split('\n');
    final wrappedLines = <String>[];

    for (final line in rawLines) {
      if (line.length <= maxCharsPerLine) {
        wrappedLines.add(line);
        continue;
      }
      var remaining = line;
      while (remaining.length > maxCharsPerLine) {
        final window = remaining.substring(0, maxCharsPerLine + 1);
        final lastSpace = window.lastIndexOf(' ');
        if (lastSpace > 0) {
          wrappedLines.add(remaining.substring(0, lastSpace));
          remaining = remaining.substring(lastSpace + 1);
        } else {
          wrappedLines.add(remaining.substring(0, maxCharsPerLine));
          remaining = remaining.substring(maxCharsPerLine);
        }
      }
      wrappedLines.add(remaining);
    }
    return wrappedLines.join('\n');
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;
    final hasLongLine =
        text.split('\n').any((line) => line.length > maxCharsPerLine);
    if (!hasLongLine) return newValue;

    final wrapped = wrapTextAtColumn(text, maxCharsPerLine: maxCharsPerLine);
    final lengthDelta = wrapped.length - text.length;
    final rawOffset = newValue.selection.baseOffset;
    final nextOffset = rawOffset < 0
        ? wrapped.length
        : (rawOffset + lengthDelta).clamp(0, wrapped.length);

    return TextEditingValue(
      text: wrapped,
      selection: TextSelection.collapsed(offset: nextOffset),
    );
  }
}

/// Metadata and Agent guidance for each of the 8 focused sections in Stage 1.
class _SectionConfig {
  final String numLabel;
  final String optionKey;
  final String shortTitle;
  final String title;
  final List<String> options;
  final bool isMultiSelect;

  const _SectionConfig({
    required this.numLabel,
    required this.optionKey,
    required this.shortTitle,
    required this.title,
    required this.options,
    this.isMultiSelect = false,
  });
}

/// Stage 1 Screen: Structure-First One-Section-at-a-Time Dynamic UI + Full Blueprint Review
/// - Steps `01` to `09`: Focuses on one blueprint section at a time (Artifact Zone + Agent Console + Nav Bar).
/// - Step `10`: Full-Width Blueprint Review sheet right before approval.
class ProjectPitchScreen extends StatefulWidget {
  final WorkbenchProvider workbench;

  const ProjectPitchScreen({
    super.key,
    required this.workbench,
  });

  @override
  State<ProjectPitchScreen> createState() => _ProjectPitchScreenState();
}

class _ProjectPitchScreenState extends State<ProjectPitchScreen>
    with WorkbenchThemeMixin {
  final TextEditingController _sparkController = TextEditingController();
  final TextEditingController _agentPromptController = TextEditingController();
  final FocusNode _sparkFocusNode = FocusNode();
  final List<String> _sparkUndoStack = <String>[];

  KeyEventResult _handleMultilinePitchKeyEvent(
    KeyEvent event,
    TextEditingController controller, {
    required VoidCallback onSubmit,
  }) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final isEnter = event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (!isEnter) return KeyEventResult.ignored;

    if (HardwareKeyboard.instance.isShiftPressed) {
      final text = controller.text;
      final selection = controller.selection;
      final start = selection.isValid ? selection.start : text.length;
      final end = selection.isValid ? selection.end : text.length;
      final newText = text.replaceRange(start, end, '\n');
      controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: start + 1),
      );
      return KeyEventResult.handled;
    }

    onSubmit();
    return KeyEventResult.handled;
  }

  String? _lastTrackedProjectId;
  final Map<int, int?> _selectedOptionBySection = {};
  final Map<int, Set<int>> _selectedOptionsBySection = {};
  final Map<int, dynamic> _initialSectionDefaults = {};

  /// Step 10 Full Review hover, Bento focus, & single-open Refine drawer state.
  int? _hoveredReviewSectionIdx;
  int? _focusedBentoSectionIdx;
  int? _openRefineDrawerSectionIdx;

  /// Inline Click-to-Edit state (Upgrade 2: replaces popup AlertDialogs across Stage 1).
  String? _activeInlineEditKey;
  final TextEditingController _inlineItemEditController =
      TextEditingController();

  @override
  bool get isDark => widget.workbench.isDark;

  // Unified Single-Column 680px Quiet Document Measure (matches Feature Runbook & Progressive Release):
  double get _viewportWidth => MediaQuery.sizeOf(context).width;
  bool get _isMobileMeasure => _viewportWidth < 640;
  bool get _isTabletMeasure => _viewportWidth >= 640 && _viewportWidth < 1024;
  double get _measureColumnMaxWidth => _isMobileMeasure ? 460.0 : 680.0;
  double get _measureBodyFontSize => 13.5;
  double get _measureLeadFontSize => 15.0;
  double get _measureTitleFontSize => _isMobileMeasure ? 20.0 : 22.0;
  double get _measureSpecValueSize => 12.5;
  double get _measureCardPadH => _isMobileMeasure ? 14.0 : 16.0;
  double get _measureCardPadV => _isMobileMeasure ? 12.0 : 14.0;
  double get _measureCardGap => 10.0;

  void _rebuild([VoidCallback? fn]) => setState(fn ?? () {});

  List<_SectionConfig> get _sections => _kSections;
  static const List<_SectionConfig> _kSections = [
    _SectionConfig(
      numLabel: '01',
      optionKey: 'goal',
      shortTitle: 'Goal',
      title: 'Goal',
      options: [],
    ),
    _SectionConfig(
      numLabel: '02',
      optionKey: 'gameSpec',
      shortTitle: 'Game Spec',
      title: 'Game Spec',
      options: [
        'Top-Down Twin-Stick Arena: 2D Top-Down · Twin-Stick (WASD + Aim) · Singleplayer · Single-Screen Wave Arena',
        '3D Isometric Action Roguelite: 3D Isometric · Mouse + WASD · Singleplayer · Procedural Room Grid',
        '2D Side-Scrolling Platformer: 2D Side-Scrolling · Gamepad / Precision Platformer · Singleplayer · Multi-Room Obstacle Course',
      ],
    ),
    _SectionConfig(
      numLabel: '03',
      optionKey: 'techSpec',
      shortTitle: 'Tech Spec',
      title: 'Tech Spec',
      options: [
        'Godot 4 2D Native Stack: Godot 4 (GDScript) · PC & Web · Godot 4 2D Pixel / Vector · ConfigFile (.cfg / .tres)',
        'Godot 4 Forward+ 3D Stack: Godot 4 (GDScript) · PC & Steam Deck · Godot 4 Forward+ 3D · Resource (.tres)',
        'Godot 4 GDExtension Stack: Godot 4 (GDScript + GDExtension C++) · PC Desktop · Godot 4 Forward+ 3D · ConfigFile (.cfg / .tres)',
      ],
    ),
    _SectionConfig(
      numLabel: '04',
      optionKey: 'designPillars',
      shortTitle: 'Design Pillars',
      title: 'Design Pillars',
      isMultiSelect: true,
      options: [],
    ),
    _SectionConfig(
      numLabel: '05',
      optionKey: 'tradeOffs',
      shortTitle: 'Trade-Offs',
      title: 'Trade-Offs',
      isMultiSelect: true,
      options: [],
    ),
    _SectionConfig(
      numLabel: '06',
      optionKey: 'coreLoop',
      shortTitle: 'Core Loop',
      title: 'Core Loop',
      isMultiSelect: true,
      options: [],
    ),
    _SectionConfig(
      numLabel: '07',
      optionKey: 'exclusions',
      shortTitle: 'Out of Scope',
      title: 'Out of Scope',
      isMultiSelect: true,
      options: [],
    ),
    _SectionConfig(
      numLabel: '08',
      optionKey: 'doneWhen',
      shortTitle: 'Done When',
      title: 'Done When',
      options: [],
    ),
  ];

  List<String> _optionsForSection(ProjectConceptBlueprint draft, int sectionIdx) {
    final sec = _sections[sectionIdx];
    final dynamicOpts = draft.sectionOptions[sec.optionKey];
    if (dynamicOpts != null && dynamicOpts.isNotEmpty) {
      return dynamicOpts;
    }
    return sec.options;
  }

  /// Splits an option string into `(title, description)` so Playing Cards always display
  /// a crisp bold Card Title on top and a 2-line Short Description underneath.
  ({String title, String description}) _splitOptionIntoCardTitleAndBody(
    String rawOption,
    int sectionIdx,
    int optIdx,
  ) {
    final clean = rawOption.trim();
    if (clean.contains(':')) {
      final colonIdx = clean.indexOf(':');
      final head = clean.substring(0, colonIdx).trim();
      final tail = clean.substring(colonIdx + 1).trim();
      if (head.isNotEmpty && tail.isNotEmpty && head.length <= 42) {
        return (title: head, description: tail);
      }
    }
    if (clean.contains('·')) {
      final dotIdx = clean.indexOf('·');
      final head = clean.substring(0, dotIdx).trim();
      final tail = clean.substring(dotIdx + 1).trim();
      if (head.isNotEmpty && tail.isNotEmpty) {
        return (title: head, description: tail);
      }
    }
    if (clean.toLowerCase().contains(' over ')) {
      final overParts = clean.split(_overSplitRegex);
      if (overParts.length >= 2) {
        final winTitle = overParts.first
            .replaceFirst(_prioritizePrefixRegex, '')
            .trim();
        return (title: winTitle, description: clean);
      }
    }
    final words = clean.split(_whitespaceRegex);
    if (words.length > 4) {
      return (
        title: words.take(3).join(' '),
        description: clean,
      );
    }
    return (
      title: 'Option 0${optIdx + 1}',
      description: clean,
    );
  }

  @override
  void dispose() {
    _sparkController.dispose();
    _agentPromptController.dispose();
    _inlineItemEditController.dispose();
    _sparkFocusNode.dispose();
    super.dispose();
  }

  void _captureSectionDefaultIfNeeded(
    ProjectConceptBlueprint draft,
    int sectionIdx,
  ) {
    if (_initialSectionDefaults.containsKey(sectionIdx)) return;
    switch (sectionIdx) {
      case 0:
        _initialSectionDefaults[0] = draft.goal;
        break;
      case 1:
        _initialSectionDefaults[1] = List<String>.from(draft.gameSpec);
        break;
      case 2:
        _initialSectionDefaults[2] = List<String>.from(draft.techSpec);
        break;
      case 3:
        _initialSectionDefaults[3] = List<String>.from(draft.designPillars);
        break;
      case 4:
        _initialSectionDefaults[4] = List<String>.from(draft.tradeOffs);
        break;
      case 5:
        _initialSectionDefaults[5] = List<String>.from(draft.coreLoopBeats);
        break;
      case 6:
        _initialSectionDefaults[6] = List<String>.from(draft.exclusions);
        break;
      case 7:
        _initialSectionDefaults[7] = draft.doneWhen;
        break;
    }
  }

  void _restoreSectionDefault(ProjectConceptBlueprint draft, int sectionIdx) {
    final saved = _initialSectionDefaults[sectionIdx];
    if (saved == null) return;
    widget.workbench.updateConceptDraft((d) {
      switch (sectionIdx) {
        case 0:
          if (saved is String) d.goal = saved;
          break;
        case 1:
          if (saved is List<String>) d.gameSpec = List<String>.from(saved);
          break;
        case 2:
          if (saved is List<String>) d.techSpec = List<String>.from(saved);
          break;
        case 3:
          if (saved is List<String>) d.designPillars = List<String>.from(saved);
          break;
        case 4:
          if (saved is List<String>) d.tradeOffs = List<String>.from(saved);
          break;
        case 5:
          if (saved is List<String>) d.coreLoopBeats = List<String>.from(saved);
          break;
        case 6:
          if (saved is List<String>) d.exclusions = List<String>.from(saved);
          break;
        case 7:
          if (saved is String) d.doneWhen = saved;
          break;
      }
    });
  }

  bool _isSectionOptionSelected(int sectionIdx, int optIdx) {
    final sec = _sections[sectionIdx];
    if (sec.isMultiSelect) {
      return _selectedOptionsBySection[sectionIdx]?.contains(optIdx) ?? false;
    }
    return _selectedOptionBySection[sectionIdx] == optIdx;
  }

  Future<void> _selectSectionOption(
    ProjectConceptBlueprint draft,
    int sectionIdx,
    int optIdx,
  ) async {
    final opts = _optionsForSection(draft, sectionIdx);
    if (optIdx < 0 || optIdx >= opts.length) return;
    final optionText = opts[optIdx];
    final sec = _sections[sectionIdx];

    if (sec.isMultiSelect) {
      _captureSectionDefaultIfNeeded(draft, sectionIdx);
      final currentSet = Set<int>.from(
        _selectedOptionsBySection[sectionIdx] ?? const <int>{},
      );
      final wasSelected = currentSet.contains(optIdx);
      if (wasSelected) {
        currentSet.remove(optIdx);
      } else {
        currentSet.add(optIdx);
      }
      if (currentSet.isEmpty) {
        _restoreSectionDefault(draft, sectionIdx);
        setState(() {
          _selectedOptionsBySection.remove(sectionIdx);
          _selectedOptionBySection.remove(sectionIdx);
        });
        return;
      }

      setState(() {
        _selectedOptionsBySection[sectionIdx] = currentSet;
        _selectedOptionBySection[sectionIdx] = currentSet.last;
      });
      _applyMultiSelectSectionOptionsDeterministic(
        draft,
        sectionIdx,
        currentSet,
        opts,
      );
      return;
    }

    // Clicking the already-selected Option Card unselects it and restores the initial generated default!
    if (_selectedOptionBySection[sectionIdx] == optIdx) {
      _restoreSectionDefault(draft, sectionIdx);
      setState(() {
        _selectedOptionBySection.remove(sectionIdx);
      });
      return;
    }

    _captureSectionDefaultIfNeeded(draft, sectionIdx);

    _applySectionOptionDeterministic(draft, sectionIdx, optIdx, optionText);
    if (!mounted) return;
    setState(() {
      _selectedOptionBySection[sectionIdx] = optIdx;
    });
  }

  void _applyMultiSelectSectionOptionsDeterministic(
    ProjectConceptBlueprint draft,
    int sectionIdx,
    Set<int> selectedIndices,
    List<String> opts,
  ) {
    final sorted = selectedIndices.toList()..sort();
    final savedDefault = _initialSectionDefaults[sectionIdx];
    final baseList = savedDefault is List<String>
        ? List<String>.from(savedDefault)
        : <String>[];

    widget.workbench.updateConceptDraft((d) {
      switch (sectionIdx) {
        case 3: // 04 Design Pillars
          final combined = List<String>.from(baseList);
          for (final idx in sorted) {
            if (idx < 0 || idx >= opts.length) continue;
            final raw = opts[idx].trim();
            final val = ProjectConceptBlueprint.ensureNamedPillar(
              raw,
              combined.length,
            );
            if (!combined.contains(val)) combined.add(val);
          }
          d.designPillars = combined;
          break;
        case 4: // 05 Trade-Offs
          final combined = List<String>.from(baseList);
          for (final idx in sorted) {
            if (idx < 0 || idx >= opts.length) continue;
            final raw = opts[idx].trim();
            final body = raw.contains(':')
                ? raw.substring(raw.indexOf(':') + 1).trim()
                : raw;
            if (!combined.contains(body)) combined.add(body);
          }
          d.tradeOffs = combined;
          break;
        case 5: // 06 Core Loop Beats
          final combined = List<String>.from(baseList);
          for (final idx in sorted) {
            if (idx < 0 || idx >= opts.length) continue;
            final raw = opts[idx].trim();
            final body = raw.contains(':')
                ? raw.substring(raw.indexOf(':') + 1).trim()
                : raw;
            if (body.contains('→')) {
              combined.clear();
              final steps = body
                  .split('→')
                  .map((s) => s.trim())
                  .where((s) => s.isNotEmpty)
                  .toList();
              for (int i = 0; i < steps.length; i++) {
                final formatted = steps[i].trim();
                if (!combined.any((c) => c.toLowerCase().startsWith(
                    formatted.split(':').first.trim().toLowerCase()))) {
                  combined.add(formatted);
                }
              }
            } else {
              final formatted = raw.contains(':')
                  ? raw
                  : 'Beat ${combined.length + 1}: $raw';
              if (!combined.contains(formatted) && !combined.contains(raw)) {
                combined.add(formatted);
              }
            }
          }
          if (combined.isNotEmpty) {
            d.coreLoopBeats = combined;
          }
          break;
        case 6: // 07 Out of Scope Exclusions
          final combined = List<String>.from(baseList);
          for (final idx in sorted) {
            if (idx < 0 || idx >= opts.length) continue;
            final raw = opts[idx].trim();
            final body = raw.contains(':')
                ? raw.substring(raw.indexOf(':') + 1).trim()
                : raw;
            if (!combined.contains(body)) combined.add(body);
          }
          d.exclusions = combined;
          break;
      }
    });
  }

  void _applySectionOptionDeterministic(
    ProjectConceptBlueprint draft,
    int sectionIdx,
    int optIdx,
    String optionText,
  ) {
    final trimmedOption = optionText.trim();
    final colonIdx = trimmedOption.indexOf(':');
    final firstSepMatch = _dotPipeSepRegex.firstMatch(trimmedOption);
    final hasLeadingTitlePrefix = colonIdx > 0 &&
        (firstSepMatch == null || colonIdx < firstSepMatch.start);
    final bodyAfterColon = hasLeadingTitlePrefix
        ? trimmedOption.substring(colonIdx + 1).trim()
        : trimmedOption;

    widget.workbench.updateConceptDraft((d) {
      switch (sectionIdx) {
        case 0:
          final cleanGoal = ProjectConceptBlueprint.sanitizeGoalText(optionText);
          if (cleanGoal.isNotEmpty) {
            d.goal = cleanGoal.endsWith('.') ? cleanGoal : '$cleanGoal.';
          }
          break;
        case 1:
          final specParts = bodyAfterColon
              .split(_dotPipeSplitRegex)
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();
          if (specParts.isNotEmpty) {
            d.gameSpec = [
              specParts[0],
              specParts.length > 1 ? specParts[1] : (d.gameSpec.length > 1 ? d.gameSpec[1] : ''),
              specParts.length >= 4 ? specParts[2] : (d.gameSpec.length > 2 ? d.gameSpec[2] : ''),
              specParts.length >= 3 ? specParts.last : (d.gameSpec.length > 3 ? d.gameSpec[3] : ''),
            ];
          }
          break;
        case 2:
          final techParts = bodyAfterColon
              .split(_dotPipeSplitRegex)
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();
          if (techParts.isNotEmpty) {
            d.techSpec = ProjectConceptBlueprint.normalizeGodotTechSpec([
              techParts[0],
              techParts.length > 1 ? techParts[1] : (d.techSpec.length > 1 ? d.techSpec[1] : ''),
              techParts.length > 2 ? techParts[2] : (d.techSpec.length > 2 ? d.techSpec[2] : ''),
              techParts.length > 3 ? techParts[3] : (d.techSpec.length > 3 ? d.techSpec[3] : ''),
            ]);
          }
          break;
        case 7:
          d.doneWhen = bodyAfterColon;
          break;
      }
    });
  }

  Future<void> _submitSectionPrompt(
    ProjectConceptBlueprint draft,
    int sectionIdx, {
    TextEditingController? controller,
  }) async {
    final activeController = controller ?? _agentPromptController;
    final text = activeController.text
        .replaceAll(_newlineCollapseRegex, ' ')
        .trim();
    if (text.isEmpty || widget.workbench.isAgentBusy) return;
    activeController.clear();

    final sec = _sections[sectionIdx];
    await widget.workbench.sendConceptChatMessage(
      '[Section ${sec.numLabel} ${sec.title}] $text',
    );
    if (!mounted) return;
    setState(() {
      _initialSectionDefaults.remove(sectionIdx);
      _selectedOptionBySection.remove(sectionIdx);
      _selectedOptionsBySection.remove(sectionIdx);
    });
  }

  List<String> _kvPresetsForCell(bool isGameSpec, int cellIndex) {
    const gameSpecPresets = <int, List<String>>{
      0: ['2D Top-Down', '2D Side-Scrolling', '3D First-Person', '3D Third-Person', '3D Isometric'],
      1: ['WASD + Mouse', 'KBM / Gamepad', 'Gamepad Platformer', 'Point & Click'],
      2: ['Singleplayer', 'Local Couch Co-Op', 'Singleplayer Leaderboards', 'Singleplayer Survival'],
      3: ['Single-Screen Arena', 'Continuous Overworld', 'Multi-Room Course', 'Procedural Room Grid'],
    };
    const techSpecPresets = <int, List<String>>{
      0: [
        'Godot 4 (GDScript)',
        'Godot 4 (GDScript + GDExtension C++)',
      ],
      1: ['PC Desktop', 'PC & Steam Deck', 'PC & Web (HTML5)'],
      2: [
        'Godot 4 Greybox (2D / Forward+)',
        'Godot 4 Forward+ 3D',
        'Godot 4 2D Pixel / Vector',
        'Godot 4 Compatibility (Web/Mobile)',
      ],
      3: ['ConfigFile (.cfg / .tres)', 'Steam Cloud Save', 'Stateless Arcade Session'],
    };
    return (isGameSpec ? gameSpecPresets[cellIndex] : techSpecPresets[cellIndex]) ?? const <String>[];
  }

  void _startInlineEdit(String key, String initialText) {
    _rebuild(() {
      _activeInlineEditKey = key;
      _inlineItemEditController.text = initialText;
      _inlineItemEditController.selection = TextSelection.fromPosition(
        TextPosition(offset: _inlineItemEditController.text.length),
      );
    });
  }

  void _applyDirectKvValue({
    required bool isGameSpec,
    required int cellIndex,
    required String newValue,
  }) {
    final trimmed = newValue.trim();
    if (trimmed.isEmpty) return;
    widget.workbench.updateConceptDraft((d) {
      final targetList = isGameSpec ? List<String>.from(d.gameSpec) : List<String>.from(d.techSpec);
      while (targetList.length <= cellIndex) {
        targetList.add('—');
      }
      targetList[cellIndex] = trimmed;
      if (isGameSpec) {
        d.gameSpec = targetList;
      } else {
        d.techSpec = targetList;
      }
    });
  }

  void _promptEditProjectTitle(ProjectConceptBlueprint draft, {String key = 'project_title'}) {
    _startInlineEdit(key, draft.title);
  }

  void _saveInlineProjectTitle(String val) {
    final trimmed = val.trim();
    if (trimmed.isEmpty) return;
    final activeId = widget.workbench.activeProjectId;
    if (activeId != null) {
      widget.workbench.renameProject(activeId, trimmed);
    } else {
      widget.workbench.updateConceptDraft((d) => d.title = trimmed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentProjectId = widget.workbench.activeProjectId;
    if (currentProjectId != _lastTrackedProjectId) {
      _lastTrackedProjectId = currentProjectId;
      _selectedOptionBySection.clear();
      _selectedOptionsBySection.clear();
      _initialSectionDefaults.clear();
      _hoveredReviewSectionIdx = null;
      _focusedBentoSectionIdx = null;
      _openRefineDrawerSectionIdx = null;
      _activeInlineEditKey = null;
      _sparkController.clear();
      _sparkUndoStack.clear();
      _agentPromptController.clear();
    }

    final draft = widget.workbench.conceptDraft;

    // Step 1A: Before the first Spark is submitted, show the centered Spark launcher
    if (draft == null) {
      return Container(
        color: bgBase,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: _buildInitialSparkLauncher(),
            ),
          ),
        ),
      );
    }

    if (widget.workbench.jumpToFullReviewPending) {
      widget.workbench.consumeJumpToFullReviewPending();
    }

    // Step 1B: Spacious Single-Column Concept Blueprint (75ch Desktop · 65ch Tablet · 50ch Mobile)
    return Container(
      key: const ValueKey('concept_interview_card'),
      color: bgBase,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                _isMobileMeasure ? 14 : 24,
                _isMobileMeasure ? 18 : 26,
                _isMobileMeasure ? 14 : 24,
                36,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: _measureColumnMaxWidth),
                  child: _buildFullReviewWorkspace(draft),
                ),
              ),
            ),
          ),
          _buildConceptStickyBottomDock(draft),
        ],
      ),
    );
  }

}

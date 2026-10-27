import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/agent_blueprints.dart';
import '../providers/workbench_provider.dart';
import '../theme/app_theme.dart';

part 'pitch_spark_and_outliner_part.dart';
part 'pitch_section_workspace_part.dart';
part 'pitch_full_review_part.dart';

/// Wraps each line of text at [maxCharsPerLine] (default 70 characters),
/// breaking cleanly at the last space before column 70 (or at column 70 for
/// continuous words) while preserving manual `Shift + Enter` newlines.
class MaxColumnLineWrapFormatter extends TextInputFormatter {
  final int maxCharsPerLine;

  const MaxColumnLineWrapFormatter({this.maxCharsPerLine = 70});

  static String wrapTextAtColumn(String input, {int maxCharsPerLine = 70}) {
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

/// Metadata and Agent guidance for each of the 9 focused sections in Stage 1.
class _SectionConfig {
  final String numLabel;
  final String optionKey;
  final String shortTitle;
  final String title;
  final String purpose;
  final String question;
  final List<String> options;
  final bool isMultiSelect;

  const _SectionConfig({
    required this.numLabel,
    required this.optionKey,
    required this.shortTitle,
    required this.title,
    required this.purpose,
    required this.question,
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
  final TextEditingController _inlineReviewPromptController =
      TextEditingController();
  final FocusNode _sparkFocusNode = FocusNode();
  final FocusNode _conceptChatFocusNode = FocusNode();

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

  final RegExp _overSplitRegex = RegExp(
    r'\s+over\s+',
    caseSensitive: false,
  );
  final RegExp _prioritizePrefixRegex = RegExp(
    r'^Prioritize\s+',
    caseSensitive: false,
  );
  final RegExp _whitespaceRegex = RegExp(r'\s+');
  final RegExp _dotPipeSepRegex = RegExp(r'[·|]');
  final RegExp _dotPipeSplitRegex = RegExp(r'\s*[·|]\s*');
  final RegExp _goalClauseSplitRegex = RegExp(r',\s*and\s+|,\s+');
  final RegExp _nonWordStripRegex = RegExp(r'[^\w\s-]');

  /// Active step index: `0`..`7` for sections `01`..`08`, and `8` (default) for `09 · Full Concept Review` (Single-Page Blueprint).
  String? _lastTrackedProjectId;
  int _currentStep = 8;
  final Set<int> _visitedSteps = {0, 1, 2, 3, 4, 5, 6, 7};
  final Map<int, int?> _selectedOptionBySection = {};
  final Map<int, Set<int>> _selectedOptionsBySection = {};
  final Map<int, dynamic> _initialSectionDefaults = {};
  final Map<int, String> _agentNotesBySection = {};

  /// Step 10 Full Review hover & inline contextual Agent drawer state.
  int? _hoveredReviewSectionIdx;
  int? _inlineEditingSectionIdx;

  /// Inline Click-to-Edit state (Upgrade 2: replaces popup AlertDialogs across Stage 1).
  String? _activeInlineEditKey;
  final TextEditingController _inlineItemEditController =
      TextEditingController();

  @override
  bool get isDark => widget.workbench.isDark;

  void _rebuild([VoidCallback? fn]) => setState(fn ?? () {});

  List<_SectionConfig> get _sections => _kSections;
  static const List<_SectionConfig> _kSections = [
    _SectionConfig(
      numLabel: '01',
      optionKey: 'goal',
      shortTitle: 'Goal',
      title: 'Goal',
      purpose: 'Plain-English statement of what we are building and why.',
      question: 'How should we frame the core prototype goal for v0.1?',
      options: [],
    ),
    _SectionConfig(
      numLabel: '02',
      optionKey: 'gameSpec',
      shortTitle: 'Game Spec',
      title: 'Game Spec',
      purpose: 'Camera view, player controls, mode, and arena layout.',
      question: 'Which camera perspective and control scheme fits best?',
      options: [],
    ),
    _SectionConfig(
      numLabel: '03',
      optionKey: 'techSpec',
      shortTitle: 'Tech Spec',
      title: 'Tech Spec',
      purpose: 'Engine, target platform, asset pipeline, and save/network architecture.',
      question: 'What engine and technical pipeline are we targeting for v0.1?',
      options: [],
    ),
    _SectionConfig(
      numLabel: '04',
      optionKey: 'designPillars',
      shortTitle: 'Design Pillars',
      title: 'Design Pillars',
      purpose: 'Core player experience truths (how the game feels, never a feature list).',
      question: 'Which player experience truth should anchor our design decisions?',
      isMultiSelect: true,
      options: [],
    ),
    _SectionConfig(
      numLabel: '05',
      optionKey: 'tradeOffs',
      shortTitle: 'Trade-Offs',
      title: 'Trade-Offs (X over Y)',
      purpose: 'Explicit engineering & design priority rules when mechanics conflict.',
      question: 'When mechanics conflict during production, what wins?',
      isMultiSelect: true,
      options: [],
    ),
    _SectionConfig(
      numLabel: '06',
      optionKey: 'coreLoop',
      shortTitle: 'Core Loop',
      title: 'In Scope: Core Gameplay Loop',
      purpose: 'Repeatable player gameplay loop used to define the Epics and Features in Stage 2.',
      question: 'How should the playable core loop flow from start to reset?',
      isMultiSelect: true,
      options: [],
    ),
    _SectionConfig(
      numLabel: '07',
      optionKey: 'exclusions',
      shortTitle: 'Out of Scope',
      title: 'Out of Scope (Exclusions)',
      purpose: 'Hard exclusions cut from the Prototype to prevent scope creep.',
      question: 'Which scope-creep features should we explicitly cut from the Prototype?',
      isMultiSelect: true,
      options: [],
    ),
    _SectionConfig(
      numLabel: '08',
      optionKey: 'doneWhen',
      shortTitle: 'Done When',
      title: 'Done When',
      purpose: 'Observable playtest condition that proves the Prototype is complete.',
      question: 'How will we verify that the Prototype loop is done?',
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
      final dotParts = clean
          .split('·')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (dotParts.length >= 2) {
        return (
          title: dotParts.first,
          description: dotParts.sublist(1).join(' · '),
        );
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
    _inlineReviewPromptController.dispose();
    _inlineItemEditController.dispose();
    _sparkFocusNode.dispose();
    _conceptChatFocusNode.dispose();
    super.dispose();
  }

  void _goToStep(int step) {
    final clamped = step.clamp(0, _sections.length);
    setState(() {
      _visitedSteps.add(_currentStep);
      _currentStep = clamped;
      if (clamped == _sections.length) {
        // When entering Full Review, mark all 9 sections visited
        for (int i = 0; i < _sections.length; i++) {
          _visitedSteps.add(i);
        }
      } else {
        _visitedSteps.add(clamped);
      }
      _inlineEditingSectionIdx = null;
    });
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
          _agentNotesBySection[sectionIdx] =
              'Cleared selections — restored default ${sec.title}.';
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
      if (!mounted) return;
      setState(() {
        _agentNotesBySection[sectionIdx] =
            'Combined ${currentSet.length} selected option(s) into ${sec.title} ✓';
      });
      return;
    }

    // Clicking the already-selected Option Card unselects it and restores the initial generated default!
    if (_selectedOptionBySection[sectionIdx] == optIdx) {
      _restoreSectionDefault(draft, sectionIdx);
      setState(() {
        _selectedOptionBySection.remove(sectionIdx);
        _agentNotesBySection[sectionIdx] =
            'Unselected option — restored default ${sec.title}.';
      });
      return;
    }

    _captureSectionDefaultIfNeeded(draft, sectionIdx);

    _applySectionOptionDeterministic(draft, sectionIdx, optIdx, optionText);
    if (!mounted) return;
    setState(() {
      _selectedOptionBySection[sectionIdx] = optIdx;
      _agentNotesBySection[sectionIdx] =
          'Agent updated ${sec.title}: Applied "$optionText".';
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
          final combined = <String>[];
          for (final idx in sorted) {
            if (idx < 0 || idx >= opts.length) continue;
            final raw = opts[idx].trim();
            final val = raw.contains(':') ? raw : 'Core Focus: $raw';
            if (!combined.contains(val)) combined.add(val);
          }
          for (final existing in baseList) {
            if (combined.length < 4 && !combined.contains(existing)) {
              combined.add(existing);
            }
          }
          d.designPillars = combined;
          break;
        case 4: // 05 Trade-Offs
          final combined = <String>[];
          for (final idx in sorted) {
            if (idx < 0 || idx >= opts.length) continue;
            final raw = opts[idx].trim();
            final body = raw.contains(':')
                ? raw.substring(raw.indexOf(':') + 1).trim()
                : raw;
            if (!combined.contains(body)) combined.add(body);
          }
          for (final existing in baseList) {
            if (combined.length < 3 && !combined.contains(existing)) {
              combined.add(existing);
            }
          }
          d.tradeOffs = combined;
          break;
        case 5: // 06 Core Loop Beats
          final combined = <String>[];
          for (final idx in sorted) {
            if (idx < 0 || idx >= opts.length) continue;
            final raw = opts[idx].trim();
            final body = raw.contains(':')
                ? raw.substring(raw.indexOf(':') + 1).trim()
                : raw;
            if (body.contains('→')) {
              final steps = body
                  .split('→')
                  .map((s) => s.trim())
                  .where((s) => s.isNotEmpty);
              for (final step in steps) {
                final formatted = step.trim();
                if (!combined.any((c) => c.toLowerCase().startsWith(
                    step.split(':').first.trim().toLowerCase()))) {
                  combined.add(formatted);
                }
              }
            } else if (!combined.contains(raw)) {
              combined.add(raw);
            }
          }
          if (combined.isNotEmpty) {
            d.coreLoopBeats = combined;
          }
          break;
        case 6: // 07 Out of Scope Exclusions
          final combined = <String>[];
          for (final idx in sorted) {
            if (idx < 0 || idx >= opts.length) continue;
            final raw = opts[idx].trim();
            final body = raw.contains(':')
                ? raw.substring(raw.indexOf(':') + 1).trim()
                : raw;
            if (!combined.contains(body)) combined.add(body);
          }
          for (final existing in baseList) {
            if (!combined.contains(existing)) {
              combined.add(existing);
            }
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
            d.techSpec = [
              techParts[0],
              techParts.length > 1 ? techParts[1] : (d.techSpec.length > 1 ? d.techSpec[1] : ''),
              techParts.length > 2 ? techParts[2] : (d.techSpec.length > 2 ? d.techSpec[2] : ''),
              techParts.length > 3 ? techParts[3] : (d.techSpec.length > 3 ? d.techSpec[3] : ''),
            ];
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
        .replaceAll(RegExp(r'\s*\n\s*'), ' ')
        .trim();
    if (text.isEmpty || widget.workbench.isAgentBusy) return;
    activeController.clear();

    final sec = _sections[sectionIdx];
    await widget.workbench.sendConceptChatMessage(
      '[Section ${sec.numLabel} ${sec.title}] $text',
    );
    if (!mounted) return;
    setState(() {
      _agentNotesBySection[sectionIdx] =
          'Agent updated ${sec.title} based on your direction: "$text"';
    });
  }

  Future<void> _copyBlueprintAsMarkdown(ProjectConceptBlueprint draft) async {
    final buf = StringBuffer()
      ..writeln('# ${draft.title} — Project Concept Blueprint')
      ..writeln()
      ..writeln('## 01. Goal')
      ..writeln('> ${draft.goal}')
      ..writeln()
      ..writeln('## 02. Game Spec')
      ..writeln('- **Camera View:** ${draft.gameSpec.isNotEmpty ? draft.gameSpec[0] : "—"}')
      ..writeln('- **Controls:** ${draft.gameSpec.length > 1 ? draft.gameSpec[1] : "—"}')
      ..writeln('- **Player Mode:** ${draft.gameSpec.length > 2 ? draft.gameSpec[2] : "—"}')
      ..writeln('- **Arena Structure:** ${draft.gameSpec.length > 3 ? draft.gameSpec[3] : "—"}')
      ..writeln()
      ..writeln('## 03. Tech Spec')
      ..writeln('- **Engine:** ${draft.techSpec.isNotEmpty ? draft.techSpec[0] : "—"}')
      ..writeln('- **Platform:** ${draft.techSpec.length > 1 ? draft.techSpec[1] : "—"}')
      ..writeln('- **Asset Pipeline:** ${draft.techSpec.length > 2 ? draft.techSpec[2] : "—"}')
      ..writeln('- **Network / Save:** ${draft.techSpec.length > 3 ? draft.techSpec[3] : "—"}')
      ..writeln()
      ..writeln('## 04. Design Pillars');
    for (int i = 0; i < draft.designPillars.length; i++) {
      buf.writeln('- **P·${(i + 1).toString().padLeft(2, '0')}:** ${draft.designPillars[i]}');
    }
    buf
      ..writeln()
      ..writeln('## 05. Trade-Offs (X over Y)');
    for (final t in draft.tradeOffs) {
      buf.writeln('- ✓ $t');
    }
    buf
      ..writeln()
      ..writeln('## 06. In Scope: Core Loop Beats');
    for (int i = 0; i < draft.coreLoopBeats.length; i++) {
      buf.writeln('- **BEAT·${(i + 1).toString().padLeft(2, '0')}:** ${draft.coreLoopBeats[i]}');
    }
    buf
      ..writeln()
      ..writeln('## 07. Out of Scope (Exclusions)');
    for (final c in draft.exclusions) {
      buf.writeln('- [CUT] $c');
    }
    buf
      ..writeln()
      ..writeln('## 08. Done When')
      ..writeln('> ${draft.doneWhen}')
      ..writeln()
      ..writeln('## 09. Progressive Releases (v0.1 → v0.2+)');
    for (final r in draft.releaseTrainTitles) {
      buf.writeln('- $r');
    }

    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (!mounted) return;
    AppToast.show(
      context,
      'Copied Project Concept Blueprint as Markdown',
      icon: Icons.check_circle_outline,
      isDark: isDark,
      accentColor: accentEmerald,
    );
  }

  List<String> _kvPresetsForCell(bool isGameSpec, int cellIndex) {
    const gameSpecPresets = <int, List<String>>{
      0: ['2D Top-Down', '2D Side-Scrolling', '3D First-Person', '3D Third-Person', '3D Isometric'],
      1: ['Twin-Stick (WASD + Aim)', 'Mouse + WASD', 'Gamepad / Precision Platformer', 'Point & Click'],
      2: ['Singleplayer', 'Local Couch Co-Op', 'Singleplayer + Leaderboards'],
      3: ['Single-Screen Wave Arena', 'Continuous Single Overworld', 'Multi-Room Obstacle Course', 'Procedural Room Grid'],
    };
    const techSpecPresets = <int, List<String>>{
      0: ['Godot 4 (GDScript)', 'Unity 6 (C#)', 'Unreal Engine 5', 'Custom / Raylib'],
      1: ['PC Desktop', 'PC & Steam Deck', 'Web + Desktop'],
      2: ['2D Sprites + Particles', '3D Greybox Meshes', '2D/3D Hybrid Pipeline', 'Low-Poly Stylized'],
      3: ['Offline Local Save', 'Steam Cloud Save', 'Stateless Arcade Session'],
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
      _currentStep = _sections.length;
      _visitedSteps
        ..clear()
        ..addAll(List<int>.generate(_sections.length, (i) => i));
      _selectedOptionBySection.clear();
      _selectedOptionsBySection.clear();
      _initialSectionDefaults.clear();
      _agentNotesBySection.clear();
      _hoveredReviewSectionIdx = null;
      _inlineEditingSectionIdx = null;
      _activeInlineEditKey = null;
      _sparkController.clear();
      _agentPromptController.clear();
      _inlineReviewPromptController.clear();
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
      _currentStep = _sections.length;
      for (int i = 0; i < _sections.length; i++) {
        _visitedSteps.add(i);
      }
    }

    // Step 1B / 1C: Unified Left Outliner Sidebar (308px) + Focused Co-Design Canvas
    return Container(
      key: const ValueKey('concept_interview_card'),
      color: bgBase,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 780;
          final mainCanvasColumn = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1100),
                      child: _currentStep < _sections.length
                          ? _buildFocusedSectionWorkspace(draft, _currentStep)
                          : _buildFullReviewWorkspace(draft),
                    ),
                  ),
                ),
              ),
              _buildConceptStickyBottomDock(draft),
            ],
          );

          if (!isWide) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 220,
                  child: _buildLeftConceptOutlinerRail(draft),
                ),
                Expanded(child: mainCanvasColumn),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 248,
                child: _buildLeftConceptOutlinerRail(draft),
              ),
              Expanded(child: mainCanvasColumn),
            ],
          );
        },
      ),
    );
  }

}

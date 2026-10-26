import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/agent_blueprints.dart';
import '../providers/workbench_provider.dart';
import '../theme/app_theme.dart';

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

  /// Active step index: `0`..`8` for sections `01`..`09`, and `9` for `10 · Full Review`.
  int _currentStep = 0;
  final Set<int> _visitedSteps = {0};
  final Map<int, int?> _selectedOptionBySection = {};
  final Map<int, Set<int>> _selectedOptionsBySection = {};
  final Map<int, dynamic> _initialSectionDefaults = {};
  final Map<int, String> _agentNotesBySection = {};

  /// Step 10 Full Review hover & inline contextual Agent drawer state.
  int? _hoveredReviewSectionIdx;
  int? _inlineEditingSectionIdx;

  @override
  bool get isDark => widget.workbench.isDark;

  static const List<_SectionConfig> _sections = [
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
      final overParts = clean.split(RegExp(r'\s+over\s+', caseSensitive: false));
      if (overParts.length >= 2) {
        final winTitle = overParts.first
            .replaceFirst(RegExp(r'^Prioritize\s+', caseSensitive: false), '')
            .trim();
        return (title: winTitle, description: clean);
      }
    }
    final words = clean.split(RegExp(r'\s+'));
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
      case 8:
        _initialSectionDefaults[8] = List<String>.from(draft.releaseTrainTitles);
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
        case 8:
          if (saved is List<String>) {
            d.releaseTrainTitles = List<String>.from(saved);
          }
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
                final formatted = step.contains(':')
                    ? step
                    : _describeCoreLoopBeatStep(step);
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

  String _describeCoreLoopBeatStep(String rawStep) {
    return rawStep.trim();
  }

  void _applySectionOptionDeterministic(
    ProjectConceptBlueprint draft,
    int sectionIdx,
    int optIdx,
    String optionText,
  ) {
    final bodyAfterColon = optionText.contains(':')
        ? optionText.substring(optionText.indexOf(':') + 1).trim()
        : optionText.trim();

    widget.workbench.updateConceptDraft((d) {
      switch (sectionIdx) {
        case 0:
          final cleanGoal = ProjectConceptBlueprint.sanitizeGoalText(optionText);
          if (cleanGoal.isNotEmpty) {
            d.goal = cleanGoal.endsWith('.') ? cleanGoal : '$cleanGoal.';
          }
          break;
        case 1:
          final specParts = optionText
              .split('·')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();
          if (specParts.length >= 3) {
            d.gameSpec = [
              specParts[0],
              specParts[1],
              specParts.length >= 4 ? specParts[2] : 'Singleplayer',
              specParts.last,
            ];
          } else if (optIdx == 0) {
            d.gameSpec = [
              '2D Top-Down',
              'Twin-Stick (WASD + Aim)',
              'Singleplayer',
              'Single-Screen Wave Arena',
            ];
          } else if (optIdx == 1) {
            d.gameSpec = [
              '2D Side-Scrolling',
              'Precision Controls',
              'Singleplayer',
              'Multi-Room Stages',
            ];
          } else {
            d.gameSpec = [
              '3D First-Person',
              'Mouse + WASD',
              'Singleplayer',
              'Enclosed Sandbox',
            ];
          }
          break;
        case 2:
          final techParts = optionText
              .split('·')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();
          if (techParts.length >= 4) {
            d.techSpec = techParts.take(4).toList();
          } else if (optIdx == 0) {
            d.techSpec = [
              'Godot 4 (2D)',
              'PC (Steam / Desktop)',
              '2D Sprites + Particles',
              'Offline-Only Local Save',
            ];
          } else if (optIdx == 1) {
            d.techSpec = [
              'Unity 6',
              'PC & Steam Deck',
              '2D/3D Hybrid Pipeline',
              'Steam Cloud Save',
            ];
          } else {
            d.techSpec = [
              'Unreal Engine 5',
              'PC Desktop',
              '3D Greybox Meshes',
              'Offline Local Save',
            ];
          }
          break;
        case 7:
          d.doneWhen = bodyAfterColon;
          break;
        case 8:
          final lowerOpt = optionText.toLowerCase();
          final isSplitOption = lowerOpt.contains('v0.2') ||
              lowerOpt.contains('two-step') ||
              lowerOpt.contains('split') ||
              (!lowerOpt.contains('single') && optIdx == 1);
          if (!isSplitOption) {
            d.releaseTrainTitles = [
              'v0.1: ${d.title} Core Loop - Prototype',
            ];
          } else {
            d.releaseTrainTitles = [
              'v0.1: ${d.title} Controls & Mechanics - Prototype',
              'v0.2: Full ${d.title} Core Loop - Prototype',
            ];
          }
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

  void _showDirectKvEditDialog({
    required bool isGameSpec,
    required int cellIndex,
    required String label,
    required String currentValue,
  }) {
    final controller = TextEditingController(text: currentValue);
    const gameSpecPresets = <int, List<String>>{
      0: ['2D Top-Down', '2D Side-Scrolling', '3D First-Person', '3D Isometric'],
      1: ['Twin-Stick (WASD + Aim)', 'Mouse + WASD', 'Gamepad / Precision Platformer', 'Point & Click'],
      2: ['Singleplayer', 'Local Couch Co-Op', 'Singleplayer + Leaderboards'],
      3: ['Single-Screen Wave Arena', 'Continuous Single Overworld', 'Multi-Room Obstacle Course', 'Procedural Room Grid'],
    };
    const techSpecPresets = <int, List<String>>{
      0: ['Godot 4 (2D)', 'Unity 6', 'Unreal Engine 5', 'Custom / Raylib'],
      1: ['PC Desktop', 'PC & Steam Deck', 'Web + Desktop'],
      2: ['2D Sprites + Particles', '3D Greybox Meshes', '2D/3D Hybrid Pipeline', 'Low-Poly Stylized'],
      3: ['Offline Local Save', 'Steam Cloud Save', 'Stateless Arcade Session'],
    };
    final presets = (isGameSpec ? gameSpecPresets[cellIndex] : techSpecPresets[cellIndex]) ?? const <String>[];

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: bgSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: borderBright),
          ),
          title: Text(
            'Edit $label',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: textPrimary,
            ),
          ),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  style: GoogleFonts.inter(fontSize: 13.5, color: textPrimary),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: bgRecessed,
                    hintText: 'Enter $label...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: borderSubtle),
                    ),
                  ),
                  onSubmitted: (val) {
                    _applyDirectKvValue(isGameSpec: isGameSpec, cellIndex: cellIndex, newValue: val);
                    Navigator.of(ctx).pop();
                  },
                ),
                if (presets.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'QUICK PRESETS',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final p in presets)
                        InkWell(
                          onTap: () {
                            _applyDirectKvValue(isGameSpec: isGameSpec, cellIndex: cellIndex, newValue: p);
                            Navigator.of(ctx).pop();
                          },
                          borderRadius: BorderRadius.circular(4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                            decoration: BoxDecoration(
                              color: bgRecessed,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: borderSubtle),
                            ),
                            child: Text(
                              p,
                              style: GoogleFonts.inter(
                                fontSize: 11.5,
                                color: textSecondary,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Cancel', style: GoogleFonts.inter(fontSize: 12, color: textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: focalAccent,
                foregroundColor: focalAccentFg,
                elevation: 0,
              ),
              onPressed: () {
                _applyDirectKvValue(
                  isGameSpec: isGameSpec,
                  cellIndex: cellIndex,
                  newValue: controller.text,
                );
                Navigator.of(ctx).pop();
              },
              child: Text(
                'Save',
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        );
      },
    );
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

  void _promptEditProjectTitle(ProjectConceptBlueprint draft) {
    _showDirectSectionTextEditDialog(
      title: 'Rename Project Title',
      initialText: draft.title,
      onSave: (val) {
        final activeId = widget.workbench.activeProjectId;
        if (activeId != null) {
          widget.workbench.renameProject(activeId, val);
        } else {
          widget.workbench.updateConceptDraft((d) => d.title = val);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
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

  // ── Initial New Project Idea Intake & Expansion Launcher (Before Concept Draft Exists) ──
  Widget _buildInitialSparkLauncher() {
    final intake = widget.workbench.sparkIntake;
    final expansionCards = intake?.expansionCards ?? const [];

    Future<void> submitIdeaToAgent() async {
      final text = _sparkController.text
          .replaceAll(RegExp(r'\s*\n\s*'), ' ')
          .trim();
      if (text.isEmpty && intake == null) return;
      _sparkController.clear();
      await widget.workbench.ingestOrRefineSparkIdea(text);
    }

    Widget buildExpansionPlayingCard(int index) {
      final card = expansionCards[index];
      final isSelected = card.isSelected;

      return Material(
        color: isSelected ? bgHover.withValues(alpha: 0.45) : Colors.transparent,
        child: InkWell(
          key: ValueKey('spark_card_$index'),
          onTap: widget.workbench.isAgentBusy
              ? null
              : () => widget.workbench.toggleSparkExpansionCard(index),
          child: Container(
            padding: EdgeInsets.fromLTRB(isSelected ? 13 : 8, 13, 8, 13),
            decoration: BoxDecoration(
              border: Border(
                left: isSelected
                    ? BorderSide(color: accentEmerald, width: 3)
                    : BorderSide.none,
                bottom: BorderSide(color: borderSubtle),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    isSelected
                        ? Icons.check_circle_rounded
                        : Icons.add_circle_outline_rounded,
                    size: 16,
                    color: isSelected ? accentEmerald : textMuted,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 10,
                        runSpacing: 4,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                card.title,
                                style: AppTheme.displayFont(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700,
                                  color: textPrimary,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                card.badge,
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  color: textSecondary,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            isSelected
                                ? '✓ Added to Concept'
                                : '+ Add to Concept',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color:
                                  isSelected ? accentEmerald : textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        card.description,
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          height: 1.48,
                          color: textSecondary,
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: borderSubtle)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'STEP 1A · NEW PROJECT',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: accentCyan,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Pitch your game idea to the Agent & shape your Concept Summary',
                style: AppTheme.displayFont(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                intake == null
                    ? 'Tell the Agent your game idea below so it can summarize the core loop back to you and generate tailored Concept Addition Cards.'
                    : 'Review the Agent\'s ingested summary below. Use the same input field to ask for changes, or toggle the Concept Addition rows on/off before clicking Start Concept Blueprint →.',
                style: GoogleFonts.inter(fontSize: 13, color: textSecondary),
              ),
            ],
          ),
        ),
        if (intake != null) ...[
          const SizedBox(height: 16),
          Container(
            key: const ValueKey('agent_idea_summary_card'),
            padding: const EdgeInsets.only(left: 16, top: 6, bottom: 6, right: 8),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: accentEmerald,
                  width: 3,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: accentEmerald,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'AGENT IDEA SUMMARY',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: accentEmerald,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          intake.workingTitle,
                          style: AppTheme.displayFont(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: textPrimary,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          key: const ValueKey('fast_track_concept_review_btn'),
                          onTap: widget.workbench.isAgentBusy
                              ? null
                              : () => widget.workbench.startConceptInterview(
                                    _sparkController.text,
                                    true,
                                  ),
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            child: Text(
                              'Fast-Track to Review ◫',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: accentEmerald,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        InkWell(
                          key: const ValueKey('clear_idea_summary_btn'),
                          onTap: () => widget.workbench.clearSparkIdeaIntake(),
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            child: Text(
                              'Reset ×',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: textMuted,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  intake.effectiveSummary,
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    height: 1.52,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  children: [
                    for (final m in intake.mechanics)
                      Text(
                        '⚡ $m',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: textSecondary,
                        ),
                      ),
                    for (final added
                        in intake.expansionCards.where((c) => c.isSelected))
                      Text(
                        '✓ + ${added.title}',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: accentEmerald,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Focus(
                      onKeyEvent: (node, event) =>
                          _handleMultilinePitchKeyEvent(
                        event,
                        _sparkController,
                        onSubmit: submitIdeaToAgent,
                      ),
                      child: TextField(
                        key: const ValueKey('spark_input_field'),
                        controller: _sparkController,
                        focusNode: _sparkFocusNode,
                        minLines: 1,
                        maxLines: null,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        inputFormatters: const [
                          MaxColumnLineWrapFormatter(maxCharsPerLine: 70),
                        ],
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: textPrimary,
                        ),
                        decoration: InputDecoration(
                          hintMaxLines: 1,
                          hintText: intake == null
                              ? 'Pitch your game idea (70 chars/line · Shift+Enter for new line)...'
                              : 'Tell the Agent what to change or add (Shift+Enter for new line)...',
                          hintStyle: GoogleFonts.inter(
                            fontSize: 13,
                            color: textMuted,
                          ),
                          filled: true,
                          fillColor: bgRecessed,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 14,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(color: borderSubtle),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(color: borderSubtle),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide:
                                BorderSide(color: borderBright, width: 1.5),
                          ),
                        ),
                        onSubmitted: (_) => submitIdeaToAgent(),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                key: const ValueKey('ingest_idea_summary_btn'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: textPrimary,
                  backgroundColor: bgRecessed,
                  side: BorderSide(color: borderBright),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 15,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                onPressed:
                    widget.workbench.isAgentBusy ? null : submitIdeaToAgent,
                child: Text(
                  intake == null ? 'Summarize Idea' : 'Update Summary',
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                key: const ValueKey('import_existing_gdd_btn'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: textPrimary,
                  backgroundColor: bgRecessed,
                  side: BorderSide(color: borderBright),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 15,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                onPressed: widget.workbench.isAgentBusy
                    ? null
                    : () => _showImportGddDialog(context),
                icon: Icon(Icons.description_outlined, size: 14, color: textSecondary),
                label: Text(
                  'Import GDD / Notes',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (intake != null) ...[
                const SizedBox(width: 10),
                ElevatedButton(
                  key: const ValueKey('start_concept_interview_btn'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: focalAccent,
                    foregroundColor: focalAccentFg,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 15,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    elevation: 0,
                  ),
                  onPressed: widget.workbench.isAgentBusy
                      ? null
                      : () => widget.workbench.startConceptInterview(
                            _sparkController.text
                                .replaceAll(RegExp(r'\s*\n\s*'), ' ')
                                .trim(),
                          ),
                  child: Text(
                    widget.workbench.isAgentBusy
                        ? 'Drafting Blueprint...'
                        : 'Start Concept Blueprint →',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (intake != null) ...[
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: borderSubtle)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'IDEAS TO ADD TO YOUR CONCEPT (CLICK TO TOGGLE ON / OFF)',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: textSecondary,
                    ),
                  ),
                  InkWell(
                    key: const ValueKey('shuffle_spark_ideas_btn'),
                    onTap: () => widget.workbench.shuffleSparkExpansionCards(),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      child: Text(
                        '↻ Refresh Suggestions',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: accentCyan,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (int i = 0; i < expansionCards.length; i++)
                  buildExpansionPlayingCard(i),
              ],
            ),
          ],
          if (widget.workbench.savedProjects.isNotEmpty) ...[
            const SizedBox(height: 20),
            Container(
              key: const ValueKey('stage1_saved_projects_strip'),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: bgRecessed,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: borderSubtle),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'SAVED PROJECTS IN VAULT (${widget.workbench.savedProjects.length}) — 1-CLICK RESUME',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                          color: textSecondary,
                        ),
                      ),
                      Text(
                        widget.workbench.isCloudSynced ? '☁ Cloud Synced' : '⚡ Local Auto-Save',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9,
                          color: textMuted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final p in widget.workbench.savedProjects)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: bgSurface,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: borderSubtle),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              InkWell(
                                key: ValueKey('spark_resume_project_${p.id}'),
                                onTap: () => widget.workbench.switchProject(p.id),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.folder_open_rounded,
                                      size: 13,
                                      color: textSecondary,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      p.title,
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: textPrimary,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Resume →',
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w700,
                                        color: accentEmerald,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              InkWell(
                                key: ValueKey('spark_duplicate_project_${p.id}'),
                                onTap: () => widget.workbench.duplicateProject(p.id),
                                child: Tooltip(
                                  message: 'Duplicate Project',
                                  child: Icon(
                                    Icons.copy_all_rounded,
                                    size: 13,
                                    color: textMuted,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              InkWell(
                                key: ValueKey('spark_delete_project_${p.id}'),
                                onTap: () => widget.workbench.deleteProject(p.id),
                                child: Tooltip(
                                  message: 'Delete Project',
                                  child: Icon(
                                    Icons.close_rounded,
                                    size: 13,
                                    color: textMuted,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      );
  }

  /// Option 5: Opens a dialog to paste an existing GDD, Notion note, or README document,
  /// extracts all 9 Concept sections, and jumps straight to `Step 10 · Full Review`.
  void _showImportGddDialog(BuildContext context) {
    final gddController = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          key: const ValueKey('import_gdd_dialog'),
          backgroundColor: bgSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: borderBright),
          ),
          title: Row(
            children: [
              Icon(Icons.description_outlined, size: 18, color: accentAmber),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Import Existing GDD / Pitch Notes',
                  style: AppTheme.displayFont(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: textPrimary,
                  ),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 620,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Paste your unstructured GDD, Notion notes, or README below. The Agent will extract all 9 Concept sections (Goal, Game Spec, Tech Spec, Pillars, Trade-Offs, Core Loop, Out of Scope, Done When, Release Train) and jump straight to Step 10 · Full Review.',
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    height: 1.45,
                    color: textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('import_gdd_text_field'),
                  controller: gddController,
                  maxLines: 9,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 12,
                    height: 1.45,
                    color: textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText:
                        '# Neon Grapple Arena\nGoal: Build a fast 3D grappling hook arena shooter in Godot 4.\nEngine: Godot 4 (3D)\nCore Loop: Grapple -> Shoot -> Bank Score -> Reset\nDone When: Playtester completes 3 consecutive arena waves without clipping.',
                    hintStyle: GoogleFonts.jetBrainsMono(
                      fontSize: 11.5,
                      color: textMuted,
                    ),
                    filled: true,
                    fillColor: bgRecessed,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: borderSubtle),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: borderSubtle),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: accentAmber, width: 1.4),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(
                'Cancel',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: textSecondary,
                ),
              ),
            ),
            ElevatedButton.icon(
              key: const ValueKey('confirm_import_gdd_btn'),
              style: ElevatedButton.styleFrom(
                backgroundColor: accentEmerald,
                foregroundColor: Colors.black,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              onPressed: () async {
                final raw = gddController.text.trim();
                if (raw.isEmpty) return;
                Navigator.of(ctx).pop();
                await widget.workbench.importExistingGddAndJumpToReview(raw);
              },
              icon: const Icon(Icons.auto_awesome_rounded, size: 14),
              label: Text(
                'Extract 9-Section Blueprint & Jump to Review →',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ── Unified 2-Surface Recessed Left Concept Stepper (`01 Goal` ... `09 Releases` + `10 Full Review`) ─
  Widget _buildLeftConceptOutlinerRail(ProjectConceptBlueprint draft) {
    final verifiedCount =
        _visitedSteps.where((idx) => idx >= 0 && idx < _sections.length).length;
    final viewSummary = draft.gameSpec.isNotEmpty ? draft.gameSpec.first : '2D/3D';
    final engineSummary = draft.techSpec.isNotEmpty ? draft.techSpec.first : 'Engine';

    return Container(
      key: const ValueKey('stage1_left_outliner_rail'),
      color: bgRecessed,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Flush Top Snapshot Header (Zero 4-sided nested boxes)
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 11),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        key: const ValueKey('stage1_rename_project_title_btn'),
                        onTap: () => _promptEditProjectTitle(draft),
                        borderRadius: BorderRadius.circular(3),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                draft.title.trim().isEmpty
                                    ? 'Concept Blueprint'
                                    : draft.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: textPrimary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.edit_outlined,
                              size: 11,
                              color: textMuted,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$verifiedCount/${_sections.length} ✓',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: accentEmerald,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        '$viewSummary · $engineSummary · ${draft.coreLoopBeats.length} Beats',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          color: textMuted,
                        ),
                      ),
                    ),
                    InkWell(
                      key: const ValueKey('new_spark_reset_btn'),
                      onTap: () => widget.workbench.resetConceptToSpark(),
                      borderRadius: BorderRadius.circular(3),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        child: Text(
                          '+ New Project',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: accentCyan,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Flat 10-Step Section List (`01`..`09` + `10 Full Concept Review` as the last item)
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 6),
              children: [
                for (int i = 0; i < _sections.length; i++)
                  _buildOutlineSectionNode(draft, i),
                _buildFinalReviewOutlineNode(verifiedCount: verifiedCount),
              ],
            ),
          ),

          // Quick-Action Footer: Jump straight to 2. Workbench (Build v0.1) from any section
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: InkWell(
              key: const ValueKey('outliner_quick_build_v01_btn'),
              onTap: widget.workbench.isAgentBusy
                  ? null
                  : () => widget.workbench.approveConceptAndBuildRelease(),
              borderRadius: BorderRadius.circular(5),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                child: Text(
                  'Build v0.1 →',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: accentEmerald,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _sectionOutlineMetaBadge(ProjectConceptBlueprint draft, int index) {
    switch (index) {
      case 0:
        return draft.goal.trim().isEmpty ? 'Draft' : 'Locked';
      case 1:
        return draft.gameSpec.isNotEmpty ? draft.gameSpec.first : 'Spec';
      case 2:
        return draft.techSpec.isNotEmpty ? draft.techSpec.first : 'Tech';
      case 3:
        return '${draft.designPillars.length} Pillars';
      case 4:
        return '${draft.tradeOffs.length} Rules';
      case 5:
        return '${draft.coreLoopBeats.length} Beats';
      case 6:
        return '${draft.exclusions.length} Cuts';
      case 7:
        return 'Playtest';
      case 8:
        return 'v0.1';
      default:
        return '';
    }
  }

  Widget _buildOutlineSectionNode(ProjectConceptBlueprint draft, int index) {
    final sec = _sections[index];
    final isActive = _currentStep == index;
    final isDone = _visitedSteps.contains(index);
    final metaBadge = _sectionOutlineMetaBadge(draft, index);

    return InkWell(
      key: ValueKey('step_node_$index'),
      onTap: () => _goToStep(index),
      child: Container(
        padding: const EdgeInsets.fromLTRB(13, 9, 12, 9),
        decoration: BoxDecoration(
          color: isActive
              ? accentCyan.withValues(alpha: 0.09)
              : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: isActive ? accentCyan : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              child: Text(
                sec.numLabel,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10.5,
                  fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                  color: isActive ? accentCyan : textMuted,
                ),
              ),
            ),
            Expanded(
              child: Text(
                sec.shortTitle,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  color: isActive
                      ? textPrimary
                      : (isDone ? textSecondary : textMuted),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 88),
              child: Text(
                metaBadge,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  color: isActive ? textPrimary : textMuted,
                ),
              ),
            ),
            if (isDone) ...[
              const SizedBox(width: 6),
              Text(
                '✓',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: accentEmerald,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFinalReviewOutlineNode({required int verifiedCount}) {
    final isActive = _currentStep == _sections.length;
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: borderSubtle),
          bottom: BorderSide(color: borderSubtle),
        ),
      ),
      child: InkWell(
        key: const ValueKey('synthesize_concept_btn'),
        onTap: () => _goToStep(_sections.length),
        child: Container(
          padding: const EdgeInsets.fromLTRB(13, 11, 12, 11),
          decoration: BoxDecoration(
            color: isActive
                ? accentEmerald.withValues(alpha: 0.10)
                : Colors.transparent,
            border: Border(
              left: BorderSide(
                color: isActive ? accentEmerald : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                child: Text(
                  '09',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: isActive ? accentEmerald : textSecondary,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Full Concept Review',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: textPrimary,
                      ),
                    ),
                    Text(
                      'Inspect all ${_sections.length} sections ($verifiedCount/${_sections.length})',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 9.5,
                        color: textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                'READY →',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: accentEmerald,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Direct Text Edit Dialog for Any Section Callout or Row ──────────────────
  void _showDirectSectionTextEditDialog({
    required String title,
    required String initialText,
    required ValueChanged<String> onSave,
  }) {
    final controller = TextEditingController(text: initialText);
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: bgSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: borderBright),
          ),
          title: Text(
            'Edit $title',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: textPrimary,
            ),
          ),
          content: SizedBox(
            width: 480,
            child: TextField(
              controller: controller,
              autofocus: true,
              maxLines: 3,
              minLines: 1,
              style: GoogleFonts.inter(fontSize: 13.5, color: textPrimary),
              decoration: InputDecoration(
                filled: true,
                fillColor: bgRecessed,
                hintText: 'Enter $title...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: borderSubtle),
                ),
              ),
              onSubmitted: (val) {
                final trimmed = val.trim();
                if (trimmed.isNotEmpty) onSave(trimmed);
                Navigator.of(ctx).pop();
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(
                'Cancel',
                style: GoogleFonts.inter(fontSize: 12, color: textSecondary),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: focalAccent,
                foregroundColor: focalAccentFg,
                elevation: 0,
              ),
              onPressed: () {
                final trimmed = controller.text.trim();
                if (trimmed.isNotEmpty) onSave(trimmed);
                Navigator.of(ctx).pop();
              },
              child: Text(
                'Save',
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        );
      },
    );
  }

  // ── Steps `01`–`09`: De-Boxed Full-Width Single-Section Workspace ──────────
  Widget _buildFocusedSectionWorkspace(ProjectConceptBlueprint draft, int sectionIdx) {
    final sec = _sections[sectionIdx];
    final agentNote = _agentNotesBySection[sectionIdx];
    final stage1Interventions = widget.workbench.stage1Interventions;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final intervention in stage1Interventions.take(1)) ...[
          Container(
            key: const ValueKey('stage1_intervention_banner'),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: bgSurface,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(
                color: (intervention.severity == 'crimson'
                        ? accentCrimson
                        : accentAmber)
                    .withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: (intervention.severity == 'crimson'
                            ? accentCrimson
                            : accentAmber)
                        .withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    intervention.badge,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: intervention.severity == 'crimson'
                          ? accentCrimson
                          : accentAmber,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${intervention.title} — ${intervention.reason}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      color: textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                InkWell(
                  key: const ValueKey('stage1_apply_intervention_btn'),
                  onTap: () => widget.workbench.applyAgentIntervention(intervention),
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: (intervention.severity == 'crimson'
                              ? accentCrimson
                              : accentAmber)
                          .withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: (intervention.severity == 'crimson'
                                ? accentCrimson
                                : accentAmber)
                            .withValues(alpha: 0.55),
                      ),
                    ),
                    child: Text(
                      intervention.actionLabel,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        color: intervention.severity == 'crimson'
                            ? accentCrimson
                            : accentAmber,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        // SECTION 1: DE-BOXED EDITORIAL ARTIFACT SECTION WORKSPACE
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: borderSubtle),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    runSpacing: 8,
                    spacing: 12,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'SECTION ${sec.numLabel} / 08',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                              color: accentCyan,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '· ${sec.shortTitle.toUpperCase()}',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                              color: textSecondary,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.edit_outlined,
                            size: 11,
                            color: textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Click any item below to edit directly',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        sec.numLabel,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: accentCyan,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          sec.title,
                          style: AppTheme.displayFont(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                            color: textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    sec.purpose,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Full-Width Editorial Artifact Content (No Outer 4-Sided Box)
            _buildSectionContentWidget(draft, sectionIdx),
          ],
        ),

        const SizedBox(height: 16),

        // SECTION 2: BOXLESS AGENT OPTIONS (Top Hairline Divider + Listed Option Rows)
        Container(
          padding: const EdgeInsets.only(top: 12),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: borderSubtle),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: borderSubtle),
                  ),
                ),
                child: Row(
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: accentCyan,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'AGENT · ${widget.workbench.conversationModel.toUpperCase()}',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                            color: accentCyan,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        sec.question,
                        style: GoogleFonts.inter(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: textPrimary,
                        ),
                      ),
                    ),
                    if (sec.isMultiSelect) ...[
                      const SizedBox(width: 8),
                      Container(
                        key: ValueKey('multi_select_badge_$sectionIdx'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        child: Text(
                          '+ / ✓ MULTI-SELECT · ADD ANY',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            color: accentEmerald,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 8),
                    InkWell(
                      key: const ValueKey('regenerate_section_options_btn'),
                      onTap: () {
                        setState(() {
                          _selectedOptionBySection.remove(sectionIdx);
                          _selectedOptionsBySection.remove(sectionIdx);
                        });
                        widget.workbench.regenerateStage1SectionOptions(
                          sec.optionKey,
                        );
                      },
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        child: Text(
                          '↻ Refresh Options',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Vertical Listed Option Rows (Full-Width, Hairline-Divided)
              Builder(
                builder: (context) {
                  final options = _optionsForSection(draft, sectionIdx);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (int optIdx = 0; optIdx < options.length; optIdx++)
                        _buildAgentOptionCard(
                          draft: draft,
                          sectionIdx: sectionIdx,
                          optIdx: optIdx,
                          label: options[optIdx],
                          isSelected: _isSectionOptionSelected(sectionIdx, optIdx),
                        ),
                    ],
                  );
                },
              ),

              if (agentNote != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(color: accentEmerald, width: 2),
                    ),
                  ),
                  child: Text(
                    agentNote,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      color: textSecondary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ── Sticky Bottom Studio Dock (Steps `01`–`09` + Step `10 Full Review`) ─────
  Widget _buildConceptStickyBottomDock(ProjectConceptBlueprint draft) {
    final isFullReview = _currentStep >= _sections.length;
    if (isFullReview) {
      return Container(
        key: const ValueKey('concept_sticky_bottom_dock'),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: bgSurface,
          border: Border(top: BorderSide(color: borderBright)),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1160),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: 10,
              spacing: 16,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton(
                      onPressed: () => _goToStep(_sections.length - 1),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: textPrimary,
                        backgroundColor: bgRecessed,
                        side: BorderSide(color: borderSubtle),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                      child: Text(
                        '← Back to Section 08',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: accentEmerald.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: accentEmerald.withValues(alpha: 0.45),
                        ),
                      ),
                      child: Text(
                        'ALL 8 SECTIONS READY',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: accentEmerald,
                        ),
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _copyBlueprintAsMarkdown(draft),
                      icon: const Icon(Icons.copy_rounded, size: 14),
                      label: Text(
                        'Copy Markdown',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: textPrimary,
                        backgroundColor: bgRecessed,
                        side: BorderSide(color: borderSubtle),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _buildPrimaryApproveButton(
                      key: const ValueKey('approve_concept_plan_release_btn'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    final sectionIdx = _currentStep;
    final sec = _sections[sectionIdx];
    final nextTitle = sectionIdx + 1 < _sections.length
        ? 'Next: ${_sections[sectionIdx + 1].shortTitle} →'
        : 'Next: Full Blueprint Review →';

    return Container(
      key: const ValueKey('concept_sticky_bottom_dock'),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: bgSurface,
        border: Border(top: BorderSide(color: borderBright)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1160),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // [ASK AGENT] Input Bar
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: bgRecessed,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: borderSubtle),
                      ),
                      child: Row(
                        children: [
                          Text(
                            '[ASK AGENT]',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: textSecondary,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Focus(
                              onKeyEvent: (node, event) =>
                                  _handleMultilinePitchKeyEvent(
                                event,
                                _agentPromptController,
                                onSubmit: () =>
                                    _submitSectionPrompt(draft, sectionIdx),
                              ),
                              child: TextField(
                                key: const ValueKey('concept_chat_input_field'),
                                controller: _agentPromptController,
                                focusNode: _conceptChatFocusNode,
                                minLines: 1,
                                maxLines: null,
                                keyboardType: TextInputType.multiline,
                                textInputAction: TextInputAction.newline,
                                inputFormatters: const [
                                  MaxColumnLineWrapFormatter(
                                    maxCharsPerLine: 70,
                                  ),
                                ],
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  height: 1.4,
                                  color: textPrimary,
                                ),
                                decoration: InputDecoration(
                                  hintMaxLines: 1,
                                  hintText:
                                      'Tell the Agent how to change or expand ${sec.title} (70 chars/line · Shift+Enter for new line)...',
                                  hintStyle: GoogleFonts.inter(
                                    fontSize: 12.5,
                                    color: textMuted,
                                  ),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  filled: false,
                                  isDense: true,
                                  contentPadding:
                                      const EdgeInsets.symmetric(vertical: 8),
                                ),
                                onSubmitted: (_) =>
                                    _submitSectionPrompt(draft, sectionIdx),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: widget.workbench.isAgentBusy
                        ? null
                        : () => _submitSectionPrompt(draft, sectionIdx),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: textPrimary,
                      backgroundColor: bgRecessed,
                      side: BorderSide(color: borderBright),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                    child: Text(
                      widget.workbench.isAgentBusy ? 'Updating...' : 'Send to Agent',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Step Navigation Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  OutlinedButton(
                    onPressed: sectionIdx == 0
                        ? null
                        : () => _goToStep(sectionIdx - 1),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: textPrimary,
                      backgroundColor: bgRecessed,
                      side: BorderSide(color: borderSubtle),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                    child: Text(
                      '← Previous Section',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      OutlinedButton(
                        key: const ValueKey('skip_to_full_review_btn'),
                        onPressed: () => _goToStep(_sections.length),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: textPrimary,
                          backgroundColor: bgRecessed,
                          side: BorderSide(
                            color: accentAmber.withValues(alpha: 0.55),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 11,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                        child: Text(
                          'Review Full Blueprint ◫',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        key: const ValueKey('next_section_btn'),
                        onPressed: () => _goToStep(sectionIdx + 1),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: focalAccent,
                          foregroundColor: focalAccentFg,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 11,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                        child: Text(
                          nextTitle,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAgentOptionCard({
    required ProjectConceptBlueprint draft,
    required int sectionIdx,
    required int optIdx,
    required String label,
    required bool isSelected,
  }) {
    final parsed = _splitOptionIntoCardTitleAndBody(label, sectionIdx, optIdx);
    final sec = _sections[sectionIdx];
    final isMulti = sec.isMultiSelect;
    final activeBarColor = isMulti ? accentEmerald : accentCyan;

    return Material(
      color: isSelected ? bgHover.withValues(alpha: 0.45) : Colors.transparent,
      child: InkWell(
        key: ValueKey('agent_option_card_${sectionIdx}_$optIdx'),
        onTap: () => _selectSectionOption(draft, sectionIdx, optIdx),
        child: Container(
          padding: EdgeInsets.fromLTRB(isSelected ? 13 : 8, 10, 8, 10),
          decoration: BoxDecoration(
            border: Border(
              left: isSelected
                  ? BorderSide(color: activeBarColor, width: 3)
                  : BorderSide.none,
              bottom: BorderSide(color: borderSubtle),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Unified Selection Indicator: Radio Circle for single-select, Check/Add for multi-select
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: isMulti
                    ? Icon(
                        isSelected
                            ? Icons.check_circle_rounded
                            : Icons.add_circle_outline_rounded,
                        size: 16,
                        color: isSelected ? accentEmerald : textMuted,
                      )
                    : Container(
                        width: 15,
                        height: 15,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSelected ? accentCyan : Colors.transparent,
                          border: Border.all(
                            color: isSelected ? accentCyan : textMuted,
                            width: 1.4,
                          ),
                        ),
                        child: isSelected
                            ? Container(
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: bgBase,
                                ),
                              )
                            : null,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 10,
                      runSpacing: 4,
                      children: [
                        Text(
                          parsed.title,
                          style: AppTheme.displayFont(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: textPrimary,
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              optIdx == 0 ? 'RECOMMENDED' : 'OPTION 0${optIdx + 1}',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                color: optIdx == 0 ? accentCyan : textSecondary,
                              ),
                            ),
                            if (isMulti) ...[
                              const SizedBox(width: 10),
                              Text(
                                isSelected
                                    ? '✓ Added to ${sec.shortTitle}'
                                    : '+ Add to ${sec.shortTitle}',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  color: isSelected
                                      ? accentEmerald
                                      : textSecondary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      parsed.description,
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        height: 1.42,
                        color: textSecondary,
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

  // ── 6 Distinct Structural Section Layouts ──────────────────────────────────
  Widget _buildSectionContentWidget(
    ProjectConceptBlueprint draft,
    int sectionIdx, {
    bool isReadOnlySummary = false,
  }) {
    switch (sectionIdx) {
      case 0: // 01 Goal — Option A: Strategy Badge + Bold 1-Sentence Headline + 3 Scannable Clause Cards
        return _buildStructuredGoalSection(
          draft,
          onEditTap: isReadOnlySummary
              ? null
              : () => _showDirectSectionTextEditDialog(
                    title: '01 Goal',
                    initialText: ProjectConceptBlueprint.sanitizeGoalText(draft.goal),
                    onSave: (val) => widget.workbench.updateConceptDraft(
                      (d) => d.goal = ProjectConceptBlueprint.sanitizeGoalText(val),
                    ),
                  ),
        );
      case 1: // 02 Game Spec — 2×2 Key-Value Spec Grid (Direct Click-to-Edit)
        return _buildKvSpecGrid(
          isGameSpec: true,
          keys: const ['CAMERA VIEW', 'CONTROLS', 'PLAYER MODE', 'ARENA STRUCTURE'],
          values: draft.gameSpec,
        );
      case 2: // 03 Tech Spec — 2×2 Key-Value Spec Grid (Direct Click-to-Edit)
        return _buildKvSpecGrid(
          isGameSpec: false,
          keys: const ['ENGINE', 'PLATFORM', 'ASSET PIPELINE', 'NETWORK / SAVE'],
          values: draft.techSpec,
        );
      case 3: // 04 Design Pillars — 3 Side-by-Side Pillar Playing Cards + Inline Add/Remove
        return _buildDesignPillarCards(draft, isReadOnlySummary: isReadOnlySummary);
      case 4: // 05 Trade-Offs — Split X OVER Y Comparison Bars + Inline Add/Remove
        return _buildTradeOffSplitBars(
          draft.tradeOffs,
          onEditItem: (i, val) => widget.workbench.updateConceptDraft((d) {
            final next = List<String>.from(d.tradeOffs);
            next[i] = val;
            d.tradeOffs = next;
          }),
          onDeleteItem: (!isReadOnlySummary && draft.tradeOffs.length > 1)
              ? (i) => widget.workbench.updateConceptDraft((d) {
                    final next = List<String>.from(d.tradeOffs)..removeAt(i);
                    d.tradeOffs = next;
                  })
              : null,
          onAddItem: isReadOnlySummary
              ? null
              : () => _showDirectSectionTextEditDialog(
                    title: 'Add Trade-Off (X over Y)',
                    initialText: 'Immediate arcade responsiveness over complex simulation depth',
                    onSave: (val) => widget.workbench.updateConceptDraft((d) {
                      d.tradeOffs = [...d.tradeOffs, val];
                    }),
                  ),
        );
      case 5: // 06 Core Loop — Connected Beat Cycle Rows + Inline Add/Remove/Reorder
        return _buildIndexedRows(
          prefix: 'BEAT',
          items: draft.coreLoopBeats,
          isCoreLoop: true,
          onEditItem: (i, val) => widget.workbench.updateConceptDraft((d) {
            final next = List<String>.from(d.coreLoopBeats);
            next[i] = val;
            d.coreLoopBeats = next;
          }),
          onReorderItem: (!isReadOnlySummary && draft.coreLoopBeats.length > 1)
              ? (oldIdx, newIdx) => widget.workbench.updateConceptDraft((d) {
                    if (newIdx < 0 || newIdx >= d.coreLoopBeats.length) return;
                    final next = List<String>.from(d.coreLoopBeats);
                    final moved = next.removeAt(oldIdx);
                    next.insert(newIdx, moved);
                    d.coreLoopBeats = next;
                  })
              : null,
          onDeleteItem: (!isReadOnlySummary && draft.coreLoopBeats.length > 1)
              ? (i) => widget.workbench.updateConceptDraft((d) {
                    final next = List<String>.from(d.coreLoopBeats)..removeAt(i);
                    d.coreLoopBeats = next;
                  })
              : null,
          onAddItem: isReadOnlySummary
              ? null
              : () => _showDirectSectionTextEditDialog(
                    title: 'Add Core Loop Beat',
                    initialText: 'Extract & Upgrade: Spend gathered resources on one immediate loadout upgrade.',
                    onSave: (val) => widget.workbench.updateConceptDraft((d) {
                      d.coreLoopBeats = [...d.coreLoopBeats, val];
                    }),
                  ),
        );
      case 6: // 07 Out of Scope — 2-Column Recessed Guardrail Grid + Inline Add/Remove
        return _buildCutGuardrailChips(
          draft.exclusions,
          onEditItem: (i, val) => widget.workbench.updateConceptDraft((d) {
            final next = List<String>.from(d.exclusions);
            next[i] = val;
            d.exclusions = next;
          }),
          onDeleteItem: (!isReadOnlySummary && draft.exclusions.length > 1)
              ? (i) => widget.workbench.updateConceptDraft((d) {
                    final next = List<String>.from(d.exclusions)..removeAt(i);
                    d.exclusions = next;
                  })
              : null,
          onAddItem: isReadOnlySummary
              ? null
              : () => _showDirectSectionTextEditDialog(
                    title: 'Add Out of Scope Exclusion (Cut)',
                    initialText: 'No procedural world generation or multiplayer networking in v0.1',
                    onSave: (val) => widget.workbench.updateConceptDraft((d) {
                      d.exclusions = [...d.exclusions, val];
                    }),
                  ),
        );
      case 7: // 08 Done When — Acceptance Callout Statement with Highlighted Playtest Metrics
        return _buildCalloutStatement(
          draft.doneWhen,
          highlightMetrics: true,
          onEditTap: () => _showDirectSectionTextEditDialog(
            title: '08 Done When',
            initialText: draft.doneWhen,
            onSave: (val) => widget.workbench.updateConceptDraft((d) => d.doneWhen = val),
          ),
        );
      case 8: // 09 Prototype Release — Phase 1 Active Target + 3 Horizontal Locked Phase Cards
      default:
        return _buildReleaseTrainPipeline(
          draft,
          isReadOnlySummary: isReadOnlySummary,
        );
    }
  }

  Widget _buildStructuredGoalSection(
    ProjectConceptBlueprint draft, {
    VoidCallback? onEditTap,
  }) {
    final sanitized = ProjectConceptBlueprint.sanitizeGoalText(draft.goal);
    final colonIdx = sanitized.indexOf(':');
    String strategyBadge = 'PROTOTYPE TARGET';
    String headline = sanitized;

    if (colonIdx > 0 && colonIdx <= 48 && colonIdx < sanitized.length - 1) {
      strategyBadge = sanitized.substring(0, colonIdx).trim().toUpperCase();
      headline = sanitized.substring(colonIdx + 1).trim();
    } else {
      final selectedOptIdx = _selectedOptionBySection[0];
      final goalOpts = draft.sectionOptions['goal'] ?? const <String>[];
      if (selectedOptIdx != null &&
          selectedOptIdx >= 0 &&
          selectedOptIdx < goalOpts.length) {
        final opt = goalOpts[selectedOptIdx];
        final optColon = opt.indexOf(':');
        if (optColon > 0 && optColon <= 48) {
          strategyBadge = opt.substring(0, optColon).trim().toUpperCase();
        }
      }
    }

    final clauses = _extractGoalClauses(headline, draft.coreLoopBeats);
    final clauseAccents = <Color>[accentCyan, accentAmber, accentEmerald];

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const ValueKey('stage1_goal_structured_card'),
        onTap: onEditTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.only(left: 16, top: 8, bottom: 8, right: 12),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: accentCyan,
                width: 3,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Strategy Badge Row + Click to Edit hint
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: accentCyan.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(
                        color: accentCyan.withValues(alpha: 0.30),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: accentCyan,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          strategyBadge,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            color: accentCyan,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  if (onEditTap != null)
                    Text(
                      '✎ Click to edit',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        color: textMuted,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              // 2. Bold 1-Sentence Headline
              Text(
                headline,
                style: GoogleFonts.inter(
                  fontSize: 16.5,
                  fontWeight: FontWeight.w700,
                  height: 1.45,
                  letterSpacing: -0.2,
                  color: textPrimary,
                ),
              ),
              if (clauses.isNotEmpty) ...[
                const SizedBox(height: 14),
                // 3. 3 Scannable Clause Cards (01, 02, 03)
                LayoutBuilder(
                  builder: (context, constraints) {
                    final useRow = constraints.maxWidth >= 520;
                    final cards = List<Widget>.generate(clauses.length, (i) {
                      final clause = clauses[i];
                      final accent = clauseAccents[i % clauseAccents.length];
                      final numTag = (i + 1).toString().padLeft(2, '0');
                      return Container(
                        key: ValueKey('stage1_goal_clause_card_$i'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: bgRecessed,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: borderSubtle),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$numTag · ${clause.title.toUpperCase()}',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                                color: accent,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              clause.body,
                              style: GoogleFonts.inter(
                                fontSize: 12.5,
                                height: 1.42,
                                color: textSecondary,
                              ),
                            ),
                          ],
                        ),
                      );
                    });

                    if (useRow) {
                      return IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var i = 0; i < cards.length; i++) ...[
                              if (i > 0) const SizedBox(width: 10),
                              Expanded(child: cards[i]),
                            ],
                          ],
                        ),
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < cards.length; i++) ...[
                          if (i > 0) const SizedBox(height: 8),
                          cards[i],
                        ],
                      ],
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<({String title, String body})> _extractGoalClauses(
    String headline,
    List<String> coreLoopBeats,
  ) {
    // 1. Check if headline has a 3-part action series after "where you "
    final lower = headline.toLowerCase();
    final whereIdx = lower.indexOf('where you ');
    if (whereIdx != -1) {
      final afterWhere = headline.substring(whereIdx + 'where you '.length).trim();
      final parts = afterWhere
          .split(RegExp(r',\s*and\s+|,\s+'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (parts.length >= 3) {
        return List.generate(3, (i) {
          final rawClause = parts[i];
          final formattedClause = rawClause[0].toUpperCase() + rawClause.substring(1);
          final body = formattedClause.endsWith('.')
              ? formattedClause
              : '$formattedClause.';
          // Pair with Core Loop Beat title when available, else derive a 2-3 word label
          String title = _deriveShortClauseLabel(rawClause, i);
          if (i < coreLoopBeats.length && coreLoopBeats[i].contains(':')) {
            final beatTitle = coreLoopBeats[i].split(':').first.trim();
            if (beatTitle.isNotEmpty && beatTitle.length <= 24) {
              title = beatTitle;
            }
          }
          return (title: title, body: body);
        });
      }
    }

    // 2. Otherwise pull the top 3 Core Loop Beats (`Title: Action description`)
    final result = <({String title, String body})>[];
    for (var i = 0; i < coreLoopBeats.length && result.length < 3; i++) {
      final beat = coreLoopBeats[i].trim();
      if (beat.isEmpty) continue;
      final colon = beat.indexOf(':');
      if (colon > 0 && colon < beat.length - 1) {
        result.add((
          title: beat.substring(0, colon).trim(),
          body: beat.substring(colon + 1).trim(),
        ));
      } else {
        result.add((
          title: 'Step 0${i + 1}',
          body: beat,
        ));
      }
    }
    return result;
  }

  String _deriveShortClauseLabel(String clause, int index) {
    final lower = clause.toLowerCase();
    if (lower.contains('plant') && lower.contains('harvest')) {
      return 'Plant & Harvest';
    }
    if (lower.contains('sell') || lower.contains('ammo') || lower.contains('load')) {
      return 'Load or Sell';
    }
    if (lower.contains('wave') || lower.contains('arena')) {
      return 'Arena Run';
    }
    final words = clause
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(3)
        .toList();
    if (words.isEmpty) return 'Phase 0${index + 1}';
    return words.join(' ');
  }

  Widget _buildCalloutStatement(
    String statement, {
    required bool highlightMetrics,
    VoidCallback? onEditTap,
  }) {
    final barColor = highlightMetrics ? accentEmerald : accentCyan;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onEditTap,
        child: Container(
          padding: const EdgeInsets.only(left: 16, top: 8, bottom: 8, right: 12),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: barColor,
                width: 3,
              ),
            ),
          ),
          child: highlightMetrics
              ? buildMetricHighlightedRichText(
                  statement,
                  usePill: true,
                  fontSize: 15,
                  height: 1.58,
                )
              : Text(
                  statement,
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    height: 1.58,
                    color: textPrimary,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildKvSpecGrid({
    required bool isGameSpec,
    required List<String> keys,
    required List<String> values,
  }) {
    final pairs = List.generate(keys.length, (i) {
      final val = i < values.length ? values[i] : '—';
      return MapEntry(keys[i], val);
    });

    return Container(
      decoration: BoxDecoration(
        color: bgRecessed,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _buildKvCell(
                    isGameSpec: isGameSpec,
                    cellIndex: 0,
                    k: pairs[0].key,
                    v: pairs[0].value,
                    rightBorder: true,
                    bottomBorder: true,
                  ),
                ),
                Expanded(
                  child: _buildKvCell(
                    isGameSpec: isGameSpec,
                    cellIndex: 1,
                    k: pairs[1].key,
                    v: pairs[1].value,
                    rightBorder: false,
                    bottomBorder: true,
                  ),
                ),
              ],
            ),
          ),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _buildKvCell(
                    isGameSpec: isGameSpec,
                    cellIndex: 2,
                    k: pairs[2].key,
                    v: pairs[2].value,
                    rightBorder: true,
                    bottomBorder: false,
                  ),
                ),
                Expanded(
                  child: _buildKvCell(
                    isGameSpec: isGameSpec,
                    cellIndex: 3,
                    k: pairs[3].key,
                    v: pairs[3].value,
                    rightBorder: false,
                    bottomBorder: false,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKvCell({
    required bool isGameSpec,
    required int cellIndex,
    required String k,
    required String v,
    required bool rightBorder,
    required bool bottomBorder,
  }) {
    return Material(
      color: bgSurface,
      child: InkWell(
        onTap: () => _showDirectKvEditDialog(
          isGameSpec: isGameSpec,
          cellIndex: cellIndex,
          label: k,
          currentValue: v,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              right: rightBorder ? BorderSide(color: borderSubtle) : BorderSide.none,
              bottom: bottomBorder ? BorderSide(color: borderSubtle) : BorderSide.none,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    k,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: textSecondary.withValues(alpha: 0.85),
                    ),
                  ),
                  Icon(
                    Icons.edit_outlined,
                    size: 11,
                    color: textMuted.withValues(alpha: 0.65),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                v,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Splits `"Lead-In Label: Description text"` so the lead-in before `:` is bold & bright
  /// and the description after `:` is slightly muted for instant scanability.
  Widget _buildFormattedLeadInText(String rawText) {
    final colonIdx = rawText.indexOf(':');
    if (colonIdx <= 0 || colonIdx >= rawText.length - 1) {
      return Text(
        rawText,
        style: GoogleFonts.inter(
          fontSize: 13.5,
          height: 1.45,
          color: textPrimary,
        ),
      );
    }

    final leadIn = rawText.substring(0, colonIdx + 1);
    final rest = rawText.substring(colonIdx + 1);

    return RichText(
      text: TextSpan(
        style: GoogleFonts.inter(
          fontSize: 13.5,
          height: 1.45,
        ),
        children: [
          TextSpan(
            text: leadIn,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: textPrimary,
            ),
          ),
          TextSpan(
            text: rest,
            style: TextStyle(
              fontWeight: FontWeight.w400,
              color: textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  // ── Section 04: Open Editorial Hairline-Divided Design Pillars + Inline Add/Delete ──
  Widget _buildDesignPillarCards(
    ProjectConceptBlueprint draft, {
    bool isReadOnlySummary = false,
  }) {
    final pillars = draft.designPillars;

    Widget buildPillarRow(int idx) {
      final raw = pillars[idx];
      final parsedPillar =
          ProjectConceptBlueprint.parsePillarTitleAndBody(raw, idx);
      final String title = parsedPillar.title;
      final String body = parsedPillar.body;

      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showDirectSectionTextEditDialog(
            title: 'P·${(idx + 1).toString().padLeft(2, '0')} Design Pillar',
            initialText: '${parsedPillar.title}: ${parsedPillar.body}',
            onSave: (val) => widget.workbench.updateConceptDraft((d) {
              final next = List<String>.from(d.designPillars);
              next[idx] = ProjectConceptBlueprint.ensureNamedPillar(val, idx);
              d.designPillars = next;
            }),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: borderSubtle),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 48,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'P·${(idx + 1).toString().padLeft(2, '0')}',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: accentCyan,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppTheme.displayFont(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        body,
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          height: 1.42,
                          color: textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isReadOnlySummary && pillars.length > 1) ...[
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () => widget.workbench.updateConceptDraft((d) {
                      final next = List<String>.from(d.designPillars)..removeAt(idx);
                      d.designPillars = next;
                    }),
                    borderRadius: BorderRadius.circular(3),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      child: Text(
                        '×',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: textMuted,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < pillars.length; i++) buildPillarRow(i),
        if (!isReadOnlySummary) ...[
          const SizedBox(height: 10),
          _buildInlineAddBar(
            label: '+ Add a custom Design Pillar...',
            onTap: () => _showDirectSectionTextEditDialog(
              title: 'Add Design Pillar',
              initialText: 'Every Choice Echoes: Player actions leave visible feedback in the arena.',
              onSave: (val) => widget.workbench.updateConceptDraft((d) {
                d.designPillars = [
                  ...d.designPillars,
                  ProjectConceptBlueprint.ensureNamedPillar(
                    val,
                    d.designPillars.length,
                  ),
                ];
              }),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildInlineAddBar({
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: bgRecessed.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(5),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(5),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: borderSubtle),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: textMuted,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: bgSurface,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: borderBright),
                ),
                child: Text(
                  '+ Add',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIndexedRows({
    required String prefix,
    required List<String> items,
    required bool isCoreLoop,
    void Function(int index, String newValue)? onEditItem,
    void Function(int oldIndex, int newIndex)? onReorderItem,
    void Function(int index)? onDeleteItem,
    VoidCallback? onAddItem,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < items.length; i++) ...[
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onEditItem == null
                  ? null
                  : () => _showDirectSectionTextEditDialog(
                        title: '$prefix·${(i + 1).toString().padLeft(2, '0')}',
                        initialText: items[i],
                        onSave: (val) => onEditItem(i, val),
                      ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 13),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: borderSubtle),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 68,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 1.5),
                        child: Text(
                          '$prefix·${(i + 1).toString().padLeft(2, '0')}',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: accentCyan,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildFormattedLeadInText(items[i]),
                    ),
                    if (onReorderItem != null && items.length > 1) ...[
                      const SizedBox(width: 6),
                      InkWell(
                        key: ValueKey('core_loop_move_up_$i'),
                        onTap: i > 0 ? () => onReorderItem(i, i - 1) : null,
                        borderRadius: BorderRadius.circular(3),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                          child: Text(
                            '↑',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: i > 0
                                  ? textSecondary
                                  : textMuted.withValues(alpha: 0.3),
                            ),
                          ),
                        ),
                      ),
                      InkWell(
                        key: ValueKey('core_loop_move_down_$i'),
                        onTap: i < items.length - 1
                            ? () => onReorderItem(i, i + 1)
                            : null,
                        borderRadius: BorderRadius.circular(3),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                          child: Text(
                            '↓',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: i < items.length - 1
                                  ? textSecondary
                                  : textMuted.withValues(alpha: 0.3),
                            ),
                          ),
                        ),
                      ),
                    ],
                    if (onDeleteItem != null) ...[
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: () => onDeleteItem(i),
                        borderRadius: BorderRadius.circular(3),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          child: Text(
                            '×',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: textMuted,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
        if (isCoreLoop && items.isNotEmpty) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Text(
                '↺ Loops back to BEAT·01 (Continuous Cycle)',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: accentCyan,
                ),
              ),
            ),
          ),
        ],
        if (onAddItem != null) ...[
          const SizedBox(height: 10),
          _buildInlineAddBar(
            label: isCoreLoop
                ? '+ Add a custom Core Loop Beat...'
                : '+ Add item...',
            onTap: onAddItem,
          ),
        ],
      ],
    );
  }

  Widget _buildTradeOffSplitBars(
    List<String> tradeOffs, {
    void Function(int index, String newValue)? onEditItem,
    void Function(int index)? onDeleteItem,
    VoidCallback? onAddItem,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < tradeOffs.length; i++) ...[
          _buildSingleTradeOffBar(
            tradeOffs[i],
            onTap: onEditItem == null
                ? null
                : () => _showDirectSectionTextEditDialog(
                      title: 'Trade-Off #${i + 1} (X over Y)',
                      initialText: tradeOffs[i],
                      onSave: (val) => onEditItem(i, val),
                    ),
            onDelete: onDeleteItem == null ? null : () => onDeleteItem(i),
          ),
        ],
        if (onAddItem != null) ...[
          const SizedBox(height: 10),
          _buildInlineAddBar(
            label: '+ Add a custom Trade-Off (X over Y)...',
            onTap: onAddItem,
          ),
        ],
      ],
    );
  }

  Widget _buildSingleTradeOffBar(
    String rawRule, {
    VoidCallback? onTap,
    VoidCallback? onDelete,
  }) {
    final clean = rawRule.replaceFirst(RegExp(r'^Prioritize\s+', caseSensitive: false), '');
    final parts = clean.split(RegExp(r'\s+over\s+', caseSensitive: false));
    final winText = parts.isNotEmpty ? parts[0].trim() : clean;
    final loseText = parts.length > 1 ? parts.sublist(1).join(' over ').trim() : 'secondary complexity';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 13),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: borderSubtle),
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 58,
                child: Text(
                  '✓ WIN',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: accentEmerald,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  winText,
                  textAlign: TextAlign.right,
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Text(
                'OVER',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: textSecondary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  loseText,
                  textAlign: TextAlign.left,
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    color: textSecondary.withValues(alpha: 0.78),
                    decoration: TextDecoration.lineThrough,
                    decorationColor: accentCrimson.withValues(alpha: 0.70),
                    decorationThickness: 1.6,
                  ),
                ),
              ),
              if (onDelete != null) ...[
                const SizedBox(width: 8),
                InkWell(
                  onTap: onDelete,
                  borderRadius: BorderRadius.circular(3),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    child: Text(
                      '×',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: textMuted,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCutGuardrailChips(
    List<String> exclusions, {
    void Function(int index, String newValue)? onEditItem,
    void Function(int index)? onDeleteItem,
    VoidCallback? onAddItem,
  }) {
    Widget buildExclusionRow(int idx) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onEditItem == null
              ? null
              : () => _showDirectSectionTextEditDialog(
                    title: 'Out of Scope Exclusion #${idx + 1}',
                    initialText: exclusions[idx],
                    onSave: (val) => onEditItem(idx, val),
                  ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 11),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: borderSubtle),
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 52,
                  child: Text(
                    '✕ CUT',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: accentCrimson,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    exclusions[idx],
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: textSecondary.withValues(alpha: 0.9),
                    ),
                  ),
                ),
                if (onDeleteItem != null) ...[
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: () => onDeleteItem(idx),
                    borderRadius: BorderRadius.circular(3),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      child: Text(
                        '×',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: textMuted,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < exclusions.length; i++) buildExclusionRow(i),
        if (onAddItem != null) ...[
          const SizedBox(height: 10),
          _buildInlineAddBar(
            label: '+ Add an Out of Scope exclusion (Cut)...',
            onTap: onAddItem,
          ),
        ],
      ],
    );
  }

  Widget _buildReleaseTrainPipeline(
    ProjectConceptBlueprint draft, {
    bool isReadOnlySummary = false,
  }) {
    final releases = draft.releaseTrainTitles;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: borderSubtle)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'PROGRESSIVE AI RELEASE TRACK (v0.1 → v0.2 → v0.3+)',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: textPrimary,
                ),
              ),
              Text(
                'ACTIVE TARGET · v0.1',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  color: accentCyan,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Approving this Concept immediately builds v0.1 in the Workbench. For v0.2 → v0.3+, the Agentic AI guides which existing features to Upgrade and which New Systems to add next.',
          style: GoogleFonts.inter(
            fontSize: 12.5,
            color: textSecondary,
          ),
        ),
        const SizedBox(height: 10),
        for (int i = 0; i < releases.length; i++)
          _buildReleaseStepCard(
            releases[i],
            draft: draft,
            isFirst: i == 0,
            index: i,
            onTap: () => _showDirectSectionTextEditDialog(
              title: 'Release v0.${i + 1}',
              initialText: releases[i],
              onSave: (val) => widget.workbench.updateConceptDraft((d) {
                final next = List<String>.from(d.releaseTrainTitles);
                next[i] = val;
                d.releaseTrainTitles = next;
              }),
            ),
          ),
        if (!isReadOnlySummary) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: accentEmerald, width: 2),
                bottom: BorderSide(color: borderSubtle),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 116,
                  child: Text(
                    'v0.2 → v0.3+ · AI',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      color: accentEmerald,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Progressive Agentic Releases Inside the Workbench',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Click "+ New Release (v0.2) ✦" in the Workbench at any time—the Agent recommends which existing features to Upgrade (UPGRADE), which New Features (NEW) to add, and what direction to take next.',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          height: 1.4,
                          color: textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildReleaseStepCard(
    String fullTitle, {
    required ProjectConceptBlueprint draft,
    required bool isFirst,
    required int index,
    VoidCallback? onTap,
  }) {
    final verTag = isFirst ? 'v0.1 · ACTIVE TARGET' : 'v0.${index + 1} · QUEUED';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.fromLTRB(isFirst ? 14 : 8, 12, 8, 12),
          decoration: BoxDecoration(
            border: Border(
              left: isFirst
                  ? BorderSide(color: accentAmber, width: 3)
                  : BorderSide.none,
              bottom: BorderSide(color: borderSubtle),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    verTag,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: isFirst
                          ? accentAmber
                          : textSecondary.withValues(alpha: 0.85),
                    ),
                  ),
                  Text(
                    isFirst ? 'READY TO PLAN →' : 'QUEUED',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      color: isFirst ? accentAmber : textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                fullTitle,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: isFirst ? textPrimary : textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Builder(
                builder: (context) {
                  final totalBeats = draft.coreLoopBeats.length;
                  final isSplitTrain = draft.releaseTrainTitles.length > 1;
                  final halfCount = (totalBeats + 1) ~/ 2;
                  final scopeCaption = isSplitTrain
                      ? (index == 0
                          ? 'Part 1 Scope: Core Loop Beats 1–$halfCount (Controls & Primary Mechanics)'
                          : 'Part 2 Scope: Core Loop Beats ${halfCount + 1}–$totalBeats (Progression & Loop Reset)')
                      : 'Scope: $totalBeats Core Loop Beats · ${draft.gameSpec.length} Game Specs · ${draft.designPillars.length} Design Pillars';
                  return Text(
                    scopeCaption,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      color: textSecondary.withValues(alpha: 0.85),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Step `10 · Full Review`: Boxless Single Editorial Dossier Sheet ──────────
  Widget _buildFullReviewWorkspace(ProjectConceptBlueprint draft) {
    return Container(
      key: const ValueKey('project_blueprint_card'),
      color: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Verification Header (Open Hairline Divider, No Outer Box)
          Container(
            padding: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: borderSubtle)),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: 12,
              spacing: 16,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'STEP 09 · FINAL BLUEPRINT VERIFICATION',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                        color: accentAmber,
                      ),
                    ),
                    const SizedBox(height: 4),
                    InkWell(
                      onTap: () => _promptEditProjectTitle(draft),
                      borderRadius: BorderRadius.circular(4),
                      child: Text(
                        '${draft.title} — Complete Project Concept Blueprint',
                        style: AppTheme.displayFont(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Hover any section to adjust it inline with the Agent, or click any item to edit directly.',
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        color: textSecondary,
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _copyBlueprintAsMarkdown(draft),
                      icon: const Icon(Icons.copy_rounded, size: 14),
                      label: Text(
                        'Copy Markdown',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: textPrimary,
                        backgroundColor: bgRecessed,
                        side: BorderSide(color: borderSubtle),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _buildPrimaryApproveButton(),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Open Editorial Sections (Hairline Dividers Only — No Outer Box)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 01 Goal (Full Width)
              _buildFullReviewBlock(
                draft: draft,
                sectionIdx: 0,
                child: _buildSectionContentWidget(
                  draft,
                  0,
                  isReadOnlySummary: true,
                ),
              ),

              Padding(
                padding: const EdgeInsets.symmetric(vertical: 22),
                child: Divider(height: 1, thickness: 1, color: borderSubtle),
              ),

              // 02 Game Spec + 03 Tech Spec (50/50 Side-by-Side Row with Equal Height)
              LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth < 720) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildFullReviewBlock(
                          draft: draft,
                          sectionIdx: 1,
                          child: _buildSectionContentWidget(
                            draft,
                            1,
                            isReadOnlySummary: true,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 22),
                          child: Divider(
                            height: 1,
                            thickness: 1,
                            color: borderSubtle,
                          ),
                        ),
                        _buildFullReviewBlock(
                          draft: draft,
                          sectionIdx: 2,
                          child: _buildSectionContentWidget(
                            draft,
                            2,
                            isReadOnlySummary: true,
                          ),
                        ),
                      ],
                    );
                  }
                  return IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _buildFullReviewBlock(
                            draft: draft,
                            sectionIdx: 1,
                            child: _buildSectionContentWidget(
                              draft,
                              1,
                              isReadOnlySummary: true,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: VerticalDivider(
                            width: 1,
                            thickness: 1,
                            color: borderSubtle,
                          ),
                        ),
                        Expanded(
                          child: _buildFullReviewBlock(
                            draft: draft,
                            sectionIdx: 2,
                            child: _buildSectionContentWidget(
                              draft,
                              2,
                              isReadOnlySummary: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),

              // 04 Design Pillars through 08 Done When
              for (int idx = 3; idx < _sections.length; idx++) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 22),
                  child: Divider(
                    height: 1,
                    thickness: 1,
                    color: borderSubtle,
                  ),
                ),
                _buildFullReviewBlock(
                  draft: draft,
                  sectionIdx: idx,
                  child: _buildSectionContentWidget(
                    draft,
                    idx,
                    isReadOnlySummary: true,
                  ),
                ),
              ],
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 22),
                child: Divider(
                  height: 1,
                  thickness: 1,
                  color: borderSubtle,
                ),
              ),
              _buildReleaseTrainPipeline(
                draft,
                isReadOnlySummary: true,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPrimaryApproveButton({Key? key}) {
    return ElevatedButton(
      key: key,
      onPressed: widget.workbench.isAgentBusy
          ? null
          : () => widget.workbench.approveConceptAndBuildRelease(),
      style: ElevatedButton.styleFrom(
        backgroundColor: focalAccent,
        foregroundColor: focalAccentFg,
        elevation: 0,
        padding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 14,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(color: accentAmber.withValues(alpha: 0.55)),
        ),
      ),
      child: Text(
        widget.workbench.isAgentBusy
            ? 'Building v0.1 Workbench...'
            : 'Approve & Build v0.1 →',
        style: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildFullReviewBlock({
    required ProjectConceptBlueprint draft,
    required int sectionIdx,
    required Widget child,
  }) {
    final sec = _sections[sectionIdx];
    final isHovered = _hoveredReviewSectionIdx == sectionIdx;
    final isInlineOpen = _inlineEditingSectionIdx == sectionIdx;
    final showControls = isHovered || isInlineOpen;

    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredReviewSectionIdx = sectionIdx),
      onExit: (_) {
        if (_hoveredReviewSectionIdx == sectionIdx) {
          setState(() => _hoveredReviewSectionIdx = null);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: isInlineOpen
              ? bgRecessed.withValues(alpha: 0.65)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: bgRecessed,
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(color: borderBright),
                        ),
                        child: Text(
                          sec.numLabel,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          sec.title.toUpperCase(),
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                            color: textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 140),
                  opacity: showControls ? 1.0 : 0.0,
                  child: IgnorePointer(
                    ignoring: !showControls,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        OutlinedButton(
                          onPressed: () {
                            setState(() {
                              if (_inlineEditingSectionIdx == sectionIdx) {
                                _inlineEditingSectionIdx = null;
                              } else {
                                _inlineEditingSectionIdx = sectionIdx;
                                _inlineReviewPromptController.clear();
                              }
                            });
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: isInlineOpen ? focalAccentFg : textPrimary,
                            backgroundColor: isInlineOpen ? focalAccent : bgRecessed,
                            side: BorderSide(color: borderBright),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            minimumSize: const Size(0, 28),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          child: Text(
                            isInlineOpen ? 'Close Agent Edit' : 'Edit with Agent',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        OutlinedButton(
                          onPressed: () => _goToStep(sectionIdx),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: textSecondary,
                            backgroundColor: bgRecessed,
                            side: BorderSide(color: borderSubtle),
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                            minimumSize: const Size(0, 28),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          child: Text(
                            'Revisit →',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,

            // Contextual Inline Agent Drawer (Adjust section right inside Full Review without losing context)
            if (isInlineOpen) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: bgRecessed,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: borderBright),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                            decoration: BoxDecoration(
                              color: bgSurface,
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(color: borderSubtle),
                            ),
                            child: TextField(
                              controller: _inlineReviewPromptController,
                              autofocus: true,
                              style: GoogleFonts.inter(
                                fontSize: 12.5,
                                color: textPrimary,
                              ),
                              decoration: InputDecoration(
                                hintText:
                                    'Tell the Agent how to adjust ${sec.numLabel} ${sec.title}...',
                                hintStyle: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: textMuted,
                                ),
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                isDense: true,
                                contentPadding:
                                    const EdgeInsets.symmetric(vertical: 8),
                              ),
                              onSubmitted: (_) => _submitSectionPrompt(
                                draft,
                                sectionIdx,
                                controller: _inlineReviewPromptController,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: widget.workbench.isAgentBusy
                              ? null
                              : () => _submitSectionPrompt(
                                    draft,
                                    sectionIdx,
                                    controller: _inlineReviewPromptController,
                                  ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: focalAccent,
                            foregroundColor: focalAccentFg,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 11,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                          child: Text(
                            widget.workbench.isAgentBusy ? 'Updating...' : 'Apply',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (int optIdx = 0;
                            optIdx < _optionsForSection(draft, sectionIdx).length;
                            optIdx++)
                          InkWell(
                            onTap: () => _selectSectionOption(draft, sectionIdx, optIdx),
                            borderRadius: BorderRadius.circular(4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: bgSurface,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: _isSectionOptionSelected(sectionIdx, optIdx)
                                      ? (_sections[sectionIdx].isMultiSelect
                                          ? accentEmerald
                                          : textPrimary)
                                      : borderSubtle,
                                ),
                              ),
                              child: Text(
                                _optionsForSection(draft, sectionIdx)[optIdx],
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: textSecondary,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/agent_blueprints.dart';
import '../providers/workbench_provider.dart';
import '../theme/app_theme.dart';

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

class _ProjectPitchScreenState extends State<ProjectPitchScreen> {
  final TextEditingController _sparkController = TextEditingController();
  final TextEditingController _agentPromptController = TextEditingController();
  final TextEditingController _inlineReviewPromptController =
      TextEditingController();

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

  bool get _isDark => widget.workbench.isDark;
  Color get _bgBase => AppTheme.bgBaseFor(_isDark);
  Color get _bgSurface => AppTheme.bgSurfaceFor(_isDark);
  Color get _bgRecessed => AppTheme.bgSurfaceRecessedFor(_isDark);
  Color get _bgHover => AppTheme.bgSurfaceHoverFor(_isDark);
  Color get _borderSubtle => AppTheme.borderSubtleFor(_isDark);
  Color get _borderBright => AppTheme.borderBrightFor(_isDark);
  Color get _textPrimary => AppTheme.textPrimaryFor(_isDark);
  Color get _textSecondary => AppTheme.textSecondaryFor(_isDark);
  Color get _textMuted => AppTheme.textMutedFor(_isDark);
  Color get _focalAccent => AppTheme.focalAccentFor(_isDark);
  Color get _focalAccentFg => AppTheme.focalAccentFgFor(_isDark);

  // Subtle semantic accents for instant grayscale-safe + semantic scanability
  Color get _accentEmerald => AppTheme.accentGreenFor(_isDark);
  Color get _accentCrimson => AppTheme.accentRedFor(_isDark);
  Color get _accentAmber => AppTheme.accentAmberFor(_isDark);

  static const List<_SectionConfig> _sections = [
    _SectionConfig(
      numLabel: '01',
      optionKey: 'goal',
      shortTitle: 'Goal',
      title: 'Goal',
      purpose: 'Plain-English statement of what we are building and why.',
      question: 'How should we frame the core prototype goal for v0.1?',
      options: [
        'Single-Arena Loop: Focus v0.1 strictly on the core gameplay loop in a single test arena',
        'Prep + Arena Loop: Include an interactive prep & staging zone before entering the active loop in v0.1',
        'Controls & Feel First: Focus v0.1 on primary player controls and core mechanic feel first',
      ],
    ),
    _SectionConfig(
      numLabel: '02',
      optionKey: 'gameSpec',
      shortTitle: 'Game Spec',
      title: 'Game Spec',
      purpose: 'Camera view, player controls, mode, and arena layout.',
      question: 'Which camera perspective and control scheme fits best?',
      options: [
        '2D Top-Down · Twin-Stick (WASD + Mouse Aim) · Singleplayer · Single-Screen Arena',
        '2D Side-Scrolling · Precision Controls · Singleplayer · Multi-Room Stages',
        '3D First-Person · Mouse + WASD · Singleplayer · Enclosed Sandbox',
      ],
    ),
    _SectionConfig(
      numLabel: '03',
      optionKey: 'techSpec',
      shortTitle: 'Tech Spec',
      title: 'Tech Spec',
      purpose: 'Engine, target platform, asset pipeline, and save/network architecture.',
      question: 'What engine and technical pipeline are we targeting for v0.1?',
      options: [
        'Godot 4 (2D) · PC Desktop · 2D Sprites + Particles · Offline Local Save',
        'Unity 6 · PC & Steam Deck · 2D/3D Hybrid Pipeline · Steam Cloud Save',
        'Unreal Engine 5 · PC Desktop · 3D Greybox Meshes · Offline Local Save',
      ],
    ),
    _SectionConfig(
      numLabel: '04',
      optionKey: 'designPillars',
      shortTitle: 'Design Pillars',
      title: 'Design Pillars',
      purpose: 'Core player experience truths (how the game feels, never a feature list).',
      question: 'Which player experience truth should anchor our design decisions?',
      isMultiSelect: true,
      options: [
        'Unbroken Momentum: Prioritize continuous movement velocity and readable telegraphs',
        'Tactical Positioning: Prioritize deliberate positioning and high-clarity feedback',
        'Chain-Reaction Mastery: Prioritize fast chain-reactions and rewarding loop mastery',
      ],
    ),
    _SectionConfig(
      numLabel: '05',
      optionKey: 'tradeOffs',
      shortTitle: 'Trade-Offs',
      title: 'Trade-Offs (X over Y)',
      purpose: 'Explicit engineering & design priority rules when mechanics conflict.',
      question: 'When mechanics conflict during production, what wins?',
      isMultiSelect: true,
      options: [
        'Instant Input Response: Instant arcade input response over realistic physics inertia',
        'Animation Commitment: Deliberate animation commitment over instant cancelable movement',
        'Greybox Readability: Clean greybox readability over heavy visual shaders in v0.1',
      ],
    ),
    _SectionConfig(
      numLabel: '06',
      optionKey: 'coreLoop',
      shortTitle: 'Core Loop',
      title: 'In Scope: Core Loop Beats',
      purpose: 'The sequential playable beats that make up the complete game loop.',
      question: 'How should the playable core loop Beats flow from start to reset?',
      isMultiSelect: true,
      options: [
        'Complete 4-Beat Loop: Staging & Prep → Active Gameplay Beats → Resource & Upgrade Choice → Loop Resolution & Reset',
        'Direct Action Loop: Immediate Entry → Core Mechanic Escalation → Target Objective → Score / Loot Tally → Instant Reset',
        'Skill Mastery Loop: Setup & Positioning → Primary Skill Execution → Hazard / Counter Response → Reward Payout → Next Round',
      ],
    ),
    _SectionConfig(
      numLabel: '07',
      optionKey: 'exclusions',
      shortTitle: 'Out of Scope',
      title: 'Out of Scope (Exclusions)',
      purpose: 'Hard exclusions cut from the Prototype to prevent scope creep.',
      question: 'Which scope-creep features should we explicitly cut from the Prototype?',
      isMultiSelect: true,
      options: [
        'Cut Trees, Co-Op & Story: Cut multi-branch skill trees, online co-op, and story cutscenes from Prototype',
        'Defer Bosses & Crafting: Defer multi-phase bosses and deep inventory crafting until MVP releases',
        'Defer Meta-Save & Audio: Defer persistent meta-progression saves and audio settings until MVP',
      ],
    ),
    _SectionConfig(
      numLabel: '08',
      optionKey: 'doneWhen',
      shortTitle: 'Done When',
      title: 'Done When',
      purpose: 'Observable playtest condition that proves the Prototype is complete.',
      question: 'How will we verify that the Prototype loop is done?',
      options: [
        '60 FPS Full Loop: Playtester completes a full core loop cycle at 60 FPS with zero soft-locks',
        'All Beats & Clean Reset: Playtester executes all core loop beats, collects rewards, and resets cleanly',
        '3 Consecutive Runs: Playtester completes 3 consecutive loop cycles with responsive controls and clear feedback',
      ],
    ),
    _SectionConfig(
      numLabel: '09',
      optionKey: 'prototypeRelease',
      shortTitle: 'Prototype Release',
      title: 'Phase 1: Prototype Release',
      purpose: 'Focuses strictly on proving the Core Loop first. Subsequent phases (MVPs per Beat → Vertical Slice → Full Production) unlock as each phase completes.',
      question: 'How should we scope Phase 1 (Prototype) before unlocking MVP Beat Releases?',
      options: [
        'Single v0.1 Greybox: Single Greybox Prototype (v0.1) proving the Core Loop Beats work together',
        'Two-Step v0.1 → v0.2: v0.1 Player Movement & Controls → v0.2 Full Core Loop Arena',
      ],
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

    setState(() {
      _selectedOptionBySection[sectionIdx] = optIdx;
      _agentNotesBySection[sectionIdx] =
          'Agent updating ${sec.title}: "$optionText"...';
    });

    // When a live AI key is configured, ask the Agent to update this specific section
    // for the user's actual game concept rather than overwriting with a hardcoded list!
    if (widget.workbench.hasLiveAiKey) {
      await widget.workbench.sendConceptChatMessage(
        '[Section ${sec.numLabel} ${sec.title}] Update ONLY the ${sec.title} section for "${draft.title}" (${draft.sparkIdea}) to apply this choice: "$optionText". Keep all other sections intact.',
      );
      if (!mounted) return;
      setState(() {
        _agentNotesBySection[sectionIdx] =
            'Agent updated ${sec.title}: Applied "$optionText".';
      });
      return;
    }

    _applySectionOptionDeterministic(draft, sectionIdx, optIdx, optionText);
    if (!mounted) return;
    setState(() {
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
                    : '$step: Execute $step for ${d.title} (${d.sparkIdea})';
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
    final bodyAfterColon = optionText.contains(':')
        ? optionText.substring(optionText.indexOf(':') + 1).trim()
        : optionText.trim();

    widget.workbench.updateConceptDraft((d) {
      switch (sectionIdx) {
        case 0:
          if (bodyAfterColon.toLowerCase().startsWith('build ')) {
            d.goal = bodyAfterColon;
          } else if (optIdx == 0) {
            d.goal =
                'Build a playable ${d.title} prototype centered on ${d.sparkIdea} with immediate loop feedback in a single arena.';
          } else if (optIdx == 1) {
            d.goal =
                'Build a ${d.title} prototype connecting an interactive prep & staging zone to repeatable core loop rounds.';
          } else {
            d.goal =
                'Build a ${d.title} prototype proving primary player controls and core mechanic feel for ${d.sparkIdea}.';
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
        case 3:
          final pillarValue = optionText.contains(':')
              ? optionText
              : 'Core Focus: $optionText';
          if (d.designPillars.isNotEmpty) {
            d.designPillars[0] = pillarValue;
          } else {
            d.designPillars = [pillarValue];
          }
          break;
        case 4:
          if (bodyAfterColon.toLowerCase().contains(' over ')) {
            if (d.tradeOffs.isNotEmpty) {
              d.tradeOffs[0] = bodyAfterColon;
            } else {
              d.tradeOffs = [bodyAfterColon];
            }
          }
          break;
        case 5:
          // Parse arrow-separated beats if the option describes a loop sequence,
          // otherwise preserve the concept's existing beats and adjust Beat 1!
          if (bodyAfterColon.contains('→')) {
            final steps = bodyAfterColon
                .split('→')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList();
            if (steps.length >= 3) {
              d.coreLoopBeats = [
                for (final step in steps)
                  step.contains(':')
                      ? step
                      : '$step: Execute $step for ${d.title} (${d.sparkIdea})',
              ];
            }
          }
          break;
        case 6:
          if (d.exclusions.isNotEmpty) {
            d.exclusions[0] = bodyAfterColon;
          } else {
            d.exclusions = [bodyAfterColon];
          }
          break;
        case 7:
          d.doneWhen = bodyAfterColon;
          break;
        case 8:
          if (optIdx == 0) {
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
    final text = activeController.text.trim();
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
      ..writeln('## 09. Phase 1: Prototype Release');
    for (final r in draft.releaseTrainTitles) {
      buf.writeln('- $r');
    }

    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (!mounted) return;
    AppToast.show(
      context,
      'Copied Project Concept Blueprint as Markdown',
      icon: Icons.check_circle_outline,
      isDark: _isDark,
      accentColor: _accentEmerald,
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
          backgroundColor: _bgSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: _borderBright),
          ),
          title: Text(
            'Edit $label',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
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
                  style: GoogleFonts.inter(fontSize: 13.5, color: _textPrimary),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: _bgRecessed,
                    hintText: 'Enter $label...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: _borderSubtle),
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
                      color: _textSecondary,
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
                              color: _bgRecessed,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: _borderSubtle),
                            ),
                            child: Text(
                              p,
                              style: GoogleFonts.inter(
                                fontSize: 11.5,
                                color: _textSecondary,
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
              child: Text('Cancel', style: GoogleFonts.inter(fontSize: 12, color: _textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _focalAccent,
                foregroundColor: _focalAccentFg,
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

  @override
  Widget build(BuildContext context) {
    final draft = widget.workbench.conceptDraft;

    // Step 1A: Before the first Spark is submitted, show the centered Spark launcher
    if (draft == null) {
      return Container(
        color: _bgBase,
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

    // Step 1B / 1C: Structure-First One-Section-at-a-Time Dynamic UI + Step 10 Full Review
    return Container(
      key: const ValueKey('concept_interview_card'),
      color: _bgBase,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildStepperRail(draft),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1160),
                  child: _currentStep < _sections.length
                      ? _buildFocusedSectionWorkspace(draft, _currentStep)
                      : _buildFullReviewWorkspace(draft),
                ),
              ),
            ),
          ),
          _buildConceptStickyBottomDock(draft),
        ],
      ),
    );
  }

  // ── Initial New Project Idea Intake & Expansion Launcher (Before Concept Draft Exists) ──
  Widget _buildInitialSparkLauncher() {
    final intake = widget.workbench.sparkIntake;
    final expansionCards = intake?.expansionCards ?? const [];

    Future<void> submitIdeaToAgent() async {
      final text = _sparkController.text.trim();
      if (text.isEmpty && intake == null) return;
      _sparkController.clear();
      await widget.workbench.ingestOrRefineSparkIdea(text);
    }

    Widget buildExpansionPlayingCard(int index) {
      final card = expansionCards[index];
      final isSelected = card.isSelected;
      final Color badgeColor = card.accentType == 'amber'
          ? _accentAmber
          : (card.accentType == 'emerald' ? _accentEmerald : _textPrimary);

      return Material(
        color: isSelected ? _bgHover : _bgRecessed,
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          key: ValueKey('spark_card_$index'),
          onTap: widget.workbench.isAgentBusy
              ? null
              : () => widget.workbench.toggleSparkExpansionCard(index),
          borderRadius: BorderRadius.circular(7),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(7),
              border: Border.all(
                color: isSelected ? _accentEmerald : _borderSubtle,
                width: isSelected ? 1.5 : 1.0,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2.5,
                            ),
                            decoration: BoxDecoration(
                              color: badgeColor.withValues(alpha: 0.13),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: badgeColor.withValues(alpha: 0.42),
                              ),
                            ),
                            child: Text(
                              card.badge,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.3,
                                color: badgeColor,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          isSelected
                              ? Icons.check_circle_rounded
                              : Icons.add_circle_outline_rounded,
                          size: 16,
                          color: isSelected ? _accentEmerald : _textMuted,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      card.title,
                      style: AppTheme.displayFont(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: _textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      card.description,
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        height: 1.48,
                        color: _textSecondary,
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.only(top: 8),
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(color: _borderSubtle),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              isSelected
                                  ? '✓ Added to Concept'
                                  : '+ Add to Concept',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color:
                                    isSelected ? _accentEmerald : _accentAmber,
                              ),
                            ),
                          ),
                          Text(
                            isSelected ? '✓' : '+',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: isSelected ? _accentEmerald : _accentAmber,
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
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _bgSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _bgRecessed,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: _borderBright),
                ),
                child: Text(
                  'STEP 1A · NEW PROJECT',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: _textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Pitch your game idea to the Agent & shape your Concept Summary',
                  style: AppTheme.displayFont(
                    fontSize: 17.5,
                    fontWeight: FontWeight.w700,
                    color: _textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            intake == null
                ? 'Tell the Agent your game idea below so it can summarize the core loop back to you and generate tailored Concept Addition Cards.'
                : 'Review the Agent\'s ingested summary below. Use the same input field to ask for changes, or toggle the Concept Addition Cards on/off before clicking Start Concept Blueprint →.',
            style: GoogleFonts.inter(fontSize: 13, color: _textSecondary),
          ),
          if (intake != null) ...[
            const SizedBox(height: 14),
            Container(
              key: const ValueKey('agent_idea_summary_card'),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _bgRecessed,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                  color: _accentEmerald.withValues(alpha: 0.45),
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
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _accentEmerald.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: _accentEmerald.withValues(alpha: 0.45),
                              ),
                            ),
                            child: Text(
                              'AGENT IDEA SUMMARY',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                color: _accentEmerald,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            intake.workingTitle,
                            style: AppTheme.displayFont(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: _textPrimary,
                            ),
                          ),
                        ],
                      ),
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
                              color: _textMuted,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    intake.effectiveSummary,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      height: 1.5,
                      color: _textPrimary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final m in intake.mechanics)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: _bgSurface,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: _borderSubtle),
                          ),
                          child: Text(
                            '⚡ $m',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: _textSecondary,
                            ),
                          ),
                        ),
                      for (final added
                          in intake.expansionCards.where((c) => c.isSelected))
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: _accentEmerald.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: _accentEmerald.withValues(alpha: 0.45),
                            ),
                          ),
                          child: Text(
                            '✓ + ${added.title}',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: _accentEmerald,
                            ),
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
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('spark_input_field'),
                  controller: _sparkController,
                  style: GoogleFonts.inter(fontSize: 14, color: _textPrimary),
                  decoration: InputDecoration(
                    hintText: intake == null
                        ? 'Pitch your game idea to the Agent (e.g., Cozy 2D submarine salvage & photo game)...'
                        : 'Tell the Agent what to change or add to this summary...',
                    hintStyle: GoogleFonts.inter(fontSize: 13, color: _textMuted),
                    filled: true,
                    fillColor: _bgRecessed,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: _borderSubtle),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: _borderSubtle),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: _borderBright, width: 1.5),
                    ),
                  ),
                  onSubmitted: (_) => submitIdeaToAgent(),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                key: const ValueKey('ingest_idea_summary_btn'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _textPrimary,
                  backgroundColor: _bgRecessed,
                  side: BorderSide(color: _borderBright),
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
                  foregroundColor: _accentAmber,
                  backgroundColor: _accentAmber.withValues(alpha: 0.08),
                  side: BorderSide(color: _accentAmber.withValues(alpha: 0.45)),
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
                icon: const Icon(Icons.description_outlined, size: 14),
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
                    backgroundColor: _focalAccent,
                    foregroundColor: _focalAccentFg,
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
                            _sparkController.text,
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'IDEAS TO ADD TO YOUR CONCEPT (CLICK TO TOGGLE ON / OFF)',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: _textSecondary,
                  ),
                ),
                InkWell(
                  key: const ValueKey('shuffle_spark_ideas_btn'),
                  onTap: () => widget.workbench.shuffleSparkExpansionCards(),
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: _bgRecessed,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: _borderSubtle),
                    ),
                    child: Text(
                      '↻ Refresh Suggestions',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: _accentAmber,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 660) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (int i = 0; i < expansionCards.length; i++) ...[
                        buildExpansionPlayingCard(i),
                        if (i < expansionCards.length - 1)
                          const SizedBox(height: 10),
                      ],
                    ],
                  );
                }
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (int i = 0; i < expansionCards.length; i++) ...[
                        Expanded(child: buildExpansionPlayingCard(i)),
                        if (i < expansionCards.length - 1)
                          const SizedBox(width: 12),
                      ],
                    ],
                  ),
                );
              },
            ),
          ],
          if (widget.workbench.savedProjects.isNotEmpty) ...[
            const SizedBox(height: 20),
            Container(
              key: const ValueKey('stage1_saved_projects_strip'),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _bgRecessed,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: _borderSubtle),
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
                          color: _accentEmerald,
                        ),
                      ),
                      Text(
                        widget.workbench.isCloudSynced ? '☁ Cloud Synced' : '⚡ Local Auto-Save',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9,
                          color: _textMuted,
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
                            color: _bgSurface,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: _borderSubtle),
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
                                      color: _accentAmber,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      p.title,
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: _textPrimary,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Resume →',
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w700,
                                        color: _accentEmerald,
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
                                    color: _textMuted,
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
                                    color: _textMuted,
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
      ),
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
          backgroundColor: _bgSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: _borderBright),
          ),
          title: Row(
            children: [
              Icon(Icons.description_outlined, size: 18, color: _accentAmber),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Import Existing GDD / Pitch Notes',
                  style: AppTheme.displayFont(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _textPrimary,
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
                    color: _textSecondary,
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
                    color: _textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText:
                        '# Neon Grapple Arena\nGoal: Build a fast 3D grappling hook arena shooter in Godot 4.\nEngine: Godot 4 (3D)\nCore Loop: Grapple -> Shoot -> Bank Score -> Reset\nDone When: Playtester completes 3 consecutive arena waves without clipping.',
                    hintStyle: GoogleFonts.jetBrainsMono(
                      fontSize: 11.5,
                      color: _textMuted,
                    ),
                    filled: true,
                    fillColor: _bgRecessed,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: _borderSubtle),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: _borderSubtle),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: _accentAmber, width: 1.4),
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
                  color: _textSecondary,
                ),
              ),
            ),
            ElevatedButton.icon(
              key: const ValueKey('confirm_import_gdd_btn'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _accentEmerald,
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

  // ── Sticky Horizontal Stepper Rail (`01 Goal` ... `09 Prototype Release` + `10 Full Review`) ─
  Widget _buildStepperRail(ProjectConceptBlueprint draft) {
    final verifiedCount = _visitedSteps.where((idx) => idx >= 0 && idx < _sections.length).length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: _bgSurface,
        border: Border(bottom: BorderSide(color: _borderSubtle)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            InkWell(
              key: const ValueKey('new_spark_reset_btn'),
              onTap: () => widget.workbench.resetConceptToSpark(),
              borderRadius: BorderRadius.circular(5),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: _accentAmber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(
                    color: _accentAmber.withValues(alpha: 0.45),
                  ),
                ),
                child: Text(
                  '+ New Project',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: _accentAmber,
                  ),
                ),
              ),
            ),
            Container(
              width: 1,
              height: 18,
              margin: const EdgeInsets.symmetric(horizontal: 10),
              color: _borderBright,
            ),
            for (int i = 0; i < _sections.length; i++) ...[
              _buildStepNode(
                index: i,
                numText: _sections[i].numLabel,
                label: _sections[i].shortTitle,
                isActive: _currentStep == i,
                isDone: _visitedSteps.contains(i) && _currentStep != i,
              ),
              if (i < _sections.length - 1)
                Container(
                  width: 6,
                  height: 1,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  color: _borderSubtle,
                ),
            ],
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _accentEmerald.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: _accentEmerald.withValues(alpha: 0.38),
                ),
              ),
              child: Text(
                '$verifiedCount/9 Verified',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  color: _accentEmerald,
                ),
              ),
            ),
            const SizedBox(width: 8),
            _buildStepNode(
              key: const ValueKey('synthesize_concept_btn'),
              index: _sections.length,
              numText: '10',
              label: 'Full Review',
              isActive: _currentStep == _sections.length,
              isDone: false,
              isFinalReview: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepNode({
    Key? key,
    required int index,
    required String numText,
    required String label,
    required bool isActive,
    required bool isDone,
    bool isFinalReview = false,
  }) {
    return InkWell(
      key: key ?? ValueKey('step_node_$index'),
      onTap: () => _goToStep(index),
      borderRadius: BorderRadius.circular(5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: isActive ? _bgHover : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: isActive
                ? (isFinalReview ? _accentAmber : _textPrimary)
                : Colors.transparent,
            width: isActive ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  numText,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: isActive
                        ? (isFinalReview ? _accentAmber : _textPrimary)
                        : (isDone ? _accentEmerald : _textMuted),
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                    color: isActive
                        ? _textPrimary
                        : (isDone ? _textSecondary : _textMuted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Container(
              height: 2,
              width: 28,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                color: isActive
                    ? (isFinalReview ? _accentAmber : _focalAccent)
                    : (isDone
                        ? _accentEmerald.withValues(alpha: 0.65)
                        : Colors.transparent),
              ),
            ),
          ],
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
          backgroundColor: _bgSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: _borderBright),
          ),
          title: Text(
            'Edit $title',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
            ),
          ),
          content: SizedBox(
            width: 480,
            child: TextField(
              controller: controller,
              autofocus: true,
              maxLines: 3,
              minLines: 1,
              style: GoogleFonts.inter(fontSize: 13.5, color: _textPrimary),
              decoration: InputDecoration(
                filled: true,
                fillColor: _bgRecessed,
                hintText: 'Enter $title...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: _borderSubtle),
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
                style: GoogleFonts.inter(fontSize: 12, color: _textSecondary),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _focalAccent,
                foregroundColor: _focalAccentFg,
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
              color: _bgSurface,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(
                color: (intervention.severity == 'crimson'
                        ? _accentCrimson
                        : _accentAmber)
                    .withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: (intervention.severity == 'crimson'
                            ? _accentCrimson
                            : _accentAmber)
                        .withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    intervention.badge,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: intervention.severity == 'crimson'
                          ? _accentCrimson
                          : _accentAmber,
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
                      color: _textSecondary,
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
                              ? _accentCrimson
                              : _accentAmber)
                          .withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: (intervention.severity == 'crimson'
                                ? _accentCrimson
                                : _accentAmber)
                            .withValues(alpha: 0.55),
                      ),
                    ),
                    child: Text(
                      intervention.actionLabel,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        color: intervention.severity == 'crimson'
                            ? _accentCrimson
                            : _accentAmber,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        // CARD 1: THE FOCUSED ARTIFACT SECTION CARD (Full-Width 1160px Canvas, Matching Step 10 Hierarchy)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          decoration: BoxDecoration(
            color: _bgSurface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _borderSubtle),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top Section Header Bar (Full Width — No 210px Left Squeeze)
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                runSpacing: 8,
                spacing: 12,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: _bgRecessed,
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(color: _borderBright),
                        ),
                        child: Text(
                          sec.numLabel,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: _textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        sec.title.toUpperCase(),
                        style: AppTheme.displayFont(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                          color: _textPrimary,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _bgRecessed,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: _borderSubtle),
                        ),
                        child: Text(
                          'SECTION ${sec.numLabel} / 09',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: _textSecondary.withValues(alpha: 0.85),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: _bgRecessed,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: _borderBright.withValues(alpha: 0.55)),
                        ),
                        child: Text(
                          '← / → Step',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: _textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _bgRecessed,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: _borderSubtle),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.edit_outlined,
                              size: 11,
                              color: _textSecondary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Click any item below to edit directly',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: _textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                sec.purpose,
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  color: _textSecondary,
                ),
              ),
              const SizedBox(height: 16),

              // Full-Width Artifact Content (Identical Proportions to Step 10 Full Review)
              _buildSectionContentWidget(draft, sectionIdx),
            ],
          ),
        ),

        const SizedBox(height: 18),

        // CARD 2: THE AGENT CO-DESIGN CONSOLE & STEP NAVIGATION CARD
        Container(
          decoration: BoxDecoration(
            color: _bgSurface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _borderSubtle),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
                decoration: BoxDecoration(
                  color: _bgRecessed,
                  border: Border(
                    bottom: BorderSide(color: _borderSubtle),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                          decoration: BoxDecoration(
                            color: _bgSurface,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: _borderBright),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _accentAmber,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'AGENT · ${widget.workbench.conversationModel.toUpperCase()}',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  color: _textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            sec.question,
                            style: GoogleFonts.inter(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: _textPrimary,
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
                            decoration: BoxDecoration(
                              color: _accentEmerald.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: _accentEmerald.withValues(alpha: 0.45),
                              ),
                            ),
                            child: Text(
                              '+ / ✓ MULTI-SELECT · ADD ANY',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: _accentEmerald,
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
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: _bgSurface,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: _borderSubtle),
                            ),
                            child: Text(
                              '↻ Refresh Options',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: _accentAmber,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Side-by-Side Agent Option Playing Cards
                    LayoutBuilder(
                      builder: (context, optConstraints) {
                        final options = _optionsForSection(draft, sectionIdx);
                        final isWide = optConstraints.maxWidth >= 680;
                        if (!isWide) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (int optIdx = 0; optIdx < options.length; optIdx++) ...[
                                _buildAgentOptionCard(
                                  draft: draft,
                                  sectionIdx: sectionIdx,
                                  optIdx: optIdx,
                                  label: options[optIdx],
                                  isSelected: _isSectionOptionSelected(sectionIdx, optIdx),
                                ),
                                if (optIdx < options.length - 1) const SizedBox(height: 8),
                              ],
                            ],
                          );
                        }
                        return IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (int optIdx = 0; optIdx < options.length; optIdx++) ...[
                                Expanded(
                                  child: _buildAgentOptionCard(
                                    draft: draft,
                                    sectionIdx: sectionIdx,
                                    optIdx: optIdx,
                                    label: options[optIdx],
                                    isSelected: _isSectionOptionSelected(sectionIdx, optIdx),
                                  ),
                                ),
                                if (optIdx < options.length - 1) const SizedBox(width: 10),
                              ],
                            ],
                          ),
                        );
                      },
                    ),

                    if (agentNote != null) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          border: Border(
                            left: BorderSide(color: _accentEmerald, width: 2),
                          ),
                        ),
                        child: Text(
                          agentNote,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 11,
                            color: _textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
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
          color: _bgSurface,
          border: Border(top: BorderSide(color: _borderBright)),
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
                        foregroundColor: _textPrimary,
                        backgroundColor: _bgRecessed,
                        side: BorderSide(color: _borderSubtle),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                      child: Text(
                        '← Back to Section 09',
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
                        color: _accentEmerald.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: _accentEmerald.withValues(alpha: 0.45),
                        ),
                      ),
                      child: Text(
                        'ALL 9 SECTIONS READY',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: _accentEmerald,
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
                        foregroundColor: _textPrimary,
                        backgroundColor: _bgRecessed,
                        side: BorderSide(color: _borderSubtle),
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
        color: _bgSurface,
        border: Border(top: BorderSide(color: _borderBright)),
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
                        color: _bgRecessed,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: _borderSubtle),
                      ),
                      child: Row(
                        children: [
                          Text(
                            '[ASK AGENT]',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: _textSecondary,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              key: const ValueKey('concept_chat_input_field'),
                              controller: _agentPromptController,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: _textPrimary,
                              ),
                              decoration: InputDecoration(
                                hintText:
                                    'Tell the Agent how to change or expand ${sec.title}...',
                                hintStyle: GoogleFonts.inter(
                                  fontSize: 12.5,
                                  color: _textMuted,
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
                      foregroundColor: _textPrimary,
                      backgroundColor: _bgRecessed,
                      side: BorderSide(color: _borderBright),
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
                      foregroundColor: _textPrimary,
                      backgroundColor: _bgRecessed,
                      side: BorderSide(color: _borderSubtle),
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
                      TextButton(
                        onPressed: () => _goToStep(_sections.length),
                        child: Text(
                          'Skip to Final Review',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: _textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        key: const ValueKey('next_section_btn'),
                        onPressed: () => _goToStep(sectionIdx + 1),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _focalAccent,
                          foregroundColor: _focalAccentFg,
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

    return Material(
      color: isSelected ? _bgHover : _bgSurface,
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        key: ValueKey('agent_option_card_${sectionIdx}_$optIdx'),
        onTap: () => _selectSectionOption(draft, sectionIdx, optIdx),
        borderRadius: BorderRadius.circular(7),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: isSelected
                  ? (isMulti ? _accentEmerald : _textPrimary)
                  : _borderSubtle,
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (isMulti)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (optIdx == 0)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: _accentEmerald.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(3),
                                  border: Border.all(
                                    color: _accentEmerald.withValues(alpha: 0.42),
                                  ),
                                ),
                                child: Text(
                                  'RECOMMENDED',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w700,
                                    color: _accentEmerald,
                                  ),
                                ),
                              )
                            else
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: _bgRecessed,
                                  borderRadius: BorderRadius.circular(3),
                                  border: Border.all(color: _borderSubtle),
                                ),
                                child: Text(
                                  'OPTION 0${optIdx + 1}',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w700,
                                    color: _textSecondary,
                                  ),
                                ),
                              ),
                            const SizedBox(width: 5),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: _bgRecessed,
                                borderRadius: BorderRadius.circular(3),
                                border: Border.all(
                                  color: _borderBright.withValues(alpha: 0.6),
                                ),
                              ),
                              child: Text(
                                'Key ${optIdx + 1}',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w700,
                                  color: _textSecondary,
                                ),
                              ),
                            ),
                          ],
                        )
                      else
                        Container(
                          width: 15,
                          height: 15,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isSelected ? _focalAccent : Colors.transparent,
                            border: Border.all(
                              color: isSelected ? _focalAccent : _textMuted,
                              width: 1.4,
                            ),
                          ),
                          child: isSelected
                              ? Container(
                                  width: 5,
                                  height: 5,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _focalAccentFg,
                                  ),
                                )
                              : null,
                        ),
                      if (isMulti)
                        Icon(
                          isSelected
                              ? Icons.check_circle_rounded
                              : Icons.add_circle_outline_rounded,
                          size: 16,
                          color: isSelected ? _accentEmerald : _textMuted,
                        )
                      else
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (optIdx == 0)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: _accentEmerald.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(3),
                                  border: Border.all(
                                    color: _accentEmerald.withValues(alpha: 0.42),
                                  ),
                                ),
                                child: Text(
                                  'RECOMMENDED',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w700,
                                    color: _accentEmerald,
                                  ),
                                ),
                              )
                            else
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: _bgRecessed,
                                  borderRadius: BorderRadius.circular(3),
                                  border: Border.all(color: _borderSubtle),
                                ),
                                child: Text(
                                  'OPTION 0${optIdx + 1}',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w700,
                                    color: _textSecondary,
                                  ),
                                ),
                              ),
                            const SizedBox(width: 5),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: _bgRecessed,
                                borderRadius: BorderRadius.circular(3),
                                border: Border.all(
                                  color: _borderBright.withValues(alpha: 0.6),
                                ),
                              ),
                              child: Text(
                                'Key ${optIdx + 1}',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w700,
                                  color: _textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    parsed.title,
                    style: AppTheme.displayFont(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _textPrimary,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    parsed.description,
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      height: 1.48,
                      color: _textSecondary,
                    ),
                  ),
                ],
              ),
              if (isMulti)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.only(top: 8),
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(color: _borderSubtle),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              isSelected
                                  ? '✓ Added to ${sec.shortTitle}'
                                  : '+ Add to ${sec.shortTitle}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: isSelected ? _accentEmerald : _accentAmber,
                              ),
                            ),
                          ),
                          Text(
                            isSelected ? '✓' : '+',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: isSelected ? _accentEmerald : _accentAmber,
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
      case 0: // 01 Goal — Callout Blockquote (Click to Edit)
        return _buildCalloutStatement(
          draft.goal,
          highlightMetrics: false,
          onEditTap: () => _showDirectSectionTextEditDialog(
            title: '01 Goal',
            initialText: draft.goal,
            onSave: (val) => widget.workbench.updateConceptDraft((d) => d.goal = val),
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
      case 5: // 06 Core Loop — Connected Beat Cycle Rows + Inline Add/Remove
        return _buildIndexedRows(
          prefix: 'BEAT',
          items: draft.coreLoopBeats,
          isCoreLoop: true,
          onEditItem: (i, val) => widget.workbench.updateConceptDraft((d) {
            final next = List<String>.from(d.coreLoopBeats);
            next[i] = val;
            d.coreLoopBeats = next;
          }),
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

  Widget _buildCalloutStatement(
    String statement, {
    required bool highlightMetrics,
    VoidCallback? onEditTap,
  }) {
    return Material(
      color: _bgRecessed,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onEditTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: _borderSubtle),
          ),
          clipBehavior: Clip.antiAlias,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 3,
                  color: highlightMetrics ? _accentEmerald : _focalAccent,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
                    child: highlightMetrics
                        ? _buildMetricHighlightedRichText(statement)
                        : Text(
                            statement,
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              height: 1.58,
                              color: _textPrimary,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Wraps quantitative playtest targets (e.g., `10-minute`, `3 escalating waves`, `40 enemies`, `60 FPS`)
  /// in bold inline pills so QA metrics pop immediately inside `08 Done When`.
  Widget _buildMetricHighlightedRichText(String statement) {
    final metricRegex = RegExp(
      r'\b(\d+(?:[\.\-]\d+)?(?:\s*(?:minute|minutes|min|second|seconds|sec|s|FPS|fps|key|keys|waves|wave|enemies|enemy|rooms|room|players|player|ms|%))?)\b',
      caseSensitive: false,
    );
    final spans = <InlineSpan>[];
    int lastEnd = 0;

    for (final match in metricRegex.allMatches(statement)) {
      if (match.start > lastEnd) {
        spans.add(
          TextSpan(
            text: statement.substring(lastEnd, match.start),
          ),
        );
      }
      final metricText = match.group(0)!;
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
            decoration: BoxDecoration(
              color: _accentEmerald.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: _accentEmerald.withValues(alpha: 0.42),
              ),
            ),
            child: Text(
              metricText,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: _textPrimary,
              ),
            ),
          ),
        ),
      );
      lastEnd = match.end;
    }

    if (lastEnd < statement.length) {
      spans.add(TextSpan(text: statement.substring(lastEnd)));
    }

    return RichText(
      text: TextSpan(
        style: GoogleFonts.inter(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          height: 1.58,
          color: _textPrimary,
        ),
        children: spans,
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
        color: _bgRecessed,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _borderSubtle),
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
      color: _bgSurface,
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
              right: rightBorder ? BorderSide(color: _borderSubtle) : BorderSide.none,
              bottom: bottomBorder ? BorderSide(color: _borderSubtle) : BorderSide.none,
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
                      color: _textSecondary.withValues(alpha: 0.85),
                    ),
                  ),
                  Icon(
                    Icons.edit_outlined,
                    size: 11,
                    color: _textMuted.withValues(alpha: 0.65),
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
                  color: _textPrimary,
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
          color: _textPrimary,
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
              color: _textPrimary,
            ),
          ),
          TextSpan(
            text: rest,
            style: TextStyle(
              fontWeight: FontWeight.w400,
              color: _textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  // ── Section 04: 3 Side-by-Side Design Pillar Playing Cards + Inline Add/Delete ──
  Widget _buildDesignPillarCards(
    ProjectConceptBlueprint draft, {
    bool isReadOnlySummary = false,
  }) {
    final pillars = draft.designPillars;

    Widget buildPillarCard(int idx) {
      final raw = pillars[idx];
      final colonIdx = raw.indexOf(':');
      final String title = (colonIdx > 0 && colonIdx < 48)
          ? raw.substring(0, colonIdx).trim()
          : 'Pillar 0${idx + 1}';
      final String body = (colonIdx > 0 && colonIdx < 48)
          ? raw.substring(colonIdx + 1).trim()
          : raw;

      return Material(
        color: _bgRecessed,
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          onTap: () => _showDirectSectionTextEditDialog(
            title: 'P·${(idx + 1).toString().padLeft(2, '0')} Design Pillar',
            initialText: raw,
            onSave: (val) => widget.workbench.updateConceptDraft((d) {
              final next = List<String>.from(d.designPillars);
              next[idx] = val;
              d.designPillars = next;
            }),
          ),
          borderRadius: BorderRadius.circular(7),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: _borderSubtle),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: _bgSurface,
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(color: _borderBright),
                      ),
                      child: Text(
                        'P·${(idx + 1).toString().padLeft(2, '0')}',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: _textSecondary,
                        ),
                      ),
                    ),
                    if (!isReadOnlySummary && pillars.length > 1)
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
                              color: _textMuted,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  title,
                  style: AppTheme.displayFont(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _textPrimary,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  body,
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    height: 1.48,
                    color: _textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 680 && pillars.length <= 4;
            if (!isWide) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (int i = 0; i < pillars.length; i++) ...[
                    buildPillarCard(i),
                    if (i < pillars.length - 1) const SizedBox(height: 8),
                  ],
                ],
              );
            }
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (int i = 0; i < pillars.length; i++) ...[
                    Expanded(child: buildPillarCard(i)),
                    if (i < pillars.length - 1) const SizedBox(width: 10),
                  ],
                ],
              ),
            );
          },
        ),
        if (!isReadOnlySummary) ...[
          const SizedBox(height: 10),
          _buildInlineAddBar(
            label: '+ Add a custom Design Pillar...',
            onTap: () => _showDirectSectionTextEditDialog(
              title: 'Add Design Pillar',
              initialText: 'Every Choice Echoes: Player actions leave visible feedback in the arena.',
              onSave: (val) => widget.workbench.updateConceptDraft((d) {
                d.designPillars = [...d.designPillars, val];
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
      color: _bgRecessed.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(5),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(5),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: _borderSubtle),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: _textMuted,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _bgSurface,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: _borderBright),
                ),
                child: Text(
                  '+ Add',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: _textPrimary,
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
    void Function(int index)? onDeleteItem,
    VoidCallback? onAddItem,
  }) {
    final badgeAccent = isCoreLoop ? _accentEmerald : _borderBright;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < items.length; i++) ...[
          Material(
            color: _bgRecessed,
            borderRadius: BorderRadius.circular(5),
            child: InkWell(
              onTap: onEditItem == null
                  ? null
                  : () => _showDirectSectionTextEditDialog(
                        title: '$prefix·${(i + 1).toString().padLeft(2, '0')}',
                        initialText: items[i],
                        onSave: (val) => onEditItem(i, val),
                      ),
              borderRadius: BorderRadius.circular(5),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: _borderSubtle),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 68,
                      padding: const EdgeInsets.symmetric(vertical: 2.5),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isCoreLoop
                            ? _accentEmerald.withValues(alpha: 0.12)
                            : _bgSurface,
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(
                          color: isCoreLoop
                              ? badgeAccent.withValues(alpha: 0.45)
                              : _borderBright,
                        ),
                      ),
                      child: Text(
                        '$prefix·${(i + 1).toString().padLeft(2, '0')}',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: isCoreLoop ? _accentEmerald : _textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _buildFormattedLeadInText(items[i]),
                    ),
                    if (onDeleteItem != null) ...[
                      const SizedBox(width: 8),
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
                              color: _textMuted,
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
          if (i < items.length - 1)
            if (isCoreLoop)
              Row(
                children: [
                  const SizedBox(width: 47),
                  Container(
                    width: 2,
                    height: 8,
                    color: _accentEmerald.withValues(alpha: 0.45),
                  ),
                ],
              )
            else
              const SizedBox(height: 7),
        ],
        if (isCoreLoop && items.isNotEmpty) ...[
          Row(
            children: [
              const SizedBox(width: 47),
              Container(
                width: 2,
                height: 8,
                color: _accentEmerald.withValues(alpha: 0.45),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _accentEmerald.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: _accentEmerald.withValues(alpha: 0.35),
                ),
              ),
              child: Text(
                '↺ Loops back to BEAT·01 (Continuous Cycle)',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: _accentEmerald,
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
          if (i < tradeOffs.length - 1) const SizedBox(height: 7),
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
      color: _bgRecessed,
      borderRadius: BorderRadius.circular(5),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(5),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: _borderSubtle),
          ),
          child: Row(
            children: [
              // Left winning option: Checkmark on far left, winning text right-aligned toward center OVER pill
              Container(
                width: 68,
                padding: const EdgeInsets.symmetric(vertical: 2),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _accentEmerald.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                    color: _accentEmerald.withValues(alpha: 0.45),
                  ),
                ),
                child: Text(
                  '✓ WIN',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: _accentEmerald,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  winText,
                  textAlign: TextAlign.right,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: _bgSurface,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: _borderBright),
                ),
                child: Text(
                  'OVER',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: _textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  loseText,
                  textAlign: TextAlign.left,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: _textSecondary.withValues(alpha: 0.78),
                    decoration: TextDecoration.lineThrough,
                    decorationColor: _accentCrimson.withValues(alpha: 0.70),
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
                        color: _textMuted,
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
    Widget buildExclusionCard(int idx) {
      return Material(
        color: _bgRecessed.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onEditItem == null
              ? null
              : () => _showDirectSectionTextEditDialog(
                    title: 'Out of Scope Exclusion #${idx + 1}',
                    initialText: exclusions[idx],
                    onSave: (val) => onEditItem(idx, val),
                  ),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _borderSubtle),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _accentCrimson.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(
                      color: _accentCrimson.withValues(alpha: 0.42),
                    ),
                  ),
                  child: Text(
                    'CUT',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: _accentCrimson,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    exclusions[idx],
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      color: _textSecondary.withValues(alpha: 0.88),
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
                          color: _textMuted,
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
        LayoutBuilder(
          builder: (context, constraints) {
            final isTwoCol = constraints.maxWidth >= 620 && exclusions.length > 1;
            if (!isTwoCol) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (int i = 0; i < exclusions.length; i++) ...[
                    buildExclusionCard(i),
                    if (i < exclusions.length - 1) const SizedBox(height: 7),
                  ],
                ],
              );
            }
            final rows = <Widget>[];
            for (int i = 0; i < exclusions.length; i += 2) {
              final hasSecond = i + 1 < exclusions.length;
              rows.add(
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: buildExclusionCard(i)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: hasSecond
                            ? buildExclusionCard(i + 1)
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
              );
              if (i + 2 < exclusions.length) {
                rows.add(const SizedBox(height: 8));
              }
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: rows,
            );
          },
        ),
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
    const lockedPhases = [
      ProductionPhase.mvp,
      ProductionPhase.verticalSlice,
      ProductionPhase.fullProduction,
    ];

    Widget buildLockedPhaseCard(int pIdx) {
      final phase = lockedPhases[pIdx];
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _bgRecessed.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: _borderSubtle),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: _bgSurface,
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: _borderSubtle),
                  ),
                  child: Text(
                    'LOCKED · PHASE ${pIdx + 2}',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 8.5,
                      fontWeight: FontWeight.w700,
                      color: _textSecondary.withValues(alpha: 0.8),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              phase.label,
              style: GoogleFonts.inter(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: _textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              phase.summary,
              style: GoogleFonts.inter(
                fontSize: 11.5,
                height: 1.4,
                color: _textSecondary.withValues(alpha: 0.75),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Active Phase 1: Prototype Release(s)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _bgRecessed,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: _borderBright),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    ProductionPhase.prototype.label,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: _textPrimary,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: _accentAmber.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: _accentAmber.withValues(alpha: 0.55),
                      ),
                    ),
                    child: Text(
                      'ACTIVE PHASE',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        color: _accentAmber,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                ProductionPhase.prototype.summary,
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  color: _textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              for (int i = 0; i < releases.length; i++) ...[
                _buildReleaseStepCard(
                  releases[i],
                  draft: draft,
                  isFirst: i == 0,
                  index: i,
                  onTap: () => _showDirectSectionTextEditDialog(
                    title: 'Prototype Release v0.${i + 1}',
                    initialText: releases[i],
                    onSave: (val) => widget.workbench.updateConceptDraft((d) {
                      final next = List<String>.from(d.releaseTrainTitles);
                      next[i] = val;
                      d.releaseTrainTitles = next;
                    }),
                  ),
                ),
                if (i < releases.length - 1)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        const SizedBox(width: 24),
                        Text(
                          '↓ THEN',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: _textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
        if (!isReadOnlySummary) ...[
          const SizedBox(height: 10),
          // Locked Future Production Phases (3 Horizontal Roadmap Cards on Desktop)
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 680) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (int pIdx = 0; pIdx < lockedPhases.length; pIdx++) ...[
                      buildLockedPhaseCard(pIdx),
                      if (pIdx < lockedPhases.length - 1) const SizedBox(height: 6),
                    ],
                  ],
                );
              }
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (int pIdx = 0; pIdx < lockedPhases.length; pIdx++) ...[
                      Expanded(child: buildLockedPhaseCard(pIdx)),
                      if (pIdx < lockedPhases.length - 1) const SizedBox(width: 8),
                    ],
                  ],
                ),
              );
            },
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
      color: isFirst ? _bgSurface : _bgRecessed,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isFirst ? _accentAmber : _borderSubtle,
              width: isFirst ? 1.6 : 1.0,
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
                      color: isFirst ? _accentAmber : _textSecondary.withValues(alpha: 0.85),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isFirst
                          ? _accentAmber.withValues(alpha: 0.14)
                          : _bgSurface,
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(
                        color: isFirst
                            ? _accentAmber.withValues(alpha: 0.45)
                            : _borderSubtle,
                      ),
                    ),
                    child: Text(
                      isFirst ? 'READY TO PLAN →' : 'QUEUED',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: isFirst ? _accentAmber : _textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                fullTitle,
                style: GoogleFonts.inter(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: isFirst ? _textPrimary : _textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Scope: ${draft.coreLoopBeats.length} Core Loop Beats · ${draft.gameSpec.length} Game Specs · ${draft.designPillars.length} Design Pillars',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  color: _textSecondary.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Step `10 · Full Review`: Clean Single Dossier Blueprint Sheet ───────────
  Widget _buildFullReviewWorkspace(ProjectConceptBlueprint draft) {
    return Container(
      key: const ValueKey('project_blueprint_card'),
      color: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Verification Banner Card
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
            decoration: BoxDecoration(
              color: _bgSurface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _borderBright),
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
                      'STEP 10 · FINAL BLUEPRINT VERIFICATION',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                        color: _accentAmber,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${draft.title} — Complete Project Concept Blueprint',
                      style: AppTheme.displayFont(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: _textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Hover any section to adjust it inline with the Agent, or click any item to edit directly.',
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        color: _textSecondary,
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
                        foregroundColor: _textPrimary,
                        backgroundColor: _bgRecessed,
                        side: BorderSide(color: _borderSubtle),
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

          // Single Unified Blueprint Dossier Sheet (Clean Hairline Dividers, No Outer Box-Within-Box Clutter)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 26),
            decoration: BoxDecoration(
              color: _bgSurface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _borderSubtle),
            ),
            child: Column(
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
                  child: Divider(height: 1, thickness: 1, color: _borderSubtle),
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
                              color: _borderSubtle,
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
                              color: _borderSubtle,
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

                // 04 Design Pillars through 09 Prototype Release
                for (int idx = 3; idx < _sections.length; idx++) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 22),
                    child: Divider(
                      height: 1,
                      thickness: 1,
                      color: _borderSubtle,
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
              ],
            ),
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
          : () => widget.workbench.openReleasePlanGate(),
      style: ElevatedButton.styleFrom(
        backgroundColor: _focalAccent,
        foregroundColor: _focalAccentFg,
        elevation: 0,
        padding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 14,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(color: _accentAmber.withValues(alpha: 0.55)),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.workbench.isAgentBusy
                ? 'Generating Release Plan...'
                : 'Approve & Plan v0.1 Release →',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
            decoration: BoxDecoration(
              color: _focalAccentFg.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              '⌘↵',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: _focalAccentFg,
              ),
            ),
          ),
        ],
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
              ? _bgRecessed.withValues(alpha: 0.65)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _bgRecessed,
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(color: _borderBright),
                      ),
                      child: Text(
                        sec.numLabel,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: _textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      sec.title.toUpperCase(),
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: _textPrimary,
                      ),
                    ),
                  ],
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
                            foregroundColor: isInlineOpen ? _focalAccentFg : _textPrimary,
                            backgroundColor: isInlineOpen ? _focalAccent : _bgRecessed,
                            side: BorderSide(color: _borderBright),
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
                            foregroundColor: _textSecondary,
                            backgroundColor: _bgRecessed,
                            side: BorderSide(color: _borderSubtle),
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
                  color: _bgRecessed,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _borderBright),
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
                              color: _bgSurface,
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(color: _borderSubtle),
                            ),
                            child: TextField(
                              controller: _inlineReviewPromptController,
                              autofocus: true,
                              style: GoogleFonts.inter(
                                fontSize: 12.5,
                                color: _textPrimary,
                              ),
                              decoration: InputDecoration(
                                hintText:
                                    'Tell the Agent how to adjust ${sec.numLabel} ${sec.title}...',
                                hintStyle: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: _textMuted,
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
                            backgroundColor: _focalAccent,
                            foregroundColor: _focalAccentFg,
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
                                color: _bgSurface,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: _isSectionOptionSelected(sectionIdx, optIdx)
                                      ? (_sections[sectionIdx].isMultiSelect
                                          ? _accentEmerald
                                          : _textPrimary)
                                      : _borderSubtle,
                                ),
                              ),
                              child: Text(
                                _optionsForSection(draft, sectionIdx)[optIdx],
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: _textSecondary,
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

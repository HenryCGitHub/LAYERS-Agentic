import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/agent_blueprints.dart';
import '../providers/workbench_provider.dart';
import '../theme/app_theme.dart';

/// Metadata and Agent guidance for each of the 9 focused sections in Stage 1.
class _SectionConfig {
  final String numLabel;
  final String shortTitle;
  final String title;
  final String purpose;
  final String question;
  final List<String> options;

  const _SectionConfig({
    required this.numLabel,
    required this.shortTitle,
    required this.title,
    required this.purpose,
    required this.question,
    required this.options,
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
  final TextEditingController _sparkController = TextEditingController(
    text: 'High-speed grappling hook parkour roguelite',
  );
  final TextEditingController _agentPromptController = TextEditingController();

  /// Active step index: `0`..`8` for sections `01`..`09`, and `9` for `10 · Full Review`.
  int _currentStep = 0;
  final Set<int> _visitedSteps = {0};
  final Map<int, int> _selectedOptionBySection = {
    for (int i = 0; i < 9; i++) i: 0,
  };
  final Map<int, String> _agentNotesBySection = {};

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

  static const List<_SectionConfig> _sections = [
    _SectionConfig(
      numLabel: '01',
      shortTitle: 'Goal',
      title: 'Goal',
      purpose: 'Plain-English statement of what we are building and why.',
      question: 'How should we frame the core prototype goal for v0.1?',
      options: [
        'Focus v0.1 strictly on the core movement & combat loop in a single arena',
        'Include an interactive staging area before entering wave rounds in v0.1',
        'Focus v0.1 on pure movement traversal before adding enemy waves',
      ],
    ),
    _SectionConfig(
      numLabel: '02',
      shortTitle: 'Game Spec',
      title: 'Game Spec',
      purpose: 'Camera view, player controls, mode, and arena layout.',
      question: 'Which camera perspective and control scheme fits best?',
      options: [
        '2D Top-Down · Twin-Stick (WASD + Mouse Aim) · Single-Screen Arena',
        '2D Side-Scrolling · Precision Platformer · Multi-Room Stages',
        '3D First-Person · Mouse + WASD · Enclosed Wave Arena',
      ],
    ),
    _SectionConfig(
      numLabel: '03',
      shortTitle: 'Tech Spec',
      title: 'Tech Spec',
      purpose: 'Engine, target platform, asset pipeline, and save/network architecture.',
      question: 'What engine and technical pipeline are we targeting for v0.1?',
      options: [
        'Godot 4 · PC Desktop · 2D Sprites / Greybox · Offline Local Save',
        'Unity 6 · PC & Steam Deck · 2D/3D Hybrid · Steam Cloud Save',
        'Unreal Engine 5 · PC Desktop · 3D Greybox Meshes · Local Save',
      ],
    ),
    _SectionConfig(
      numLabel: '04',
      shortTitle: 'Design Pillars',
      title: 'Design Pillars',
      purpose: 'Core player experience truths (how the game feels, never a feature list).',
      question: 'Which player experience truth should anchor our design decisions?',
      options: [
        'Prioritize unbroken movement momentum and readable enemy telegraphs',
        'Prioritize deliberate tactical positioning and high-risk parries',
        'Prioritize fast chaotic chain-reactions and screen-clearing combos',
      ],
    ),
    _SectionConfig(
      numLabel: '05',
      shortTitle: 'Trade-Offs',
      title: 'Trade-Offs (X over Y)',
      purpose: 'Explicit engineering & design priority rules when mechanics conflict.',
      question: 'When mechanics conflict during production, what wins?',
      options: [
        'Instant arcade input response over realistic physics inertia',
        'Deliberate animation commitment over instant cancelable movement',
        'Clean greybox readability over heavy visual shaders in v0.1',
      ],
    ),
    _SectionConfig(
      numLabel: '06',
      shortTitle: 'Core Loop',
      title: 'In Scope: Core Loop Beats',
      purpose: 'The sequential playable beats that make up the complete game loop.',
      question: 'How should the playable core loop Beats flow from start to reset?',
      options: [
        'Full Action Loop: Staging Prep → Traversal Entry → Wave Spawning → Primary Combat → Resource Pickup → Upgrade Choice → Loop Reset',
        'Wave Survival Loop: Loadout Select → Arena Entry → Hazard Escalation → Target Elimination → Loot Tally → Next Wave or Reset',
        'Speed Traversal Loop: Start Gate → Grapple & Dash Chain → Hazard Dodge → Target Strike → Split Time Evaluation → Instant Retry',
      ],
    ),
    _SectionConfig(
      numLabel: '07',
      shortTitle: 'Out of Scope',
      title: 'Out of Scope (Exclusions)',
      purpose: 'Hard exclusions cut from the Prototype to prevent scope creep.',
      question: 'Which scope-creep features should we explicitly cut from the Prototype?',
      options: [
        'Cut skill trees, online co-op, and story cutscenes from Prototype',
        'Also cut multi-phase bosses and town shop menus until MVP releases',
        'Also cut persistent meta-progression saves and audio settings until MVP',
      ],
    ),
    _SectionConfig(
      numLabel: '08',
      shortTitle: 'Done When',
      title: 'Done When',
      purpose: 'Observable playtest condition that proves the Prototype is complete.',
      question: 'How will we verify that the Prototype loop is done?',
      options: [
        'Playtester completes a full core loop cycle at 60 FPS with zero soft-locks',
        'Playtester clears escalating waves, collects drops, and resets cleanly',
        'Playtester beats target par time in the greybox arena without clipping',
      ],
    ),
    _SectionConfig(
      numLabel: '09',
      shortTitle: 'Prototype Release',
      title: 'Phase 1: Prototype Release',
      purpose: 'Focuses strictly on proving the Core Loop first. Subsequent phases (MVPs per Beat → Vertical Slice → Full Production) unlock as each phase completes.',
      question: 'How should we scope Phase 1 (Prototype) before unlocking MVP Beat Releases?',
      options: [
        'Single Greybox Prototype (v0.1) proving the Core Loop Beats work together',
        'Two-Step Prototype: v0.1 Movement & Controls Toy → v0.2 Core Loop Beat Connection',
      ],
    ),
  ];

  @override
  void dispose() {
    _sparkController.dispose();
    _agentPromptController.dispose();
    super.dispose();
  }

  void _goToStep(int step) {
    final clamped = step.clamp(0, _sections.length);
    setState(() {
      _visitedSteps.add(_currentStep);
      _currentStep = clamped;
      _visitedSteps.add(clamped);
    });
  }

  void _selectSectionOption(ProjectConceptBlueprint draft, int sectionIdx, int optIdx) {
    final optionText = _sections[sectionIdx].options[optIdx];
    setState(() {
      _selectedOptionBySection[sectionIdx] = optIdx;
      _agentNotesBySection[sectionIdx] =
          'Agent updated ${_sections[sectionIdx].title}: Applied "$optionText".';
    });
    _applySectionOptionDeterministic(draft, sectionIdx, optIdx);
  }

  void _applySectionOptionDeterministic(
    ProjectConceptBlueprint draft,
    int sectionIdx,
    int optIdx,
  ) {
    widget.workbench.updateConceptDraft((d) {
      switch (sectionIdx) {
        case 0:
          if (optIdx == 0) {
            d.goal =
                'Build a playable ${d.title} prototype centered on ${d.sparkIdea} with immediate loop feedback in a single arena.';
          } else if (optIdx == 1) {
            d.goal =
                'Build a ${d.title} prototype connecting an interactive prep room to repeatable arena waves.';
          } else {
            d.goal =
                'Build a high-speed ${d.title} movement traversal prototype proving core control feel before adding combat.';
          }
          break;
        case 1:
          if (optIdx == 0) {
            d.gameSpec = [
              '2D Top-Down',
              'Twin-Stick (WASD + Aim)',
              'Singleplayer',
              'Single-Screen Wave Arena',
            ];
          } else if (optIdx == 1) {
            d.gameSpec = [
              '2D Side-Scrolling',
              'Precision Platformer',
              'Singleplayer',
              'Multi-Room Obstacle Course',
            ];
          } else {
            d.gameSpec = [
              '3D First-Person',
              'Mouse + WASD',
              'Singleplayer',
              'Enclosed Wave Arena',
            ];
          }
          break;
        case 2:
          if (optIdx == 0) {
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
          if (optIdx == 0) {
            d.designPillars = [
              'Flow-State Momentum: Never force the player to stop moving to act or aim.',
              'Readable Chaos: Every hazard and attack is clearly telegraphed before impact.',
              'Every Run Teaches Something: Failures feel fair, fast to recover from, and immediately repeatable.',
            ];
          } else if (optIdx == 1) {
            d.designPillars = [
              'Tactical Positioning: Every dodge and parry rewards reading enemy spacing.',
              'High-Clarity Telegraphs: Audio and visual cues always precede heavy strikes.',
              'Fast Recovery: Mistakes punish health, never control responsiveness.',
            ];
          } else {
            d.designPillars = [
              'Chain-Reaction Payoff: Every combo triggers visible arena-wide feedback.',
              'Relentless Tempo: Zero downtime between wave spawns and movement bursts.',
              'Instant Readability: Silhouettes stay crisp even during peak particle bursts.',
            ];
          }
          break;
        case 4:
          if (optIdx == 0) {
            d.tradeOffs = [
              'Instant arcade input response over realistic physics inertia',
              'Clear silhouette readability over dense particle clutter',
              'Fast 1-key loop reset over multi-screen menu flows',
            ];
          } else if (optIdx == 1) {
            d.tradeOffs = [
              'Deliberate animation commitment over instant cancelable movement',
              'Crisp hitbox accuracy over forgiving auto-aim assist',
              'Fast 1-key loop reset over multi-screen menu flows',
            ];
          } else {
            d.tradeOffs = [
              'Clean greybox readability over heavy visual shaders in v0.1',
              'Locked 60 FPS frame pacing over high-poly environment detail',
              'Single-arena depth over multiple unfinished levels',
            ];
          }
          break;
        case 5:
          if (optIdx == 0) {
            d.coreLoopBeats = [
              'Staging & Loadout Prep: Select active tool or movement modifier in the starting zone',
              'Arena Entry & Traversal: Enter the arena and chain primary movement impulses across terrain',
              'Hazard & Wave Spawning: Trigger room encounters with telegraphed enemy waves and active hazards',
              'Primary Combat & Timing: Strike targets using momentum windows, deflection, and dodge recovery',
              'Resource Drop & Pickup: Collect dropped energy, ammo, or health orbs mid-encounter',
              'Room Clear & Upgrade Choice: Complete wave objective and select a run-modifying upgrade',
              'Loop Resolution & Instant Reset: Bank round results or trigger 1-key arena reset on failure',
            ];
          } else if (optIdx == 1) {
            d.coreLoopBeats = [
              'Loadout Select: Pick primary weapon and passive perk in the staging room',
              'Arena Entry: Drop into the active wave arena and establish movement flow',
              'Hazard Escalation: Dodge telegraphed floor hazards and incoming enemy projectiles',
              'Target Elimination: Defeat wave enemies using primary and secondary attacks',
              'Loot Tally: Gather dropped currency and health pickups before timer expires',
              'Wave Upgrade Choice: Pick a stat boost between waves',
              'Run Resolution & Reset: Clear final wave or reset immediately on defeat',
            ];
          } else {
            d.coreLoopBeats = [
              'Start Gate Launch: Trigger initial speed burst out of the starting gate',
              'Grapple & Dash Chain: Link grappling swings and air dashes across gaps',
              'Hazard Dodge: Navigate moving obstacles without losing velocity',
              'Target Strike: Hit checkpoint targets mid-flight to extend boost meter',
              'Split Time Evaluation: Cross finish beacon and compare split rank',
              'Instant Retry: Reset to start gate in a single keypress',
            ];
          }
          break;
        case 6:
          if (optIdx == 0) {
            d.exclusions = [
              'Multi-branch skill trees and deep inventory crafting menus',
              'Online multiplayer matchmaking and netcode replication',
              'Cinematic story cutscenes and NPC dialogue trees',
            ];
          } else if (optIdx == 1) {
            d.exclusions = [
              'Multi-branch skill trees and deep inventory crafting menus',
              'Multi-phase boss encounters and town shop menus (deferred to MVP releases)',
              'Online multiplayer matchmaking and netcode replication',
            ];
          } else {
            d.exclusions = [
              'Persistent meta-progression save files (deferred to MVP releases)',
              'Custom keybind & audio mixer menus in v0.1',
              'Online multiplayer matchmaking and story cutscenes',
            ];
          }
          break;
        case 7:
          if (optIdx == 0) {
            d.doneWhen =
                'Playtester completes a full core loop cycle at 60 FPS with responsive controls and zero state soft-locks.';
          } else if (optIdx == 1) {
            d.doneWhen =
                'Playtester clears escalating waves, collects drops, and resets the arena with zero collisions or soft-locks.';
          } else {
            d.doneWhen =
                'Playtester completes the greybox obstacle course under par time with zero wall-clipping or input drops.';
          }
          break;
        case 8:
          if (optIdx == 0) {
            d.releaseTrainTitles = [
              'v0.1: Core Toy & Movement Loop - Prototype',
            ];
          } else {
            d.releaseTrainTitles = [
              'v0.1: Greybox Movement & Control Toy - Prototype',
              'v0.2: Core Loop Beat Connection - Prototype',
            ];
          }
          break;
      }
    });
  }

  Future<void> _submitSectionPrompt(ProjectConceptBlueprint draft, int sectionIdx) async {
    final text = _agentPromptController.text.trim();
    if (text.isEmpty || widget.workbench.isAgentBusy) return;
    _agentPromptController.clear();

    final sec = _sections[sectionIdx];
    await widget.workbench.sendConceptChatMessage('[Section ${sec.numLabel} ${sec.title}] $text');
    if (!mounted) return;
    setState(() {
      _agentNotesBySection[sectionIdx] =
          'Agent updated ${sec.title} based on your direction: "$text"';
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
              constraints: const BoxConstraints(maxWidth: 760),
              child: _buildInitialSparkLauncher(),
            ),
          ),
        ),
      );
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
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1020),
                  child: _currentStep < _sections.length
                      ? _buildFocusedSectionWorkspace(draft, _currentStep)
                      : _buildFullReviewWorkspace(draft),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Initial Spark Launcher (Before Concept Draft Exists) ────────────────────
  Widget _buildInitialSparkLauncher() {
    const sampleSparks = [
      'High-speed grappling hook parkour roguelite',
      'Cozy 2D submarine salvage & deep-sea creature photography',
      'Top-down cyberpunk katana deflection boss-rush arena',
    ];

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
                  'STEP 1A · THE SPARK',
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
                  'Pitch your game idea to build your Concept Blueprint',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Enter a 1-sentence game idea. The Agent will draft all 9 blueprint sections so you can review and refine them one focused section at a time.',
            style: GoogleFonts.inter(fontSize: 13, color: _textSecondary),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('spark_input_field'),
                  controller: _sparkController,
                  style: GoogleFonts.inter(fontSize: 14, color: _textPrimary),
                  decoration: InputDecoration(
                    hintText: 'e.g., High-speed grappling hook parkour roguelite...',
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
                  onSubmitted: (_) =>
                      widget.workbench.startConceptInterview(_sparkController.text),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                key: const ValueKey('start_concept_interview_btn'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _focalAccent,
                  foregroundColor: _focalAccentFg,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                  elevation: 0,
                ),
                onPressed: widget.workbench.isAgentBusy
                    ? null
                    : () =>
                        widget.workbench.startConceptInterview(_sparkController.text),
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
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in sampleSparks)
                InkWell(
                  onTap: () {
                    _sparkController.text = s;
                    widget.workbench.startConceptInterview(s);
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _bgRecessed,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: _borderSubtle),
                    ),
                    child: Text(
                      s,
                      style: GoogleFonts.inter(fontSize: 11.5, color: _textSecondary),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Horizontal Stepper Rail (`01 Goal` ... `09 Release Train` + `10 Full Review`) ─
  Widget _buildStepperRail(ProjectConceptBlueprint draft) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: _bgSurface,
        border: Border(bottom: BorderSide(color: _borderSubtle)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (int i = 0; i < _sections.length; i++) ...[
              _buildStepNode(
                index: i,
                numText: _visitedSteps.contains(i) && _currentStep != i
                    ? '✓'
                    : _sections[i].numLabel,
                label: _sections[i].shortTitle,
                isActive: _currentStep == i,
                isDone: _visitedSteps.contains(i) && _currentStep != i,
              ),
              if (i < _sections.length - 1)
                Container(
                  width: 8,
                  height: 1,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  color: _borderSubtle,
                ),
            ],
            Container(
              width: 14,
              height: 1,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              color: _borderBright,
            ),
            _buildStepNode(
              key: const ValueKey('synthesize_concept_btn'),
              index: _sections.length,
              numText: '10',
              label: 'Full Review',
              isActive: _currentStep == _sections.length,
              isDone: false,
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
            color: isActive ? _textPrimary : Colors.transparent,
            width: isActive ? 1.6 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 18,
              height: 18,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isActive
                    ? _focalAccent
                    : (isDone ? _bgHover : _bgRecessed),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                  color: isActive
                      ? _focalAccent
                      : (isDone ? _borderBright : _borderSubtle),
                ),
              ),
              child: Text(
                numText,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  color: isActive
                      ? _focalAccentFg
                      : (isDone ? _textPrimary : _textMuted),
                ),
              ),
            ),
            const SizedBox(width: 6),
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
      ),
    );
  }

  // ── Steps `01`–`09`: Focused Single-Section Workspace ───────────────────────
  Widget _buildFocusedSectionWorkspace(ProjectConceptBlueprint draft, int sectionIdx) {
    final sec = _sections[sectionIdx];
    final selectedOpt = _selectedOptionBySection[sectionIdx] ?? 0;
    final agentNote = _agentNotesBySection[sectionIdx];
    final nextTitle = sectionIdx + 1 < _sections.length
        ? 'Next: ${_sections[sectionIdx + 1].shortTitle} →'
        : 'Next: Full Blueprint Review →';

    return Container(
      decoration: BoxDecoration(
        color: _bgSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Project Context Strip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: _bgRecessed,
              border: Border(bottom: BorderSide(color: _borderSubtle)),
            ),
            child: Row(
              children: [
                Text(
                  'PROJECT: ${draft.title.toUpperCase()}',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _textPrimary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Spark: "${draft.sparkIdea}"',
                    style: GoogleFonts.inter(fontSize: 11.5, color: _textMuted),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  'SECTION ${sec.numLabel} OF 09',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: _textSecondary,
                  ),
                ),
              ],
            ),
          ),

          // ZONE 1: THE ARTIFACT SPEC (Elevated Surface, 2-Column Layout)
          Padding(
            padding: const EdgeInsets.all(24),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 640;
                final leftHeader = Container(
                  padding: const EdgeInsets.only(left: 12),
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(color: _focalAccent, width: 3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SECTION ${sec.numLabel} / 09',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                          color: _textMuted,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        sec.title,
                        style: GoogleFonts.inter(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: _textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        sec.purpose,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          height: 1.45,
                          color: _textSecondary,
                        ),
                      ),
                    ],
                  ),
                );

                final rightWidget = _buildSectionContentWidget(draft, sectionIdx);

                if (!isWide) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      leftHeader,
                      const SizedBox(height: 16),
                      rightWidget,
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 210, child: leftHeader),
                    const SizedBox(width: 24),
                    Expanded(child: rightWidget),
                  ],
                );
              },
            ),
          ),

          // ZONE 2: THE AGENT CONSOLE (Recessed Inset Well)
          Container(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
            decoration: BoxDecoration(
              color: _bgRecessed,
              border: Border(
                top: BorderSide(color: _borderSubtle),
                bottom: BorderSide(color: _borderSubtle),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: _bgSurface,
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(color: _borderBright),
                      ),
                      child: Text(
                        'AGENT · ${widget.workbench.conversationModel.toUpperCase()}',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: _textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        sec.question,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Clickable Radio Option Cards
                for (int optIdx = 0; optIdx < sec.options.length; optIdx++) ...[
                  _buildAgentOptionCard(
                    draft: draft,
                    sectionIdx: sectionIdx,
                    optIdx: optIdx,
                    label: sec.options[optIdx],
                    isSelected: selectedOpt == optIdx,
                  ),
                  const SizedBox(height: 6),
                ],

                const SizedBox(height: 6),

                // [ASK AGENT] Input Bar
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _bgSurface,
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
                                color: _textMuted,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                key: const ValueKey('concept_chat_input_field'),
                                controller: _agentPromptController,
                                style: GoogleFonts.inter(
                                  fontSize: 12.5,
                                  color: _textPrimary,
                                ),
                                decoration: InputDecoration(
                                  hintText:
                                      'Tell the Agent how to change or expand ${sec.title}...',
                                  hintStyle: GoogleFonts.inter(
                                    fontSize: 12,
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
                        backgroundColor: _bgSurface,
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
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),

                if (agentNote != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(color: _borderBright, width: 2),
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

          // ZONE 3: SECTION NAVIGATION BAR
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            color: _bgSurface,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                OutlinedButton(
                  onPressed: sectionIdx == 0
                      ? null
                      : () => _goToStep(sectionIdx - 1),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _textPrimary,
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
          ),
        ],
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
    return InkWell(
      onTap: () => _selectSectionOption(draft, sectionIdx, optIdx),
      borderRadius: BorderRadius.circular(5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: isSelected ? _bgHover : _bgSurface,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: isSelected ? _textPrimary : _borderSubtle,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
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
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                  color: isSelected ? _textPrimary : _textSecondary,
                ),
              ),
            ),
            if (optIdx == 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: _borderSubtle),
                ),
                child: Text(
                  'RECOMMENDED',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: _textMuted,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── 6 Distinct Structural Section Layouts (Grayscale-Proof) ─────────────────
  Widget _buildSectionContentWidget(ProjectConceptBlueprint draft, int sectionIdx) {
    switch (sectionIdx) {
      case 0: // 01 Goal — Callout Blockquote
        return _buildCalloutStatement(draft.goal);
      case 1: // 02 Game Spec — 2×2 Key-Value Spec Grid
        return _buildKvSpecGrid(
          keys: const ['CAMERA VIEW', 'CONTROLS', 'PLAYER MODE', 'ARENA STRUCTURE'],
          values: draft.gameSpec,
        );
      case 2: // 03 Tech Spec — 2×2 Key-Value Spec Grid
        return _buildKvSpecGrid(
          keys: const ['ENGINE', 'PLATFORM', 'ASSET PIPELINE', 'NETWORK / SAVE'],
          values: draft.techSpec,
        );
      case 3: // 04 Design Pillars — Indexed Rows (P·01, P·02, P·03)
        return _buildIndexedRows(prefix: 'P', items: draft.designPillars);
      case 4: // 05 Trade-Offs — Split X OVER Y Comparison Bars
        return _buildTradeOffSplitBars(draft.tradeOffs);
      case 5: // 06 Core Loop — Indexed Beat Rows (BEAT·01, BEAT·02, BEAT·03)
        return _buildIndexedRows(prefix: 'BEAT', items: draft.coreLoopBeats);
      case 6: // 07 Out of Scope — Guardrail Chips with [CUT] Badge
        return _buildCutGuardrailChips(draft.exclusions);
      case 7: // 08 Done When — Acceptance Callout Statement
        return _buildCalloutStatement(draft.doneWhen);
      case 8: // 09 Release Train — 3-Column Horizontal Pipeline
      default:
        return _buildReleaseTrainPipeline(draft.releaseTrainTitles);
    }
  }

  Widget _buildCalloutStatement(String statement) {
    return Container(
      decoration: BoxDecoration(
        color: _bgRecessed,
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
              color: _focalAccent,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Text(
                  statement,
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    height: 1.5,
                    color: _textPrimary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKvSpecGrid({
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
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _buildKvCell(pairs[0].key, pairs[0].value, rightBorder: true, bottomBorder: true)),
              Expanded(child: _buildKvCell(pairs[1].key, pairs[1].value, rightBorder: false, bottomBorder: true)),
            ],
          ),
          Row(
            children: [
              Expanded(child: _buildKvCell(pairs[2].key, pairs[2].value, rightBorder: true, bottomBorder: false)),
              Expanded(child: _buildKvCell(pairs[3].key, pairs[3].value, rightBorder: false, bottomBorder: false)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKvCell(
    String k,
    String v, {
    required bool rightBorder,
    required bool bottomBorder,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: _bgSurface,
        border: Border(
          right: rightBorder ? BorderSide(color: _borderSubtle) : BorderSide.none,
          bottom: bottomBorder ? BorderSide(color: _borderSubtle) : BorderSide.none,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            k,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
              color: _textMuted,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            v,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIndexedRows({
    required String prefix,
    required List<String> items,
  }) {
    return Column(
      children: [
        for (int i = 0; i < items.length; i++) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: _bgRecessed,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: _borderSubtle),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _bgSurface,
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: _borderBright),
                  ),
                  child: Text(
                    '$prefix·${(i + 1).toString().padLeft(2, '0')}',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: _textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    items[i],
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      height: 1.4,
                      color: _textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (i < items.length - 1) const SizedBox(height: 7),
        ],
      ],
    );
  }

  Widget _buildTradeOffSplitBars(List<String> tradeOffs) {
    return Column(
      children: [
        for (int i = 0; i < tradeOffs.length; i++) ...[
          _buildSingleTradeOffBar(tradeOffs[i]),
          if (i < tradeOffs.length - 1) const SizedBox(height: 7),
        ],
      ],
    );
  }

  Widget _buildSingleTradeOffBar(String rawRule) {
    final clean = rawRule.replaceFirst(RegExp(r'^Prioritize\s+', caseSensitive: false), '');
    final parts = clean.split(RegExp(r'\s+over\s+', caseSensitive: false));
    final winText = parts.isNotEmpty ? parts[0].trim() : clean;
    final loseText = parts.length > 1 ? parts.sublist(1).join(' over ').trim() : 'secondary complexity';

    return Container(
      decoration: BoxDecoration(
        color: _bgRecessed,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: _borderSubtle),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Text(
                  '✓ $winText',
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: _textPrimary,
                  ),
                ),
              ),
            ),
            Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: _bgSurface,
                border: Border(
                  left: BorderSide(color: _borderSubtle),
                  right: BorderSide(color: _borderSubtle),
                ),
              ),
              child: Text(
                'OVER',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  color: _textMuted,
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Text(
                  loseText,
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    color: _textMuted,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCutGuardrailChips(List<String> exclusions) {
    return Column(
      children: [
        for (int i = 0; i < exclusions.length; i++) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: _bgRecessed,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: _borderBright),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: _borderSubtle),
                  ),
                  child: Text(
                    'CUT',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: _textMuted,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    exclusions[i],
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: _textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (i < exclusions.length - 1) const SizedBox(height: 7),
        ],
      ],
    );
  }

  Widget _buildReleaseTrainPipeline(List<String> releases) {
    const lockedPhases = [
      ProductionPhase.mvp,
      ProductionPhase.verticalSlice,
      ProductionPhase.fullProduction,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Active Phase 1: Prototype Release(s)
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
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    ProductionPhase.prototype.label,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: _textPrimary,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: _focalAccent,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      'ACTIVE PHASE',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: _focalAccentFg,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                ProductionPhase.prototype.summary,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: _textSecondary,
                ),
              ),
              const SizedBox(height: 10),
              for (int i = 0; i < releases.length; i++) ...[
                _buildReleaseStepCard(releases[i], isFirst: i == 0, index: i),
                if (i < releases.length - 1) const SizedBox(height: 8),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        // Locked Future Production Phases (Defined One Phase at a Time After Completion)
        for (int pIdx = 0; pIdx < lockedPhases.length; pIdx++) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _bgRecessed,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: _borderSubtle),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _bgSurface,
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: _borderSubtle),
                  ),
                  child: Text(
                    'LOCKED',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: _textMuted,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            lockedPhases[pIdx].label,
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: _textSecondary,
                            ),
                          ),
                          Text(
                            lockedPhases[pIdx].unlockCondition,
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 9.5,
                              color: _textMuted,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        lockedPhases[pIdx].summary,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: _textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (pIdx < lockedPhases.length - 1) const SizedBox(height: 6),
        ],
      ],
    );
  }

  Widget _buildReleaseStepCard(String fullTitle, {required bool isFirst, required int index}) {
    final verTag = isFirst ? 'v0.1 · ACTIVE TARGET' : 'v0.${index + 1} · QUEUED';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isFirst ? _bgSurface : _bgRecessed,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isFirst ? _textPrimary : _borderSubtle,
          width: isFirst ? 1.8 : 1.0,
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
                  fontWeight: FontWeight.w700,
                  color: isFirst ? _textPrimary : _textMuted,
                ),
              ),
              Text(
                isFirst ? '▶' : '○',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  color: isFirst ? _textPrimary : _textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            fullTitle,
            style: GoogleFonts.inter(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: isFirst ? _textPrimary : _textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  // ── Step `10 · Full Review`: Clean Full-Width Blueprint Sheet ───────────────
  Widget _buildFullReviewWorkspace(ProjectConceptBlueprint draft) {
    return Container(
      key: const ValueKey('project_blueprint_card'),
      decoration: BoxDecoration(
        color: _bgSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Single-Line Banner Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            decoration: BoxDecoration(
              color: _bgRecessed,
              border: Border(bottom: BorderSide(color: _borderSubtle)),
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
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: _textMuted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${draft.title} — Complete Project Concept Blueprint',
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: _textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Review all 9 sections below. Click Revisit on any section to adjust it with the Agent.',
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        color: _textSecondary,
                      ),
                    ),
                  ],
                ),
                ElevatedButton(
                  key: const ValueKey('approve_concept_plan_release_btn'),
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
                    ),
                  ),
                  child: Text(
                    widget.workbench.isAgentBusy
                        ? 'Generating Release Plan...'
                        : 'Approve & Plan v0.1 Release →',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 01 Goal (Full Width)
          _buildFullReviewBlock(
            sectionIdx: 0,
            child: _buildSectionContentWidget(draft, 0),
          ),

          // 02 Game Spec + 03 Tech Spec (50/50 Side-by-Side Row)
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 680) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildFullReviewBlock(
                      sectionIdx: 1,
                      child: _buildSectionContentWidget(draft, 1),
                    ),
                    _buildFullReviewBlock(
                      sectionIdx: 2,
                      child: _buildSectionContentWidget(draft, 2),
                    ),
                  ],
                );
              }
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border(right: BorderSide(color: _borderSubtle)),
                        ),
                        child: _buildFullReviewBlock(
                          sectionIdx: 1,
                          child: _buildSectionContentWidget(draft, 1),
                        ),
                      ),
                    ),
                    Expanded(
                      child: _buildFullReviewBlock(
                        sectionIdx: 2,
                        child: _buildSectionContentWidget(draft, 2),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

          // 04 Design Pillars through 09 Release Train (Full Width Blocks)
          for (int idx = 3; idx < _sections.length; idx++)
            _buildFullReviewBlock(
              sectionIdx: idx,
              child: _buildSectionContentWidget(draft, idx),
              isLast: idx == _sections.length - 1,
            ),
        ],
      ),
    );
  }

  Widget _buildFullReviewBlock({
    required int sectionIdx,
    required Widget child,
    bool isLast = false,
  }) {
    final sec = _sections[sectionIdx];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      decoration: BoxDecoration(
        border: Border(
          bottom: isLast ? BorderSide.none : BorderSide(color: _borderSubtle),
        ),
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
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: _textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    sec.title.toUpperCase(),
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                      color: _textPrimary,
                    ),
                  ),
                ],
              ),
              OutlinedButton(
                onPressed: () => _goToStep(sectionIdx),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _textSecondary,
                  backgroundColor: _bgRecessed,
                  side: BorderSide(color: _borderSubtle),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

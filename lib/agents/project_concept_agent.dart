import 'dart:convert';
import '../constants/text_style_guide.dart';
import '../models/agent_blueprints.dart';
import '../models/epic_spec.dart';
import '../utils/unreal_spec_guard.dart';
import 'gemini_agent_client.dart';

/// Stage 1 Unreal Co-Designer Agent (`1. Project Spec` -> `PROJECT_SPEC.md`).
/// Generates the high-level Unreal foundation (`§01–§04`) and strictly `v0.1` Epics (`§05`),
/// and applies natural-language Co-Designer revisions cleanly in a single pass.
class ProjectConceptAgent {
  static Map<String, dynamic> get _rootSpecToolSchema => <String, dynamic>{
        'name': 'commit_unreal_root_spec',
        'description':
            'Create or update the Unreal Engine Project Spec (`ROOT_MCP_CONTEXT`) with §01-§04 foundation contracts and strictly v0.1 prototype Epics in §05 (each complete with §01-§06).',
        'parameters': <String, dynamic>{
          'type': 'OBJECT',
          'required': [
            'gameTitle',
            'pitch',
            'coreLoop',
            'cameraChoiceId',
            'cameraContract',
            'characterScale',
            'inputContract',
            'assetPolicy',
            'pillars',
            'tradeOffs',
            'outOfScope',
            'releaseDoneWhen',
            'initialEpics',
          ],
          'properties': <String, dynamic>{
            'gameTitle': {
              'type': 'STRING',
              'description': '2-3 word plain game title in UPPERCASE.',
            },
            'pitch': {
              'type': 'STRING',
              'description': LayersTextStyleGuide.blufVisionSchemaDesc,
            },
            'coreLoop': {
              'type': 'ARRAY',
              'items': {
                'type': 'STRING',
                'description': LayersTextStyleGuide.coreLoopStepSchemaDesc,
              },
            },
            'cameraChoiceId': {
              'type': 'STRING',
              'enum': ['isometric', 'topdown', 'tps'],
            },
            'cameraContract': {
              'type': 'STRING',
              'description': LayersTextStyleGuide.unrealContractSchemaDesc,
            },
            'characterScale': {
              'type': 'STRING',
              'description':
                  'Player actor capsule radius/height in cm and walk/run speed in cm/s.',
            },
            'inputContract': {
              'type': 'STRING',
              'description':
                  'Enhanced Input Mapping Context + primary InputActions (e.g. IMC_Core + IA_Move, IA_Fire).',
            },
            'assetPolicy': {
              'type': 'STRING',
              'description':
                  'Prototype greybox policy + UDataAsset / @editable tuning location.',
            },
            'cameraDecisionOptions': {
              'type': 'ARRAY',
              'items': {
                'type': 'OBJECT',
                'required': ['id', 'label', 'contractValue'],
                'properties': {
                  'id': {'type': 'STRING'},
                  'label': {'type': 'STRING'},
                  'contractValue': {'type': 'STRING'},
                  'note': {'type': 'STRING'},
                },
              },
            },
            'pillars': {
              'type': 'ARRAY',
              'items': {
                'type': 'STRING',
                'description': LayersTextStyleGuide.pillarSchemaDesc,
              },
            },
            'tradeOffs': {
              'type': 'ARRAY',
              'items': {
                'type': 'OBJECT',
                'required': ['prefer', 'avoid'],
                'properties': {
                  'prefer': {'type': 'STRING'},
                  'avoid': {'type': 'STRING'},
                },
              },
            },
            'outOfScope': {
              'type': 'ARRAY',
              'items': {
                'type': 'STRING',
                'description': LayersTextStyleGuide.exclusionItemSchemaDesc,
              },
            },
            'releaseDoneWhen': {
              'type': 'STRING',
              'description': LayersTextStyleGuide.causalPieCheckSchemaDesc,
            },
            'initialEpics': {
              'type': 'ARRAY',
              'description':
                  'Strictly 3-4 v0.1 playable prototype Epics only (defer later features to v0.2+).',
              'items': _epicJsonSchema,
            },
            'coDesignNote': {
              'type': 'STRING',
              'description': 'Short 1-line summary of the spec changes applied.',
            },
          },
        },
      };

  static Map<String, dynamic> get _epicJsonSchema => <String, dynamic>{
        'type': 'OBJECT',
        'required': [
          'code',
          'title',
          'goal',
          'links',
          'outOfScope',
          'controls',
          'states',
          'interrupts',
          'tuning',
          'feedback',
          'levelStaging',
          'checks',
        ],
        'properties': <String, dynamic>{
          'code': {
            'type': 'STRING',
            'description': 'Sequential code E01, E02, E03...',
          },
          'title': {
            'type': 'STRING',
            'description': LayersTextStyleGuide.epicTitleSchemaDesc,
          },
          'goal': {
            'type': 'STRING',
            'description': '1 plain sentence describing the playable Epic system.',
          },
          'links': {
            'type': 'ARRAY',
            'items': {'type': 'STRING'},
          },
          'outOfScope': {
            'type': 'ARRAY',
            'items': {'type': 'STRING'},
          },
          'controls': {
            'type': 'ARRAY',
            'items': {
              'type': 'OBJECT',
              'required': ['action', 'trigger', 'rule'],
              'properties': {
                'action': {'type': 'STRING'},
                'trigger': {'type': 'STRING'},
                'rule': {
                  'type': 'STRING',
                  'description': LayersTextStyleGuide.unrealControlRuleSchemaDesc,
                },
              },
            },
          },
          'states': {
            'type': 'ARRAY',
            'items': {'type': 'STRING'},
          },
          'interrupts': {
            'type': 'ARRAY',
            'items': {'type': 'STRING'},
          },
          'tuning': {
            'type': 'ARRAY',
            'items': {
              'type': 'OBJECT',
              'required': ['key', 'value', 'unit'],
              'properties': {
                'key': {'type': 'STRING'},
                'value': {'type': 'STRING'},
                'unit': {
                  'type': 'STRING',
                  'description': LayersTextStyleGuide.unrealTuningUnitSchemaDesc,
                },
              },
            },
          },
          'feedback': {
            'type': 'ARRAY',
            'items': {'type': 'STRING'},
          },
          'levelStaging': {'type': 'STRING'},
          'checks': {
            'type': 'ARRAY',
            'items': {
              'type': 'OBJECT',
              'required': ['text'],
              'properties': {
                'text': {
                  'type': 'STRING',
                  'description': LayersTextStyleGuide.causalPieCheckSchemaDesc,
                },
              },
            },
          },
        },
      };

  /// Synthesizes a complete Unreal Root Project Spec + 3 `v0.1` Epics from a 1-sentence spark.
  static Future<ProjectConceptBlueprint> draftSpecFromSpark({
    required String sparkPrompt,
    required String apiKey,
    UnrealTargetEngine targetEngine = UnrealTargetEngine.ue5Mcp,
    String preferredModel = GeminiAgentClient.pinnedLiveFlashModel,
    String thinkingLevel = 'LOW',
  }) async {
    final trimmedSpark = sparkPrompt.trim();
    final matchedPreset = UnrealSparkPresets.matchSparkPrompt(trimmedSpark);

    if (!GeminiAgentClient.hasKey(apiKey)) {
      final fallback =
          (matchedPreset ?? _buildSynthesizedFallback(trimmedSpark))
              .deepCopy();
      fallback.targetEngine = targetEngine;
      if (trimmedSpark.isNotEmpty) {
        fallback.sparkPrompt = trimmedSpark;
      }
      return UnrealSpecGuard.sanitizeConceptBlueprint(fallback);
    }

    final prompt = '''
${LayersTextStyleGuide.compactStyleRules}

You are the LAYERS Unreal Engine Project Co-Designer.
Generate a clean, build-ready Stage 1 Project Spec (`PROJECT_SPEC.md` -> `ROOT_MCP_CONTEXT`) for this game idea:
USER SPARK: "$trimmedSpark"
TARGET ARCHITECTURE: ${targetEngine.fullLabel} (${targetEngine.architectureContract})

CRITICAL CONSTRAINTS:
- Produce strictly `v0.1` Prototype Epics in `initialEpics` (3 Epics total: E01 Player Core, E02 Primary Action/Mechanic, E03 Target/Challenge/Loop Closure).
- Defer meta-progression, menus, save slots, inventory UI, and Wave/Boss content to `outOfScope` and future `v0.2+` releases.
- Use Unreal Engine 1 UU = 1 cm units (`cm`, `cm/s`, `deg`, `s`, `hp`) everywhere in §02 and every Epic's §04 tuning variables.
- Each Epic in `initialEpics` MUST include full §01–§06 sections so clicking Approve launches Unreal MCP immediately with zero missing fields.
''';

    final res = await GeminiAgentClient.generateJson(
      prompt: prompt,
      apiKey: apiKey,
      preferredModel: preferredModel,
      thinkingLevel: thinkingLevel,
      temperature: 0.4,
      functionDeclarations: [_rootSpecToolSchema],
    );

    if (res != null) {
      final parsed = ProjectConceptBlueprint.fromJson(res);
      parsed.sparkPrompt =
          trimmedSpark.isEmpty ? parsed.sparkPrompt : trimmedSpark;
      parsed.targetEngine = targetEngine;
      if (parsed.initialEpics.isNotEmpty) {
        for (int i = 0; i < parsed.initialEpics.length; i++) {
          final ep = parsed.initialEpics[i];
          ep.code = 'E0${i + 1}';
          ep.lineageKey = 'e0${i + 1}';
          ep.releaseVersion = 'v0.1';
          ep.lifecycle =
              i == 0 ? EpicLifecycle.active : EpicLifecycle.queued;
        }
        return UnrealSpecGuard.sanitizeConceptBlueprint(parsed);
      }
    }

    final fallback =
        (matchedPreset ?? _buildSynthesizedFallback(trimmedSpark)).deepCopy();
    fallback.targetEngine = targetEngine;
    if (trimmedSpark.isNotEmpty) {
      fallback.sparkPrompt = trimmedSpark;
    }
    return UnrealSpecGuard.sanitizeConceptBlueprint(fallback);
  }

  /// Applies a user's Co-Designer instruction directly onto an active Stage 1 [ProjectConceptBlueprint].
  static Future<ProjectConceptBlueprint> applyCoDesignEdit({
    required ProjectConceptBlueprint currentSpec,
    required String instruction,
    required String apiKey,
    String preferredModel = GeminiAgentClient.pinnedLiveFlashModel,
    String thinkingLevel = 'LOW',
  }) async {
    final trimmed = instruction.trim();
    if (trimmed.isEmpty) return currentSpec;

    if (!GeminiAgentClient.hasKey(apiKey)) {
      return _applyOfflineCoDesignEdit(currentSpec, trimmed);
    }

    final prompt = '''
${LayersTextStyleGuide.compactStyleRules}

Update the Unreal Engine Root Project Spec (`ROOT_MCP_CONTEXT`) below according to the user's instruction.
Return the complete updated JSON via `commit_unreal_root_spec`, preserving existing approved sections unless the instruction asks to change them.
Keep all `initialEpics` strictly at `v0.1` prototype scope and 1 UU = 1 cm units.

CURRENT SPEC JSON:
${jsonEncode(currentSpec.toJson())}

USER CO-DESIGN INSTRUCTION:
"$trimmed"
''';

    final res = await GeminiAgentClient.generateJson(
      prompt: prompt,
      apiKey: apiKey,
      preferredModel: preferredModel,
      thinkingLevel: thinkingLevel,
      temperature: 0.35,
      functionDeclarations: [_rootSpecToolSchema],
    );

    if (res != null) {
      final parsed = ProjectConceptBlueprint.fromJson(res);
      parsed.sparkPrompt = currentSpec.sparkPrompt;
      parsed.targetEngine = currentSpec.targetEngine;
      parsed.lastCoDesignNote =
          (res['coDesignNote'] ?? 'Updated spec from: $trimmed')
              .toString()
              .trim();
      if (parsed.initialEpics.isNotEmpty) {
        for (int i = 0; i < parsed.initialEpics.length; i++) {
          final ep = parsed.initialEpics[i];
          ep.code = 'E0${i + 1}';
          ep.lineageKey = 'e0${i + 1}';
          ep.releaseVersion = 'v0.1';
          if (i == 0 && ep.lifecycle == EpicLifecycle.queued) {
            ep.lifecycle = EpicLifecycle.active;
          }
        }
        return UnrealSpecGuard.sanitizeConceptBlueprint(parsed);
      }
    }

    return _applyOfflineCoDesignEdit(currentSpec, trimmed);
  }

  static ProjectConceptBlueprint _applyOfflineCoDesignEdit(
    ProjectConceptBlueprint current,
    String instruction,
  ) {
    final next = current.deepCopy();
    final lower = instruction.toLowerCase();

    if (lower.contains('third person') ||
        lower.contains('tps') ||
        lower.contains('over-shoulder') ||
        lower.contains('over shoulder')) {
      next.cameraChoiceId = 'tps';
      next.cameraContract =
          'SpringArm 380 cm · SocketOffset (0, 65, 55) cm · 68 deg FOV · CameraLag 10.0';
      next.lastCoDesignNote = 'Switched §02 Camera contract to Third-Person.';
    } else if (lower.contains('top-down') || lower.contains('top down')) {
      next.cameraChoiceId = 'topdown';
      next.cameraContract =
          'SpringArm 1650 cm @ -88 deg pitch, 50 deg FOV, Fixed Arena Framing';
      next.lastCoDesignNote = 'Switched §02 Camera contract to Fixed Top-Down.';
    } else if (lower.contains('isometric')) {
      next.cameraChoiceId = 'isometric';
      next.cameraContract =
          'SpringArm 1450 cm @ -52 deg pitch, 55 deg FOV, CameraLag 9.0';
      next.lastCoDesignNote = 'Switched §02 Camera contract to Isometric.';
    } else if (lower.startsWith('no ') ||
        lower.contains('cut ') ||
        lower.contains('remove ')) {
      final cut = instruction
          .replaceFirst(RegExp(r'^(cut|remove)\s+', caseSensitive: false), '')
          .trim();
      final item = cut.toLowerCase().startsWith('no ') ? cut : 'No $cut';
      if (!next.outOfScope.contains(item)) {
        next.outOfScope = [...next.outOfScope, item];
      }
      next.lastCoDesignNote = 'Added hard scope cut: $item';
    } else {
      next.pillars = [...next.pillars, instruction];
      next.lastCoDesignNote = 'Added Co-Design direction: $instruction';
    }
    return UnrealSpecGuard.sanitizeConceptBlueprint(next);
  }

  static ProjectConceptBlueprint _buildSynthesizedFallback(String sparkPrompt) {
    final cleaned = sparkPrompt.trim();
    final titleWords = cleaned
        .replaceAll(RegExp(r'[^A-Za-z0-9\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 3)
        .take(2)
        .map((w) => w.toUpperCase())
        .toList();
    final title =
        titleWords.isEmpty ? 'PROTOTYPE ZERO' : titleWords.join(' ');
    final shortSpark = cleaned.isEmpty
        ? 'Focused Unreal Engine vertical prototype testing core player movement and primary interaction'
        : cleaned;

    return ProjectConceptBlueprint(
      sparkPrompt: cleaned,
      gameTitle: title,
      pitch: '$title — $shortSpark',
      coreLoop: const [
        'Move & Orient',
        'Trigger Primary Action',
        'React & Dodge',
        'Reset Run',
      ],
      pillars: const [
        'Instant Frame-1 Control: Player movement and actions respond immediately without sluggish inertia',
        'Clear Spatial Silhouettes: Distinct bright/dark debug primitives communicate danger before impact',
      ],
      tradeOffs: const [
        TradeOffRule(
          prefer: 'Tight single-level greybox arena',
          avoid: 'Multi-level streaming world',
        ),
        TradeOffRule(
          prefer: 'Readable debug geometry & UMG shapes',
          avoid: 'Premature final art pipelines',
        ),
      ],
      outOfScope: const [
        'No main menu, settings modal, or save slots',
        'No multiplayer replication or lobby flows',
        'No inventory UI or equipment loadouts',
      ],
      releaseDoneWhen:
          'Press PIE in L_ProtoArena -> complete full 30s core loop cleanly with 0 Output Log errors',
      initialEpics: [
        EpicSpec(
          id: 'ep_01',
          code: 'E01',
          lineageKey: 'e01',
          title: 'Player Movement & Camera Rig',
          releaseVersion: 'v0.1',
          lifecycle: EpicLifecycle.active,
          goal:
              'Control the player ACharacter at fixed ground speed with smooth directional facing and locked Unreal SpringArm framing.',
          links: const [
            'Reads DA_PlayerLocomotion PrimaryDataAsset',
            'Provides Actor location & facing vector to E02',
          ],
          outOfScope: const [
            'No climbing, swimming, or crouch stances',
          ],
          controls: [
            EpicControlBinding(
              action: 'IA_Move (Vector2D)',
              trigger: 'Held (WASD)',
              rule: 'Accelerates smoothly to 620 cm/s cleanly along arena ground plane',
            ),
            EpicControlBinding(
              action: 'IA_Dodge (Bool)',
              trigger: 'Started (Space)',
              rule: 'Impulses 500 cm forward over 0.16s with 1.0s cooldown',
            ),
          ],
          states: const [
            'Idle / Move -> DodgeImpulse (0.16s) -> Recover -> Idle / Move',
          ],
          interrupts: const [
            'DodgeImpulse grants temporary collision ignore on enemy pawns',
          ],
          tuning: [
            EpicTuningParam(key: 'MoveSpeed', value: '620', unit: 'cm/s'),
            EpicTuningParam(key: 'DodgeDistance', value: '500', unit: 'cm'),
            EpicTuningParam(key: 'DodgeCooldown', value: '1.0', unit: 's'),
          ],
          feedback: const [
            'Bright debug ribbon trail during DodgeImpulse',
            'Compact radial cooldown arc beneath player capsule',
          ],
          levelStaging:
              'L_ProtoArena: 2800x2800 cm greybox floor + perimeter blocking walls + PlayerStart',
          checks: [
            EpicPieCheck(
              id: 'ep_01_c1',
              text: 'Press WASD -> player capsule moves smoothly at 620 cm/s with zero wall snagging',
            ),
            EpicPieCheck(
              id: 'ep_01_c2',
              text: 'Press Space -> executes crisp 500 cm forward dash and obeys 1.0s cooldown',
            ),
          ],
        ),
        EpicSpec(
          id: 'ep_02',
          code: 'E02',
          lineageKey: 'e02',
          title: 'Primary Player Action & Feedback',
          releaseVersion: 'v0.1',
          lifecycle: EpicLifecycle.queued,
          goal:
              'Execute the primary combat or interaction action cleanly along aim direction with crisp hit reaction.',
          links: const [
            'Reads player transform from E01 and emits damage events to E03 actors',
          ],
          outOfScope: const [
            'No secondary skill tree or combo upgrades',
          ],
          controls: [
            EpicControlBinding(
              action: 'IA_Primary (Bool)',
              trigger: 'Started (LMB)',
              rule: 'Fires active projectile or melee trace out to 1600 cm',
            ),
          ],
          states: const [
            'Ready -> ActiveAction (0.18s) -> Cooldown (0.25s) -> Ready',
          ],
          interrupts: const [
            'E01 DodgeImpulse cleanly cancels cooldown wind-down',
          ],
          tuning: [
            EpicTuningParam(key: 'ActionDamage', value: '25', unit: 'hp'),
            EpicTuningParam(key: 'ActionRange', value: '1600', unit: 'cm'),
            EpicTuningParam(key: 'ActionCooldown', value: '0.25', unit: 's'),
          ],
          feedback: const [
            'Emissive impact flash on target surface plus brief camera impulse',
          ],
          levelStaging:
              'L_ProtoArena: add two static collision pillars at 800 cm and 1400 cm range',
          checks: [
            EpicPieCheck(
              id: 'ep_02_c1',
              text: 'Click LMB -> primary action triggers immediately with visible impact cue on hit',
            ),
          ],
        ),
        EpicSpec(
          id: 'ep_03',
          code: 'E03',
          lineageKey: 'e03',
          title: 'Target Actor & Arena Loop Closure',
          releaseVersion: 'v0.1',
          lifecycle: EpicLifecycle.queued,
          goal:
              'Place interactive enemy/target actors with readable threat telegraph, HP tracking, and quick arena reset.',
          links: const [
            'Consumes E02 damage events and drives simple UMG counter overlay',
          ],
          outOfScope: const [
            'No procedural dungeon rooms or loot chests',
          ],
          controls: [
            EpicControlBinding(
              action: 'IA_ResetProto (Bool)',
              trigger: 'Pressed (R)',
              rule: 'Respawns targets and resets player HP to 100 in < 0.2s',
            ),
          ],
          states: const [
            'Patrol -> Telegraph (0.50s) -> Execute -> Stagger / Defeated',
          ],
          interrupts: const [
            'Heavy hit triggers 0.40s brief knockback stagger without freezing player movement',
          ],
          tuning: [
            EpicTuningParam(key: 'TargetHP', value: '100', unit: 'hp'),
            EpicTuningParam(key: 'TelegraphDuration', value: '0.50', unit: 's'),
          ],
          feedback: const [
            'Floating overhead HP bar + crimson telegraph outline before enemy attack',
          ],
          levelStaging:
              'L_ProtoArena: 2 target actors stationed 1200 cm north of PlayerStart',
          checks: [
            EpicPieCheck(
              id: 'ep_03_c1',
              text: 'Defeat both targets -> HUD status updates cleanly and pressing R resets arena without leaks',
            ),
          ],
        ),
      ],
    );
  }
}

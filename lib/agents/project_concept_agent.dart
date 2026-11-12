import '../constants/text_style_guide.dart';
import '../constants/tiers.dart';
import '../models/agent_blueprints.dart';
import 'gemini_agent_client.dart';

/// A single AI-suggested mechanic or twist card on the New Project screen
/// that the user can toggle on/off to fold into (or remove from) their Concept Summary.
class SparkExpansionCard {
  final String badge;
  final String title;
  final String description;
  final String additionSummary;
  final String accentType;
  bool isSelected;

  SparkExpansionCard({
    required this.badge,
    required this.title,
    required this.description,
    required this.additionSummary,
    this.accentType = 'amber',
    this.isSelected = false,
  });
}

/// One thing the blueprint needs that the user's pitch doesn't state yet
/// (`TWIST`, `SETUP`, or `ACTION`) plus a short question about their idea.
class SparkMissingPiece {
  final String kind;
  final String question;

  const SparkMissingPiece({required this.kind, required this.question});

  /// Text dropped into the pitch input when the user taps this nudge.
  String get seed => switch (kind) {
        'TWIST' => 'Twist: ',
        'SETUP' => 'Camera and engine: ',
        _ => 'Core action: ',
      };
}

/// Holds the ingested AI summary of the user's raw game idea on the New Project screen,
/// plus the 3 toggleable Concept Expansion Cards tailored to that idea.
class SparkIdeaIntakeResult {
  String rawIdea;
  String workingTitle;
  String baseSummary;
  List<String> mechanics;
  List<SparkExpansionCard> expansionCards;

  /// `null` = unknown (Gemini didn't say); `[]` = checked and nothing is missing.
  List<SparkMissingPiece>? missing;

  SparkIdeaIntakeResult({
    required this.rawIdea,
    required this.workingTitle,
    required this.baseSummary,
    required this.mechanics,
    required this.expansionCards,
    this.missing,
  });

  /// Returns the effective summary including any selected Expansion Cards.
  String get effectiveSummary {
    final activeAdditions = expansionCards
        .where((c) => c.isSelected)
        .map((c) => c.additionSummary)
        .toList();
    if (activeAdditions.isEmpty) return baseSummary;
    return '$baseSummary Included additions: ${activeAdditions.join(' · ')}.';
  }

  /// Returns the canonical prompt sent to `startConceptInterview` when the user
  /// clicks `Start Concept Blueprint →`.
  String get canonicalPrompt {
    final activeAdditions = expansionCards
        .where((c) => c.isSelected)
        .map((c) => '${c.title} (${c.additionSummary})')
        .toList();
    if (activeAdditions.isEmpty) {
      return '$rawIdea — $baseSummary';
    }
    return '$rawIdea — $baseSummary With added mechanics: ${activeAdditions.join('; ')}';
  }
}

/// Stage 1 Agent: Turns a "Spark" idea into a Concept Blueprint and section-focused
/// guidance using Gemini AI (`gemini-flash-latest`).
/// Contains zero hardcoded archetypes, zero fallback game templates, and zero minimal scaffolds.
/// Returns `null` (or `false`) whenever the app is offline or Gemini AI is unreachable.
class ProjectConceptAgent {
  static const _kCardAccents = ['amber', 'emerald', 'neutral'];

  static bool _isPlaceholderString(String s) =>
      s.isEmpty ||
      s == '...' ||
      s.toLowerCase().startsWith('only if ');

  static List<String> _parseStringList(
    dynamic raw, {
    bool filterPlaceholders = true,
  }) {
    if (raw is! List) return const <String>[];
    return raw
        .map((e) => e.toString().trim())
        .where((s) => filterPlaceholders ? !_isPlaceholderString(s) : s.isNotEmpty)
        .toList();
  }

  static List<String> _normalizeTechSpecEngine(
    List<String> techSpec,
    List<String> gameSpec,
    String sparkText,
  ) {
    if (techSpec.isEmpty) return techSpec;
    final result = List<String>.from(techSpec);
    final e0 = result.first.toLowerCase();
    final hasBp = e0.contains('blueprint') || e0.contains('bp');
    final hasCpp = e0.contains('c++') || e0.contains('cpp');
    final hasHybrid = e0.contains('hybrid') || (hasBp && hasCpp);

    if (e0.contains('unreal') || e0.contains('ue5')) {
      if (hasHybrid) {
        result[0] = 'Unreal Engine 5 (Blueprints / C++)';
      } else if (hasBp) {
        result[0] = 'Unreal Engine 5 (Blueprints)';
      } else if (hasCpp) {
        result[0] = 'Unreal Engine 5 (C++)';
      } else {
        result[0] = 'Unreal Engine 5 (Blueprints / C++)';
      }
      return result;
    }

    // Standardize all new Stage 1 projects onto Unreal Engine 5 workflows.
    final corpus =
        '${techSpec.join(' ')} $sparkText'.toLowerCase();
    if ((corpus.contains('blueprint') && !corpus.contains('c++')) &&
        !corpus.contains('hybrid')) {
      result[0] = 'Unreal Engine 5 (Blueprints)';
    } else if ((corpus.contains('c++') || corpus.contains('cpp')) &&
        !corpus.contains('blueprint') &&
        !corpus.contains('hybrid')) {
      result[0] = 'Unreal Engine 5 (C++)';
    } else {
      result[0] = 'Unreal Engine 5 (Blueprints / C++)';
    }
    return result;
  }

  /// Parses the optional `missing` array; returns `null` when absent/malformed.
  static List<SparkMissingPiece>? _parseMissingPieces(dynamic raw) {
    if (raw is! List) return null;
    const kinds = {'TWIST', 'SETUP', 'ACTION'};
    final seen = <String>{};
    final result = <SparkMissingPiece>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final kind = (item['kind'] ?? '').toString().trim().toUpperCase();
      final question = (item['question'] ?? '').toString().trim();
      if (!kinds.contains(kind) || question.isEmpty || !seen.add(kind)) {
        continue;
      }
      result.add(SparkMissingPiece(kind: kind, question: question));
      if (result.length >= 2) break;
    }
    return result;
  }

  static List<SparkExpansionCard> _parseExpansionCards(dynamic rawCards) {
    if (rawCards is! List) return const <SparkExpansionCard>[];
    final cards = <SparkExpansionCard>[];
    for (int i = 0; i < rawCards.length && i < 3; i++) {
      final item = rawCards[i];
      if (item is Map) {
        cards.add(
          SparkExpansionCard(
            badge: (item['badge'] ??
                    item['category'] ??
                    '0${i + 1} · IDEA ADDITION')
                .toString()
                .trim(),
            title: (item['title'] ?? 'Gameplay Twist ${i + 1}')
                .toString()
                .trim(),
            description:
                (item['description'] ?? item['pitch'] ?? '').toString().trim(),
            additionSummary: (item['additionSummary'] ?? item['title'] ?? '')
                .toString()
                .trim(),
            accentType: _kCardAccents[i % _kCardAccents.length],
          ),
        );
      }
    }
    return cards;
  }

  /// Native Gemini Tool Declaration for `startConceptInterview` (`commit_concept_blueprint`).
  /// Enforces the 4-cell `gameSpec`, concrete `engine` enum in `techSpec`, `pillarName: playerFeeling`
  /// pairs, and `priorityX over overAlternativeY` rules at the schema level.
  static const Map<String, dynamic> commitConceptBlueprintTool = {
    'name': 'commit_concept_blueprint',
    'description':
        'Commits the structured 8-section Stage 1 Concept Blueprint for the game prototype.',
    'parameters': {
      'type': 'OBJECT',
      'properties': {
        'title': {
          'type': 'STRING',
          'description': LayersTextStyleGuide.stage1TitleSchemaDesc,
        },
        'goal': {
          'type': 'STRING',
          'description': LayersTextStyleGuide.stage1GoalSchemaDesc,
        },
        'gameSpec': {
          'type': 'OBJECT',
          'properties': {
            'cameraView': {
              'type': 'STRING',
              'description': LayersTextStyleGuide.specCellSchemaDesc,
            },
            'controls': {
              'type': 'STRING',
              'description': LayersTextStyleGuide.specCellSchemaDesc,
            },
            'playerMode': {
              'type': 'STRING',
              'description': LayersTextStyleGuide.specCellSchemaDesc,
            },
            'arenaStructure': {
              'type': 'STRING',
              'description': LayersTextStyleGuide.specCellSchemaDesc,
            },
          },
          'required': [
            'cameraView',
            'controls',
            'playerMode',
            'arenaStructure',
          ],
        },
        'techSpec': {
          'type': 'OBJECT',
          'properties': {
            'engine': {
              'type': 'STRING',
              'enum': [
                'Unreal Engine 5 (Blueprints)',
                'Unreal Engine 5 (C++)',
                'Unreal Engine 5 (Blueprints / C++)',
              ],
            },
            'platform': {
              'type': 'STRING',
              'description': LayersTextStyleGuide.specCellSchemaDesc,
            },
            'assetPipeline': {
              'type': 'STRING',
              'description': LayersTextStyleGuide.specCellSchemaDesc,
            },
            'saveMode': {
              'type': 'STRING',
              'description': LayersTextStyleGuide.specCellSchemaDesc,
            },
          },
          'required': ['engine', 'platform', 'assetPipeline', 'saveMode'],
        },
        'designPillars': {
          'type': 'ARRAY',
          'description':
              '3-4 core player feelings/experiences (never features or genres).',
          'items': {
            'type': 'OBJECT',
            'required': ['pillarName', 'playerExperience'],
            'properties': {
              'pillarName': {
                'type': 'STRING',
                'description': LayersTextStyleGuide.pillarNameSchemaDesc,
              },
              'playerExperience': {
                'type': 'STRING',
                'description': LayersTextStyleGuide.pillarExperienceSchemaDesc,
              },
            },
          },
        },
        'tradeOffs': {
          'type': 'ARRAY',
          'description':
              '2-3 compact X over Y engineering/design boundaries (2-4 words per side, no "Prioritize" or version suffixes).',
          'items': {
            'type': 'OBJECT',
            'required': ['priorityX', 'overAlternativeY'],
            'properties': {
              'priorityX': {
                'type': 'STRING',
                'description': LayersTextStyleGuide.tradeOffPrioritySchemaDesc,
              },
              'overAlternativeY': {
                'type': 'STRING',
                'description':
                    LayersTextStyleGuide.tradeOffAlternativeSchemaDesc,
              },
            },
          },
        },
        'coreLoopBeats': {
          'type': 'ARRAY',
          'items': {
            'type': 'STRING',
            'description': LayersTextStyleGuide.coreLoopBeatSchemaDesc,
          },
        },
        'exclusions': {
          'type': 'ARRAY',
          'items': {
            'type': 'STRING',
            'description': LayersTextStyleGuide.exclusionItemSchemaDesc,
          },
        },
        'doneWhen': {
          'type': 'STRING',
          'description': LayersTextStyleGuide.causalTriggerResultSchemaDesc,
        },
        'releaseTrainTitles': {
          'type': 'ARRAY',
          'items': {'type': 'STRING'},
        },
        'sectionOptions': {
          'type': 'OBJECT',
          'description':
              'Upfront Option Cards keyed by section (goal, gameSpec, techSpec, designPillars, tradeOffs, coreLoop, exclusions, doneWhen).',
          'properties': {
            'goal': {
              'type': 'ARRAY',
              'items': {'type': 'STRING'},
            },
            'gameSpec': {
              'type': 'ARRAY',
              'items': {'type': 'STRING'},
            },
            'techSpec': {
              'type': 'ARRAY',
              'items': {'type': 'STRING'},
            },
            'designPillars': {
              'type': 'ARRAY',
              'items': {'type': 'STRING'},
            },
            'tradeOffs': {
              'type': 'ARRAY',
              'items': {'type': 'STRING'},
            },
            'coreLoop': {
              'type': 'ARRAY',
              'items': {'type': 'STRING'},
            },
            'exclusions': {
              'type': 'ARRAY',
              'items': {'type': 'STRING'},
            },
            'doneWhen': {
              'type': 'ARRAY',
              'items': {'type': 'STRING'},
            },
          },
        },
      },
      'required': [
        'title',
        'goal',
        'gameSpec',
        'techSpec',
        'designPillars',
        'tradeOffs',
        'coreLoopBeats',
        'exclusions',
        'doneWhen',
      ],
    },
  };

  /// Native Gemini Tool Declaration for Stage 1A `ingestOrRefineSparkIdea` (`commit_spark_intake`).
  static const Map<String, dynamic> commitSparkIntakeTool = {
    'name': 'commit_spark_intake',
    'description':
        'Summarizes a developer raw game idea into a workingTitle, 2-sentence baseSummary, mechanics tags, and 3 optional expansion twist cards.',
    'parameters': {
      'type': 'OBJECT',
      'required': ['workingTitle', 'baseSummary', 'mechanics'],
      'properties': {
        'workingTitle': {
          'type': 'STRING',
          'description': 'Concrete 2-3 word game title.',
        },
        'baseSummary': {
          'type': 'STRING',
          'description':
              '2 natural sentences summarizing the premise, core mechanics, and repeatable loop.',
        },
        'mechanics': {
          'type': 'ARRAY',
          'items': {'type': 'STRING'},
        },
        'missing': {
          'type': 'ARRAY',
          'description':
              'At most 2 things the developer\'s own text does not state yet. Empty array when the action, twist, and setup are all present.',
          'items': {
            'type': 'OBJECT',
            'required': ['kind', 'question'],
            'properties': {
              'kind': {
                'type': 'STRING',
                'description':
                    'TWIST (the risk or cost), SETUP (camera and engine), or ACTION (what the player does every few seconds).',
              },
              'question': {
                'type': 'STRING',
                'description':
                    'One short plain question about this specific idea, 12 words or fewer.',
              },
            },
          },
        },
        'expansionCards': {
          'type': 'ARRAY',
          'items': {
            'type': 'OBJECT',
            'required': ['badge', 'title', 'description', 'additionSummary'],
            'properties': {
              'badge': {
                'type': 'STRING',
                'description':
                    'e.g. "01 · RISK vs REWARD", "02 · WORLD HAZARD", or "03 · META UPGRADE"',
              },
              'title': {'type': 'STRING'},
              'description': {'type': 'STRING'},
              'additionSummary': {'type': 'STRING'},
            },
          },
        },
      },
    },
  };

  /// Native Gemini Tool Declaration for Stage 1A `refreshSparkExpansionCards` (`propose_spark_expansion_cards`).
  static const Map<String, dynamic> proposeSparkExpansionCardsTool = {
    'name': 'propose_spark_expansion_cards',
    'description':
        'Proposes 3 fresh gameplay expansion / twist cards for the active game concept.',
    'parameters': {
      'type': 'OBJECT',
      'required': ['expansionCards'],
      'properties': {
        'expansionCards': {
          'type': 'ARRAY',
          'items': {
            'type': 'OBJECT',
            'required': ['badge', 'title', 'description', 'additionSummary'],
            'properties': {
              'badge': {
                'type': 'STRING',
                'description':
                    'e.g. "01 · RISK vs REWARD", "02 · WORLD HAZARD", or "03 · META UPGRADE"',
              },
              'title': {'type': 'STRING'},
              'description': {'type': 'STRING'},
              'additionSummary': {'type': 'STRING'},
            },
          },
        },
      },
    },
  };

  /// Native Gemini Tool Declaration for `sendConceptChatTurn` (`update_concept_section`).
  static const Map<String, dynamic> updateConceptSectionTool = {
    'name': 'update_concept_section',
    'description':
        'Updates only the modified section(s) of the Live Concept Blueprint in response to the developer.',
    'parameters': {
      'type': 'OBJECT',
      'properties': {
        'reply': {
          'type': 'STRING',
          'description': '1-sentence confirmation of what changed.',
        },
        'updatedFields': {
          'type': 'ARRAY',
          'items': {'type': 'STRING'},
        },
        'title': {
          'type': 'STRING',
          'description': LayersTextStyleGuide.stage1TitleSchemaDesc,
        },
        'goal': {
          'type': 'STRING',
          'description': LayersTextStyleGuide.stage1GoalSchemaDesc,
        },
        'goalOptions': {
          'type': 'ARRAY',
          'items': {'type': 'STRING'},
        },
        'gameSpec': {
          'type': 'OBJECT',
          'required': [
            'cameraView',
            'controls',
            'playerMode',
            'arenaStructure',
          ],
          'properties': {
            'cameraView': {
              'type': 'STRING',
              'description': LayersTextStyleGuide.specCellSchemaDesc,
            },
            'controls': {
              'type': 'STRING',
              'description': LayersTextStyleGuide.specCellSchemaDesc,
            },
            'playerMode': {
              'type': 'STRING',
              'description': LayersTextStyleGuide.specCellSchemaDesc,
            },
            'arenaStructure': {
              'type': 'STRING',
              'description': LayersTextStyleGuide.specCellSchemaDesc,
            },
          },
        },
        'techSpec': {
          'type': 'OBJECT',
          'required': ['engine', 'platform', 'assetPipeline', 'saveMode'],
          'properties': {
            'engine': {
              'type': 'STRING',
              'enum': [
                'Unreal Engine 5 (Blueprints)',
                'Unreal Engine 5 (C++)',
                'Unreal Engine 5 (Blueprints / C++)',
              ],
            },
            'platform': {
              'type': 'STRING',
              'description': LayersTextStyleGuide.specCellSchemaDesc,
            },
            'assetPipeline': {
              'type': 'STRING',
              'description': LayersTextStyleGuide.specCellSchemaDesc,
            },
            'saveMode': {
              'type': 'STRING',
              'description': LayersTextStyleGuide.specCellSchemaDesc,
            },
          },
        },
        'designPillars': {
          'type': 'ARRAY',
          'items': {
            'type': 'OBJECT',
            'required': ['pillarName', 'playerExperience'],
            'properties': {
              'pillarName': {
                'type': 'STRING',
                'description': LayersTextStyleGuide.pillarNameSchemaDesc,
              },
              'playerExperience': {
                'type': 'STRING',
                'description': LayersTextStyleGuide.pillarExperienceSchemaDesc,
              },
            },
          },
        },
        'tradeOffs': {
          'type': 'ARRAY',
          'items': {
            'type': 'OBJECT',
            'required': ['priorityX', 'overAlternativeY'],
            'properties': {
              'priorityX': {
                'type': 'STRING',
                'description': LayersTextStyleGuide.tradeOffPrioritySchemaDesc,
              },
              'overAlternativeY': {
                'type': 'STRING',
                'description':
                    LayersTextStyleGuide.tradeOffAlternativeSchemaDesc,
              },
            },
          },
        },
        'coreLoopBeats': {
          'type': 'ARRAY',
          'items': {
            'type': 'STRING',
            'description': LayersTextStyleGuide.coreLoopBeatSchemaDesc,
          },
        },
        'exclusions': {
          'type': 'ARRAY',
          'items': {
            'type': 'STRING',
            'description': LayersTextStyleGuide.exclusionItemSchemaDesc,
          },
        },
        'doneWhen': {
          'type': 'STRING',
          'description': LayersTextStyleGuide.causalTriggerResultSchemaDesc,
        },
        'releaseTrainTitles': {
          'type': 'ARRAY',
          'items': {'type': 'STRING'},
        },
      },
      'required': ['reply', 'updatedFields'],
    },
  };

  /// Returns a strictly single-section Gemini tool schema when the user is editing a specific
  /// Stage 1 section (`01 Goal` through `08 Done When`), preventing cross-section overwrites.
  /// Falls back to the multi-section `updateConceptSectionTool` on `09 Full Concept Review` or general chat.
  static Map<String, dynamic> buildFocusedConceptSectionTool(
    String? sectionHeaderOrName,
  ) {
    final raw = (sectionHeaderOrName ?? '').trim().toLowerCase();
    if (raw.isEmpty || raw.contains('09') || raw.contains('review')) {
      return updateConceptSectionTool;
    }
    if (raw.contains('02') || raw.contains('game spec') || raw == 'gamespec') {
      return const {
        'name': 'update_game_spec_section',
        'description':
            'Updates ONLY the 02 · Game Spec section (4 required cells: cameraView, controls, playerMode, arenaStructure).',
        'parameters': {
          'type': 'OBJECT',
          'required': ['reply', 'gameSpec'],
          'properties': {
            'reply': {'type': 'STRING'},
            'gameSpec': {
              'type': 'OBJECT',
              'required': [
                'cameraView',
                'controls',
                'playerMode',
                'arenaStructure',
              ],
              'properties': {
                'cameraView': {'type': 'STRING'},
                'controls': {'type': 'STRING'},
                'playerMode': {'type': 'STRING'},
                'arenaStructure': {'type': 'STRING'},
              },
            },
          },
        },
      };
    }
    if (raw.contains('03') || raw.contains('tech spec') || raw == 'techspec') {
      return const {
        'name': 'update_tech_spec_section',
        'description':
            'Updates ONLY the 03 · Tech Spec section (4 required cells: concrete engine enum, platform, assetPipeline, saveMode).',
        'parameters': {
          'type': 'OBJECT',
          'required': ['reply', 'techSpec'],
          'properties': {
            'reply': {'type': 'STRING'},
            'techSpec': {
              'type': 'OBJECT',
              'required': ['engine', 'platform', 'assetPipeline', 'saveMode'],
              'properties': {
                'engine': {
                  'type': 'STRING',
                  'enum': [
                    'Unreal Engine 5 (Blueprints)',
                    'Unreal Engine 5 (C++)',
                    'Unreal Engine 5 (Blueprints / C++)',
                  ],
                },
                'platform': {'type': 'STRING'},
                'assetPipeline': {'type': 'STRING'},
                'saveMode': {'type': 'STRING'},
              },
            },
          },
        },
      };
    }
    if (raw.contains('04') ||
        raw.contains('design pillar') ||
        raw == 'designpillars') {
      return const {
        'name': 'update_design_pillars_section',
        'description':
            'Updates ONLY the 04 · Design Pillars section with named player-experience statements.',
        'parameters': {
          'type': 'OBJECT',
          'required': ['reply', 'designPillars'],
          'properties': {
            'reply': {'type': 'STRING'},
            'designPillars': {
              'type': 'ARRAY',
              'items': {
                'type': 'OBJECT',
                'required': ['pillarName', 'playerExperience'],
                'properties': {
                  'pillarName': {
                    'type': 'STRING',
                    'description': '2-3 word pillar title',
                  },
                  'playerExperience': {
                    'type': 'STRING',
                    'description':
                        '1-sentence player feeling or tension (never a feature or genre)',
                  },
                },
              },
            },
          },
        },
      };
    }
    if (raw.contains('05') ||
        raw.contains('trade-off') ||
        raw.contains('tradeoff')) {
      return const {
        'name': 'update_trade_offs_section',
        'description':
            'Updates ONLY the 05 · Trade-Offs section with explicit X over Y engineering/design boundary rules.',
        'parameters': {
          'type': 'OBJECT',
          'required': ['reply', 'tradeOffs'],
          'properties': {
            'reply': {'type': 'STRING'},
            'tradeOffs': {
              'type': 'ARRAY',
              'items': {
                'type': 'OBJECT',
                'required': ['priorityX', 'overAlternativeY'],
                'properties': {
                  'priorityX': {
                    'type': 'STRING',
                    'description':
                        '2-4 words naming what we prioritize (e.g. "Immediate arcade dash")',
                  },
                  'overAlternativeY': {
                    'type': 'STRING',
                    'description':
                        '2-4 words naming what we sacrifice (e.g. "Realistic momentum inertia")',
                  },
                },
              },
            },
          },
        },
      };
    }
    if (raw.contains('06') || raw.contains('core loop') || raw == 'coreloop') {
      return const {
        'name': 'update_core_loop_section',
        'description':
            'Updates ONLY the 06 · Core Loop section with chronological playable beats.',
        'parameters': {
          'type': 'OBJECT',
          'required': ['reply', 'coreLoopBeats'],
          'properties': {
            'reply': {'type': 'STRING'},
            'coreLoopBeats': {
              'type': 'ARRAY',
              'items': {
                'type': 'STRING',
                'description':
                    'Beat Name: Observable player action and system response',
              },
            },
          },
        },
      };
    }
    if (raw.contains('07') ||
        raw.contains('out of scope') ||
        raw.contains('exclusion')) {
      return const {
        'name': 'update_exclusions_section',
        'description':
            'Updates ONLY the 07 · Out of Scope section with explicit prototype exclusions.',
        'parameters': {
          'type': 'OBJECT',
          'required': ['reply', 'exclusions'],
          'properties': {
            'reply': {'type': 'STRING'},
            'exclusions': {
              'type': 'ARRAY',
              'items': {'type': 'STRING'},
            },
          },
        },
      };
    }
    if (raw.contains('08') || raw.contains('done when') || raw == 'donewhen') {
      return const {
        'name': 'update_done_when_section',
        'description':
            'Updates ONLY the 08 · Done When section with a concrete playtest completion condition.',
        'parameters': {
          'type': 'OBJECT',
          'required': ['reply', 'doneWhen'],
          'properties': {
            'reply': {'type': 'STRING'},
            'doneWhen': {'type': 'STRING'},
          },
        },
      };
    }
    if (raw.contains('01') || raw.contains('goal')) {
      return const {
        'name': 'update_goal_section',
        'description':
            'Updates ONLY the 01 · Goal (and optional working title / goalOptions) section.',
        'parameters': {
          'type': 'OBJECT',
          'required': ['reply', 'goal'],
          'properties': {
            'reply': {'type': 'STRING'},
            'title': {'type': 'STRING'},
            'goal': {'type': 'STRING'},
            'goalOptions': {
              'type': 'ARRAY',
              'items': {'type': 'STRING'},
            },
          },
        },
      };
    }
    return updateConceptSectionTool;
  }

  /// Normalizes Design Pillars from either structured `{pillarName, playerExperience}` tool objects
  /// or plain strings (`"Pillar Name: Experience"`).
  static List<String> parsePillarsList(dynamic raw) {
    if (raw is List) {
      final result = <String>[];
      for (int i = 0; i < raw.length; i++) {
        final item = raw[i];
        if (item is Map) {
          final name = (item['pillarName'] ?? item['name'] ?? item['title'] ?? '')
              .toString()
              .trim();
          final exp = (item['playerExperience'] ??
                  item['experience'] ??
                  item['description'] ??
                  '')
              .toString()
              .trim();
          if (name.isNotEmpty && exp.isNotEmpty) {
            result.add('$name: $exp');
          } else if (exp.isNotEmpty) {
            result.add(ProjectConceptBlueprint.ensureNamedPillar(exp, i));
          }
        } else {
          final s = item?.toString().trim() ?? '';
          if (s.isNotEmpty && !_isPlaceholderString(s)) {
            result.add(ProjectConceptBlueprint.ensureNamedPillar(s, i));
          }
        }
      }
      return result;
    }
    return _parseStringList(raw);
  }

  /// Normalizes Trade-Offs from either structured `{priorityX, overAlternativeY}` tool objects
  /// or plain `"X over Y"` strings.
  static List<String> parseTradeOffsList(dynamic raw) {
    if (raw is List) {
      final result = <String>[];
      for (final item in raw) {
        if (item is Map) {
          final x = (item['priorityX'] ?? item['prioritized'] ?? item['x'] ?? '')
              .toString()
              .trim();
          final y = (item['overAlternativeY'] ?? item['over'] ?? item['y'] ?? '')
              .toString()
              .trim();
          final label = (item['label'] ?? '').toString().trim();
          if (x.isNotEmpty && y.isNotEmpty) {
            final rule = '$x over $y';
            result.add(label.isNotEmpty ? '$label: $rule' : rule);
          }
        } else {
          final s = item?.toString().trim() ?? '';
          if (s.isNotEmpty && !_isPlaceholderString(s)) {
            result.add(s);
          }
        }
      }
      return result;
    }
    return _parseStringList(raw);
  }

  /// Builds a section-matched Gemini Tool Schema for `regenerateSectionOptionsWithAi`.
  static Map<String, dynamic> buildSectionOptionsTool(String optionKey) {
    switch (optionKey) {
      case 'gameSpec':
        return const {
          'name': 'propose_game_spec_options',
          'description':
              'Proposes 3 fresh 4-cell Game Spec Option Cards (label + cameraView, controls, playerMode, arenaStructure).',
          'parameters': {
            'type': 'OBJECT',
            'required': ['options'],
            'properties': {
              'options': {
                'type': 'ARRAY',
                'items': {
                  'type': 'OBJECT',
                  'required': [
                    'label',
                    'cameraView',
                    'controls',
                    'playerMode',
                    'arenaStructure',
                  ],
                  'properties': {
                    'label': {'type': 'STRING'},
                    'cameraView': {'type': 'STRING'},
                    'controls': {'type': 'STRING'},
                    'playerMode': {'type': 'STRING'},
                    'arenaStructure': {'type': 'STRING'},
                  },
                },
              },
            },
          },
        };
      case 'techSpec':
        return const {
          'name': 'propose_tech_spec_options',
          'description':
              'Proposes 3 fresh 4-cell Tech Spec Option Cards (label + concrete engine enum, platform, assetPipeline, saveMode).',
          'parameters': {
            'type': 'OBJECT',
            'required': ['options'],
            'properties': {
              'options': {
                'type': 'ARRAY',
                'items': {
                  'type': 'OBJECT',
                  'required': [
                    'label',
                    'engine',
                    'platform',
                    'assetPipeline',
                    'saveMode',
                  ],
                  'properties': {
                    'label': {'type': 'STRING'},
                    'engine': {
                      'type': 'STRING',
                      'enum': [
                        'Unreal Engine 5 (Blueprints)',
                        'Unreal Engine 5 (C++)',
                        'Unreal Engine 5 (Blueprints / C++)',
                      ],
                    },
                    'platform': {'type': 'STRING'},
                    'assetPipeline': {'type': 'STRING'},
                    'saveMode': {'type': 'STRING'},
                  },
                },
              },
            },
          },
        };
      case 'designPillars':
        return const {
          'name': 'propose_design_pillar_options',
          'description':
              'Proposes 3 fresh Design Pillar Option Cards (pillarName + playerExperience).',
          'parameters': {
            'type': 'OBJECT',
            'required': ['options'],
            'properties': {
              'options': {
                'type': 'ARRAY',
                'items': {
                  'type': 'OBJECT',
                  'required': ['pillarName', 'playerExperience'],
                  'properties': {
                    'pillarName': {
                      'type': 'STRING',
                      'description': '2-3 Word Pillar Name',
                    },
                    'playerExperience': {
                      'type': 'STRING',
                      'description':
                          'Concise 1-sentence player feeling (never a feature or genre).',
                    },
                  },
                },
              },
            },
          },
        };
      case 'tradeOffs':
        return const {
          'name': 'propose_trade_off_options',
          'description':
              'Proposes 3 fresh X-over-Y Trade-Off Option Cards (label + priorityX over overAlternativeY).',
          'parameters': {
            'type': 'OBJECT',
            'required': ['options'],
            'properties': {
              'options': {
                'type': 'ARRAY',
                'items': {
                  'type': 'OBJECT',
                  'required': ['label', 'priorityX', 'overAlternativeY'],
                  'properties': {
                    'label': {'type': 'STRING'},
                    'priorityX': {'type': 'STRING'},
                    'overAlternativeY': {'type': 'STRING'},
                  },
                },
              },
            },
          },
        };
      case 'coreLoop':
        return const {
          'name': 'propose_core_loop_options',
          'description':
              'Proposes 3 fresh Core Loop Sequence Option Cards (label + sequential playable beats).',
          'parameters': {
            'type': 'OBJECT',
            'required': ['options'],
            'properties': {
              'options': {
                'type': 'ARRAY',
                'items': {
                  'type': 'OBJECT',
                  'required': ['label', 'beats'],
                  'properties': {
                    'label': {'type': 'STRING'},
                    'beats': {
                      'type': 'ARRAY',
                      'items': {'type': 'STRING'},
                    },
                  },
                },
              },
            },
          },
        };
      default:
        return {
          'name': 'propose_${optionKey}_options',
          'description':
              'Proposes 3 fresh Option Cards for the $optionKey section.',
          'parameters': const {
            'type': 'OBJECT',
            'required': ['options'],
            'properties': {
              'options': {
                'type': 'ARRAY',
                'items': {'type': 'STRING'},
              },
            },
          },
        };
    }
  }

  /// Normalizes option cards returned by `buildSectionOptionsTool` (supporting both typed cell maps and strings).
  static List<String> parseSectionOptionsToolOutput(
    String optionKey,
    dynamic rawOptions,
  ) {
    if (rawOptions is! List) return const <String>[];
    final result = <String>[];
    for (final item in rawOptions) {
      if (item is Map) {
        final label = (item['label'] ?? 'Option').toString().trim();
        if (optionKey == 'gameSpec') {
          final cells = _parseSpecCells(
            item,
            const ['cameraView', 'controls', 'playerMode', 'arenaStructure'],
          );
          if (cells.length >= 2) {
            result.add('$label: ${cells.join(' · ')}');
          }
        } else if (optionKey == 'techSpec') {
          final cells = _parseSpecCells(
            item,
            const ['engine', 'platform', 'assetPipeline', 'saveMode'],
          );
          if (cells.length >= 2) {
            result.add('$label: ${cells.join(' · ')}');
          }
        } else if (optionKey == 'designPillars') {
          final pName =
              (item['pillarName'] ?? item['label'] ?? '').toString().trim();
          final pExp =
              (item['playerExperience'] ?? item['text'] ?? '').toString().trim();
          if (pName.isNotEmpty && pExp.isNotEmpty) {
            result.add('$pName: $pExp');
          } else if (pExp.isNotEmpty) {
            result.add(pExp);
          }
        } else if (optionKey == 'tradeOffs') {
          final x = (item['priorityX'] ?? '').toString().trim();
          final y = (item['overAlternativeY'] ?? '').toString().trim();
          if (x.isNotEmpty && y.isNotEmpty) {
            result.add('$label: $x over $y');
          }
        } else if (optionKey == 'coreLoop') {
          final beats = _parseStringList(item['beats']);
          if (beats.isNotEmpty) {
            result.add('$label: ${beats.join(' → ')}');
          }
        } else {
          final text = (item['text'] ?? item['option'] ?? '').toString().trim();
          if (text.isNotEmpty) result.add(text);
        }
      } else {
        final s = item?.toString().trim() ?? '';
        if (s.isNotEmpty && !_isPlaceholderString(s)) {
          result.add(s);
        }
      }
    }
    return result;
  }

  static List<String> _parseSpecCells(
    dynamic raw,
    List<String> keysOrder,
  ) {
    if (raw is Map) {
      final cells = <String>[];
      for (final k in keysOrder) {
        final v = (raw[k] ?? '').toString().trim();
        if (v.isNotEmpty) cells.add(v);
      }
      if (cells.isNotEmpty) return cells;
    }
    return _parseStringList(raw);
  }

  /// Step 1B: Generates the initial 9-section Concept Blueprint from a spark idea via Gemini AI.
  /// Returns `null` if offline or if Gemini AI cannot be reached.
  static Future<ProjectConceptBlueprint?> startConceptInterview(
    String rawSpark, {
    String apiKey = '',
    String modelName = 'gemini-flash-latest',
    String thinkingLevel = 'LOW',
    bool isGddExtraction = false,
  }) async {
    final cleanSpark = ProjectConceptBlueprint.normalizeCommonTypos(
      rawSpark.trim(),
    );
    if (cleanSpark.isEmpty || !GeminiAgentClient.hasKey(apiKey)) {
      return null;
    }

    final promptLead = isGddExtraction
        ? '''You are an indie game producer extracting a structured 8-section Stage 1 Concept Blueprint from this pasted Game Design Document (GDD) / Notes:
"""
$cleanSpark
"""
- FAITHFUL GDD EXTRACTION: Extract and preserve the exact title, mechanics, camera/controls, engine/platform, design pillars, trade-offs, core loop beats, exclusions, and completion criteria described in the pasted document rather than inventing unrelated systems.'''
        : '''You are an indie game producer creating a Stage 1 Concept Blueprint for this spark idea:
"$cleanSpark"''';

    final prompt = '''
$promptLead

${GeminiAgentClient.compactStyleRules}
- Draft the 4 cells of `gameSpec` (`cameraView`, `controls`, `playerMode`, `arenaStructure`) and `techSpec` (`engine`, `platform`, `assetPipeline`, `saveMode`) strictly as 2–4 Title-Case words each. In `techSpec`, ALWAYS lock `engine` to Unreal Engine 5 (`"Unreal Engine 5 (Blueprints)"`, `"Unreal Engine 5 (C++)"`, or `"Unreal Engine 5 (Blueprints / C++)"`).
- Draft `designPillars` naming the core player feelings and emotional experiences the game must create (never features or genres), and `tradeOffs` as practical `priorityX` over `overAlternativeY` engineering and design boundaries.
- Decompose `coreLoopBeats` into sequential playable Beats (`Beat Name: Observable player action and system response`) in chronological player-loop order:
  1. Beat 1 MUST be the immediate in-game player control & primary action (e.g. Walking & Tank Inspection, Grapple/Dash Traversal, Vehicle Handling, or Grid Placement—never a pre-match menu).
  2. Middle Beats cover the core simulation/action and reactive challenge in the exact chronological sequence the player experiences them.
  3. Final Beats cover Harvesting/Reward collection, Selling/Upgrading equipment, and starting the next cycle/run so the loop never dead-ends.

Call `commit_concept_blueprint` with the structured blueprint.
''';

    final json = await GeminiAgentClient.generateJson(
      prompt: prompt,
      apiKey: apiKey,
      preferredModel: modelName,
      thinkingLevel: thinkingLevel,
      temperature: 0.55,
      functionDeclarations: const [commitConceptBlueprintTool],
    );

    if (json == null) return null;

    final aiTitle = json['title']?.toString().trim() ?? '';
    final resolvedTitle = aiTitle.isNotEmpty ? aiTitle : cleanSpark;
    final parsedSectionOptions = _parseSectionOptions(json['sectionOptions']);
    final releaseTitles = _parseStringList(json['releaseTrainTitles']);
    final parsedGameSpec = _parseSpecCells(
      json['gameSpec'],
      const ['cameraView', 'controls', 'playerMode', 'arenaStructure'],
    );
    final parsedTechSpec = _normalizeTechSpecEngine(
      _parseSpecCells(
        json['techSpec'],
        const ['engine', 'platform', 'assetPipeline', 'saveMode'],
      ),
      parsedGameSpec,
      cleanSpark,
    );

    return ProjectConceptBlueprint(
      title: resolvedTitle,
      sparkIdea: cleanSpark,
      questions: const <AgentQuestion>[],
      goal: ProjectConceptBlueprint.sanitizeGoalText(
        json['goal']?.toString().trim() ?? '',
      ),
      gameSpec: parsedGameSpec,
      techSpec: parsedTechSpec,
      designPillars: parsePillarsList(json['designPillars']),
      tradeOffs: parseTradeOffsList(json['tradeOffs']),
      coreLoopBeats: sortBeatsByDeveloperImpact(
        _parseStringList(json['coreLoopBeats']),
      ),
      exclusions: _parseStringList(json['exclusions']),
      doneWhen: json['doneWhen']?.toString().trim() ?? '',
      firstReleasePreset: ReleaseScope.featurePrototype,
      releaseTrainTitles: releaseTitles.isNotEmpty
          ? releaseTitles.take(1).toList()
          : <String>['v0.1: $resolvedTitle - Prototype'],
      isInterviewComplete: true,
      lastUpdatedFields: const [
        'Title',
        'Game Spec',
        'Tech Spec',
        'Design Pillars',
        'Trade-Offs',
        'Goal',
        'Core Loop',
        'Exclusions',
        'Prototype Release',
      ],
      sectionOptions: parsedSectionOptions,
      lastAgentReply: 'Drafted the initial $resolvedTitle Concept Blueprint.',
    );
  }

  /// Stateless Blueprint Turn: Takes the user's instruction, updates the live
  /// `ProjectConceptBlueprint` in place using `conversationModel` (`gemini-flash-latest`),
  /// and sets `lastAgentReply`. Returns `false` if offline or if Gemini AI is unreachable.
  static Future<bool> sendConceptChatTurn(
    ProjectConceptBlueprint draft,
    String userMessage, {
    String apiKey = '',
    String conversationModel = 'gemini-flash-latest',
    String planningModel = 'gemini-flash-latest',
    String thinkingLevel = 'LOW',
  }) async {
    final cleanMsg = ProjectConceptBlueprint.normalizeCommonTypos(
      userMessage.trim(),
    );
    if (cleanMsg.isEmpty || !GeminiAgentClient.hasKey(apiKey)) return false;

    final isSectionScoped = cleanMsg.startsWith('[Section ');
    final sectionScopeRule = isSectionScoped
        ? '\n- SECTION-SCOPED REQUEST: Focus your update on the target `[Section ...]` named in Developer Direction while keeping locked upstream sections consistent. When updating `gameSpec`, always return all 4 cells `["Camera View", "Controls", "Player Mode", "Arena Structure"]`; when updating `techSpec`, always return all 4 cells `["Engine", "Platform", "Asset Pipeline", "Network / Save"]`.'
        : '';

    final closeBracketIdx =
        isSectionScoped ? cleanMsg.indexOf(']') : -1;
    final focusedSectionTag = (isSectionScoped && closeBracketIdx > 0)
        ? cleanMsg.substring(0, closeBracketIdx + 1)
        : null;
    final activeConceptTool =
        buildFocusedConceptSectionTool(focusedSectionTag);
    final activeToolName = activeConceptTool['name']?.toString() ??
        'update_concept_section';

    final prompt = '''
You are Antigravity, an indie game producer updating a Live Concept Blueprint.
Spark: "${draft.sparkIdea}"
Current Blueprint:
- Title: "${draft.title}"
- Goal: "${draft.goal}"
- Game Spec: ${draft.gameSpec.join(' · ')}
- Tech Spec: ${draft.techSpec.join(' · ')}
- Design Pillars: ${draft.designPillars.join(' | ')}
- Trade-Offs: ${draft.tradeOffs.join(' | ')}
- Core Loop Beats: ${draft.coreLoopBeats.join(' | ')}
- Out of Scope: ${draft.exclusions.join(' | ')}
- Done When: "${draft.doneWhen}"
- Release Train: ${draft.releaseTrainTitles.join(' | ')}
Developer Direction: "$cleanMsg"

${GeminiAgentClient.compactStyleRules}
- Synthesize and rewrite the affected field(s) into natural, polished game-dev English. NEVER copy-paste the developer's raw phrasing ("instead of...", "but in a...") verbatim.
- DELTA-ONLY OUTPUT: Call `$activeToolName` including ONLY `reply` and the specific Blueprint key(s) that actually changed. Omit all unchanged keys!$sectionScopeRule

Call `$activeToolName` with the delta update.
''';

    final json = await GeminiAgentClient.generateJson(
      prompt: prompt,
      apiKey: apiKey,
      preferredModel: conversationModel,
      thinkingLevel: thinkingLevel,
      temperature: 0.45,
      functionDeclarations: [activeConceptTool],
    );

    if (json == null) return false;

    List<String>? cleanList(dynamic raw) {
      if (raw is! List && raw is! Map) return null;
      final list = _parseStringList(raw);
      return list.isNotEmpty ? list : null;
    }

    final updated = <String>[];
    final newTitle = json['title']?.toString().trim() ?? '';
    if (!_isPlaceholderString(newTitle) && newTitle != draft.title) {
      draft.title = newTitle;
      updated.add('Title');
    }
    final game = _parseSpecCells(
      json['gameSpec'],
      const ['cameraView', 'controls', 'playerMode', 'arenaStructure'],
    );
    if (game.length >= 2) {
      draft.gameSpec = game;
      updated.add('Game Spec');
    }
    final tech = _parseSpecCells(
      json['techSpec'],
      const ['engine', 'platform', 'assetPipeline', 'saveMode'],
    );
    if (tech.length >= 2) {
      draft.techSpec = _normalizeTechSpecEngine(
        tech,
        draft.gameSpec,
        draft.sparkIdea,
      );
      updated.add('Tech Spec');
    }
    final pillars = parsePillarsList(json['designPillars']);
    if (pillars.isNotEmpty) {
      draft.designPillars = pillars;
      updated.add('Design Pillars');
    }
    final tradeOffs = parseTradeOffsList(json['tradeOffs']);
    if (tradeOffs.isNotEmpty) {
      draft.tradeOffs = tradeOffs;
      updated.add('Trade-Offs');
    }
    final newGoal = json['goal']?.toString().trim() ?? '';
    if (!_isPlaceholderString(newGoal) && newGoal != draft.goal) {
      draft.goal = ProjectConceptBlueprint.sanitizeGoalText(newGoal);
      updated.add('Goal');
    }
    final goalOpts = cleanList(json['goalOptions']);
    if (goalOpts != null && goalOpts.length >= 2) {
      draft.sectionOptions['goal'] = goalOpts;
    }
    final nestedSectionOpts = _parseSectionOptions(json['sectionOptions']);
    for (final entry in nestedSectionOpts.entries) {
      if (entry.value.isNotEmpty) {
        draft.sectionOptions[entry.key] = entry.value;
      }
    }
    final beats = cleanList(json['coreLoopBeats']);
    if (beats != null) {
      draft.coreLoopBeats = sortBeatsByDeveloperImpact(beats);
      updated.add('Core Loop');
    }
    final excl = cleanList(json['exclusions']);
    if (excl != null) {
      draft.exclusions = excl;
      updated.add('Exclusions');
    }
    final done = json['doneWhen']?.toString().trim() ?? '';
    if (!_isPlaceholderString(done) && done != draft.doneWhen) {
      draft.doneWhen = done;
      updated.add('Done When');
    }
    final releases = cleanList(json['releaseTrainTitles']);
    if (releases != null) {
      draft.releaseTrainTitles = releases;
      updated.add('Prototype Release');
    }

    final explicitUpdated = cleanList(json['updatedFields']);
    final effectiveUpdated =
        (explicitUpdated != null && explicitUpdated.isNotEmpty)
            ? explicitUpdated
            : (updated.isNotEmpty ? updated : const ['Concept Refined']);

    final replyText = json['reply']?.toString().trim() ??
        'Updated the Project Concept Blueprint with your direction!';

    draft.lastUpdatedFields = effectiveUpdated;
    draft.isInterviewComplete = true;
    draft.lastAgentReply = replyText;
    return true;
  }

  static const List<({String tag, String label, String directive})>
      conceptSectionBuildOrder = [
    (
      tag: '[Section 01 · Goal]',
      label: '01 · Goal',
      directive:
          'Draft the initial concise 2-3 word `title` and `goal` ("Build a playable [Title] prototype where you [action 1], [action 2], and [action 3].").',
    ),
    (
      tag: '[Section 02 · Game Spec]',
      label: '02 · Game Spec',
      directive:
          'Draft the 4 cells of `gameSpec` (`cameraView`, `controls`, `playerMode`, `arenaStructure`) strictly as 2-4 Title-Case words each (e.g. "3D First-Person", "WASD + Mouse", "Singleplayer", "Rooftop Garden Hub"; no narrative sentences or clauses).',
    ),
    (
      tag: '[Section 03 · Tech Spec]',
      label: '03 · Tech Spec',
      directive:
          'Draft the 4 cells of `techSpec` (`engine` must be "Unreal Engine 5 (Blueprints)", "Unreal Engine 5 (C++)", or "Unreal Engine 5 (Blueprints / C++)", plus `platform`, `assetPipeline`, `saveMode`) strictly as 2-4 Title-Case words each (e.g. "PC Desktop", "UE5 Greybox + Lumen", "SaveGame Slot (.sav)").',
    ),
    (
      tag: '[Section 04 · Design Pillars]',
      label: '04 · Design Pillars',
      directive:
          'Draft `designPillars` naming the core player feelings and emotional experiences the game must create (never features or genres).',
    ),
    (
      tag: '[Section 05 · Trade-Offs]',
      label: '05 · Trade-Offs',
      directive:
          'Draft `tradeOffs` as practical `priorityX` over `overAlternativeY` engineering and design boundaries.',
    ),
    (
      tag: '[Section 06 · Core Loop]',
      label: '06 · Core Loop',
      directive:
          'Draft `coreLoopBeats` in chronological playable loop order ("Beat Name: Observable player action and system response"), starting with immediate in-game player control and ending with reward/upgrade and next-cycle reset.',
    ),
    (
      tag: '[Section 07 · Out of Scope]',
      label: '07 · Out of Scope',
      directive:
          'Draft `exclusions` listing explicit prototype scope cuts ("No ...") to keep v0.1 focused.',
    ),
    (
      tag: '[Section 08 · Done When]',
      label: '08 · Done When',
      directive:
          'Draft `doneWhen` as a concise 1-sentence observable playtest completion condition covering the Core Loop without FPS targets.',
    ),
  ];

  /// Ranks a Core Loop Beat so pre-match Staging/Loadout menus (`3`) and end-of-run Reset/Summary (`4`)
  /// are never placed ahead of active in-game gameplay beats (`0`), while preserving the exact
  /// chronological player order of all active gameplay beats (`0`).
  static int developerImpactTierForBeat(String rawBeat) {
    final head = rawBeat.split(':').first.toLowerCase();

    final isResetOrSummary = head.contains('reset') ||
        head.contains('resolution') ||
        head.contains('summary') ||
        head.contains('tally');
    if (isResetOrSummary) return 4;

    final isPrepOrLoadout = (head.contains('staging') ||
            head.contains('loadout') ||
            head.contains('prep') ||
            head.contains('contract') ||
            head.contains('menu') ||
            head.contains('rig select')) &&
        !head.contains('traversal') &&
        !head.contains('movement') &&
        !head.contains('driving') &&
        !head.contains('parkour');
    if (isPrepOrLoadout) return 3;

    return 0;
  }

  /// Ensures `coreLoopBeats` starts with the highest-impact Core Toy & Primary Control beat
  /// and places low-impact Staging/Loadout Prep beats after the core gameplay mechanics exist.
  static List<String> sortBeatsByDeveloperImpact(List<String> beats) {
    if (beats.length <= 1) return beats;
    final firstTier = developerImpactTierForBeat(beats.first);
    final hasHigherImpactLater =
        beats.skip(1).any((b) => developerImpactTierForBeat(b) < firstTier);
    if (!hasHigherImpactLater) return beats;

    final indexed = <({int index, int tier, String beat})>[
      for (int i = 0; i < beats.length; i++)
        (index: i, tier: developerImpactTierForBeat(beats[i]), beat: beats[i]),
    ];
    indexed.sort((a, b) {
      final cmp = a.tier.compareTo(b.tier);
      return cmp != 0 ? cmp : a.index.compareTo(b.index);
    });
    return [for (final item in indexed) item.beat];
  }

  static Map<String, List<String>> _parseSectionOptions(
    dynamic rawSectionOptions,
  ) {
    final result = <String, List<String>>{};
    if (rawSectionOptions is! Map) return result;

    for (final entry in rawSectionOptions.entries) {
      final key = entry.key.toString().trim();
      if (key.isNotEmpty) {
        final typedCleaned = parseSectionOptionsToolOutput(key, entry.value);
        final cleaned = typedCleaned.isNotEmpty
            ? typedCleaned
            : _parseStringList(entry.value);
        if (cleaned.isNotEmpty) {
          result[key] = cleaned;
        }
      }
    }
    return result;
  }

  /// Ingests a raw game idea (or refines an existing ingested summary) on the New Project screen
  /// via Gemini AI (`gemini-flash-latest`). Returns `null` if offline or if Gemini AI is unreachable.
  static Future<SparkIdeaIntakeResult?> ingestOrRefineSparkIdea({
    required String userInput,
    SparkIdeaIntakeResult? existingIntake,
    int suggestionVariantOffset = 0,
    String apiKey = '',
    String modelName = 'gemini-flash-latest',
    String thinkingLevel = 'LOW',
  }) async {
    final cleanInput = userInput.trim();
    final seedIdea =
        existingIntake != null ? existingIntake.rawIdea : cleanInput;
    if (seedIdea.isEmpty || !GeminiAgentClient.hasKey(apiKey)) {
      return null;
    }

    final selectedCardAdditions = existingIntake == null
        ? const <String>[]
        : existingIntake.expansionCards
            .where((c) => c.isSelected)
            .map((c) => '${c.title}: ${c.additionSummary}')
            .toList();
    final selectedContext = selectedCardAdditions.isEmpty
        ? ''
        : '\nSelected Idea Additions to Fold In: ${selectedCardAdditions.join(' | ')}';

    final prompt = '''
You are an indie game producer summarizing a developer's game idea before building the blueprint.
${existingIntake != null ? 'Original Premise: "${existingIntake.rawIdea}"\nPrevious Title: "${existingIntake.workingTitle}"\nPrevious Summary: "${existingIntake.baseSummary}"$selectedContext\n${cleanInput.isNotEmpty ? 'User Update Direction: "$cleanInput"' : 'Action: Polish Previous Summary into a clean 2-sentence game pitch.'}' : 'Raw Idea: "$seedIdea"'}
${GeminiAgentClient.compactStyleRules}
- `workingTitle` MUST be a concrete 2-3 word game title naming the setting/role/mechanic (NEVER just copy the first 3 words of the user's sentence).
- `baseSummary` MUST be 2 natural sentences synthesizing the premise, core mechanics, and loop in game-design language (NEVER quote, echo, or replace the summary with the user's raw input sentence verbatim).
- `missing` lists (max 2) only what the developer's own text truly lacks: `TWIST` (a risk or cost), `SETUP` (camera and engine), `ACTION` (what the player does every few seconds). Never invent one; return an empty array when all three are present.
${existingIntake != null ? '- Preserve the core genre, role, and setting of `Previous Summary` while smoothly integrating `User Update Direction` (never switch to an unrelated genre).' : ''}

Call `commit_spark_intake` with the structured summary.
''';

    final json = await GeminiAgentClient.generateJson(
      prompt: prompt,
      apiKey: apiKey,
      preferredModel: modelName,
      thinkingLevel: thinkingLevel,
      temperature: 0.45,
      functionDeclarations: const [commitSparkIntakeTool],
    );
    if (json == null) return null;

    final wTitle = (json['workingTitle'] ?? '').toString().trim();
    final summary = (json['baseSummary'] ?? '').toString().trim();
    final mechs = _parseStringList(json['mechanics']);
    final cards = _parseExpansionCards(json['expansionCards']);
    if (summary.isEmpty ||
        (GeminiAgentClient.testMockResponder != null && cards.isEmpty)) {
      return null;
    }

    final updatedRawIdea = existingIntake != null
        ? (cleanInput.isNotEmpty
            ? '${existingIntake.rawIdea}, $cleanInput'
            : existingIntake.rawIdea)
        : seedIdea;
    return SparkIdeaIntakeResult(
      rawIdea: updatedRawIdea,
      workingTitle: wTitle.isNotEmpty
          ? wTitle
          : (existingIntake?.workingTitle ?? updatedRawIdea),
      baseSummary: summary,
      mechanics: mechs.isNotEmpty
          ? mechs
          : (existingIntake?.mechanics ?? const <String>[]),
      expansionCards: cards.isNotEmpty
          ? cards
          : (existingIntake?.expansionCards ?? const <SparkExpansionCard>[]),
      missing: _parseMissingPieces(json['missing']),
    );
  }

  /// Refreshes ONLY the 3 Concept Expansion / Twist Cards on the Stage 1A New Project screen
  /// while strictly preserving `existingIntake.rawIdea`, `workingTitle`, `baseSummary`, and `mechanics`.
  /// Returns `null` if offline or if Gemini AI is unreachable.
  static Future<List<SparkExpansionCard>?> refreshSparkExpansionCards({
    required SparkIdeaIntakeResult existingIntake,
    required int suggestionVariantOffset,
    String apiKey = '',
    String modelName = 'gemini-flash-latest',
    String thinkingLevel = 'LOW',
  }) async {
    if (!GeminiAgentClient.hasKey(apiKey)) return null;

    final previousTitles = existingIntake.expansionCards
        .map((c) => c.title.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    final prompt = '''
You are an indie game producer proposing 3 NEW gameplay expansion / twist cards for this exact game concept:
Working Title: "${existingIntake.workingTitle}"
Original Idea: "${existingIntake.rawIdea}"
Current Summary: "${existingIntake.baseSummary}"
Core Mechanics: ${existingIntake.mechanics.join(', ')}
${previousTitles.isNotEmpty ? 'Previously Shown Cards (DO NOT REPEAT): ${previousTitles.join(' | ')}' : ''}

${GeminiAgentClient.compactStyleRules}
- Stay 100% faithful to "${existingIntake.workingTitle}" and its exact subject, genre, and mechanics (never switch to an unrelated genre or theme).
- Propose 3 distinct, concrete playable twists that complement "${existingIntake.workingTitle}".

Call `propose_spark_expansion_cards` with 3 fresh expansion cards.
''';

    final json = await GeminiAgentClient.generateJson(
      prompt: prompt,
      apiKey: apiKey,
      preferredModel: modelName,
      thinkingLevel: thinkingLevel,
      temperature: 0.65,
      functionDeclarations: const [proposeSparkExpansionCardsTool],
    );
    if (json == null) return null;

    final cards = _parseExpansionCards(json['expansionCards']);
    if (cards.length < 3) return null;

    return _preserveSelectedExpansionCards(
      existingCards: existingIntake.expansionCards,
      freshCards: cards,
    );
  }

  static List<SparkExpansionCard> _preserveSelectedExpansionCards({
    required List<SparkExpansionCard> existingCards,
    required List<SparkExpansionCard> freshCards,
  }) {
    final result = <SparkExpansionCard>[];
    for (int i = 0; i < 3; i++) {
      if (i < existingCards.length && existingCards[i].isSelected) {
        result.add(existingCards[i]);
      } else if (i < freshCards.length) {
        result.add(freshCards[i]);
      }
    }
    return result;
  }

  /// Regenerates 3 fresh Option Cards for a specific Stage 1B section (`optionKey`)
  /// using `gemini-flash-latest`. Returns `null` if offline or if Gemini AI is unreachable.
  static Future<List<String>?> regenerateSectionOptionsWithAi({
    required ProjectConceptBlueprint draft,
    required String optionKey,
    required List<String> currentOptions,
    String apiKey = '',
    String modelName = 'gemini-flash-latest',
    String thinkingLevel = 'LOW',
  }) async {
    if (!GeminiAgentClient.hasKey(apiKey)) return null;

    final sectionFormatRule = switch (optionKey) {
      'goal' =>
        '- Format each option as: `"Strategy Label: Build a playable ${draft.title} prototype where you [action 1], [action 2], and [action 3]."`',
      'gameSpec' =>
        '- Format each option with 4 `·`-separated cells after the colon: `"Spec Label: Camera View · Controls · Player Mode · Arena Structure"` (e.g., `"Tight Arena Spec: 2D Top-Down · Twin-Stick WASD+Mouse · Singleplayer · Single-Screen Arena"`).',
      'techSpec' =>
        '- Format each option with 4 `·`-separated cells after the colon: `"Stack Label: Unreal Engine 5 Workflow · Platform · Asset Pipeline · Save Mode"` (e.g., `"UE5 Hybrid Stack: Unreal Engine 5 (Blueprints / C++) · PC Desktop · UE5 Greybox + Lumen · SaveGame Slot (.sav)"`).',
      'designPillars' =>
        '- Format each option as: `"2-3 Word Pillar Name: 1-sentence core player feeling or emotional tension (never a feature or genre)"`.',
      'tradeOffs' =>
        '- Format each option as an explicit `X over Y` boundary rule: `"Rule Label: Concrete Priority X over Concrete Alternative Y"`.',
      'coreLoop' =>
        '- Format each option as a 4-to-5 beat chain separated by ` → `: `"Loop Label: Beat 1 Name: Action → Beat 2 Name: Action → Beat 3 Name: Action → Beat 4 Name: Action"`.',
      'exclusions' =>
        '- Format each option as a prototype scope cut: `"Cut Label: No [2-4 word excluded system/content]"`.',
      'doneWhen' =>
        '- Format each option in Causal Trigger -> Result style without FPS targets: `"Playtest Gate Label: [Player Action] -> [Observable Loop Resolution]"`.',
      _ =>
        '- Format each option as `"Short Label: Concrete statement tailored to ${draft.title}"`.',
    };

    final sectionOptionsTool = buildSectionOptionsTool(optionKey);
    final sectionToolName =
        sectionOptionsTool['name']?.toString() ?? 'propose_section_options';

    final prompt = '''
You are an indie game producer generating 3 fresh Option Cards for the "$optionKey" section of this game concept:
Title: "${draft.title}"
Spark Premise: "${draft.sparkIdea}"
Current Goal: "${draft.goal}"
Game Spec: ${draft.gameSpec.join(' · ')}
Tech Spec: ${draft.techSpec.join(' · ')}
Design Pillars: ${draft.designPillars.join(' | ')}
Trade-Offs: ${draft.tradeOffs.join(' | ')}
Current Core Loop: ${draft.coreLoopBeats.join(' -> ')}
Out of Scope: ${draft.exclusions.join(' | ')}
${currentOptions.isNotEmpty ? 'Previously Shown Options (DO NOT REPEAT): ${currentOptions.join(' | ')}' : ''}

${GeminiAgentClient.compactStyleRules}
- Stay 100% faithful to "${draft.title}" and its locked upstream Game Spec, Tech Spec, Design Pillars, and Trade-Offs.
$sectionFormatRule

Call `$sectionToolName` with 3 fresh options.
''';
    final json = await GeminiAgentClient.generateJson(
      prompt: prompt,
      apiKey: apiKey,
      preferredModel: modelName,
      thinkingLevel: thinkingLevel,
      temperature: 0.65,
      functionDeclarations: [sectionOptionsTool],
    );
    final parsed = parseSectionOptionsToolOutput(optionKey, json?['options'])
        .take(3)
        .toList();
    if (parsed.length >= 2) {
      return parsed;
    }
    return null;
  }

  /// Option 5: Extracts a complete 8-section `ProjectConceptBlueprint` from an unstructured
  /// GDD, Notion note, or README document and marks it ready for `Step 09 · Full Concept Review`.
  /// Returns `null` if offline or if Gemini AI is unreachable.
  static Future<ProjectConceptBlueprint?> extractConceptFromGdd(
    String rawGdd, {
    String apiKey = '',
    String modelName = 'gemini-flash-latest',
    String thinkingLevel = 'LOW',
  }) async {
    final cleanDoc = rawGdd.trim();
    if (cleanDoc.isEmpty || !GeminiAgentClient.hasKey(apiKey)) return null;

    final bp = await startConceptInterview(
      cleanDoc,
      apiKey: apiKey,
      modelName: modelName,
      thinkingLevel: thinkingLevel,
      isGddExtraction: true,
    );
    if (bp == null) return null;

    bp.isInterviewComplete = true;
    bp.lastUpdatedFields = const [
      'Extracted Full 8-Section Concept from Pasted GDD / Notes',
    ];
    return bp;
  }
}

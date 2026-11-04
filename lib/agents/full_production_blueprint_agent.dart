import '../constants/text_style_guide.dart';
import '../models/agent_blueprints.dart';
import 'gemini_agent_client.dart';

/// Act 2 · Full Production Blueprint Agent.
/// Drafts the 6-section Full Production Blueprint (with 3 option cards per section)
/// in a single `gemini-flash-latest` pass once the Vertical Slice is complete.
class FullProductionBlueprintAgent {
  const FullProductionBlueprintAgent._();

  static const Map<String, dynamic> commitFullProductionBlueprintTool = {
    'name': 'commit_full_production_blueprint',
    'description':
        'Commits the Act 2 Full Production Blueprint that turns the finished 1-level Vertical Slice into the full v1.0 game, plus 3 option cards per section.',
    'parameters': {
      'type': 'OBJECT',
      'required': [
        'goal',
        'contentScale',
        'fullGameLoop',
        'promotedSystems',
        'permanentCuts',
        'doneWhen',
      ],
      'properties': {
        'goal': {
          'type': 'STRING',
          'description': LayersTextStyleGuide.blufReleaseGoalSchemaDesc,
        },
        'contentScale': {
          'type': 'ARRAY',
          'description':
              'Target v1.0 content counts as 2–4 word Title-Case labels (e.g. "3 Biomes", "6 Enemy Types", "3 Bosses", "12 Shop Perks").',
          'items': {'type': 'STRING'},
        },
        'fullGameLoop': {
          'type': 'ARRAY',
          'description':
              'Full-game progression beats from launch to credits/next run, each as "[2–4 Word Beat] — [Scope]".',
          'items': {'type': 'STRING'},
        },
        'promotedSystems': {
          'type': 'ARRAY',
          'description':
              'Deferred or new systems now in v1.0 scope as 2–4 word Title-Case labels (e.g. "Save & Load", "Title Menu", "Audio Settings").',
          'items': {'type': 'STRING'},
        },
        'permanentCuts': {
          'type': 'ARRAY',
          'description':
              'Systems that stay out of v1.0 formatted "No [2–4 word system]".',
          'items': {'type': 'STRING'},
        },
        'doneWhen': {
          'type': 'STRING',
          'description': LayersTextStyleGuide.causalTriggerResultSchemaDesc,
        },
        'sectionOptions': {
          'type': 'OBJECT',
          'description':
              '3 alternative option cards per section keyed by goal, contentScale, fullGameLoop, promotedSystems, permanentCuts, doneWhen. List sections use " | " to join items inside 1 option.',
          'properties': {
            'goal': {
              'type': 'ARRAY',
              'items': {'type': 'STRING'},
            },
            'contentScale': {
              'type': 'ARRAY',
              'items': {'type': 'STRING'},
            },
            'fullGameLoop': {
              'type': 'ARRAY',
              'items': {'type': 'STRING'},
            },
            'promotedSystems': {
              'type': 'ARRAY',
              'items': {'type': 'STRING'},
            },
            'permanentCuts': {
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
    },
  };

  /// Returns `null` when Gemini AI is unreachable (the user can still fill the sections by hand).
  static Future<FullProductionBlueprint?> draft({
    required String projectTitle,
    required String conceptSummary,
    required String liveTreeSummary,
    required List<String> unlockedDeferredExclusions,
    required List<String> scheduledInboxTitles,
    required String apiKey,
    String modelName = 'gemini-flash-latest',
    String thinkingLevel = 'LOW',
  }) async {
    if (!GeminiAgentClient.hasKey(apiKey)) return null;
    final prompt = '''
You are the Lead Game Producer for "$projectTitle". The 1-level Vertical Slice is finished and polished.
Draft the Act 2 Full Production Blueprint that turns this Vertical Slice into the complete v1.0 game.
$conceptSummary
Live Vertical Slice Tree (core Epics stay STABLE — never redesign them):
$liveTreeSummary
Deferred Out-of-Scope items now unlocked for Full Production: ${unlockedDeferredExclusions.isEmpty ? 'none' : unlockedDeferredExclusions.join(' | ')}
Feature Inbox ideas scheduled for Full Production: ${scheduledInboxTitles.isEmpty ? 'none' : scheduledInboxTitles.join(' | ')}
${GeminiAgentClient.compactStyleRules}
- Section 04 Promoted Systems MUST include every unlocked deferred item and scheduled Inbox idea above unless it conflicts with a permanent cut.
- Content & World Scale names target counts only (never mechanics already finished in the Vertical Slice).
- Full-Game Loop describes the whole playthrough (launch → progression → bosses/finale → save/unlocks → credits or next run).
- 06 Done When is 1 observable Trigger → Result sentence covering the full v1.0 playthrough from the title screen.
- Provide 3 option cards per section in sectionOptions (first option = your recommendation).
Call `commit_full_production_blueprint`.''';

    final json = await GeminiAgentClient.generateJson(
      prompt: prompt,
      apiKey: apiKey,
      preferredModel: modelName,
      thinkingLevel: thinkingLevel,
      temperature: 0.45,
      functionDeclarations: const [commitFullProductionBlueprintTool],
    );
    if (json == null) return null;
    final bp = FullProductionBlueprint.fromJson(json);
    for (final item in scheduledInboxTitles) {
      final norm = item.toLowerCase().trim();
      if (norm.isNotEmpty &&
          !bp.promotedSystems.any((p) => p.toLowerCase().trim() == norm)) {
        bp.promotedSystems.add(item.trim());
      }
    }
    return bp.goal.isEmpty && bp.fullGameLoop.isEmpty ? null : bp;
  }
}

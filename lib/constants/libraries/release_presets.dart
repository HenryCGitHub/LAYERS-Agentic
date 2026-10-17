import '../tiers.dart';

/// Standard release milestone presets across the 7 release types.
const List<ReleaseScopePreset> standardReleasePresets = [
  ReleaseScopePreset(
    id: 'preset_featurePrototype',
    title: 'Prototype',
    icon: '',
    description:
        'A fast prototype to test if a single mechanic or feature is fun and feasible.',
    appDescription:
        'A rapid spike to test a single technical approach or interaction pattern.',
    phaseTemplateIds: [
      'core_systems_spike',
      'assemble_systems_sandbox',
    ],
  ),
  ReleaseScopePreset(
    id: 'preset_proofOfConcept',
    title: 'Proof of Concept',
    icon: '',
    description:
        'A rapid concept prototype proving the core game idea works as a playable whole.',
    appDescription:
        'A rapid concept prototype proving the core product idea works as a usable whole.',
    phaseTemplateIds: [
      'core_mechanics_production',
      'content_world_building',
      'polish_game_feel',
      'playtesting_balancing',
    ],
  ),
  ReleaseScopePreset(
    id: 'preset_mvp',
    title: 'MVP',
    icon: '',
    description:
        'The bare-minimum playable build to test the complete game loop from start to finish.',
    appDescription:
        'The minimum viable product running the complete core user workflow.',
    phaseTemplateIds: [
      'core_mechanics_production',
      'content_world_building',
      'polish_game_feel',
      'optimization_qa',
    ],
  ),
  ReleaseScopePreset(
    id: 'preset_verticalSlice',
    title: 'Vertical Slice',
    icon: '',
    description:
        'A 10–15 minute showcase level built to near-final visual, audio, and feel quality to prove the finished quality bar.',
    appDescription:
        'A complete vertical slice of one full feature module built to production-grade quality and polish.',
    phaseTemplateIds: [
      'content_world_building',
      'polish_game_feel',
      'playtesting_balancing',
      'optimization_qa',
    ],
  ),
  ReleaseScopePreset(
    id: 'preset_fullProduction',
    title: 'Full Production',
    icon: '',
    description:
        'Building out all content, levels, systems, and polish for the complete game release.',
    appDescription:
        'Complete product engineering, backend integrations, security, edge cases, and launch readiness.',
    phaseTemplateIds: [
      'content_world_building',
      'polish_game_feel',
      'playtesting_balancing',
      'optimization_qa',
      'launch_deployment',
      'live_operations_maintenance',
    ],
  ),
  ReleaseScopePreset(
    id: 'preset_patch',
    title: 'Patch / Maintenance',
    icon: '',
    description:
        'A targeted fix release addressing bugs, balance issues, and stability improvements for a live product.',
    appDescription:
        'A targeted fix release addressing bugs, performance regressions, and stability issues.',
    phaseTemplateIds: [
      'optimization_qa',
      'launch_deployment',
    ],
  ),
  ReleaseScopePreset(
    id: 'preset_contentUpdate',
    title: 'Feature & Content Update',
    icon: '',
    description:
        'A post-launch content drop adding new features, levels, mechanics, and systems to an already-shipped game.',
    appDescription:
        'A post-launch update adding new features, workflows, integrations, and enhancements.',
    phaseTemplateIds: [
      'content_world_building',
      'polish_game_feel',
      'playtesting_balancing',
      'optimization_qa',
    ],
  ),
];

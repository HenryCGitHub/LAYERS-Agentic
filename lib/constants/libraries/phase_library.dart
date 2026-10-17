import '../tiers.dart';

/// Standard atomic phase templates across production categories.
const List<PhaseTemplate> standardPhaseLibrary = [
  // Prototype Phase 1: Core Systems Spike
  PhaseTemplate(
    id: 'core_systems_spike',
    title: 'Core Systems',
    category: PhaseCategory.coreSystems,
    defaultGoal:
        'Build and verify isolated core mechanic systems and interactions in greybox.',
    defaultBuildDefinition:
        'Functional mechanics test build with responsive inputs and basic feedback.',
  ),

  // Prototype Phase 2: Assemble Systems Sandbox
  PhaseTemplate(
    id: 'assemble_systems_sandbox',
    title: 'Assemble Systems',
    category: PhaseCategory.assembly,
    defaultGoal:
        'Assemble core systems together into one playable test arena to evaluate game feel and loop verification.',
    defaultBuildDefinition:
        'Integrated sandbox build executing the full moment-to-moment loop at target frame rate.',
  ),

  // 1. Prototyping
  PhaseTemplate(
    id: 'pre_production_prototyping',
    title: 'Prototyping',
    category: PhaseCategory.prototyping,
    defaultGoal:
        'Test core movement and control feel to verify the baseline gameplay interaction loop. Strictly defer high-poly 3D models, textures, custom audio mixing, and netcode.',
    defaultBuildDefinition:
        'Playable graybox dev branch executable with responsive jumping and collisions tested over a complete 3-minute obstacle course.',
  ),

  // 2. Core Systems
  PhaseTemplate(
    id: 'core_mechanics_production',
    title: 'Core Systems',
    category: PhaseCategory.coreSystems,
    defaultGoal:
        'Build the foundational player state machine and implement combat hit detection rules. Strictly defer mass environment content creation, marketing UI, and cosmetic skins.',
    defaultBuildDefinition:
        'Feature-complete mechanics test sandbox build executing a 5-minute combat engagement testing combo chaining and input buffers.',
  ),

  // 3. Content
  PhaseTemplate(
    id: 'content_world_building',
    title: 'Content',
    category: PhaseCategory.content,
    defaultGoal:
        'Author modular environment biome kits and integrate enemy encounter patrol packs. Strictly defer core physics engine rewrites and net-new combat subsystems.',
    defaultBuildDefinition:
        'Integrated zone build with item spawns navigating a 10-minute exploration loop engaging placed enemy encampments.',
  ),

  // 4. Polish
  PhaseTemplate(
    id: 'polish_game_feel',
    title: 'Polish',
    category: PhaseCategory.polish,
    defaultGoal:
        'Tighten melee hit-stop and recoil timing while adding directional stealth audio visualizers. Strictly defer new secondary game modes and additional weapon archetypes.',
    defaultBuildDefinition:
        'Juiced build with tactile feedback enabled running a full combat encounter loop testing screenshake and impact cues.',
  ),

  // 5. Testing
  PhaseTemplate(
    id: 'playtesting_balancing',
    title: 'Testing',
    category: PhaseCategory.testing,
    defaultGoal:
        'Triage playtest feedback and telemetry while balancing combat difficulty curves and pacing. Strictly defer unapproved scope expansion and net-new system introductions.',
    defaultBuildDefinition:
        'Tuned build with telemetry dashboard active completing a full mission run verifying resource economy pacing.',
  ),

  // 6. Optimize
  PhaseTemplate(
    id: 'optimization_qa',
    title: 'Optimize',
    category: PhaseCategory.optimize,
    defaultGoal:
        'Profile GPU/CPU budgets to baseline and fix memory leaks and crash bugs. Strictly defer new gameplay feature commits and unoptimized raw art imports.',
    defaultBuildDefinition:
        'Stable release candidate build v0.1.0-RC executing a 30-minute stress test run verifying frame rates under max load.',
  ),

  // 7. Launch
  PhaseTemplate(
    id: 'launch_deployment',
    title: 'Launch',
    category: PhaseCategory.launch,
    defaultGoal:
        'Package release build and sign certificates while verifying storefront achievements and cloud save pipelines. Strictly defer untested code changes and non-critical refactors.',
    defaultBuildDefinition:
        'Verified public storefront gold master build completing first-time user tutorial with verified cloud save sync integrity.',
  ),

  // 8. Live Ops
  PhaseTemplate(
    id: 'live_operations_maintenance',
    title: 'Live Ops',
    category: PhaseCategory.liveOps,
    defaultGoal:
        'Deploy seasonal content and balance patches while addressing player bug reports and regressions. Strictly defer breaking database schema changes and unverified live service updates.',
    defaultBuildDefinition:
        'Live update build with verified changelog testing seasonal event challenge loop and verifying cosmetic inventory persistence.',
  ),
];

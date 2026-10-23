import 'package:flutter/material.dart';
import 'libraries/release_presets.dart';
export 'libraries/release_presets.dart';

enum TierType {
  project,
  release,
  epic,
  feature;

  String get id => name.toUpperCase();

  String get displayName => switch (this) {
        TierType.project => 'Project',
        TierType.release => 'Release',
        TierType.epic => 'Epic',
        TierType.feature => 'Feature',
      };

  String get pluralDisplayName => switch (this) {
        TierType.project => 'Projects',
        TierType.release => 'Releases',
        TierType.epic => 'Epics',
        TierType.feature => 'Features',
      };

  int get level => switch (this) {
        TierType.project => 1,
        TierType.release => 2,
        TierType.epic => 3,
        TierType.feature => 4,
      };

  String get shortTag => switch (this) {
        TierType.project => 'PROJ',
        TierType.release => 'REL',
        TierType.epic => 'EPIC',
        TierType.feature => 'FEAT',
      };

  String get letterBadge => switch (this) {
        TierType.project => 'P',
        TierType.release => 'R',
        TierType.epic => 'E',
        TierType.feature => 'F',
      };

  String get emoji => letterBadge;

  IconData get icon => switch (this) {
        TierType.project => Icons.folder_outlined,
        TierType.release => Icons.rocket_launch_outlined,
        TierType.epic => Icons.layers_outlined,
        TierType.feature => Icons.widgets_outlined,
      };

  String get descriptionTooltip => switch (this) {
        TierType.project => 'Project: Root game workspace',
        TierType.release => 'Release: Target ship milestone',
        TierType.epic => 'Epic: Core Gameplay Loop Epic',
        TierType.feature => 'Feature: Playable mechanic & deliverable',
      };

  Color colorFor(bool isDark) => switch (this) {
        TierType.project =>
          isDark ? const Color(0xFFC084FC) : const Color(0xFF7E22CE), // Purple
        TierType.release =>
          isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7), // Sky Blue
        TierType.epic =>
          isDark ? const Color(0xFF22D3EE) : const Color(0xFF0891B2), // Cyan
        TierType.feature =>
          isDark ? const Color(0xFFFB923C) : const Color(0xFFEA580C), // Coral / Orange
      };

  Color get color => colorFor(true);

  TierType? get nextChildTier => switch (this) {
        TierType.project => TierType.release,
        TierType.release => TierType.epic,
        TierType.epic => TierType.feature,
        TierType.feature => null,
      };

  TierType? get parentTier => switch (this) {
        TierType.project => null,
        TierType.release => TierType.project,
        TierType.epic => TierType.release,
        TierType.feature => TierType.epic,
      };

  static TierType fromString(String val) {
    final lower = val.toLowerCase().trim();
    if (lower == 'goal' || lower == 'project') return TierType.project;
    if (lower == 'phase' || lower == 'release') return TierType.release;
    if (lower == 'epic') return TierType.epic;
    if (lower == 'task' || lower == 'feature') return TierType.feature;
    return TierType.values.firstWhere(
      (e) => e.name.toLowerCase() == lower,
      orElse: () => TierType.project,
    );
  }
}

enum PhaseCategory {
  prototyping('Prototyping'),
  coreSystems('Core Systems'),
  assembly('Assemble Systems'),
  content('Content'),
  polish('Polish'),
  testing('Testing'),
  optimize('Optimize'),
  launch('Launch'),
  liveOps('Live Ops');

  final String label;
  String get icon => '';

  const PhaseCategory(this.label);

  // Backward compatibility static aliases for legacy keys
  static const PhaseCategory production = coreSystems;
  static const PhaseCategory gameFeel = polish;
  static const PhaseCategory playtesting = testing;
  static const PhaseCategory qa = optimize;
  static const PhaseCategory liveUpdates = liveOps;
  static const PhaseCategory assembleSystems = assembly;

  static PhaseCategory fromString(String? val, {String title = ''}) {
    if (val != null && val.isNotEmpty) {
      final clean = val.toLowerCase().trim();
      for (final cat in PhaseCategory.values) {
        if (cat.name.toLowerCase() == clean ||
            cat.label.toLowerCase() == clean ||
            cat.label.toLowerCase().contains(clean) ||
            clean.contains(cat.name.toLowerCase())) {
          return cat;
        }
      }
      // Backward-compatible mapping for legacy enum names & old long labels
      if (clean == 'assembly' ||
          clean == 'assemblesystems' ||
          clean == 'assemble systems' ||
          clean.contains('assemble') ||
          clean.contains('assembly')) {
        return PhaseCategory.assembly;
      }
      if (clean == 'production' ||
          clean.contains('core mechanics') ||
          clean.contains('core systems')) {
        return PhaseCategory.coreSystems;
      }
      if (clean == 'gamefeel' ||
          clean == 'game feel' ||
          clean.contains('polish')) {
        return PhaseCategory.polish;
      }
      if (clean == 'playtesting' ||
          clean.contains('balancing') ||
          clean.contains('playtest') ||
          clean.contains('testing')) {
        return PhaseCategory.testing;
      }
      if (clean == 'qa' ||
          clean.contains('optimization') ||
          clean.contains('optimize')) {
        return PhaseCategory.optimize;
      }
      if (clean == 'liveupdates' ||
          clean == 'live updates' ||
          clean.contains('live operations') ||
          clean.contains('live ops')) {
        return PhaseCategory.liveOps;
      }
      if (clean.contains('prototyping') ||
          clean.contains('r&d') ||
          clean.contains('prototype')) {
        return PhaseCategory.prototyping;
      }
      if (clean.contains('content') || clean.contains('world')) {
        return PhaseCategory.content;
      }
      if (clean.contains('launch') || clean.contains('deployment')) {
        return PhaseCategory.launch;
      }
    }
    final lowerTitle = title.toLowerCase();
    if (lowerTitle.contains('assemble') ||
        lowerTitle.contains('assembly')) {
      return PhaseCategory.assembly;
    } else if (lowerTitle.contains('feel') ||
        lowerTitle.contains('polish') ||
        lowerTitle.contains('juice') ||
        lowerTitle.contains('vfx') ||
        lowerTitle.contains('sfx') ||
        lowerTitle.contains('audio')) {
      return PhaseCategory.polish;
    } else if (lowerTitle.contains('mechanic') ||
        lowerTitle.contains('production') ||
        lowerTitle.contains('combat') ||
        lowerTitle.contains('system')) {
      return PhaseCategory.coreSystems;
    } else if (lowerTitle.contains('content') ||
        lowerTitle.contains('world') ||
        lowerTitle.contains('level') ||
        lowerTitle.contains('quest') ||
        lowerTitle.contains('map')) {
      return PhaseCategory.content;
    } else if (lowerTitle.contains('playtest') ||
        lowerTitle.contains('balance') ||
        lowerTitle.contains('tuning') ||
        lowerTitle.contains('testing') ||
        lowerTitle.contains('telemetry')) {
      return PhaseCategory.testing;
    } else if (lowerTitle.contains('qa') ||
        lowerTitle.contains('optimization') ||
        lowerTitle.contains('optimize') ||
        lowerTitle.contains('bug') ||
        lowerTitle.contains('profile') ||
        lowerTitle.contains('hardening')) {
      return PhaseCategory.optimize;
    } else if (lowerTitle.contains('launch') ||
        lowerTitle.contains('deploy') ||
        lowerTitle.contains('store')) {
      return PhaseCategory.launch;
    } else if (lowerTitle.contains('live') ||
        lowerTitle.contains('ops') ||
        lowerTitle.contains('maintenance') ||
        lowerTitle.contains('patch')) {
      return PhaseCategory.liveOps;
    } else if (lowerTitle.contains('prototype') ||
        lowerTitle.contains('pre-production') ||
        lowerTitle.contains('r&d') ||
        lowerTitle.contains('concept') ||
        lowerTitle.contains('graybox') ||
        lowerTitle.contains('greybox') ||
        lowerTitle.contains('sandbox') ||
        lowerTitle.contains('locomotion')) {
      return PhaseCategory.prototyping;
    }
    return PhaseCategory.prototyping;
  }
}

/// The 4 official Release Types / Completeness passes for Releases and Features.
enum MilestonePass {
  prototype(
    'Prototype',
    '10-minute crude greybox run proving moment-to-moment gameplay feel',
    Color(0xFF38BDF8),
    '1. PROTOTYPE',
  ),
  mvp(
    'MVP',
    'End-to-end game loop connected with basic systems (HUD, health, win/loss)',
    Color(0xFFFB923C),
    '2. MVP',
  ),
  verticalSlice(
    'Vertical Slice',
    '1 flagship level at 100% production art, lighting, spatial audio, and locked 60 FPS',
    Color(0xFF818CF8),
    '3. VERTICAL SLICE',
  ),
  fullProduction(
    'Full Production',
    'Full campaign across all levels, narrative arc, bosses, zero-crash hardening',
    Color(0xFF10B981),
    '4. FULL PRODUCTION',
  );

  static const MilestonePass rough = MilestonePass.prototype;
  static const MilestonePass build = MilestonePass.mvp;
  static const MilestonePass finalPass = MilestonePass.fullProduction;

  final String label;
  final String description;
  final Color color;
  final String badgeText;

  const MilestonePass(this.label, this.description, this.color, this.badgeText);

  MilestonePass get nextPass {
    switch (this) {
      case MilestonePass.prototype:
        return MilestonePass.mvp;
      case MilestonePass.mvp:
        return MilestonePass.verticalSlice;
      case MilestonePass.verticalSlice:
      case MilestonePass.fullProduction:
        return MilestonePass.fullProduction;
    }
  }

  bool get hasNext => this != MilestonePass.fullProduction;

  int get indexOrder {
    switch (this) {
      case MilestonePass.prototype:
        return 1;
      case MilestonePass.mvp:
        return 2;
      case MilestonePass.verticalSlice:
        return 3;
      case MilestonePass.fullProduction:
        return 4;
    }
  }

  static MilestonePass fromString(String? val) {
    if (val == null) return MilestonePass.prototype;
    final lower = val.toLowerCase().trim();
    if (lower.contains('production') || lower.contains('final')) return MilestonePass.fullProduction;
    if (lower.contains('vertical') || lower.contains('slice')) return MilestonePass.verticalSlice;
    if (lower.contains('mvp') || lower.contains('build') || lower.contains('core')) return MilestonePass.mvp;
    if (lower.contains('proto') || lower.contains('rough')) return MilestonePass.prototype;
    return MilestonePass.prototype;
  }
}

enum ReleaseScope {
  featurePrototype(
    'Prototype',
    '',
    'A fast prototype to test if a single mechanic or feature is fun and feasible.',
    2,
    Color(0xFF71717A), // Monochromatic Neutral
    category: 'rd',
    appDescription:
        'A rapid spike to validate a single technical approach or interaction pattern.',
  ),
  firstPlayable(
    'Proof of Concept',
    '',
    'A rapid concept prototype proving the core game idea works as a playable whole.',
    4,
    Color(0xFF71717A), // Monochromatic Neutral
    category: 'preLaunch',
    appDescription:
        'A rapid concept prototype proving the core product idea works as a usable whole.',
  ),
  mvp(
    'MVP',
    '',
    'The bare-minimum playable build to test the complete game loop from start to finish.',
    4,
    Color(0xFF71717A), // Monochromatic Neutral
    category: 'preLaunch',
    appDescription:
        'The minimum viable product delivering the end-to-end core user workflow.',
  ),
  verticalSlice(
    'Vertical Slice',
    '',
    'A 10–15 minute showcase level built to near-final visual, audio, and feel quality to prove the finished quality bar.',
    4,
    Color(0xFF71717A), // Monochromatic Neutral
    category: 'preLaunch',
    appDescription:
        'A complete end-to-end slice of one full feature module built to production-grade quality and polish.',
  ),
  fullProduction(
    'Full Production',
    '',
    'Building out all content, levels, systems, and polish for the complete game release.',
    6,
    Color(0xFF71717A), // Monochromatic Neutral
    category: 'preLaunch',
    appDescription:
        'Complete product engineering, backend integrations, security, edge cases, and launch readiness.',
  ),
  patch(
    'Patch / Maintenance',
    '',
    'A targeted fix release addressing bugs, balance issues, and stability improvements for a live product.',
    2,
    Color(0xFF71717A), // Monochromatic Neutral
    category: 'postLaunch',
    appDescription:
        'A targeted fix release addressing bugs, performance regressions, and stability issues.',
  ),
  contentUpdate(
    'Feature & Content Update',
    '',
    'A post-launch content drop adding new features, levels, mechanics, and systems to an already-shipped game.',
    4,
    Color(0xFF71717A), // Monochromatic Neutral
    category: 'postLaunch',
    appDescription:
        'A post-launch update delivering new features, workflows, integrations, and enhancements.',
  );

  static const ReleaseScope prototype = ReleaseScope.featurePrototype;
  static const ReleaseScope proofOfConcept = ReleaseScope.firstPlayable;

  final String label;
  final String icon;
  final String description;
  final String? appDescription;
  final int phaseCount;
  final Color color;
  final String category;

  const ReleaseScope(
    this.label,
    this.icon,
    this.description,
    this.phaseCount,
    this.color, {
    this.appDescription,
    required this.category,
  });

  static const Map<String, List<ReleaseScope>> groupedValues = {
    'rd': [ReleaseScope.featurePrototype],
    'preLaunch': [
      ReleaseScope.firstPlayable,
      ReleaseScope.mvp,
      ReleaseScope.verticalSlice,
      ReleaseScope.fullProduction,
    ],
    'postLaunch': [
      ReleaseScope.patch,
      ReleaseScope.contentUpdate,
    ],
  };

  static String categoryLabel(String cat) {
    switch (cat) {
      case 'rd':
        return 'Prototypes (R&D)';
      case 'preLaunch':
        return 'Core Production (MVP & Milestones)';
      case 'postLaunch':
        return 'Live Ops & Maintenance';
      default:
        return cat;
    }
  }

  String descriptionFor(ProjectDomain domain) {
    if (domain == ProjectDomain.appDev && appDescription != null) {
      return appDescription!;
    }
    return description;
  }

  ReleaseScopePreset get preset => standardReleasePresets.firstWhere(
        (p) =>
            p.id == 'preset_$name' ||
            p.title.toLowerCase() == label.toLowerCase() ||
            (this == ReleaseScope.featurePrototype && p.id == 'preset_prototype') ||
            (this == ReleaseScope.fullProduction && p.id == 'preset_standard'),
        orElse: () => standardReleasePresets.first,
      );

  static ReleaseScope fromDocument(dynamic doc) {
    if (doc == null) return ReleaseScope.fullProduction;
    final Map<String, dynamic> sections = doc.sections is Map<String, dynamic>
        ? (doc.sections as Map<String, dynamic>)
        : {};
    final String title = doc.title is String ? (doc.title as String) : '';

    // 1. Explicit milestonePass section takes top priority
    final milestonePass = sections['milestonePass'];
    if (milestonePass != null && milestonePass.toString().trim().isNotEmpty) {
      final s = _matchEnum(milestonePass.toString());
      if (s != null) return s;
    }

    // 2. Explicit preset section
    final preset = sections['preset'];
    if (preset != null && preset.toString().trim().isNotEmpty) {
      final s = _matchEnum(preset.toString());
      if (s != null) return s;
    }

    // 3. 'scope' or legacy 'work' section check - strictly exact match only (prevent long S.I.P. false match)
    final legacyScope = sections['scope'] ?? sections['work'];
    if (legacyScope != null && legacyScope.toString().trim().isNotEmpty) {
      final s = _matchEnum(legacyScope.toString());
      if (s != null) return s;
    }

    // 4. Fallback to keywords in title
    return _fromTitle(title);
  }

  static ReleaseScope? _matchEnum(String val) {
    final clean = val.trim().toLowerCase();
    if (clean == 'prototype' ||
        clean == 'preset_prototype' ||
        clean == 'featureprototype' ||
        clean == 'rough') {
      return ReleaseScope.featurePrototype;
    }
    if (clean == 'mvp' || clean == 'preset_mvp' || clean == 'build') {
      return ReleaseScope.mvp;
    }
    if (clean == 'verticalslice' ||
        clean == 'vertical_slice' ||
        clean == 'vertical slice' ||
        clean == 'preset_verticalslice') {
      return ReleaseScope.verticalSlice;
    }
    if (clean == 'fullproduction' ||
        clean == 'full_production' ||
        clean == 'full production' ||
        clean == 'standard' ||
        clean == 'preset_standard' ||
        clean == 'final' ||
        clean == 'finalpass') {
      return ReleaseScope.fullProduction;
    }
    for (final s in ReleaseScope.values) {
      if (clean == s.name.toLowerCase() ||
          clean == s.label.toLowerCase() ||
          clean == 'preset_${s.name.toLowerCase()}') {
        return s;
      }
    }
    return null;
  }

  static ReleaseScope _fromTitle(String title) {
    final lowerTitle = title.toLowerCase();
    if (lowerTitle.contains('patch') ||
        lowerTitle.contains('hotfix') ||
        lowerTitle.contains('maintenance') ||
        lowerTitle.contains('bugfix')) {
      return ReleaseScope.patch;
    } else if (lowerTitle.contains('content update') ||
        lowerTitle.contains('dlc') ||
        lowerTitle.contains('expansion') ||
        lowerTitle.contains('update')) {
      return ReleaseScope.contentUpdate;
    } else if (lowerTitle.contains('proof of concept') ||
        lowerTitle.contains('poc') ||
        lowerTitle.contains('first playable') ||
        lowerTitle.contains('concept')) {
      return ReleaseScope.firstPlayable;
    } else if (lowerTitle.contains('prototype') ||
        lowerTitle.contains('graybox') ||
        lowerTitle.contains('greybox') ||
        lowerTitle.contains('r&d')) {
      return ReleaseScope.featurePrototype;
    } else if (lowerTitle.contains('vertical slice') ||
        lowerTitle.contains('demo') ||
        lowerTitle.contains('slice') ||
        lowerTitle.contains('showcase')) {
      return ReleaseScope.verticalSlice;
    } else if (lowerTitle.contains('mvp') ||
        lowerTitle.contains('alpha') ||
        lowerTitle.contains('early access') ||
        lowerTitle.contains('0.1')) {
      return ReleaseScope.mvp;
    }
    return ReleaseScope.fullProduction;
  }

  static ReleaseScope fromString(String? val, {String title = ''}) {
    if (val != null && val.isNotEmpty) {
      final s = _matchEnum(val);
      if (s != null) return s;
      final clean = val.toLowerCase().trim();
      if (clean == 'prototype') return ReleaseScope.featurePrototype;
      if (clean == 'standard') return ReleaseScope.fullProduction;
      if (clean.length < 40) {
        for (final item in ReleaseScope.values) {
          if (clean.contains(item.name.toLowerCase()) ||
              clean.contains(item.label.toLowerCase())) {
            return item;
          }
        }
      }
    }
    return _fromTitle(title);
  }
}

class ReleaseScopePreset {
  final String id;
  final String title;
  final String icon;
  final String description;
  final String? appDescription;
  final List<String> phaseTemplateIds;

  const ReleaseScopePreset({
    required this.id,
    required this.title,
    required this.icon,
    required this.description,
    this.appDescription,
    required this.phaseTemplateIds,
  });

  String descriptionFor(ProjectDomain domain) {
    if (domain == ProjectDomain.appDev && appDescription != null) {
      return appDescription!;
    }
    return description;
  }
}

/// The high-level creative and engineering domain for a project.
enum ProjectDomain {
  gameDev(
    'Game Development',
    '🎮',
    'Game development with real-time mechanics, game feel, physics, audio, and playable loops.',
  ),
  appDev(
    'Software & Application Development',
    '💻',
    'Software, web, mobile, and cloud development with UI states, APIs, data structures, and workflows.',
  );

  final String label;
  final String icon;
  final String description;

  const ProjectDomain(this.label, this.icon, this.description);

  static ProjectDomain fromString(String? val) {
    if (val == null) return ProjectDomain.gameDev;
    final lower = val.trim().toLowerCase();
    if (lower == 'appdev' ||
        lower == 'app' ||
        lower == 'software' ||
        lower == 'web' ||
        lower == 'saas' ||
        lower == 'backend' ||
        lower.contains('application') ||
        lower.contains('software')) {
      return ProjectDomain.appDev;
    }
    return ProjectDomain.gameDev;
  }

  static ProjectDomain fromDocument(dynamic doc) {
    if (doc == null) return ProjectDomain.gameDev;
    final Map<String, dynamic> sections = doc.sections is Map<String, dynamic>
        ? (doc.sections as Map<String, dynamic>)
        : {};
    final String title = doc.title is String ? (doc.title as String) : '';

    // 1. Explicit domain section takes top priority
    final domainSec = sections['domain'];
    if (domainSec != null && domainSec.toString().trim().isNotEmpty) {
      return fromString(domainSec.toString());
    }

    // 2. Keyword detection in title / pitch / meta
    final pitch = sections['pitch']?.toString().toLowerCase() ?? '';
    final meta = sections['meta']?.toString().toLowerCase() ?? '';
    final lowerTitle = title.toLowerCase();
    final combined = '$lowerTitle $pitch $meta';

    if (combined.contains('saas') ||
        combined.contains('mobile app') ||
        combined.contains('web app') ||
        combined.contains('flutter app') ||
        combined.contains('react') ||
        combined.contains('backend api') ||
        combined.contains('crm') ||
        combined.contains('dashboard') ||
        combined.contains('microservice') ||
        combined.contains('cloud platform')) {
      if (!combined.contains('gameplay') &&
          !combined.contains('combat') &&
          !combined.contains('player movement') &&
          !combined.contains('video game')) {
        return ProjectDomain.appDev;
      }
    }

    return ProjectDomain.gameDev;
  }
}

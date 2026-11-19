import 'package:flutter/material.dart';

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
        TierType.feature => Icons.extension_outlined,
      };

  String get descriptionTooltip => switch (this) {
        TierType.project => 'Project: Root Godot 4 PROJECT_SPEC.md workspace',
        TierType.release => 'Release: Target playable milestone (v0.1, v0.2+)',
        TierType.epic =>
          'Epic: Large game domain owning shared scenes, scripts, and state rules',
        TierType.feature =>
          'Feature: Sittable 30-90 min playable slice with tuning and Playtest Gate',
      };

  Color colorFor(bool isDark) => switch (this) {
        TierType.project =>
          isDark ? const Color(0xFFF9FAFB) : const Color(0xFF0F172A),
        TierType.release =>
          isDark ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B),
        TierType.epic =>
          isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
        TierType.feature =>
          isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
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
    if (lower == 'feature' || lower == 'feat') return TierType.feature;
    return TierType.values.firstWhere(
      (e) => e.name.toLowerCase() == lower,
      orElse: () => TierType.project,
    );
  }
}

enum ReleaseScope {
  featurePrototype(
    'Prototype',
    '',
    'A fast prototype to test if the core gameplay loop is fun and responsive in Godot Playtest.',
    2,
    Color(0xFF71717A),
    category: 'rd',
    appDescription:
        'A rapid greybox spike proving core controls and physics feel cleanly.',
  ),
  firstPlayable(
    'Proof of Concept',
    '',
    'A rapid concept prototype proving the core game idea works as a playable whole.',
    4,
    Color(0xFF71717A),
    category: 'preLaunch',
    appDescription:
        'A rapid concept prototype proving the core product idea works as a usable whole.',
  ),
  mvp(
    'MVP',
    '',
    'The bare-minimum playable build to test the complete game loop from start to finish.',
    4,
    Color(0xFF71717A),
    category: 'preLaunch',
    appDescription:
        'The minimum viable product delivering the end-to-end core user workflow.',
  ),
  verticalSlice(
    'Vertical Slice',
    '',
    'A 10-15 minute showcase level built to near-final visual, audio, and feel quality.',
    4,
    Color(0xFF71717A),
    category: 'preLaunch',
    appDescription:
        'A complete end-to-end slice of one full feature module built to production-grade polish.',
  ),
  fullProduction(
    'Full Production',
    '',
    'Building out all content, levels, systems, and polish for the complete game release.',
    6,
    Color(0xFF71717A),
    category: 'preLaunch',
    appDescription:
        'Complete product engineering, polish, and launch readiness.',
  ),
  patch(
    'Patch / Maintenance',
    '',
    'A targeted fix release addressing bugs, balance issues, and stability improvements.',
    2,
    Color(0xFF71717A),
    category: 'postLaunch',
    appDescription:
        'A targeted fix release addressing bugs, performance regressions, and stability issues.',
  ),
  contentUpdate(
    'Feature & Content Update',
    '',
    'A post-launch content drop adding new features, levels, mechanics, and systems.',
    4,
    Color(0xFF71717A),
    category: 'postLaunch',
    appDescription:
        'A post-launch update delivering new features, workflows, and enhancements.',
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

  static String categoryLabel(String cat) => switch (cat) {
        'rd' => 'Prototypes (R&D)',
        'preLaunch' => 'Core Production (MVP & Milestones)',
        'postLaunch' => 'Live Ops & Maintenance',
        _ => cat,
      };

  static final Map<String, ReleaseScope> _scopeLookup = _buildScopeLookup();

  static Map<String, ReleaseScope> _buildScopeLookup() {
    final map = <String, ReleaseScope>{
      'prototype': ReleaseScope.featurePrototype,
      'preset_prototype': ReleaseScope.featurePrototype,
      'featureprototype': ReleaseScope.featurePrototype,
      'rough': ReleaseScope.featurePrototype,
      'mvp': ReleaseScope.mvp,
      'preset_mvp': ReleaseScope.mvp,
      'build': ReleaseScope.mvp,
      'verticalslice': ReleaseScope.verticalSlice,
      'vertical_slice': ReleaseScope.verticalSlice,
      'vertical slice': ReleaseScope.verticalSlice,
      'preset_verticalslice': ReleaseScope.verticalSlice,
      'fullproduction': ReleaseScope.fullProduction,
      'full_production': ReleaseScope.fullProduction,
      'full production': ReleaseScope.fullProduction,
      'standard': ReleaseScope.fullProduction,
      'preset_standard': ReleaseScope.fullProduction,
      'final': ReleaseScope.fullProduction,
      'finalpass': ReleaseScope.fullProduction,
      'patch': ReleaseScope.patch,
      'hotfix': ReleaseScope.patch,
      'maintenance': ReleaseScope.patch,
      'bugfix': ReleaseScope.patch,
      'contentupdate': ReleaseScope.contentUpdate,
      'content_update': ReleaseScope.contentUpdate,
      'content update': ReleaseScope.contentUpdate,
      'poc': ReleaseScope.firstPlayable,
      'proof of concept': ReleaseScope.firstPlayable,
      'proofofconcept': ReleaseScope.firstPlayable,
      'first playable': ReleaseScope.firstPlayable,
      'firstplayable': ReleaseScope.firstPlayable,
    };
    for (final s in ReleaseScope.values) {
      map[s.name.toLowerCase()] = s;
      map[s.label.toLowerCase()] = s;
      map['preset_${s.name.toLowerCase()}'] = s;
    }
    return map;
  }

  static ReleaseScope fromDocument(dynamic doc) {
    if (doc == null) return ReleaseScope.fullProduction;
    final Map<dynamic, dynamic> sections =
        doc.sections is Map ? (doc.sections as Map) : const {};
    final String title = doc.title is String ? (doc.title as String) : '';

    final releaseScopeVal = sections['releaseScope'] ?? sections['milestonePass'];
    if (releaseScopeVal != null &&
        releaseScopeVal.toString().trim().isNotEmpty) {
      final s = _matchEnum(releaseScopeVal.toString());
      if (s != null) return s;
    }

    final preset = sections['preset'];
    if (preset != null && preset.toString().trim().isNotEmpty) {
      final s = _matchEnum(preset.toString());
      if (s != null) return s;
    }

    final legacyScope = sections['scope'] ?? sections['work'];
    if (legacyScope != null && legacyScope.toString().trim().isNotEmpty) {
      final s = _matchEnum(legacyScope.toString());
      if (s != null) return s;
    }

    return _fromTitle(title);
  }

  static ReleaseScope? _matchEnum(String val) =>
      _scopeLookup[val.trim().toLowerCase()];

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
        lowerTitle.contains('r&d') ||
        (lowerTitle.contains('0.1') && !lowerTitle.contains('mvp'))) {
      return ReleaseScope.featurePrototype;
    } else if (lowerTitle.contains('vertical slice') ||
        lowerTitle.contains('demo') ||
        lowerTitle.contains('slice') ||
        lowerTitle.contains('showcase')) {
      return ReleaseScope.verticalSlice;
    } else if (lowerTitle.contains('mvp') ||
        lowerTitle.contains('alpha') ||
        lowerTitle.contains('early access')) {
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

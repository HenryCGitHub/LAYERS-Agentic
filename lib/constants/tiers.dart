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

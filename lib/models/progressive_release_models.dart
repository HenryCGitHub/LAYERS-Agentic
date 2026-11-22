import '../utils/unreal_spec_guard.dart';
import 'epic_spec.dart';

class EpicUpgradeOption {
  String id;
  String text;
  String? targetFeatureCode;
  bool chosen;

  EpicUpgradeOption({
    required this.id,
    required this.text,
    this.targetFeatureCode,
    this.chosen = false,
  });

  EpicUpgradeOption copyWith({
    String? id,
    String? text,
    String? targetFeatureCode,
    bool? chosen,
  }) {
    return EpicUpgradeOption(
      id: id ?? this.id,
      text: text ?? this.text,
      targetFeatureCode: targetFeatureCode ?? this.targetFeatureCode,
      chosen: chosen ?? this.chosen,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'text': text,
        if (targetFeatureCode != null && targetFeatureCode!.trim().isNotEmpty)
          'targetFeatureCode': targetFeatureCode,
        'chosen': chosen,
      };

  factory EpicUpgradeOption.fromJson(Map<String, dynamic> json, [int idx = 0]) {
    final rawTarget = (json['targetFeatureCode'] ?? '').toString().trim();
    return EpicUpgradeOption(
      id: (json['id'] ?? 'up_${idx + 1}').toString(),
      text: (json['text'] ?? '').toString().trim(),
      targetFeatureCode: rawTarget.isEmpty ? null : rawTarget,
      chosen: json['chosen'] == true,
    );
  }
}

class ReleaseDirectionPreset {
  final String id;
  final String label;
  final String description;
  final List<String> upgradeIds;
  final List<String> newEpicIds;

  const ReleaseDirectionPreset({
    required this.id,
    required this.label,
    required this.description,
    required this.upgradeIds,
    required this.newEpicIds,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'label': label,
        'desc': description,
        'upgrades': upgradeIds,
        'newEpics': newEpicIds,
      };

  factory ReleaseDirectionPreset.fromJson(Map<String, dynamic> json) {
    final mergedUpgradeAndNewFeatureIds = <String>{
      ...parseStringList(json['upgrades']),
      ...parseStringList(json['newFeatures']),
    }.toList();
    return ReleaseDirectionPreset(
      id: (json['id'] ?? 'preset').toString(),
      label: (json['label'] ?? 'Release Direction').toString(),
      description: (json['desc'] ?? json['description'] ?? '').toString(),
      upgradeIds: mergedUpgradeAndNewFeatureIds,
      newEpicIds: parseStringList(json['newEpics']),
    );
  }
}

class ProgressiveReleaseDraft {
  final String targetVersion;
  List<ReleaseDirectionPreset> presets;
  Map<String, List<EpicUpgradeOption>> upgradesByLineageKey;
  Map<String, List<FeatureSpec>> candidateNewFeaturesByLineageKey;
  Set<String> chosenNewFeatureIds;
  List<EpicSpec> candidateNewEpics;
  String? activePresetId;

  ProgressiveReleaseDraft({
    required this.targetVersion,
    required this.presets,
    required this.upgradesByLineageKey,
    Map<String, List<FeatureSpec>>? candidateNewFeaturesByLineageKey,
    Set<String>? chosenNewFeatureIds,
    required this.candidateNewEpics,
    this.activePresetId,
  })  : candidateNewFeaturesByLineageKey =
            candidateNewFeaturesByLineageKey ?? <String, List<FeatureSpec>>{},
        chosenNewFeatureIds = chosenNewFeatureIds ??
            <String>{
              for (final list
                  in (candidateNewFeaturesByLineageKey ?? const {}).values)
                for (final f in list) f.id,
            };

  bool get hasSelectedChanges {
    for (final opts in upgradesByLineageKey.values) {
      if (opts.any((u) => u.chosen)) return true;
    }
    for (final feats in candidateNewFeaturesByLineageKey.values) {
      if (feats.any((f) => chosenNewFeatureIds.contains(f.id))) return true;
    }
    return candidateNewEpics.any((ep) => ep.chosenForNextRelease);
  }

  ProgressiveReleaseDraft deepCopy() {
    return ProgressiveReleaseDraft(
      targetVersion: targetVersion,
      presets: List<ReleaseDirectionPreset>.from(presets),
      upgradesByLineageKey: {
        for (final e in upgradesByLineageKey.entries)
          e.key: [for (final u in e.value) u.copyWith()],
      },
      candidateNewFeaturesByLineageKey: {
        for (final e in candidateNewFeaturesByLineageKey.entries)
          e.key: [for (final f in e.value) f.deepCopy()],
      },
      chosenNewFeatureIds: Set<String>.from(chosenNewFeatureIds),
      candidateNewEpics: [
        for (final ep in candidateNewEpics) ep.deepCopy(),
      ],
      activePresetId: activePresetId,
    );
  }
}

List<String> parseStringList(dynamic raw) {
  if (raw is! List) return <String>[];
  return raw
      .map((e) => e.toString().trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

List<int> parseReleaseParts(String version) {
  final clean = version.trim().toLowerCase().replaceFirst(RegExp(r'^v'), '');
  if (clean.isEmpty) return const <int>[0, 0];
  return [
    for (final seg in clean.split('.'))
      int.tryParse(RegExp(r'^\d+').firstMatch(seg)?.group(0) ?? '') ?? 0,
  ];
}

int compareReleaseVersions(
  String a,
  String b,
  List<String> releaseOrder,
) {
  final normA = a.trim().toLowerCase();
  final normB = b.trim().toLowerCase();
  if (releaseOrder.isNotEmpty) {
    final normalizedOrder =
        releaseOrder.map((r) => r.trim().toLowerCase()).toList();
    final idxA = normalizedOrder.indexOf(normA);
    final idxB = normalizedOrder.indexOf(normB);
    if (idxA != -1 && idxB != -1) {
      return idxA.compareTo(idxB);
    }
  }
  final pa = parseReleaseParts(normA);
  final pb = parseReleaseParts(normB);
  final maxLen = pa.length > pb.length ? pa.length : pb.length;
  for (int i = 0; i < maxLen; i++) {
    final va = i < pa.length ? pa[i] : 0;
    final vb = i < pb.length ? pb[i] : 0;
    if (va != vb) return va.compareTo(vb);
  }
  return 0;
}

List<EpicSceneOwnership> extractLegacySceneOwnership(
  List<String> links,
  String levelStaging,
) {
  final uePathPattern = RegExp(r'/Game/[^\s,)\];"]+');
  final seen = <String>{};
  final result = <EpicSceneOwnership>[];

  void scanText(String source, String fallbackRole) {
    final trimmed = source.trim();
    if (trimmed.isEmpty) return;
    final sanitized = UnrealSpecGuard.sanitizeLine(trimmed);
    for (final m in uePathPattern.allMatches(sanitized)) {
      final path = m.group(0)!.trim();
      if (path.isEmpty || !seen.add(path)) continue;
      String role = fallbackRole;
      final split = sanitized.split(RegExp(r'\s+[—-]\s+'));
      if (split.length > 1 && split.first.contains(path)) {
        role = split.sublist(1).join(' - ').trim();
      }
      result.add(EpicSceneOwnership(path: path, role: role));
    }
  }

  for (final link in links) {
    scanText(link, 'Shared scene or script');
  }
  scanText(levelStaging, 'Playtest room scene');
  return result;
}

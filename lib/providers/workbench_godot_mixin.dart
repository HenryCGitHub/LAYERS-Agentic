part of 'workbench_provider.dart';

/// Snapshot of the single Epic currently active in the native Godot 4 LAYERS Dock.
class ActiveGodotEpicSnapshot {
  final String releaseVersion;
  final String? activeEpicId;
  final String activeEpicCode;
  final String activeEpicTitle;
  final String activeEpicGoal;
  final int epicPosition;
  final int totalEpics;
  final int completedFeaturesInActiveEpic;
  final int totalFeaturesInActiveEpic;
  final bool allEpicsCompleted;

  const ActiveGodotEpicSnapshot({
    required this.releaseVersion,
    required this.activeEpicId,
    required this.activeEpicCode,
    required this.activeEpicTitle,
    required this.activeEpicGoal,
    required this.epicPosition,
    required this.totalEpics,
    required this.completedFeaturesInActiveEpic,
    required this.totalFeaturesInActiveEpic,
    required this.allEpicsCompleted,
  });
}

/// Godot 4 Active Epic Cloud Sync snapshot & Dock Link Token helper (`v3.0` Pure Spec & Playtest Dock).
extension WorkbenchGodotMixin on WorkbenchProvider {
  /// Resolves the single active Epic shown inside the Godot 4 Dock (`E01` -> `E02` -> ...),
  /// matching `/godotLink/epic` Cloud Sync progression rules.
  ActiveGodotEpicSnapshot computeActiveGodotEpicSnapshot() {
    final activeVer = activeReleaseVersionTag;
    final beats = activeReleaseBeats;
    if (beats.isEmpty) {
      return ActiveGodotEpicSnapshot(
        releaseVersion: activeVer,
        activeEpicId: null,
        activeEpicCode: '',
        activeEpicTitle: '',
        activeEpicGoal: '',
        epicPosition: 0,
        totalEpics: 0,
        completedFeaturesInActiveEpic: 0,
        totalFeaturesInActiveEpic: 0,
        allEpicsCompleted: false,
      );
    }

    bool isFeatureFinishedForGodot(TierDocument feat) {
      if (!isFeatureActiveInRelease(feat, activeVer)) return true;
      final states = FeatureStateNode.getStatesForDocument(feat);
      if (states.isEmpty) return feat.isCompleted;
      FeatureStateNode? cp;
      final matching = states.where((s) => s.releaseVersion == activeVer).toList();
      if (matching.isNotEmpty) {
        cp = matching.last;
      } else {
        for (final s in states) {
          if (!s.isCompleted || !s.isPlaytestPassed) {
            cp = s;
            break;
          }
        }
        cp ??= states.last;
      }
      return cp.isPlaytestPassed;
    }

    final releaseHasActiveFeats = beats.any(
      (b) => featuresForBeat(b.id).any(
        (f) => isFeatureActiveInRelease(f, activeVer),
      ),
    );

    final candidates = <({
      TierDocument beat,
      int originalIndex,
      int doneCount,
      int totalCount,
    })>[];

    for (int i = 0; i < beats.length; i++) {
      final beat = beats[i];
      final allFeats = featuresForBeat(beat.id);
      final scopedFeats = releaseHasActiveFeats
          ? allFeats.where((f) => isFeatureActiveInRelease(f, activeVer)).toList()
          : allFeats;
      if (releaseHasActiveFeats && allFeats.isNotEmpty && scopedFeats.isEmpty) {
        continue;
      }
      final doneCount = scopedFeats.where(isFeatureFinishedForGodot).length;
      candidates.add((
        beat: beat,
        originalIndex: i,
        doneCount: doneCount,
        totalCount: scopedFeats.length,
      ));
    }

    if (candidates.isEmpty) {
      return ActiveGodotEpicSnapshot(
        releaseVersion: activeVer,
        activeEpicId: null,
        activeEpicCode: '',
        activeEpicTitle: '',
        activeEpicGoal: '',
        epicPosition: 0,
        totalEpics: 0,
        completedFeaturesInActiveEpic: 0,
        totalFeaturesInActiveEpic: 0,
        allEpicsCompleted: false,
      );
    }

    final hasAnyPopulated = candidates.any((c) => c.totalCount > 0);
    for (int idx = 0; idx < candidates.length; idx++) {
      final c = candidates[idx];
      final shouldPick = hasAnyPopulated
          ? (c.totalCount > 0 && c.doneCount < c.totalCount)
          : idx == 0;
      if (shouldPick) {
        final code = 'E${(c.originalIndex + 1).toString().padLeft(2, '0')}';
        return ActiveGodotEpicSnapshot(
          releaseVersion: activeVer,
          activeEpicId: c.beat.id,
          activeEpicCode: code,
          activeEpicTitle: c.beat.title,
          activeEpicGoal: SectionTextUtils.resolveGoal(c.beat.sections),
          epicPosition: idx + 1,
          totalEpics: candidates.length,
          completedFeaturesInActiveEpic: c.doneCount,
          totalFeaturesInActiveEpic: c.totalCount,
          allEpicsCompleted: false,
        );
      }
    }

    final last = candidates.last;
    return ActiveGodotEpicSnapshot(
      releaseVersion: activeVer,
      activeEpicId: null,
      activeEpicCode: 'E${(last.originalIndex + 1).toString().padLeft(2, '0')}',
      activeEpicTitle: last.beat.title,
      activeEpicGoal: SectionTextUtils.resolveGoal(last.beat.sections),
      epicPosition: candidates.length,
      totalEpics: candidates.length,
      completedFeaturesInActiveEpic: last.doneCount,
      totalFeaturesInActiveEpic: last.totalCount,
      allEpicsCompleted: true,
    );
  }

  /// Generates, fetches, or rotates a per-project Cloud Link Token (`lyr_...`) for the Godot 4 Dock.
  Future<({String? token, String? error})> fetchOrCreateGodotLinkToken({
    bool rotate = false,
  }) async {
    final pid = _activeProjectId;
    if (pid == null || pid.trim().isEmpty) {
      return (token: null, error: 'Create or select a project first.');
    }
    if (!rotate) {
      final cached = _cachedGodotLinkTokensByProjectId[pid];
      if (cached != null && cached.trim().isNotEmpty) {
        return (token: cached, error: null);
      }
    }

    try {
      final resp = await GeminiAgentClient.postAuthenticatedProxyAction(
        routePath: '/godotLink/token',
        payload: <String, dynamic>{
          'projectId': pid,
          'rotate': rotate,
        },
      );
      final token = resp.body['linkToken']?.toString().trim() ?? '';
      if (resp.statusCode == 200 && token.isNotEmpty) {
        _cachedGodotLinkTokensByProjectId[pid] = token;
        notifyListeners();
        return (token: token, error: null);
      }
      final errObj = resp.body['error'];
      final serverMsg =
          (errObj is Map ? errObj['message'] : null)?.toString().trim();
      return (
        token: null,
        error: (serverMsg != null && serverMsg.isNotEmpty)
            ? serverMsg
            : 'Sign in with Google to generate a live Godot Cloud Link Token.',
      );
    } catch (e) {
      return (
        token: null,
        error: 'Unable to fetch Godot Cloud Link Token: $e',
      );
    }
  }

  static String _normalizeResPath(String raw) {
    final cleaned = raw.trim().replaceAll('\\', '/');
    if (cleaned.isEmpty) return '';
    return cleaned.startsWith('res://') ? cleaned : 'res://${cleaned.replaceFirst(RegExp(r'^/+'), '')}';
  }

  /// Extracts the `.gd` script `res://...` path from strings like `"res://scenes/player.tscn · res://scripts/player.gd"`.
  String? extractPrimaryScriptResPath(String? rawAssetString) {
    if (rawAssetString == null || rawAssetString.trim().isEmpty) return null;
    final match = RegExp(r'res://[^\s,|·;"]+\.gd\b').firstMatch(rawAssetString);
    return match != null ? _normalizeResPath(match.group(0)!) : null;
  }

  /// Extracts the `.tscn` scene `res://...` path from a feature's `primary_asset` string.
  String? extractPrimarySceneResPath(String? rawAssetString) {
    if (rawAssetString == null || rawAssetString.trim().isEmpty) return null;
    final match = RegExp(r'res://[^\s,|·;"]+\.tscn\b').firstMatch(rawAssetString);
    return match != null ? _normalizeResPath(match.group(0)!) : null;
  }
}

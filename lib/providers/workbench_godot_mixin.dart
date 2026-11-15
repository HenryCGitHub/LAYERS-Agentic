part of 'workbench_provider.dart';

/// Snapshot of the single Epic currently active in the native Godot 4 LAYERS Dock.
class ActiveGodotEpicSnapshot {
  final String releaseVersion;
  final String? activeEpicId;
  final String activeEpicCode;
  final String activeEpicTitle;
  final String activeEpicGoal;
  final String? activeFeatureId;
  final String activeFeatureTitle;
  final int epicPosition;
  final int totalEpics;
  final int completedFeaturesInActiveEpic;
  final int totalFeaturesInActiveEpic;
  final bool allEpicsCompleted;
  final String releaseGoal;
  final String releaseDoneWhen;

  const ActiveGodotEpicSnapshot({
    required this.releaseVersion,
    required this.activeEpicId,
    required this.activeEpicCode,
    required this.activeEpicTitle,
    required this.activeEpicGoal,
    this.activeFeatureId,
    this.activeFeatureTitle = '',
    required this.epicPosition,
    required this.totalEpics,
    required this.completedFeaturesInActiveEpic,
    required this.totalFeaturesInActiveEpic,
    required this.allEpicsCompleted,
    this.releaseGoal = '',
    this.releaseDoneWhen = '',
  });
}

/// Godot 4 Active Epic Cloud Sync snapshot & Dock Link Token helper (`v3.0` Pure Spec & Playtest Dock).
extension WorkbenchGodotMixin on WorkbenchProvider {
  /// Returns the latest `last_godot_sync_ms` timestamp across the active project's tree, or null if unsynced.
  DateTime? get activeProjectLastGodotSyncAt {
    final pid = _activeProjectId;
    if (pid == null) return null;
    int maxMs = 0;
    for (final id in _collectProjectDocumentTreeIds(pid)) {
      final raw = documents[id]?.sections['last_godot_sync_ms'];
      final ms = int.tryParse(raw ?? '') ?? 0;
      if (ms > maxMs) {
        maxMs = ms;
      }
    }
    return maxMs > 0 ? DateTime.fromMillisecondsSinceEpoch(maxMs) : null;
  }

  /// True once the active project (or any document in its tree) has synced with the Godot 4 Dock.
  bool get isActiveProjectSyncedWithGodot => activeProjectLastGodotSyncAt != null;

  /// Human-readable Godot Cloud Sync status summary for modals and tooltips.
  String formatGodotSyncStatusLabel({DateTime? now}) {
    final syncedAt = activeProjectLastGodotSyncAt;
    if (syncedAt == null) return 'Not synced with Godot yet';
    final diff = (now ?? DateTime.now()).difference(syncedAt);
    if (diff.inSeconds < 60) return 'Synced just now';
    if (diff.inMinutes < 60) return 'Synced ${diff.inMinutes}m ago';
    if (diff.inHours < 24) return 'Synced ${diff.inHours}h ago';
    return 'Synced ${diff.inDays}d ago';
  }

  /// Focuses Web Studio onto the active unfinished Feature shown in the Godot 4 Dock.
  bool focusActiveGodotFeature() {
    final snap = computeActiveGodotEpicSnapshot();
    final targetId = snap.activeFeatureId;
    if (targetId == null || !documents.containsKey(targetId)) {
      return false;
    }
    _currentStage = WorkbenchStage.releaseWorkbench;
    selectFeature(targetId, triggerAiSynthesis: false);
    return true;
  }

  /// Resolves the single active Epic shown inside the Godot 4 Dock (`E01` -> `E02` -> ...),
  /// matching `/godotLink/epic` Cloud Sync progression rules.
  ActiveGodotEpicSnapshot computeActiveGodotEpicSnapshot() {
    final activeVer = activeReleaseVersionTag;
    final beats = activeReleaseBeats;
    final activeRel = activeRelease;
    final relBp = activeRel != null ? releaseBlueprintFor(activeRel.id) : null;
    final rawRelGoal = (relBp?.goal.trim().isNotEmpty ?? false)
        ? relBp!.goal.trim()
        : SectionTextUtils.resolveGoal(activeRel?.sections ?? const {});
    final relGoal = rawRelGoal
        .replaceFirst(RegExp(r'^Goal:\s*', caseSensitive: false), '')
        .trim();
    final rawRelDone = (relBp?.doneWhen.trim().isNotEmpty ?? false)
        ? relBp!.doneWhen.trim()
        : SectionTextUtils.resolveDoneWhen(activeRel?.sections ?? const {});
    final strippedRelDone = rawRelDone
        .replaceFirst(RegExp(r'^End\s*Goal:\s*', caseSensitive: false), '')
        .trim();
    final relDoneWhen = SectionTextUtils.resolveCheckpointDoneWhen(
      playtestGoalParam: strippedRelDone,
      sections: activeProject?.sections ?? const {},
    );
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
        releaseGoal: relGoal,
        releaseDoneWhen: relDoneWhen,
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
      TierDocument? nextFeature,
    })>[];

    final godotFeatId =
        (activeProject?.sections['last_godot_feature_id'] ?? '').trim();
    final webSelFeatId =
        (activeProject?.sections['selected_feature_id'] ?? '').trim();

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
      TierDocument? nextFeat;
      if (godotFeatId.isNotEmpty) {
        for (final f in scopedFeats) {
          if (f.id == godotFeatId && !isFeatureFinishedForGodot(f)) {
            nextFeat = f;
            break;
          }
        }
      } else if (webSelFeatId.isNotEmpty) {
        for (final f in scopedFeats) {
          if (f.id == webSelFeatId && !isFeatureFinishedForGodot(f)) {
            nextFeat = f;
            break;
          }
        }
      }
      if (nextFeat == null) {
        for (final f in scopedFeats) {
          if (!isFeatureFinishedForGodot(f)) {
            nextFeat = f;
            break;
          }
        }
      }
      nextFeat ??= scopedFeats.isNotEmpty ? scopedFeats.first : null;
      candidates.add((
        beat: beat,
        originalIndex: i,
        doneCount: doneCount,
        totalCount: scopedFeats.length,
        nextFeature: nextFeat,
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
        releaseGoal: relGoal,
        releaseDoneWhen: relDoneWhen,
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
          activeFeatureId: c.nextFeature?.id,
          activeFeatureTitle: c.nextFeature?.title ?? '',
          epicPosition: idx + 1,
          totalEpics: candidates.length,
          completedFeaturesInActiveEpic: c.doneCount,
          totalFeaturesInActiveEpic: c.totalCount,
          allEpicsCompleted: false,
          releaseGoal: relGoal,
          releaseDoneWhen: relDoneWhen,
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
      activeFeatureId: last.nextFeature?.id,
      activeFeatureTitle: last.nextFeature?.title ?? '',
      epicPosition: candidates.length,
      totalEpics: candidates.length,
      completedFeaturesInActiveEpic: last.doneCount,
      totalFeaturesInActiveEpic: last.totalCount,
      allEpicsCompleted: true,
      releaseGoal: relGoal,
      releaseDoneWhen: relDoneWhen,
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

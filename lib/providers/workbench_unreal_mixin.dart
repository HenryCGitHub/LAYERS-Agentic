part of 'workbench_provider.dart';

/// Unreal `LayersBridge` Cloud Link Sync, `.uproject` Live Snapshot inspection,
/// and canonical MCP payload compilation helpers.
extension WorkbenchUnrealMixin on WorkbenchProvider {
  DateTime? get activeProjectLastUnrealSyncAt {
    final pid = _activeProjectId;
    if (pid == null) return null;
    int maxMs = 0;
    for (final id in _collectProjectDocumentTreeIds(pid)) {
      final raw = documents[id]?.sections['last_unreal_sync_ms'];
      final ms = int.tryParse(raw ?? '') ?? 0;
      if (ms > maxMs) {
        maxMs = ms;
      }
    }
    return maxMs > 0 ? DateTime.fromMillisecondsSinceEpoch(maxMs) : null;
  }

  bool get isActiveProjectSyncedWithUnreal =>
      activeProjectLastUnrealSyncAt != null;

  String formatUnrealSyncStatusLabel({DateTime? now}) {
    final syncedAt = activeProjectLastUnrealSyncAt;
    if (syncedAt == null) return 'Not synced with Unreal yet';
    final diff = (now ?? DateTime.now()).difference(syncedAt);
    if (diff.inSeconds < 60) return 'Synced just now';
    if (diff.inMinutes < 60) return 'Synced ${diff.inMinutes}m ago';
    if (diff.inHours < 24) return 'Synced ${diff.inHours}h ago';
    return 'Synced ${diff.inDays}d ago';
  }

  Map<String, dynamic>? get latestLiveUprojectContext {
    final raw = activeProject?.sections['unreal_live_context_json'];
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    return null;
  }

  String get activeRootMcpMarkdown {
    final spec = _conceptDraft;
    if (spec == null) return '# ROOT_MCP_CONTEXT\nNo Project Spec drafted yet.';
    return UnrealMcpPayloadBuilder.buildRootMcpContext(
      spec,
      liveUprojectContext: latestLiveUprojectContext,
    );
  }

  String activeEpicMcpPayload(EpicSpec epic) {
    final spec = _conceptDraft ??
        ProjectConceptBlueprint(
          gameTitle: activeProject?.title ?? 'UNREAL PROJECT',
        );
    return UnrealMcpPayloadBuilder.buildEpicMcpPayload(
      rootSpec: spec,
      epic: epic,
      releaseEpics: activeReleaseEpics,
      liveUprojectContext: latestLiveUprojectContext,
    );
  }

  /// Generates, fetches, or rotates a per-project Cloud Link Token (`lyr_...`) for `LayersBridge` in UE5.9/UE6.
  Future<({String? token, String? error})> fetchOrCreateUnrealLinkToken({
    bool rotate = false,
  }) async {
    final pid = _activeProjectId;
    if (pid == null || pid.trim().isEmpty) {
      return (token: null, error: 'Create or select a project first.');
    }
    if (!rotate) {
      final cached = _cachedUnrealLinkTokensByProjectId[pid];
      if (cached != null && cached.trim().isNotEmpty) {
        return (token: cached, error: null);
      }
    }

    try {
      final resp = await GeminiAgentClient.postAuthenticatedProxyAction(
        routePath: '/unrealLink/token',
        payload: <String, dynamic>{
          'projectId': pid,
          'rotate': rotate,
        },
      );
      final token = resp.body['linkToken']?.toString().trim() ?? '';
      if (resp.statusCode == 200 && token.isNotEmpty) {
        _cachedUnrealLinkTokensByProjectId[pid] = token;
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
            : 'Sign in with Google to generate a live Unreal Bridge Token.',
      );
    } catch (e) {
      return (
        token: null,
        error: 'Unable to fetch Unreal Link Token: $e',
      );
    }
  }
}

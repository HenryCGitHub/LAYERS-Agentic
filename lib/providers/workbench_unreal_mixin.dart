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
    String? projectId,
  }) async {
    final pid = (projectId ?? _activeProjectId)?.trim();
    if (pid == null || pid.isEmpty) {
      return (token: null, error: 'Create or select a project first.');
    }
    await flushProjectTreeToCloud(pid);
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

  bool get hasPendingUnrealAuth =>
      _pendingUnrealAuthPort != null &&
      (_pendingUnrealAuthState ?? '').isNotEmpty;

  bool get isUnrealAuthMinimized => _unrealAuthMinimized;
  int? get pendingUnrealAuthPort => _pendingUnrealAuthPort;
  String? get pendingUnrealAuthState => _pendingUnrealAuthState;
  String? get pendingUnrealUprojectName => _pendingUnrealUprojectName;
  bool get isCompletingUnrealAuth => _isCompletingUnrealAuth;
  String? get unrealAuthError => _unrealAuthError;

  /// Picks the best-matching saved LAYERS project for an incoming `.uproject` handoff.
  String? get effectiveUnrealAuthProjectId {
    final projects = savedProjects;
    if (projects.isEmpty) return null;
    if (_unrealAuthSelectedProjectId != null &&
        projects.any((p) => p.id == _unrealAuthSelectedProjectId)) {
      return _unrealAuthSelectedProjectId;
    }
    final rawUproj = _pendingUnrealUprojectName;
    if (rawUproj != null && rawUproj.trim().isNotEmpty) {
      String norm(String s) =>
          s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      final uprojNorm = norm(rawUproj);
      if (uprojNorm.length >= 3) {
        String? tokenMatchId;
        for (final p in projects) {
          final pNorm = norm(p.title);
          if (pNorm.length >= 3 &&
              (uprojNorm.contains(pNorm) || pNorm.contains(uprojNorm))) {
            return p.id;
          }
          if (tokenMatchId == null) {
            final tokens = RegExp(r'[a-z0-9]{3,}')
                .allMatches(p.title.toLowerCase())
                .map((m) => m.group(0)!)
                .where((t) => t != 'the' && t != 'and' && t != 'project');
            if (tokens.any((tok) => uprojNorm.contains(tok))) {
              tokenMatchId = p.id;
            }
          }
        }
        if (tokenMatchId != null) {
          return tokenMatchId;
        }
      }
    }
    if (_activeProjectId != null &&
        projects.any((p) => p.id == _activeProjectId)) {
      return _activeProjectId;
    }
    return projects.first.id;
  }

  void selectUnrealAuthProject(String projectId) {
    _unrealAuthSelectedProjectId = projectId;
    _unrealAuthError = null;
    notifyListeners();
  }

  void setUnrealAuthMinimized(bool minimized) {
    _unrealAuthMinimized = minimized;
    notifyListeners();
  }

  void dismissPendingUnrealAuth() {
    _pendingUnrealAuthPort = null;
    _pendingUnrealAuthState = null;
    _pendingUnrealUprojectName = null;
    _unrealAuthSelectedProjectId = null;
    _unrealAuthMinimized = false;
    _isCompletingUnrealAuth = false;
    _unrealAuthError = null;
    notifyListeners();
  }

  /// Mints/fetches the per-`.uproject` credential for the signed-in Google user and redirects
  /// to the waiting Unreal Editor loopback listener (`127.0.0.1:<port>/callback`).
  Future<({bool ok, String? callbackUrl, String? error})>
      completePendingUnrealAuthHandoff() async {
    if (!hasPendingUnrealAuth) {
      return (
        ok: false,
        callbackUrl: null,
        error: 'No active Unreal authentication handoff.',
      );
    }
    final targetPid = effectiveUnrealAuthProjectId;
    if (targetPid == null || targetPid.isEmpty) {
      _unrealAuthError = 'Create or select a LAYERS project first.';
      notifyListeners();
      return (ok: false, callbackUrl: null, error: _unrealAuthError);
    }

    final port = _pendingUnrealAuthPort!;
    final state = _pendingUnrealAuthState!;
    _isCompletingUnrealAuth = true;
    _unrealAuthError = null;
    notifyListeners();

    if (_activeProjectId != targetPid) {
      switchProject(targetPid);
    }

    final res = await fetchOrCreateUnrealLinkToken(projectId: targetPid);
    final token = res.token?.trim() ?? '';
    if (token.isEmpty) {
      _isCompletingUnrealAuth = false;
      _unrealAuthError =
          res.error ?? 'Failed to provision project sync link.';
      notifyListeners();
      return (ok: false, callbackUrl: null, error: _unrealAuthError);
    }

    final projTitle = (documents[targetPid]?.title ?? 'LAYERS Project').trim();
    final callbackUrl = Uri.http(
      '127.0.0.1:$port',
      '/callback',
      <String, String>{
        'state': state,
        'token': token,
        'project': projTitle,
      },
    ).toString();

    _pendingUnrealAuthPort = null;
    _pendingUnrealAuthState = null;
    _pendingUnrealUprojectName = null;
    _unrealAuthSelectedProjectId = null;
    _unrealAuthMinimized = false;
    _isCompletingUnrealAuth = false;
    _unrealAuthError = null;
    notifyListeners();

    triggerBrowserRedirect(callbackUrl);
    return (ok: true, callbackUrl: callbackUrl, error: null);
  }
}

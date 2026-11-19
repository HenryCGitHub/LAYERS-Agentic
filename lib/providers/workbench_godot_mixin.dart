part of 'workbench_provider.dart';

/// Godot 4 Dock Cloud Link Sync, Live `project.godot` Snapshot inspection,
/// and canonical Godot 4 context compilation helpers.
extension WorkbenchGodotMixin on WorkbenchProvider {
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

  bool get isActiveProjectSyncedWithGodot =>
      activeProjectLastGodotSyncAt != null;

  String formatGodotSyncStatusLabel({DateTime? now}) {
    final syncedAt = activeProjectLastGodotSyncAt;
    if (syncedAt == null) return 'Not synced with Godot 4 yet';
    final diff = (now ?? DateTime.now()).difference(syncedAt);
    if (diff.inSeconds < 60) return 'Synced just now';
    if (diff.inMinutes < 60) return 'Synced ${diff.inMinutes}m ago';
    if (diff.inHours < 24) return 'Synced ${diff.inHours}h ago';
    return 'Synced ${diff.inDays}d ago';
  }

  Map<String, dynamic>? get latestLiveGodotContext {
    final raw = activeProject?.sections['godot_live_context_json'];
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    return null;
  }

  String get activeRootGodotMarkdown {
    final spec = _conceptDraft;
    if (spec == null) {
      return '# ROOT_GODOT_CONTEXT\nNo Project Spec drafted yet.';
    }
    return GodotContextBuilder.buildRootGodotContext(
      spec,
      liveGodotContext: latestLiveGodotContext,
    );
  }

  String activeEpicGodotContext(EpicSpec epic) {
    final spec = _conceptDraft ??
        ProjectConceptBlueprint(
          gameTitle: activeProject?.title ?? 'GODOT PROJECT',
        );
    return GodotContextBuilder.buildEpicGodotContext(
      rootSpec: spec,
      epic: epic,
      releaseEpics: activeReleaseEpics,
      liveGodotContext: latestLiveGodotContext,
    );
  }

  /// Returns the 4-tier Godot 4 sync context for Cloud/Dock callers while keeping
  /// legacy explicit-empty-feature Epics backwards-compatible with [activeEpicGodotContext].
  String activeGodotSyncContext({
    EpicSpec? epicOverride,
    FeatureSpec? featureOverride,
  }) {
    final epic = epicOverride ?? selectedEpicSpec;
    if (epic == null) {
      return activeRootGodotMarkdown;
    }
    final feat = featureOverride ??
        (epicOverride == null ? selectedFeatureSpec : null);
    if (feat != null) {
      return activeFeatureBuildPrompt(epic, feat);
    }
    if (epic.hasFeatures) {
      return activeEpicArchitecturePrompt(epic);
    }
    return activeEpicGodotContext(epic);
  }

  /// Builds filename + Markdown payload for the currently active selection
  /// (`Feature Build Prompt` | `Epic Architecture Brief` | `PROJECT_SPEC.md`).
  ({String filename, String content}) buildActiveSelectionMarkdownExport() {
    final projTitle = _conceptDraft?.normalizedTitle ??
        activeProject?.title ??
        'layers_project';
    final epic = selectedEpicSpec;
    final feat = selectedFeatureSpec;
    if (epic != null && feat != null) {
      return (
        filename: buildFeaturePromptFilename(
          projTitle,
          epic.code,
          feat.code,
          feat.title,
        ),
        content: activeFeatureBuildPrompt(epic, feat),
      );
    }
    if (epic != null) {
      return (
        filename: buildEpicArchitectureFilename(
          projTitle,
          epic.code,
          epic.title,
        ),
        content: activeEpicArchitecturePrompt(epic),
      );
    }
    return (
      filename: buildProjectSpecFilename(projTitle),
      content: activeRootGodotMarkdown,
    );
  }

  /// Builds filename + full structured project Markdown across all releases, Epics, and Features.
  ({String filename, String content}) buildFullProjectMarkdownExport() {
    final rootSpec = _conceptDraft ??
        ProjectConceptBlueprint(
          gameTitle: activeProject?.title ?? 'layers_project',
        );
    final epicsByRelease = <String, List<EpicSpec>>{
      for (final rel in projectReleases)
        releaseDisplayName(rel): epicsForRelease(rel.id),
    };
    return (
      filename: buildProjectSpecFilename(rootSpec.normalizedTitle),
      content: GodotContextBuilder.buildFullProjectSpecMarkdown(
        rootSpec: rootSpec,
        epicsByReleaseLabel: epicsByRelease,
        liveGodotContext: latestLiveGodotContext,
      ),
    );
  }

  /// Builds filename + active release Markdown context bundle (`ROOT_GODOT_CONTEXT` + Release Epics/Features).
  ({String filename, String content}) buildActiveReleaseMarkdownExport() {
    final rootSpec = _conceptDraft ??
        ProjectConceptBlueprint(
          gameTitle: activeProject?.title ?? 'layers_project',
        );
    final rel = activeRelease;
    final releaseLabel =
        rel != null ? releaseDisplayName(rel) : 'v0.1 · Prototype';
    return (
      filename:
          'godot_release_${activeReleaseVersionTag.replaceAll('.', '_')}.md',
      content: GodotContextBuilder.buildReleaseContextBundle(
        rootSpec: rootSpec,
        releaseLabel: releaseLabel,
        releaseEpics: activeReleaseEpics,
        releaseOrder: projectReleaseOrder,
        liveGodotContext: latestLiveGodotContext,
      ),
    );
  }

  /// Generates, fetches, or rotates a per-project Cloud Link Token (`lyr_...`) for the Godot 4 Dock.
  Future<({String? token, String? error})> fetchOrCreateGodotLinkToken({
    bool rotate = false,
    String? projectId,
  }) async {
    final pid = (projectId ?? _activeProjectId)?.trim();
    if (pid == null || pid.isEmpty) {
      return (token: null, error: 'Create or select a project first.');
    }
    await flushProjectTreeToCloud(pid);
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
            : 'Sign in with Google to generate a live Godot 4 Dock Token.',
      );
    } catch (e) {
      return (
        token: null,
        error: 'Unable to fetch Godot Link Token: $e',
      );
    }
  }

  bool get hasPendingGodotAuth =>
      _pendingGodotAuthPort != null &&
      (_pendingGodotAuthState ?? '').isNotEmpty;

  bool get isGodotAuthMinimized => _godotAuthMinimized;
  int? get pendingGodotAuthPort => _pendingGodotAuthPort;
  String? get pendingGodotAuthState => _pendingGodotAuthState;
  String? get pendingGodotProjectName => _pendingGodotProjectName;
  bool get isCompletingGodotAuth => _isCompletingGodotAuth;
  String? get godotAuthError => _godotAuthError;

  /// Picks the best-matching saved LAYERS project for an incoming `project.godot` handoff.
  String? get effectiveGodotAuthProjectId {
    final projects = savedProjects;
    if (projects.isEmpty) return null;
    if (_godotAuthSelectedProjectId != null &&
        projects.any((p) => p.id == _godotAuthSelectedProjectId)) {
      return _godotAuthSelectedProjectId;
    }
    final rawProj = _pendingGodotProjectName;
    if (rawProj != null && rawProj.trim().isNotEmpty) {
      String norm(String s) =>
          s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      final projNorm = norm(rawProj);
      if (projNorm.length >= 3) {
        String? tokenMatchId;
        for (final p in projects) {
          final pNorm = norm(p.title);
          if (pNorm.length >= 3 &&
              (projNorm.contains(pNorm) || pNorm.contains(projNorm))) {
            return p.id;
          }
          if (tokenMatchId == null) {
            final tokens = RegExp(r'[a-z0-9]{3,}')
                .allMatches(p.title.toLowerCase())
                .map((m) => m.group(0)!)
                .where((t) => t != 'the' && t != 'and' && t != 'project');
            if (tokens.any((tok) => projNorm.contains(tok))) {
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

  void selectGodotAuthProject(String projectId) {
    _godotAuthSelectedProjectId = projectId;
    _godotAuthError = null;
    notifyListeners();
  }

  void setGodotAuthMinimized(bool minimized) {
    _godotAuthMinimized = minimized;
    notifyListeners();
  }

  void dismissPendingGodotAuth() {
    _pendingGodotAuthPort = null;
    _pendingGodotAuthState = null;
    _pendingGodotProjectName = null;
    _godotAuthSelectedProjectId = null;
    _godotAuthMinimized = false;
    _isCompletingGodotAuth = false;
    _godotAuthError = null;
    notifyListeners();
  }

  /// Flushes the project tree to Cloud Vault, mints the `lyr_...` token for the signed-in
  /// Google user, and redirects to the Godot Editor TCP loopback listener (`127.0.0.1:<port>/callback`).
  Future<({bool ok, String? callbackUrl, String? error})>
      completePendingGodotAuthHandoff() async {
    if (!hasPendingGodotAuth) {
      return (
        ok: false,
        callbackUrl: null,
        error: 'No active Godot authentication handoff.',
      );
    }
    final targetPid = effectiveGodotAuthProjectId;
    if (targetPid == null || targetPid.isEmpty) {
      _godotAuthError = 'Create or select a LAYERS project first.';
      notifyListeners();
      return (ok: false, callbackUrl: null, error: _godotAuthError);
    }

    final port = _pendingGodotAuthPort!;
    final state = _pendingGodotAuthState!;
    _isCompletingGodotAuth = true;
    _godotAuthError = null;
    notifyListeners();

    if (_activeProjectId != targetPid) {
      switchProject(targetPid);
    }

    final res = await fetchOrCreateGodotLinkToken(projectId: targetPid);
    final token = res.token?.trim() ?? '';
    if (token.isEmpty) {
      _isCompletingGodotAuth = false;
      _godotAuthError =
          res.error ?? 'Failed to provision project sync link.';
      notifyListeners();
      return (ok: false, callbackUrl: null, error: _godotAuthError);
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

    _pendingGodotAuthPort = null;
    _pendingGodotAuthState = null;
    _pendingGodotProjectName = null;
    _godotAuthSelectedProjectId = null;
    _godotAuthMinimized = false;
    _isCompletingGodotAuth = false;
    _godotAuthError = null;
    notifyListeners();

    triggerBrowserRedirect(callbackUrl);
    return (ok: true, callbackUrl: callbackUrl, error: null);
  }
}

part of 'workbench_provider.dart';

int _docEffectiveTimestampMs(TierDocument doc) {
  final codeTs = int.tryParse(doc.sections['updated_at_ms'] ?? '') ?? 0;
  final godotSyncTs =
      int.tryParse(doc.sections['last_godot_sync_ms'] ?? '') ?? 0;
  return codeTs > godotSyncTs ? codeTs : godotSyncTs;
}

int _countCompletedSubtasksRecursive(List<Subtask> tasks) {
  int count = 0;
  for (final t in tasks) {
    if (t.completed) count++;
    if (t.children.isNotEmpty) {
      count += _countCompletedSubtasksRecursive(t.children);
    }
  }
  return count;
}

int _countTotalSubtasksRecursive(List<Subtask> tasks) {
  int count = 0;
  for (final t in tasks) {
    count++;
    if (t.children.isNotEmpty) {
      count += _countTotalSubtasksRecursive(t.children);
    }
  }
  return count;
}

/// Returns `true` when [remoteDoc] carries newer timestamps or further Godot/Playtest
/// progress than [localDoc] so startup cloud sync merges instead of overwriting.
bool shouldPreferRemoteDocumentOnSync(
  TierDocument localDoc,
  TierDocument remoteDoc,
) {
  final remoteTs = _docEffectiveTimestampMs(remoteDoc);
  final localTs = _docEffectiveTimestampMs(localDoc);
  if (remoteTs != localTs) {
    return remoteTs > localTs;
  }

  final remoteCompleted = _countCompletedSubtasksRecursive(remoteDoc.subtasks);
  final localCompleted = _countCompletedSubtasksRecursive(localDoc.subtasks);
  if (remoteCompleted != localCompleted) {
    return remoteCompleted > localCompleted;
  }

  int countEpicProgressScore(TierDocument doc) {
    if (doc.tier != TierType.epic) return 0;
    final spec = EpicSpec.fromDocument(doc);
    final resolvedFixes = spec.fixes.where((f) => f.resolved).length;
    final passedFeatures = spec.features.where((f) => f.isPassed).length;
    final featureChecksPassed = spec.features.fold<int>(
      0,
      (sum, f) =>
          sum +
          [...f.checks, ...f.releaseDeltaChecks]
              .where((c) => c.passed)
              .length,
    );
    final featureFixes = spec.features.fold<int>(
      0,
      (sum, f) => sum + f.fixes.length,
    );
    final resolvedFeatureFixes = spec.features.fold<int>(
      0,
      (sum, f) => sum + f.fixes.where((fx) => fx.resolved).length,
    );
    return spec.passedChecksCount +
        spec.fixes.length +
        resolvedFixes +
        passedFeatures +
        featureChecksPassed +
        featureFixes +
        resolvedFeatureFixes +
        (doc.isCompleted ? 1 : 0);
  }

  final remoteSignedGuards = countEpicProgressScore(remoteDoc);
  final localSignedGuards = countEpicProgressScore(localDoc);
  if (remoteSignedGuards != localSignedGuards) {
    return remoteSignedGuards > localSignedGuards;
  }

  if (remoteDoc.isCompleted != localDoc.isCompleted) {
    return remoteDoc.isCompleted;
  }

  final remoteTotalTasks = _countTotalSubtasksRecursive(remoteDoc.subtasks);
  final localTotalTasks = _countTotalSubtasksRecursive(localDoc.subtasks);
  if (remoteTotalTasks != localTotalTasks) {
    return remoteTotalTasks > localTotalTasks;
  }

  if (remoteDoc.childrenIds.length != localDoc.childrenIds.length) {
    return remoteDoc.childrenIds.length > localDoc.childrenIds.length;
  }

  final remoteGodotCtx =
      (remoteDoc.sections['godot_live_context_json'] ?? '').trim();
  final localGodotCtx =
      (localDoc.sections['godot_live_context_json'] ?? '').trim();
  if (remoteGodotCtx.isNotEmpty && localGodotCtx.isEmpty) {
    return true;
  }

  return false;
}

/// Persistence, Cloud Firestore real-time sync, authentication, and multi-project vault operations
/// for [WorkbenchProvider].
extension WorkbenchStorageMixin on WorkbenchProvider {
  static const Set<String> _legacyPlaceholderIds = {
    'proj_vanguard',
    'rel_01',
    'epic_01',
    'feat_01',
    'feat_02',
  };
  static const JsonEncoder _prettyJsonEncoder = JsonEncoder.withIndent('  ');

  void _onAuthStateChanged() {
    final user = _authService.currentUser;
    if (user == null) {
      _isCloudSynced = false;
      _myAiAccessStatus = null;
      _aiAccessRecords = const [];
      clearCachedGodotLinkTokens();
      _firestoreService.stopRealtimeSync();
      notifyListeners();
      return;
    }

    final email = (user.email ?? '').trim().toLowerCase();
    if (email == WorkbenchProvider.ownerAdminEmail) {
      _myAiAccessStatus = 'approved';
      _pendingUrlInviteToken = null;
      _pendingUrlInvitedEmail = null;
      _inviteFeedbackMessage = null;
      _startApprovedCloudSync(user.uid, isAdmin: true, userEmail: email);
      notifyListeners();
      return;
    }

    // Non-admin sign-in: verify or activate invite BEFORE touching Firestore `users/{uid}`
    unawaited(_verifyOrAcceptInvitedLogin(user.uid, email));
  }

  void _startApprovedCloudSync(
    String uid, {
    required bool isAdmin,
    required String userEmail,
  }) {
    GeminiAgentClient.lastErrorStatus = null;
    _offlineErrorMessage = null;
    _isCloudSynced = true;
    _lastCloudSyncAt = DateTime.now();

    if (isAdmin) {
      _firestoreService.watchAllAiAccessEntries(
        onEntries: (entries) {
          _aiAccessRecords = entries;
          notifyListeners();
        },
      );
    } else {
      _firestoreService.watchMyAiAccess(
        email: userEmail,
        onStatus: (status) {
          if (status == 'revoked') {
            _myAiAccessStatus = 'revoked';
            _isCloudSynced = false;
            _firestoreService.stopRealtimeSync();
            _offlineErrorMessage =
                'Access for $userEmail has been revoked by the workspace admin.';
            unawaited(_authService.signOut());
            notifyListeners();
          } else if (status != null) {
            _myAiAccessStatus = status;
            notifyListeners();
          }
        },
      );
    }

    bool initialLocalPushDone = false;
    () async {
      try {
        final remoteInitial = await _firestoreService.fetchAllDocuments(
          uid: uid,
        );
        final docsToPush = <TierDocument>[];
        if (remoteInitial != null && remoteInitial.isNotEmpty) {
          bool mergedAny = false;
          for (final entry in remoteInitial.entries) {
            final docId = entry.key;
            final remoteDoc = entry.value;
            final localDoc = documents[docId];
            if (localDoc == null) {
              documents[docId] = remoteDoc;
              LocalVaultService.saveDocument(remoteDoc);
              mergedAny = true;
              continue;
            }
            final preferRemote = shouldPreferRemoteDocumentOnSync(
              localDoc,
              remoteDoc,
            );
            final baseDoc = preferRemote ? remoteDoc : localDoc;
            final otherDoc = preferRemote ? localDoc : remoteDoc;
            final mergedChildren = <String>{
              ...baseDoc.childrenIds,
              ...otherDoc.childrenIds,
            }.toList();
            final childrenChanged =
                mergedChildren.length != baseDoc.childrenIds.length;
            final winner = childrenChanged
                ? baseDoc.copyWith(childrenIds: mergedChildren)
                : baseDoc;
            if (preferRemote || childrenChanged) {
              documents[docId] = winner;
              LocalVaultService.saveDocument(winner);
              mergedAny = true;
            }
            if (!preferRemote || childrenChanged) {
              docsToPush.add(winner);
            }
          }
          for (final localDoc in documents.values) {
            if (!remoteInitial.containsKey(localDoc.id)) {
              docsToPush.add(localDoc);
            }
          }
          if (mergedAny && !_isAgentBusy) {
            if (!_tryResolvePendingDeepLink()) {
              final keepingNewProjectIntake =
                  _activeProjectId != null &&
                  _activeProjectId == _unpersistedNewProjectId &&
                  !documents.containsKey(_activeProjectId);
              if (!keepingNewProjectIntake) {
                if (_activeProjectId == null ||
                    !documents.containsKey(_activeProjectId)) {
                  final projs = savedProjects;
                  if (projs.isNotEmpty) {
                    _restoreProjectState(projs.first.id);
                  }
                } else {
                  _restoreProjectState(
                    _activeProjectId!,
                    preserveProgressiveDraft:
                        _isDraftingProgressive || _progressiveDraft != null,
                    preserveSameProjectUi: true,
                  );
                }
              }
            }
            notifyListeners();
          }
        } else {
          docsToPush.addAll(documents.values);
        }
        await Future.wait([
          for (final doc in docsToPush)
            _firestoreService.saveDocument(uid: uid, doc: doc),
        ]);
      } finally {
        initialLocalPushDone = true;
      }
    }();
    if (_activeProjectId != null) {
      _firestoreService.saveSettings(
        uid: uid,
        settings: {
          'activeDocumentId': _activeProjectId,
          'themeMode': _isDark ? 'dark' : 'light',
        },
      );
    } else {
      _firestoreService.fetchUserSettings(uid: uid).then((remoteSettings) {
        if (remoteSettings == null) return;
        final remoteTheme = remoteSettings['themeMode']?.toString();
        if (remoteTheme != null) {
          _isDark = remoteTheme != 'light';
        }
        final remoteActiveId = remoteSettings['activeDocumentId']?.toString();
        if (!_tryResolvePendingDeepLink() &&
            _activeProjectId == null &&
            remoteActiveId != null &&
            documents.containsKey(remoteActiveId)) {
          _restoreProjectState(remoteActiveId);
        }
        notifyListeners();
      });
    }
    _firestoreService.startRealtimeSync(
      uid: uid,
      onSync: (remoteDocs) {
        _lastCloudSyncAt = DateTime.now();
        if (!initialLocalPushDone) return;
        applyRemoteDocumentSnapshot(remoteDocs);
      },
    );
  }

  /// Re-applies the latest queued Firestore snapshot once in-flight writes and agent turns finish.
  void flushDeferredRemoteSnapshotIfIdle() {
    if (_isDisposed || _isAgentBusy || _pendingCloudWriteDocIds.isNotEmpty) {
      return;
    }
    final queued = _deferredRemoteSnapshot;
    if (queued == null) return;
    _deferredRemoteSnapshot = null;
    applyRemoteDocumentSnapshot(queued);
  }

  /// Applies an incoming Firestore snapshot across `documents` while protecting
  /// active debounced keystrokes, in-flight Cloud writes, and live progressive release drafts.
  bool applyRemoteDocumentSnapshot(Map<String, TierDocument> remoteDocs) {
    if (_isAgentBusy || _pendingCloudWriteDocIds.isNotEmpty) {
      _deferredRemoteSnapshot = Map<String, TierDocument>.from(remoteDocs);
      return false;
    }
    _deferredRemoteSnapshot = null;
    if (remoteDocs.isNotEmpty) {
      final removedIds = documents.keys
          .where(
            (localId) =>
                !remoteDocs.containsKey(localId) &&
                !_persistTimers.containsKey(localId),
          )
          .toList();
      for (final removedId in removedIds) {
        documents.remove(removedId);
        LocalVaultService.deleteDocument(removedId);
      }
    }
    for (final entry in remoteDocs.entries) {
      if (_persistTimers.containsKey(entry.key)) continue;
      final localDoc = documents[entry.key];
      if (localDoc != null &&
          _docEffectiveTimestampMs(localDoc) >
              _docEffectiveTimestampMs(entry.value)) {
        continue;
      }
      documents[entry.key] = entry.value;
      LocalVaultService.saveDocument(entry.value);
    }
    if (!_tryResolvePendingDeepLink()) {
      final keepingNewProjectIntake =
          _activeProjectId != null &&
          _activeProjectId == _unpersistedNewProjectId &&
          !documents.containsKey(_activeProjectId);
      if (!keepingNewProjectIntake) {
        if (_activeProjectId == null ||
            !documents.containsKey(_activeProjectId)) {
          final projs = savedProjects;
          if (projs.isNotEmpty) {
            _restoreProjectState(projs.first.id);
          } else {
            createNewProject();
            return true;
          }
        } else {
          _restoreProjectState(
            _activeProjectId!,
            preserveProgressiveDraft:
                _isDraftingProgressive || _progressiveDraft != null,
            preserveSameProjectUi: true,
          );
        }
      }
    }
    notifyListeners();
    return true;
  }

  Future<void> _verifyOrAcceptInvitedLogin(
    String uid,
    String signedInEmail,
  ) async {
    final res = await GeminiAgentClient.postAuthenticatedProxyAction(
      routePath: '/acceptInvite',
      payload: <String, dynamic>{
        if (_pendingUrlInviteToken != null)
          'inviteToken': _pendingUrlInviteToken,
        if (_pendingUrlInvitedEmail != null)
          'invitedEmail': _pendingUrlInvitedEmail,
      },
    );

    if (res.statusCode == 200 && res.body['status'] == 'approved') {
      _myAiAccessStatus = 'approved';
      _pendingUrlInviteToken = null;
      _pendingUrlInvitedEmail = null;
      _inviteFeedbackMessage = null;
      _startApprovedCloudSync(uid, isAdmin: false, userEmail: signedInEmail);
      notifyListeners();
      return;
    }

    final errorObj = res.body['error'];
    final serverMsg = (errorObj is Map ? errorObj['message'] : null)?.toString();

    if (res.statusCode == 409) {
      // Wrong Google account selected for the invite link: keep invite modal open and prompt account switch
      _myAiAccessStatus = 'uninvited';
      _inviteFeedbackMessage = serverMsg ??
          'This invite was sent to $_pendingUrlInvitedEmail, but you signed in as $signedInEmail. Please switch Google accounts.';
      await _authService.signOut();
      notifyListeners();
      return;
    }

    // Uninvited or revoked user: sign out immediately (server already purged uninvited Firebase Auth UID)
    _myAiAccessStatus = res.body['status']?.toString() ?? 'uninvited';
    _offlineErrorMessage = serverMsg ??
        'Invite required — $signedInEmail has not been invited to this workspace yet.';
    await _authService.signOut();
    notifyListeners();
  }

  /// Sends (or resends) an email invite to [rawEmail] via `geminiProxy` `/sendInvite` (Admin-only).
  Future<({bool ok, bool emailSent, String? inviteUrl, String message})>
      sendUserInvite(
    String rawEmail, {
    bool resetStatus = false,
  }) async {
    final cleanEmail = rawEmail.trim().toLowerCase();
    if (cleanEmail.isEmpty || !cleanEmail.contains('@')) {
      return (
        ok: false,
        emailSent: false,
        inviteUrl: null,
        message: 'Enter a valid email address.',
      );
    }
    if (cleanEmail == WorkbenchProvider.ownerAdminEmail) {
      return (
        ok: false,
        emailSent: false,
        inviteUrl: null,
        message: 'Workspace owner already has full access.',
      );
    }

    final res = await GeminiAgentClient.postAuthenticatedProxyAction(
      routePath: '/sendInvite',
      payload: <String, dynamic>{
        'email': cleanEmail,
        'resetStatus': resetStatus,
      },
    );

    if (res.statusCode == 200 && res.body['ok'] == true) {
      final emailSent = res.body['emailSent'] == true;
      final inviteUrl = res.body['inviteUrl']?.toString();
      final nextStatus = (res.body['status'] ?? 'invited').toString();
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final updated = <AiAccessRecord>[
        AiAccessRecord(
          email: cleanEmail,
          status: nextStatus,
          inviteUrl: inviteUrl,
          invitedAtMs: nowMs,
        ),
        for (final r in _aiAccessRecords)
          if (r.email != cleanEmail) r,
      ];
      _aiAccessRecords = updated;
      notifyListeners();
      return (
        ok: true,
        emailSent: emailSent,
        inviteUrl: inviteUrl,
        message: emailSent
            ? 'Invite email sent to $cleanEmail.'
            : 'Invite created for $cleanEmail — invite link copied to clipboard.',
      );
    }

    final errObj = res.body['error'];
    final errMsg = (errObj is Map ? errObj['message'] : null)?.toString() ??
        'Failed to send invite (HTTP ${res.statusCode}).';
    return (
      ok: false,
      emailSent: false,
      inviteUrl: null,
      message: errMsg,
    );
  }

  /// Cancels a pending invite or revokes an active member's access (Admin-only).
  Future<bool> revokeUserInvite(String rawEmail) async {
    final cleanEmail = rawEmail.trim().toLowerCase();
    if (cleanEmail.isEmpty || cleanEmail == WorkbenchProvider.ownerAdminEmail) {
      return false;
    }
    final res = await GeminiAgentClient.postAuthenticatedProxyAction(
      routePath: '/revokeInvite',
      payload: <String, dynamic>{'email': cleanEmail},
    );
    if (res.statusCode == 200 && res.body['ok'] == true) {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      _aiAccessRecords = [
        for (final r in _aiAccessRecords)
          if (r.email == cleanEmail)
            AiAccessRecord(
              email: r.email,
              status: 'revoked',
              displayName: r.displayName,
              invitedAtMs: r.invitedAtMs,
              acceptedAtMs: r.acceptedAtMs,
              revokedAtMs: nowMs,
            )
          else
            r,
      ];
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Accepts a `?invite=<token>` link by signing in with Google and verifying via `/acceptInvite`.
  Future<bool> acceptPendingInviteWithGoogle() async {
    _inviteFeedbackMessage = null;
    notifyListeners();
    final cred = await _authService.signInWithGoogle();
    if (cred == null || cred.user == null) {
      notifyListeners();
      return false;
    }
    final uid = cred.user!.uid;
    final email = (cred.user!.email ?? '').trim().toLowerCase();
    if (email == WorkbenchProvider.ownerAdminEmail) {
      _myAiAccessStatus = 'approved';
      _pendingUrlInviteToken = null;
      _pendingUrlInvitedEmail = null;
      _startApprovedCloudSync(uid, isAdmin: true, userEmail: email);
      notifyListeners();
      return true;
    }
    await _verifyOrAcceptInvitedLogin(uid, email);
    return _myAiAccessStatus == 'approved';
  }

  void dismissPendingUrlInvite() {
    _pendingUrlInviteToken = null;
    _pendingUrlInvitedEmail = null;
    _inviteFeedbackMessage = null;
    notifyListeners();
  }

  /// Flushes pending debounced edits, merges remote-newer Cloud documents, and pushes
  /// local changes to Cloud Firestore without overwriting newer Godot Dock edits.
  Future<void> syncNowWithCloud() async {
    if (_persistTimers.isNotEmpty) {
      final pendingIds = _persistTimers.keys.toList();
      for (final id in pendingIds) {
        _persistTimers.remove(id)?.cancel();
        final pendingDoc = documents[id];
        if (pendingDoc != null) {
          await LocalVaultService.saveDocument(pendingDoc);
        }
      }
    } else {
      for (final doc in documents.values) {
        await LocalVaultService.saveDocument(doc);
      }
    }

    final uid = (testOverrideUserUid ?? _authService.currentUser?.uid)?.trim();
    if (uid == null || uid.isEmpty || !isSessionApprovedForAi) {
      _persistSettings();
      _lastCloudSyncAt = DateTime.now();
      notifyListeners();
      return;
    }

    final remoteDocs = testCloudDocumentsFetcher != null
        ? await testCloudDocumentsFetcher!(uid)
        : await _firestoreService.fetchAllDocuments(uid: uid);

    final docsToPush = <TierDocument>[];
    bool mergedAny = false;
    if (remoteDocs != null && remoteDocs.isNotEmpty) {
      for (final entry in remoteDocs.entries) {
        final docId = entry.key;
        final remoteDoc = entry.value;
        final localDoc = documents[docId];
        if (localDoc == null) {
          documents[docId] = remoteDoc;
          await LocalVaultService.saveDocument(remoteDoc);
          mergedAny = true;
          continue;
        }
        final preferRemote = shouldPreferRemoteDocumentOnSync(
          localDoc,
          remoteDoc,
        );
        final baseDoc = preferRemote ? remoteDoc : localDoc;
        final otherDoc = preferRemote ? localDoc : remoteDoc;
        final mergedChildren = <String>{
          ...baseDoc.childrenIds,
          ...otherDoc.childrenIds,
        }.toList();
        final childrenChanged =
            mergedChildren.length != baseDoc.childrenIds.length;
        final winner = childrenChanged
            ? baseDoc.copyWith(childrenIds: mergedChildren)
            : baseDoc;
        if (preferRemote || childrenChanged) {
          documents[docId] = winner;
          await LocalVaultService.saveDocument(winner);
          mergedAny = true;
        }
        if (!preferRemote || childrenChanged) {
          docsToPush.add(winner);
        }
      }
      for (final localDoc in documents.values) {
        if (!remoteDocs.containsKey(localDoc.id)) {
          docsToPush.add(localDoc);
        }
      }
    } else {
      docsToPush.addAll(documents.values);
    }

    final futures = <Future<void>>[];
    for (final doc in docsToPush) {
      _pendingCloudWriteDocIds.add(doc.id);
      final saveFuture = testCloudDocumentSaver != null
          ? testCloudDocumentSaver!(uid, doc)
          : _firestoreService.saveDocument(uid: uid, doc: doc);
      futures.add(
        saveFuture.whenComplete(() {
          _pendingCloudWriteDocIds.remove(doc.id);
          if (_pendingCloudWriteDocIds.isEmpty) {
            flushDeferredRemoteSnapshotIfIdle();
          }
        }),
      );
    }
    if (futures.isNotEmpty) {
      await Future.wait(futures);
    }
    if (_pendingCloudWriteDocIds.isEmpty) {
      flushDeferredRemoteSnapshotIfIdle();
    }

    if (mergedAny &&
        !_isAgentBusy &&
        _activeProjectId != null &&
        documents.containsKey(_activeProjectId)) {
      _restoreProjectState(
        _activeProjectId!,
        preserveProgressiveDraft:
            _isDraftingProgressive || _progressiveDraft != null,
        preserveSameProjectUi: true,
      );
    }

    _persistSettings();
    _lastCloudSyncAt = DateTime.now();
    notifyListeners();
  }

  /// Invites a collaborator by email (`editor` or `viewer`) to the active project and persists to Firestore.
  Future<bool> inviteProjectCollaborator({
    required String collaboratorEmail,
    String role = 'editor',
  }) async {
    final proj = activeProject;
    final cleanEmail = collaboratorEmail.trim().toLowerCase();
    if (proj == null || cleanEmail.isEmpty || !cleanEmail.contains('@')) {
      return false;
    }
    final list = _projectCollaborators.putIfAbsent(proj.id, () => []);
    list.removeWhere((c) => c['email'] == cleanEmail);
    list.add({'email': cleanEmail, 'role': role});
    proj.sections['collaborators_json'] = jsonEncode(list);
    _persistDocument(proj);

    final user = _authService.currentUser;
    if (user != null && isSessionApprovedForAi) {
      await _firestoreService.inviteCollaborator(
        projectId: proj.id,
        projectTitle: proj.title,
        ownerEmail: user.email ?? 'owner',
        collaboratorEmail: cleanEmail,
        role: role,
      );
      if (isAdminUser) {
        unawaited(sendUserInvite(cleanEmail));
      }
    }
    notifyListeners();
    return true;
  }

  Future<bool> signInWithGoogle() async {
    final cred = await _authService.signInWithGoogle();
    notifyListeners();
    return cred != null;
  }

  Future<void> signOutFromCloud() async {
    _autoSyncDebounceTimer?.cancel();
    _deferredRemoteSnapshot = null;
    _pendingCloudWriteDocIds.clear();
    clearCachedGodotLinkTokens();
    await _authService.signOut();
    notifyListeners();
  }

  /// Applies Web Studio URL deep-link query params (`?project=<id>&epic=<id>`)
  /// and Godot 4 Dock Google Sign-In browser handoff params (`?godot_auth=1&port=<port>&state=<nonce>&project_name=<Name>`).
  void applyDeepLinkParams(Map<String, String> queryParams) {
    bool didUpdate = false;
    final godotAuthFlag =
        (queryParams['godot_auth'] ?? '').trim().toLowerCase();
    if (godotAuthFlag == '1' || godotAuthFlag == 'true') {
      final port = int.tryParse((queryParams['port'] ?? '').trim());
      final state = (queryParams['state'] ?? '').trim();
      final projectNameRaw =
          (queryParams['project_name'] ?? '').trim();
      if (port != null &&
          port >= 1024 &&
          port <= 65535 &&
          RegExp(r'^[A-Za-z0-9_\-]{8,128}$').hasMatch(state)) {
        _pendingGodotAuthPort = port;
        _pendingGodotAuthState = state;
        _pendingGodotProjectName = projectNameRaw.isEmpty
            ? null
            : (projectNameRaw.length > 120
                ? projectNameRaw.substring(0, 120)
                : projectNameRaw);
        _godotAuthSelectedProjectId = null;
        _godotAuthMinimized = false;
        _godotAuthError = null;
        didUpdate = true;
      }
    }

    final projParam = (queryParams['project'] ?? '').trim();
    final rawEpicParam = (queryParams['epic'] ?? '').trim();
    final rawFeatureParam = (queryParams['feature'] ?? '').trim();
    final epicParam = rawEpicParam.isNotEmpty ? rawEpicParam : rawFeatureParam;
    final explicitFeatureParam =
        rawEpicParam.isNotEmpty ? rawFeatureParam : '';
    if (projParam.isNotEmpty) {
      _pendingUrlProjectId = projParam;
    }
    if (epicParam.isNotEmpty) {
      _pendingUrlEpicId = epicParam;
    }
    if (explicitFeatureParam.isNotEmpty) {
      _pendingUrlFeatureId = explicitFeatureParam;
    }
    if ((projParam.isNotEmpty ||
            epicParam.isNotEmpty ||
            explicitFeatureParam.isNotEmpty) &&
        _tryResolvePendingDeepLink()) {
      didUpdate = true;
    }
    if (didUpdate) {
      notifyListeners();
    }
  }

  ({String projectId, TierDocument epicDoc})? _findEpicDocByIdOrCode(
    String rawIdOrCode, {
    String? withinProjectId,
  }) {
    final clean = rawIdOrCode.trim();
    if (clean.isEmpty) return null;

    final projects = withinProjectId != null
        ? [if (documents[withinProjectId] != null) documents[withinProjectId]!]
        : savedProjects;

    final direct = documents[clean];
    if (direct != null && direct.tier == TierType.epic) {
      for (final proj in projects) {
        if (_collectProjectDocumentTreeIds(proj.id).contains(direct.id)) {
          return (projectId: proj.id, epicDoc: direct);
        }
      }
    }

    final lower = clean.toLowerCase();
    for (final proj in projects) {
      final treeIds = _collectProjectDocumentTreeIds(proj.id);
      int idx = 0;
      for (final id in treeIds) {
        final doc = documents[id];
        if (doc == null || doc.tier != TierType.epic) continue;
        final parsed = EpicSpec.fromDocument(doc, indexHint: idx);
        idx += 1;
        if (parsed.code.toLowerCase() == lower ||
            parsed.lineageKey.toLowerCase() == lower) {
          return (projectId: proj.id, epicDoc: doc);
        }
      }
    }
    return null;
  }

  bool _tryResolvePendingDeepLink() {
    final reqProjId = _pendingUrlProjectId;
    final reqEpicId = _pendingUrlEpicId;
    if ((reqProjId == null || reqProjId.isEmpty) &&
        (reqEpicId == null || reqEpicId.isEmpty)) {
      return false;
    }

    String? targetProjId;
    TierDocument? matchedEpicDoc;
    if (reqProjId != null &&
        reqProjId.isNotEmpty &&
        documents[reqProjId]?.tier == TierType.project) {
      targetProjId = reqProjId;
      if (reqEpicId != null && reqEpicId.isNotEmpty) {
        matchedEpicDoc = _findEpicDocByIdOrCode(
          reqEpicId,
          withinProjectId: targetProjId,
        )?.epicDoc;
      }
    } else if (reqEpicId != null && reqEpicId.isNotEmpty) {
      final found = _findEpicDocByIdOrCode(reqEpicId);
      if (found != null) {
        targetProjId = found.projectId;
        matchedEpicDoc = found.epicDoc;
      }
    }
    if (targetProjId == null) {
      return false;
    }

    if (_activeProjectId != targetProjId) {
      _restoreProjectState(targetProjId);
    }
    final proj = documents[targetProjId];
    if (proj != null && projectReleases.isNotEmpty) {
      _currentStage = WorkbenchStage.releaseWorkbench;
      proj.sections['current_stage'] = WorkbenchStage.releaseWorkbench.name;
    }

    final reqFeatureId = _pendingUrlFeatureId;
    bool resolvedEpic = reqEpicId == null || reqEpicId.isEmpty;
    if (!resolvedEpic && matchedEpicDoc != null) {
      final parentRelId = matchedEpicDoc.parentId;
      if (parentRelId != null && documents[parentRelId]?.tier == TierType.release) {
        _activeReleaseId = parentRelId;
        proj?.sections['active_release_id'] = parentRelId;
      }
      if (reqFeatureId != null && reqFeatureId.isNotEmpty) {
        selectFeature(matchedEpicDoc.id, reqFeatureId);
        _pendingUrlFeatureId = null;
      } else {
        selectEpic(matchedEpicDoc.id);
      }
      resolvedEpic = true;
    }

    _pendingUrlProjectId = null;
    if (resolvedEpic) {
      _pendingUrlEpicId = null;
    }
    _persistSettings();
    return true;
  }

  /// Loads saved projects from LocalStorage / SharedPreferences, detects `?invite=` & `?project=`/`?feature=` URL params,
  /// and starts Cloud Firestore sync if an approved Google account is logged in.
  Future<void> initVault() async {
    try {
      final qp = Uri.base.queryParameters;
      final urlInvite = qp['invite']?.trim();
      if (urlInvite != null && urlInvite.isNotEmpty) {
        _pendingUrlInviteToken = urlInvite;
        _pendingUrlInvitedEmail = qp['invited_email']?.trim().toLowerCase();
      }
      applyDeepLinkParams(qp);
    } catch (_) {}

    try {
      final loaded = await LocalVaultService.loadVaultData();
      // Ignore legacy static placeholder docs (`proj_vanguard`) if they don't have a concept_blueprint_json
      for (final doc in loaded.documents.values) {
        if (_legacyPlaceholderIds.contains(doc.id)) {
          continue;
        }
        documents[doc.id] = doc;
      }
      if (loaded.themeMode != null) {
        _isDark = loaded.themeMode != 'light';
      }
      // API keys are no longer loaded from browser localStorage; all live calls authenticate via Google Sign-In + geminiProxy.
      _apiKey = GeminiAgentClient.resolveDefaultApiKey();
      String normalizeSavedModel(String raw) {
        final trimmed = raw.trim();
        return trimmed == GeminiAgentClient.pinnedLiveFlashModel
            ? trimmed
            : GeminiAgentClient.pinnedLiveFlashModel;
      }

      final hadSavedAiPrefs = loaded.modelName != null ||
          loaded.planningModel != null ||
          loaded.thinkingLevel != null;
      final savedConversation = loaded.modelName?.trim();
      final savedPlanning = loaded.planningModel?.trim();
      final savedThinking = loaded.thinkingLevel?.trim().toUpperCase();

      _conversationModel = savedConversation != null && savedConversation.isNotEmpty
          ? normalizeSavedModel(savedConversation)
          : GeminiAgentClient.pinnedLiveFlashModel;
      _planningModel = savedPlanning != null && savedPlanning.isNotEmpty
          ? normalizeSavedModel(savedPlanning)
          : GeminiAgentClient.pinnedLiveFlashModel;
      _thinkingLevel = 'LOW';

      final needsAiPrefsMigration = hadSavedAiPrefs &&
          (savedConversation != GeminiAgentClient.pinnedLiveFlashModel ||
              savedPlanning != GeminiAgentClient.pinnedLiveFlashModel ||
              savedThinking != 'LOW');
      final projs = savedProjects;
      if (!_tryResolvePendingDeepLink() && projs.isNotEmpty) {
        final targetId = (loaded.activeDocumentId != null &&
                documents.containsKey(loaded.activeDocumentId))
            ? loaded.activeDocumentId!
            : projs.first.id;
        _restoreProjectState(targetId);
      }
      if (needsAiPrefsMigration) {
        await LocalVaultService.saveSettings(
          activeDocumentId: _activeProjectId ??
              loaded.activeDocumentId ??
              'proj_main',
          apiKey: '',
          modelName: _conversationModel,
          planningModel: _planningModel,
          thinkingLevel: _thinkingLevel,
          themeMode: _isDark ? 'dark' : 'light',
        );
      }
    } catch (e) {
      debugPrint('initVault error: $e');
    }
    _onAuthStateChanged();
    notifyListeners();
  }

  /// All user-created Tier 1 Project documents in the vault.
  List<TierDocument> get savedProjects {
    return documents.values
        .where((d) => d.tier == TierType.project)
        .toList();
  }

  /// Switches the active project and restores its Stage 1/2/3 blueprints and selection.
  void switchProject(String projectId) {
    if (!documents.containsKey(projectId)) return;
    _restoreProjectState(projectId);
    _persistSettings();
    notifyListeners();
  }

  /// Starts a brand-new Project at Stage 1 (`1. Project Spec`) while keeping existing projects in the vault.
  void createNewProject() {
    _activeProjectId = 'proj_${DateTime.now().millisecondsSinceEpoch}';
    _unpersistedNewProjectId = _activeProjectId;
    _activeReleaseId = null;
    _selectedEpicId = null;
    _selectedFeatureId = null;
    _expandedEpicIds.clear();
    _userPinnedDimension = false;
    _conceptDraft = null;
    _clearStage1TransientState();
    _progressiveDraft = null;
    _showingSparkPicker = true;
    _offlineErrorMessage = null;
    _executionLog.clear();
    _currentStage = WorkbenchStage.projectPitch;
    notifyListeners();
  }

  /// Renames a saved project in the vault (updating both its TierDocument title and Concept Blueprint).
  void renameProject(String projectId, String newTitle) {
    final clean = newTitle.trim();
    final proj = documents[projectId];
    if (proj == null || clean.isEmpty) return;

    proj.title = clean;
    final rawConcept = proj.sections['concept_blueprint_json'];
    if (rawConcept != null && rawConcept.isNotEmpty) {
      try {
        final bp = ProjectConceptBlueprint.fromJson(
          jsonDecode(rawConcept) as Map<String, dynamic>,
        );
        bp.gameTitle = clean.toUpperCase();
        proj.sections['concept_blueprint_json'] = jsonEncode(bp.toJson());
        if (_activeProjectId == projectId && _conceptDraft != null) {
          _conceptDraft!.gameTitle = clean.toUpperCase();
        }
      } catch (_) {}
    }
    _persistDocument(proj);
    notifyListeners();
  }

  /// Collects all document IDs belonging to [projectId]'s 3-tier tree (`Project -> Release -> Epic`).
  Set<String> _collectProjectDocumentTreeIds(String projectId) {
    final proj = documents[projectId];
    if (proj == null) return <String>{};

    final childrenByParent = <String, List<String>>{};
    for (final doc in documents.values) {
      if (doc.parentId != null) {
        childrenByParent.putIfAbsent(doc.parentId!, () => []).add(doc.id);
      }
    }

    final collectedIds = <String>{proj.id};
    final queue = <String>[proj.id, ...proj.childrenIds];
    while (queue.isNotEmpty) {
      final currentId = queue.removeLast();
      collectedIds.add(currentId);
      final doc = documents[currentId];
      if (doc != null) {
        for (final childId in doc.childrenIds) {
          if (collectedIds.add(childId)) {
            queue.add(childId);
          }
        }
      }
      final directChildren = childrenByParent[currentId];
      if (directChildren != null) {
        for (final childId in directChildren) {
          if (collectedIds.add(childId)) {
            queue.add(childId);
          }
        }
      }
    }
    return collectedIds;
  }

  /// Cancels pending debounce timers and saves [projectId]'s full 3-tier tree
  /// (`Project -> Release -> Epic`) to Firestore before Godot 4 Dock handoff redirects
  /// unload the browser tab.
  Future<void> flushProjectTreeToCloud(String projectId) async {
    final treeIds = _collectProjectDocumentTreeIds(projectId);
    if (treeIds.isEmpty) return;
    for (final id in treeIds) {
      final timer = _persistTimers.remove(id);
      if (timer != null) {
        timer.cancel();
      }
      final doc = documents[id];
      if (doc != null) {
        LocalVaultService.saveDocument(doc);
      }
    }
    final uid = (testOverrideUserUid ?? _authService.currentUser?.uid)?.trim();
    if (uid == null || uid.isEmpty || !isSessionApprovedForAi) return;
    final futures = <Future<void>>[];
    for (final id in treeIds) {
      final doc = documents[id];
      if (doc == null) continue;
      _pendingCloudWriteDocIds.add(id);
      final saveFuture = testCloudDocumentSaver != null
          ? testCloudDocumentSaver!(uid, doc)
          : _firestoreService.saveDocument(uid: uid, doc: doc);
      futures.add(
        saveFuture.whenComplete(() {
          _pendingCloudWriteDocIds.remove(id);
          if (_pendingCloudWriteDocIds.isEmpty) {
            flushDeferredRemoteSnapshotIfIdle();
          }
        }),
      );
    }
    if (futures.isNotEmpty) {
      await Future.wait(futures);
    }
  }

  void _remapEmbeddedEpicJsonAndClearSync(
    Map<String, String> sections, {
    String? newEpicDocId,
    required bool clearGodotSync,
  }) {
    if (clearGodotSync) {
      sections.remove('last_godot_sync_ms');
      sections.remove('godot_live_context_json');
      sections.remove('last_unreal_sync_ms');
      sections.remove('unreal_live_context_json');
    }
    if (newEpicDocId != null) {
      final rawSpec = sections['epic_spec_json'];
      if (rawSpec != null && rawSpec.isNotEmpty) {
        try {
          final map = Map<String, dynamic>.from(jsonDecode(rawSpec) as Map);
          map['id'] = newEpicDocId;
          sections['epic_spec_json'] = jsonEncode(map);
        } catch (_) {}
      }
    }
  }

  /// Deep-clones an existing project across all 3 tiers (`Project -> Release -> Epic`),
  /// persists to LocalVault & Cloud Firestore, and switches to the copy.
  String? duplicateProject(String projectId) {
    final src = documents[projectId];
    if (src == null) return null;

    final newId = 'proj_${DateTime.now().microsecondsSinceEpoch}';
    final copyTitle = '${src.title} (Copy)';
    final copiedSections = Map<String, String>.from(src.sections);
    _remapEmbeddedEpicJsonAndClearSync(copiedSections, clearGodotSync: true);

    final rawConcept = copiedSections['concept_blueprint_json'];
    if (rawConcept != null && rawConcept.isNotEmpty) {
      try {
        final bp = ProjectConceptBlueprint.fromJson(
          jsonDecode(rawConcept) as Map<String, dynamic>,
        );
        bp.gameTitle = copyTitle.toUpperCase();
        copiedSections['concept_blueprint_json'] = jsonEncode(bp.toJson());
      } catch (_) {}
    }

    final newReleaseIds = <String>[];
    String? mappedActiveReleaseId;
    final mappedRelIds = <String, String>{};
    final mappedEpicIds = <String, String>{};

    for (int rIdx = 0; rIdx < src.childrenIds.length; rIdx++) {
      final oldRelId = src.childrenIds[rIdx];
      final oldRel = documents[oldRelId];
      if (oldRel == null) continue;
      final newRelId = '${newId}_rel_${rIdx + 1}';
      mappedRelIds[oldRelId] = newRelId;
      if (copiedSections['active_release_id'] == oldRelId) {
        mappedActiveReleaseId = newRelId;
      }

      final newEpicIds = <String>[];
      for (int eIdx = 0; eIdx < oldRel.childrenIds.length; eIdx++) {
        final oldEpicId = oldRel.childrenIds[eIdx];
        final existingMapped = mappedEpicIds[oldEpicId];
        if (existingMapped != null) {
          newEpicIds.add(existingMapped);
          continue;
        }
        final oldEpic = documents[oldEpicId];
        if (oldEpic == null || oldEpic.tier != TierType.epic) continue;
        final newEpicId = '${newRelId}_epic_${eIdx + 1}';
        mappedEpicIds[oldEpicId] = newEpicId;
        final epicSections = Map<String, String>.from(oldEpic.sections);
        _remapEmbeddedEpicJsonAndClearSync(
          epicSections,
          newEpicDocId: newEpicId,
          clearGodotSync: true,
        );
        final clonedEpic = oldEpic.copyWith(
          id: newEpicId,
          parentId: newRelId,
          sections: epicSections,
          subtasks: oldEpic.subtasks.map((st) => st.copyWith()).toList(),
        );
        documents[newEpicId] = clonedEpic;
        _persistDocument(clonedEpic);
        newEpicIds.add(newEpicId);
      }

      final relSections = Map<String, String>.from(oldRel.sections);
      _remapEmbeddedEpicJsonAndClearSync(relSections, clearGodotSync: true);
      final newRelDoc = oldRel.copyWith(
        id: newRelId,
        parentId: newId,
        childrenIds: newEpicIds,
        sections: relSections,
      );
      documents[newRelId] = newRelDoc;
      _persistDocument(newRelDoc);
      newReleaseIds.add(newRelId);
    }

    if (newReleaseIds.isNotEmpty) {
      copiedSections['active_release_id'] =
          mappedActiveReleaseId ?? newReleaseIds.first;
    }
    final oldSelectedEpic = copiedSections['selected_epic_id'];
    if (oldSelectedEpic != null && mappedEpicIds.containsKey(oldSelectedEpic)) {
      copiedSections['selected_epic_id'] = mappedEpicIds[oldSelectedEpic]!;
    }

    final copyDoc = TierDocument(
      id: newId,
      title: copyTitle,
      tier: TierType.project,
      childrenIds: newReleaseIds,
      sections: copiedSections,
    );
    documents[newId] = copyDoc;
    _persistDocument(copyDoc);
    switchProject(newId);
    return newId;
  }

  /// Exports the full interactive state of [projectId] (`Project -> Release -> Epic`,
  /// Concept Blueprint, and Epic Specs) as a portable `.layers.json` bundle.
  String exportProjectToJson([String? projectId]) {
    final targetId = projectId ?? _activeProjectId;
    if (targetId == null) return '';
    if (targetId == _activeProjectId) {
      _syncActiveProjectMetadata();
    }
    final proj = documents[targetId];
    if (proj == null) return '';

    final collectedIds = _collectProjectDocumentTreeIds(proj.id);

    final bundleDocs = <Map<String, dynamic>>[
      for (final id in collectedIds)
        if (documents[id] != null) documents[id]!.toJson(),
    ];

    final payload = <String, dynamic>{
      'format': 'layers-agentic-project-v3',
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'projectId': proj.id,
      'projectTitle': proj.title,
      'documents': bundleDocs,
    };

    return _prettyJsonEncoder.convert(payload);
  }

  /// Imports a `.layers.json` project bundle into the vault, automatically remapping IDs
  /// if any document ID collides with an existing project, and switches to the imported project.
  String? importProjectFromJson(String rawJson) {
    final trimmed = rawJson.trim();
    if (trimmed.isEmpty) return null;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map<String, dynamic>) return null;
      final rawDocs = decoded['documents'];
      if (rawDocs is! List || rawDocs.isEmpty) return null;

      final parsedDocs = <TierDocument>[];
      for (final item in rawDocs) {
        if (item is Map) {
          final map = Map<String, dynamic>.from(item);
          if (TierDocument.isLegacyIgnoredTier(map)) continue;
          parsedDocs.add(TierDocument.fromJson(map));
        }
      }
      if (parsedDocs.isEmpty) return null;

      final rootProj = parsedDocs.firstWhere(
        (d) => d.tier == TierType.project,
        orElse: () => parsedDocs.first,
      );

      final hasCollision = parsedDocs.any((d) => documents.containsKey(d.id));
      final idMap = <String, String>{};
      final baseTs = DateTime.now().microsecondsSinceEpoch;
      if (hasCollision) {
        for (int i = 0; i < parsedDocs.length; i++) {
          final d = parsedDocs[i];
          if (d.tier == TierType.project) {
            idMap[d.id] = 'proj_${baseTs}_$i';
          } else {
            idMap[d.id] = '${d.tier.name}_${baseTs}_$i';
          }
        }
      } else {
        for (final d in parsedDocs) {
          idMap[d.id] = d.id;
        }
      }

      String remapId(String id) => idMap[id] ?? id;

      for (final d in parsedDocs) {
        final newId = remapId(d.id);
        final newParentId = d.parentId != null ? remapId(d.parentId!) : null;
        final newChildrenIds = d.childrenIds.map(remapId).toList();
        final newSections = Map<String, String>.from(d.sections);

        _remapEmbeddedEpicJsonAndClearSync(
          newSections,
          newEpicDocId: d.tier == TierType.epic ? newId : null,
          clearGodotSync: hasCollision,
        );

        String importedTitle = d.title;
        if (d.tier == TierType.project) {
          if (hasCollision && !importedTitle.endsWith(' (Imported)')) {
            importedTitle = '$importedTitle (Imported)';
            final rawConcept = newSections['concept_blueprint_json'];
            if (rawConcept != null && rawConcept.isNotEmpty) {
              try {
                final cMap = Map<String, dynamic>.from(
                  jsonDecode(rawConcept) as Map,
                );
                cMap['gameTitle'] = importedTitle.toUpperCase();
                newSections['concept_blueprint_json'] = jsonEncode(cMap);
              } catch (_) {}
            }
          }
          final oldActiveRel = newSections['active_release_id'];
          if (oldActiveRel != null && idMap.containsKey(oldActiveRel)) {
            newSections['active_release_id'] = idMap[oldActiveRel]!;
          }
          final oldSelEpic = newSections['selected_epic_id'];
          if (oldSelEpic != null && idMap.containsKey(oldSelEpic)) {
            newSections['selected_epic_id'] = idMap[oldSelEpic]!;
          }
        }

        final importedDoc = d.copyWith(
          id: newId,
          title: importedTitle,
          parentId: newParentId,
          childrenIds: newChildrenIds,
          sections: newSections,
        );
        documents[newId] = importedDoc;
        _persistDocument(importedDoc);
      }

      final importedProjId = remapId(rootProj.id);
      switchProject(importedProjId);
      return importedProjId;
    } catch (e) {
      debugPrint('importProjectFromJson error: $e');
      return null;
    }
  }

  /// Deletes a project and its child documents from LocalVaultService and Cloud Firestore.
  void deleteProject(String projectId) {
    final idsToRemove = _collectProjectDocumentTreeIds(projectId);
    if (idsToRemove.isEmpty) return;

    _cachedGodotLinkTokensByProjectId.remove(projectId);
    _projectCollaborators.remove(projectId);
    final user = _authService.currentUser;
    for (final id in idsToRemove) {
      _persistTimers.remove(id)?.cancel();
      _pendingCloudWriteDocIds.remove(id);
      documents.remove(id);
      LocalVaultService.deleteDocument(id);
      if (user != null) {
        _firestoreService.deleteDocument(uid: user.uid, docId: id);
      }
    }

    if (_activeProjectId == projectId) {
      final remaining = savedProjects;
      if (remaining.isNotEmpty) {
        switchProject(remaining.first.id);
      } else {
        createNewProject();
      }
    } else {
      notifyListeners();
    }
    if (_pendingCloudWriteDocIds.isEmpty) {
      flushDeferredRemoteSnapshotIfIdle();
    }
  }

  void _restoreProjectState(
    String projectId, {
    bool preserveProgressiveDraft = false,
    bool preserveSameProjectUi = false,
  }) {
    final proj = documents[projectId];
    if (proj == null) return;
    final prevProjectId = _activeProjectId;
    final prevConceptJson =
        _conceptDraft != null ? jsonEncode(_conceptDraft!.toJson()) : null;
    _unpersistedNewProjectId = null;
    if (!preserveProgressiveDraft) {
      _executionLog.clear();
      _progressiveDraft = null;
    }
    _activeProjectId = projectId;

    // Restore Collaborators
    final rawCollabs = proj.sections['collaborators_json'];
    if (rawCollabs != null && rawCollabs.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawCollabs) as List<dynamic>;
        _projectCollaborators[projectId] = [
          for (final item in decoded)
            if (item is Map)
              {
                'email': (item['email'] ?? '').toString(),
                'role': (item['role'] ?? 'editor').toString(),
              },
        ];
      } catch (_) {}
    }

    // Restore Concept Blueprint
    final rawConcept = proj.sections['concept_blueprint_json'];
    final sameConceptUnchanged = preserveSameProjectUi &&
        prevProjectId == projectId &&
        ((rawConcept == null && prevConceptJson == null) ||
            (rawConcept != null && rawConcept == prevConceptJson));
    if (rawConcept != null && rawConcept.isNotEmpty) {
      try {
        _conceptDraft = ProjectConceptBlueprint.fromJson(
          jsonDecode(rawConcept) as Map<String, dynamic>,
        );
      } catch (e) {
        debugPrint('Restore concept_blueprint_json error: $e');
        _conceptDraft = null;
      }
    } else {
      _conceptDraft = null;
    }
    if (!sameConceptUnchanged) {
      _clearStage1TransientState();
    }
    _showingSparkPicker = _conceptDraft == null || !_conceptDraft!.hasSpec;

    // Restore active Release & Epic selection
    final savedRelId = proj.sections['active_release_id'];
    if (savedRelId != null && documents[savedRelId]?.tier == TierType.release) {
      _activeReleaseId = savedRelId;
    } else if (projectReleases.isNotEmpty) {
      _activeReleaseId = projectReleases.first.id;
    } else {
      _activeReleaseId = null;
    }

    final epicDocs = activeReleaseEpicDocs;
    final validEpicIds = epicDocs.map((d) => d.id).toSet();
    if (preserveSameProjectUi && prevProjectId == projectId) {
      _expandedEpicIds.retainWhere(validEpicIds.contains);
    } else {
      _expandedEpicIds.clear();
    }
    if (epicDocs.isNotEmpty) {
      final savedEpicId = proj.sections['selected_epic_id'];
      if (savedEpicId != null && epicDocs.any((d) => d.id == savedEpicId)) {
        _selectedEpicId = savedEpicId;
      } else {
        final firstUnpassed = epicDocs.firstWhere(
          (d) => !EpicSpec.fromDocument(d).isPassed,
          orElse: () => epicDocs.first,
        );
        _selectedEpicId = firstUnpassed.id;
      }
      if (_selectedEpicId != null) {
        _expandedEpicIds.add(_selectedEpicId!);
      }
      if (proj.sections.containsKey('selected_feature_id')) {
        final savedFeatureId =
            (proj.sections['selected_feature_id'] ?? '').trim();
        if (savedFeatureId.isEmpty) {
          _selectedFeatureId = null;
        } else {
          _selectedFeatureId = _defaultFeatureIdForEpicDoc(
            _selectedEpicId,
            preferredId: savedFeatureId,
          );
        }
      } else {
        _selectedFeatureId = _defaultFeatureIdForEpicDoc(_selectedEpicId);
      }
    } else {
      _selectedEpicId = null;
      _selectedFeatureId = null;
    }

    final savedStage = proj.sections['current_stage'];
    if ((savedStage == WorkbenchStage.releaseWorkbench.name ||
            savedStage == 'releasePlanGate') &&
        epicDocs.isNotEmpty) {
      _currentStage = WorkbenchStage.releaseWorkbench;
    } else {
      _currentStage = WorkbenchStage.projectPitch;
    }
  }

  void _persistDocument(TierDocument doc, {bool debounce = false}) {
    _persistTimers.remove(doc.id)?.cancel();
    doc.sections['updated_at_ms'] =
        DateTime.now().millisecondsSinceEpoch.toString();
    void writeNow() {
      LocalVaultService.saveDocument(doc);
      final uid = (testOverrideUserUid ?? _authService.currentUser?.uid)?.trim();
      if (uid != null && uid.isNotEmpty && isSessionApprovedForAi) {
        _pendingCloudWriteDocIds.add(doc.id);
        final saveFuture = testCloudDocumentSaver != null
            ? testCloudDocumentSaver!(uid, doc)
            : _firestoreService.saveDocument(uid: uid, doc: doc);
        saveFuture.then((_) {
          _lastCloudSyncAt = DateTime.now();
        }).whenComplete(() {
          _pendingCloudWriteDocIds.remove(doc.id);
          if (_pendingCloudWriteDocIds.isEmpty) {
            flushDeferredRemoteSnapshotIfIdle();
          }
        });
      }
    }

    if (debounce && enableAutoLoad) {
      _persistTimers[doc.id] = Timer(const Duration(milliseconds: 250), () {
        _persistTimers.remove(doc.id);
        if (!documents.containsKey(doc.id)) return;
        writeNow();
      });
    } else {
      writeNow();
    }
  }

  void _persistSettings() {
    final activeId = _activeProjectId ?? 'proj_main';
    LocalVaultService.saveSettings(
      activeDocumentId: activeId,
      apiKey: '',
      modelName: _conversationModel,
      planningModel: _planningModel,
      thinkingLevel: _thinkingLevel,
      themeMode: _isDark ? 'dark' : 'light',
    );
    final user = _authService.currentUser;
    if (user != null && isSessionApprovedForAi) {
      _firestoreService.saveSettings(
        uid: user.uid,
        settings: {
          'activeDocumentId': activeId,
          'themeMode': _isDark ? 'dark' : 'light',
        },
      );
    }
  }

  void _syncActiveProjectMetadata() {
    final proj = activeProject;
    if (proj == null) return;
    proj.sections['current_stage'] = _currentStage.name;
    if (_activeReleaseId != null) {
      proj.sections['active_release_id'] = _activeReleaseId!;
    }
    if (_selectedEpicId != null) {
      proj.sections['selected_epic_id'] = _selectedEpicId!;
    }
    proj.sections['selected_feature_id'] = _selectedFeatureId ?? '';
    if (_conceptDraft != null) {
      proj.sections['concept_blueprint_json'] =
          jsonEncode(_conceptDraft!.toJson());
    }
    _persistDocument(proj);
    _persistSettings();
  }
}

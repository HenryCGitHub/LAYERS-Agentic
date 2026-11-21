import '../agents/gemini_agent_client.dart';
import '../constants/tiers.dart';
import '../models/epic_spec.dart';
import '../models/tier_document.dart';
import 'firestore_vault_service.dart';
import 'project_archive_codec.dart';

int docEffectiveTimestampMs(TierDocument doc) {
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
  final remoteTs = docEffectiveTimestampMs(remoteDoc);
  final localTs = docEffectiveTimestampMs(localDoc);
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

/// Pure Cloud invite, allowlist, remote sync merge, and URL deep-link helper methods
/// extracted from `WorkbenchStorageMixin`.
class CloudInviteDeepLinkService {
  /// Computes non-destructive local winners and pending pushes when merging [remoteDocs].
  static ({
    List<TierDocument> docsToSaveLocally,
    List<TierDocument> docsToPush,
  }) mergeRemoteDocumentMap({
    required Map<String, TierDocument> documents,
    required Map<String, TierDocument>? remoteDocs,
  }) {
    final docsToSaveLocally = <TierDocument>[];
    final docsToPush = <TierDocument>[];
    if (remoteDocs != null && remoteDocs.isNotEmpty) {
      for (final entry in remoteDocs.entries) {
        final docId = entry.key;
        final remoteDoc = entry.value;
        final localDoc = documents[docId];
        if (localDoc == null) {
          docsToSaveLocally.add(remoteDoc);
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
          docsToSaveLocally.add(winner);
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
    return (
      docsToSaveLocally: docsToSaveLocally,
      docsToPush: docsToPush,
    );
  }

  /// Parses Web Studio URL deep-link and Godot 4 OAuth loopback query parameters.
  static ({
    bool hasGodotAuth,
    int? godotPort,
    String? godotState,
    String? godotProjectName,
    String? projectId,
    String? epicId,
    String? featureId,
  }) parseDeepLinkQuery(Map<String, String> queryParams) {
    bool hasGodotAuth = false;
    int? godotPort;
    String? godotState;
    String? godotProjectName;

    final godotAuthFlag =
        (queryParams['godot_auth'] ?? '').trim().toLowerCase();
    if (godotAuthFlag == '1' || godotAuthFlag == 'true') {
      final port = int.tryParse((queryParams['port'] ?? '').trim());
      final state = (queryParams['state'] ?? '').trim();
      final projectNameRaw = (queryParams['project_name'] ?? '').trim();
      if (port != null &&
          port >= 1024 &&
          port <= 65535 &&
          RegExp(r'^[A-Za-z0-9_\-]{8,128}$').hasMatch(state)) {
        hasGodotAuth = true;
        godotPort = port;
        godotState = state;
        godotProjectName = projectNameRaw.isEmpty
            ? null
            : (projectNameRaw.length > 120
                ? projectNameRaw.substring(0, 120)
                : projectNameRaw);
      }
    }

    final projParam = (queryParams['project'] ?? '').trim();
    final rawEpicParam = (queryParams['epic'] ?? '').trim();
    final rawFeatureParam = (queryParams['feature'] ?? '').trim();
    final epicParam = rawEpicParam.isNotEmpty ? rawEpicParam : rawFeatureParam;
    final explicitFeatureParam =
        rawEpicParam.isNotEmpty ? rawFeatureParam : '';

    return (
      hasGodotAuth: hasGodotAuth,
      godotPort: godotPort,
      godotState: godotState,
      godotProjectName: godotProjectName,
      projectId: projParam.isNotEmpty ? projParam : null,
      epicId: epicParam.isNotEmpty ? epicParam : null,
      featureId: explicitFeatureParam.isNotEmpty ? explicitFeatureParam : null,
    );
  }

  /// Resolves an Epic document by exact document ID, code (`E01`), or lineage key (`e01`).
  static ({String projectId, TierDocument epicDoc})? findEpicDocByIdOrCode({
    required Map<String, TierDocument> documents,
    required List<TierDocument> savedProjects,
    required String rawIdOrCode,
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
        if (ProjectArchiveCodec.collectProjectTreeIds(documents, proj.id)
            .contains(direct.id)) {
          return (projectId: proj.id, epicDoc: direct);
        }
      }
    }

    final lower = clean.toLowerCase();
    for (final proj in projects) {
      final treeIds =
          ProjectArchiveCodec.collectProjectTreeIds(documents, proj.id);
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

  /// Calls `/acceptInvite` on `geminiProxy` and classifies approved / mismatch / uninvited responses.
  static Future<({
    bool approved,
    bool wrongAccount,
    String status,
    String? feedbackMessage,
    String? offlineError,
  })> verifyOrAcceptInvitedLogin({
    required String signedInEmail,
    String? inviteToken,
    String? invitedEmail,
  }) async {
    final res = await GeminiAgentClient.postAuthenticatedProxyAction(
      routePath: '/acceptInvite',
      payload: <String, dynamic>{
        if (inviteToken != null) 'inviteToken': inviteToken,
        if (invitedEmail != null) 'invitedEmail': invitedEmail,
      },
    );

    if (res.statusCode == 200 && res.body['status'] == 'approved') {
      return (
        approved: true,
        wrongAccount: false,
        status: 'approved',
        feedbackMessage: null,
        offlineError: null,
      );
    }

    final errorObj = res.body['error'];
    final serverMsg = (errorObj is Map ? errorObj['message'] : null)?.toString();

    if (res.statusCode == 409) {
      return (
        approved: false,
        wrongAccount: true,
        status: 'uninvited',
        feedbackMessage: serverMsg ??
            'This invite was sent to $invitedEmail, but you signed in as $signedInEmail. Please switch Google accounts.',
        offlineError: null,
      );
    }

    return (
      approved: false,
      wrongAccount: false,
      status: res.body['status']?.toString() ?? 'uninvited',
      feedbackMessage: null,
      offlineError: serverMsg ??
          'Invite required — $signedInEmail has not been invited to this workspace yet.',
    );
  }

  /// Sends (or resends) an email invite to [rawEmail] via `geminiProxy` `/sendInvite`.
  static Future<({
    bool ok,
    bool emailSent,
    String? inviteUrl,
    String message,
    List<AiAccessRecord>? updatedRecords,
  })> sendUserInvite({
    required String rawEmail,
    required String ownerAdminEmail,
    required List<AiAccessRecord> currentRecords,
    bool resetStatus = false,
  }) async {
    final cleanEmail = rawEmail.trim().toLowerCase();
    if (cleanEmail.isEmpty || !cleanEmail.contains('@')) {
      return (
        ok: false,
        emailSent: false,
        inviteUrl: null,
        message: 'Enter a valid email address.',
        updatedRecords: null,
      );
    }
    if (cleanEmail == ownerAdminEmail) {
      return (
        ok: false,
        emailSent: false,
        inviteUrl: null,
        message: 'Workspace owner already has full access.',
        updatedRecords: null,
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
        for (final r in currentRecords)
          if (r.email != cleanEmail) r,
      ];
      return (
        ok: true,
        emailSent: emailSent,
        inviteUrl: inviteUrl,
        message: emailSent
            ? 'Invite email sent to $cleanEmail.'
            : 'Invite created for $cleanEmail — invite link copied to clipboard.',
        updatedRecords: updated,
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
      updatedRecords: null,
    );
  }

  /// Revokes a user invite or active workspace access via `geminiProxy` `/revokeInvite`.
  static Future<List<AiAccessRecord>?> revokeUserInvite({
    required String rawEmail,
    required String ownerAdminEmail,
    required List<AiAccessRecord> currentRecords,
  }) async {
    final cleanEmail = rawEmail.trim().toLowerCase();
    if (cleanEmail.isEmpty || cleanEmail == ownerAdminEmail) {
      return null;
    }
    final res = await GeminiAgentClient.postAuthenticatedProxyAction(
      routePath: '/revokeInvite',
      payload: <String, dynamic>{'email': cleanEmail},
    );
    if (res.statusCode == 200 && res.body['ok'] == true) {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      return <AiAccessRecord>[
        for (final r in currentRecords)
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
    }
    return null;
  }

  /// Resolves a queued `?project=&epic=&feature=` target across saved projects.
  static ({String projectId, TierDocument? matchedEpicDoc})?
      resolvePendingDeepLinkTarget({
    required Map<String, TierDocument> documents,
    required List<TierDocument> savedProjects,
    String? pendingProjectId,
    String? pendingEpicId,
  }) {
    if ((pendingProjectId == null || pendingProjectId.isEmpty) &&
        (pendingEpicId == null || pendingEpicId.isEmpty)) {
      return null;
    }

    String? targetProjId;
    TierDocument? matchedEpicDoc;
    if (pendingProjectId != null &&
        pendingProjectId.isNotEmpty &&
        documents[pendingProjectId]?.tier == TierType.project) {
      targetProjId = pendingProjectId;
      if (pendingEpicId != null && pendingEpicId.isNotEmpty) {
        matchedEpicDoc = findEpicDocByIdOrCode(
          documents: documents,
          savedProjects: savedProjects,
          rawIdOrCode: pendingEpicId,
          withinProjectId: targetProjId,
        )?.epicDoc;
      }
    } else if (pendingEpicId != null && pendingEpicId.isNotEmpty) {
      final found = findEpicDocByIdOrCode(
        documents: documents,
        savedProjects: savedProjects,
        rawIdOrCode: pendingEpicId,
      );
      if (found != null) {
        targetProjId = found.projectId;
        matchedEpicDoc = found.epicDoc;
      }
    }
    if (targetProjId == null) return null;
    return (projectId: targetProjId, matchedEpicDoc: matchedEpicDoc);
  }

  /// Computes snapshot deletions and newer remote overwrites while protecting pending debounced writes.
  static ({List<String> removedIds, List<TierDocument> docsToApply})
      computeSnapshotSyncActions({
    required Map<String, TierDocument> documents,
    required Map<String, TierDocument> remoteDocs,
    required Set<String> activePersistTimerIds,
  }) {
    final removedIds = <String>[
      if (remoteDocs.isNotEmpty)
        for (final localId in documents.keys)
          if (!remoteDocs.containsKey(localId) &&
              !activePersistTimerIds.contains(localId))
            localId,
    ];
    final docsToApply = <TierDocument>[];
    for (final entry in remoteDocs.entries) {
      if (activePersistTimerIds.contains(entry.key)) continue;
      final localDoc = documents[entry.key];
      if (localDoc != null &&
          docEffectiveTimestampMs(localDoc) >
              docEffectiveTimestampMs(entry.value)) {
        continue;
      }
      docsToApply.add(entry.value);
    }
    return (removedIds: removedIds, docsToApply: docsToApply);
  }
}

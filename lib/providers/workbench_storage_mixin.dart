part of 'workbench_provider.dart';

/// Persistence, Cloud Firestore real-time sync, authentication, and multi-project vault operations
/// for [WorkbenchProvider].
extension WorkbenchStorageMixin on WorkbenchProvider {
  void _onAuthStateChanged() {
    final user = _authService.currentUser;
    if (user != null) {
      _isCloudSynced = true;
      _lastCloudSyncAt = DateTime.now();
      bool initialLocalPushDone = false;
      // Push any existing local documents up to Firestore on login
      Future.wait([
        for (final doc in documents.values)
          _firestoreService.saveDocument(uid: user.uid, doc: doc),
      ]).then((_) {
        initialLocalPushDone = true;
      });
      if (_activeProjectId != null) {
        _firestoreService.saveSettings(
          uid: user.uid,
          settings: {
            'activeDocumentId': _activeProjectId,
            'themeMode': _isDark ? 'dark' : 'light',
          },
        );
      } else {
        _firestoreService.fetchUserSettings(uid: user.uid).then((remoteSettings) {
          if (remoteSettings == null) return;
          final remoteTheme = remoteSettings['themeMode']?.toString();
          if (remoteTheme != null) {
            _isDark = remoteTheme != 'light';
          }
          final remoteActiveId = remoteSettings['activeDocumentId']?.toString();
          if (remoteActiveId != null && documents.containsKey(remoteActiveId)) {
            _restoreProjectState(remoteActiveId);
          }
          notifyListeners();
        });
      }
      _firestoreService.startRealtimeSync(
        uid: user.uid,
        onSync: (remoteDocs) {
          _lastCloudSyncAt = DateTime.now();
          if (remoteDocs.isEmpty && !initialLocalPushDone) return;
          // Skip intermediate snapshot reconciliation while local batch writes or agent operations are in flight
          if (_isAgentBusy || _pendingCloudWriteDocIds.isNotEmpty) return;
          // Reconcile remote deletions once initial local push has finished
          if (initialLocalPushDone && remoteDocs.isNotEmpty) {
            final removedIds = documents.keys
                .where((localId) => !remoteDocs.containsKey(localId))
                .toList();
            for (final removedId in removedIds) {
              documents.remove(removedId);
              LocalVaultService.deleteDocument(removedId);
            }
          }
          for (final entry in remoteDocs.entries) {
            documents[entry.key] = entry.value;
            LocalVaultService.saveDocument(entry.value);
          }
          if (_activeProjectId == null || !documents.containsKey(_activeProjectId)) {
            final projs = savedProjects;
            if (projs.isNotEmpty) {
              _restoreProjectState(projs.first.id);
            }
          } else {
            _restoreProjectState(_activeProjectId!);
          }
          notifyListeners();
        },
      );
    } else {
      _isCloudSynced = false;
      _firestoreService.stopRealtimeSync();
    }
    notifyListeners();
  }

  /// Manually pushes all current local documents and settings to Cloud Firestore.
  Future<void> syncNowWithCloud() async {
    final user = _authService.currentUser;
    for (final doc in documents.values) {
      await LocalVaultService.saveDocument(doc);
      if (user != null) {
        await _firestoreService.saveDocument(uid: user.uid, doc: doc);
      }
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
    if (user != null) {
      await _firestoreService.inviteCollaborator(
        projectId: proj.id,
        projectTitle: proj.title,
        ownerEmail: user.email ?? 'owner',
        collaboratorEmail: cleanEmail,
        role: role,
      );
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
    await _authService.signOut();
    notifyListeners();
  }

  /// Loads saved projects from LocalStorage / SharedPreferences and starts Cloud Firestore sync if logged in.
  Future<void> initVault() async {
    try {
      final loaded = await LocalVaultService.loadVaultData();
      // Ignore legacy static placeholder docs (`proj_vanguard`) if they don't have a concept_blueprint_json
      for (final doc in loaded.documents.values) {
        if (doc.id == 'proj_vanguard' ||
            doc.id == 'rel_01' ||
            doc.id == 'epic_01' ||
            doc.id == 'feat_01' ||
            doc.id == 'feat_02') {
          continue;
        }
        documents[doc.id] = doc;
      }
      if (loaded.themeMode != null) {
        _isDark = loaded.themeMode != 'light';
      }
      if (loaded.apiKey != null && loaded.apiKey!.trim().isNotEmpty) {
        _apiKey = loaded.apiKey!.trim();
      }
      if (loaded.modelName != null && loaded.modelName!.trim().isNotEmpty) {
        _conversationModel = loaded.modelName!.trim();
      }
      if (loaded.planningModel != null &&
          loaded.planningModel!.trim().isNotEmpty) {
        _planningModel = loaded.planningModel!.trim();
      }
      if (loaded.thinkingLevel != null &&
          loaded.thinkingLevel!.trim().isNotEmpty) {
        _thinkingLevel = loaded.thinkingLevel!.trim().toUpperCase();
      }
      final projs = savedProjects;
      if (projs.isNotEmpty) {
        final targetId = (loaded.activeDocumentId != null &&
                documents.containsKey(loaded.activeDocumentId))
            ? loaded.activeDocumentId!
            : projs.first.id;
        _restoreProjectState(targetId);
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

  /// Starts a brand-new Project at Stage 1A (`New Project`) while keeping existing projects in the vault.
  void createNewProject() {
    _activeProjectId = 'proj_${DateTime.now().millisecondsSinceEpoch}';
    _activeReleaseId = null;
    _selectedBeatId = null;
    _selectedFeatureId = null;
    _conceptDraft = null;
    _releaseBlueprint = null;
    _sparkIntake = null;
    _sparkSuggestionVariantOffset = 0;
    _offlineErrorMessage = null;
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
        bp.title = clean;
        proj.sections['concept_blueprint_json'] = jsonEncode(bp.toJson());
        if (_activeProjectId == projectId && _conceptDraft != null) {
          _conceptDraft!.title = clean;
        }
      } catch (_) {}
    }
    _persistDocument(proj);
    notifyListeners();
  }

  String _remapSerializedReleaseBlueprintJson(
    String rawJson,
    String Function(String id) remapId,
  ) {
    if (rawJson.trim().isEmpty) return rawJson;
    try {
      final bpMap = Map<String, dynamic>.from(jsonDecode(rawJson) as Map);
      final oldRelDocId = bpMap['releaseDocId']?.toString();
      if (oldRelDocId != null && oldRelDocId.isNotEmpty) {
        bpMap['releaseDocId'] = remapId(oldRelDocId);
      }
      final rawBeats = bpMap['beats'];
      if (rawBeats is List) {
        for (final bItem in rawBeats) {
          if (bItem is Map) {
            final bId = bItem['id']?.toString();
            if (bId != null && bId.isNotEmpty) {
              bItem['id'] = remapId(bId);
            }
            final rawFeats = bItem['features'];
            if (rawFeats is List) {
              for (final fItem in rawFeats) {
                if (fItem is Map) {
                  final fId = fItem['id']?.toString();
                  if (fId != null && fId.isNotEmpty) {
                    fItem['id'] = remapId(fId);
                  }
                }
              }
            }
          }
        }
      }
      return jsonEncode(bpMap);
    } catch (_) {
      return rawJson;
    }
  }

  /// Deep-clones an existing project across all 4 tiers (Project -> Release -> Beat -> Feature)
  /// including all Checkpoints and How-To Sub-Steps, persists to LocalStorage & Firestore, and switches to the copy.
  String? duplicateProject(String projectId) {
    final src = documents[projectId];
    if (src == null) return null;

    final newId = 'proj_${DateTime.now().microsecondsSinceEpoch}';
    final copyTitle = '${src.title} (Copy)';
    final copiedSections = Map<String, String>.from(src.sections);

    final rawConcept = copiedSections['concept_blueprint_json'];
    if (rawConcept != null && rawConcept.isNotEmpty) {
      try {
        final bp = ProjectConceptBlueprint.fromJson(
          jsonDecode(rawConcept) as Map<String, dynamic>,
        );
        bp.title = copyTitle;
        copiedSections['concept_blueprint_json'] = jsonEncode(bp.toJson());
      } catch (_) {}
    }

    final newReleaseIds = <String>[];
    String? mappedActiveReleaseId;
    final mappedRelIds = <String, String>{};
    final mappedBeatIds = <String, String>{};
    final mappedFeatIds = <String, String>{};

    for (int rIdx = 0; rIdx < src.childrenIds.length; rIdx++) {
      final oldRelId = src.childrenIds[rIdx];
      final oldRel = documents[oldRelId];
      if (oldRel == null) continue;
      final newRelId = '${newId}_rel_${rIdx + 1}';
      mappedRelIds[oldRelId] = newRelId;
      if (copiedSections['active_release_id'] == oldRelId) {
        mappedActiveReleaseId = newRelId;
      }

      // Deep-clone Tier 3 Beats and Tier 4 Features under this Release while preserving shared Live-Tree identity across releases
      final newBeatIds = <String>[];
      for (int bIdx = 0; bIdx < oldRel.childrenIds.length; bIdx++) {
        final oldBeatId = oldRel.childrenIds[bIdx];
        final existingMappedBeatId = mappedBeatIds[oldBeatId];
        if (existingMappedBeatId != null) {
          newBeatIds.add(existingMappedBeatId);
          continue;
        }
        final oldBeat = documents[oldBeatId];
        if (oldBeat == null) continue;
        final newBeatId = '${newId}_beat_${mappedBeatIds.length + 1}';
        mappedBeatIds[oldBeatId] = newBeatId;

        final newFeatIds = <String>[];
        for (int fIdx = 0; fIdx < oldBeat.childrenIds.length; fIdx++) {
          final oldFeatId = oldBeat.childrenIds[fIdx];
          final existingMappedFeatId = mappedFeatIds[oldFeatId];
          if (existingMappedFeatId != null) {
            newFeatIds.add(existingMappedFeatId);
            continue;
          }
          final oldFeat = documents[oldFeatId];
          if (oldFeat == null) continue;
          final newFeatId = '${newBeatId}_feat_${fIdx + 1}';
          mappedFeatIds[oldFeatId] = newFeatId;
          final clonedFeat = oldFeat.copyWith(
            id: newFeatId,
            parentId: newBeatId,
            sections: Map<String, String>.from(oldFeat.sections),
            subtasks: oldFeat.subtasks.map((st) => st.copyWith()).toList(),
          );
          documents[newFeatId] = clonedFeat;
          _persistDocument(clonedFeat);
          newFeatIds.add(newFeatId);
        }

        final newBeatDoc = oldBeat.copyWith(
          id: newBeatId,
          parentId: newRelId,
          childrenIds: newFeatIds,
          sections: Map<String, String>.from(oldBeat.sections),
        );
        documents[newBeatId] = newBeatDoc;
        _persistDocument(newBeatDoc);
        newBeatIds.add(newBeatId);
      }

      final newRelDoc = oldRel.copyWith(
        id: newRelId,
        parentId: newId,
        childrenIds: newBeatIds,
        sections: Map<String, String>.from(oldRel.sections),
      );
      documents[newRelId] = newRelDoc;
      _persistDocument(newRelDoc);
      newReleaseIds.add(newRelId);
    }

    // Clone any superseded/archived features whose parent Beat belongs to this project
    final supersededToClone = documents.values
        .where(
          (d) =>
              d.tier == TierType.feature &&
              !mappedFeatIds.containsKey(d.id) &&
              d.parentId != null &&
              mappedBeatIds.containsKey(d.parentId),
        )
        .toList();
    for (int sIdx = 0; sIdx < supersededToClone.length; sIdx++) {
      final oldSup = supersededToClone[sIdx];
      final newBeatId = mappedBeatIds[oldSup.parentId!]!;
      final newSupId = '${newBeatId}_sup_${sIdx + 1}';
      mappedFeatIds[oldSup.id] = newSupId;
      final clonedSup = oldSup.copyWith(
        id: newSupId,
        parentId: newBeatId,
        sections: Map<String, String>.from(oldSup.sections),
        subtasks: oldSup.subtasks.map((st) => st.copyWith()).toList(),
      );
      documents[newSupId] = clonedSup;
      _persistDocument(clonedSup);
    }

    String remapClonedId(String id) =>
        mappedRelIds[id] ?? mappedBeatIds[id] ?? mappedFeatIds[id] ?? id;

    for (final newRelId in newReleaseIds) {
      final relDoc = documents[newRelId];
      if (relDoc == null) continue;
      final rawRelBp = relDoc.sections['release_blueprint_json'];
      if (rawRelBp != null && rawRelBp.isNotEmpty) {
        relDoc.sections['release_blueprint_json'] =
            _remapSerializedReleaseBlueprintJson(rawRelBp, remapClonedId);
        _persistDocument(relDoc);
      }
    }
    final rawProjRelBp = copiedSections['release_blueprint_json'];
    if (rawProjRelBp != null && rawProjRelBp.isNotEmpty) {
      copiedSections['release_blueprint_json'] =
          _remapSerializedReleaseBlueprintJson(rawProjRelBp, remapClonedId);
    }

    if (newReleaseIds.isNotEmpty) {
      copiedSections['active_release_id'] =
          mappedActiveReleaseId ?? newReleaseIds.first;
    }
    final oldSelectedBeat = copiedSections['selected_beat_id'];
    if (oldSelectedBeat != null && mappedBeatIds.containsKey(oldSelectedBeat)) {
      copiedSections['selected_beat_id'] = mappedBeatIds[oldSelectedBeat]!;
    }
    final oldSelectedFeat = copiedSections['selected_feature_id'];
    if (oldSelectedFeat != null && mappedFeatIds.containsKey(oldSelectedFeat)) {
      copiedSections['selected_feature_id'] = mappedFeatIds[oldSelectedFeat]!;
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

  /// Exports the full interactive state of [projectId] (defaults to [activeProjectId])
  /// across all 4 tiers (`Project`, `Release`, `Epic`, `Feature`, including superseded features,
  /// Concept Blueprint, Release Blueprint, and completed checkpoints) as a portable `.layers.json` bundle.
  String exportProjectToJson([String? projectId]) {
    final targetId = projectId ?? _activeProjectId;
    if (targetId == null) return '';
    if (targetId == _activeProjectId) {
      _syncActiveProjectMetadata();
    }
    final proj = documents[targetId];
    if (proj == null) return '';

    final collectedIds = <String>{proj.id};
    for (final relId in proj.childrenIds) {
      collectedIds.add(relId);
      final relDoc = documents[relId];
      if (relDoc != null) {
        for (final beatId in relDoc.childrenIds) {
          collectedIds.add(beatId);
          final beatDoc = documents[beatId];
          if (beatDoc != null) {
            collectedIds.addAll(beatDoc.childrenIds);
          }
        }
      }
    }
    // Include any detached/superseded Epics or Features belonging to this project
    bool addedMore = true;
    while (addedMore) {
      addedMore = false;
      for (final doc in documents.values) {
        if (!collectedIds.contains(doc.id) &&
            doc.parentId != null &&
            collectedIds.contains(doc.parentId)) {
          collectedIds.add(doc.id);
          addedMore = true;
        }
      }
    }

    final bundleDocs = <Map<String, dynamic>>[
      for (final id in collectedIds)
        if (documents[id] != null) documents[id]!.toJson(),
    ];

    final payload = <String, dynamic>{
      'format': 'layers-agentic-project-v2',
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'projectId': proj.id,
      'projectTitle': proj.title,
      'documents': bundleDocs,
    };

    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  /// Imports a `.layers.json` project bundle into the vault, automatically remapping IDs
  /// if any document ID collides with an existing project in the vault, and switches to the imported project.
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
        if (item is Map<String, dynamic>) {
          parsedDocs.add(TierDocument.fromJson(item));
        } else if (item is Map) {
          parsedDocs.add(
            TierDocument.fromJson(Map<String, dynamic>.from(item)),
          );
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
                cMap['title'] = importedTitle;
                newSections['concept_blueprint_json'] = jsonEncode(cMap);
              } catch (_) {}
            }
          }
          final oldActiveRel = newSections['active_release_id'];
          if (oldActiveRel != null && idMap.containsKey(oldActiveRel)) {
            newSections['active_release_id'] = idMap[oldActiveRel]!;
          }
          final oldSelBeat = newSections['selected_beat_id'];
          if (oldSelBeat != null && idMap.containsKey(oldSelBeat)) {
            newSections['selected_beat_id'] = idMap[oldSelBeat]!;
          }
          final oldSelFeat = newSections['selected_feature_id'];
          if (oldSelFeat != null && idMap.containsKey(oldSelFeat)) {
            newSections['selected_feature_id'] = idMap[oldSelFeat]!;
          }
        }
        if (d.tier == TierType.project || d.tier == TierType.release) {
          final rawRelBp = newSections['release_blueprint_json'];
          if (rawRelBp != null && rawRelBp.isNotEmpty) {
            newSections['release_blueprint_json'] =
                _remapSerializedReleaseBlueprintJson(rawRelBp, remapId);
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
    final proj = documents[projectId];
    if (proj == null) return;

    final idsToRemove = <String>{projectId};
    for (final relId in proj.childrenIds) {
      idsToRemove.add(relId);
      final relDoc = documents[relId];
      if (relDoc != null) {
        for (final beatId in relDoc.childrenIds) {
          idsToRemove.add(beatId);
          final beatDoc = documents[beatId];
          if (beatDoc != null) {
            idsToRemove.addAll(beatDoc.childrenIds);
          }
        }
      }
    }
    // Also collect any detached/superseded child documents whose parentId belongs to this project
    for (final doc in documents.values) {
      if (doc.parentId != null && idsToRemove.contains(doc.parentId)) {
        idsToRemove.add(doc.id);
      }
    }

    final user = _authService.currentUser;
    for (final id in idsToRemove) {
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
  }

  void _restoreProjectState(String projectId) {
    final proj = documents[projectId];
    if (proj == null) return;
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
    if (rawConcept != null && rawConcept.isNotEmpty) {
      try {
        _conceptDraft = ProjectConceptBlueprint.fromJson(
          jsonDecode(rawConcept) as Map<String, dynamic>,
        );
      } catch (e) {
        debugPrint('Restore concept_blueprint_json error: $e');
      }
    }

    // Restore Release Blueprint
    final rawRelBp = proj.sections['release_blueprint_json'];
    if (rawRelBp != null && rawRelBp.isNotEmpty) {
      try {
        _releaseBlueprint = ReleaseBlueprint.fromJson(
          jsonDecode(rawRelBp) as Map<String, dynamic>,
        );
        final ownerRel = documents[_releaseBlueprint!.releaseDocId];
        if (ownerRel != null &&
            (ownerRel.sections['release_blueprint_json'] == null ||
                ownerRel.sections['release_blueprint_json']!.isEmpty)) {
          ownerRel.sections['release_blueprint_json'] = rawRelBp;
        }
      } catch (e) {
        debugPrint('Restore release_blueprint_json error: $e');
      }
    } else {
      _releaseBlueprint = null;
    }

    // Restore active release, beat, and feature
    final savedRelId = proj.sections['active_release_id'];
    if (savedRelId != null && documents.containsKey(savedRelId)) {
      _activeReleaseId = savedRelId;
    } else if (proj.childrenIds.isNotEmpty) {
      _activeReleaseId = proj.childrenIds.first;
    } else {
      _activeReleaseId = null;
    }
    repackProjectReleasesSequentially(proj, pruneAllUnbuilt: true);
    if (_activeReleaseId != null) {
      final activeRelBp = releaseBlueprintFor(_activeReleaseId!);
      if (activeRelBp != null) {
        _releaseBlueprint = activeRelBp;
      }
    }

    final beats = activeReleaseBeats;
    if (beats.isNotEmpty) {
      // Self-heal any cross-Epic duplicate feature ID collisions from prior builds
      final seenFeatIds = <String, String>{}; // featId -> first beatId
      for (int bIdx = 0; bIdx < beats.length; bIdx++) {
        final b = beats[bIdx];
        for (int cIdx = 0; cIdx < b.childrenIds.length; cIdx++) {
          final fid = b.childrenIds[cIdx];
          final firstBeatId = seenFeatIds[fid];
          if (firstBeatId == null) {
            seenFeatIds[fid] = b.id;
          } else if (firstBeatId != b.id) {
            final origDoc = documents[fid];
            if (origDoc != null) {
              final clonedId = 'feat_${b.id}_${cIdx + 1}';
              final distinctTitle =
                  MechanicArchetypeProfile.concreteFeatureTitleForBeat(
                origDoc.title,
                beatTitle: b.title,
                beatGoal: b.sections['scope'] ?? '',
                beatIndex: bIdx,
              );
              final clonedDoc = TierDocument(
                id: clonedId,
                title: distinctTitle,
                tier: TierType.feature,
                parentId: b.id,
                estimatedDuration: origDoc.estimatedDuration,
                sections: Map<String, String>.from(origDoc.sections),
              );
              documents[clonedId] = clonedDoc;
              b.childrenIds[cIdx] = clonedId;
            }
          }
        }
      }

      // Self-heal any single-release v0.1 features that suffered from the duplicate-checkpoint 50% completion bug
      final isInitialV01 = proj.childrenIds.length <= 1 &&
          activeReleaseVersionTag == 'v0.1' &&
          (activeRelease?.sections['prototypePart'] ?? '') != '2';
      if (isInitialV01) {
        for (final b in beats) {
          for (final f in featuresForBeat(b.id)) {
            final states = FeatureStateNode.getStatesForDocument(f);
            if (states.length >= 2 &&
                states.every((s) => s.releaseVersion == 'v0.1')) {
              final cleanNode = !states.last.isCompleted
                  ? states.last
                  : states.first;
              final cleanedTitle = cleanNode.cleanStageTitle;
              final healedNode = FeatureStateNode(
                id: '${f.id}_v0.1_cp_1',
                name: 'Checkpoint 1: $cleanedTitle',
                trigger: cleanNode.trigger,
                order: 0,
                checklist: cleanNode.checklist,
                coveredScope: cleanNode.coveredScope,
                tuningParams: cleanNode.tuningParams,
                edgeCases: cleanNode.edgeCases,
                parameters: Map<String, String>.from(cleanNode.parameters)
                  ..['releaseVersion'] = 'v0.1',
              );
              FeatureStateNode.saveStatesToDocument(f, [healedNode]);
              _persistDocument(f);
            }
          }
        }
      }

      final candidateFeatId = (projectId == _activeProjectId &&
              _selectedFeatureId != null &&
              documents.containsKey(_selectedFeatureId))
          ? _selectedFeatureId
          : proj.sections['selected_feature_id'];
      TierDocument? matchedBeat;
      TierDocument? matchedFeat;
      if (candidateFeatId != null) {
        for (final b in beats) {
          for (final f in featuresForBeat(b.id)) {
            if (f.id == candidateFeatId) {
              matchedBeat = b;
              matchedFeat = f;
              break;
            }
          }
          if (matchedFeat != null) break;
        }
      }
      if (matchedBeat != null && matchedFeat != null) {
        _selectedBeatId = matchedBeat.id;
        _selectedFeatureId = matchedFeat.id;
      } else {
        _selectFirstIncompleteFeatureInActiveRelease();
      }
    } else {
      _selectedBeatId = null;
      _selectedFeatureId = null;
    }

    // Restore Stage & Production Phase
    final activeRel = _activeReleaseId != null ? documents[_activeReleaseId] : null;
    _syncCurrentPhaseFromRelease(activeRel);

    final savedStage = proj.sections['current_stage'];
    if ((savedStage == WorkbenchStage.releaseWorkbench.name ||
            savedStage == 'releasePlanGate') &&
        beats.isNotEmpty) {
      _currentStage = WorkbenchStage.releaseWorkbench;
    } else {
      _currentStage = WorkbenchStage.projectPitch;
    }
  }

  void _syncCurrentPhaseFromRelease(TierDocument? relDoc) {
    if (relDoc == null) {
      _currentPhase = ProductionPhase.prototype;
      return;
    }
    final rawPhase = (relDoc.sections['phase'] ?? '').trim();
    if (rawPhase == ProductionPhase.mvp.name) {
      _currentPhase = ProductionPhase.mvp;
    } else if (rawPhase == ProductionPhase.verticalSlice.name) {
      _currentPhase = ProductionPhase.verticalSlice;
    } else if (rawPhase == ProductionPhase.fullProduction.name) {
      _currentPhase = ProductionPhase.fullProduction;
    } else if (rawPhase == ProductionPhase.prototype.name) {
      _currentPhase = ProductionPhase.prototype;
    } else {
      final scope = relDoc.releaseScope;
      if (scope == ReleaseScope.mvp) {
        _currentPhase = ProductionPhase.mvp;
      } else if (scope == ReleaseScope.verticalSlice) {
        _currentPhase = ProductionPhase.verticalSlice;
      } else if (scope == ReleaseScope.fullProduction) {
        _currentPhase = ProductionPhase.fullProduction;
      } else {
        _currentPhase = ProductionPhase.prototype;
      }
    }
  }

  void _persistDocument(TierDocument doc, {bool debounce = false}) {
    _persistTimers.remove(doc.id)?.cancel();
    void writeNow() {
      LocalVaultService.saveDocument(doc);
      final user = _authService.currentUser;
      if (user != null) {
        _pendingCloudWriteDocIds.add(doc.id);
        _firestoreService.saveDocument(uid: user.uid, doc: doc).whenComplete(() {
          _pendingCloudWriteDocIds.remove(doc.id);
        });
      }
    }

    if (debounce && enableAutoLoad) {
      _persistTimers[doc.id] = Timer(const Duration(milliseconds: 250), () {
        _persistTimers.remove(doc.id);
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
      apiKey: _apiKey,
      modelName: _conversationModel,
      planningModel: _planningModel,
      thinkingLevel: _thinkingLevel,
      themeMode: _isDark ? 'dark' : 'light',
    );
    final user = _authService.currentUser;
    if (user != null) {
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
    if (_selectedBeatId != null) {
      proj.sections['selected_beat_id'] = _selectedBeatId!;
    }
    if (_selectedFeatureId != null) {
      proj.sections['selected_feature_id'] = _selectedFeatureId!;
    }
    if (_conceptDraft != null) {
      proj.sections['concept_blueprint_json'] =
          jsonEncode(_conceptDraft!.toJson());
    }
    if (_releaseBlueprint != null) {
      final bpJson = jsonEncode(_releaseBlueprint!.toJson());
      proj.sections['release_blueprint_json'] = bpJson;
      final relDoc = documents[_releaseBlueprint!.releaseDocId];
      if (relDoc != null &&
          relDoc.sections['release_blueprint_json'] != bpJson) {
        relDoc.sections['release_blueprint_json'] = bpJson;
        _persistDocument(relDoc, debounce: true);
      }
    }
    _persistDocument(proj);
    _persistSettings();
  }
}

import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../constants/tiers.dart';
import '../models/agent_blueprints.dart';
import '../models/epic_spec.dart';
import '../models/tier_document.dart';
import '../utils/unreal_spec_guard.dart';

/// Pure project-tree collector and portable `.layers.json` archive codec
/// for multi-tier (`Project -> Release -> Epic`) vaults.
class ProjectArchiveCodec {
  static const JsonEncoder _prettyJsonEncoder = JsonEncoder.withIndent('  ');

  /// Collects all document IDs belonging to [projectId]'s 3-tier tree.
  static Set<String> collectProjectTreeIds(
    Map<String, TierDocument> documents,
    String projectId,
  ) {
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

  /// Strips sync metadata and updates embedded `epic_spec_json` IDs when cloning or importing.
  static void remapEmbeddedEpicJsonAndClearSync(
    Map<String, String> sections, {
    String? newEpicDocId,
    required bool clearSyncMetadata,
  }) {
    if (clearSyncMetadata) {
      sections.remove('dimension');
      sections.remove('last_godot_sync_ms');
      sections.remove('godot_live_context_json');
      sections.remove('collaborators_json');
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

  /// Auto-migrates legacy archive or vault documents in-place into clean Unreal Engine 5 specs
  /// while preserving existing timestamps (`updated_at_ms`) and returns migrated document IDs.
  static Set<String> migrateDocumentMapToUnreal(Map<String, TierDocument> docs) {
    final migratedIds = <String>{};
    final projectModes = <String, UnrealArchitectureMode>{};

    // Pass 1: Sanitize Project blueprints, strip legacy dimension/sync keys, and track mode.
    for (final id in docs.keys.toList()) {
      final doc = docs[id];
      if (doc == null || doc.tier != TierType.project) continue;
      final rawConcept = doc.sections['concept_blueprint_json'];
      var mode = UnrealArchitectureMode.fromString(doc.sections['dimension']);
      Map<String, dynamic>? decodedConcept;
      if (rawConcept != null && rawConcept.trim().isNotEmpty) {
        try {
          final raw = jsonDecode(rawConcept);
          if (raw is Map) {
            decodedConcept = Map<String, dynamic>.from(raw);
            mode = ProjectConceptBlueprint.fromJson(decodedConcept).architectureMode;
          }
        } catch (_) {}
      }
      projectModes[id] = mode;

      final needsMig = doc.sections.containsKey('dimension') ||
          doc.sections.containsKey('last_godot_sync_ms') ||
          doc.sections.containsKey('godot_live_context_json') ||
          UnrealSpecGuard.containsEngineLeakage(doc.title) ||
          (rawConcept != null &&
              (rawConcept.contains('"dimension"') ||
                  UnrealSpecGuard.containsEngineLeakage(rawConcept)));
      if (!needsMig) continue;

      final nextSections = Map<String, String>.from(doc.sections)
        ..remove('dimension')
        ..remove('last_godot_sync_ms')
        ..remove('godot_live_context_json');
      if (decodedConcept != null) {
        try {
          final bp = ProjectConceptBlueprint.fromJson(decodedConcept);
          final cleanBp = UnrealSpecGuard.sanitizeConceptBlueprint(raw: bp);
          mode = cleanBp.architectureMode;
          projectModes[id] = mode;
          nextSections['concept_blueprint_json'] = jsonEncode(cleanBp.toJson());
        } catch (_) {}
      }
      final cleanTitle = UnrealSpecGuard.sanitizeLine(doc.title, mode: mode).trim();
      docs[id] = doc.copyWith(
        title: cleanTitle.isEmpty ? doc.title : cleanTitle,
        sections: nextSections,
      );
      migratedIds.add(id);
    }

    final epicModes = <String, UnrealArchitectureMode>{};
    for (final entry in projectModes.entries) {
      for (final treeId in collectProjectTreeIds(docs, entry.key)) {
        epicModes[treeId] = entry.value;
      }
    }

    // Pass 2: Strip legacy metadata from Release documents.
    for (final id in docs.keys.toList()) {
      final doc = docs[id];
      if (doc == null || doc.tier != TierType.release) continue;
      if (!doc.sections.containsKey('dimension') &&
          !doc.sections.containsKey('last_godot_sync_ms') &&
          !doc.sections.containsKey('godot_live_context_json')) {
        continue;
      }
      final nextSections = Map<String, String>.from(doc.sections)
        ..remove('dimension')
        ..remove('last_godot_sync_ms')
        ..remove('godot_live_context_json');
      docs[id] = doc.copyWith(sections: nextSections);
      migratedIds.add(id);
    }

    // Pass 3: Sanitize Epic & embedded Feature specs while preserving existing updated_at_ms.
    for (final id in docs.keys.toList()) {
      final doc = docs[id];
      if (doc == null || doc.tier != TierType.epic) continue;
      final rawSpec = doc.sections['epic_spec_json'];
      final rawGoal = doc.sections['goal'];
      final needsMig = doc.sections.containsKey('dimension') ||
          doc.sections.containsKey('last_godot_sync_ms') ||
          doc.sections.containsKey('godot_live_context_json') ||
          UnrealSpecGuard.containsEngineLeakage(doc.title) ||
          (rawSpec != null && UnrealSpecGuard.containsEngineLeakage(rawSpec)) ||
          (rawGoal != null && UnrealSpecGuard.containsEngineLeakage(rawGoal));
      if (!needsMig) continue;

      final mode = epicModes[id] ?? UnrealArchitectureMode.blueprint;
      final parsed = EpicSpec.fromDocument(doc);
      final cleanSpec = UnrealSpecGuard.sanitizeEpicSpec(parsed, mode: mode);
      final updated = cleanSpec.applyToDocument(doc, preserveTimestamp: true);
      final cleanedSections = Map<String, String>.from(updated.sections)
        ..remove('dimension')
        ..remove('last_godot_sync_ms')
        ..remove('godot_live_context_json');
      docs[id] = updated.copyWith(sections: cleanedSections);
      migratedIds.add(id);
    }

    return migratedIds;
  }

  /// Deep-clones an existing 3-tier project tree without mutating [documents].
  static ({String newProjectId, List<TierDocument> docsToSave})?
      cloneProjectTree({
    required Map<String, TierDocument> documents,
    required String projectId,
    required List<TierDocument> Function(String) releaseDocsForProject,
    required List<TierDocument> Function(String) epicDocsForRelease,
  }) {
    final src = documents[projectId];
    if (src == null) return null;

    final newId = 'proj_${DateTime.now().microsecondsSinceEpoch}';
    final copyTitle = '${src.title} (Copy)';
    final copiedSections = Map<String, String>.from(src.sections);
    remapEmbeddedEpicJsonAndClearSync(copiedSections, clearSyncMetadata: true);

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

    final docsToSave = <TierDocument>[];
    final newReleaseIds = <String>[];
    String? mappedActiveReleaseId;
    final mappedEpicIds = <String, String>{};

    final srcReleases = releaseDocsForProject(src.id);
    for (int rIdx = 0; rIdx < srcReleases.length; rIdx++) {
      final oldRel = srcReleases[rIdx];
      final oldRelId = oldRel.id;
      final newRelId = '${newId}_rel_${rIdx + 1}';
      if (copiedSections['active_release_id'] == oldRelId) {
        mappedActiveReleaseId = newRelId;
      }

      final newEpicIds = <String>[];
      final srcEpics = epicDocsForRelease(oldRelId);
      for (int eIdx = 0; eIdx < srcEpics.length; eIdx++) {
        final oldEpic = srcEpics[eIdx];
        final oldEpicId = oldEpic.id;
        final existingMapped = mappedEpicIds[oldEpicId];
        if (existingMapped != null) {
          newEpicIds.add(existingMapped);
          continue;
        }
        final newEpicId = '${newRelId}_epic_${eIdx + 1}';
        mappedEpicIds[oldEpicId] = newEpicId;
        final epicSections = Map<String, String>.from(oldEpic.sections);
        remapEmbeddedEpicJsonAndClearSync(
          epicSections,
          newEpicDocId: newEpicId,
          clearSyncMetadata: true,
        );
        final clonedEpic = oldEpic.copyWith(
          id: newEpicId,
          parentId: newRelId,
          sections: epicSections,
          subtasks: oldEpic.subtasks.map((st) => st.copyWith()).toList(),
        );
        docsToSave.add(clonedEpic);
        newEpicIds.add(newEpicId);
      }

      final relSections = Map<String, String>.from(oldRel.sections);
      remapEmbeddedEpicJsonAndClearSync(relSections, clearSyncMetadata: true);
      final newRelDoc = oldRel.copyWith(
        id: newRelId,
        parentId: newId,
        childrenIds: newEpicIds,
        sections: relSections,
      );
      docsToSave.add(newRelDoc);
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
    docsToSave.add(copyDoc);
    return (newProjectId: newId, docsToSave: docsToSave);
  }

  /// Serializes [projectId]'s 3-tier tree into a portable `.layers.json` string.
  static String encodeProjectJson({
    required Map<String, TierDocument> documents,
    required String projectId,
  }) {
    final proj = documents[projectId];
    if (proj == null) return '';

    final collectedIds = collectProjectTreeIds(documents, proj.id);
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

  /// Decodes a `.layers.json` bundle, scopes reachable project docs, and remaps IDs on collision.
  static ({String importedProjectId, List<TierDocument> docsToSave})?
      decodeProjectJson({
    required String rawJson,
    required Set<String> existingDocIds,
  }) {
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

      final rootProj =
          parsedDocs.where((d) => d.tier == TierType.project).firstOrNull;
      if (rootProj == null) return null;

      final parsedById = <String, TierDocument>{
        for (final d in parsedDocs) d.id: d,
      };
      final childrenByParent = <String, List<String>>{};
      for (final d in parsedDocs) {
        if (d.parentId != null && d.parentId!.isNotEmpty) {
          childrenByParent.putIfAbsent(d.parentId!, () => []).add(d.id);
        }
      }
      final reachableIds = <String>{rootProj.id};
      final queue = <String>[rootProj.id];
      while (queue.isNotEmpty) {
        final curId = queue.removeLast();
        final curDoc = parsedById[curId];
        if (curDoc != null) {
          for (final cid in curDoc.childrenIds) {
            if (parsedById.containsKey(cid) && reachableIds.add(cid)) {
              queue.add(cid);
            }
          }
        }
        final directChildren = childrenByParent[curId];
        if (directChildren != null) {
          for (final cid in directChildren) {
            if (parsedById.containsKey(cid) && reachableIds.add(cid)) {
              queue.add(cid);
            }
          }
        }
      }
      final scopedDocs = <TierDocument>[
        for (final d in parsedDocs)
          if (reachableIds.contains(d.id)) d,
      ];

      final hasCollision = scopedDocs.any((d) => existingDocIds.contains(d.id));
      final idMap = <String, String>{};
      final baseTs = DateTime.now().microsecondsSinceEpoch;
      if (hasCollision) {
        for (int i = 0; i < scopedDocs.length; i++) {
          final d = scopedDocs[i];
          if (d.tier == TierType.project) {
            idMap[d.id] = 'proj_${baseTs}_$i';
          } else {
            idMap[d.id] = '${d.tier.name}_${baseTs}_$i';
          }
        }
      } else {
        for (final d in scopedDocs) {
          idMap[d.id] = d.id;
        }
      }

      String remapId(String id) => idMap[id] ?? id;

      final docsToSave = <TierDocument>[];
      for (final d in scopedDocs) {
        final newId = remapId(d.id);
        final newParentId = d.parentId != null ? remapId(d.parentId!) : null;
        final newChildrenIds = d.childrenIds.map(remapId).toList();
        final newSections = Map<String, String>.from(d.sections);

        remapEmbeddedEpicJsonAndClearSync(
          newSections,
          newEpicDocId: d.tier == TierType.epic ? newId : null,
          clearSyncMetadata: true,
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

        docsToSave.add(
          d.copyWith(
            id: newId,
            title: importedTitle,
            parentId: newParentId,
            childrenIds: newChildrenIds,
            sections: newSections,
          ),
        );
      }

      final migratedMap = <String, TierDocument>{
        for (final d in docsToSave) d.id: d,
      };
      migrateDocumentMapToUnreal(migratedMap);
      return (
        importedProjectId: remapId(rootProj.id),
        docsToSave: [for (final d in docsToSave) migratedMap[d.id]!],
      );
    } catch (e) {
      debugPrint('decodeProjectJson error: $e');
      return null;
    }
  }

  /// Decodes the collaborator email/role list persisted in a project's `collaborators_json` section.
  static List<Map<String, String>>? decodeCollaborators(String? rawJson) {
    if (rawJson == null || rawJson.isEmpty) return null;
    try {
      final decoded = jsonDecode(rawJson) as List<dynamic>;
      return <Map<String, String>>[
        for (final item in decoded)
          if (item is Map)
            {
              'email': (item['email'] ?? '').toString(),
              'role': (item['role'] ?? 'editor').toString(),
            },
      ];
    } catch (_) {
      return null;
    }
  }
}

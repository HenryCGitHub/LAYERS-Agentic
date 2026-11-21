import '../constants/tiers.dart';
import '../models/agent_blueprints.dart';
import '../models/epic_spec.dart';
import '../models/tier_document.dart';

/// Pure Stage 1 -> Stage 2 `v0.1` Release seeding, Feature ID/code allocation,
/// and non-destructive Epic/Feature slice reconciliation helper.
class V01ReleaseSeeder {
  /// Ensures unique `F01..FNN` codes and non-colliding IDs across [specs],
  /// respecting [reservedCodesLower] from other releases.
  static void assignUniqueFeatureIdsAndCodes(
    List<EpicSpec> specs, {
    Set<String> reservedCodesLower = const {},
  }) {
    final usedCodesLower = Set<String>.from(reservedCodesLower);
    final usedIds = <String>{};
    int maxNum = 0;
    final codeRx = RegExp(r'^F(\d+)$', caseSensitive: false);
    for (final cLower in usedCodesLower) {
      final m = codeRx.firstMatch(cLower);
      final n = int.tryParse(m?.group(1) ?? '') ?? 0;
      if (n > maxNum) maxNum = n;
    }
    for (final spec in specs) {
      for (final f in spec.features) {
        final m = codeRx.firstMatch(f.code.trim());
        final n = int.tryParse(m?.group(1) ?? '') ?? 0;
        if (n > maxNum) maxNum = n;
      }
    }
    String nextUnusedCode() {
      do {
        maxNum++;
      } while (usedCodesLower
          .contains(FeatureSpec.formatCode(maxNum).toLowerCase()));
      final next = FeatureSpec.formatCode(maxNum);
      usedCodesLower.add(next.toLowerCase());
      return next;
    }

    for (final spec in specs) {
      for (int i = 0; i < spec.features.length; i++) {
        var feat = spec.features[i];
        final cClean = feat.code.trim();
        if (cClean.isEmpty || !usedCodesLower.add(cClean.toLowerCase())) {
          feat.code = nextUnusedCode();
        }
        final fid = feat.id.trim();
        if (fid.isEmpty ||
            FeatureSpec.isPositionalFallbackFeatureId(fid) ||
            !usedIds.add(fid)) {
          var candId = '${spec.id}_${feat.code.toLowerCase()}';
          var sfx = 2;
          while (usedIds.contains(candId)) {
            candId = '${spec.id}_${feat.code.toLowerCase()}_$sfx';
            sfx++;
          }
          feat = feat.deepCopy(idOverride: candId);
          spec.features[i] = feat;
          usedIds.add(feat.id);
        }
      }
    }
  }

  /// Merges [incoming] Feature slices with [existing] Playtest checks, `[FIX]` notes,
  /// passed statuses, and custom Stage 2 slices.
  static List<FeatureSpec> reconcileFeatureSlices({
    required List<FeatureSpec> incoming,
    required List<FeatureSpec> existing,
  }) {
    if (existing.isEmpty) return [for (final f in incoming) f.deepCopy()];
    final matched = List<bool>.filled(existing.length, false);
    int? findMatch(FeatureSpec inc) {
      if (inc.id.isNotEmpty &&
          !FeatureSpec.isPositionalFallbackFeatureId(inc.id)) {
        for (int i = 0; i < existing.length; i++) {
          if (!matched[i] && existing[i].id == inc.id) return i;
        }
      }
      final incTitle = inc.title.trim().toLowerCase();
      if (incTitle.isNotEmpty) {
        for (int i = 0; i < existing.length; i++) {
          if (!matched[i] &&
              existing[i].title.trim().toLowerCase() == incTitle) {
            return i;
          }
        }
      }
      final incCode = inc.code.trim().toLowerCase();
      if (incCode.isNotEmpty) {
        for (int i = 0; i < existing.length; i++) {
          if (!matched[i] &&
              existing[i].code.trim().toLowerCase() == incCode) {
            return i;
          }
        }
      }
      return null;
    }

    final result = <FeatureSpec>[];
    for (final inc in incoming) {
      final mIdx = findMatch(inc);
      if (mIdx == null) {
        result.add(inc.deepCopy());
        continue;
      }
      matched[mIdx] = true;
      final oldFeat = existing[mIdx];
      if (oldFeat.isPassed) {
        result.add(oldFeat.deepCopy());
        continue;
      }
      final mergedFeat = inc.deepCopy(
        idOverride: oldFeat.id,
        codeOverride: oldFeat.code,
        statusOverride: oldFeat.status,
      );
      mergedFeat.fixes = [for (final fx in oldFeat.fixes) fx.copyWith()];
      for (final chk in [...mergedFeat.checks, ...mergedFeat.releaseDeltaChecks]) {
        final wasPassed = [...oldFeat.checks, ...oldFeat.releaseDeltaChecks].any(
          (old) =>
              old.passed &&
              (old.id == chk.id ||
                  old.text.trim().toLowerCase() ==
                      chk.text.trim().toLowerCase()),
        );
        if (wasPassed) chk.passed = true;
      }
      result.add(mergedFeat);
    }

    // Preserve user-added custom slices created in Stage 2
    for (int i = 0; i < existing.length; i++) {
      if (!matched[i]) {
        result.add(existing[i].deepCopy());
      }
    }
    return result;
  }

  /// Materializes or reconciles the `v0.1 · Prototype` release document and its
  /// child `EpicSpec` documents without touching storage or Firestore directly.
  static ({
    String releaseId,
    TierDocument releaseDoc,
    List<TierDocument> epicDocsToSave,
    List<String> removedDocIds,
    List<EpicSpec>? reconciledInitialEpics,
  }) buildOrReconcileV01Release({
    required String projectId,
    required ProjectConceptBlueprint draft,
    TierDocument? existingV01Release,
    required List<TierDocument> existingDocs,
    required Set<String> reservedCodesLower,
  }) {
    final relId = existingV01Release?.id ?? '${projectId}_rel_v01';
    final epicIds = <String>[];
    final epicDocsToSave = <TierDocument>[];
    final removedDocIds = <String>[];
    List<EpicSpec>? reconciledInitialEpics;

    if (existingV01Release == null || existingDocs.isEmpty) {
      final createdSpecs = <EpicSpec>[];
      for (int i = 0; i < draft.initialEpics.length; i++) {
        final rawEpic = draft.initialEpics[i];
        final epId = '${relId}_epic_${i + 1}';
        final cleanEpic = rawEpic.deepCopy(
          idOverride: epId,
          releaseVersionOverride: 'v0.1',
          lifecycleOverride:
              i == 0 ? EpicLifecycle.active : EpicLifecycle.queued,
        );
        cleanEpic.code = 'E${(i + 1).toString().padLeft(2, '0')}';
        cleanEpic.lineageKey = rawEpic.lineageKey.trim().isEmpty
            ? EpicSpec.formatLineageKey(i + 1)
            : rawEpic.lineageKey.trim();
        createdSpecs.add(cleanEpic);
      }
      assignUniqueFeatureIdsAndCodes(
        createdSpecs,
        reservedCodesLower: reservedCodesLower,
      );
      for (final cleanEpic in createdSpecs) {
        final epDoc = cleanEpic.toTierDocument(
          docId: cleanEpic.id,
          parentReleaseId: relId,
        );
        epicDocsToSave.add(epDoc);
        epicIds.add(cleanEpic.id);
      }
    } else {
      final existingSpecs = [
        for (int i = 0; i < existingDocs.length; i++)
          EpicSpec.fromDocument(existingDocs[i], indexHint: i),
      ];
      final matched = List<bool>.filled(existingDocs.length, false);

      int? findMatchIdx(EpicSpec incoming) {
        final inKey = incoming.lineageKey.trim().toLowerCase();
        if (inKey.isNotEmpty) {
          for (int j = 0; j < existingSpecs.length; j++) {
            if (!matched[j] &&
                existingSpecs[j].lineageKey.trim().toLowerCase() == inKey) {
              return j;
            }
          }
        }
        for (int j = 0; j < existingDocs.length; j++) {
          if (!matched[j] && existingDocs[j].id == incoming.id) {
            return j;
          }
        }
        final inTitle = incoming.title.trim().toLowerCase();
        if (inTitle.isNotEmpty) {
          for (int j = 0; j < existingSpecs.length; j++) {
            if (!matched[j] &&
                existingSpecs[j].title.trim().toLowerCase() == inTitle) {
              return j;
            }
          }
        }
        return null;
      }

      final reconciledSpecs = <EpicSpec>[];
      final reconciledBaseDocs = <TierDocument?>[];

      for (int i = 0; i < draft.initialEpics.length; i++) {
        final incoming = draft.initialEpics[i];
        final matchIdx = findMatchIdx(incoming);
        if (matchIdx != null) {
          matched[matchIdx] = true;
          final existingDoc = existingDocs[matchIdx];
          final existingSpec = existingSpecs[matchIdx];
          if (existingSpec.isPassed) {
            reconciledSpecs.add(existingSpec.deepCopy(idOverride: existingDoc.id));
            reconciledBaseDocs.add(existingDoc);
          } else {
            final merged = incoming.deepCopy(
              idOverride: existingDoc.id,
              releaseVersionOverride: 'v0.1',
              lifecycleOverride: existingSpec.lifecycle,
            );
            merged.fixes = [for (final f in existingSpec.fixes) f.copyWith()];
            merged.baselineSummary = List<String>.from(existingSpec.baselineSummary);
            merged.upgradeDeltas = List<String>.from(existingSpec.upgradeDeltas);
            for (final check in merged.checks) {
              final wasPassed = existingSpec.checks.any(
                (old) =>
                    old.passed &&
                    (old.id == check.id ||
                        old.text.trim().toLowerCase() ==
                            check.text.trim().toLowerCase()),
              );
              if (wasPassed) check.passed = true;
            }
            merged.features = reconcileFeatureSlices(
              incoming: merged.features,
              existing: existingSpec.features,
            );
            reconciledSpecs.add(merged);
            reconciledBaseDocs.add(existingDoc);
          }
        } else {
          final newEpId =
              '${relId}_epic_${DateTime.now().microsecondsSinceEpoch}_$i';
          final created = incoming.deepCopy(
            idOverride: newEpId,
            releaseVersionOverride: 'v0.1',
          );
          if (created.lineageKey.trim().isEmpty) {
            created.lineageKey = 'epic_${reconciledSpecs.length + 1}';
          }
          reconciledSpecs.add(created);
          reconciledBaseDocs.add(null);
        }
      }

      for (int j = 0; j < existingDocs.length; j++) {
        if (matched[j]) continue;
        final existingDoc = existingDocs[j];
        final existingSpec = existingSpecs[j];
        if (existingSpec.isPassed ||
            existingSpec.openFixes.isNotEmpty ||
            existingSpec.totalOpenFeatureFixes() > 0 ||
            existingSpec.passedChecksCount > 0 ||
            existingSpec.features.any(
              (f) => f.isPassed || f.checks.any((c) => c.passed),
            )) {
          reconciledSpecs.add(existingSpec.deepCopy(idOverride: existingDoc.id));
          reconciledBaseDocs.add(existingDoc);
        } else {
          removedDocIds.add(existingDoc.id);
        }
      }

      bool assignedActive = false;
      final usedLineageKeys = <String>{};
      int nextLineageOrd = 1;
      for (int i = 0; i < reconciledSpecs.length; i++) {
        final spec = reconciledSpecs[i];
        spec.code = 'E${(i + 1).toString().padLeft(2, '0')}';
        var lk = spec.lineageKey.trim().toLowerCase();
        if (lk.isEmpty || usedLineageKeys.contains(lk)) {
          while (usedLineageKeys
              .contains(EpicSpec.formatLineageKey(nextLineageOrd))) {
            nextLineageOrd++;
          }
          lk = EpicSpec.formatLineageKey(nextLineageOrd);
        }
        spec.lineageKey = lk;
        usedLineageKeys.add(lk);
        if (!spec.isPassed &&
            spec.lifecycle != EpicLifecycle.upgrading &&
            spec.lifecycle != EpicLifecycle.newEpic) {
          if (!assignedActive) {
            spec.lifecycle = EpicLifecycle.active;
            assignedActive = true;
          } else {
            spec.lifecycle = EpicLifecycle.queued;
          }
        }
      }

      assignUniqueFeatureIdsAndCodes(
        reconciledSpecs,
        reservedCodesLower: reservedCodesLower,
      );
      for (int i = 0; i < reconciledSpecs.length; i++) {
        final spec = reconciledSpecs[i];
        final baseDoc = reconciledBaseDocs[i];
        final updatedDoc = baseDoc != null
            ? spec.applyToDocument(baseDoc)
            : spec.toTierDocument(docId: spec.id, parentReleaseId: relId);
        epicDocsToSave.add(updatedDoc);
        epicIds.add(updatedDoc.id);
      }

      reconciledInitialEpics = [for (final s in reconciledSpecs) s.deepCopy()];
    }

    final releaseDoc = TierDocument(
      id: relId,
      title: existingV01Release?.title ?? 'v0.1 · Prototype',
      tier: TierType.release,
      parentId: projectId,
      childrenIds: epicIds,
      estimatedDuration: '${epicIds.length} Epics',
      sections: <String, String>{
        if (existingV01Release != null) ...existingV01Release.sections,
        'release_version': 'v0.1',
        'goal': draft.pitch,
        'doneWhen': draft.releaseDoneWhen,
      },
    );

    return (
      releaseId: relId,
      releaseDoc: releaseDoc,
      epicDocsToSave: epicDocsToSave,
      removedDocIds: removedDocIds,
      reconciledInitialEpics: reconciledInitialEpics,
    );
  }
}

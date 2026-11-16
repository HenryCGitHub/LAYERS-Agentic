part of 'workbench_provider.dart';

/// Stage 2 actions: Release switching, Epic selection, live `§04` tuning,
/// `§06` PIE Acceptance Checkboxes, Flag `[FIX]` / Resolve, and `Pass Epic ✓`.
extension WorkbenchReleaseMixin on WorkbenchProvider {
  void selectActiveRelease(String releaseId) {
    final rel = documents[releaseId];
    if (rel == null || rel.tier != TierType.release) return;
    _activeReleaseId = rel.id;
    final epics = epicDocsForRelease(rel.id);
    if (epics.isEmpty) {
      _selectedEpicId = null;
    } else {
      final firstUnpassed = epics.firstWhere(
        (d) => !EpicSpec.fromDocument(d).isPassed,
        orElse: () => epics.first,
      );
      _selectedEpicId = firstUnpassed.id;
    }
    _syncActiveProjectMetadata();
    notifyListeners();
  }

  void selectEpic(String epicId) {
    final doc = documents[epicId];
    if (doc == null || doc.tier != TierType.epic) return;
    if (doc.parentId != null && doc.parentId != _activeReleaseId) {
      _activeReleaseId = doc.parentId;
    }
    _selectedEpicId = epicId;
    _syncActiveProjectMetadata();
    notifyListeners();
  }

  void _updateAndPersistEpic(
    String epicId,
    void Function(EpicSpec spec) mutate, {
    bool debounce = false,
  }) {
    final doc = documents[epicId];
    if (doc == null || doc.tier != TierType.epic) return;
    final idx = activeReleaseEpicDocs.indexWhere((d) => d.id == epicId);
    final spec = EpicSpec.fromDocument(doc, indexHint: idx >= 0 ? idx : 0);
    mutate(spec);
    final updatedDoc = spec.applyToDocument(doc);
    documents[epicId] = updatedDoc;
    _persistDocument(updatedDoc, debounce: debounce);
    notifyListeners();
  }

  void togglePieCheck(String epicId, String checkId, [bool? value]) {
    _updateAndPersistEpic(epicId, (spec) {
      for (final c in spec.checks) {
        if (c.id == checkId) {
          c.passed = value ?? !c.passed;
          break;
        }
      }
      final anyUnchecked = spec.checks.any((c) => !c.passed);
      if (spec.lifecycle == EpicLifecycle.queued) {
        spec.lifecycle = EpicLifecycle.active;
      } else if (spec.lifecycle == EpicLifecycle.stable && anyUnchecked) {
        spec.lifecycle = spec.upgradeDeltas.isNotEmpty
            ? EpicLifecycle.upgrading
            : EpicLifecycle.active;
      }
    });
  }

  void updateEpicTuningParam(String epicId, int paramIndex, String newValue) {
    _updateAndPersistEpic(
      epicId,
      (spec) {
        if (paramIndex >= 0 && paramIndex < spec.tuning.length) {
          spec.tuning[paramIndex].value = newValue.trim();
        }
      },
      debounce: true,
    );
  }

  void addEpicTuningParam(
    String epicId, {
    required String key,
    required String value,
    required String unit,
  }) {
    final cleanKey = UnrealSpecGuard.sanitizeTuningKey(key, fallback: '');
    if (cleanKey.isEmpty) return;
    _updateAndPersistEpic(epicId, (spec) {
      final nextVal = value.trim().isEmpty ? '0' : value.trim();
      final existingIdx = spec.tuning.indexWhere(
        (t) => t.key.trim().toLowerCase() == cleanKey.toLowerCase(),
      );
      if (existingIdx >= 0) {
        final existing = spec.tuning[existingIdx];
        existing.value = nextVal;
        existing.unit = UnrealSpecGuard.normalizeUnrealUnit(
          existing.key,
          unit.trim().isEmpty ? existing.unit : unit,
        );
      } else {
        spec.tuning.add(
          EpicTuningParam(
            key: cleanKey,
            value: nextVal,
            unit: UnrealSpecGuard.normalizeUnrealUnit(cleanKey, unit),
          ),
        );
      }
    });
  }

  void updateEpicSections(
    String epicId, {
    String? title,
    String? goal,
    String? levelStaging,
  }) {
    _updateAndPersistEpic(
      epicId,
      (spec) {
        if (title != null && title.trim().isNotEmpty) {
          spec.title = UnrealSpecGuard.sanitizeLine(title);
        }
        if (goal != null) spec.goal = UnrealSpecGuard.sanitizeLine(goal);
        if (levelStaging != null) {
          spec.levelStaging = UnrealSpecGuard.sanitizeLine(levelStaging);
        }
      },
      debounce: true,
    );
  }

  void flagEpicFix(String epicId, String fixText) {
    final clean = fixText.trim();
    if (clean.isEmpty) return;
    _updateAndPersistEpic(epicId, (spec) {
      spec.fixes.add(
        EpicPieFix(
          id: 'fix_${DateTime.now().microsecondsSinceEpoch}',
          text: UnrealSpecGuard.sanitizeLine(clean),
          resolved: false,
        ),
      );
      if (spec.lifecycle == EpicLifecycle.stable ||
          spec.lifecycle == EpicLifecycle.queued) {
        spec.lifecycle = spec.upgradeDeltas.isNotEmpty
            ? EpicLifecycle.upgrading
            : EpicLifecycle.active;
      }
    });
  }

  void resolveEpicFix(String epicId, String fixId, {bool resolved = true}) {
    _updateAndPersistEpic(epicId, (spec) {
      for (final f in spec.fixes) {
        if (f.id == fixId) {
          f.resolved = resolved;
          break;
        }
      }
    });
  }

  void deleteEpicFix(String epicId, String fixId) {
    _updateAndPersistEpic(epicId, (spec) {
      spec.fixes.removeWhere((f) => f.id == fixId);
    });
  }

  void passActiveEpic(String epicId) {
    _updateAndPersistEpic(epicId, (spec) {
      for (final f in spec.fixes) {
        f.resolved = true;
      }
      for (final c in spec.checks) {
        c.passed = true;
      }
      spec.lifecycle = EpicLifecycle.stable;
    });
    selectNextUnfinishedEpic();
  }

  void reopenEpic(String epicId) {
    _updateAndPersistEpic(epicId, (spec) {
      if (spec.upgradeDeltas.isNotEmpty) {
        spec.lifecycle = EpicLifecycle.upgrading;
        final verLower = spec.releaseVersion.trim().toLowerCase();
        final deltaChecks = spec.checks.where((c) {
          final t = c.text.trim().toLowerCase();
          return c.id.contains('_delta_') ||
              (verLower.isNotEmpty
                  ? t.startsWith('verify $verLower delta')
                  : t.contains('delta:'));
        }).toList();
        if (deltaChecks.isNotEmpty) {
          for (final c in deltaChecks) {
            c.passed = false;
          }
          return;
        }
      } else {
        spec.lifecycle = EpicLifecycle.active;
      }
      for (final c in spec.checks) {
        c.passed = false;
      }
    });
  }

  void selectNextUnfinishedEpic() {
    final epics = activeReleaseEpics;
    if (epics.isEmpty) return;
    for (final ep in epics) {
      if (!ep.isPassed) {
        _selectedEpicId = ep.id;
        _syncActiveProjectMetadata();
        notifyListeners();
        return;
      }
    }
  }
}

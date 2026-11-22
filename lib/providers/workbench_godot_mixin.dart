part of 'workbench_provider.dart';

/// Project markdown and context compilation helpers (migrated to CoPilot mixin in Round 3).
extension WorkbenchGodotMixin on WorkbenchProvider {
  String get activeRootGodotMarkdown {
    final spec = _conceptDraft;
    if (spec == null) {
      return '# ROOT_GODOT_CONTEXT\nNo Project Spec drafted yet.';
    }
    return GodotContextBuilder.buildRootGodotContext(spec);
  }

  String activeEpicGodotContext(EpicSpec epic) {
    final spec = _conceptDraft ??
        ProjectConceptBlueprint(
          gameTitle: activeProject?.title ?? 'LAYERS PROJECT',
        );
    return GodotContextBuilder.buildEpicGodotContext(
      rootSpec: spec,
      epic: epic,
      releaseEpics: activeReleaseEpics,
    );
  }

  /// Returns the 4-tier context for the selected Project, Epic, or Feature.
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
      ),
    );
  }
}

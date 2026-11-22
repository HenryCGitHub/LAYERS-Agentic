part of 'workbench_provider.dart';

/// Ultimate Engine CoPilot GDD & Feature / `[FIX]` prompt export helpers.
extension WorkbenchCopilotMixin on WorkbenchProvider {
  UnrealArchitectureMode get unrealArchitectureMode {
    if (_conceptDraft != null) {
      return _conceptDraft!.architectureMode;
    }
    final raw = activeProject?.sections['unreal_arch_mode'];
    if (raw != null && raw.trim().isNotEmpty) {
      return UnrealArchitectureMode.fromString(raw);
    }
    return UnrealArchitectureMode.blueprint;
  }

  String get activeRootUnrealMarkdown {
    final spec = _conceptDraft;
    if (spec == null) {
      return '# ROOT_UNREAL_CONTEXT\nNo Project Spec drafted yet.';
    }
    return UnrealContextBuilder.buildRootUnrealContext(
      spec,
      mode: unrealArchitectureMode,
    );
  }

  /// Returns the CoPilot context prompt for the selected Project, Epic, or Feature.
  String activeCoPilotPrompt({
    EpicSpec? epicOverride,
    FeatureSpec? featureOverride,
  }) {
    final epic = epicOverride ?? selectedEpicSpec;
    if (epic == null) {
      return activeRootUnrealMarkdown;
    }
    final feat = featureOverride ??
        (epicOverride == null ? selectedFeatureSpec : null);
    if (feat != null) {
      return activeFeatureBuildPrompt(epic, feat);
    }
    return activeEpicArchitecturePrompt(epic);
  }

  /// Builds filename + Ultimate Engine CoPilot GDD Markdown (`*_copilot_gdd.md`).
  ({String filename, String content}) buildCoPilotGddExport() {
    final rootSpec = _conceptDraft ??
        ProjectConceptBlueprint(
          gameTitle: activeProject?.title ?? 'layers_project',
        );
    final epicsByRelease = <String, List<EpicSpec>>{
      for (final rel in projectReleases)
        releaseDisplayName(rel): epicsForRelease(rel.id),
    };
    return (
      filename: buildCoPilotGddFilename(rootSpec.normalizedTitle),
      content: UnrealContextBuilder.buildCoPilotGddMarkdown(
        rootSpec: rootSpec,
        epicsByReleaseLabel: epicsByRelease,
        mode: unrealArchitectureMode,
      ),
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
      content: UnrealContextBuilder.buildFullProjectSpecMarkdown(
        rootSpec: rootSpec,
        epicsByReleaseLabel: epicsByRelease,
        mode: unrealArchitectureMode,
      ),
    );
  }
}

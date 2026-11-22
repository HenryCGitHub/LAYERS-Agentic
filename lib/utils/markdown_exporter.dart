/// Cross-platform file export gateway.
///
/// Conditionally routes to modern Dart 3 `dart:js_interop` DOM anchor download
/// implementation on Flutter Web, or falls back to the safe stub on native platforms.
library;

export 'markdown_exporter_stub.dart'
    if (dart.library.js_interop) 'markdown_exporter_web.dart';

/// Sanitizes an arbitrary project title into a clean cross-platform filename slug.
String sanitizeExportSlug(String raw, {String fallback = 'layers_project'}) {
  final slug = raw
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return slug.isEmpty ? fallback : slug;
}

/// Filename slug for exporting a Project's full structured spec (`*_project_spec.md`).
String buildProjectSpecFilename(String projectTitle) =>
    '${sanitizeExportSlug(projectTitle)}_project_spec.md';

/// Filename slug for exporting a Project's CoPilot GDD markdown (`*_copilot_gdd.md`).
String buildCoPilotGddFilename(String projectTitle) =>
    '${sanitizeExportSlug(projectTitle)}_copilot_gdd.md';

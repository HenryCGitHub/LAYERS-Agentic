/// Cross-platform file export gateway.
///
/// Conditionally routes to modern Dart 3 `dart:js_interop` DOM anchor download
/// implementation on Flutter Web, or falls back to the safe stub on native platforms.
library;

import 'markdown_exporter_stub.dart'
    if (dart.library.js_interop) 'markdown_exporter_web.dart' as platform_exporter;

export 'markdown_exporter_stub.dart'
    if (dart.library.js_interop) 'markdown_exporter_web.dart';

/// Test-only interceptor capturing loopback browser handoff redirects.
bool Function(String targetUrl)? debugBrowserRedirectInterceptor;

/// Navigates the current browser tab to a validated URL (e.g. `http://127.0.0.1:<port>/callback`).
bool triggerBrowserRedirect(String targetUrl) {
  final interceptor = debugBrowserRedirectInterceptor;
  if (interceptor != null) {
    return interceptor(targetUrl);
  }
  return platform_exporter.performPlatformBrowserRedirect(targetUrl);
}

/// Sanitizes an arbitrary project title into a clean cross-platform filename slug.
String sanitizeExportSlug(String raw, {String fallback = 'layers_project'}) {
  final slug = raw
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return slug.isEmpty ? fallback : slug;
}

/// Filename slug for copying or exporting a Feature build prompt (`*_prompt.md`).
String buildFeaturePromptFilename(
  String projectTitle,
  String epicCode,
  String featureCode,
  String featureTitle,
) {
  final projSlug = sanitizeExportSlug(projectTitle);
  final featSlug = sanitizeExportSlug(
    '${epicCode}_${featureCode}_$featureTitle',
    fallback: 'feature',
  );
  return '${projSlug}_${featSlug}_prompt.md';
}

/// Filename slug for exporting an Epic domain architecture brief (`*_architecture.md`).
String buildEpicArchitectureFilename(
  String projectTitle,
  String epicCode,
  String epicTitle,
) {
  final projSlug = sanitizeExportSlug(projectTitle);
  final epicSlug = sanitizeExportSlug(
    '${epicCode}_$epicTitle',
    fallback: 'epic',
  );
  return '${projSlug}_${epicSlug}_architecture.md';
}

/// Filename slug for exporting a Project's full structured spec (`*_project_spec.md`).
String buildProjectSpecFilename(String projectTitle) =>
    '${sanitizeExportSlug(projectTitle)}_project_spec.md';

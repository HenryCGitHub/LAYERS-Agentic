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

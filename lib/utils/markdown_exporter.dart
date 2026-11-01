/// Cross-platform file export gateway.
///
/// Conditionally routes to modern Dart 3 `dart:js_interop` DOM anchor download
/// implementation on Flutter Web, or falls back to the safe stub on native platforms.
library;

export 'markdown_exporter_stub.dart'
    if (dart.library.js_interop) 'markdown_exporter_web.dart';

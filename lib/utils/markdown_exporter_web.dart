import 'dart:js_interop';

@JS('document')
external _DomDocument get _document;

extension type _DomDocument._(JSObject _) implements JSObject {
  external _DomAnchorElement createElement(String tagName);
}

extension type _DomAnchorElement._(JSObject _) implements JSObject {
  external set href(String value);
  external set download(String value);
  external void click();
}

/// Triggers a direct browser download of a `.md` or `.json` file on Flutter Web.
bool triggerMarkdownFileDownload({
  required String filename,
  required String content,
}) {
  try {
    final mimeType = filename.endsWith('.json')
        ? 'application/json'
        : 'text/markdown';
    final anchor = _document.createElement('a');
    anchor.href =
        'data:$mimeType;charset=utf-8,${Uri.encodeComponent(content)}';
    anchor.download = filename;
    anchor.click();
    return true;
  } catch (_) {
    return false;
  }
}

/// Triggers a direct browser download for a static web asset (e.g. `layers_godot_plugin.zip`).
bool triggerRelativeAssetDownload({
  required String relativeHref,
  required String downloadFilename,
}) {
  try {
    final anchor = _document.createElement('a');
    anchor.href = relativeHref;
    anchor.download = downloadFilename;
    anchor.click();
    return true;
  } catch (_) {
    return false;
  }
}

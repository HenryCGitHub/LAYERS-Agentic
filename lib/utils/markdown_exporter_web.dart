import 'dart:js_interop';

@JS('document')
external _DomDocument get _document;

@JS('window.location')
external _DomLocation get _location;

extension type _DomDocument._(JSObject _) implements JSObject {
  external _DomAnchorElement createElement(String tagName);
}

extension type _DomAnchorElement._(JSObject _) implements JSObject {
  external set href(String value);
  external set download(String value);
  external void click();
}

extension type _DomLocation._(JSObject _) implements JSObject {
  external void assign(String url);
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

/// Navigates the current browser tab to [targetUrl] (e.g. loopback handoff callback).
bool performPlatformBrowserRedirect(String targetUrl) {
  try {
    _location.assign(targetUrl);
    return true;
  } catch (_) {
    return false;
  }
}

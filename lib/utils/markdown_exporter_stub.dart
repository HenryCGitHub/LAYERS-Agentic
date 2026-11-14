/// Non-web stub for triggering client-side browser file downloads.
///
/// Returns `false` on non-web platforms because DOM anchor downloads are unavailable.
/// Callers handle this by providing clipboard-copied fallback feedback to the user.
bool triggerMarkdownFileDownload({
  required String filename,
  required String content,
}) {
  return false;
}

/// Non-web stub for downloading static bundled assets from `web/`.
bool triggerRelativeAssetDownload({
  required String relativeHref,
  required String downloadFilename,
}) {
  return false;
}

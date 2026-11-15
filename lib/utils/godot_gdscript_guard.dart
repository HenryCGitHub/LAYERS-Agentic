/// Parsed Godot 4 Debugger / Output error snippet for `⚑ Issue` triage.
class GodotDebuggerIssueMatch {
  final String resPath;
  final int? lineNumber;
  final String errorKind;
  final String rawExcerpt;

  const GodotDebuggerIssueMatch({
    required this.resPath,
    this.lineNumber,
    required this.errorKind,
    required this.rawExcerpt,
  });

  String get summaryChipLabel {
    final loc = lineNumber != null ? '$resPath:$lineNumber' : resPath;
    return 'Matched: $loc · $errorKind';
  }
}

/// Deterministic Godot 4 Debugger/Output trace parser for `⚑ Issue` triage.
class GodotGdscriptGuard {
  /// Extracts script file path, line number, and Godot 4 error signature from pasted Debugger/Output text.
  static GodotDebuggerIssueMatch? parseDebuggerTrace(String rawInput) {
    final text = rawInput.trim();
    if (text.isEmpty) return null;

    final resLoc = RegExp(r'(res://[^\s:")]+\.gd)(?::(\d+))?').firstMatch(text);
    final scriptLine = RegExp(r'\b([A-Za-z0-9_]+\.gd):(\d+)\b').firstMatch(text);

    String path = '';
    int? line;
    if (resLoc != null) {
      path = resLoc.group(1)!;
      line = int.tryParse(resLoc.group(2) ?? '');
    } else if (scriptLine != null) {
      path = scriptLine.group(1)!;
      line = int.tryParse(scriptLine.group(2) ?? '');
    }

    final lower = text.toLowerCase();
    String? errorKind;
    if (lower.contains('null instance') || lower.contains('null value')) {
      errorKind = 'Null Instance';
    } else if (lower.contains('node not found') || lower.contains('get_node')) {
      errorKind = '@onready / Node Not Found';
    } else if (lower.contains('flushing queries') || lower.contains('call_deferred')) {
      errorKind = 'Physics / call_deferred';
    } else if (lower.contains('invalid call') ||
        lower.contains('invalid assignment') ||
        lower.contains('invalid type') ||
        lower.contains('invalid access')) {
      errorKind = 'Invalid Call / Type Mismatch';
    } else if (lower.contains('parse error') ||
        (lower.contains('identifier') && lower.contains('not declared'))) {
      errorKind = 'GDScript Parse Error';
    } else if (path.isNotEmpty || RegExp(r'\bE \d+:\d+:\d+').hasMatch(text)) {
      errorKind = 'Godot Runtime Error';
    }

    if (path.isEmpty && errorKind == null) return null;

    final firstLine = text.split('\n').first.trim();
    return GodotDebuggerIssueMatch(
      resPath: path.isNotEmpty ? path : 'res://script_trace.gd',
      lineNumber: line,
      errorKind: errorKind ?? 'Runtime Error',
      rawExcerpt: firstLine.length > 140
          ? '${firstLine.substring(0, 140)}...'
          : firstLine,
    );
  }
}

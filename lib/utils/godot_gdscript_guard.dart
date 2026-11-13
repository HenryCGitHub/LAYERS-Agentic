/// Structured surgical hunk targeting an existing GDScript file without rewriting unrelated code.
class GdScriptPatchHunk {
  final String targetBlock;
  final String replaceBlock;
  final String note;

  const GdScriptPatchHunk({
    required this.targetBlock,
    required this.replaceBlock,
    this.note = '',
  });

  factory GdScriptPatchHunk.fromJson(Map<String, dynamic> json) {
    return GdScriptPatchHunk(
      targetBlock: (json['targetBlock'] ?? json['target'] ?? '').toString(),
      replaceBlock: (json['replaceBlock'] ?? json['replace'] ?? '').toString(),
      note: (json['note'] ?? json['reason'] ?? '').toString().trim(),
    );
  }

  Map<String, dynamic> toJson() => {
        'targetBlock': targetBlock,
        'replaceBlock': replaceBlock,
        if (note.isNotEmpty) 'note': note,
      };
}

class GdScriptPatchResult {
  final String updatedContent;
  final int appliedCount;
  final List<GdScriptPatchHunk> unmatchedHunks;
  final List<String> warnings;

  const GdScriptPatchResult({
    required this.updatedContent,
    required this.appliedCount,
    this.unmatchedHunks = const [],
    this.warnings = const [],
  });

  bool get hasUnmatched => unmatchedHunks.isNotEmpty;
}

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

/// Deterministic GDScript patch-hunk applier, Godot 4 syntax normalizer, symbol guard & trace parser.
class GodotGdscriptGuard {
  /// Applies structured `{targetBlock, replaceBlock}` hunks onto `existingContent` while preserving untouched lines.
  static GdScriptPatchResult applyPatchHunks({
    required String existingContent,
    required List<GdScriptPatchHunk> hunks,
  }) {
    final originalNormalized = existingContent.replaceAll('\r\n', '\n');
    var current = originalNormalized;
    var applied = 0;
    final unmatched = <GdScriptPatchHunk>[];
    final warnings = <String>[];
    var hadDeleteHunk = false;

    for (final hunk in hunks) {
      final target = hunk.targetBlock.replaceAll('\r\n', '\n');
      final replacement = hunk.replaceBlock.replaceAll('\r\n', '\n');
      if (replacement.trim().isEmpty && target.trim().isNotEmpty) {
        hadDeleteHunk = true;
      }

      if (target.trim().isEmpty) {
        if (replacement.trim().isEmpty) continue;
        if (_containsTrimmedBlock(current, replacement)) {
          applied++;
          continue;
        }
        final cleanCurr = current.trimRight();
        current = cleanCurr.isEmpty
            ? replacement.trimRight()
            : '$cleanCurr\n\n${replacement.trimRight()}';
        applied++;
        continue;
      }

      final exactIdx = current.indexOf(target);
      if (exactIdx != -1) {
        current =
            '${current.substring(0, exactIdx)}$replacement${current.substring(exactIdx + target.length)}';
        applied++;
        continue;
      }

      final trimmedMatch = _replaceWhitespaceTolerantLines(current, target, replacement);
      if (trimmedMatch != null) {
        current = trimmedMatch;
        applied++;
        continue;
      }

      if (replacement.trim().isNotEmpty && _containsTrimmedBlock(current, replacement)) {
        applied++;
        continue;
      }

      unmatched.add(hunk);
    }

    final normalizedOut = normalizeGodot4Syntax(current);
    warnings.addAll(normalizedOut.fixes);

    if (!hadDeleteHunk && originalNormalized.trim().isNotEmpty) {
      final dropped = detectDroppedSymbols(
        before: originalNormalized,
        after: normalizedOut.code,
      );
      warnings.addAll(dropped);
    }

    return GdScriptPatchResult(
      updatedContent: normalizedOut.code,
      appliedCount: applied,
      unmatchedHunks: unmatched,
      warnings: warnings.toSet().toList(),
    );
  }

  /// Normalizes common Godot 3 holdover syntax to Godot 4 idioms outside comments.
  static ({String code, List<String> fixes}) normalizeGodot4Syntax(String code) {
    final lines = code.replaceAll('\r\n', '\n').split('\n');
    final fixes = <String>[];
    final out = <String>[];

    for (final line in lines) {
      var next = line;
      final trimmed = line.trimLeft();
      if (!trimmed.startsWith('#')) {
        if (RegExp(r'^(\s*)export\s*\(([^)]+)\)\s+var\b').hasMatch(next)) {
          next = next.replaceFirstMapped(
            RegExp(r'^(\s*)export\s*\(([^)]+)\)\s+var\b'),
            (m) => '${m.group(1)}@export var',
          );
          fixes.add('Normalized Godot 3 `export(...) var` → `@export var`.');
        } else if (RegExp(r'^(\s*)export\s+var\b').hasMatch(next)) {
          next = next.replaceFirstMapped(
            RegExp(r'^(\s*)export\s+var\b'),
            (m) => '${m.group(1)}@export var',
          );
          fixes.add('Normalized Godot 3 `export var` → `@export var`.');
        }

        if (RegExp(r'^(\s*)onready\s+var\b').hasMatch(next)) {
          next = next.replaceFirstMapped(
            RegExp(r'^(\s*)onready\s+var\b'),
            (m) => '${m.group(1)}@onready var',
          );
          fixes.add('Normalized Godot 3 `onready var` → `@onready var`.');
        }

        if (trimmed == 'tool') {
          next = next.replaceFirst('tool', '@tool');
          fixes.add('Normalized Godot 3 `tool` → `@tool`.');
        }

        final moveMatch = RegExp(r'\bmove_and_slide\s*\(([^)]+)\)').firstMatch(next);
        if (moveMatch != null && moveMatch.group(1)!.trim().isNotEmpty) {
          next = next.replaceAll(RegExp(r'\bmove_and_slide\s*\([^)]+\)'), 'move_and_slide()');
          fixes.add('Normalized Godot 3 `move_and_slide(args)` → Godot 4 `move_and_slide()`.');
        }

        final yieldTimer = RegExp(
          r'yield\s*\(\s*([^,]+),\s*"timeout"\s*\)',
        ).firstMatch(next);
        if (yieldTimer != null) {
          next = next.replaceFirst(
            yieldTimer.group(0)!,
            'await ${yieldTimer.group(1)!.trim()}.timeout',
          );
          fixes.add('Normalized Godot 3 `yield(..., "timeout")` → `await ...timeout`.');
        }

        final connectMatch = RegExp(
          r'([A-Za-z0-9_\.\$]+)\.connect\(\s*"([A-Za-z0-9_]+)"\s*,\s*self\s*,\s*"([A-Za-z0-9_]+)"\s*\)',
        ).firstMatch(next);
        if (connectMatch != null) {
          final emitter = connectMatch.group(1)!;
          final sig = connectMatch.group(2)!;
          final handler = connectMatch.group(3)!;
          next = next.replaceFirst(connectMatch.group(0)!, '$emitter.$sig.connect($handler)');
          fixes.add('Normalized Godot 3 `.connect("$sig", self, "$handler")` → Godot 4 callable.');
        }
      }
      out.add(next);
    }

    return (code: out.join('\n'), fixes: fixes.toSet().toList());
  }

  /// Flags top-level `func` or `signal` declarations that existed in `before` but disappeared from `after`.
  static List<String> detectDroppedSymbols({
    required String before,
    required String after,
  }) {
    Set<String> extract(String src, RegExp pattern) {
      return pattern
          .allMatches(src.replaceAll('\r\n', '\n'))
          .map((m) => m.group(1)!)
          .toSet();
    }

    final funcRx = RegExp(r'^func\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(', multiLine: true);
    final sigRx = RegExp(r'^signal\s+([A-Za-z_][A-Za-z0-9_]*)\b', multiLine: true);

    final warnings = <String>[];
    final afterFuncs = extract(after, funcRx);
    for (final fn in extract(before, funcRx)) {
      if (!afterFuncs.contains(fn)) {
        warnings.add('Unexpectedly dropped method `func $fn()` during patch merge.');
      }
    }
    final afterSigs = extract(after, sigRx);
    for (final sig in extract(before, sigRx)) {
      if (!afterSigs.contains(sig)) {
        warnings.add('Unexpectedly dropped `signal $sig` during patch merge.');
      }
    }
    return warnings;
  }

  /// Updates an existing `@export var <varName>` default value cleanly inside stored GDScript.
  static String? updateExportVarValue(
    String code,
    String varName,
    String formattedGodotValue,
  ) {
    final normalized = code.replaceAll('\r\n', '\n');
    final escaped = RegExp.escape(varName.trim());
    if (escaped.isEmpty) return null;
    final pattern = RegExp(
      '^(\\s*@export(?:_[^\\s(]+(?:\\([^)]*\\))?)?\\s+var\\s+$escaped(?:\\s*:\\s*[A-Za-z0-9_]+)?\\s*=\\s*)([^#\\n]+)(#[^\\n]*)?\$',
      multiLine: true,
    );
    final match = pattern.firstMatch(normalized);
    if (match == null) return null;
    final prefix = match.group(1)!;
    final comment = match.group(3) ?? '';
    final replacement = comment.isEmpty
        ? '$prefix$formattedGodotValue'
        : '$prefix$formattedGodotValue $comment';
    return normalized.replaceRange(match.start, match.end, replacement);
  }

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
    } else if (lower.contains('parse error') || lower.contains('identifier') && lower.contains('not declared')) {
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
      rawExcerpt: firstLine.length > 140 ? '${firstLine.substring(0, 140)}...' : firstLine,
    );
  }

  static bool _containsTrimmedBlock(String haystack, String needle) {
    final normHay = haystack
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .join('\n');
    final normNeedle = needle
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .join('\n');
    return normNeedle.isNotEmpty && normHay.contains(normNeedle);
  }

  static String? _replaceWhitespaceTolerantLines(
    String content,
    String targetBlock,
    String replaceBlock,
  ) {
    final sourceLines = content.split('\n');
    final targetLines = targetBlock.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (targetLines.isEmpty) return null;

    for (var start = 0; start < sourceLines.length; start++) {
      if (sourceLines[start].trim() != targetLines.first.trim()) continue;
      var sIdx = start;
      var tIdx = 0;
      var endIdx = start;
      while (sIdx < sourceLines.length && tIdx < targetLines.length) {
        final sTrim = sourceLines[sIdx].trim();
        if (sTrim.isEmpty) {
          sIdx++;
          continue;
        }
        if (sTrim != targetLines[tIdx].trim()) break;
        endIdx = sIdx;
        sIdx++;
        tIdx++;
      }
      if (tIdx == targetLines.length) {
        final replacementLines = replaceBlock.trim().isEmpty
            ? <String>[]
            : replaceBlock.split('\n');
        final updated = <String>[
          ...sourceLines.sublist(0, start),
          ...replacementLines,
          ...sourceLines.sublist(endIdx + 1),
        ];
        return updated.join('\n');
      }
    }
    return null;
  }
}

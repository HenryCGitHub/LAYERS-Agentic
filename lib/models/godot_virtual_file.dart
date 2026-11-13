import 'dart:convert';

import 'package:layers_agentic/constants/tiers.dart';
import 'package:layers_agentic/models/tier_document.dart';

enum GodotDiffLineKind { context, added, removed }

/// Single line inside a unified diff preview for Godot disk sync or script revision review.
class GodotDiffLine {
  final GodotDiffLineKind kind;
  final int? oldLineNumber;
  final int? newLineNumber;
  final String text;

  const GodotDiffLine({
    required this.kind,
    this.oldLineNumber,
    this.newLineNumber,
    required this.text,
  });
}

/// Cumulative Godot artifact (`res://...`) stored in Firestore/LocalVault as a `TierType.codeFile` document.
class GodotVirtualFile {
  static const String resPathKey = 'res_path';
  static const String contentKey = 'content';
  static const String languageKey = 'language';
  static const String releaseVersionKey = 'release_version';
  static const String featureIdsKey = 'feature_ids';
  static const String updatedAtMsKey = 'updated_at_ms';
  static const String lastDiskHashKey = 'last_disk_hash';

  final String id;
  final String projectId;
  final String resPath;
  final String content;
  final String language;
  final String releaseVersion;
  final List<String> featureIds;
  final int updatedAtMs;
  final String lastDiskHash;

  const GodotVirtualFile({
    required this.id,
    required this.projectId,
    required this.resPath,
    required this.content,
    required this.language,
    required this.releaseVersion,
    this.featureIds = const [],
    this.updatedAtMs = 0,
    this.lastDiskHash = '',
  });

  /// Canonicalizes paths to `res://...` with forward slashes.
  static String normalizeResPath(String raw) {
    var cleaned = raw.trim().replaceAll('\\', '/');
    if (cleaned.isEmpty) return '';
    while (cleaned.startsWith('/')) {
      cleaned = cleaned.substring(1);
    }
    if (!cleaned.startsWith('res://')) {
      cleaned = 'res://$cleaned';
    }
    return cleaned;
  }

  /// Deterministic document ID scoped to `(projectId, resPath)` so upserts never duplicate Cloud records.
  static String stableDocId(String projectId, String resPath) {
    final norm = normalizeResPath(resPath);
    final slug = norm
        .replaceFirst('res://', '')
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final hash = computeContentHash(norm).substring(0, 6);
    return '${projectId}_code_${slug}_$hash';
  }

  static String inferLanguage(String resPath) {
    final lower = resPath.toLowerCase();
    if (lower.endsWith('.gd')) return 'gdscript';
    if (lower.endsWith('.tscn')) return 'tscn';
    if (lower.endsWith('.tres')) return 'tres';
    if (lower.endsWith('.godot') || lower.endsWith('.cfg')) return 'ini';
    if (lower.endsWith('.md')) return 'markdown';
    return 'text';
  }

  /// Disk writes are strictly restricted to `.gd` and `.tres`; `.tscn` / `project.godot` remain read-only/copyable.
  bool get isDiskWritable {
    final lower = resPath.toLowerCase();
    return lower.endsWith('.gd') || lower.endsWith('.tres');
  }

  String get contentHash => computeContentHash(content);

  bool get hasUnsyncedChangesComparedToLastDisk =>
      lastDiskHash.isNotEmpty && lastDiskHash != contentHash;

  GodotVirtualFile copyWith({
    String? id,
    String? projectId,
    String? resPath,
    String? content,
    String? language,
    String? releaseVersion,
    List<String>? featureIds,
    int? updatedAtMs,
    String? lastDiskHash,
  }) {
    final nextPath = resPath != null ? normalizeResPath(resPath) : this.resPath;
    return GodotVirtualFile(
      id: id ?? this.id,
      projectId: projectId ?? this.projectId,
      resPath: nextPath,
      content: content ?? this.content,
      language: language ?? (resPath != null ? inferLanguage(nextPath) : this.language),
      releaseVersion: releaseVersion ?? this.releaseVersion,
      featureIds: featureIds ?? this.featureIds,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      lastDiskHash: lastDiskHash ?? this.lastDiskHash,
    );
  }

  factory GodotVirtualFile.fromTierDocument(TierDocument doc) {
    final rawPath = doc.sections[resPathKey] ?? doc.title;
    final normPath = normalizeResPath(rawPath);
    List<String> parsedFeatures = const [];
    final rawFeatures = (doc.sections[featureIdsKey] ?? '').trim();
    if (rawFeatures.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawFeatures);
        if (decoded is List) {
          parsedFeatures = decoded.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
        }
      } catch (_) {}
    }

    return GodotVirtualFile(
      id: doc.id,
      projectId: doc.parentId ?? '',
      resPath: normPath,
      content: (doc.sections[contentKey] ?? '').replaceAll('\r\n', '\n'),
      language: (doc.sections[languageKey] ?? '').trim().isNotEmpty
          ? doc.sections[languageKey]!.trim()
          : inferLanguage(normPath),
      releaseVersion: (doc.sections[releaseVersionKey] ?? doc.phase ?? 'v0.1').trim(),
      featureIds: parsedFeatures,
      updatedAtMs: int.tryParse(doc.sections[updatedAtMsKey] ?? '') ?? 0,
      lastDiskHash: (doc.sections[lastDiskHashKey] ?? '').trim(),
    );
  }

  TierDocument toTierDocument() {
    final normPath = normalizeResPath(resPath);
    final iconEmoji = switch (language) {
      'gdscript' => '📜',
      'tscn' => '🎬',
      'tres' => '📦',
      _ => '📄',
    };
    return TierDocument(
      id: id.isEmpty ? stableDocId(projectId, normPath) : id,
      title: normPath,
      tier: TierType.codeFile,
      parentId: projectId,
      phase: releaseVersion,
      icon: iconEmoji,
      colorHex: '#3B82F6',
      sections: {
        resPathKey: normPath,
        contentKey: content.replaceAll('\r\n', '\n'),
        languageKey: language.isEmpty ? inferLanguage(normPath) : language,
        releaseVersionKey: releaseVersion,
        featureIdsKey: jsonEncode(featureIds.toSet().toList()),
        updatedAtMsKey: updatedAtMs.toString(),
        if (lastDiskHash.isNotEmpty) lastDiskHashKey: lastDiskHash,
      },
    );
  }

  /// Deterministic FNV-1a hash over normalized LF text for cheap disk vs Cloud comparison.
  static String computeContentHash(String text) {
    final normalized = text.replaceAll('\r\n', '\n');
    const int fnvPrime = 0x01000193;
    int hash = 0x811c9dc5;
    for (final unit in utf8.encode(normalized)) {
      hash ^= unit;
      hash = (hash * fnvPrime) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  /// Computes a clean line-level diff between `oldText` and `newText` with surrounding context lines.
  static List<GodotDiffLine> computeUnifiedDiff(
    String oldText,
    String newText, {
    int contextLines = 3,
  }) {
    final oldLines = oldText.isEmpty
        ? <String>[]
        : oldText.replaceAll('\r\n', '\n').split('\n');
    final newLines = newText.isEmpty
        ? <String>[]
        : newText.replaceAll('\r\n', '\n').split('\n');

    final n = oldLines.length;
    final m = newLines.length;
    if (n == 0 && m == 0) return const [];

    // Guard against quadratic DP on very large files by falling back to full replacement hunk.
    if (n * m > 250000) {
      return [
        for (var i = 0; i < n; i++)
          GodotDiffLine(
            kind: GodotDiffLineKind.removed,
            oldLineNumber: i + 1,
            text: oldLines[i],
          ),
        for (var j = 0; j < m; j++)
          GodotDiffLine(
            kind: GodotDiffLineKind.added,
            newLineNumber: j + 1,
            text: newLines[j],
          ),
      ];
    }

    final dp = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
    for (var i = n - 1; i >= 0; i--) {
      for (var j = m - 1; j >= 0; j--) {
        if (oldLines[i] == newLines[j]) {
          dp[i][j] = dp[i + 1][j + 1] + 1;
        } else {
          dp[i][j] = dp[i + 1][j] >= dp[i][j + 1] ? dp[i + 1][j] : dp[i][j + 1];
        }
      }
    }

    final raw = <GodotDiffLine>[];
    var i = 0;
    var j = 0;
    while (i < n && j < m) {
      if (oldLines[i] == newLines[j]) {
        raw.add(GodotDiffLine(
          kind: GodotDiffLineKind.context,
          oldLineNumber: i + 1,
          newLineNumber: j + 1,
          text: oldLines[i],
        ));
        i++;
        j++;
      } else if (dp[i + 1][j] >= dp[i][j + 1]) {
        raw.add(GodotDiffLine(
          kind: GodotDiffLineKind.removed,
          oldLineNumber: i + 1,
          text: oldLines[i],
        ));
        i++;
      } else {
        raw.add(GodotDiffLine(
          kind: GodotDiffLineKind.added,
          newLineNumber: j + 1,
          text: newLines[j],
        ));
        j++;
      }
    }
    while (i < n) {
      raw.add(GodotDiffLine(
        kind: GodotDiffLineKind.removed,
        oldLineNumber: i + 1,
        text: oldLines[i],
      ));
      i++;
    }
    while (j < m) {
      raw.add(GodotDiffLine(
        kind: GodotDiffLineKind.added,
        newLineNumber: j + 1,
        text: newLines[j],
      ));
      j++;
    }

    final changedIndices = <int>[];
    for (var idx = 0; idx < raw.length; idx++) {
      if (raw[idx].kind != GodotDiffLineKind.context) {
        changedIndices.add(idx);
      }
    }
    if (changedIndices.isEmpty) return const [];

    final visible = List<bool>.filled(raw.length, false);
    for (final idx in changedIndices) {
      final start = (idx - contextLines).clamp(0, raw.length - 1);
      final end = (idx + contextLines).clamp(0, raw.length - 1);
      for (var k = start; k <= end; k++) {
        visible[k] = true;
      }
    }
    return [
      for (var idx = 0; idx < raw.length; idx++)
        if (visible[idx]) raw[idx],
    ];
  }

  /// Generates a clean starter Godot 4 `.tscn` text scaffold (copy/download only; never auto-overwrites disk).
  static String buildTscnStarterScaffold({
    required String rootNodeName,
    required String rootNodeType,
    String? scriptResPath,
    List<({String name, String type})> childNodes = const [],
  }) {
    final hasScript = scriptResPath != null && scriptResPath.trim().isNotEmpty;
    final loadSteps = hasScript ? 2 : 1;
    final buf = StringBuffer()
      ..writeln('[gd_scene load_steps=$loadSteps format=3]')
      ..writeln();
    if (hasScript) {
      buf.writeln('[ext_resource type="Script" path="${normalizeResPath(scriptResPath)}" id="1_script"]');
      buf.writeln();
    }
    buf.writeln('[node name="$rootNodeName" type="$rootNodeType"]');
    if (hasScript) {
      buf.writeln('script = ExtResource("1_script")');
    }
    for (final child in childNodes) {
      buf.writeln();
      buf.writeln('[node name="${child.name}" type="${child.type}" parent="."]');
    }
    return buf.toString().trimRight();
  }

  /// Generates a clean starter Godot 4 `.tres` `Resource` text file.
  static String buildTresStarterResource({
    required String scriptClassName,
    required String scriptResPath,
    Map<String, String> properties = const {},
  }) {
    final buf = StringBuffer()
      ..writeln('[gd_resource type="Resource" script_class="$scriptClassName" load_steps=2 format=3]')
      ..writeln()
      ..writeln('[ext_resource type="Script" path="${normalizeResPath(scriptResPath)}" id="1_res"]')
      ..writeln()
      ..writeln('[resource]')
      ..writeln('script = ExtResource("1_res")');
    for (final entry in properties.entries) {
      buf.writeln('${entry.key} = ${entry.value}');
    }
    return buf.toString().trimRight();
  }

  /// Extracts a valid Godot node/resource identifier from display labels like
  /// `"Root Node: Control (CanvasLayer)"` -> `"Control"`.
  static String sanitizeGdClassName(
    String rawClass, {
    String fallback = 'Node',
  }) {
    final stripped = rawClass
        .replaceFirst(RegExp(r'^root\s+node\s*:\s*', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*\(.*?\)'), '')
        .trim();
    final match = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*').firstMatch(stripped);
    if (match != null && match.group(0)!.isNotEmpty) {
      return match.group(0)!;
    }
    return fallback;
  }

  /// Generates a clean starter Godot 4 `.gd` script scaffold from Feature specs
  /// (`@export var` tuning params + step goals) when no saved script exists yet.
  static String buildGdStarterScaffold({
    required String baseClass,
    required String scriptTitle,
    List<String> tuningParams = const [],
    List<String> stepTitles = const [],
  }) {
    final cleanBase = sanitizeGdClassName(baseClass);
    final buf = StringBuffer()
      ..writeln('extends $cleanBase')
      ..writeln('# $scriptTitle');

    final seenExports = <String>{};
    final exportLines = <String>[];
    for (final rawParam in tuningParams) {
      final parts = rawParam.split(RegExp(r'[:=]'));
      if (parts.length < 2) continue;
      final varName = parts.first
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9_]+'), '_')
          .replaceAll(RegExp(r'^_+|_+$'), '');
      if (varName.isEmpty || !seenExports.add(varName)) continue;
      final rawVal = parts.sublist(1).join(':').trim();
      final typed = _inferGdExportDeclaration(rawVal);
      exportLines.add('@export var $varName: ${typed.type} = ${typed.value}');
    }

    if (exportLines.isNotEmpty) {
      buf.writeln();
      for (final line in exportLines) {
        buf.writeln(line);
      }
    }

    buf
      ..writeln()
      ..writeln('func _ready() -> void:');
    if (stepTitles.isEmpty) {
      buf.writeln('\tpass');
    } else {
      for (final title in stepTitles.take(4)) {
        final clean = title.trim();
        if (clean.isNotEmpty) {
          buf.writeln('\t# TODO: $clean');
        }
      }
      buf.writeln('\tpass');
    }

    if (cleanBase.contains('CharacterBody')) {
      buf
        ..writeln()
        ..writeln('func _physics_process(_delta: float) -> void:')
        ..writeln('\tmove_and_slide()');
    }
    return buf.toString().trimRight();
  }

  static ({String type, String value}) _inferGdExportDeclaration(String rawVal) {
    final trimmed = rawVal.trim();
    final lower = trimmed.toLowerCase();
    if (lower == 'true' || lower == 'false') {
      return (type: 'bool', value: lower);
    }
    if (trimmed.startsWith('Vector2(')) {
      return (type: 'Vector2', value: trimmed);
    }
    if (trimmed.startsWith('Vector3(')) {
      return (type: 'Vector3', value: trimmed);
    }
    final numMatch = RegExp(r'^(-?\d+(?:\.\d+)?)').firstMatch(trimmed);
    if (numMatch != null) {
      final numLiteral = numMatch.group(1)!;
      if (numLiteral.contains('.')) {
        return (type: 'float', value: numLiteral);
      }
      final parsedInt = int.tryParse(numLiteral);
      if (parsedInt != null &&
          RegExp(r'\b(?:count|max|slots|waves|ammo|charges|layer|mask|level)\b',
                  caseSensitive: false)
              .hasMatch(trimmed)) {
        return (type: 'int', value: '$parsedInt');
      }
      return (type: 'float', value: '$numLiteral.0');
    }
    final escaped = trimmed.replaceAll('"', '\\"');
    return (type: 'String', value: '"$escaped"');
  }
}

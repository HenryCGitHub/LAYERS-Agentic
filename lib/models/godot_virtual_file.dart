import 'dart:convert';

import 'package:layers_agentic/constants/tiers.dart';
import 'package:layers_agentic/models/tier_document.dart';

/// Cumulative Godot artifact (`res://...`) stored in Firestore/LocalVault as a `TierType.codeFile` document.
class GodotVirtualFile {
  static const String resPathKey = 'res_path';
  static const String contentKey = 'content';
  static const String languageKey = 'language';
  static const String releaseVersionKey = 'release_version';
  static const String featureIdsKey = 'feature_ids';
  static const String updatedAtMsKey = 'updated_at_ms';

  final String id;
  final String projectId;
  final String resPath;
  final String content;
  final String language;
  final String releaseVersion;
  final List<String> featureIds;
  final int updatedAtMs;

  const GodotVirtualFile({
    required this.id,
    required this.projectId,
    required this.resPath,
    required this.content,
    required this.language,
    required this.releaseVersion,
    this.featureIds = const [],
    this.updatedAtMs = 0,
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

  String get contentHash => computeContentHash(content);

  GodotVirtualFile copyWith({
    String? id,
    String? projectId,
    String? resPath,
    String? content,
    String? language,
    String? releaseVersion,
    List<String>? featureIds,
    int? updatedAtMs,
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
      },
    );
  }

  /// Deterministic FNV-1a hash over normalized LF text.
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

  /// Generates a clean starter Godot 4 `.tscn` text scaffold for copy/download.
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

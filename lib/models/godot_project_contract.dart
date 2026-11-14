import 'dart:convert';

/// Autoload singleton declared inside the Godot project's `project.godot` `[autoload]` table.
class GodotAutoloadEntry {
  final String name;
  final String resPath;

  const GodotAutoloadEntry({
    required this.name,
    required this.resPath,
  });

  factory GodotAutoloadEntry.fromJson(Map<String, dynamic> json) {
    return GodotAutoloadEntry(
      name: (json['name'] ?? '').toString().trim(),
      resPath: GodotAutoloadEntry.normalizeResPath(
        (json['resPath'] ?? json['path'] ?? '').toString(),
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'resPath': resPath,
      };

  static String normalizeResPath(String raw) {
    final cleaned = raw.trim().replaceAll('"', '').replaceFirst(RegExp(r'^\*+'), '');
    if (cleaned.isEmpty) return '';
    return cleaned.startsWith('res://') ? cleaned : 'res://$cleaned';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GodotAutoloadEntry &&
          other.name == name &&
          other.resPath == resPath;

  @override
  int get hashCode => Object.hash(name, resPath);
}

/// Canonical per-project Godot 4 configuration contract (physics layers, input actions, autoloads, groups).
class GodotProjectContract {
  static const String sectionKey = 'godot_contract';

  static const Map<int, String> defaultStarterPhysicsLayers = {
    1: 'World',
    2: 'Player',
    3: 'Enemy',
    4: 'Projectile',
    5: 'Pickup',
  };

  /// 1-based layer number (1..32) to human-readable layer name.
  final Map<int, String> physicsLayers;
  final List<String> inputActions;
  final List<GodotAutoloadEntry> autoloads;
  final List<String> groups;
  final String engineVersion;
  final bool is3D;

  const GodotProjectContract({
    this.physicsLayers = const {},
    this.inputActions = const [],
    this.autoloads = const [],
    this.groups = const [],
    this.engineVersion = '4.3',
    this.is3D = false,
  });

  factory GodotProjectContract.starter({bool is3D = false}) {
    return GodotProjectContract(
      physicsLayers: Map<int, String>.from(defaultStarterPhysicsLayers),
      inputActions: const [
        'move_left',
        'move_right',
        'move_up',
        'move_down',
        'jump',
        'interact',
      ],
      autoloads: const [],
      groups: const ['player', 'enemy'],
      engineVersion: '4.3',
      is3D: is3D,
    );
  }

  bool get hasAnyEntries =>
      physicsLayers.isNotEmpty ||
      inputActions.isNotEmpty ||
      autoloads.isNotEmpty ||
      groups.isNotEmpty;

  GodotProjectContract copyWith({
    Map<int, String>? physicsLayers,
    List<String>? inputActions,
    List<GodotAutoloadEntry>? autoloads,
    List<String>? groups,
    String? engineVersion,
    bool? is3D,
  }) {
    return GodotProjectContract(
      physicsLayers: physicsLayers ?? this.physicsLayers,
      inputActions: inputActions ?? this.inputActions,
      autoloads: autoloads ?? this.autoloads,
      groups: groups ?? this.groups,
      engineVersion: engineVersion ?? this.engineVersion,
      is3D: is3D ?? this.is3D,
    );
  }

  factory GodotProjectContract.fromJson(Map<String, dynamic> json) {
    final rawLayers = json['physicsLayers'] as Map<String, dynamic>? ?? const {};
    final parsedLayers = <int, String>{};
    for (final entry in rawLayers.entries) {
      final numIdx = int.tryParse(entry.key.trim());
      final label = entry.value.toString().trim();
      if (numIdx != null && numIdx >= 1 && numIdx <= 32 && label.isNotEmpty) {
        parsedLayers[numIdx] = label;
      }
    }

    List<String> parseStrings(dynamic raw) {
      if (raw is! List) return const [];
      return raw
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toSet()
          .toList();
    }

    final rawAutoloads = json['autoloads'] as List<dynamic>? ?? const [];
    final parsedAutoloads = <GodotAutoloadEntry>[];
    for (final item in rawAutoloads) {
      if (item is Map<String, dynamic>) {
        final entry = GodotAutoloadEntry.fromJson(item);
        if (entry.name.isNotEmpty && entry.resPath.isNotEmpty) {
          parsedAutoloads.add(entry);
        }
      }
    }

    return GodotProjectContract(
      physicsLayers: parsedLayers,
      inputActions: parseStrings(json['inputActions']),
      autoloads: parsedAutoloads,
      groups: parseStrings(json['groups']),
      engineVersion: (json['engineVersion'] ?? '4.3').toString().trim(),
      is3D: json['is3D'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    final sortedLayerKeys = physicsLayers.keys.toList()..sort();
    return {
      'physicsLayers': {
        for (final k in sortedLayerKeys) k.toString(): physicsLayers[k]!,
      },
      'inputActions': inputActions,
      'autoloads': autoloads.map((a) => a.toJson()).toList(),
      'groups': groups,
      'engineVersion': engineVersion,
      'is3D': is3D,
    };
  }

  String toJsonString() => jsonEncode(toJson());

  static GodotProjectContract fromProjectSections(
    Map<String, String> sections, {
    bool is3DHint = false,
  }) {
    final raw = (sections[sectionKey] ?? '').trim();
    if (raw.isEmpty) {
      return GodotProjectContract.starter(is3D: is3DHint);
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return GodotProjectContract.fromJson(decoded);
      }
    } catch (_) {
      // Fallback to starter contract if stored JSON is corrupted.
    }
    return GodotProjectContract.starter(is3D: is3DHint);
  }

  /// Computes Godot physics layer/mask integer bitmask from 1-based layer numbers (`1..32`).
  static int bitmaskForLayerNumbers(Iterable<int> layerNumbers) {
    var mask = 0;
    for (final layer in layerNumbers) {
      if (layer >= 1 && layer <= 32) {
        mask |= 1 << (layer - 1);
      }
    }
    return mask;
  }

  /// Computes bitmask from layer names defined on this contract (case-insensitive).
  int bitmaskForLayerNames(Iterable<String> names) {
    final wanted = names.map((n) => n.trim().toLowerCase()).where((s) => s.isNotEmpty).toSet();
    final matched = <int>[];
    for (final entry in physicsLayers.entries) {
      if (wanted.contains(entry.value.trim().toLowerCase())) {
        matched.add(entry.key);
      }
    }
    return bitmaskForLayerNumbers(matched);
  }

  /// Decodes an integer Godot layer/mask bitmask into sorted 1-based layer numbers (`1..32`).
  static List<int> layerNumbersFromBitmask(int mask) {
    final numbers = <int>[];
    for (var bit = 0; bit < 32; bit++) {
      if ((mask & (1 << bit)) != 0) {
        numbers.add(bit + 1);
      }
    }
    return numbers;
  }

  String layerLabel(int layerNumber) =>
      physicsLayers[layerNumber] ?? 'Layer $layerNumber';

  /// Emits ready-to-paste `project.godot` INI sections for `[layer_names]`, `[autoload]`, and `[input]`.
  String toProjectGodotIniSnippet() {
    final buf = StringBuffer();
    if (physicsLayers.isNotEmpty) {
      final prefix = is3D ? '3d_physics' : '2d_physics';
      buf.writeln('[layer_names]');
      final keys = physicsLayers.keys.toList()..sort();
      for (final k in keys) {
        buf.writeln('$prefix/layer_$k="${physicsLayers[k]}"');
      }
      buf.writeln();
    }
    if (autoloads.isNotEmpty) {
      buf.writeln('[autoload]');
      for (final a in autoloads) {
        buf.writeln('${a.name}="*${a.resPath}"');
      }
      buf.writeln();
    }
    if (inputActions.isNotEmpty) {
      buf.writeln('[input]');
      for (final action in inputActions) {
        buf.writeln('$action={\n"deadzone": 0.5,\n"events": []\n}');
      }
    }
    return buf.toString().trimRight();
  }

  /// Compact prompt/AGENTS.md summary preserving exact Godot identifiers and layer numbers.
  String toPromptSummary() {
    final buf = StringBuffer();
    if (physicsLayers.isNotEmpty) {
      final keys = physicsLayers.keys.toList()..sort();
      final items = keys.map((k) => 'L$k=${physicsLayers[k]}').join(', ');
      buf.writeln('Physics Layers (${is3D ? "3D" : "2D"}): $items');
    }
    if (inputActions.isNotEmpty) {
      buf.writeln('InputMap Actions: ${inputActions.join(', ')}');
    }
    if (autoloads.isNotEmpty) {
      final items = autoloads.map((a) => '${a.name} (${a.resPath})').join(', ');
      buf.writeln('Autoloads: $items');
    }
    if (groups.isNotEmpty) {
      buf.writeln('Node Groups: ${groups.join(', ')}');
    }
    return buf.toString().trim();
  }
}

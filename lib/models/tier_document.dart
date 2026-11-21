import '../constants/tiers.dart';

int _globalIdCounter = 0;

/// Generates a guaranteed unique ID even when called hundreds of times in a microsecond loop.
String generateUniqueId(String prefix) {
  _globalIdCounter++;
  return '$prefix-${DateTime.now().microsecondsSinceEpoch}-$_globalIdCounter';
}

class DurationHelper {
  static final RegExp _durationRegex = RegExp(r'([\d\.]+)\s*([a-z]+)');

  static int parseToMinutes(String durationStr) {
    final raw = durationStr.trim().toLowerCase();
    if (raw.isEmpty) return 0;

    final match = _durationRegex.firstMatch(raw);
    if (match == null) return 0;

    final val = double.tryParse(match.group(1) ?? '') ?? 0.0;
    final unit = match.group(2) ?? '';

    if (unit.startsWith('mo')) return (val * 160 * 60).round();
    if (unit.startsWith('m')) return val.round();
    if (unit.startsWith('h')) return (val * 60).round();
    if (unit.startsWith('d')) return (val * 8 * 60).round();
    if (unit.startsWith('w')) return (val * 40 * 60).round();
    return 0;
  }

  static String formatMinutes(int totalMinutes) {
    if (totalMinutes <= 0) return '';
    if (totalMinutes < 60) return '${totalMinutes}m';
    final hours = totalMinutes / 60.0;
    return hours % 1 == 0
        ? '${hours.toInt()}h'
        : '${hours.toStringAsFixed(1)}h';
  }

  static String normalizeToHours(String durationStr) {
    final raw = durationStr.trim();
    if (raw.isEmpty) return '';
    final mins = parseToMinutes(raw);
    if (mins <= 0) return raw;
    return formatMinutes(mins);
  }
}

class Subtask {
  final String id;
  String text;
  bool completed;
  List<Subtask> children;

  Subtask({
    required this.id,
    required this.text,
    this.completed = false,
    List<Subtask>? children,
  }) : children = children ?? [];

  factory Subtask.fromJson(Map<String, dynamic> json) {
    final rawChildren = json['children'] as List<dynamic>? ?? [];
    return Subtask(
      id: json['id'] as String? ?? generateUniqueId('st'),
      text: json['text'] as String? ?? '',
      completed: json['completed'] as bool? ?? false,
      children: rawChildren
          .map((e) => Subtask.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'completed': completed,
      'children': children.map((c) => c.toJson()).toList(),
    };
  }

  Subtask copyWith({
    String? id,
    String? text,
    bool? completed,
    List<Subtask>? children,
  }) {
    return Subtask(
      id: id ?? this.id,
      text: text ?? this.text,
      completed: completed ?? this.completed,
      children: children ?? this.children.map((c) => c.copyWith()).toList(),
    );
  }
}

class TierDocument {
  final String id;
  String title;
  TierType tier;
  String? parentId;
  List<String> childrenIds;
  String assignee;
  String dueDate;
  String? _estimatedDuration;
  String get estimatedDuration => _estimatedDuration ?? '';
  set estimatedDuration(String val) =>
      _estimatedDuration = DurationHelper.normalizeToHours(val);
  String icon;
  String colorHex;
  Map<String, String> sections;
  List<Subtask> subtasks;
  String? phase;
  bool isInbox;
  bool isIcebox;
  bool isCompleted;

  /// Returns true if a persisted JSON map belongs to a retired tier
  /// (`feature`, `task`, `codeFile`, `code_file`, `godot_file`) that must be skipped
  /// during load/sync/import rather than falling back to `TierType.project`.
  static bool isLegacyIgnoredTier(Map<dynamic, dynamic> json) {
    final raw = (json['tier'] ?? '').toString().trim().toLowerCase();
    return raw == 'feature' ||
        raw == 'task' ||
        raw == 'codefile' ||
        raw == 'code_file' ||
        raw == 'godot_file';
  }

  TierDocument({
    required this.id,
    required this.title,
    required this.tier,
    this.parentId,
    List<String>? childrenIds,
    this.assignee = 'Me',
    this.dueDate = '',
    String? estimatedDuration,
    this.icon = '📄',
    this.colorHex = '#3b82f6',
    Map<String, String>? sections,
    List<Subtask>? subtasks,
    this.phase,
    this.isInbox = false,
    this.isIcebox = false,
    this.isCompleted = false,
  })  : _estimatedDuration = DurationHelper.normalizeToHours(estimatedDuration ?? ''),
        childrenIds = childrenIds ?? [],
        sections = sections ?? {},
        subtasks = subtasks ?? [];

  factory TierDocument.fromJson(Map<String, dynamic> json) {
    final rawSections = json['sections'] as Map<String, dynamic>? ?? {};
    final sectionsMap = rawSections.map((k, v) => MapEntry(k, v.toString()));

    final rawSubtasks = json['subtasks'] as List<dynamic>? ?? [];
    final subtasksList = rawSubtasks
        .map((e) => Subtask.fromJson(e as Map<String, dynamic>))
        .toList();

    final rawChildren = json['childrenIds'] as List<dynamic>? ?? [];
    final childrenList = rawChildren.map((e) => e.toString()).toList();

    String rawTierStr = json['tier'] as String? ?? 'PROJECT';
    if (rawTierStr.toUpperCase() == 'GOAL') rawTierStr = 'PROJECT';

    return TierDocument(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'Untitled',
      tier: TierType.fromString(rawTierStr),
      parentId: json['parentId'] as String?,
      childrenIds: childrenList,
      assignee: json['assignee'] as String? ?? 'Me',
      dueDate: json['dueDate'] as String? ?? '',
      estimatedDuration: json['estimatedDuration'] as String? ??
          json['estimate'] as String? ??
          '',
      icon: json['icon'] as String? ?? '📄',
      colorHex: json['color'] as String? ?? '#3b82f6',
      sections: sectionsMap,
      subtasks: subtasksList,
      phase: json['phase'] as String?,
      isInbox: json['isInbox'] as bool? ?? false,
      isIcebox: json['isIcebox'] as bool? ?? false,
      isCompleted: json['isCompleted'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'tier': tier.id,
      'parentId': parentId,
      'childrenIds': childrenIds,
      'assignee': assignee,
      'dueDate': dueDate,
      'estimatedDuration': estimatedDuration,
      'icon': icon,
      'color': colorHex,
      'sections': sections,
      'subtasks': subtasks.map((s) => s.toJson()).toList(),
      'phase': phase,
      'isInbox': isInbox,
      'isIcebox': isIcebox,
      'isCompleted': isCompleted,
    };
  }

  TierDocument copyWith({
    String? id,
    String? title,
    TierType? tier,
    String? parentId,
    List<String>? childrenIds,
    String? assignee,
    String? dueDate,
    String? estimatedDuration,
    String? icon,
    String? colorHex,
    Map<String, String>? sections,
    List<Subtask>? subtasks,
    String? phase,
    bool? isInbox,
    bool? isIcebox,
    bool? isCompleted,
  }) {
    return TierDocument(
      id: id ?? this.id,
      title: title ?? this.title,
      tier: tier ?? this.tier,
      parentId: parentId ?? this.parentId,
      childrenIds: childrenIds != null
          ? List<String>.from(childrenIds)
          : List<String>.from(this.childrenIds),
      assignee: assignee ?? this.assignee,
      dueDate: dueDate ?? this.dueDate,
      estimatedDuration: estimatedDuration ?? this.estimatedDuration,
      icon: icon ?? this.icon,
      colorHex: colorHex ?? this.colorHex,
      sections: sections != null
          ? Map<String, String>.from(sections)
          : Map<String, String>.from(this.sections),
      subtasks: subtasks != null
          ? List<Subtask>.from(subtasks)
          : List<Subtask>.from(this.subtasks),
      phase: phase ?? this.phase,
      isInbox: isInbox ?? this.isInbox,
      isIcebox: isIcebox ?? this.isIcebox,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }
}


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

    if (unit.startsWith('m') && !unit.startsWith('mo')) {
      return val.round();
    } else if (unit.startsWith('h')) {
      return (val * 60).round();
    } else if (unit.startsWith('d')) {
      return (val * 8 * 60).round(); // 1 workday = 8 working hours
    } else if (unit.startsWith('w')) {
      return (val * 40 * 60).round(); // 1 workweek = 40 working hours
    } else if (unit.startsWith('mo')) {
      return (val * 160 * 60).round(); // 1 workmonth = 160 working hours
    }
    return 0;
  }

  static String formatMinutes(int totalMinutes) {
    if (totalMinutes <= 0) return '';

    if (totalMinutes < 60) {
      return '${totalMinutes}m';
    }

    // Pure Hours (h) model (Linear & GitHub standard)
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
  bool isExpanded;
  String? specNotes;
  String? verification;
  bool verificationCompleted;
  String? codeSnippet;
  String? codeTargetFile;
  String? codeLanguage;

  Subtask({
    required this.id,
    required this.text,
    this.completed = false,
    List<Subtask>? children,
    this.isExpanded = true,
    this.specNotes,
    this.verification,
    this.verificationCompleted = false,
    this.codeSnippet,
    this.codeTargetFile,
    this.codeLanguage,
  }) : children = children ?? [];

  /// Number of completed child subtasks
  int get completedChildrenCount => children.where((c) => c.completed).length;

  /// Total number of child subtasks
  int get totalChildrenCount => children.length;

  /// Total number of atomic leaf checkboxes in this subtree
  int get leafCount =>
      children.isEmpty ? 1 : children.fold(0, (sum, c) => sum + c.leafCount);

  /// Number of completed atomic leaf checkboxes in this subtree
  int get completedLeafCount => children.isEmpty
      ? (completed ? 1 : 0)
      : children.fold(0, (sum, c) => sum + c.completedLeafCount);

  /// Returns count of executable leaf substeps.
  /// For an unbroken top-level task, returns 0 so it never adds phantom ghost counts.
  /// For a broken-down task containing stages, returns the sum of stage substeps.
  /// For a stage with children, returns children.length.
  int get executableSubstepCount {
    if (children.isEmpty) return 0;
    return children.fold(
      0,
      (sum, c) => sum + (c.children.isNotEmpty ? c.children.length : 1),
    );
  }

  /// Returns count of completed executable leaf substeps.
  int get completedExecutableSubstepCount {
    if (children.isEmpty) return 0;
    return children.fold(
      0,
      (sum, c) =>
          sum +
          (c.children.isNotEmpty
              ? c.children.where((sc) => sc.completed).length
              : (c.completed ? 1 : 0)),
    );
  }

  /// Fractional progress (0.0 to 1.0) for this subtask item
  double get progress {
    if (children.isEmpty) {
      return completed ? 1.0 : 0.0;
    }
    final total = leafCount;
    if (total == 0) return 0.0;
    return completedLeafCount / total;
  }

  /// Whether this task is considered completed, either explicitly or because all its
  /// child subtasks/substeps/leaf checkboxes are completed.
  bool get isDone =>
      completed ||
      (children.isNotEmpty &&
          (children.every((c) => c.completed) ||
              (executableSubstepCount > 0 &&
                  completedExecutableSubstepCount == executableSubstepCount) ||
              (leafCount > 0 && completedLeafCount == leafCount)));

  static final RegExp _childSplitRegex = RegExp(r',\s*');
  static final RegExp _quotesTrimRegex = RegExp(r'''^["']|["']$''');
  static final RegExp _healPatternRegex = RegExp(
    r'^\{\s*text:\s*(.+?)(?:,\s*[Cc]hildren:\s*\[(.*)\]\s*)?\}?$',
    caseSensitive: false,
    dotAll: true,
  );
  static final RegExp _curlyTrimRegex = RegExp(r'^\{|\}$');

  factory Subtask.fromJson(Map<String, dynamic> json) {
    var rawText = json['text'] as String? ?? '';
    final rawChildren = json['children'] as List<dynamic>? ?? [];
    var childrenList = rawChildren
        .map((e) => Subtask.fromJson(e as Map<String, dynamic>))
        .toList();

    // Auto-heal stringified map representations like:
    // {text: Step Goal, Children: [Sub 1, Sub 2]} or {text: Step Goal, children: [Sub 1, Sub 2]}
    final trimmed = rawText.trim();
    if (trimmed.startsWith('{') &&
        (trimmed.contains('text:') || trimmed.contains('Text:'))) {
      final match = _healPatternRegex.firstMatch(trimmed);
      if (match != null) {
        rawText = match.group(1)?.trim() ?? rawText;
        final nestedChildrenStr = match.group(2);
        if (nestedChildrenStr != null &&
            nestedChildrenStr.trim().isNotEmpty &&
            childrenList.isEmpty) {
          final childItems = _splitUnpackedChildren(nestedChildrenStr);
          var idx = 0;
          final now = DateTime.now().millisecondsSinceEpoch;
          childrenList = childItems.map((c) {
            idx++;
            return Subtask(
              id: 'st-$now-$idx',
              text: c,
            );
          }).toList();
        }
      }
      rawText = rawText.replaceAll(_curlyTrimRegex, '').trim();
      if (rawText.toLowerCase().startsWith('text:')) {
        rawText = rawText.substring(5).trim();
      }
    }

    return Subtask(
      id: json['id'] as String? ??
          'st-${DateTime.now().millisecondsSinceEpoch}',
      text: rawText,
      completed: json['completed'] as bool? ?? false,
      children: childrenList,
      isExpanded: json['isExpanded'] as bool? ?? true,
      specNotes: json['specNotes'] as String? ?? json['spec_notes'] as String?,
      verification: json['verification'] as String?,
      verificationCompleted: json['verificationCompleted'] as bool? ?? false,
      codeSnippet: json['codeSnippet'] as String?,
      codeTargetFile: json['codeTargetFile'] as String? ?? json['code_target_file'] as String?,
      codeLanguage: json['codeLanguage'] as String?,
    );
  }

  static List<String> _splitUnpackedChildren(String raw) {
    return raw
        .split(_childSplitRegex)
        .map((s) => s.trim().replaceAll(_quotesTrimRegex, ''))
        .where((s) => s.isNotEmpty)
        .toList();
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'completed': completed,
      'children': children.map((c) => c.toJson()).toList(),
      'isExpanded': isExpanded,
      if (specNotes != null && specNotes!.isNotEmpty) 'specNotes': specNotes,
      if (verification != null && verification!.isNotEmpty)
        'verification': verification,
      if (verificationCompleted) 'verificationCompleted': verificationCompleted,
      if (codeSnippet != null && codeSnippet!.isNotEmpty)
        'codeSnippet': codeSnippet,
      if (codeTargetFile != null && codeTargetFile!.isNotEmpty)
        'codeTargetFile': codeTargetFile,
      if (codeLanguage != null && codeLanguage!.isNotEmpty)
        'codeLanguage': codeLanguage,
    };
  }

  Subtask copyWith({
    String? id,
    String? text,
    bool? completed,
    List<Subtask>? children,
    bool? isExpanded,
    String? specNotes,
    String? verification,
    bool? verificationCompleted,
    String? codeSnippet,
    String? codeTargetFile,
    String? codeLanguage,
  }) {
    return Subtask(
      id: id ?? this.id,
      text: text ?? this.text,
      completed: completed ?? this.completed,
      children: children ?? this.children.map((c) => c.copyWith()).toList(),
      isExpanded: isExpanded ?? this.isExpanded,
      specNotes: specNotes ?? this.specNotes,
      verification: verification ?? this.verification,
      verificationCompleted:
          verificationCompleted ?? this.verificationCompleted,
      codeSnippet: codeSnippet ?? this.codeSnippet,
      codeTargetFile: codeTargetFile ?? this.codeTargetFile,
      codeLanguage: codeLanguage ?? this.codeLanguage,
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
  String get estimatedDuration =>
      DurationHelper.normalizeToHours(_estimatedDuration ?? '');
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

  ReleaseScope get releaseScope => ReleaseScope.fromDocument(this);

  /// Semantic version for Release documents (e.g. "v1.2.0" or "v0.1").
  String get releaseVersion {
    final v = sections['version']?.trim();
    if (v != null && v.isNotEmpty) {
      return v.startsWith('v') ? v : 'v$v';
    }
    final match =
        RegExp(r'v?(\d+\.\d+(?:\.\d+)?)', caseSensitive: false).firstMatch(title);
    if (match != null) {
      final matched = match.group(1)!;
      return 'v$matched';
    }
    return 'v0.1.0';
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

  static final RegExp indentedBulletMatchRegex =
      RegExp(r'^\s{2,}[\•\-\*]\s*');
  static final RegExp leadingBulletCleanRegex =
      RegExp(r'^(?:[0-9]+[\.\)]|\s*[\-\•\>]\s*|\s*\*(?!\*)\s*|\s*\[[\s xX]?\]\s*)+\s*');

  /// Strips leading bullet markers ("• ", "- ", "* ", "1. ", etc.) from all lines of text.
  static String cleanBulletPrefixes(String text) {
    if (text.isEmpty) return text;
    final lines = text.split('\n');
    final cleaned = <String>[];
    for (final rawLine in lines) {
      final trimmed = rawLine.trim();
      if (trimmed.isEmpty) {
        cleaned.add('');
        continue;
      }
      String cleanLine;
      if (indentedBulletMatchRegex.hasMatch(rawLine)) {
        cleanLine = rawLine.replaceFirst(indentedBulletMatchRegex, '').trim();
      } else {
        cleanLine = trimmed.replaceFirst(leadingBulletCleanRegex, '').trim();
      }
      cleaned.add(cleanLine);
    }
    return cleaned.join('\n').trim();
  }
}


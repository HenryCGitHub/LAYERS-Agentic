import 'package:flutter/material.dart';
import '../constants/tiers.dart';

enum InboxCategory {
  bug,
  mechanic,
  polish,
  idea;

  String get label => switch (this) {
        InboxCategory.bug => 'Bug',
        InboxCategory.mechanic => 'Mechanic',
        InboxCategory.polish => 'Polish',
        InboxCategory.idea => 'Idea',
      };

  String get emoji => switch (this) {
        InboxCategory.bug => '🐛',
        InboxCategory.mechanic => '⚡',
        InboxCategory.polish => '✨',
        InboxCategory.idea => '💡',
      };

  Color get color => const Color(0xFF71717A);

  static InboxCategory fromString(String? val) {
    if (val == null) return InboxCategory.mechanic;
    final lower = val.trim().toLowerCase();
    for (final cat in InboxCategory.values) {
      if (cat.name == lower || cat.label.toLowerCase() == lower) {
        return cat;
      }
    }
    return InboxCategory.mechanic;
  }

  static InboxCategory detectFromText(String text) {
    final lower = text.trim().toLowerCase();
    if (lower.startsWith('!bug') ||
        lower.contains('bug') ||
        lower.contains('fix') ||
        lower.contains('error') ||
        lower.contains('crash') ||
        lower.contains('glitch') ||
        lower.contains('broken') ||
        lower.contains('issue') ||
        lower.contains('fail') ||
        lower.contains('stutter') ||
        lower.contains('flicker') ||
        lower.contains('desync') ||
        lower.contains('leak') ||
        lower.contains('missing collision') ||
        lower.contains('falls through')) {
      return InboxCategory.bug;
    }
    if (lower.startsWith('!polish') ||
        lower.contains('screenshake') ||
        lower.contains('screen shake') ||
        lower.contains('juice') ||
        lower.contains('sfx') ||
        lower.contains('audio') ||
        lower.contains('sound') ||
        lower.contains('particle') ||
        lower.contains('vfx') ||
        lower.contains('hitstop') ||
        lower.contains('camera') ||
        lower.contains('feel') ||
        lower.contains('animation') ||
        lower.contains('anim ') ||
        lower.contains('smooth') ||
        lower.contains('lighting') ||
        lower.contains('visual') ||
        lower.contains('glow') ||
        lower.contains('hud polish') ||
        lower.contains('soundscape') ||
        lower.contains('footstep')) {
      return InboxCategory.polish;
    }
    if (lower.startsWith('!idea') ||
        lower.startsWith('what if') ||
        lower.startsWith('maybe ') ||
        lower.contains('concept') ||
        lower.contains('dlc') ||
        lower.contains('post launch') ||
        lower.contains('post-launch') ||
        lower.contains('multiplayer mmo') ||
        lower.contains('pvp arena') ||
        lower.contains('sequel')) {
      return InboxCategory.idea;
    }
    return InboxCategory.mechanic;
  }
}

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

/// Represents a single observable criterion item within a task's verification gate.
class VerificationItem {
  final int index;
  final String text;
  final bool isChecked;
  final String rawLine;

  const VerificationItem({
    required this.index,
    required this.text,
    required this.isChecked,
    required this.rawLine,
  });
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

  static final RegExp _explicitCheckedRegex = RegExp(r'\[[xX]\]');
  static final RegExp _explicitUncheckedRegex = RegExp(r'\[\s*\]');
  static final RegExp _cleanBulletRegex = RegExp(r'^[\-\*\•\d\.\)]+\s*');
  static final RegExp _cleanCheckboxRegex = RegExp(r'^\[[ xX]\]\s*');
  static final RegExp _bulletPrefixRegex = RegExp(r'^(\s*[\-\*\•\d\.\)]+\s*)');
  static final RegExp _childSplitRegex = RegExp(r',\s*');
  static final RegExp _quotesTrimRegex = RegExp(r'''^["']|["']$''');
  static final RegExp _healPatternRegex = RegExp(
    r'^\{\s*text:\s*(.+?)(?:,\s*[Cc]hildren:\s*\[(.*)\]\s*)?\}?$',
    caseSensitive: false,
    dotAll: true,
  );
  static final RegExp _curlyTrimRegex = RegExp(r'^\{|\}$');

  /// Parses [verification] markdown text into individual observable criteria items.
  List<VerificationItem> get verificationItems {
    if (verification == null || verification!.trim().isEmpty) return const [];
    final rawLines = verification!.split('\n');
    final items = <VerificationItem>[];
    int itemIdx = 0;
    for (final line in rawLines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      final isExplicitChecked = _explicitCheckedRegex.hasMatch(trimmed);
      final isExplicitUnchecked = _explicitUncheckedRegex.hasMatch(trimmed);

      final cleanText = trimmed
          .replaceAll(_cleanBulletRegex, '')
          .replaceAll(_cleanCheckboxRegex, '')
          .trim();

      if (cleanText.isEmpty) continue;

      final checked = isExplicitChecked ||
          (!isExplicitUnchecked && verificationCompleted);
      items.add(VerificationItem(
        index: itemIdx++,
        text: cleanText,
        isChecked: checked,
        rawLine: trimmed,
      ));
    }
    return items;
  }

  /// Toggles an individual verification criterion at [itemIndex], updating the underlying
  /// [verification] text with `[x]` or `[ ]`, and synchronizing [verificationCompleted].
  void toggleVerificationItem(int itemIndex, {bool? completed}) {
    if (verification == null) return;
    final rawLines = verification!.split('\n');
    int currentItemIdx = 0;
    for (int i = 0; i < rawLines.length; i++) {
      final trimmed = rawLines[i].trim();
      if (trimmed.isEmpty) continue;

      final cleanText = trimmed
          .replaceAll(_cleanBulletRegex, '')
          .replaceAll(_cleanCheckboxRegex, '')
          .trim();
      if (cleanText.isEmpty) continue;

      if (currentItemIdx == itemIndex) {
        final isCurrentlyChecked = _explicitCheckedRegex.hasMatch(trimmed) ||
            (!_explicitUncheckedRegex.hasMatch(trimmed) && verificationCompleted);
        final targetChecked = completed ?? !isCurrentlyChecked;

        final bulletMatch = _bulletPrefixRegex.firstMatch(rawLines[i]);
        final prefix = bulletMatch?.group(1) ?? '- ';
        final box = targetChecked ? '[x] ' : '[ ] ';
        rawLines[i] = '$prefix$box$cleanText';
        break;
      }
      currentItemIdx++;
    }
    verification = rawLines.join('\n');

    final items = verificationItems;
    verificationCompleted =
        items.isNotEmpty && items.every((item) => item.isChecked);
  }

  /// Sets all individual criteria in [verification] to [completed].
  void setAllVerificationItems(bool completed) {
    if (verification == null) return;
    final rawLines = verification!.split('\n');
    for (int i = 0; i < rawLines.length; i++) {
      final trimmed = rawLines[i].trim();
      if (trimmed.isEmpty) continue;

      final cleanText = trimmed
          .replaceAll(_cleanBulletRegex, '')
          .replaceAll(_cleanCheckboxRegex, '')
          .trim();
      if (cleanText.isEmpty) continue;

      final bulletMatch = _bulletPrefixRegex.firstMatch(rawLines[i]);
      final prefix = bulletMatch?.group(1) ?? '- ';
      final box = completed ? '[x] ' : '[ ] ';
      rawLines[i] = '$prefix$box$cleanText';
    }
    verification = rawLines.join('\n');
    verificationCompleted = completed;
  }

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

/// Embedded work unit within a Feature document (Tier 1 of the Feature Checklist)
class TaskItem {
  final String id;
  String title;
  String? _estimatedDuration;
  String get estimatedDuration =>
      DurationHelper.normalizeToHours(_estimatedDuration ?? '2h');
  set estimatedDuration(String val) =>
      _estimatedDuration = DurationHelper.normalizeToHours(val);
  String discipline; // 'Code', 'Math', 'Audio', 'Feel', 'QA'
  bool isCompleted;
  List<Subtask> subtasks; // Tier 2 Items (with children for Tier 3 sub-steps)
  bool isExpanded;
  String? specNotes;
  String? verification;
  bool verificationCompleted;
  String? codeSnippet;
  String? codeTargetFile;
  String? codeLanguage;

  TaskItem({
    required this.id,
    required this.title,
    String? estimatedDuration,
    this.discipline = 'Code',
    this.isCompleted = false,
    List<Subtask>? subtasks,
    this.isExpanded = true,
    this.specNotes,
    this.verification,
    this.verificationCompleted = false,
    this.codeSnippet,
    this.codeTargetFile,
    this.codeLanguage,
  })  : _estimatedDuration =
            DurationHelper.normalizeToHours(estimatedDuration ?? '2h'),
        subtasks = subtasks ?? [];

  int get totalSubstepsCount => subtasks.fold<int>(
      0, (acc, s) => acc + (s.children.isEmpty ? 1 : s.children.length));

  int get completedSubstepsCount => subtasks.fold<int>(
      0,
      (acc, s) =>
          acc +
          (s.children.isEmpty
              ? (s.completed ? 1 : 0)
              : s.completedChildrenCount));

  double get progress {
    final total = totalSubstepsCount;
    if (total == 0) return isCompleted ? 1.0 : 0.0;
    return completedSubstepsCount / total;
  }

  factory TaskItem.fromJson(Map<String, dynamic> json) {
    final rawSubtasks = json['subtasks'] as List<dynamic>? ?? [];
    final subtaskList = rawSubtasks
        .map((e) => Subtask.fromJson(e as Map<String, dynamic>))
        .toList();

    return TaskItem(
      id: json['id'] as String? ?? generateUniqueId('task'),
      title: json['title'] as String? ?? 'Untitled Task',
      estimatedDuration: json['estimatedDuration'] as String? ??
          json['estimate'] as String? ??
          '2h',
      discipline: json['discipline'] as String? ?? 'Code',
      isCompleted: json['isCompleted'] as bool? ?? false,
      subtasks: subtaskList,
      isExpanded: json['isExpanded'] as bool? ?? true,
      specNotes: json['specNotes'] as String? ?? json['spec_notes'] as String?,
      verification: json['verification'] as String?,
      verificationCompleted: json['verificationCompleted'] as bool? ?? false,
      codeSnippet: json['codeSnippet'] as String?,
      codeTargetFile: json['codeTargetFile'] as String?,
      codeLanguage: json['codeLanguage'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'estimatedDuration': estimatedDuration,
      'discipline': discipline,
      'isCompleted': isCompleted,
      if (subtasks.isNotEmpty)
        'subtasks': subtasks.map((s) => s.toJson()).toList(),
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

  TaskItem copyWith({
    String? id,
    String? title,
    String? estimatedDuration,
    String? discipline,
    bool? isCompleted,
    List<Subtask>? subtasks,
    bool? isExpanded,
    String? specNotes,
    String? verification,
    bool? verificationCompleted,
    String? codeSnippet,
    String? codeTargetFile,
    String? codeLanguage,
  }) {
    return TaskItem(
      id: id ?? this.id,
      title: title ?? this.title,
      estimatedDuration: estimatedDuration ?? this.estimatedDuration,
      discipline: discipline ?? this.discipline,
      isCompleted: isCompleted ?? this.isCompleted,
      subtasks: subtasks ?? this.subtasks.map((s) => s.copyWith()).toList(),
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

class DocHistoryEntry {
  final String id;
  final String timestamp;
  final String author; // 'user', 'ai', 'ai_waterfall'
  final String summary;
  final Map<String, String> snapshotSections;

  DocHistoryEntry({
    required this.id,
    required this.timestamp,
    required this.author,
    required this.summary,
    required this.snapshotSections,
  });

  factory DocHistoryEntry.fromJson(Map<String, dynamic> json) {
    final rawSnap = json['snapshotSections'] as Map<String, dynamic>? ?? {};
    final snap = rawSnap.map((k, v) => MapEntry(k, v.toString()));
    return DocHistoryEntry(
      id: json['id'] as String? ??
          'hist-${DateTime.now().millisecondsSinceEpoch}',
      timestamp: json['timestamp'] as String? ?? '',
      author: json['author'] as String? ?? 'user',
      summary: json['summary'] as String? ?? 'Document updated',
      snapshotSections: snap,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'timestamp': timestamp,
      'author': author,
      'summary': summary,
      'snapshotSections': snapshotSections,
    };
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
  List<TaskItem> tasks;
  List<DocHistoryEntry> history;
  String? phase;
  bool isInbox;
  bool isIcebox;
  bool isCompleted;
  InboxCategory? inboxCategory;
  String? triageRationale;

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
    List<TaskItem>? tasks,
    List<DocHistoryEntry>? history,
    this.phase,
    this.isInbox = false,
    this.isIcebox = false,
    this.isCompleted = false,
    this.inboxCategory,
    this.triageRationale,
  })  : _estimatedDuration = DurationHelper.normalizeToHours(estimatedDuration ?? ''),
        childrenIds = childrenIds ?? [],
        sections = sections ?? {},
        subtasks = subtasks ?? [],
        tasks = tasks ?? [],
        history = history ?? [];

  factory TierDocument.fromJson(Map<String, dynamic> json) {
    final rawSections = json['sections'] as Map<String, dynamic>? ?? {};
    final sectionsMap = rawSections.map((k, v) => MapEntry(k, v.toString()));

    final rawSubtasks = json['subtasks'] as List<dynamic>? ?? [];
    final subtasksList = rawSubtasks
        .map((e) => Subtask.fromJson(e as Map<String, dynamic>))
        .toList();

    final rawTasks = json['tasks'] as List<dynamic>? ?? [];
    final tasksList = rawTasks
        .map((e) => TaskItem.fromJson(e as Map<String, dynamic>))
        .toList();

    final rawHist = json['history'] as List<dynamic>? ?? [];
    final histList = rawHist
        .map((e) => DocHistoryEntry.fromJson(e as Map<String, dynamic>))
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
      tasks: tasksList,
      history: histList,
      phase: json['phase'] as String?,
      isInbox: json['isInbox'] as bool? ?? false,
      isIcebox: json['isIcebox'] as bool? ?? false,
      isCompleted: json['isCompleted'] as bool? ?? false,
      inboxCategory: json['inboxCategory'] != null
          ? InboxCategory.fromString(json['inboxCategory'] as String?)
          : null,
      triageRationale: json['triageRationale'] as String?,
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
      'tasks': tasks.map((t) => t.toJson()).toList(),
      'history': history.map((h) => h.toJson()).toList(),
      'phase': phase,
      'isInbox': isInbox,
      'isIcebox': isIcebox,
      'isCompleted': isCompleted,
      if (inboxCategory != null) 'inboxCategory': inboxCategory!.name,
      if (triageRationale != null) 'triageRationale': triageRationale,
    };
  }

  bool get isFullyPopulated {
    if (tier == TierType.project) {
      final hasConcept = (sections['highConcept'] ??
              sections['pitch'] ??
              sections['vision'] ??
              sections['scope'] ??
              '')
          .trim()
          .isNotEmpty;
      return hasConcept;
    }
    final hasScope = (sections['scope'] ?? sections['work'] ?? '').trim().isNotEmpty;
    return hasScope;
  }

  ReleaseScope get releaseScope => ReleaseScope.fromDocument(this);
  ProjectDomain get projectDomain => ProjectDomain.fromDocument(this);

  /// The active completeness pass for this Release milestone (Rough, Build, Final).
  MilestonePass get milestonePass {
    final explicit = sections['milestonePass']?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      return MilestonePass.fromString(explicit);
    }
    final passSec = sections['pass']?.trim();
    if (passSec != null && passSec.isNotEmpty && passSec.length <= 24) {
      return MilestonePass.fromString(passSec);
    }
    final initialTitle = sections['initialTitle']?.trim() ?? '';
    if (initialTitle.isNotEmpty) {
      return MilestonePass.fromString('$title $initialTitle');
    }
    return MilestonePass.fromString(title);
  }

  /// The active completeness pass for this Feature (Rough, Build, Final).
  MilestonePass get featurePass {
    final explicit = sections['activePass'] ?? sections['pass'];
    return MilestonePass.fromString(explicit);
  }

  /// Entry pre-condition for an Epic loop beat.
  String? get entryCondition {
    final c = sections['entryCondition']?.trim();
    if (c != null && c.isNotEmpty) return c;
    final states = sections['states']?.trim() ?? '';
    if (states.isNotEmpty) {
      final match = RegExp(
        r'(?:Entry(?:\s+Pre-?condition)?|Entry\s+State)\s*:\s*([^\n\r]+)',
        caseSensitive: false,
      ).firstMatch(states);
      if (match != null && match.group(1)!.trim().isNotEmpty) {
        return match.group(1)!.trim();
      }
    }
    return null;
  }

  /// Exit handoff for an Epic loop beat.
  String? get exitHandoff {
    final h = sections['exitHandoff']?.trim();
    if (h != null && h.isNotEmpty) return h;
    final states = sections['states']?.trim() ?? '';
    if (states.isNotEmpty) {
      final match = RegExp(
        r'(?:Exit(?:\s+Handoff)?|Handoff)\s*:\s*([^\n\r]+)',
        caseSensitive: false,
      ).firstMatch(states);
      if (match != null && match.group(1)!.trim().isNotEmpty) {
        return match.group(1)!.trim();
      }
    }
    return null;
  }

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

  /// Title or ID of upstream blocking epic for an epic document.
  String? get blockedByTitle {
    final b = sections['blockedBy']?.trim();
    if (b == null || b.isEmpty || b.toLowerCase() == 'none') return null;
    return b;
  }

  /// Explicit technical blocker reason.
  String? get blockerReason {
    final r = sections['blockerReason']?.trim();
    if (r == null || r.isEmpty) return null;
    return r;
  }

  /// Discipline tag for this epic/feature (e.g. Code, Level Design, Audio, Art, Feel & Code).
  String? get disciplineTag {
    final d = sections['discipline']?.trim();
    if (d != null && d.isNotEmpty) return d;
    final lower = title.toLowerCase();
    if (lower.contains('audio') || lower.contains('sfx') || lower.contains('sound')) {
      return 'Audio';
    }
    if (lower.contains('arena') || lower.contains('level') || lower.contains('environment') || lower.contains('map')) {
      return 'Level Design';
    }
    if (lower.contains('camera') || lower.contains('juice') || lower.contains('feel') || lower.contains('vfx')) {
      return 'Feel & Code';
    }
    return 'Code';
  }

  /// Ship criteria string for this epic or release.
  String? get shipCriteria {
    final s = sections['shipCriteria']?.trim();
    if (s != null && s.isNotEmpty) return s;
    final pass = sections['pass']?.trim();
    if (pass != null && pass.isNotEmpty) return pass;
    return null;
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
    List<TaskItem>? tasks,
    List<DocHistoryEntry>? history,
    String? phase,
    bool? isInbox,
    bool? isIcebox,
    bool? isCompleted,
    InboxCategory? inboxCategory,
    String? triageRationale,
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
      tasks: tasks != null
          ? List<TaskItem>.from(tasks)
          : List<TaskItem>.from(this.tasks),
      history: history != null
          ? List<DocHistoryEntry>.from(history)
          : List<DocHistoryEntry>.from(this.history),
      phase: phase ?? this.phase,
      isInbox: isInbox ?? this.isInbox,
      isIcebox: isIcebox ?? this.isIcebox,
      isCompleted: isCompleted ?? this.isCompleted,
      inboxCategory: inboxCategory ?? this.inboxCategory,
      triageRationale: triageRationale ?? this.triageRationale,
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

class MergeRequest {
  final String keepTitle;
  final List<String> deleteTitles;

  MergeRequest({
    required this.keepTitle,
    required this.deleteTitles,
  });

  factory MergeRequest.fromJson(Map<String, dynamic> json) => MergeRequest(
        keepTitle: json['keepTitle']?.toString() ?? '',
        deleteTitles: (json['deleteTitles'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
      );

  Map<String, dynamic> toJson() => {
        'keepTitle': keepTitle,
        'deleteTitles': deleteTitles,
      };
}

class InheritedIgnoreItem {
  final String docId;
  final TierType tier;
  final String title;
  final String text;

  const InheritedIgnoreItem({
    required this.docId,
    required this.tier,
    required this.title,
    required this.text,
  });
}


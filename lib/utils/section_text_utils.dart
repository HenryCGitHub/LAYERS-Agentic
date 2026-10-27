/// Utility for parsing and resolving 3-part Scope & Goal sections across documents.
class SectionTextUtils {
  // ── Centralized 3-Part Scope Parsers (DRY — Project / Release / Epic / Feature) ──

  static final RegExp _goalMatchRegex =
      RegExp(r'Goal:\s*([^\n]+)', caseSensitive: false);
  static final RegExp _doneWhenMatchRegex = RegExp(
    r'Done\s*(?:When|If):\s*([^\n]+)',
    caseSensitive: false,
  );
  static final RegExp _inScopeHeaderRegex =
      RegExp(r'In Scope:\s*', caseSensitive: false);
  static final RegExp _headingCleanRegex = RegExp(r'^#+\s*');
  static final RegExp _asteriskCleanRegex = RegExp(r'^\*+\s*');
  static final RegExp _inScopeEndSplitRegex = RegExp(
    r'(?:Exclusions|Done\s*(?:When|If)|Out\s*(?:of\s*)?Scope):',
    caseSensitive: false,
  );
  static final RegExp _bulletPrefixStripRegex = RegExp(r'^[•\*\-\s]+');
  static final RegExp _exclusionsBlockRegex = RegExp(
    r'(?:Out of Scope|Out Scope|Exclusions):\s*([\s\S]*?)(?=(?:Done\s*(?:When|If)|In Scope):|$)',
    caseSensitive: false,
  );
  static final RegExp _exclusionSuffixRegex = RegExp(
    r'\s*(?:are|is)\s+(?:strictly\s+)?(?:out of scope|deferred|excluded|forbidden)[\s\S]*$',
    caseSensitive: false,
  );
  static final RegExp _trailingDotsRegex = RegExp(r'\.+$');
  static final RegExp _exclusionSplitRegex = RegExp(
    r',\s*(?:and\s+|or\s+)?|;\s*|\band\s+',
    caseSensitive: false,
  );

  /// Resolves the single-sentence Goal from a document's `sections`.
  static String resolveGoal(Map<String, String> sections) {
    final raw = sections['scope'] ??
        sections['goal'] ??
        sections['milestoneGoal'] ??
        sections['description'];
    if (raw != null && raw.trim().isNotEmpty) {
      final match = _goalMatchRegex.firstMatch(raw);
      if (match != null && match.group(1)!.trim().isNotEmpty) {
        return match.group(1)!.trim();
      }
      final firstLine = raw
          .split('\n')
          .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
      if (firstLine.isNotEmpty) {
        return firstLine
            .replaceAll(_headingCleanRegex, '')
            .replaceAll(_asteriskCleanRegex, '')
            .trim();
      }
    }
    return '';
  }

  /// Resolves the `In Scope:` bullet list from a document's `sections`.
  static List<String> resolveInScope(Map<String, String> sections) {
    final raw = sections['scope'];
    if (raw != null && raw.trim().isNotEmpty) {
      if (_inScopeHeaderRegex.hasMatch(raw)) {
        final parts = raw.split(_inScopeHeaderRegex);
        if (parts.length > 1) {
          final after = parts[1].split(_inScopeEndSplitRegex)[0];
          final lines = after
              .split('\n')
              .map((l) => l.replaceAll(_bulletPrefixStripRegex, '').trim())
              .where((l) => l.isNotEmpty && !l.startsWith('#'))
              .toList();
          if (lines.isNotEmpty) return lines;
        }
      } else {
        // Fallback for scope text without an explicit "In Scope:" header:
        // Extract non-header, non-exclusion lines
        final lines = <String>[];
        bool inExclusions = false;
        for (final line in raw.split('\n')) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) continue;
          final lower = trimmed.toLowerCase();
          if (lower.startsWith('out of scope') || lower.startsWith('exclusions')) {
            inExclusions = true;
            continue;
          }
          if (lower.startsWith('goal:') ||
              lower.startsWith('done when:') ||
              lower.startsWith('done if:')) {
            inExclusions = false;
            continue;
          }
          if (!inExclusions) {
            final cleaned = trimmed.replaceAll(_bulletPrefixStripRegex, '').trim();
            if (cleaned.isNotEmpty && !cleaned.startsWith('#')) {
              lines.add(cleaned);
            }
          }
        }
        if (lines.isNotEmpty) return lines;
      }
    }
    return const [];
  }

  /// Resolves the `Exclusions` / `Out of Scope` bullet list from a document's `sections`.
  static List<String> resolveExclusions(
    Map<String, String> sections, {
    bool splitSingleSentence = true,
  }) {
    final results = <String>[];
    final seen = <String>{};

    void addLines(String text) {
      final rawLines = text
          .split('\n')
          .map((l) => l.replaceAll(_bulletPrefixStripRegex, '').trim())
          .where((l) => l.isNotEmpty && !l.startsWith('#'))
          .toList();

      if (rawLines.length == 1 && splitSingleSentence) {
        final splitItems = splitExclusionSentence(rawLines.first);
        for (final item in splitItems) {
          final cleaned = item.replaceAll(_bulletPrefixStripRegex, '').trim();
          if (cleaned.isNotEmpty && seen.add(cleaned.toLowerCase())) {
            results.add(cleaned);
          }
        }
      } else {
        for (final line in rawLines) {
          if (seen.add(line.toLowerCase())) {
            results.add(line);
          }
        }
      }
    }

    final rawIgnore = sections['ignore'] ??
        sections['exclusions'] ??
        sections['outOfScope'];
    if (rawIgnore != null && rawIgnore.trim().isNotEmpty) {
      addLines(rawIgnore);
    }

    if (sections['scope'] != null) {
      final match = _exclusionsBlockRegex.firstMatch(sections['scope']!);
      if (match != null && match.group(1)!.trim().isNotEmpty) {
        addLines(match.group(1)!.trim());
      }
    }

    return results;
  }

  /// Splits a comma/conjunction-separated exclusion sentence into discrete bullet items.
  static List<String> splitExclusionSentence(String text) {
    var cleaned = text.trim();
    cleaned = cleaned.replaceAll(_exclusionSuffixRegex, '');
    cleaned = cleaned.replaceAll(_trailingDotsRegex, '').trim();
    final parts = cleaned.split(_exclusionSplitRegex);
    final result = parts
        .map((p) => p.replaceAll(_bulletPrefixStripRegex, '').trim())
        .where((p) => p.isNotEmpty)
        .toList();
    return result.isNotEmpty ? result : [text];
  }

  static final RegExp _doneWhenSplitRegex = RegExp(
    r'Done When:\s*',
    caseSensitive: false,
  );

  /// Resolves the `Done When:` condition from a document's `sections`.
  static String resolveDoneWhen(Map<String, String> sections) {
    final raw = sections['scope'] ?? sections['pass'] ?? sections['doneWhen'];
    if (raw != null && raw.trim().isNotEmpty) {
      final match = _doneWhenMatchRegex.firstMatch(raw);
      if (match != null && match.group(1)!.trim().isNotEmpty) {
        return match.group(1)!.replaceAll(_bulletPrefixStripRegex, '').trim();
      }
      if (raw.toLowerCase().contains('done when:')) {
        final after = raw.split(_doneWhenSplitRegex)[1].trim();
        final firstLine = after
            .split('\n')
            .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
        if (firstLine.isNotEmpty) {
          return firstLine.replaceAll(_bulletPrefixStripRegex, '').trim();
        }
      }
    }
    return '';
  }
}


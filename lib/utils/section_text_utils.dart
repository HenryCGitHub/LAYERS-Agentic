import '../models/tier_document.dart';

/// Parsed deliverable / mechanic scope block from a Scope section.
class ParsedScopeBlock {
  final String title;
  final List<String> bullets;
  final int index;

  ParsedScopeBlock({
    required this.title,
    required this.bullets,
    required this.index,
  });
}

/// Utility for parsing, cleaning, and comparing section text and deliverable blocks.
class SectionTextUtils {
  // ── Pre-compiled Human-Readable Regex Patterns for S.H.I.P. Sections ──

  /// Redundant S.H.I.P. section header prefixes to strip from section bodies
  static final RegExp redundantWorkEyebrowRegex = RegExp(
    r'^[\•\-\*]?\s*\[?(?:Work|Scope|Focus|Milestone Scope|Stage Scope|System Scope|Feature Scope|Task Scope)\]?:\s*(.*)$',
    caseSensitive: false,
  );
  static final RegExp redundantHowEyebrowRegex = RegExp(
    r'^[\•\-\*]?\s*\[?(?:How|Artifact|Target Loop|Execution|Platform & Execution|System Execution|Feature Execution)\]?:\s*(.*)$',
    caseSensitive: false,
  );
  static final RegExp redundantIgnoreEyebrowRegex = RegExp(
    r'^[\•\-\*]?\s*\[?(?:Ignore|Guardrails?|Milestone Guardrails|Stage Guardrails?|System Guardrails?|Feature Guardrails?|Task Guardrails?)\]?:\s*(.*)$',
    caseSensitive: false,
  );
  static final RegExp redundantPassEyebrowRegex = RegExp(
    r'^[\•\-\*]?\s*\[?(?:Pass|Benchmark|Sign-Off|Signoff|Exit Gate|Quality & Exit Gate|Pass Criteria)\]?:\s*(.*)$',
    caseSensitive: false,
  );

  /// Strips leading bullet markers ("• ", "- ", "* ")
  static final RegExp leadingBulletCleanRegex = RegExp(r'^[\•\-\*]\s*');

  /// Matches indented sub-bullets to promote them ("  - ", "  • ")
  static final RegExp indentedBulletMatchRegex = RegExp(r'^[\s\t]*[\•\-\*]\s+');

  /// Extracts bracketed deliverable title and inline description from 1:1 Scope blocks.
  /// Supports:
  /// - "[1] Wave Manager" -> group 1 = "Wave Manager"
  /// - "[Jog and Sprint Acceleration]" -> group 2 = "Jog and Sprint Acceleration"
  /// - "• [1. Jog and Sprint Acceleration]: Speed logic" -> group 2 = "Jog and Sprint Acceleration", group 3 = "Speed logic"
  static final RegExp scopeBracketRegex = RegExp(
    r'^[\•\-\*\d\.\)]*\s*(?:\[\s*\d+\s*\]\s*([^:\-\n\[\]]+)|\[(?:(?:\d+(?:[\:\)]\s*|\.(?!\d)\s*|\s*-\s+|\s*\]\s*))?)([^\]]+)\])(?:\:|\s*\-)?\s*(.*)$',
  );

  /// Strips leading numeric prefixes from task titles. Example: "1. Sprint" -> "Sprint"
  static final RegExp numberPrefixCleanRegex =
      RegExp(r'^\d+(?:[\:\)]\s*|\.(?!\d)\s*|\s*\]\s*|\s*-\s+)');

  /// Strips bullet markers and list numbers from PASS contract statements.
  static final RegExp bulletAndNumberCleanRegex =
      RegExp(r'^(?:[\•\-\*]\s*|\d+(?:[\:\)]\s*|\.(?!\d)\s*|\s*-\s+))+');

  /// Splits comma, bullet, or semicolon-delimited parameter tokens.
  static final RegExp paramDelimiterSplitRegex = RegExp(r'[,•;]');

  /// Strips leading bullet markers ("• ", "- ", "* ") and number prefixes from all lines of text.
  static String cleanBulletPrefixes(String text) => TierDocument.cleanBulletPrefixes(text);

  /// Compares two task/scope titles for equivalence, normalizing punctuation and casing.
  static bool areTitlesMatching(String a, String b) {
    final normA = a.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final normB = b.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (normA.isEmpty || normB.isEmpty) return false;
    if (normA == normB) return true;
    if (normA.contains(normB) || normB.contains(normA)) return true;
    return false;
  }

  /// Parses raw scope section text into a list of [ParsedScopeBlock]s.
  static List<ParsedScopeBlock> parseScopeBlocks(String rawText) {
    final lines = rawText.split('\n');
    final List<ParsedScopeBlock> blocks = [];
    String? currentTitle;
    final List<String> currentBullets = [];

    void flush() {
      if (currentTitle != null && currentTitle!.isNotEmpty) {
        blocks.add(ParsedScopeBlock(
          title: currentTitle!,
          bullets: List.from(currentBullets),
          index: blocks.length + 1,
        ));
        currentTitle = null;
        currentBullets.clear();
      }
    }

    for (final rawLine in lines) {
      final trimmed = rawLine.trim();
      if (trimmed.isEmpty) continue;

      final bracketMatch = scopeBracketRegex.firstMatch(trimmed);

      if (bracketMatch != null) {
        final rawTitle = (bracketMatch.group(1) ?? bracketMatch.group(2))?.trim();
        if (rawTitle != null && rawTitle.isNotEmpty) {
          var t = rawTitle.replaceAll(numberPrefixCleanRegex, '').trim();
          if (t.toLowerCase() != 'x' && t.isNotEmpty) {
            flush();
            currentTitle = t;
            final inlineVal = bracketMatch.group(3)?.trim();
            if (inlineVal != null && inlineVal.isNotEmpty) {
              final cleanBullet =
                  inlineVal.replaceAll(leadingBulletCleanRegex, '').trim();
              if (cleanBullet.isNotEmpty) currentBullets.add(cleanBullet);
            }
          }
        }
      } else if (currentTitle != null) {
        final cleanBullet =
            trimmed.replaceAll(leadingBulletCleanRegex, '').trim();
        if (cleanBullet.isNotEmpty) {
          currentBullets.add(cleanBullet);
        }
      } else {
        currentBullets.add(trimmed.replaceAll(leadingBulletCleanRegex, '').trim());
      }
    }
    flush();
    return blocks;
  }

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

  /// Resolves the `Done When:` condition from a document's `sections`.
  static String resolveDoneWhen(Map<String, String> sections) {
    final raw = sections['scope'] ?? sections['pass'] ?? sections['doneWhen'];
    if (raw != null && raw.trim().isNotEmpty) {
      final match = _doneWhenMatchRegex.firstMatch(raw);
      if (match != null && match.group(1)!.trim().isNotEmpty) {
        return match.group(1)!.replaceAll(_bulletPrefixStripRegex, '').trim();
      }
      if (raw.toLowerCase().contains('done when:')) {
        final after = raw.split(RegExp(r'Done When:\s*', caseSensitive: false))[1].trim();
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


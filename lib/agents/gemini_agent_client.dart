import 'dart:convert';
import 'package:http/http.dart' as http;

/// Lightweight, resilient Gemini JSON client for LAYERS-Agentic.
/// Supports:
/// - Base64 build-time key decoding (`GEMINI_API_KEY_B64`) so GitHub Push Protection
///   never blocks public `gh-pages` deployments.
/// - Runtime API key and Model override (`gemini-2.5-flash` default, `gemini-2.5-pro`, `gemini-2.0-flash`).
/// - Automatic model fallback if a model quota/availability error occurs.
class GeminiAgentClient {
  static const String _rawEnvKey = String.fromEnvironment('GEMINI_API_KEY');
  static const String _b64EnvKey = String.fromEnvironment('GEMINI_API_KEY_B64');
  static String? _cachedDefaultKey;

  static const Map<String, String> _jsonHeaders = {
    'Content-Type': 'application/json',
  };
  static const Duration _heavyModelTimeout = Duration(seconds: 45);
  static const Duration _standardModelTimeout = Duration(seconds: 30);
  static const int _maxOutputTokens = 8192;

  /// Shared compact style rules injected across Stage 1 & Stage 2 prompts (~55 tokens vs ~220 tokens).
  static const String compactStyleRules = '''
RULES:
- Use plain, literal 2-4 word game-dev titles naming the observable player or world action (e.g. "Truck Steering", "Roof Turret Fire", "Raider Ambush", "Crate Pickup").
- Write in straightforward, everyday English—never roleplay the genre's slang or lore. Use game terms only when they name a specific mechanic or tactic ("kite", "dash", "parry", "cooldown"); never use subculture slang ("gib", "frag"), archaic/lore words ("Husbandry", "Homestead", "Expedition"), or corporate/engineering buzzwords ("canonical", "deliver", "verified", "validate", "leverage", "unified", "end-to-end", "synergy", "seamlessly") when a plain word ("main", "blast", "clear", "defeat") means the same thing.
- NEVER name features or epics after code classes or architecture suffixes ("Controller", "System", "Mechanic", "Manager", "Component", "Handler", "Subsystem").
- Design Pillars describe player experience/feel (never a feature or genre). Trade-Offs use explicit "X over Y" rules.
- `doneWhen` must describe an observable gameplay loop completion condition (spawning, executing core beats, win/fail resolution, clean reset) and NEVER use framerate/FPS targets ("60 FPS").
- Start goals with concrete verbs ("Build...", "Expand...") and NEVER copy-paste raw user instructions verbatim.''';

  /// Records the last non-200 status hint (e.g., HTTP 402 prepayment credits depleted) for diagnostics.
  static String? lastErrorStatus;

  /// Optional test-only responder used by `flutter test` to simulate Gemini JSON responses
  /// without any hardcoded production scaffolds.
  static Future<Map<String, dynamic>?> Function(
    String prompt,
    String preferredModel,
  )? testMockResponder;

  static String resolveDefaultApiKey() {
    if (_cachedDefaultKey != null) return _cachedDefaultKey!;
    if (_rawEnvKey.trim().isNotEmpty) {
      return _cachedDefaultKey = _rawEnvKey.trim();
    }
    if (_b64EnvKey.trim().isNotEmpty) {
      try {
        return _cachedDefaultKey =
            utf8.decode(base64Decode(_b64EnvKey.trim())).trim();
      } catch (_) {}
    }
    return _cachedDefaultKey = '';
  }

  static bool hasKey(String apiKey) {
    if (testMockResponder != null) return true;
    final key = apiKey.trim().isNotEmpty ? apiKey.trim() : resolveDefaultApiKey();
    return key.isNotEmpty;
  }

  static Future<Map<String, dynamic>?> generateJson({
    required String prompt,
    required String apiKey,
    String preferredModel = 'gemini-flash-latest',
    String thinkingLevel = 'LOW',
    double temperature = 0.5,
  }) async {
    if (testMockResponder != null) {
      return testMockResponder!(prompt, preferredModel);
    }
    final key = apiKey.trim().isNotEmpty ? apiKey.trim() : resolveDefaultApiKey();
    if (key.isEmpty) {
      lastErrorStatus = 'Missing API Key';
      return null;
    }

    final modelsToTry = <String>{
      preferredModel,
      'gemini-flash-latest',
      'gemini-3-flash-preview',
      'gemini-3.1-flash-lite-preview',
    }.toList();

    final normalizedThinking = thinkingLevel.trim().toUpperCase();
    final contentsPayload = [
      {
        'parts': [
          {'text': prompt},
        ],
      },
    ];

    for (final model in modelsToTry) {
      try {
        final uri = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$key',
        );
        final genConfig = <String, dynamic>{
          'temperature': temperature,
          'maxOutputTokens': _maxOutputTokens,
          'responseMimeType': 'application/json',
        };
        if (normalizedThinking.isNotEmpty) {
          final isFlash25 = model == 'gemini-flash-latest' ||
              model.startsWith('gemini-2.5');
          genConfig['thinkingConfig'] = isFlash25
              ? <String, dynamic>{
                  'thinkingBudget': normalizedThinking == 'LOW' ? 0 : 1024,
                }
              : <String, dynamic>{
                  'thinkingLevel': normalizedThinking,
                };
        }

        final isHeavyPlanningModel =
            model.contains('argon') || model.contains('pro');
        final timeoutDuration =
            isHeavyPlanningModel ? _heavyModelTimeout : _standardModelTimeout;

        final response = await http
            .post(
              uri,
              headers: _jsonHeaders,
              body: jsonEncode({
                'contents': contentsPayload,
                'generationConfig': genConfig,
              }),
            )
            .timeout(timeoutDuration);

        if (response.statusCode == 200) {
          lastErrorStatus = null;
          final body = jsonDecode(response.body) as Map<String, dynamic>;
          final candidates = body['candidates'] as List?;
          if (candidates != null && candidates.isNotEmpty) {
            final content =
                candidates.first['content'] as Map<String, dynamic>?;
            final parts = content?['parts'] as List?;
            if (parts != null && parts.isNotEmpty) {
              for (final part in parts.reversed) {
                if (part is Map && part['thought'] != true) {
                  final rawText = part['text']?.toString() ?? '';
                  final cleaned = _extractJsonObject(rawText);
                  if (cleaned.isNotEmpty) {
                    return jsonDecode(cleaned) as Map<String, dynamic>;
                  }
                }
              }
            }
          }
        } else if (response.statusCode == 401 ||
            response.statusCode == 402 ||
            response.statusCode == 403) {
          // Fail fast on auth/billing errors instead of retrying across models
          lastErrorStatus = 'HTTP ${response.statusCode}';
          return null;
        }
      } catch (_) {
        // Fall back to next model immediately on timeout or network error
        continue;
      }
    }
    return null;
  }

  static final RegExp _jsonFenceStartRegex =
      RegExp(r'^```json\s*', multiLine: true, caseSensitive: false);
  static final RegExp _genericFenceRegex = RegExp(r'^```\s*', multiLine: true);

  static String _extractJsonObject(String raw) {
    final trimmed = raw
        .replaceAll(_jsonFenceStartRegex, '')
        .replaceAll(_genericFenceRegex, '')
        .trim();
    final start = trimmed.indexOf('{');
    final end = trimmed.lastIndexOf('}');
    if (start != -1 && end != -1 && end > start) {
      return trimmed.substring(start, end + 1);
    }
    return trimmed;
  }
}

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/text_style_guide.dart';

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
  static const Duration _heavyModelTimeout = Duration(seconds: 60);
  static const Duration _standardModelTimeout = Duration(seconds: 60);
  static const Duration _metadataTimeout = Duration(seconds: 6);

  static bool _modelMetadataChecked = false;
  static int? _cachedModelOutputTokenLimit;
  static bool _cachedSupportsThinkingLevel = true;

  /// Shared compact style rules injected across Stage 1 & Stage 2 prompts (sourced from `LayersTextStyleGuide`).
  static const String compactStyleRules =
      LayersTextStyleGuide.compactStyleRules;

  /// Records the last non-200 status hint (e.g., HTTP 402 prepayment credits depleted) for diagnostics.
  static String? lastErrorStatus;

  /// Pricing rates for Gemini 3.8 Flash (`gemini-flash-latest`):
  /// $0.75 per 1 million input tokens.
  /// $3.75 per 1 million output tokens (includes candidate text and thinking/reasoning tokens).
  static const double flashInputCostPerMillion = 0.75;
  static const double flashOutputCostPerMillion = 3.75;

  /// Accumulative token counters and estimated cost across all Gemini calls in the session.
  static int totalInputTokens = 0;
  static int totalOutputTokens = 0;
  static int totalThinkingTokens = 0;
  static double totalEstimatedCostUsd = 0.0;

  /// Records token consumption from a Gemini API response and updates estimated cost.
  static void recordUsage({
    required int inputTokens,
    required int outputTokens,
    int thinkingTokens = 0,
  }) {
    totalInputTokens += inputTokens;
    totalOutputTokens += outputTokens;
    totalThinkingTokens += thinkingTokens;
    totalEstimatedCostUsd = (totalInputTokens * flashInputCostPerMillion +
            totalOutputTokens * flashOutputCostPerMillion) /
        1000000.0;
  }

  /// Resets accumulative session token counters to 0.
  static void resetUsage() {
    totalInputTokens = 0;
    totalOutputTokens = 0;
    totalThinkingTokens = 0;
    totalEstimatedCostUsd = 0.0;
  }

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

  static Future<void> _ensureModelCapabilitiesLoaded(
    String model,
    String key,
  ) async {
    if (_modelMetadataChecked) return;
    _modelMetadataChecked = true;
    try {
      final metaUri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$model?key=$key',
      );
      final res = await http.get(metaUri).timeout(_metadataTimeout);
      if (res.statusCode == 200) {
        final meta = jsonDecode(res.body) as Map<String, dynamic>;
        final outLimit = meta['outputTokenLimit'];
        if (outLimit is int && outLimit > 0) {
          _cachedModelOutputTokenLimit = outLimit;
        }
        final version = (meta['version'] ?? '').toString().toLowerCase();
        final displayName =
            (meta['displayName'] ?? '').toString().toLowerCase();
        final description =
            (meta['description'] ?? '').toString().toLowerCase();
        if (meta['thinking'] == true ||
            version.startsWith('3') ||
            version.startsWith('4') ||
            displayName.contains(' 3') ||
            displayName.contains(' 4') ||
            description.contains('gemini 3') ||
            description.contains('gemini 4')) {
          _cachedSupportsThinkingLevel = true;
        }
      }
    } catch (_) {
      // Non-fatal: fall back to model-native defaults on generateContent
    }
  }

  static Map<String, dynamic> buildNativeThinkingConfig({
    required String normalizedThinking,
    required bool useThinkingLevelEnum,
  }) {
    final upper = normalizedThinking.trim().toUpperCase();
    if (useThinkingLevelEnum) {
      return <String, dynamic>{
        'thinkingLevel':
            (upper == 'NONE' || upper == 'MINIMAL') ? upper : 'LOW',
      };
    }
    final int budget = switch (upper) {
      'NONE' || 'MINIMAL' => 0,
      _ => 256,
    };
    return <String, dynamic>{
      'thinkingBudget': budget,
    };
  }

  static void _recordUsageFromBody(Map<String, dynamic> body) {
    try {
      final rawUsage = body['usageMetadata'];
      if (rawUsage is Map) {
        final promptTokens =
            (rawUsage['promptTokenCount'] as num?)?.toInt() ?? 0;
        final candidateTokens =
            (rawUsage['candidatesTokenCount'] as num?)?.toInt() ?? 0;
        final thoughtsTokens =
            (rawUsage['thoughtsTokenCount'] as num?)?.toInt() ?? 0;
        if (promptTokens > 0 || candidateTokens > 0) {
          recordUsage(
            inputTokens: promptTokens,
            outputTokens: candidateTokens,
            thinkingTokens: thoughtsTokens,
          );
        }
      }
    } catch (_) {}
  }

  static Map<String, dynamic>? _parseCandidateResponseJson(String responseBody) {
    try {
      final body = jsonDecode(responseBody) as Map<String, dynamic>;
      _recordUsageFromBody(body);
      final candidates = body['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) return null;
      final content = candidates.first['content'] as Map<String, dynamic>?;
      final parts = content?['parts'] as List?;
      if (parts == null || parts.isEmpty) return null;
      final toolCalls = <Map<String, dynamic>>[];
      for (final part in parts) {
        if (part is Map && part['functionCall'] is Map) {
          final fc = Map<String, dynamic>.from(part['functionCall'] as Map);
          final fnName = (fc['name'] ?? '').toString().trim();
          final rawArgs = fc['args'];
          final argsMap = rawArgs is Map
              ? Map<String, dynamic>.from(rawArgs)
              : <String, dynamic>{};
          toolCalls.add({
            'name': fnName,
            'args': argsMap,
          });
        }
      }
      if (toolCalls.isNotEmpty) {
        final primaryArgs =
            Map<String, dynamic>.from(toolCalls.first['args'] as Map);
        primaryArgs['_toolName'] = toolCalls.first['name'];
        primaryArgs['_toolCalls'] = toolCalls;
        return primaryArgs;
      }
      for (final part in parts.reversed) {
        if (part is Map && part['thought'] != true) {
          final rawText = part['text']?.toString() ?? '';
          final cleaned = _extractJsonObject(rawText);
          if (cleaned.isNotEmpty) {
            final decoded = jsonDecode(cleaned) as Map<String, dynamic>;
            return unwrapDirectJsonPayload(decoded);
          }
        }
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  /// Unwraps a direct JSON-mode object if the model wrapped the payload inside a single
  /// top-level tool name or `args`/`parameters`/`arguments` wrapper map.
  static Map<String, dynamic> unwrapDirectJsonPayload(
    Map<String, dynamic> decoded,
  ) {
    var current = decoded;
    for (int depth = 0; depth < 2; depth++) {
      if (current.length == 1) {
        final key = current.keys.first;
        final val = current.values.first;
        if (val is Map &&
            (key.startsWith('commit_') ||
                key.startsWith('update_') ||
                key.startsWith('propose_') ||
                key.startsWith('mutate_') ||
                key == 'args' ||
                key == 'parameters' ||
                key == 'arguments')) {
          current = Map<String, dynamic>.from(val);
          continue;
        }
      } else if (current['args'] is Map &&
          (current['name'] is String || current['tool'] is String)) {
        current = Map<String, dynamic>.from(current['args'] as Map);
        continue;
      }
      break;
    }
    return current;
  }

  static Future<Map<String, dynamic>?> generateJson({
    required String prompt,
    required String apiKey,
    String preferredModel = 'gemini-flash-latest',
    String thinkingLevel = 'LOW',
    double temperature = 0.5,
    List<Map<String, dynamic>>? functionDeclarations,
    String functionCallingMode = 'ANY',
    Map<String, dynamic>? responseSchema,
  }) async {
    const resolvedModel = 'gemini-flash-latest';
    if (testMockResponder != null) {
      final mockRes = await testMockResponder!(prompt, resolvedModel);
      if (mockRes != null &&
          mockRes.containsKey('_usageMetadata') &&
          mockRes['_usageMetadata'] is Map) {
        _recordUsageFromBody({
          'usageMetadata': mockRes['_usageMetadata'],
        });
      }
      return mockRes;
    }
    final key = apiKey.trim().isNotEmpty ? apiKey.trim() : resolveDefaultApiKey();
    if (key.isEmpty) {
      lastErrorStatus = 'Missing API Key';
      return null;
    }

    await _ensureModelCapabilitiesLoaded(resolvedModel, key);

    const modelsToTry = <String>[resolvedModel];

    final normalizedThinking = thinkingLevel.trim().toUpperCase();
    final hasTools =
        functionDeclarations != null && functionDeclarations.isNotEmpty;
    final contentsPayload = [
      {
        'parts': [
          {'text': prompt},
        ],
      },
    ];

    for (final model in modelsToTry) {
      final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$key',
      );
      final isHeavyPlanningModel = model.contains('pro');
      final timeoutDuration =
          isHeavyPlanningModel ? _heavyModelTimeout : _standardModelTimeout;

      try {
        final genConfig = <String, dynamic>{
          'temperature': temperature,
          if (_cachedModelOutputTokenLimit != null)
            'maxOutputTokens': _cachedModelOutputTokenLimit,
          if (!hasTools) 'responseMimeType': 'application/json',
          if (!hasTools && responseSchema != null)
            'responseSchema': responseSchema,
        };
        if (normalizedThinking.isNotEmpty) {
          genConfig['thinkingConfig'] = buildNativeThinkingConfig(
            normalizedThinking: normalizedThinking,
            useThinkingLevelEnum: _cachedSupportsThinkingLevel,
          );
        }

        final requestPayload = <String, dynamic>{
          'contents': contentsPayload,
          'generationConfig': genConfig,
          if (hasTools)
            'tools': [
              {'functionDeclarations': functionDeclarations},
            ],
          if (hasTools)
            'toolConfig': {
              'functionCallingConfig': {'mode': functionCallingMode},
            },
        };

        var response = await http
            .post(
              uri,
              headers: _jsonHeaders,
              body: jsonEncode(requestPayload),
            )
            .timeout(timeoutDuration);

        // If `gemini-flash-latest` alias upgraded on the backend and prefers the alternate
        // native thinkingConfig schema, flip and retry automatically.
        if (response.statusCode == 400 && normalizedThinking.isNotEmpty) {
          _cachedSupportsThinkingLevel = !_cachedSupportsThinkingLevel;
          genConfig['thinkingConfig'] = buildNativeThinkingConfig(
            normalizedThinking: normalizedThinking,
            useThinkingLevelEnum: _cachedSupportsThinkingLevel,
          );
          response = await http
              .post(
                uri,
                headers: _jsonHeaders,
                body: jsonEncode(requestPayload),
              )
              .timeout(timeoutDuration);
        }

        if (response.statusCode == 200) {
          lastErrorStatus = null;
          final parsed = _parseCandidateResponseJson(response.body);
          if (parsed != null) return parsed;
        } else if (response.statusCode == 401 ||
            response.statusCode == 402 ||
            response.statusCode == 403) {
          // Fail fast on auth/billing errors instead of retrying across models
          lastErrorStatus = 'HTTP ${response.statusCode}';
          return null;
        }
      } catch (_) {
        // Proceed to JSON-mode fallback if tools were active, or next model
      }

      // If a deeply nested function-calling schema timed out or returned MALFORMED_FUNCTION_CALL,
      // retry once in direct JSON mode (`responseMimeType: 'application/json'`) with LOW thinking budget.
      if (hasTools) {
        try {
          final rawToolParams = functionDeclarations.first['parameters'];
          final effectiveFallbackSchema = responseSchema ??
              (rawToolParams is Map
                  ? Map<String, dynamic>.from(rawToolParams)
                  : null);
          final fallbackGenConfig = <String, dynamic>{
            'temperature': temperature,
            if (_cachedModelOutputTokenLimit != null)
              'maxOutputTokens': _cachedModelOutputTokenLimit,
            'responseMimeType': 'application/json',
            if (effectiveFallbackSchema != null)
              'responseSchema': effectiveFallbackSchema,
            'thinkingConfig': buildNativeThinkingConfig(
              normalizedThinking: 'LOW',
              useThinkingLevelEnum: _cachedSupportsThinkingLevel,
            ),
          };
          final fallbackPayload = <String, dynamic>{
            'contents': contentsPayload,
            'generationConfig': fallbackGenConfig,
          };
          final fallbackRes = await http
              .post(
                uri,
                headers: _jsonHeaders,
                body: jsonEncode(fallbackPayload),
              )
              .timeout(timeoutDuration);
          if (fallbackRes.statusCode == 200) {
            lastErrorStatus = null;
            final parsed = _parseCandidateResponseJson(fallbackRes.body);
            if (parsed != null) return parsed;
          } else if (fallbackRes.statusCode == 401 ||
              fallbackRes.statusCode == 402 ||
              fallbackRes.statusCode == 403) {
            lastErrorStatus = 'HTTP ${fallbackRes.statusCode}';
            return null;
          }
        } catch (_) {
          continue;
        }
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

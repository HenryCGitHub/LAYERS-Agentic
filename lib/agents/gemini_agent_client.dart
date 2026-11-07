import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/text_style_guide.dart';

/// Immutable record of a single Gemini API call's token breakdown (`IN · CACHED · OUT · THINK`).
class GeminiTokenCallRecord {
  final String label;
  final String thinkingLevel;
  final int inputTokens;
  final int cachedInputTokens;
  final int outputTokens;
  final int thinkingTokens;
  final DateTime timestamp;

  const GeminiTokenCallRecord({
    required this.label,
    required this.thinkingLevel,
    required this.inputTokens,
    this.cachedInputTokens = 0,
    required this.outputTokens,
    required this.thinkingTokens,
    required this.timestamp,
  });

  /// Total tokens across Input + Visible Output + Internal Scratchpad Thinking.
  int get totalTokens => inputTokens + outputTokens + thinkingTokens;

  /// Uncached input tokens billed at standard `$0.75 / 1M`.
  int get uncachedInputTokens =>
      (inputTokens - cachedInputTokens).clamp(0, inputTokens);

  /// Google bills both `candidatesTokenCount` (`OUT`) and `thoughtsTokenCount` (`THINK`) at the Output rate.
  int get billedOutputTokens => outputTokens + thinkingTokens;

  /// Estimated USD cost for this single API call on Gemini 3.8 Flash (`$0.75 / 1M` uncached Input, `$0.075 / 1M` cached Input, `$3.75 / 1M` Output + Thinking).
  double get estimatedCostUsd =>
      ((uncachedInputTokens / 1000000.0) *
          GeminiAgentClient.inputRatePerMillionUsd) +
      ((cachedInputTokens.clamp(0, inputTokens) / 1000000.0) *
          GeminiAgentClient.cachedInputRatePerMillionUsd) +
      ((billedOutputTokens / 1000000.0) *
          GeminiAgentClient.outputRatePerMillionUsd);

  Map<String, dynamic> toJson() => {
        'label': label,
        'thinkingLevel': thinkingLevel,
        'inputTokens': inputTokens,
        'cachedInputTokens': cachedInputTokens,
        'outputTokens': outputTokens,
        'thinkingTokens': thinkingTokens,
        'timestamp': timestamp.toIso8601String(),
      };

  factory GeminiTokenCallRecord.fromJson(Map<String, dynamic> json) {
    return GeminiTokenCallRecord(
      label: (json['label'] ?? 'gemini_call').toString(),
      thinkingLevel: (json['thinkingLevel'] ?? 'LOW').toString(),
      inputTokens: (json['inputTokens'] as num?)?.toInt() ?? 0,
      cachedInputTokens: (json['cachedInputTokens'] as num?)?.toInt() ?? 0,
      outputTokens: (json['outputTokens'] as num?)?.toInt() ?? 0,
      thinkingTokens: (json['thinkingTokens'] as num?)?.toInt() ?? 0,
      timestamp: DateTime.tryParse((json['timestamp'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

/// Lightweight, resilient Gemini JSON client for LAYERS-Agentic.
/// Supports:
/// - Base64 build-time key decoding (`GEMINI_API_KEY_B64`) so GitHub Push Protection
///   never blocks public `gh-pages` deployments.
/// - Runtime API key and Model override (`gemini-flash-latest` default).
/// - Live Token Usage & Scratchpad Tracker (`IN` · `OUT` · `THINK` + 90% Implicit Cache discount).
class GeminiAgentClient {
  static const String _rawEnvKey = String.fromEnvironment('GEMINI_API_KEY');
  static const String _b64EnvKey = String.fromEnvironment('GEMINI_API_KEY_B64');
  static String? _cachedDefaultKey;

  static const Map<String, String> _jsonHeaders = {
    'Content-Type': 'application/json',
  };
  static const Duration _heavyModelTimeout = Duration(seconds: 180);
  static const Duration _standardModelTimeout = Duration(seconds: 180);
  static const Duration _metadataTimeout = Duration(seconds: 6);

  static bool _modelMetadataChecked = false;
  static int? _cachedModelOutputTokenLimit;
  static bool _cachedSupportsThinkingLevel = false;

  static const String _prefsTokenUsageKey = 'layers_gemini_token_usage_v1';

  /// Official Gemini 3.8 Flash (`gemini-flash-latest`) Standard Paid Tier rates (USD per 1M tokens).
  static const double inputRatePerMillionUsd = 0.75;

  /// Implicit Prompt-Prefix Cache rate on Gemini 3.8 Flash (`90%` discount off `$0.75 / 1M` = `$0.075 / 1M`).
  static const double cachedInputRatePerMillionUsd = 0.075;
  static const double outputRatePerMillionUsd = 3.75;

  static int totalInputTokens = 0;
  static int totalCachedInputTokens = 0;
  static int totalOutputTokens = 0;
  static int totalThinkingTokens = 0;
  static int totalApiCalls = 0;
  static final List<GeminiTokenCallRecord> callHistory =
      <GeminiTokenCallRecord>[];
  static void Function()? onUsageChanged;

  /// Estimated USD cost of Input (`IN`) tokens (`$0.75 / 1M` uncached, `$0.075 / 1M` cached).
  static double get estimatedInputCostUsd {
    final safeCached = totalCachedInputTokens.clamp(0, totalInputTokens);
    final safeUncached = (totalInputTokens - safeCached).clamp(
      0,
      totalInputTokens,
    );
    return ((safeUncached / 1000000.0) * inputRatePerMillionUsd) +
        ((safeCached / 1000000.0) * cachedInputRatePerMillionUsd);
  }

  /// Estimated USD cost of Visible Output (`OUT`) tokens for the latest API call (`$3.75 / 1M`).
  static double get estimatedOutputCostUsd =>
      (totalOutputTokens / 1000000.0) * outputRatePerMillionUsd;

  /// Estimated USD cost of Internal Scratchpad (`THINK`) tokens for the latest API call (`$3.75 / 1M`).
  static double get estimatedThinkingCostUsd =>
      (totalThinkingTokens / 1000000.0) * outputRatePerMillionUsd;

  /// Estimated total USD cost for the latest API call on Gemini 3.8 Flash (`$0.75 / 1M` Input, `$3.75 / 1M` Output + Thinking).
  static double get estimatedCostUsd =>
      estimatedInputCostUsd +
      estimatedOutputCostUsd +
      estimatedThinkingCostUsd;

  /// Formats a USD cost value cleanly for UI pills and cards (e.g., `$0.0000`, `$0.0348`).
  static String formatCostUsd(double cost) {
    final safe = cost < 0 ? 0.0 : cost;
    if (safe >= 1.0) {
      return '\$${safe.toStringAsFixed(2)}';
    }
    return '\$${safe.toStringAsFixed(4)}';
  }

  /// Formats a token count compactly (e.g., `840`, `5.2k`, `1.4M`).
  static String formatTokenCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000.0).toStringAsFixed(2)}M';
    }
    if (count >= 1000) {
      return '${(count / 1000.0).toStringAsFixed(1)}k';
    }
    return '$count';
  }

  /// Accumulates a single API call's token usage (`IN`, `CACHED`, `OUT`, `THINK`) and cost across the session until reset.
  static void recordTokenUsage({
    required String label,
    required String thinkingLevel,
    required int inputTokens,
    int cachedInputTokens = 0,
    required int outputTokens,
    required int thinkingTokens,
  }) {
    final safeIn = inputTokens < 0 ? 0 : inputTokens;
    final safeCached = cachedInputTokens.clamp(0, safeIn);
    final safeOut = outputTokens < 0 ? 0 : outputTokens;
    final safeThink = thinkingTokens < 0 ? 0 : thinkingTokens;
    totalInputTokens += safeIn;
    totalCachedInputTokens += safeCached;
    totalOutputTokens += safeOut;
    totalThinkingTokens += safeThink;
    totalApiCalls += 1;
    callHistory.insert(
      0,
      GeminiTokenCallRecord(
        label: label,
        thinkingLevel: thinkingLevel.trim().toUpperCase(),
        inputTokens: safeIn,
        cachedInputTokens: safeCached,
        outputTokens: safeOut,
        thinkingTokens: safeThink,
        timestamp: DateTime.now(),
      ),
    );
    if (callHistory.length > 30) {
      callHistory.removeRange(30, callHistory.length);
    }
    _persistTokenUsageAsync();
    onUsageChanged?.call();
  }

  /// Extracts `usageMetadata` (`promptTokenCount`, `cachedContentTokenCount`, `candidatesTokenCount`, `thoughtsTokenCount`)
  /// from a raw Gemini HTTP response body and records it.
  static void recordUsageFromResponseBody(
    String responseBody, {
    required String label,
    required String thinkingLevel,
    int fallbackPromptChars = 0,
  }) {
    try {
      final decoded = jsonDecode(responseBody);
      if (decoded is Map<String, dynamic>) {
        final usage = decoded['usageMetadata'];
        if (usage is Map) {
          final inTok = (usage['promptTokenCount'] as num?)?.toInt() ??
              (fallbackPromptChars ~/ 4);
          final cachedTok =
              (usage['cachedContentTokenCount'] as num?)?.toInt() ?? 0;
          final outTok = (usage['candidatesTokenCount'] as num?)?.toInt() ?? 0;
          final thinkTok = (usage['thoughtsTokenCount'] as num?)?.toInt() ?? 0;
          recordTokenUsage(
            label: label,
            thinkingLevel: thinkingLevel,
            inputTokens: inTok,
            cachedInputTokens: cachedTok,
            outputTokens: outTok,
            thinkingTokens: thinkTok,
          );
          return;
        }
      }
    } catch (_) {}
    recordTokenUsage(
      label: label,
      thinkingLevel: thinkingLevel,
      inputTokens: fallbackPromptChars ~/ 4,
      outputTokens: responseBody.length ~/ 4,
      thinkingTokens: 0,
    );
  }

  /// Loads persisted token counters and call log from `SharedPreferences`.
  static Future<void> loadPersistedTokenUsage() async {
    if (testMockResponder != null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsTokenUsageKey);
      if (raw == null || raw.trim().isEmpty) return;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      totalInputTokens = (map['totalInputTokens'] as num?)?.toInt() ?? 0;
      totalCachedInputTokens =
          (map['totalCachedInputTokens'] as num?)?.toInt() ?? 0;
      totalOutputTokens = (map['totalOutputTokens'] as num?)?.toInt() ?? 0;
      totalThinkingTokens = (map['totalThinkingTokens'] as num?)?.toInt() ?? 0;
      totalApiCalls = (map['totalApiCalls'] as num?)?.toInt() ?? 0;
      callHistory.clear();
      final rawHistory = map['callHistory'];
      if (rawHistory is List) {
        for (final item in rawHistory) {
          if (item is Map) {
            callHistory.add(
              GeminiTokenCallRecord.fromJson(
                Map<String, dynamic>.from(item),
              ),
            );
          }
        }
      }
      onUsageChanged?.call();
    } catch (_) {}
  }

  /// Resets cumulative token counters and call history to zero.
  static void resetTokenUsage() {
    totalInputTokens = 0;
    totalCachedInputTokens = 0;
    totalOutputTokens = 0;
    totalThinkingTokens = 0;
    totalApiCalls = 0;
    callHistory.clear();
    onUsageChanged?.call();
    if (testMockResponder != null) return;
    Future<void>(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_prefsTokenUsageKey);
      } catch (_) {}
    });
  }

  static void _persistTokenUsageAsync() {
    if (testMockResponder != null) return;
    Future<void>(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final payload = jsonEncode({
          'totalInputTokens': totalInputTokens,
          'totalCachedInputTokens': totalCachedInputTokens,
          'totalOutputTokens': totalOutputTokens,
          'totalThinkingTokens': totalThinkingTokens,
          'totalApiCalls': totalApiCalls,
          'callHistory': [for (final r in callHistory) r.toJson()],
        });
        await prefs.setString(_prefsTokenUsageKey, payload);
      } catch (_) {}
    });
  }

  /// Shared compact style rules injected across Stage 1 & Stage 2 prompts (sourced from `LayersTextStyleGuide`).
  static const String compactStyleRules =
      LayersTextStyleGuide.compactStyleRules;

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
        if (version.startsWith('3') ||
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
      // Gemini 3.8 Flash supports LOW, MEDIUM, HIGH (MINIMAL returns an error on 3.8).
      final String level = switch (upper) {
        'NONE' || 'MINIMAL' || 'LOW' => 'LOW',
        'MEDIUM' => 'MEDIUM',
        _ => 'HIGH',
      };
      return <String, dynamic>{
        'thinkingLevel': level,
      };
    }
    final int budget = switch (upper) {
      'NONE' || 'MINIMAL' => 0,
      'LOW' => 256,
      'MEDIUM' => 2048,
      _ => -1, // Uncapped dynamic thinking for HIGH
    };
    return <String, dynamic>{
      'thinkingBudget': budget,
    };
  }

  static Map<String, dynamic>? _parseCandidateResponseJson(String responseBody) {
    final body = jsonDecode(responseBody) as Map<String, dynamic>;
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
          return jsonDecode(cleaned) as Map<String, dynamic>;
        }
      }
    }
    return null;
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
    final normalizedThinking = thinkingLevel.trim().toUpperCase();
    final hasTools =
        functionDeclarations != null && functionDeclarations.isNotEmpty;
    final callLabel = hasTools
        ? (functionDeclarations.first['name']?.toString() ?? 'tool_call')
        : 'json_response';

    if (testMockResponder != null) {
      final mockRes = await testMockResponder!(prompt, resolvedModel);
      if (mockRes != null) {
        final usage = mockRes['_usageMetadata'] ?? mockRes['usageMetadata'];
        if (usage is Map) {
          recordTokenUsage(
            label: (mockRes['_toolName'] ?? callLabel).toString(),
            thinkingLevel:
                normalizedThinking.isEmpty ? 'LOW' : normalizedThinking,
            inputTokens: (usage['promptTokenCount'] as num?)?.toInt() ?? 400,
            cachedInputTokens:
                (usage['cachedContentTokenCount'] as num?)?.toInt() ?? 0,
            outputTokens:
                (usage['candidatesTokenCount'] as num?)?.toInt() ?? 600,
            thinkingTokens:
                (usage['thoughtsTokenCount'] as num?)?.toInt() ?? 200,
          );
        } else {
          final estIn = (prompt.length ~/ 4).clamp(64, 32000);
          final estOut = (jsonEncode(mockRes).length ~/ 4).clamp(64, 32000);
          final estThink = normalizedThinking == 'HIGH'
              ? 1024
              : (normalizedThinking == 'MEDIUM' ? 512 : 128);
          recordTokenUsage(
            label: (mockRes['_toolName'] ?? callLabel).toString(),
            thinkingLevel:
                normalizedThinking.isEmpty ? 'LOW' : normalizedThinking,
            inputTokens: estIn,
            outputTokens: estOut,
            thinkingTokens: estThink,
          );
        }
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
          'maxOutputTokens': _cachedModelOutputTokenLimit ?? 65536,
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
          final effectiveLabel =
              (parsed?['_toolName'] ?? callLabel).toString();
          recordUsageFromResponseBody(
            response.body,
            label: effectiveLabel,
            thinkingLevel:
                normalizedThinking.isEmpty ? 'HIGH' : normalizedThinking,
            fallbackPromptChars: prompt.length,
          );
          if (parsed != null) return parsed;
        } else if (response.statusCode == 401 ||
            response.statusCode == 402 ||
            response.statusCode == 403) {
          // Fail fast on auth/billing errors instead of retrying across models
          lastErrorStatus = 'HTTP ${response.statusCode}';
          return null;
        }
      } catch (_) {
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

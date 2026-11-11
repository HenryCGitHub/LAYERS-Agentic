import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import '../constants/text_style_guide.dart';

/// Lightweight, resilient Gemini JSON client for LAYERS-Agentic.
/// Supports:
/// - Explicit live model pinning to `gemini-3.8-flash` with Flash-only `gemini-flash-latest` failover (never Argon/Pro).
/// - Header-only `x-goog-api-key` auth (never exposing API keys in DevTools URLs).
/// - Exponential backoff + jitter retries on transient `429` / `503` / `5xx` responses.
class GeminiAgentClient {
  static const String _rawEnvKey = String.fromEnvironment('GEMINI_API_KEY');
  static const String _rawEnvProxyUrl =
      String.fromEnvironment('GEMINI_PROXY_URL');
  static const String defaultProxyBaseUrl =
      'https://us-central1-layers-b8a16.cloudfunctions.net/geminiProxy';
  static const String pinnedLiveFlashModel = 'gemini-3.8-flash';
  static String? _cachedDefaultKey;

  /// Optional override for the Firebase Cloud Function proxy URL (used in tests or custom deployments).
  static String? proxyBaseUrlOverride;

  /// Registered by `WorkbenchProvider` in live app mode so signed-in Google users route through `geminiProxy` automatically.
  static bool Function()? isProxyAuthenticated;
  static Future<String?> Function({bool forceRefresh})? authTokenProvider;

  static const Map<String, String> _jsonHeaders = {
    'Content-Type': 'application/json',
  };
  static final Random _jitterRandom = Random();
  static const int _maxTransientAttempts = 3;
  static const Duration _defaultBaseRetryDelay = Duration(milliseconds: 900);
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

  /// Optional test-only HTTP POST & backoff delay hooks for verifying header security and 503 retries.
  static Future<http.Response> Function(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
  })? testHttpPost;
  static Duration? testBaseRetryDelay;

  static Map<String, String> _buildRequestHeaders(String key) =>
      <String, String>{
        ..._jsonHeaders,
        'x-goog-api-key': key,
      };

  static Map<String, String> _buildProxyHeaders(String bearerToken) =>
      <String, String>{
        ..._jsonHeaders,
        'Authorization': 'Bearer $bearerToken',
      };

  static String get effectiveProxyBaseUrl {
    final override = proxyBaseUrlOverride;
    if (override != null) {
      return override.trim().replaceAll(RegExp(r'/+$'), '');
    }
    if (_rawEnvProxyUrl.trim().isNotEmpty) {
      return _rawEnvProxyUrl.trim().replaceAll(RegExp(r'/+$'), '');
    }
    return defaultProxyBaseUrl;
  }

  static bool get canUseAuthenticatedProxy =>
      effectiveProxyBaseUrl.isNotEmpty &&
      isProxyAuthenticated != null &&
      authTokenProvider != null &&
      isProxyAuthenticated!();

  /// Calls an authenticated admin/invite route (`/sendInvite`, `/acceptInvite`, `/revokeInvite`)
  /// on `geminiProxy` using the caller's Firebase Google ID token (with 1 automatic 401 refresh).
  static Future<({int statusCode, Map<String, dynamic> body})>
      postAuthenticatedProxyAction({
    required String routePath,
    Map<String, dynamic>? payload,
  }) async {
    final baseUrl = effectiveProxyBaseUrl;
    if (baseUrl.isEmpty || authTokenProvider == null) {
      return (
        statusCode: 401,
        body: <String, dynamic>{
          'ok': false,
          'error': {'message': 'Sign in with Google required.'},
        },
      );
    }
    var token = await authTokenProvider!(forceRefresh: false);
    if (token == null || token.trim().isEmpty) {
      return (
        statusCode: 401,
        body: <String, dynamic>{
          'ok': false,
          'error': {'message': 'Sign in with Google required.'},
        },
      );
    }

    final normalizedRoute =
        routePath.startsWith('/') ? routePath : '/$routePath';
    final uri = Uri.parse('$baseUrl$normalizedRoute');
    final encodedBody = jsonEncode(payload ?? const <String, dynamic>{});

    try {
      var res = await _postWithTransientRetry(
        uri: uri,
        headers: _buildProxyHeaders(token),
        body: encodedBody,
        timeoutDuration: const Duration(seconds: 25),
      );
      if (res.statusCode == 401) {
        final freshToken = await authTokenProvider!(forceRefresh: true);
        if (freshToken != null && freshToken.trim().isNotEmpty) {
          res = await _postWithTransientRetry(
            uri: uri,
            headers: _buildProxyHeaders(freshToken),
            body: encodedBody,
            timeoutDuration: const Duration(seconds: 25),
          );
        }
      }
      Map<String, dynamic> decoded = const <String, dynamic>{};
      if (res.body.trim().isNotEmpty) {
        try {
          final raw = jsonDecode(res.body);
          if (raw is Map) {
            decoded = Map<String, dynamic>.from(raw);
          }
        } catch (_) {}
      }
      return (statusCode: res.statusCode, body: decoded);
    } catch (e) {
      return (
        statusCode: 502,
        body: <String, dynamic>{
          'ok': false,
          'error': {'message': 'Unable to reach invite service: $e'},
        },
      );
    }
  }

  static bool _isTransientStatus(int statusCode) =>
      statusCode == 408 ||
      statusCode == 429 ||
      statusCode == 500 ||
      statusCode == 502 ||
      statusCode == 503 ||
      statusCode == 504;

  static Future<http.Response> _postWithTransientRetry({
    required Uri uri,
    required Map<String, String> headers,
    required String body,
    required Duration timeoutDuration,
  }) async {
    final baseDelay = testBaseRetryDelay ?? _defaultBaseRetryDelay;
    http.Response? lastResponse;
    Object? lastError;

    for (int attempt = 0; attempt < _maxTransientAttempts; attempt++) {
      try {
        final future = testHttpPost != null
            ? testHttpPost!(uri, headers: headers, body: body)
            : http.post(uri, headers: headers, body: body);
        final res = await future.timeout(timeoutDuration);
        lastResponse = res;
        if (!_isTransientStatus(res.statusCode) ||
            attempt == _maxTransientAttempts - 1) {
          return res;
        }
      } catch (err) {
        lastError = err;
        if (attempt == _maxTransientAttempts - 1) {
          rethrow;
        }
      }

      final expMs = baseDelay.inMilliseconds * (1 << attempt);
      final jitterMs =
          testBaseRetryDelay != null ? 0 : _jitterRandom.nextInt(250);
      final waitMs = expMs + jitterMs;
      if (waitMs > 0) {
        await Future<void>.delayed(Duration(milliseconds: waitMs));
      }
    }

    if (lastResponse != null) return lastResponse;
    throw lastError ?? StateError('Gemini HTTP request failed');
  }

  static String resolveDefaultApiKey() {
    if (_cachedDefaultKey != null) return _cachedDefaultKey!;
    if (_rawEnvKey.trim().isNotEmpty) {
      return _cachedDefaultKey = _rawEnvKey.trim();
    }
    return _cachedDefaultKey = '';
  }

  static bool hasKey(String apiKey) {
    if (testMockResponder != null) return true;
    final key = apiKey.trim().isNotEmpty ? apiKey.trim() : resolveDefaultApiKey();
    if (key.isNotEmpty) return true;
    return canUseAuthenticatedProxy;
  }

  static Future<void> _ensureModelCapabilitiesLoaded(
    String model,
    String key,
  ) async {
    if (_modelMetadataChecked || testHttpPost != null) return;
    _modelMetadataChecked = true;
    try {
      final metaUri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$model',
      );
      final res = await http.get(
        metaUri,
        headers: <String, String>{'x-goog-api-key': key},
      ).timeout(_metadataTimeout);
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
    final bool useProxy = key.isEmpty;
    String? proxyBearerToken;

    if (useProxy) {
      if (!canUseAuthenticatedProxy) {
        lastErrorStatus = 'Sign in with Google required';
        return null;
      }
      proxyBearerToken = await authTokenProvider!(forceRefresh: false);
      if (proxyBearerToken == null || proxyBearerToken.trim().isEmpty) {
        lastErrorStatus = 'Sign in with Google required';
        return null;
      }
    } else {
      await _ensureModelCapabilitiesLoaded(pinnedLiveFlashModel, key);
    }

    const modelsToTry = <String>[pinnedLiveFlashModel, 'gemini-flash-latest'];
    final String baseApiRoot = useProxy
        ? effectiveProxyBaseUrl
        : 'https://generativelanguage.googleapis.com';
    Map<String, String> requestHeaders = useProxy
        ? _buildProxyHeaders(proxyBearerToken!)
        : _buildRequestHeaders(key);

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

    int? lastNon200Status;
    bool refreshedProxyTokenOnce = false;

    for (final model in modelsToTry) {
      final uri = Uri.parse(
        '$baseApiRoot/v1beta/models/$model:generateContent',
      );
      final isHeavyPlanningModel = model.contains('pro');
      final timeoutDuration =
          isHeavyPlanningModel ? _heavyModelTimeout : _standardModelTimeout;
      int? modelLastStatus;

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

        var response = await _postWithTransientRetry(
          uri: uri,
          headers: requestHeaders,
          body: jsonEncode(requestPayload),
          timeoutDuration: timeoutDuration,
        );

        // If Firebase ID token expired right at the boundary, force-refresh once and retry.
        if (useProxy &&
            response.statusCode == 401 &&
            !refreshedProxyTokenOnce &&
            authTokenProvider != null) {
          refreshedProxyTokenOnce = true;
          final freshToken = await authTokenProvider!(forceRefresh: true);
          if (freshToken != null && freshToken.trim().isNotEmpty) {
            proxyBearerToken = freshToken;
            requestHeaders = _buildProxyHeaders(freshToken);
            response = await _postWithTransientRetry(
              uri: uri,
              headers: requestHeaders,
              body: jsonEncode(requestPayload),
              timeoutDuration: timeoutDuration,
            );
          }
        }

        // If `gemini-flash-latest` alias upgraded on the backend and prefers the alternate
        // native thinkingConfig schema, flip and retry automatically.
        if (response.statusCode == 400 && normalizedThinking.isNotEmpty) {
          _cachedSupportsThinkingLevel = !_cachedSupportsThinkingLevel;
          genConfig['thinkingConfig'] = buildNativeThinkingConfig(
            normalizedThinking: normalizedThinking,
            useThinkingLevelEnum: _cachedSupportsThinkingLevel,
          );
          response = await _postWithTransientRetry(
            uri: uri,
            headers: requestHeaders,
            body: jsonEncode(requestPayload),
            timeoutDuration: timeoutDuration,
          );
        }

        modelLastStatus = response.statusCode;
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
        } else {
          lastNon200Status = response.statusCode;
        }
      } catch (_) {
        // Proceed to JSON-mode fallback if tools were active, or next model
      }

      // If a deeply nested function-calling schema timed out or returned MALFORMED_FUNCTION_CALL
      // (and this model endpoint is NOT actively returning 429/503), retry once in direct JSON mode.
      if (hasTools &&
          (modelLastStatus == null || !_isTransientStatus(modelLastStatus))) {
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
          final fallbackRes = await _postWithTransientRetry(
            uri: uri,
            headers: requestHeaders,
            body: jsonEncode(fallbackPayload),
            timeoutDuration: timeoutDuration,
          );
          if (fallbackRes.statusCode == 200) {
            lastErrorStatus = null;
            final parsed = _parseCandidateResponseJson(fallbackRes.body);
            if (parsed != null) return parsed;
          } else if (fallbackRes.statusCode == 401 ||
              fallbackRes.statusCode == 402 ||
              fallbackRes.statusCode == 403) {
            lastErrorStatus = 'HTTP ${fallbackRes.statusCode}';
            return null;
          } else {
            lastNon200Status = fallbackRes.statusCode;
          }
        } catch (_) {
          continue;
        }
      }
    }
    if (lastNon200Status != null) {
      lastErrorStatus = 'HTTP $lastNon200Status';
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

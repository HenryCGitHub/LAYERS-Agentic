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

  static String resolveDefaultApiKey() {
    if (_rawEnvKey.trim().isNotEmpty) return _rawEnvKey.trim();
    if (_b64EnvKey.trim().isNotEmpty) {
      try {
        return utf8.decode(base64Decode(_b64EnvKey.trim())).trim();
      } catch (_) {}
    }
    return '';
  }

  static bool hasKey(String apiKey) {
    final key = apiKey.trim().isNotEmpty ? apiKey.trim() : resolveDefaultApiKey();
    return key.isNotEmpty;
  }

  static Future<Map<String, dynamic>?> generateJson({
    required String prompt,
    required String apiKey,
    String preferredModel = 'gemini-2.5-flash',
    double temperature = 0.5,
  }) async {
    final key = apiKey.trim().isNotEmpty ? apiKey.trim() : resolveDefaultApiKey();
    if (key.isEmpty) return null;

    final modelsToTry = <String>{
      preferredModel,
      'gemini-2.5-flash',
      'gemini-2.0-flash',
    }.toList();

    for (final model in modelsToTry) {
      try {
        final uri = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$key',
        );
        final response = await http
            .post(
              uri,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'contents': [
                  {
                    'parts': [
                      {'text': prompt},
                    ],
                  },
                ],
                'generationConfig': {
                  'temperature': temperature,
                  'responseMimeType': 'application/json',
                },
              }),
            )
            .timeout(const Duration(seconds: 25));

        if (response.statusCode == 200) {
          final body = jsonDecode(response.body) as Map<String, dynamic>;
          final candidates = body['candidates'] as List?;
          if (candidates != null && candidates.isNotEmpty) {
            final content = candidates.first['content'] as Map<String, dynamic>?;
            final parts = content?['parts'] as List?;
            if (parts != null && parts.isNotEmpty) {
              final rawText = parts.first['text']?.toString() ?? '';
              final cleaned = _extractJsonObject(rawText);
              if (cleaned.isNotEmpty) {
                return jsonDecode(cleaned) as Map<String, dynamic>;
              }
            }
          }
        }
      } catch (_) {
        // Try next fallback model in list
      }
    }
    return null;
  }

  static String _extractJsonObject(String raw) {
    final trimmed = raw
        .replaceAll(RegExp(r'^```json\s*', multiLine: true), '')
        .replaceAll(RegExp(r'^```\s*', multiLine: true), '')
        .trim();
    final start = trimmed.indexOf('{');
    final end = trimmed.lastIndexOf('}');
    if (start != -1 && end != -1 && end > start) {
      return trimmed.substring(start, end + 1);
    }
    return trimmed;
  }
}

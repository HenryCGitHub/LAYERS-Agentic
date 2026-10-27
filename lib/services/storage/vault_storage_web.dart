import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/tier_document.dart';
import '../local_vault_service.dart';
import 'vault_storage_interface.dart';

class VaultStorageWebImpl implements VaultStorageBackend {
  static const String _keySettings = 'tier_pm_settings';
  static const String _keyDocPrefix = 'tier_pm_doc_';
  static const String _keyDocIds = 'tier_pm_doc_ids';

  @override
  Future<VaultLoadResult> loadVaultData() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      String? activeDocumentId;
      String? apiKey;
      String? modelName;
      String? planningModel;
      String? thinkingLevel;
      String? themeMode;

      final settingsRaw = prefs.getString(_keySettings);
      if (settingsRaw != null) {
        final Map<String, dynamic> settings = jsonDecode(settingsRaw);
        activeDocumentId = settings['activeDocumentId'] as String?;
        apiKey = settings['apiKey'] as String?;
        modelName = settings['modelName'] as String?;
        planningModel = settings['planningModel'] as String?;
        thinkingLevel = settings['thinkingLevel'] as String?;
        themeMode = settings['themeMode'] as String?;
      }

      final docIds = prefs.getStringList(_keyDocIds) ?? [];
      final docsMap = <String, TierDocument>{};

      for (final id in docIds) {
        final raw = prefs.getString('$_keyDocPrefix$id');
        if (raw != null) {
          try {
            final json = jsonDecode(raw) as Map<String, dynamic>;
            final doc = TierDocument.fromJson(json);
            docsMap[doc.id] = doc;
          } catch (_) {}
        }
      }

      return VaultLoadResult(
        documents: docsMap,
        activeDocumentId: activeDocumentId,
        apiKey: apiKey,
        modelName: modelName,
        planningModel: planningModel,
        thinkingLevel: thinkingLevel,
        themeMode: themeMode,
      );
    } catch (_) {
      return VaultLoadResult(documents: {});
    }
  }

  @override
  Future<void> saveSettings({
    required String activeDocumentId,
    String? apiKey,
    String? modelName,
    String? planningModel,
    String? thinkingLevel,
    String? themeMode,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? currentThemeMode;
      final existingRaw = prefs.getString(_keySettings);
      if (existingRaw != null) {
        try {
          final Map<String, dynamic> settings = jsonDecode(existingRaw);
          currentThemeMode = settings['themeMode'] as String?;
        } catch (_) {}
      }

      await prefs.setString(
          _keySettings,
          jsonEncode({
            'version': '2.0.0',
            'activeDocumentId': activeDocumentId,
            'apiKey': apiKey ?? '',
            'modelName': modelName ?? 'gemini-flash-latest',
            'planningModel': planningModel ?? 'gemini-4-argon',
            'thinkingLevel': thinkingLevel ?? 'LOW',
            'themeMode': themeMode ?? currentThemeMode ?? 'dark',
          }));
    } catch (_) {}
  }

  @override
  Future<void> saveDocument(TierDocument doc) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          '$_keyDocPrefix${doc.id}', jsonEncode(doc.toJson()));

      final docIds = (prefs.getStringList(_keyDocIds) ?? []).toSet();
      docIds.add(doc.id);
      await prefs.setStringList(_keyDocIds, docIds.toList());
    } catch (_) {}
  }

  @override
  Future<void> deleteDocument(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_keyDocPrefix$id');

      final docIds = (prefs.getStringList(_keyDocIds) ?? []).toSet();
      docIds.remove(id);
      await prefs.setStringList(_keyDocIds, docIds.toList());
    } catch (_) {}
  }
}

VaultStorageBackend createVaultStorageBackend() => VaultStorageWebImpl();

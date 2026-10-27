import 'dart:async';
import '../models/tier_document.dart';
import 'storage/vault_storage.dart';

class VaultLoadResult {
  final Map<String, TierDocument> documents;
  final String? activeDocumentId;
  final String? apiKey;
  final String? modelName;
  final String? planningModel;
  final String? thinkingLevel;
  final String? themeMode;

  VaultLoadResult({
    required this.documents,
    this.activeDocumentId,
    this.apiKey,
    this.modelName,
    this.planningModel,
    this.thinkingLevel,
    this.themeMode,
  });
}

/// Cross-platform storage engine (Desktop files + Web LocalStorage / SharedPreferences).
class LocalVaultService {
  static Future<VaultLoadResult> loadVaultData() async {
    return vaultStorage.loadVaultData();
  }

  static Future<void> saveSettings({
    required String activeDocumentId,
    String? apiKey,
    String? modelName,
    String? planningModel,
    String? thinkingLevel,
    String? themeMode,
  }) async {
    return vaultStorage.saveSettings(
      activeDocumentId: activeDocumentId,
      apiKey: apiKey,
      modelName: modelName,
      planningModel: planningModel,
      thinkingLevel: thinkingLevel,
      themeMode: themeMode,
    );
  }

  static Future<void> saveDocument(TierDocument doc) async {
    return vaultStorage.saveDocument(doc);
  }

  static Future<void> deleteDocument(String id) async {
    return vaultStorage.deleteDocument(id);
  }
}

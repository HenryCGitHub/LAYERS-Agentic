import 'dart:async';
import '../models/tier_document.dart';
import 'storage/vault_storage.dart';

class VaultLoadResult {
  final Map<String, TierDocument> documents;
  final String? activeDocumentId;
  final String? apiKey;
  final String? llmProvider;
  final String? modelName;
  final String? thinkingLevel;
  final int aiDetailLevel;
  final List<String>? expandedTreeNodes;
  final String? themeMode;

  VaultLoadResult({
    required this.documents,
    this.activeDocumentId,
    this.apiKey,
    this.llmProvider,
    this.modelName,
    this.thinkingLevel,
    this.aiDetailLevel = 3,
    this.expandedTreeNodes,
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
    String? llmProvider,
    String? modelName,
    String? thinkingLevel,
    int aiDetailLevel = 3,
    List<String>? expandedTreeNodes,
    String? themeMode,
  }) async {
    return vaultStorage.saveSettings(
      activeDocumentId: activeDocumentId,
      apiKey: apiKey,
      llmProvider: llmProvider,
      modelName: modelName,
      thinkingLevel: thinkingLevel,
      aiDetailLevel: aiDetailLevel,
      expandedTreeNodes: expandedTreeNodes,
      themeMode: themeMode,
    );
  }

  static Future<void> saveDocument(TierDocument doc) async {
    return vaultStorage.saveDocument(doc);
  }

  static Future<void> deleteDocument(String id) async {
    return vaultStorage.deleteDocument(id);
  }

  static Future<void> saveVault({
    required Map<String, TierDocument> documents,
    required String activeDocumentId,
    String? apiKey,
    String? llmProvider,
    String? modelName,
    String? thinkingLevel,
    List<String>? expandedTreeNodes,
  }) async {
    await saveSettings(
      activeDocumentId: activeDocumentId,
      apiKey: apiKey,
      llmProvider: llmProvider,
      modelName: modelName,
      thinkingLevel: thinkingLevel,
      expandedTreeNodes: expandedTreeNodes,
    );
    for (final doc in documents.values) {
      await saveDocument(doc);
    }
  }

  static Future<void> startDiskWatcher(
      void Function(TierDocument updatedDoc) onDocChangedOnDisk) async {
    return vaultStorage.startDiskWatcher(onDocChangedOnDisk);
  }
}

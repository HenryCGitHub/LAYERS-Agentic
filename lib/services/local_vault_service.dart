import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/tier_document.dart';
import 'storage/vault_storage.dart';
import 'storage/vault_storage_interface.dart';

class VaultLoadResult {
  final Map<String, TierDocument> documents;
  final String? activeDocumentId;
  final String? apiKey;
  final String? modelName;
  final String? planningModel;
  final String? thinkingLevel;
  final String? themeMode;

  const VaultLoadResult({
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
  LocalVaultService._();

  @visibleForTesting
  static VaultStorageBackend? testBackendOverride;

  static VaultStorageBackend get _backend => testBackendOverride ?? vaultStorage;

  /// Loads all locally cached documents and settings.
  static Future<VaultLoadResult> loadVaultData() async {
    return _backend.loadVaultData();
  }

  /// Saves user settings and AI configurations to local storage.
  static Future<void> saveSettings({
    required String activeDocumentId,
    String? apiKey,
    String? modelName,
    String? planningModel,
    String? thinkingLevel,
    String? themeMode,
  }) async {
    return _backend.saveSettings(
      activeDocumentId: activeDocumentId,
      apiKey: apiKey,
      modelName: modelName,
      planningModel: planningModel,
      thinkingLevel: thinkingLevel,
      themeMode: themeMode,
    );
  }

  /// Persists a single tier document to local storage.
  static Future<void> saveDocument(TierDocument doc) async {
    return _backend.saveDocument(doc);
  }

  /// Deletes a document by id from local storage.
  static Future<void> deleteDocument(String id) async {
    return _backend.deleteDocument(id);
  }
}

import '../local_vault_service.dart';
import '../../models/tier_document.dart';

/// Contract for cross-platform local document and configuration persistence.
abstract class VaultStorageBackend {
  /// Loads all locally cached documents and settings.
  Future<VaultLoadResult> loadVaultData();

  /// Persists user settings and AI configurations.
  Future<void> saveSettings({
    required String activeDocumentId,
    String? apiKey,
    String? modelName,
    String? planningModel,
    String? thinkingLevel,
    String? themeMode,
  });

  /// Saves a single tier document.
  Future<void> saveDocument(TierDocument doc);

  /// Deletes a document by id.
  Future<void> deleteDocument(String id);
}

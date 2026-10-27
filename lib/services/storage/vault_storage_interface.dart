import '../local_vault_service.dart';
import '../../models/tier_document.dart';

abstract class VaultStorageBackend {
  Future<VaultLoadResult> loadVaultData();
  Future<void> saveSettings({
    required String activeDocumentId,
    String? apiKey,
    String? modelName,
    String? planningModel,
    String? thinkingLevel,
    String? themeMode,
  });
  Future<void> saveDocument(TierDocument doc);
  Future<void> deleteDocument(String id);
}

import '../local_vault_service.dart';
import '../../models/tier_document.dart';

abstract class VaultStorageBackend {
  Future<VaultLoadResult> loadVaultData();
  Future<void> saveSettings({
    required String activeDocumentId,
    String? apiKey,
    String? llmProvider,
    String? modelName,
    String? thinkingLevel,
    int aiDetailLevel = 3,
    List<String>? expandedTreeNodes,
    String? themeMode,
  });
  Future<void> saveDocument(TierDocument doc);
  Future<void> deleteDocument(String id);
  Future<void> startDiskWatcher(
      void Function(TierDocument updatedDoc) onDocChangedOnDisk);
}

import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:path_provider/path_provider.dart';
import '../../models/tier_document.dart';
import '../local_vault_service.dart';
import 'vault_storage_interface.dart';

class VaultStorageImpl implements VaultStorageBackend {
  static Future<Directory> _getTierPmDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/TierPM');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<Directory> _getDocumentsDir() async {
    final pm = await _getTierPmDir();
    final dir = Directory('${pm.path}/documents');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<File> _getSettingsFile() async {
    final pm = await _getTierPmDir();
    return File('${pm.path}/settings.json');
  }

  static Future<File> _docFile(String id) async {
    final dir = await _getDocumentsDir();
    return File('${dir.path}/$id.json');
  }

  @override
  Future<VaultLoadResult> loadVaultData() async {
    try {
      String? activeDocumentId;
      String? apiKey;
      String? modelName;
      String? thinkingLevel;
      String? themeMode;

      final settingsFile = await _getSettingsFile();
      if (await settingsFile.exists()) {
        final raw = await settingsFile.readAsString();
        final Map<String, dynamic> settings = jsonDecode(raw);
        activeDocumentId = settings['activeDocumentId'] as String?;
        apiKey = settings['apiKey'] as String?;
        modelName = settings['modelName'] as String?;
        thinkingLevel = settings['thinkingLevel'] as String?;
        themeMode = settings['themeMode'] as String?;
      }

      final docsDir = await _getDocumentsDir();
      final docsMap = <String, TierDocument>{};

      if (await docsDir.exists()) {
        final files = docsDir.listSync();
        for (final entity in files) {
          if (entity is File && entity.path.endsWith('.json')) {
            try {
              final raw = await entity.readAsString();
              final json = jsonDecode(raw) as Map<String, dynamic>;
              final doc = TierDocument.fromJson(json);
              docsMap[doc.id] = doc;
            } catch (_) {}
          }
        }
      }

      return VaultLoadResult(
        documents: docsMap,
        activeDocumentId: activeDocumentId,
        apiKey: apiKey,
        modelName: modelName,
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
    String? thinkingLevel,
    String? themeMode,
  }) async {
    try {
      final file = await _getSettingsFile();
      String? currentThemeMode;
      if (await file.exists()) {
        try {
          final raw = await file.readAsString();
          final Map<String, dynamic> settings = jsonDecode(raw);
          currentThemeMode = settings['themeMode'] as String?;
        } catch (_) {}
      }

      await file.writeAsString(jsonEncode({
        'version': '2.0.0',
        'activeDocumentId': activeDocumentId,
        'apiKey': apiKey ?? '',
        'modelName': modelName ?? 'gemini-flash-latest',
        'thinkingLevel': thinkingLevel ?? 'LOW',
        'themeMode': themeMode ?? currentThemeMode ?? 'dark',
      }));
    } catch (_) {}
  }

  @override
  Future<void> saveDocument(TierDocument doc) async {
    try {
      final file = await _docFile(doc.id);
      await file.writeAsString(jsonEncode(doc.toJson()));
    } catch (_) {}
  }

  @override
  Future<void> deleteDocument(String id) async {
    try {
      final file = await _docFile(id);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}

VaultStorageBackend createVaultStorageBackend() => VaultStorageImpl();

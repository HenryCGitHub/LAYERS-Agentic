import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:path_provider/path_provider.dart';
import '../../models/tier_document.dart';
import '../../data/initial_vault.dart';
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
      String? llmProvider;
      String? modelName;
      String? thinkingLevel;
      int aiDetailLevel = 3;
      List<String>? expandedTreeNodes;
      String? themeMode;

      final settingsFile = await _getSettingsFile();
      if (await settingsFile.exists()) {
        final raw = await settingsFile.readAsString();
        final Map<String, dynamic> settings = jsonDecode(raw);
        activeDocumentId = settings['activeDocumentId'] as String?;
        apiKey = settings['apiKey'] as String?;
        llmProvider = settings['llmProvider'] as String?;
        modelName = settings["modelName"] as String?;
        thinkingLevel = settings["thinkingLevel"] as String?;
        themeMode = settings['themeMode'] as String?;
        if (settings['aiDetailLevel'] is int) {
          aiDetailLevel = (settings['aiDetailLevel'] as int).clamp(1, 5);
        }
        if (settings['expandedTreeNodes'] is List) {
          expandedTreeNodes = (settings['expandedTreeNodes'] as List)
              .map((e) => e.toString())
              .toList();
        }
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

      if (docsMap.isEmpty) {
        for (final doc in initialVaultDocuments.values) {
          await saveDocument(doc);
        }
        return loadVaultData();
      }

      return VaultLoadResult(
        documents: docsMap,
        activeDocumentId: activeDocumentId,
        apiKey: apiKey,
        llmProvider: llmProvider,
        modelName: modelName,
        thinkingLevel: thinkingLevel,
        aiDetailLevel: aiDetailLevel,
        expandedTreeNodes: expandedTreeNodes,
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
    String? llmProvider,
    String? modelName,
    String? thinkingLevel,
    int aiDetailLevel = 3,
    List<String>? expandedTreeNodes,
    String? themeMode,
  }) async {
    try {
      final file = await _getSettingsFile();
      List<String> currentExpanded = [];
      String? currentThemeMode;
      if (await file.exists()) {
        try {
          final raw = await file.readAsString();
          final Map<String, dynamic> settings = jsonDecode(raw);
          if (settings['expandedTreeNodes'] is List) {
            currentExpanded = (settings['expandedTreeNodes'] as List)
                .map((e) => e.toString())
                .toList();
          }
          currentThemeMode = settings['themeMode'] as String?;
        } catch (_) {}
      }

      await file.writeAsString(jsonEncode({
        'version': '2.0.0',
        'activeDocumentId': activeDocumentId,
        'apiKey': apiKey ?? '',
        'llmProvider': llmProvider ?? 'gemini',
        'modelName': modelName ?? 'gemini-3.8-flash',
        'thinkingLevel': thinkingLevel ?? 'low',
        'aiDetailLevel': aiDetailLevel,
        'expandedTreeNodes': expandedTreeNodes ?? currentExpanded,
        'themeMode': themeMode ?? currentThemeMode ?? 'dark',
      }));
    } catch (_) {}
  }

  static final Map<String, String> _lastWrittenContent = {};

  @override
  Future<void> saveDocument(TierDocument doc) async {
    try {
      final file = await _docFile(doc.id);
      final jsonStr = jsonEncode(doc.toJson());
      _lastWrittenContent[doc.id] = jsonStr;
      await file.writeAsString(jsonStr);
    } catch (_) {}
  }

  @override
  Future<void> deleteDocument(String id) async {
    try {
      final file = await _docFile(id);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  static StreamSubscription<FileSystemEvent>? _diskSubscription;

  @override
  Future<void> startDiskWatcher(
      void Function(TierDocument updatedDoc) onDocChangedOnDisk) async {
    try {
      await _diskSubscription?.cancel();
      final docsDir = await _getDocumentsDir();
      if (!await docsDir.exists()) return;

      _diskSubscription = docsDir.watch().listen((event) async {
        if (event.type == FileSystemEvent.modify ||
            event.type == FileSystemEvent.create) {
          final path = event.path;
          if (path.endsWith('.json')) {
            try {
              final file = File(path);
              if (await file.exists()) {
                final raw = await file.readAsString();
                final json = jsonDecode(raw) as Map<String, dynamic>;
                final doc = TierDocument.fromJson(json);
                if (_lastWrittenContent[doc.id] == raw) return;
                onDocChangedOnDisk(doc);
              }
            } catch (_) {}
          }
        }
      });
    } catch (_) {}
  }
}

VaultStorageBackend createVaultStorageBackend() => VaultStorageImpl();

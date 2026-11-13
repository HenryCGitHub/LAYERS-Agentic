/// Cross-platform safe Godot project folder sync gateway.
///
/// Resolves to [GodotFolderSyncWebImpl] on web (File System Access API) and
/// [GodotFolderSyncIoImpl] on desktop/IO targets.
library;

export 'godot_folder_sync_interface.dart';

import 'godot_folder_sync_interface.dart';
import 'godot_folder_sync_stub.dart'
    if (dart.library.io) 'godot_folder_sync_io.dart'
    if (dart.library.js_interop) 'godot_folder_sync_web.dart';

final GodotFolderSyncBackend godotFolderSync = createGodotFolderSyncBackend();

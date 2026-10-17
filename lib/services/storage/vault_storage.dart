import 'vault_storage_interface.dart';
import 'vault_storage_io.dart'
    if (dart.library.html) 'vault_storage_web.dart'
    if (dart.library.js_interop) 'vault_storage_web.dart';

final VaultStorageBackend vaultStorage = createVaultStorageBackend();

/// Where account passwords live. The Flutter shell implements this with the platform keystore (hence async); the core
/// never stores a password itself and `Backup` never contains one.
abstract interface class SecretStore {
  Future<String?> password(int accountId);
  Future<void> setPassword(int accountId, String password);
  Future<void> deletePassword(int accountId);
}

/// For tests.
class MemorySecretStore implements SecretStore {
  final _store = <int, String>{};

  @override
  Future<String?> password(int accountId) async => _store[accountId];

  @override
  Future<void> setPassword(int accountId, String password) async => _store[accountId] = password;

  @override
  Future<void> deletePassword(int accountId) async => _store.remove(accountId);
}

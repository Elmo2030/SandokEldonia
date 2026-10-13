import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iptvmac/core/secret_store.dart';

/// Provider passwords in the Android Keystore (encrypted shared preferences) through flutter_secure_storage.
class SecureSecretStore implements SecretStore {
  SecureSecretStore([FlutterSecureStorage? storage]) : _s = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _s;

  String _key(int id) => 'password.$id';

  @override
  Future<String?> password(int accountId) => _s.read(key: _key(accountId));

  @override
  Future<void> setPassword(int accountId, String password) => _s.write(key: _key(accountId), value: password);

  @override
  Future<void> deletePassword(int accountId) => _s.delete(key: _key(accountId));
}

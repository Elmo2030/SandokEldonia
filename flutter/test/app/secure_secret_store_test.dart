import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptvmac/app/secure_secret_store.dart';

void main() {
  test('passwords are stored per account and can be removed; an empty one stays empty (not missing)', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    FlutterSecureStorage.setMockInitialValues({});
    final s = SecureSecretStore();
    expect(await s.password(1), isNull);
    await s.setPassword(1, 'p1');
    await s.setPassword(2, '');
    expect(await s.password(1), 'p1');
    expect(await s.password(2), '');
    await s.deletePassword(1);
    expect(await s.password(1), isNull);
    expect(await s.password(2), '');
  });
}

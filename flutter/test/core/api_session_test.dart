import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:iptvmac/core/api_session.dart';
import 'package:iptvmac/core/errors.dart';

void main() {
  final url = Uri.parse('http://panel.test/player_api.php?username=u&password=p');

  // Xtream API URLs contain the account password: no cache, no gzip.
  test('requests are uncached and uncompressed', () async {
    late http.BaseRequest seen;
    final c = MockClient((r) async {
      seen = r;
      return http.Response('ok', 200);
    });
    expect(String.fromCharCodes(await apiGet(c, url)), 'ok');
    expect(seen.headers['Accept-Encoding'], 'identity');
    expect(seen.headers['Cache-Control'], 'no-store');
  });

  test('a non-2xx status is IPTVError.http', () async {
    final c = MockClient((r) async => http.Response('', 403));
    await expectLater(apiGet(c, url), throwsA(IPTVError.http(403)));
  });

  test('a body over the size limit is badResponse', () async {
    final c = MockClient((r) async => http.Response('x' * 11, 200));
    await expectLater(apiGet(c, url, maxBytes: 10), throwsA(IPTVError.badResponse));
    expect((await apiGet(c, url, maxBytes: 11)).length, 11);
  });

  test('a stalled server times out', () async {
    final c = MockClient((r) => Future.delayed(const Duration(seconds: 2), () => http.Response('late', 200)));
    await expectLater(apiGet(c, url, idleTimeout: const Duration(milliseconds: 50)), throwsA(isA<TimeoutException>()));
    await expectLater(apiGet(c, url, timeout: const Duration(milliseconds: 50)), throwsA(isA<TimeoutException>()));
  });

  test('a drip-fed body hits the overall timeout', () async {
    final c = MockClient.streaming((r, _) async => http.StreamedResponse(
        Stream.periodic(const Duration(milliseconds: 20), (_) => [65]), 200));
    await expectLater(apiGet(c, url, timeout: const Duration(milliseconds: 200)), throwsA(isA<TimeoutException>()));
  });
}

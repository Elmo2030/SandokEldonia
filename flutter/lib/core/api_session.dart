import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'errors.dart';

/// Provider-controlled size limit: a list this large is a broken or hostile response, not a catalog.
const maxResponseBytes = 300000000;

/// One GET for the Xtream/M3U layer. The URLs carry the account password: `package:http` has no on-disk cache, and this
/// asks for `no-store` anyway.
///
/// - [timeout]: the whole transfer (a drip-fed endless body must not keep a sync running for days).
/// - [idleTimeout]: the wait for the response and between two chunks of the body.
/// - `Accept-Encoding: identity`: no gzip, so a tiny response cannot expand into gigabytes.
/// Errors: a non-2xx status is `IPTVError.http`, a body over [maxBytes] is `IPTVError.badResponse`; network failures and
/// timeouts surface as the client's own exceptions (`TimeoutException`, `ClientException`, `SocketException`).
Future<Uint8List> apiGet(
  http.Client client,
  Uri url, {
  Duration timeout = const Duration(seconds: 600),
  Duration idleTimeout = const Duration(seconds: 60),
  int maxBytes = maxResponseBytes,
}) {
  Future<Uint8List> run() async {
    final req = http.Request('GET', url)
      ..headers['Accept-Encoding'] = 'identity'
      ..headers['Cache-Control'] = 'no-store';
    final resp = await client.send(req).timeout(idleTimeout);
    final code = resp.statusCode;
    if (code < 200 || code >= 300) {
      await resp.stream.listen(null).cancel();
      throw IPTVError.http(code);
    }
    final out = BytesBuilder(copy: false);
    await for (final chunk in resp.stream.timeout(idleTimeout)) {
      out.add(chunk);
      if (out.length > maxBytes) throw IPTVError.badResponse;
    }
    return out.takeBytes();
  }

  return run().timeout(timeout);
}

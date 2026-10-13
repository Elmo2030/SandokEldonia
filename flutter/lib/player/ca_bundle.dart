import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

/// libmpv's TLS library needs a PEM file of root certificates: Android keeps its roots as one file per certificate in a directory, so
/// HTTPS streams failed to open. The bundle (Mozilla roots, made by scripts/make-ca-bundle.sh for the iPhone app) ships as an asset and is
/// copied next to the app's data once; its path goes to mpv as `tls-ca-file`.
abstract final class CaBundle {
  static Future<String>? _path;

  static Future<String> path() => _path ??= _copy();

  static Future<String> _copy() async {
    final data = await rootBundle.load('assets/cacert.pem');
    final file = File('${(await getApplicationSupportDirectory()).path}/cacert.pem');
    if (!file.existsSync() || file.lengthSync() != data.lengthInBytes) {
      await file.create(recursive: true);
      await file.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), flush: true);
    }
    return file.path;
  }
}

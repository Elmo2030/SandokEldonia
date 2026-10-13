import 'dart:io';

import 'package:iptvmac/app/library_model.dart';
import 'package:iptvmac/downloads/background_download_engine.dart';
import 'package:iptvmac/downloads/downloads_model.dart';
import 'package:iptvmac/downloads/library_downloads.dart';
import 'package:path_provider/path_provider.dart';

/// The real downloads for the Android app: files in the app's own external files folder (`Android/data/<id>/files/Downloads`,
/// no permission needed), the list in [support]/downloads.json. Anything else, or any failure, gives the disabled model.
Future<DownloadsModel> openDownloads(LibraryModel library, Directory support) async {
  if (!Platform.isAndroid) return DownloadsModel.disabled();
  try {
    final external = await getExternalStorageDirectory();
    if (external == null) return DownloadsModel.disabled();
    final dir = '${external.path}/Downloads';
    final model = DownloadsModel(
      engine: BackgroundDownloadEngine(partialDir: '$dir/.partial'),
      store: File('${support.path}/downloads.json'),
      dir: dir,
      resolveUrl: library.downloadUrl,
    );
    await model.load();
    return model;
  } catch (_) {
    return DownloadsModel.disabled();
  }
}

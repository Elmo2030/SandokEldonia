/// Dart port of `Sources/IPTVCore/DownloadNaming.swift`: a safe, unused file name for a download.
abstract final class DownloadNaming {
  static const videoExtensions = {'mp4', 'mkv', 'avi', 'mov', 'm4v', 'ts', 'webm', 'flv', 'wmv', 'mpg', 'mpeg', 'm2ts', 'mts', '3gp'};

  static final _bad = RegExp(r'[/\\:?*"<>|\u0000-\u001F\u007F-\u009F]');
  static final _trim = RegExp(r'^[.\s]+|[.\s]+$');

  /// A direct media file the app can save as it is. Playlists (.m3u8, .mpd) and unknown containers are not.
  /// [orEmpty]: an Xtream movie without an extension is requested as .mp4, so "no extension" is fine there.
  static bool isDirectFile(String? ext, {bool orEmpty = false}) {
    final e = (ext ?? '').trim().toLowerCase();
    return e.isEmpty ? orEmpty : videoExtensions.contains(e);
  }

  /// "title.ext" ("title (2).ext" when taken). [taken] answers whether a name exists.
  static String fileName({required String title, String? ext, required bool Function(String) taken}) {
    var base = title.replaceAll(_bad, '-').replaceAll(_trim, '');
    if (base.isEmpty) base = 'download';
    base = String.fromCharCodes(base.runes.take(120));
    // The provider chooses the extension: only video containers, never .dmg/.apk/.sh/.zip.
    final e = (ext ?? '').toLowerCase();
    final suffix = videoExtensions.contains(e) ? e : 'mp4';
    // 255 bytes is the file name limit and CJK/emoji take 3-4 bytes a character: keep room for " (99)" and the extension.
    final runes = base.runes.toList();
    while (runes.isNotEmpty && _utf8Length(runes) > 200) {
      runes.removeLast();
    }
    base = String.fromCharCodes(runes);
    var name = '$base.$suffix', n = 2;
    while (taken(name)) {
      name = '$base ($n).$suffix';
      n++;
    }
    return name;
  }

  static int _utf8Length(List<int> runes) {
    var n = 0;
    for (final r in runes) {
      n += r < 0x80 ? 1 : r < 0x800 ? 2 : r < 0x10000 ? 3 : 4;
    }
    return n;
  }
}

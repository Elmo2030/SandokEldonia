import 'package:flutter_test/flutter_test.dart';
import 'package:iptvmac/downloads/download_naming.dart';

String name(String title, String? ext, {bool Function(String)? taken}) => DownloadNaming.fileName(title: title, ext: ext, taken: taken ?? (_) => false);

void main() {
  // The same cases as Tests/IPTVCoreTests/DownloadNamingTests.swift
  test('file names are safe and unique', () {
    expect(name('A/B: C?', 'MKV'), 'A-B- C-.mkv');
    expect(name('  ..  ', null), 'download.mp4');
    expect(name('x', '../../etc'), 'x.mp4');
    expect(name('Movie', 'mp4', taken: (n) => n == 'Movie.mp4' || n == 'Movie (2).mp4'), 'Movie (3).mp4');
    final long = name('ש' * 300, 'mp4'); // Hebrew: 2 bytes a letter
    expect(long.codeUnits.length <= 250 && long.endsWith('.mp4'), isTrue);
    expect(long.runes.fold<int>(0, (s, r) => s + (r < 0x80 ? 1 : r < 0x800 ? 2 : r < 0x10000 ? 3 : 4)) <= 250, isTrue);
    expect(name('x', 'dmg'), 'x.mp4'); // the provider must not choose .dmg/.pkg/.app
    expect(name('x', 'MKV'), 'x.mkv');
  });

  test('emoji and CJK stay within the byte limit, control characters become dashes', () {
    final emoji = name('🎬' * 200, 'mkv');
    expect(emoji.endsWith('.mkv'), isTrue);
    expect(utf8Length(emoji) <= 250, isTrue);
    expect(name('a\u0000b\u007Fc', 'mp4'), 'a-b-c.mp4');
    expect(name('a//b', 'mp4'), 'a--b.mp4');
  });

  test('only plain media files are direct files', () {
    for (final e in ['mp4', 'MKV', 'ts', 'avi']) {
      expect(DownloadNaming.isDirectFile(e), isTrue, reason: e);
    }
    for (final e in ['m3u8', 'mpd', 'php', 'dmg', '', null]) {
      expect(DownloadNaming.isDirectFile(e), isFalse, reason: '$e');
    }
    expect(DownloadNaming.isDirectFile(null, orEmpty: true), isTrue);
    expect(DownloadNaming.isDirectFile('m3u8', orEmpty: true), isFalse);
  });
}

int utf8Length(String s) => s.runes.fold(0, (n, r) => n + (r < 0x80 ? 1 : r < 0x800 ? 2 : r < 0x10000 ? 3 : 4));

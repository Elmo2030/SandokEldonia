import 'package:flutter_test/flutter_test.dart';
import 'package:iptvmac/player/video_quality.dart';

void main() {
  for (final (w, h, tag) in [
    (7680, 4320, '8K'), (3840, 2160, '4K'), (4096, 2160, '4K'), (2560, 1440, 'QHD'), (1920, 1080, 'FHD'), (1280, 720, 'HD'),
    (1024, 576, 'SD'), (720, 576, 'SD'), (640, 360, 'SD'),
    // cinema crops count by their width; a few missing lines do not change the tag
    (3840, 1600, '4K'), (1920, 800, 'FHD'), (1280, 536, 'HD'), (1920, 1038, 'FHD'),
  ]) {
    test('${w}x$h is $tag', () => expect(videoQualityLabel(w, h), tag));
  }

  for (final (w, h) in [(0, 0), (1920, 0), (-1, 1080)]) {
    test('${w}x$h is unknown', () => expect(videoQualityLabel(w, h), isNull));
  }
}

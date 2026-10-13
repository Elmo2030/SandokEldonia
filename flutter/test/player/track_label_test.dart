import 'package:flutter_test/flutter_test.dart';
import 'package:iptvmac/player/track_label.dart';

Track track(int id, {String? lang, String? title}) => Track(id: id, type: 'audio', lang: lang, title: title);

String? en(String c) => const {'en': 'English', 'he': 'Hebrew'}[c];
String? de(String c) => const {'he': 'Hebräisch'}[c];

void main() {
  test('a track is named by its language in the users language', () {
    expect(TrackLabel.text(track(1, lang: 'eng'), languageName: en), 'English');
    expect(TrackLabel.text(track(2, lang: 'he'), languageName: en), 'Hebrew');
    expect(TrackLabel.text(track(2, lang: 'heb'), languageName: de), 'Hebräisch');
  });

  test("the providers title is added only when it says more", () {
    expect(TrackLabel.text(track(1, lang: 'eng', title: 'Commentary'), languageName: en), 'English · Commentary');
    expect(TrackLabel.text(track(1, lang: 'eng', title: 'english'), languageName: en), 'English');
    expect(TrackLabel.text(track(1, lang: 'eng', title: 'Eng'), languageName: en), 'English');
    expect(TrackLabel.text(track(3, title: 'Director'), languageName: en), 'Director');
  });

  test('an unknown track falls back to its code or number', () {
    expect(TrackLabel.text(track(4), languageName: en), '#4');
    expect(TrackLabel.text(track(4, lang: 'und'), languageName: en), '#4');
    expect(TrackLabel.text(track(5, lang: 'zzz'), languageName: en), 'ZZZ');
    expect(TrackLabel.text(track(6, lang: '', title: ''), languageName: en), '#6');
  });

  test('without a name table the code is shown in capitals', () {
    expect(TrackLabel.text(track(1, lang: 'eng')), 'ENG');
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:iptvmac/app/source_draft.dart';
import 'package:iptvmac/core/models.dart';

void main() {
  test('Xtream form: complete only with name, server and user; a bad server is flagged while typing', () {
    final d = SourceDraft();
    expect(d.isComplete, isFalse);
    d
      ..name = 'Home'
      ..server = 'panel.test:8080'
      ..username = 'u';
    expect(d.isComplete, isTrue);
    expect(d.serverLooksWrong, isFalse); // the scheme may be left out for a server
    expect(d.canTest, isTrue);
    d.server = 'http://';
    expect(d.serverLooksWrong, isTrue);
    expect(d.canTest, isFalse);
  });

  test('M3U form needs a full http(s) link', () {
    final d = SourceDraft(kind: AccountKind.m3u, name: 'List', url: 'panel.test/list.m3u');
    expect(d.urlLooksWrong, isTrue);
    expect(d.canTest, isFalse);
    d.url = ' https://panel.test/list.m3u ';
    expect(d.urlLooksWrong, isFalse);
    expect(d.canTest, isTrue);
  });

  test('a get.php link holds the whole Xtream login', () {
    final l = SourceDraft.xtreamLogin('http://panel.test:8080/get.php?username=u&password=p%2Fq&type=m3u_plus')!;
    expect((l.server, l.username, l.password), ('http://panel.test:8080', 'u', 'p/q'));
    expect(SourceDraft.xtreamLogin('http://panel.test/list.m3u'), isNull);
    expect(SourceDraft.xtreamLogin('http://panel.test/get.php?username=&password=p'), isNull);
  });

  test('pasting: login link, plain playlist link, bare server; the name defaults to the host', () {
    var d = SourceDraft()..applyPasted('http://panel.test:8080/player_api.php?username=u&password=p');
    expect((d.kind, d.server, d.username, d.password, d.name), (AccountKind.xtream, 'http://panel.test:8080', 'u', 'p', 'panel.test'));
    d = SourceDraft()..applyPasted('https://lists.test/a.m3u');
    expect((d.kind, d.url, d.name), (AccountKind.m3u, 'https://lists.test/a.m3u', 'lists.test'));
    d = SourceDraft()..applyPasted('panel.test:8080');
    expect(d.server, 'panel.test:8080');
  });

  test('makeAccount trims and keeps the password apart from the account', () {
    final (:account, :password) = SourceDraft(name: ' Home ', server: ' http://panel.test ', username: ' u ', password: 'p').makeAccount();
    expect((account.name, account.server, account.username, account.url, password), ('Home', 'http://panel.test', 'u', null, 'p'));
    final m3u = SourceDraft(kind: AccountKind.m3u, name: 'L', url: ' https://x.test/a.m3u ', password: 'ignored').makeAccount();
    expect((m3u.account.url, m3u.password), ('https://x.test/a.m3u', null));
  });
}

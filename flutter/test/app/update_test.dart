import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptvmac/app/library_model.dart';
import 'package:iptvmac/ui/widgets.dart';

import 'harness.dart';

String feed(List<String> tags) =>
    '<feed>${[for (final t in tags) '<entry><link rel="alternate" href="https://github.com/Goelir/IPTVMac/releases/tag/$t"/></entry>'].join()}</feed>';

void main() {
  test('a newer version in the feed becomes the banner; dismissing hides it until an even newer one comes', () async {
    final h = await Harness.createPlain(appVersion: '1.0.2');
    h.provider.feed = feed(['android-v1.0.3', 'android-v1.0.2', 'v0.9.3']);
    expect(h.model.updateAvailable, isNull, reason: 'nothing known yet');
    await h.model.checkForUpdate();
    expect(h.model.updateAvailable, '1.0.3');
    h.model.dismissUpdate();
    expect(h.model.updateAvailable, isNull);
    expect(h.model.newerVersion, '1.0.3', reason: 'Settings still says so');
    h.provider.feed = feed(['android-v1.0.4', 'android-v1.0.3']);
    await h.model.checkForUpdate(manual: true);
    expect(h.model.updateAvailable, '1.0.4');
  });

  test('no banner when the installed version is the newest or newer', () async {
    final h = await Harness.createPlain(appVersion: '1.0.3');
    h.provider.feed = feed(['android-v1.0.3', 'android-v1.0.2']);
    await h.model.checkForUpdate();
    expect(h.model.updateAvailable, isNull);
    expect(h.model.newerVersion, isNull);
    expect(h.model.updateCheck, UpdateCheck.done);
  });

  test('automatic checks run at most every 6 hours and obey the switch; a manual check always runs', () async {
    final h = await Harness.createPlain(appVersion: '1.0.2');
    h.provider.feed = feed(['android-v1.0.2']);
    await h.model.checkForUpdate();
    await h.model.checkForUpdate();
    expect(h.provider.feedCalls, 1, reason: 'the second automatic check is too soon');
    await h.model.checkForUpdate(manual: true);
    expect(h.provider.feedCalls, 2);
    final off = await Harness.createPlain(appVersion: '1.0.2', prefs: {'autoCheckUpdates': false});
    await off.model.checkForUpdate();
    expect(off.provider.feedCalls, 0, reason: 'switched off');
    await off.model.checkForUpdate(manual: true);
    expect(off.provider.feedCalls, 1);
  });

  test('a failing check says so and keeps what was known; without a version there is no check at all', () async {
    final h = await Harness.createPlain(appVersion: '1.0.2');
    h.provider.feed = feed(['android-v1.0.3']);
    await h.model.checkForUpdate();
    h.provider.fail = true;
    await h.model.checkForUpdate(manual: true);
    expect(h.model.updateCheck, UpdateCheck.failed);
    expect(h.model.updateAvailable, '1.0.3');
    final dev = await Harness.createPlain();
    await dev.model.checkForUpdate(manual: true);
    expect(dev.provider.feedCalls, 0);
  });

  testWidgets('the banner offers the release page and can be closed', (t) async {
    final h = await Harness.create(t, withAccount: true, sync: true, appVersion: '1.0.2');
    h.provider.feed = feed(['android-v1.0.3']);
    await t.runAsync(h.model.checkForUpdate);
    final opened = <String>[];
    final old = openUpdatePage;
    openUpdatePage = (v) async => opened.add(v);
    addTearDown(() => openUpdatePage = old);
    await h.pumpApp(t);
    await go(t);
    expect(find.text('Version 1.0.3 is available'), findsOneWidget);
    await t.tap(find.text('Update now'));
    expect(opened, ['1.0.3']);
    await t.tap(find.byTooltip('Later'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('update-banner')), findsNothing);
  });

  testWidgets('Settings: the check button asks the feed and answers; the switch turns the automatic check off', (t) async {
    final h = await Harness.create(t, withAccount: true, sync: true, appVersion: '1.0.2');
    h.provider.feed = feed(['android-v1.0.2']);
    await h.pumpApp(t);
    await go(t);
    await t.tap(find.text('Settings').last);
    await go(t);
    await t.scrollUntilVisible(find.byKey(const Key('check-update-tile')), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Current version: 1.0.2'), findsOneWidget);
    await t.ensureVisible(find.byKey(const Key('check-update-tile')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('check-update-tile')));
    await go(t);
    expect(h.provider.feedCalls, 1);
    expect(find.text('You have the latest version'), findsOneWidget);
    await t.ensureVisible(find.byKey(const Key('auto-update-switch')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('auto-update-switch')));
    await t.pumpAndSettle();
    expect(h.model.prefs.autoCheckUpdates, false);
  });
}

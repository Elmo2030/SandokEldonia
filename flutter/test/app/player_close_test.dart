import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptvmac/app/library_model.dart';
import 'package:iptvmac/player/play_request.dart';
import 'package:iptvmac/ui/play.dart' as play;
import 'package:provider/provider.dart';

import 'harness.dart';

/// Regression: the real player screen blocks a plain pop (PopScope canPop: false) and asks the host to close; the host must pop for real.
/// With `maybePop` the PopScope refused it again and the X button did nothing on the phone.
void main() {
  testWidgets('the close button and the system back both leave the player', (tester) async {
    final h = await Harness.create(tester);
    final original = play.playerBuilder;
    addTearDown(() => play.playerBuilder = original);
    play.playerBuilder = (r, host) => PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) host.closePlayer();
          },
          child: Scaffold(body: TextButton(key: const Key('x'), onPressed: host.closePlayer, child: const Text('close'))),
        );
    final request = PlayRequest(title: 'T', url: Uri.parse('http://panel.test/a.mp4'), isLive: false);
    await tester.pumpWidget(ChangeNotifierProvider<LibraryModel>.value(
      value: h.model,
      child: MaterialApp(home: Builder(builder: (c) => TextButton(onPressed: () => play.openPlayer(c, request), child: const Text('open')))),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('x')), findsOneWidget);
    await tester.tap(find.byKey(const Key('x')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('x')), findsNothing, reason: 'the X button must leave the player');

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute(); // the system back button
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('x')), findsNothing, reason: 'back must leave the player');
  });
}

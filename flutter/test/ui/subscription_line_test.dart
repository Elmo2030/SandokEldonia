import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptvmac/core/subscription_info.dart';
import 'package:iptvmac/l10n/app_localizations.dart';
import 'package:iptvmac/ui/settings_screen.dart';

final now = DateTime(2027, 1, 10, 12);

Future<void> show(WidgetTester t, SubscriptionInfo info, {Locale locale = const Locale('en')}) => t.pumpWidget(MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SubscriptionLine(info, now: now)),
    ));

Color colorOf(WidgetTester t) => t.widget<Text>(find.byKey(const Key('subscription-line'))).style!.color!;

void main() {
  testWidgets('shows the date and the days left, in the normal colour when it is far away', (t) async {
    await show(t, SubscriptionInfo(expires: now.add(const Duration(days: 140))));
    final s = t.widget<Text>(find.byKey(const Key('subscription-line'))).data!;
    expect(s, contains('Expires'));
    expect(s, contains('Days left: 140'));
    expect(colorOf(t), isNot(Colors.orange));
  });

  testWidgets('turns orange within a week and red once it ended (then without days left)', (t) async {
    await show(t, SubscriptionInfo(expires: now.add(const Duration(days: 3))));
    expect(colorOf(t), Colors.orange);
    await show(t, SubscriptionInfo(expires: now.subtract(const Duration(days: 2))));
    expect(t.widget<Text>(find.byKey(const Key('subscription-line'))).data!, allOf(contains('Expired'), isNot(contains('Days left'))));
    expect(colorOf(t), ThemeData().colorScheme.error);
  });

  testWidgets('nothing at all when the panel gave no date', (t) async {
    await show(t, const SubscriptionInfo());
    expect(find.byKey(const Key('subscription-line')), findsNothing);
  });

  testWidgets('works in Hebrew', (t) async {
    await show(t, SubscriptionInfo(expires: now.add(const Duration(days: 30))), locale: const Locale('he'));
    expect(t.widget<Text>(find.byKey(const Key('subscription-line'))).data!, allOf(contains('תוקף עד'), contains('30')));
  });
}

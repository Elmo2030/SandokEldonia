import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptvmac/l10n/app_localizations.dart';
import 'package:iptvmac/ui/widgets.dart';

Future<String> status(WidgetTester t, double? p, {Locale locale = const Locale('en')}) async {
  late String text;
  await t.pumpWidget(MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Builder(builder: (c) {
      text = syncStatusText(c, p);
      return const SizedBox();
    }),
  ));
  return text;
}

void main() {
  testWidgets('the sync line shows the percentage once the sync reports one', (t) async {
    expect(await status(t, null), 'Syncing…');
    expect(await status(t, 0), 'Syncing… 0%');
    expect(await status(t, 0.427), 'Syncing… 43%');
    expect(await status(t, 1), 'Syncing… 100%');
  });

  testWidgets('works in Hebrew and Arabic', (t) async {
    expect(await status(t, 0.5, locale: const Locale('he')), allOf(contains('50'), contains('%')));
    expect(await status(t, 0.5, locale: const Locale('ar')), allOf(contains('50'), contains('%')));
  });
}

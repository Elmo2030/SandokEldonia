import 'package:flutter_test/flutter_test.dart';
import 'package:iptvmac/core/subscription_info.dart';

final now = DateTime.fromMillisecondsSinceEpoch(1800000000 * 1000);

SubscriptionInfo after(double days) => SubscriptionInfo(expires: now.add(Duration(seconds: (days * 86400).round())));

void main() {
  test('the expiry is read from a string or a number', () {
    final want = DateTime.fromMillisecondsSinceEpoch(1800864000 * 1000);
    expect(SubscriptionInfo.fromUserInfo({'exp_date': '1800864000'}).expires, want);
    expect(SubscriptionInfo.fromUserInfo({'exp_date': 1800864000}).expires, want);
    expect(SubscriptionInfo.fromUserInfo({'exp_date': ' 1800864000 '}).expires, want);
  });

  for (final v in [null, '', '0', 0, 'never', '-5', '99999999999']) {
    test('exp_date $v is no date', () => expect(SubscriptionInfo.fromUserInfo({'exp_date': v}).expires, isNull));
  }

  test('a panel without the field has no expiry and an unknown state', () {
    expect(SubscriptionInfo.fromUserInfo({}).expires, isNull);
    expect(const SubscriptionInfo().state(now), SubscriptionState.unknown);
    expect(const SubscriptionInfo().daysLeft(now), isNull);
  });

  test('days left round up and the state follows', () {
    expect(after(30).daysLeft(now), 30);
    expect(after(0.1).daysLeft(now), 1, reason: 'ends tonight: one day left');
    expect(after(0).daysLeft(now), 0);
    expect(after(-3).daysLeft(now), -3);
    expect(after(30).state(now), SubscriptionState.active);
    expect(after(8).state(now), SubscriptionState.active);
    expect(after(7).state(now), SubscriptionState.soon);
    expect(after(1).state(now), SubscriptionState.soon);
    expect(after(0).state(now), SubscriptionState.expired);
    expect(after(-1).state(now), SubscriptionState.expired);
  });

  test('max connections must be positive', () {
    expect(SubscriptionInfo.fromUserInfo({'max_connections': '2'}).maxConnections, 2);
    expect(SubscriptionInfo.fromUserInfo({'max_connections': '0'}).maxConnections, isNull);
    expect(SubscriptionInfo.fromUserInfo({}).maxConnections, isNull);
  });

  test('the info survives the preferences round trip', () {
    final a = SubscriptionInfo(expires: DateTime.fromMillisecondsSinceEpoch(1800864000 * 1000), maxConnections: 3);
    expect(SubscriptionInfo.fromJson(a.toJson()), a);
    expect(SubscriptionInfo.fromJson(const SubscriptionInfo().toJson()), const SubscriptionInfo());
  });
}

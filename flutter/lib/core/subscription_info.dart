/// What an Xtream panel says about the subscription itself (`user_info` of the login answer). Everything is optional: a panel may leave any
/// of it out, and the app shows only what it got. Same rules as SubscriptionInfo.swift in the Apple apps.
class SubscriptionInfo {
  const SubscriptionInfo({this.expires, this.maxConnections});

  /// When the subscription ends; null when the panel gave no date (or `exp_date` is null/0/"", which panels use for "never").
  final DateTime? expires;
  final int? maxConnections;

  /// From the `user_info` object: `exp_date` is a Unix time in seconds, as a string or a number.
  factory SubscriptionInfo.fromUserInfo(Map<Object?, Object?> u) {
    final exp = _number(u['exp_date']);
    final max = _number(u['max_connections']);
    return SubscriptionInfo(
      expires: exp != null && exp > 0 && exp < 4102444800 ? DateTime.fromMillisecondsSinceEpoch((exp * 1000).round()) : null, // bigger than year 2100 = "never"
      maxConnections: max != null && max >= 1 ? max.toInt() : null,
    );
  }

  static double? _number(Object? v) => v is num ? v.toDouble() : v is String ? double.tryParse(v.trim()) : null;

  /// Whole days left, rounded up (a subscription that ends tonight has 1 day left); 0 or less once it ended. Null without a date.
  int? daysLeft(DateTime now) => expires == null ? null : (expires!.difference(now).inSeconds / 86400).ceil();

  /// `soon` = a week or less, the point where the app should make the date stand out.
  SubscriptionState state(DateTime now) {
    final d = daysLeft(now);
    if (d == null) return SubscriptionState.unknown;
    return d <= 0 ? SubscriptionState.expired : (d <= 7 ? SubscriptionState.soon : SubscriptionState.active);
  }

  Map<String, Object?> toJson() => {'expires': expires?.millisecondsSinceEpoch, 'maxConnections': maxConnections};

  factory SubscriptionInfo.fromJson(Map<String, Object?> j) => SubscriptionInfo(
        expires: j['expires'] is int ? DateTime.fromMillisecondsSinceEpoch(j['expires']! as int) : null,
        maxConnections: j['maxConnections'] is int ? j['maxConnections']! as int : null,
      );

  @override
  bool operator ==(Object other) => other is SubscriptionInfo && other.expires == expires && other.maxConnections == maxConnections;

  @override
  int get hashCode => Object.hash(expires, maxConnections);
}

enum SubscriptionState { unknown, active, soon, expired }

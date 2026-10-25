import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:iptvmac/core/subscription_info.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The small settings (same keys as the Apple apps' UserDefaults) and the recent searches (local only, newest first).
class AppPrefs {
  AppPrefs(this._p);
  final SharedPreferences _p;

  static const recentLimit = 8;

  String? get playlist => _p.getString('playlist'); // "all" or an account id
  set playlist(String? v) => v == null ? _p.remove('playlist') : _p.setString('playlist', v);

  /// The last subscription answers of the Xtream panels by playlist id, kept so a date shows at once and offline.
  Map<int, SubscriptionInfo> get subscriptions {
    try {
      final raw = jsonDecode(_p.getString('subscriptions') ?? '{}');
      return {
        if (raw is Map)
          for (final e in raw.entries)
            if (int.tryParse('${e.key}') case final id? when e.value is Map) id: SubscriptionInfo.fromJson((e.value as Map).cast<String, Object?>()),
      };
    } catch (_) {
      return {};
    }
  }

  set subscriptions(Map<int, SubscriptionInfo> v) => _p.setString('subscriptions', jsonEncode({for (final e in v.entries) '${e.key}': e.value.toJson()}));

  int get refreshHours => _p.getInt('refreshHours') ?? 0; // 0 = only when the app opens
  set refreshHours(int v) => _p.setInt('refreshHours', v);

  String get hiddenWords => _p.getString('hiddenCategoryWords') ?? '';
  set hiddenWords(String v) => _p.setString('hiddenCategoryWords', v);

  String get appearance => _p.getString('appearance') ?? 'system';
  set appearance(String v) => _p.setString('appearance', v);

  ThemeMode get themeMode => switch (appearance) { 'light' => ThemeMode.light, 'dark' => ThemeMode.dark, _ => ThemeMode.system };

  List<String> get recents => _p.getStringList('recentSearches') ?? const [];

  void addRecent(String term) {
    final t = term.trim();
    if (t.length < 2) return;
    _p.setStringList('recentSearches', [t, ...recents.where((r) => r.toLowerCase() != t.toLowerCase())].take(recentLimit).toList());
  }

  void removeRecent(String term) => _p.setStringList('recentSearches', [for (final r in recents) if (r != term) r]);
  void clearRecents() => _p.remove('recentSearches');
}

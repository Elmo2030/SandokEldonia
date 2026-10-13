import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The small settings (same keys as the Apple apps' UserDefaults) and the recent searches (local only, newest first).
class AppPrefs {
  AppPrefs(this._p);
  final SharedPreferences _p;

  static const recentLimit = 8;

  String? get playlist => _p.getString('playlist'); // "all" or an account id
  set playlist(String? v) => v == null ? _p.remove('playlist') : _p.setString('playlist', v);

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

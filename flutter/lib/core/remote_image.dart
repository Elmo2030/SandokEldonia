/// Image links come from the provider and are fetched without a click: http(s) only, and never a device on the user's
/// own network (a `tvg-logo="http://192.168.1.1/reboot"` would be a browse-to-trigger request).
Uri? safeImageUrl(String? s) {
  final t = s?.trim();
  if (t == null || t.isEmpty || t.length > 2048) return null;
  final u = Uri.tryParse(t);
  if (u == null || (u.scheme != 'http' && u.scheme != 'https')) return null;
  final h = u.host.toLowerCase();
  if (h.isEmpty) return null;
  if (h == 'localhost' || h.endsWith('.local') || h.endsWith('.internal') || h.endsWith('.lan')) return null;
  if (!h.contains('.') && !h.contains(':')) return null;
  final p = [for (final x in h.split('.')) if (int.tryParse(x) != null) int.parse(x)];
  if (p.length == 4) {
    if (p[0] == 10 || p[0] == 127 || p[0] == 0 || (p[0] == 169 && p[1] == 254) || (p[0] == 192 && p[1] == 168) ||
        (p[0] == 172 && p[1] >= 16 && p[1] <= 31)) {
      return null;
    }
  }
  if (h.contains(':') && (h == '::1' || h.startsWith('fe80') || h.startsWith('fc') || h.startsWith('fd'))) return null;
  return u;
}

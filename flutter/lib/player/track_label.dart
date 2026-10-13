/// An audio or subtitle track as the engine reports it. [type] is 'video', 'audio' or 'sub'; [id] is what the engine selects by.
class Track {
  const Track({required this.id, required this.type, this.lang, this.title, this.selected = false});
  final int id;
  final String type;
  final String? lang;
  final String? title;
  final bool selected;
}

/// The text of a track in a menu: the language by its name in the user's language ("English", "עברית"), then the provider's title
/// when it adds something ("Commentary"), else "#id". The engine gives ISO 639-2 codes ("eng", "heb") or 639-1 ones.
abstract final class TrackLabel {
  /// ISO 639-2 (also the "B" variants) to 639-1 for the languages IPTV providers use; names come from CLDR by the 2-letter code.
  static const iso3to1 = <String, String>{
    'alb': 'sq', 'sqi': 'sq', 'ara': 'ar', 'ben': 'bn', 'bul': 'bg', 'chi': 'zh', 'zho': 'zh', 'cze': 'cs', 'ces': 'cs', 'dut': 'nl',
    'nld': 'nl', 'eng': 'en', 'fas': 'fa', 'per': 'fa', 'fra': 'fr', 'fre': 'fr', 'ger': 'de', 'deu': 'de', 'gre': 'el', 'ell': 'el',
    'heb': 'he', 'hin': 'hi', 'hun': 'hu', 'ind': 'id', 'ita': 'it', 'jpn': 'ja', 'kor': 'ko', 'pol': 'pl', 'por': 'pt', 'rum': 'ro',
    'ron': 'ro', 'rus': 'ru', 'spa': 'es', 'swe': 'sv', 'tha': 'th', 'tur': 'tr', 'ukr': 'uk', 'urd': 'ur', 'vie': 'vi', 'amh': 'am',
    'dan': 'da', 'fin': 'fi', 'nor': 'no', 'hrv': 'hr', 'srp': 'sr', 'slk': 'sk', 'slv': 'sl', 'lit': 'lt', 'lav': 'lv',
    'est': 'et', 'cat': 'ca', 'tam': 'ta', 'tel': 'te', 'mal': 'ml', 'kur': 'ku', 'pus': 'ps', 'swa': 'sw', 'msa': 'ms', 'may': 'ms',
  };

  /// [languageName] returns the name of a 2-letter code in the user's language, or null when it does not know it.
  static String text(Track t, {String? Function(String code)? languageName}) {
    final code = t.lang;
    String? language;
    if (code != null && code.isNotEmpty && code != 'und') {
      final short = code.length == 3 ? iso3to1[code.toLowerCase()] : code;
      final name = short == null ? null : languageName?.call(short);
      language = name == null || name == code ? code.toUpperCase() : _capitalized(name);
    }
    final title = t.title == null || t.title!.isEmpty ? null : t.title;
    if (language != null && title != null) {
      return title.toLowerCase() == language.toLowerCase() || language.startsWith(title) ? language : '$language · $title';
    }
    return language ?? title ?? '#${t.id}';
  }

  static String _capitalized(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

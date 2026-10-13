import 'package:flutter/material.dart';
import 'package:iptvmac/core/item_info.dart';
import 'package:iptvmac/l10n/app_localizations.dart';

/// Year, rating (a star and the number), duration and genre: whichever the provider has. Wraps instead of truncating.
class InfoMetaLine extends StatelessWidget {
  const InfoMetaLine({super.key, required this.info});
  final ItemInfo info;

  static bool hasAny(ItemInfo i) => i.year != null || i.rating != null || i.durationMinutes != null || i.genre != null;

  static String duration(AppLocalizations l, int minutes) {
    final h = minutes ~/ 60, m = minutes % 60;
    if (h == 0) return l.unitMinutesShort(m);
    if (m == 0) return l.unitHoursShort(h);
    return '${l.unitHoursShort(h)} ${l.unitMinutesShort(m)}';
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    Widget part(String text, String label, {bool star = false}) => Semantics(
          label: '$label: $text',
          excludeSemantics: true,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (star) const Padding(padding: EdgeInsetsDirectional.only(end: 3), child: Icon(Icons.star_rounded, size: 16, color: Colors.amber)),
            Text(text, style: style),
          ]),
        );
    return Wrap(spacing: 12, runSpacing: 4, children: [
      if (info.year != null) part('${info.year}', l.infoYear),
      if (info.rating != null) part(info.rating!.toStringAsFixed(1), l.infoRating, star: true),
      if (info.durationMinutes != null) part(duration(l, info.durationMinutes!), l.infoDuration),
      if (info.genre != null) part(info.genre!, l.infoGenre),
    ]);
  }
}

/// The provider's text, as plain text (never interpreted), under a small heading.
class InfoFacts extends StatelessWidget {
  const InfoFacts({super.key, required this.info});
  final ItemInfo info;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    Widget block(String label, String value, {bool big = false}) => Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Semantics(header: true, child: Text(label, style: t.titleSmall?.copyWith(color: muted))),
            const SizedBox(height: 4),
            Text(value, style: big ? t.bodyLarge?.copyWith(height: 1.4) : t.bodyMedium),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (info.plot != null) block(l.infoPlot, info.plot!, big: true),
      if (info.director != null) block(l.infoDirector, info.director!),
      if (info.cast != null) block(l.infoCast, info.cast!),
      if (info.country != null) block(l.infoCountry, info.country!),
    ]);
  }
}

/// Poster beside the text; with big text the poster sits above it (the text would otherwise be squeezed into a sliver).
class HeaderStack extends StatelessWidget {
  const HeaderStack({super.key, required this.poster, required this.text});
  final Widget poster, text;

  @override
  Widget build(BuildContext context) {
    final big = MediaQuery.textScalerOf(context).scale(1) > 1.5;
    return big
        ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [poster, const SizedBox(height: 12), text])
        : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [poster, const SizedBox(width: 16), Expanded(child: text)]);
  }
}

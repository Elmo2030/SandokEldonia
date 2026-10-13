import 'package:flutter/material.dart';
import 'package:iptvmac/app/library_model.dart';
import 'package:iptvmac/core/models.dart';
import 'package:iptvmac/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

/// Every category, with a field to filter them; grouped by playlist in All mode.
Future<void> showCategorySheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _CategorySheet(),
    );

class _CategorySheet extends StatefulWidget {
  const _CategorySheet();
  @override
  State<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends State<_CategorySheet> {
  var _query = '';

  @override
  Widget build(BuildContext context) {
    final m = context.watch<LibraryModel>();
    final l = AppLocalizations.of(context);
    final q = _query.toLowerCase();
    final cats = [for (final c in m.categories) if (q.isEmpty || c.name.toLowerCase().contains(q)) c];

    Widget row(String tag, String title, [IconData? icon]) {
      final sel = m.selectedCategory == tag;
      return ListTile(
        leading: icon == null ? null : Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: sel ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary) : null,
        selected: sel,
        onTap: () {
          m.selectCategory(tag);
          Navigator.pop(context);
        },
      );
    }

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.75,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            decoration: InputDecoration(hintText: l.catFilter, prefixIcon: const Icon(Icons.search)),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(
          child: ListView(children: [
            if (q.isEmpty) ...[
              row('__all', l.catAll, Icons.grid_view),
              row('__fav', l.catFavorites, Icons.star_outline_rounded),
              if (m.tab != ItemType.live) row('__hist', l.catContinue, Icons.schedule),
              const Divider(),
            ],
            if (m.allPlaylists)
              for (final a in m.accounts) ...[
                if (cats.any((c) => c.accountId == a.id))
                  Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 4), child: Text(a.name, style: Theme.of(context).textTheme.labelLarge)),
                for (final c in cats.where((c) => c.accountId == a.id)) row(m.categoryTag(c), c.name),
              ]
            else
              for (final c in cats) row(m.categoryTag(c), c.name),
          ]),
        ),
      ]),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:iptvmac/app/library_model.dart';
import 'package:iptvmac/core/models.dart';
import 'package:iptvmac/l10n/app_localizations.dart';
import 'package:iptvmac/ui/browse_screen.dart';
import 'package:iptvmac/ui/item_views.dart';
import 'package:iptvmac/ui/widgets.dart';
import 'package:provider/provider.dart';

/// What belongs to you: what you started watching, and your favorites by type.
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final m = context.watch<LibraryModel>();
    final l = AppLocalizations.of(context);
    final t = Theme.of(context).textTheme;
    final shelf = [...m.continueMovies, ...m.continueSeries];
    final groups = [for (final type in ItemType.values) (type, m.favoriteItems[type] ?? const <Item>[])].where((g) => g.$2.isNotEmpty).toList();
    final heading = t.titleMedium?.copyWith(fontWeight: FontWeight.w600);
    return Scaffold(
      appBar: AppBar(title: Text(l.tabLibrary), actions: const [PlaylistMenu()]),
      body: RefreshIndicator(
        onRefresh: m.sync,
        child: shelf.isEmpty && groups.isEmpty
            ? EmptyState(icon: Icons.video_library_outlined, title: l.libraryEmpty, hint: l.libraryEmptyHint)
            : CustomScrollView(physics: const AlwaysScrollableScrollPhysics(), slivers: [
                const SliverToBoxAdapter(child: SizedBox(height: 12)),
                if (shelf.isNotEmpty) SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.only(bottom: 20), child: ContinueShelf(entries: shelf))),
                if (groups.isNotEmpty) SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 4), child: Text(l.catFavorites, style: heading))),
                for (final (type, items) in groups) ...[
                  SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 8), child: Text(sectionTitle(l, type), style: t.titleSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)))),
                  if (type == ItemType.live) ChannelListSliver(items: items) else PosterGridSliver(items: items),
                ],
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ]),
      ),
    );
  }
}

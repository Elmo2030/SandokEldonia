import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:iptvmac/app/library_model.dart';
import 'package:iptvmac/core/backup.dart';
import 'package:iptvmac/core/models.dart';
import 'package:iptvmac/l10n/app_localizations.dart';
import 'package:iptvmac/ui/about_screens.dart';
import 'package:iptvmac/ui/missing_strings.dart';
import 'package:iptvmac/ui/source_form.dart';
import 'package:provider/provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.settingsTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(padding: const EdgeInsets.only(bottom: 24), children: const [
            _SourcesSection(),
            _PreferencesSection(),
            _HiddenCategoriesSection(),
            _BackupSection(),
            _ClearSection(),
            _AboutTile(),
          ]),
        ),
      ),
    );
  }
}

/// A titled group of rows on a card, with an optional note under it.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children, this.note});
  final String? title;
  final List<Widget> children;
  final Widget? note;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (title != null) Padding(padding: const EdgeInsets.fromLTRB(4, 0, 4, 8), child: Semantics(header: true, child: Text(title!, style: t.titleSmall?.copyWith(color: cs.primary)))),
        Card(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), clipBehavior: Clip.antiAlias, child: Column(children: children)),
        if (note != null) Padding(padding: const EdgeInsets.fromLTRB(4, 8, 4, 0), child: DefaultTextStyle.merge(style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant), child: note!)),
      ]),
    );
  }
}

Future<bool> confirm(BuildContext context, {required String title, required String message, required String action}) async {
  final l = AppLocalizations.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(l.commonCancel)),
        TextButton(onPressed: () => Navigator.pop(c, true), child: Text(action, style: TextStyle(color: Theme.of(c).colorScheme.error))),
      ],
    ),
  );
  return ok == true;
}

class _SourcesSection extends StatelessWidget {
  const _SourcesSection();

  @override
  Widget build(BuildContext context) {
    final m = context.watch<LibraryModel>();
    final l = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return _Section(
      title: l.settingsAccounts,
      note: m.syncing
          ? Row(children: [const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)), const SizedBox(width: 8), Text(l.syncRunning)])
          : m.syncMessage != null
              ? Text('${l.syncFailed}: ${m.syncMessage}', style: TextStyle(color: cs.error))
              : null,
      children: [
        for (final a in m.accounts)
          ListTile(
            key: Key('source-${a.id}'),
            leading: Icon(a.kind == AccountKind.xtream ? Icons.dns_outlined : Icons.list_alt, color: cs.primary),
            title: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text([a.kind == AccountKind.xtream ? l.kindXtream : l.kindM3u, if (a.kind == AccountKind.xtream) a.username].whereType<String>().join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(icon: const Icon(Icons.refresh), tooltip: l.syncNow, onPressed: m.syncing ? null : () => m.sync([a])),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: l.settingsDelete,
                onPressed: () async {
                  if (await confirm(context, title: a.name, message: l.sourceDeleteWarn, action: l.settingsDelete)) await m.deleteAccount(a);
                },
              ),
            ]),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SourceFormScreen(edit: a))),
          ),
        ListTile(
          key: const Key('add-source-tile'),
          leading: Icon(Icons.add_circle, color: cs.primary),
          title: Text(l.accountAdd),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SourceFormScreen())),
        ),
      ],
    );
  }
}

class _PreferencesSection extends StatelessWidget {
  const _PreferencesSection();

  @override
  Widget build(BuildContext context) {
    final m = context.watch<LibraryModel>();
    final l = AppLocalizations.of(context);
    final labels = {0: l.settingsRefresh0, 6: l.settingsRefresh6, 12: l.settingsRefresh12, 24: l.settingsRefresh24};
    return Column(children: [
      _Section(title: null, children: [
        ListTile(
          title: Text(l.settingsRefresh),
          subtitle: Text(labels[m.refreshHours] ?? labels[0]!),
          onTap: () async {
            final h = await showDialog<int>(
              context: context,
              builder: (c) => SimpleDialog(title: Text(l.settingsRefresh), children: [
                for (final e in labels.entries)
                  ListTile(
                    title: Text(e.value),
                    trailing: e.key == m.refreshHours ? Icon(Icons.check, color: Theme.of(c).colorScheme.primary) : null,
                    onTap: () => Navigator.pop(c, e.key),
                  ),
              ]),
            );
            if (h != null) m.setRefreshHours(h);
          },
        ),
        ListTile(
          title: Text(l.settingsAppearance),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: 'system', label: Text(l.settingsSystem, maxLines: 1, overflow: TextOverflow.ellipsis)),
                ButtonSegment(value: 'light', label: Text(l.appearanceLight, maxLines: 1, overflow: TextOverflow.ellipsis)),
                ButtonSegment(value: 'dark', label: Text(l.appearanceDark, maxLines: 1, overflow: TextOverflow.ellipsis)),
              ],
              selected: {m.prefs.appearance},
              onSelectionChanged: (s) => m.setAppearance(s.first),
            ),
          ),
        ),
      ]),
      _Section(title: null, note: Text(Missing.languageNote), children: [
        ListTile(title: Text(l.settingsInterfaceLanguage), trailing: Text(Localizations.localeOf(context).toLanguageTag())),
      ]),
    ]);
  }
}

class _HiddenCategoriesSection extends StatefulWidget {
  const _HiddenCategoriesSection();
  @override
  State<_HiddenCategoriesSection> createState() => _HiddenCategoriesSectionState();
}

class _HiddenCategoriesSectionState extends State<_HiddenCategoriesSection> {
  late final _c = TextEditingController(text: context.read<LibraryModel>().prefs.hiddenWords);
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final m = context.read<LibraryModel>();
    return _Section(
      title: l.settingsHideCategories,
      note: Text(l.settingsHideCategoriesNote),
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            key: const Key('hidden-words'),
            controller: _c,
            autocorrect: false,
            decoration: InputDecoration(labelText: l.settingsHideCategoriesWords, hintText: 'xxx, adult'),
            onChanged: (v) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 600), () => m.setHiddenWords(v)); // applied once typing pauses
            },
          ),
        ),
      ],
    );
  }
}

class _BackupSection extends StatelessWidget {
  const _BackupSection();

  void _say(BuildContext context, String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _export(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final m = context.read<LibraryModel>();
    try {
      final saved = await FilePicker.saveFile(
          fileName: 'IPTVMac backup.json', bytes: utf8.encode(m.backupJson()), mimeType: 'application/json', type: FileType.custom, allowedExtensions: ['json']);
      if (saved != null && context.mounted) _say(context, l.backupExported);
    } catch (e) {
      if (context.mounted) _say(context, '${l.backupFailed}: $e');
    }
  }

  Future<void> _import(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final m = context.read<LibraryModel>();
    try {
      final f = await FilePicker.pickFile(type: FileType.any);
      if (f == null) return;
      if ((await f.length() ?? 0) > Backup.maxBytes) throw BackupError.tooLarge;
      await m.importBackup(await f.readAsBytes());
      if (context.mounted) _say(context, l.backupImported);
    } on BackupError catch (e) {
      if (context.mounted) {
        _say(context, switch (e) { BackupError.tooLarge => l.backupErrorTooLarge, BackupError.unsupportedVersion => l.backupErrorVersion, BackupError.invalid => l.backupErrorInvalid });
      }
    } catch (e) {
      if (context.mounted) _say(context, '${l.backupFailed}: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return _Section(title: l.settingsBackup, note: Text(l.backupWarn), children: [
      ListTile(leading: Icon(Icons.upload_file, color: cs.primary), title: Text(l.backupExport), onTap: () => _export(context)),
      ListTile(leading: Icon(Icons.download, color: cs.primary), title: Text(l.backupImport), onTap: () => _import(context)),
    ]);
  }
}

class _ClearSection extends StatelessWidget {
  const _ClearSection();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final m = context.read<LibraryModel>();
    final cs = Theme.of(context).colorScheme;
    final kinds = {
      ClearKind.history: (l.clearHistory, l.clearHistoryWarn),
      ClearKind.favorites: (l.clearFavorites, l.clearFavoritesWarn),
      ClearKind.images: (l.clearImages, l.clearImagesWarn),
    };
    return _Section(title: l.settingsClearData, children: [
      for (final e in kinds.entries)
        ListTile(
          key: Key('clear-${e.key.name}'),
          title: Text(e.value.$1, style: TextStyle(color: cs.error)),
          onTap: () async {
            if (await confirm(context, title: e.value.$1, message: e.value.$2, action: l.clearConfirm)) await m.clear(e.key);
          },
        ),
    ]);
  }
}

class _AboutTile extends StatelessWidget {
  const _AboutTile();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return _Section(title: null, children: [
      ListTile(
        key: const Key('about-tile'),
        leading: Icon(Icons.info_outline, color: Theme.of(context).colorScheme.primary),
        title: Text(l.settingsAbout),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AboutScreen())),
      ),
    ]);
  }
}

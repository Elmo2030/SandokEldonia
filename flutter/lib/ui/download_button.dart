import 'package:flutter/material.dart';
import 'package:iptvmac/downloads/download_entry.dart';
import 'package:iptvmac/downloads/downloads_model.dart';
import 'package:iptvmac/l10n/app_localizations.dart';
import 'package:iptvmac/ui/downloads_screen.dart';
import 'package:iptvmac/ui/missing_strings.dart';
import 'package:provider/provider.dart';

/// The download button of a movie or an episode: starts the download, then shows its state (progress ring, check) and opens the
/// Downloads screen when tapped. Nothing is shown when downloads are off.
class DownloadButton extends StatelessWidget {
  const DownloadButton({super.key, required this.entryKey, required this.start, this.tonal = false});

  /// `DownloadEntry.keyOf(...)` of the movie or episode.
  final String entryKey;
  final Future<AddResult> Function(DownloadsModel) start;

  /// A filled tonal button (details sheet) instead of a plain icon (episode row).
  final bool tonal;

  @override
  Widget build(BuildContext context) {
    final d = context.watch<DownloadsModel>();
    if (!d.enabled) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final e = d.find(entryKey);
    final idle = e == null || e.status == DownloadStatus.failed || e.status == DownloadStatus.canceled || e.missing;
    final Widget icon;
    final String tip;
    if (idle) {
      icon = const Icon(Icons.download_outlined);
      tip = l.downloadsAdd;
    } else if (e.status == DownloadStatus.done) {
      icon = const Icon(Icons.download_done);
      tip = l.downloadsDone;
    } else if (e.status == DownloadStatus.paused) {
      icon = const Icon(Icons.pause_circle_outline);
      tip = l.downloadsTitle;
    } else {
      icon = SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, value: e.fraction > 0 ? e.fraction : null));
      tip = e.status == DownloadStatus.queued ? l.downloadsQueued : l.downloadsTitle;
    }
    void onPressed() async {
      if (!idle) {
        Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const DownloadsScreen()));
        return;
      }
      final messenger = ScaffoldMessenger.of(context);
      final r = await start(d);
      if (r == AddResult.noUrl || r == AddResult.refused) messenger.showSnackBar(SnackBar(content: Text(Missing.downloadsCannotStart)));
    }

    return tonal ? IconButton.filledTonal(icon: icon, tooltip: tip, onPressed: onPressed) : IconButton(icon: icon, tooltip: tip, onPressed: onPressed);
  }
}

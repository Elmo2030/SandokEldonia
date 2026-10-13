import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'player_model.dart';
import 'seek_bar_math.dart';

/// Elapsed time, the bar, the time left. Always left-to-right, also in Hebrew and Arabic (Apple's rule for timelines).
/// A live stream has no timeline: it shows the "Live" badge instead.
class PlayerSeekRow extends StatelessWidget {
  const PlayerSeekRow({super.key, required this.model});
  final PlayerModel model;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    const mono = TextStyle(color: Colors.white, fontSize: 14, fontFeatures: [FontFeature.tabularFigures()]);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: model.isLive
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Text(l.playerLive, style: mono.copyWith(fontWeight: FontWeight.w600)),
              ]),
            )
          : Row(children: [
              SizedBox(width: 52, child: Text(SeekBarMath.format(model.dragScrub?.time ?? model.core.position), style: mono)),
              Expanded(child: _Bar(model: model)),
              SizedBox(
                width: 56,
                child: Text('−${SeekBarMath.format(model.core.duration - (model.dragScrub?.time ?? model.core.position))}', textAlign: TextAlign.end, style: mono),
              ),
            ]),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.model});
  final PlayerModel model;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final duration = model.core.duration;
    final shown = model.dragScrub?.time ?? model.core.position;
    final fraction = SeekBarMath.fractionOf(shown, duration);
    final dragging = model.scrubbing;
    return Semantics(
      label: l.playerSeekBar,
      value: l.playerSeekValue(SeekBarMath.format(model.core.position), SeekBarMath.format(duration)),
      increasedValue: l.playerSeekValue(SeekBarMath.format(model.core.position + model.prefs.seekStep), SeekBarMath.format(duration)),
      decreasedValue: l.playerSeekValue(SeekBarMath.format(model.core.position - model.prefs.seekStep), SeekBarMath.format(duration)),
      onIncrease: () => model.skip(model.prefs.seekStep.toDouble()),
      onDecrease: () => model.skip(-model.prefs.seekStep.toDouble()),
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          double timeAt(double x) => SeekBarMath.time(x, w, duration);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (d) {
              model.scrubBegan();
              model.barScrubChanged(timeAt(d.localPosition.dx));
            },
            onHorizontalDragUpdate: (d) => model.barScrubChanged(timeAt(d.localPosition.dx)),
            onHorizontalDragEnd: (_) => model.scrubEnded(commit: true),
            onHorizontalDragCancel: () => model.scrubEnded(commit: false),
            onTapUp: (d) {
              if (duration > 0) model.seekTo(timeAt(d.localPosition.dx));
            },
            child: SizedBox(
              height: 44,
              child: Stack(alignment: Alignment.centerLeft, children: [
                Container(height: dragging ? 6 : 4, decoration: BoxDecoration(color: Colors.white30, borderRadius: BorderRadius.circular(3))),
                Container(width: w * fraction, height: dragging ? 6 : 4, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(3))),
                Positioned(
                  left: (w * fraction - 7).clamp(0.0, w - 14),
                  child: Container(width: 14, height: 14, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }
}

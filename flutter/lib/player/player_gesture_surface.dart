import 'package:flutter/material.dart';

import 'player_gestures.dart';
import 'player_model.dart';

/// The touch layer over the picture: tap shows/hides the controls, double tap skips, a horizontal drag scrubs, a vertical drag changes
/// brightness (left half) or volume (right half), a long press plays at 2x while held, a pinch steps fit/fill/stretch.
class PlayerGestureSurface extends StatefulWidget {
  const PlayerGestureSurface({super.key, required this.model});
  final PlayerModel model;

  @override
  State<PlayerGestureSurface> createState() => _PlayerGestureSurfaceState();
}

class _PlayerGestureSurfaceState extends State<PlayerGestureSurface> {
  Offset _doubleTapAt = Offset.zero;
  Offset _origin = Offset.zero;
  DragAxis? _axis;
  TouchSide _side = TouchSide.left;
  bool _pinching = false;
  double _scale = 1;
  Offset _delta = Offset.zero;

  PlayerModel get model => widget.model;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, c) {
          final size = c.biggest;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) => model.singleTap(PlayerGestures.side(d.localPosition.dx, size.width)),
            onDoubleTapDown: (d) => _doubleTapAt = d.localPosition,
            onDoubleTap: () => model.doubleTap(PlayerGestures.side(_doubleTapAt.dx, size.width)),
            onLongPressStart: (_) => model.hold(down: true),
            onLongPressEnd: (_) => model.hold(down: false),
            onLongPressCancel: () => model.hold(down: false),
            onScaleStart: (d) {
              _origin = d.localFocalPoint;
              _delta = Offset.zero;
              _axis = null;
              _pinching = d.pointerCount >= 2;
              _scale = 1;
              _side = PlayerGestures.side(_origin.dx, size.width);
            },
            onScaleUpdate: (d) {
              if (d.pointerCount >= 2) _pinching = true;
              if (_pinching) {
                _scale = d.scale;
                return;
              }
              _delta = d.localFocalPoint - _origin;
              if (_axis == null) {
                _axis = PlayerGestures.axis(_delta.dx, _delta.dy);
                if (_axis == DragAxis.horizontal) model.scrubBegan();
                if (_axis == DragAxis.vertical) model.levelBegan(_side);
              }
              if (_axis == DragAxis.horizontal) model.scrubChanged(_delta.dx, size.width);
              if (_axis == DragAxis.vertical) model.levelChanged(_side, _delta.dy, size.height);
            },
            onScaleEnd: (d) {
              if (_pinching) {
                model.pinchEnded(_scale);
              } else if (_axis == DragAxis.horizontal) {
                model.scrubEnded(commit: true);
              } else if (_axis == DragAxis.vertical) {
                model.levelEnded(_side, _delta.dy, d.velocity.pixelsPerSecond.dy);
              }
              _axis = null;
              _pinching = false;
            },
          );
        },
      );
}

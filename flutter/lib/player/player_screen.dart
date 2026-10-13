import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_localized_locales/flutter_localized_locales.dart';

import 'android_player_system.dart';
import 'engine.dart';
import 'media_kit_engine.dart';
import 'play_request.dart';
import 'player_controls.dart';
import 'player_gesture_surface.dart';
import 'player_model.dart';
import 'player_options.dart';
import 'player_prefs.dart';
import 'player_system.dart';
import 'player_widgets.dart';

/// The full-screen player. The shell pushes it with a [PlayRequest] and a [PlayerHost]; it never touches the library itself.
/// [engineFactory], [system], [prefs] and [clock] are for tests and the lab: the defaults are libmpv, the Android system glue and the
/// stored settings. The app needs `MediaKit.ensureInitialized()` in main and the generated localizations in its MaterialApp.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.request, required this.host, this.engineFactory, this.system, this.prefs, this.clock});

  final PlayRequest request;
  final PlayerHost host;
  final PlaybackEngine Function(PlayerPrefs prefs)? engineFactory;
  final PlayerSystem? system;
  final PlayerPrefs? prefs;
  final DateTime Function()? clock;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> with WidgetsBindingObserver {
  PlayerModel? _model;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_starting) return;
    _starting = true;
    _start(MediaQuery.sizeOf(context).shortestSide < 600);
  }

  Future<void> _start(bool phone) async {
    final prefs = widget.prefs ?? await PlayerPrefs.load();
    if (!mounted) return;
    final engine = widget.engineFactory?.call(prefs) ?? MediaKitEngine(subLang: prefs.subLang, audioLang: prefs.audioLang);
    final system = widget.system ?? (Platform.isAndroid ? AndroidPlayerSystem() : PlayerSystem());
    await system.enter(lockLandscape: phone);
    if (!mounted) {
      engine.dispose();
      await system.exit();
      return;
    }
    setState(() => _model = PlayerModel(host: widget.host, request: widget.request, engine: engine, system: system, prefs: prefs, clock: widget.clock ?? DateTime.now));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) _model?.appPaused();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _model?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = _model;
    return Theme(
      data: ThemeData(brightness: Brightness.dark, useMaterial3: true),
      child: Localizations.override(
        context: context,
        delegates: const [LocaleNamesLocalizationsDelegate()],
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) model == null ? widget.host.closePlayer() : model.close();
          },
          child: Material(
            color: Colors.black,
            child: model == null ? const SizedBox.expand() : ListenableBuilder(listenable: model, builder: (_, _) => _PlayerView(model: model)),
          ),
        ),
      ),
    );
  }
}

class _PlayerView extends StatelessWidget {
  const _PlayerView({required this.model});
  final PlayerModel model;

  static const _scrim = BoxDecoration(
    gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x99000000), Color(0x40000000), Color(0x99000000)]),
  );

  @override
  Widget build(BuildContext context) {
    final failed = model.core.failed;
    final visible = model.controlsVisible;
    final transport = visible && !failed;
    final pip = model.pipActive;
    final fit = switch (model.videoScale) {
      VideoScale.fit => BoxFit.contain,
      VideoScale.fill => BoxFit.cover,
      VideoScale.stretch => BoxFit.fill,
    };
    return Stack(fit: StackFit.expand, children: [
      model.core.engine.buildVideo(fit),
      PlayerGestureSurface(model: model),
      IgnorePointer(child: AnimatedOpacity(opacity: visible ? 1 : 0, duration: const Duration(milliseconds: 200), child: const DecoratedBox(decoration: _scrim))),
      if (!pip)
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: IgnorePointer(
              ignoring: !visible,
              child: AnimatedOpacity(
                opacity: visible ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: Column(children: [
                  PlayerTopBar(model: model),
                  Expanded(child: transport && !model.upNext.isCounting ? Center(child: PlayerTransport(model: model)) : const SizedBox.shrink()),
                  if (transport && !model.upNext.isCounting) PlayerBottomPanel(model: model),
                ]),
              ),
            ),
          ),
        ),
      if (!pip) PlayerHud(model: model),
      if (!visible && model.core.buffering && !model.core.paused) const Center(child: CircularProgressIndicator(color: Colors.white)),
      if (!pip && failed) PlayerErrorCard(model: model),
      if (!pip && model.upNext.isCounting) UpNextCard(model: model),
    ]);
  }
}

import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';

import 'missing_strings.dart';
import 'player_system.dart';
import 'system_policy.dart';

/// The notification, lock-screen and headset buttons ([PlayerAudioHandler], through audio_service, which also runs the foreground
/// service that keeps the sound going with the screen off) and audio focus (audio_session: a call pauses, headphones unplugged pause).
class PlayerMediaSession {
  static PlayerAudioHandler? _handler; // audio_service can be initialised once per process

  final _policy = InterruptionPolicy();
  final _throttle = NowPlayingThrottle();
  PlayerCommands? _commands;
  AudioSession? _session;
  final _subs = <StreamSubscription<Object?>>[];

  Future<void> activate(PlayerCommands commands) async {
    _commands = commands;
    _handler ??= await AudioService.init(
      builder: PlayerAudioHandler.new,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'io.github.goelir.iptvmac.playback',
        androidNotificationChannelName: MissingStrings.playbackChannel,
        androidNotificationOngoing: false,
      ),
    );
    _handler!.attach(commands);
    final session = _session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration(
      androidAudioAttributes: AndroidAudioAttributes(contentType: AndroidAudioContentType.movie, usage: AndroidAudioUsage.media),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
      androidWillPauseWhenDucked: true,
    ));
    await session.setActive(true);
    _subs
      ..add(session.interruptionEventStream.listen(_interruption))
      ..add(session.becomingNoisyEventStream.listen((_) => _commands?.pause()));
  }

  void _interruption(AudioInterruptionEvent e) {
    final c = _commands;
    if (c == null) return;
    // With androidWillPauseWhenDucked every loss of focus arrives as "pause"; a permanent loss ("unknown") never resumes.
    final event = e.begin ? const InterruptionBegan() : InterruptionEnded(shouldResume: e.type == AudioInterruptionType.pause);
    switch (_policy.handle(event, isPlaying: c.isPlaying())) {
      case InterruptionAction.pause:
        c.pause();
      case InterruptionAction.resume:
        c.play();
      case InterruptionAction.none:
    }
  }

  void userChose() => _policy.userChose();

  void update(NowPlaying n) {
    if (_throttle.shouldPublish(n, DateTime.now())) _handler?.publish(n);
  }

  Future<void> deactivate() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    _commands = null;
    _throttle.reset();
    await _handler?.detach();
    await _session?.setActive(false);
  }
}

class PlayerAudioHandler extends BaseAudioHandler {
  PlayerCommands? _c;

  void attach(PlayerCommands c) => _c = c;

  /// The session ends (notification gone, service stopped) without closing the player.
  Future<void> detach() async {
    _c = null;
    await super.stop();
  }

  void publish(NowPlaying n) {
    // The id is not the stream URL: it can carry the provider's password, and the media session is visible to other apps.
    mediaItem.add(MediaItem(
      id: 'iptvmac-now-playing',
      title: n.title,
      artist: n.subtitle,
      duration: !n.isLive && n.duration > 0 ? Duration(milliseconds: (n.duration * 1000).round()) : null,
      isLive: n.isLive,
    ));
    playbackState.add(PlaybackState(
      controls: n.isLive
          ? [
              if (n.canPrevious) MediaControl.skipToPrevious,
              n.paused ? MediaControl.play : MediaControl.pause,
              if (n.canNext) MediaControl.skipToNext,
              MediaControl.stop,
            ]
          : [
              MediaControl.rewind,
              n.paused ? MediaControl.play : MediaControl.pause,
              MediaControl.fastForward,
              if (n.canNext) MediaControl.skipToNext,
            ],
      systemActions: {if (!n.isLive) MediaAction.seek},
      androidCompactActionIndices: n.isLive ? const [0, 1] : const [0, 1, 2],
      processingState: n.buffering ? AudioProcessingState.buffering : AudioProcessingState.ready,
      playing: !n.paused,
      updatePosition: Duration(milliseconds: (n.position * 1000).round()),
      speed: n.speed,
    ));
  }

  @override
  Future<void> play() async => _c?.play();
  @override
  Future<void> pause() async => _c?.pause();
  @override
  Future<void> stop() async => _c?.stop();
  @override
  Future<void> seek(Duration position) async => _c?.seek(position.inMilliseconds / 1000);
  @override
  Future<void> fastForward() async => _c?.skip((_c?.seekStep ?? 10).toDouble());
  @override
  Future<void> rewind() async => _c?.skip(-(_c?.seekStep ?? 10).toDouble());
  @override
  Future<void> skipToNext() async => _c?.next();
  @override
  Future<void> skipToPrevious() async => _c?.previous();
}

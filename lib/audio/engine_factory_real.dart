import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import '../data/models.dart';
import '../data/stream_resolver.dart';
import 'audio_engine.dart';
import 'just_audio_backend.dart';

/// Builds the production engine: one just_audio [AudioPlayer] driven by
/// the [AudioEngine] through [JustAudioBackend], plus an audio_service
/// handler around the same player so playback survives backgrounding
/// and answers the lock screen / notification controls. If the
/// background-audio service cannot start (unsupported platform, …) the
/// engine still works in-app; only the system controls are missing.
Future<AudioEngine> createPlaybackEngine(StreamResolver? resolver) async {
  final player = AudioPlayer();
  final cacheDir = await _audioCacheDir();
  final engine = AudioEngine(
    backend: JustAudioBackend(player, cacheDir: cacheDir),
    resolver: resolver,
  );

  try {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
  } catch (_) {
    // Audio focus niceties are optional; playback itself does not care.
  }

  try {
    await AudioService.init(
      builder: () => _EasyMusicAudioHandler(engine: engine, player: player),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'club.easymusic.easymusic.audio',
        androidNotificationChannelName: 'easyMusic 播放',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
      ),
    );
  } catch (_) {
    // No background service on this platform/session — in-app playback
    // through the engine is unaffected.
  }
  return engine;
}

Future<Directory?> _audioCacheDir() async {
  try {
    final base = await getApplicationCacheDirectory();
    final dir = Directory('${base.path}/audio_cache');
    await dir.create(recursive: true);
    return dir;
  } catch (_) {
    return null; // stream without caching
  }
}

/// Mirrors the engine into the OS: media controls call back into the
/// engine (so notification buttons follow the same queue rules —
/// unavailable skipping, failure fuse), and the engine's current track
/// becomes the notification's media item.
class _EasyMusicAudioHandler extends BaseAudioHandler with SeekHandler {
  _EasyMusicAudioHandler({required this.engine, required this.player}) {
    player.playbackEventStream
        .map(_transformEvent)
        .pipe(playbackState)
        .ignore();
    engine.addListener(_pushMediaItem);
    _pushMediaItem();
  }

  final AudioEngine engine;
  final AudioPlayer player;

  PlaybackState _transformEvent(PlaybackEvent event) {
    return PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.stop,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
      },
      androidCompactActionIndices: const [0, 1, 3],
      processingState: switch (event.processingState) {
        ProcessingState.idle => AudioProcessingState.idle,
        ProcessingState.loading => AudioProcessingState.loading,
        ProcessingState.buffering => AudioProcessingState.buffering,
        ProcessingState.ready => AudioProcessingState.ready,
        ProcessingState.completed => AudioProcessingState.completed,
      },
      playing: player.playing,
      updatePosition: player.position,
      bufferedPosition: player.bufferedPosition,
      speed: player.speed,
      queueIndex: engine.currentQueueIndex >= 0
          ? engine.currentQueueIndex
          : null,
    );
  }

  void _pushMediaItem() {
    final track = engine.currentTrack;
    mediaItem.add(track == null ? null : _toMediaItem(track));
    queue.add(engine.queue.map(_toMediaItem).toList());
  }

  MediaItem _toMediaItem(Track track) {
    final art = track.album.imageUrl;
    return MediaItem(
      id: track.id,
      title: track.name,
      artist: track.artistLine,
      album: track.album.name,
      duration: track.durationMs > 0
          ? Duration(milliseconds: track.durationMs)
          : null,
      artUri: art.startsWith('http') ? Uri.tryParse(art) : null,
      playable: !track.unavailable,
    );
  }

  @override
  Future<void> play() => engine.play();

  @override
  Future<void> pause() => engine.pause();

  @override
  Future<void> seek(Duration position) => engine.seek(position);

  @override
  Future<void> skipToNext() => engine.next();

  @override
  Future<void> skipToPrevious() => engine.previous();

  @override
  Future<void> stop() async {
    await engine.pause();
    await super.stop();
  }
}

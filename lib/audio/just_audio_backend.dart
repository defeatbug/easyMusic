import 'dart:io';

import 'package:just_audio/just_audio.dart';

import 'player_backend.dart';

/// [PlayerBackend] over a just_audio [AudioPlayer]. The player instance
/// is shared with the audio_service handler (see engine_factory_real),
/// which mirrors it into the system notification / lock screen; this
/// class is only the engine's handle on it.
///
/// Caching: when [cacheDir] is given, loads go through just_audio's
/// LockCachingAudioSource — the file downloads while it streams and
/// later plays of the same track read from disk. The cache file is
/// named by the track id (the engine's cacheKey), so a track keeps one
/// entry regardless of how often its signed URL changes.
class JustAudioBackend implements PlayerBackend {
  JustAudioBackend(this.player, {this.cacheDir});

  final AudioPlayer player;

  /// Directory for cached audio files, or null to stream only.
  final Directory? cacheDir;

  @override
  Stream<bool> get playingStream => player.playingStream;

  @override
  Stream<BackendProcessingState> get processingStateStream =>
      player.processingStateStream.map(
        (s) => switch (s) {
          ProcessingState.idle => BackendProcessingState.idle,
          ProcessingState.loading => BackendProcessingState.loading,
          ProcessingState.buffering => BackendProcessingState.buffering,
          ProcessingState.ready => BackendProcessingState.ready,
          ProcessingState.completed => BackendProcessingState.completed,
        },
      );

  @override
  Stream<Duration> get positionStream => player.positionStream;

  @override
  Stream<Duration?> get durationStream => player.durationStream;

  @override
  Future<void> load(
    String url, {
    Map<String, String> headers = const {},
    String? cacheKey,
  }) async {
    final uri = Uri.parse(url);
    final dir = cacheDir;
    final AudioSource source;
    if (dir != null && cacheKey != null && cacheKey.isNotEmpty) {
      // LockCachingAudioSource is just_audio's designated caching
      // source — experimental in name, but the only low-cost way to
      // cache while streaming, and stable across the 0.9/0.10 line.
      // ignore: experimental_member_use
      source = LockCachingAudioSource(
        uri,
        headers: headers.isEmpty ? null : headers,
        cacheFile: File('${dir.path}/${_safeName(cacheKey)}.audio'),
      );
    } else {
      source = AudioSource.uri(
        uri,
        headers: headers.isEmpty ? null : headers,
      );
    }
    await player.setAudioSource(source);
  }

  static String _safeName(String key) =>
      key.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  @override
  Future<void> loadFile(String path) async {
    await player.setAudioSource(AudioSource.uri(Uri.file(path)));
  }

  @override
  Future<void> play() => player.play();

  @override
  Future<void> pause() => player.pause();

  @override
  Future<void> seek(Duration position) => player.seek(position);

  @override
  Future<void> setVolume(double volume) => player.setVolume(volume);

  @override
  Future<void> dispose() => player.dispose();
}

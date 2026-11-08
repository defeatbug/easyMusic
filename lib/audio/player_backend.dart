/// The slice of a media player the audio engine drives. just_audio
/// implements it in production (just_audio_backend.dart); unit tests
/// substitute a fake, so the queue logic never needs a real player,
/// a platform channel, or sound hardware.
enum BackendProcessingState { idle, loading, buffering, ready, completed }

abstract class PlayerBackend {
  Stream<bool> get playingStream;
  Stream<BackendProcessingState> get processingStateStream;
  Stream<Duration> get positionStream;
  Stream<Duration?> get durationStream;

  /// Loads [url] (not yet playing). [cacheKey] names the on-disk cache
  /// entry when the backend caches; backends without a cache ignore it.
  /// Throws when the URL cannot be loaded (unreachable, bad response…).
  Future<void> load(
    String url, {
    Map<String, String> headers = const {},
    String? cacheKey,
  });

  /// Loads a file from local disk (a device song; no resolver, no
  /// cache). Throws when the file cannot be played.
  Future<void> loadFile(String path);

  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);
  Future<void> dispose();
}

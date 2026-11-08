import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../data/models.dart';
import '../data/stream_resolver.dart';
import 'player_backend.dart';

enum LoopMode { off, all, one }

/// What the player bars render: unavailable (no backend wired, e.g.
/// the screenshot build), idle (a queue is presented, nothing loaded),
/// loading/buffering, playing, paused, and error (the failure fuse
/// tripped — see [AudioEngine]).
enum EngineState { unavailable, idle, loading, buffering, playing, paused, error }

/// The playback brain: owns the queue, the play order and the failure
/// policy, and drives a [PlayerBackend] one track at a time — resolve the
/// track's stream through the plugin, load it, play it. Platform audio
/// (just_audio, the lock-screen handler) sits behind the backend and the
/// engine factory; this class is pure Dart and unit-tested with fakes.
///
/// Rules carried over from the desktop app and the task brief:
/// - Queues skip `unavailable` tracks everywhere: presenting, starting,
///   advancing — the play order only ever contains playable indices.
/// - A track whose stream fails to resolve or load is skipped to the
///   next one, but consecutive failures trip a fuse at the playable
///   count, so a dead source stops the engine instead of looping.
class AudioEngine extends ChangeNotifier {
  AudioEngine({
    this._backend,
    this._resolver,
    Random? random,
  }) : _random = random ?? Random() {
    final player = _backend;
    if (player != null) {
      _subs.add(player.playingStream.listen((playing) {
        _backendPlaying = playing;
        _notify();
      }));
      _subs.add(player.processingStateStream.listen((state) {
        _backendProcessing = state;
        if (state == BackendProcessingState.completed) {
          unawaited(_onTrackCompleted());
        }
        _notify();
      }));
    }
  }

  final PlayerBackend? _backend;
  final StreamResolver? _resolver;
  final Random _random;
  final List<StreamSubscription<dynamic>> _subs = [];

  List<Track> _queue = const [];

  /// Indices into [_queue] that can play, in the order they will play.
  /// Sequential play is ascending; shuffle reorders it (current first).
  List<int> _order = const [];
  int _pos = -1;

  bool _shuffle = false;
  LoopMode _repeat = LoopMode.off;
  double _volume = 0.8;

  bool _backendPlaying = false;
  BackendProcessingState _backendProcessing = BackendProcessingState.idle;
  bool _resolving = false;
  bool _hasLoaded = false;
  bool _fuseTripped = false;
  int _consecutiveFailures = 0;
  int _generation = 0;

  String? _lastError;
  final StreamController<String> _errors = StreamController<String>.broadcast();

  // --- state for the UI -------------------------------------------------

  /// True when a player backend is wired (the live app). A resolver is
  /// only needed for online tracks — local files play without one, so
  /// they do not gate here. The screenshot build wires neither and
  /// stays inert.
  bool get canPlay => _backend != null;

  EngineState get state {
    if (!canPlay) return EngineState.unavailable;
    if (_fuseTripped) return EngineState.error;
    if (_resolving ||
        _backendProcessing == BackendProcessingState.loading) {
      return EngineState.loading;
    }
    if (_backendProcessing == BackendProcessingState.buffering) {
      return EngineState.buffering;
    }
    if (_backendPlaying) return EngineState.playing;
    if (_hasLoaded) return EngineState.paused;
    return EngineState.idle;
  }

  bool get isPlaying => state == EngineState.playing;
  bool get isBuffering =>
      state == EngineState.loading || state == EngineState.buffering;

  Track? get currentTrack =>
      (_pos >= 0 && _pos < _order.length) ? _queue[_order[_pos]] : null;

  /// Index into the original queue of the current track (row highlight).
  int get currentQueueIndex =>
      (_pos >= 0 && _pos < _order.length) ? _order[_pos] : -1;

  List<Track> get queue => List.unmodifiable(_queue);
  bool get shuffle => _shuffle;
  LoopMode get repeat => _repeat;
  double get volume => _volume;
  String? get lastError => _lastError;

  /// One-shot playback error messages for transient UI (snackbars).
  Stream<String> get errors => _errors.stream;

  Stream<Duration> get positionStream =>
      _backend?.positionStream ?? const Stream.empty();
  Stream<Duration?> get durationStream =>
      _backend?.durationStream ?? const Stream.empty();

  // --- queue setup ------------------------------------------------------

  List<int> _playableIndices() => [
        for (var i = 0; i < _queue.length; i++)
          if (!_queue[i].unavailable) i,
      ];

  void _rebuildOrder({required bool keepCurrentFirst}) {
    final playable = _playableIndices();
    final current = currentQueueIndex;
    if (_shuffle && playable.length > 1) {
      final rest = [...playable]..shuffle(_random);
      if (keepCurrentFirst && playable.contains(current)) {
        rest
          ..remove(current)
          ..insert(0, current);
        _order = rest;
        _pos = 0;
        return;
      }
      _order = rest;
      _pos = current >= 0 ? _order.indexOf(current) : -1;
      return;
    }
    _order = playable;
    _pos = current >= 0 ? _order.indexOf(current) : -1;
  }

  /// Presents a queue without playing it (the bars' initial song, as the
  /// shell's home data arrives). Ignored once playback has started, so a
  /// home reload never yanks the queue the user is listening to.
  void presentQueue(List<Track> tracks) {
    if (_hasLoaded || _resolving) return;
    _queue = List.of(tracks);
    _fuseTripped = false;
    _consecutiveFailures = 0;
    _rebuildOrder(keepCurrentFirst: false);
    _pos = _order.isEmpty ? -1 : 0;
    _notify();
  }

  /// Starts playback of [tracks] at [startIndex] — the first playable
  /// track at or after it (wrapping to the first playable when the tail
  /// has none), skipping unavailable tracks as everywhere else.
  Future<void> playQueue(List<Track> tracks, int startIndex) async {
    _queue = List.of(tracks);
    _fuseTripped = false;
    _consecutiveFailures = 0;
    _rebuildOrder(keepCurrentFirst: false);
    if (_order.isEmpty) {
      _pos = -1;
      _reportError('没有可播放的歌曲');
      _notify();
      return;
    }
    var pos = _order.indexWhere((qi) => qi >= startIndex);
    if (pos < 0) pos = 0;
    _pos = pos;
    await _loadAndPlay(_order[_pos]);
  }

  /// Plays the queue's track at [queueIndex] (a row tap when the queue
  /// is already the presented one).
  Future<void> playAt(int queueIndex) => playQueue(_queue, queueIndex);

  // --- transport --------------------------------------------------------

  Future<void> play() async {
    if (!canPlay) return;
    if (_hasLoaded && !_fuseTripped) {
      await _backend!.play();
      return;
    }
    final index = currentQueueIndex;
    if (index >= 0) {
      // A fresh attempt after the fuse tripped starts with a clean slate.
      _fuseTripped = false;
      _consecutiveFailures = 0;
      await _loadAndPlay(index);
    }
  }

  Future<void> pause() async {
    if (!canPlay) return;
    await _backend!.pause();
  }

  Future<void> togglePlay() =>
      _backendPlaying || _resolving ? pause() : play();

  Future<void> next() => _step(1);
  Future<void> previous() => _step(-1);

  /// Manual stepping always wraps around the play order; the
  /// repeat-off stop-at-the-end rule applies only to automatic
  /// advancement when a track finishes (see [_onTrackCompleted]).
  Future<void> _step(int delta) async {
    if (!canPlay || _order.isEmpty) return;
    var pos = _pos + delta;
    if (pos >= _order.length) pos = 0;
    if (pos < 0) pos = _order.length - 1;
    _pos = pos;
    _fuseTripped = false;
    await _loadAndPlay(_order[_pos]);
  }

  Future<void> seek(Duration position) async {
    if (!canPlay || !_hasLoaded) return;
    await _backend!.seek(position);
  }

  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    await _backend?.setVolume(_volume);
    _notify();
  }

  void setShuffle(bool enabled) {
    if (_shuffle == enabled) return;
    _shuffle = enabled;
    _rebuildOrder(keepCurrentFirst: true);
    _notify();
  }

  void cycleRepeat() {
    _repeat = LoopMode.values[(_repeat.index + 1) % LoopMode.values.length];
    _notify();
  }

  void setRepeat(LoopMode mode) {
    _repeat = mode;
    _notify();
  }

  // --- the load pipeline --------------------------------------------------

  Future<void> _loadAndPlay(int queueIndex) async {
    final backend = _backend;
    if (backend == null) return;
    final track = _queue[queueIndex];
    // Local tracks play from disk: no resolver is consulted, so the
    // engine can run local queues even with no resolver wired.
    if (!track.isLocal && _resolver == null) return;
    final generation = ++_generation;
    _resolving = true;
    _notify();
    try {
      if (track.isLocal) {
        await backend.loadFile(track.localPath);
      } else {
        final stream = await _resolver!.resolveStream(track);
        if (generation != _generation) return;
        await backend.load(
          stream.url,
          headers: stream.headers,
          cacheKey: track.id,
        );
      }
      if (generation != _generation) return;
      _hasLoaded = true;
      _consecutiveFailures = 0;
      _resolving = false;
      await backend.play();
      _notify();
    } catch (e) {
      if (generation != _generation) return;
      _resolving = false;
      await _onLoadFailure(track, e);
    }
  }

  /// A track that will not resolve or load: report it, count it, and
  /// move to the next playable track — unless the fuse trips: as many
  /// consecutive failures as there are playable tracks means every
  /// remaining candidate already failed once, so stop instead of
  /// cycling forever.
  Future<void> _onLoadFailure(Track track, Object error) async {
    _consecutiveFailures++;
    final detail = _describeError(error);
    final playableCount = _order.length;
    if (_consecutiveFailures >= playableCount || playableCount == 0) {
      _fuseTripped = true;
      _reportError('多首歌曲播放失败，已停止播放（$detail）');
      _notify();
      return;
    }
    _reportError('《${track.name}》播放失败，已跳到下一首（$detail）');
    final nextPos = (_pos + 1) % _order.length;
    _pos = nextPos;
    await _loadAndPlay(_order[_pos]);
  }

  Future<void> _onTrackCompleted() async {
    if (!canPlay || _fuseTripped || _resolving) return;
    final backend = _backend;
    if (_repeat == LoopMode.one && _hasLoaded && backend != null) {
      await backend.seek(Duration.zero);
      await backend.play();
      return;
    }
    if (_pos + 1 < _order.length) {
      _pos++;
      await _loadAndPlay(_order[_pos]);
      return;
    }
    if (_repeat == LoopMode.all && _order.isNotEmpty) {
      _pos = 0;
      await _loadAndPlay(_order[_pos]);
      return;
    }
    // End of the queue, repeat off: stay on the last track, stopped.
    _notify();
  }

  /// One-line digest of a load/resolve failure for the error snackbar:
  /// exception type + message, whitespace collapsed, truncated — enough
  /// for the user to read the real cause off the screen (e.g. a
  /// cleartext or HTTP error) instead of just "playback failed".
  static String _describeError(Object error) {
    final text = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    final summary =
        text.isEmpty ? '${error.runtimeType}' : '${error.runtimeType}: $text';
    return summary.length > 120 ? '${summary.substring(0, 120)}…' : summary;
  }

  void _reportError(String message) {
    _lastError = message;
    if (!_errors.isClosed) _errors.add(message);
  }

  void _notify() {
    if (!isDisposed) notifyListeners();
  }

  bool _disposed = false;
  bool get isDisposed => _disposed;

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    for (final sub in _subs) {
      unawaited(sub.cancel());
    }
    unawaited(_errors.close());
    unawaited(_backend?.dispose() ?? Future.value());
    super.dispose();
  }
}

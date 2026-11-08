import 'dart:async';

import 'package:easymusic/audio/audio_engine.dart';
import 'package:easymusic/audio/player_backend.dart';
import 'package:easymusic/data/models.dart';
import 'package:easymusic/data/stream_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

/// A [PlayerBackend] that records everything and plays nothing: loads
/// can be made to fail per URL, and playback events are emitted by hand.
class FakePlayerBackend implements PlayerBackend {
  final _playing = StreamController<bool>.broadcast();
  final _processing = StreamController<BackendProcessingState>.broadcast();
  final _position = StreamController<Duration>.broadcast();
  final _duration = StreamController<Duration?>.broadcast();

  final List<String> loads = [];
  final List<String> fileLoads = [];
  final Set<String> failingUrls = {};
  final Set<String> failingFiles = {};
  final List<Duration> seeks = [];
  int playCalls = 0;
  int pauseCalls = 0;
  bool playing = false;
  double volume = -1;

  @override
  Stream<bool> get playingStream => _playing.stream;
  @override
  Stream<BackendProcessingState> get processingStateStream =>
      _processing.stream;
  @override
  Stream<Duration> get positionStream => _position.stream;
  @override
  Stream<Duration?> get durationStream => _duration.stream;

  @override
  Future<void> load(
    String url, {
    Map<String, String> headers = const {},
    String? cacheKey,
  }) async {
    loads.add(url);
    if (failingUrls.contains(url)) {
      throw StateError('cannot load $url');
    }
    _processing.add(BackendProcessingState.ready);
  }

  @override
  Future<void> loadFile(String path) async {
    fileLoads.add(path);
    if (failingFiles.contains(path)) {
      throw StateError('cannot load file $path');
    }
    _processing.add(BackendProcessingState.ready);
  }

  @override
  Future<void> play() async {
    playCalls++;
    playing = true;
    _playing.add(true);
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    playing = false;
    _playing.add(false);
  }

  @override
  Future<void> seek(Duration position) async => seeks.add(position);

  @override
  Future<void> setVolume(double v) async => volume = v;

  @override
  Future<void> dispose() async {}

  void emitCompleted() => _processing.add(BackendProcessingState.completed);
}

/// A [StreamResolver] mapping track id → a fake URL, failing on demand.
class FakeStreamResolver implements StreamResolver {
  FakeStreamResolver({this.failingIds = const {}});

  final Set<String> failingIds;
  final List<String> resolvedIds = [];

  @override
  Future<ResolvedStream> resolveStream(Track track) async {
    resolvedIds.add(track.id);
    if (failingIds.contains(track.id)) {
      throw StateError('no stream for ${track.id}');
    }
    return ResolvedStream(url: 'https://example.com/${track.id}.mp3');
  }
}

Track t(String id, {bool unavailable = false}) => Track(
      id: id,
      name: 'Song $id',
      durationMs: 60000,
      unavailable: unavailable,
    );

String url(String id) => 'https://example.com/$id.mp3';

void main() {
  group('AudioEngine queue logic', () {
    late FakePlayerBackend backend;
    late AudioEngine engine;

    AudioEngine buildEngine({StreamResolver? resolver}) {
      backend = FakePlayerBackend();
      return AudioEngine(
        backend: backend,
        resolver: resolver ?? FakeStreamResolver(),
      );
    }

    tearDown(() => engine.dispose());

    test('presentQueue shows the first playable track, loads nothing',
        () async {
      engine = buildEngine();
      engine.presentQueue([t('a', unavailable: true), t('b'), t('c')]);
      expect(engine.currentTrack?.id, 'b');
      expect(engine.currentQueueIndex, 1);
      expect(backend.loads, isEmpty);
      expect(engine.state, EngineState.idle);
    });

    test('playQueue starts at the tapped track', () async {
      final resolver = FakeStreamResolver();
      engine = buildEngine(resolver: resolver);
      await engine.playQueue([t('a'), t('b'), t('c')], 1);
      expect(resolver.resolvedIds, ['b']);
      expect(backend.loads, [url('b')]);
      expect(engine.currentTrack?.id, 'b');
      await pumpEventQueue();
      expect(engine.isPlaying, isTrue);
    });

    test('playQueue from an unavailable index starts at the next playable',
        () async {
      engine = buildEngine();
      await engine.playQueue([t('a', unavailable: true), t('b')], 0);
      expect(backend.loads, [url('b')]);
      expect(engine.currentTrack?.id, 'b');
    });

    test('next and previous wrap around the queue', () async {
      engine = buildEngine();
      await engine.playQueue([t('a'), t('b'), t('c')], 0);
      await engine.next();
      expect(engine.currentTrack?.id, 'b');
      await engine.next();
      expect(engine.currentTrack?.id, 'c');
      await engine.next();
      expect(engine.currentTrack?.id, 'a');
      await engine.previous();
      expect(engine.currentTrack?.id, 'c');
      expect(backend.loads, [url('a'), url('b'), url('c'), url('a'), url('c')]);
    });

    test('next never lands on an unavailable track', () async {
      engine = buildEngine();
      await engine.playQueue(
          [t('a'), t('x', unavailable: true), t('b')], 0);
      await engine.next();
      expect(engine.currentTrack?.id, 'b');
      await engine.next();
      expect(engine.currentTrack?.id, 'a');
    });

    test('track completion advances; repeat off stops at the end', () async {
      engine = buildEngine();
      await engine.playQueue([t('a'), t('b')], 0);
      backend.emitCompleted();
      await pumpEventQueue();
      expect(engine.currentTrack?.id, 'b');
      expect(backend.loads, [url('a'), url('b')]);
      backend.emitCompleted();
      await pumpEventQueue();
      // End of queue: no further load, stays on the last track.
      expect(backend.loads, [url('a'), url('b')]);
      expect(engine.currentTrack?.id, 'b');
    });

    test('repeat all wraps to the first track on completion', () async {
      engine = buildEngine();
      engine.setRepeat(LoopMode.all);
      await engine.playQueue([t('a'), t('b')], 1);
      backend.emitCompleted();
      await pumpEventQueue();
      expect(engine.currentTrack?.id, 'a');
      expect(backend.loads, [url('b'), url('a')]);
    });

    test('repeat one replays the same track without reloading', () async {
      engine = buildEngine();
      engine.setRepeat(LoopMode.one);
      await engine.playQueue([t('a'), t('b')], 0);
      final playsBefore = backend.playCalls;
      backend.emitCompleted();
      await pumpEventQueue();
      expect(backend.loads, [url('a')]);
      expect(backend.seeks, [Duration.zero]);
      expect(backend.playCalls, playsBefore + 1);
      expect(engine.currentTrack?.id, 'a');
    });

    test('cycleRepeat walks off → all → one → off', () {
      engine = buildEngine();
      expect(engine.repeat, LoopMode.off);
      engine.cycleRepeat();
      expect(engine.repeat, LoopMode.all);
      engine.cycleRepeat();
      expect(engine.repeat, LoopMode.one);
      engine.cycleRepeat();
      expect(engine.repeat, LoopMode.off);
    });

    test('shuffle traversal visits each playable track exactly once',
        () async {
      engine = buildEngine();
      engine.setShuffle(true);
      final tracks = [
        t('a'),
        t('b'),
        t('x', unavailable: true),
        t('c'),
        t('d'),
      ];
      await engine.playQueue(tracks, 0);
      final visited = <String>{engine.currentTrack!.id};
      for (var i = 0; i < 3; i++) {
        await engine.next();
        visited.add(engine.currentTrack!.id);
      }
      expect(visited, {'a', 'b', 'c', 'd'});
      await engine.next();
      expect(engine.currentTrack?.id, visited.first);
    });

    test('a track whose stream fails to resolve is skipped', () async {
      final resolver = FakeStreamResolver(failingIds: {'b'});
      engine = buildEngine(resolver: resolver);
      await engine.playQueue([t('a'), t('b'), t('c')], 1);
      expect(engine.currentTrack?.id, 'c');
      expect(backend.loads, [url('c')]);
      expect(engine.lastError, contains('播放失败'));
      // The snackbar text carries the underlying cause for diagnosis.
      expect(engine.lastError, contains('StateError'));
      expect(engine.lastError, contains('no stream for b'));
      await pumpEventQueue();
      expect(engine.isPlaying, isTrue);
    });

    test('a track that fails to load is skipped the same way', () async {
      engine = buildEngine();
      backend.failingUrls.add(url('b'));
      await engine.playQueue([t('a'), t('b'), t('c')], 1);
      expect(engine.currentTrack?.id, 'c');
      expect(backend.loads, [url('b'), url('c')]);
    });

    test('consecutive failures trip the fuse instead of looping', () async {
      final resolver = FakeStreamResolver(failingIds: {'a', 'b'});
      engine = buildEngine(resolver: resolver);
      await engine.playQueue([t('a'), t('b')], 0);
      // Each playable track was tried exactly once, then the engine
      // stopped with an error state.
      expect(resolver.resolvedIds, ['a', 'b']);
      expect(backend.loads, isEmpty);
      expect(engine.state, EngineState.error);
      expect(engine.lastError, contains('已停止'));
      expect(engine.lastError, contains('StateError'));
    });

    test('togglePlay pauses and resumes without reloading', () async {
      engine = buildEngine();
      await engine.playQueue([t('a'), t('b')], 0);
      await engine.togglePlay();
      expect(backend.pauseCalls, 1);
      await engine.togglePlay();
      expect(backend.playCalls, 2);
      expect(backend.loads, [url('a')]);
    });

    test('seek and volume pass through to the backend', () async {
      engine = buildEngine();
      await engine.playQueue([t('a')], 0);
      await engine.seek(const Duration(seconds: 30));
      expect(backend.seeks, [const Duration(seconds: 30)]);
      await engine.setVolume(1.4);
      expect(engine.volume, 1.0);
      expect(backend.volume, 1.0);
    });

    Track local(String path) => Track(
          id: 'local:$path',
          name: 'Local $path',
          durationMs: 60000,
          localPath: path,
        );

    test('a local track loads from disk and never touches the resolver',
        () async {
      final resolver = FakeStreamResolver();
      engine = buildEngine(resolver: resolver);
      await engine
          .playQueue([t('a'), local('/music/b.mp3'), t('c')], 1);
      expect(backend.fileLoads, ['/music/b.mp3']);
      expect(backend.loads, isEmpty);
      expect(resolver.resolvedIds, isEmpty);
      expect(engine.currentTrack?.localPath, '/music/b.mp3');
    });

    test('a failing local file is skipped like a failing stream',
        () async {
      engine = buildEngine();
      backend.failingFiles.add('/music/bad.mp3');
      await engine
          .playQueue([local('/music/bad.mp3'), t('c')], 0);
      expect(engine.currentTrack?.id, 'c');
      expect(backend.loads, [url('c')]);
    });

    test('a local queue plays with a backend but no resolver', () async {
      backend = FakePlayerBackend();
      engine = AudioEngine(backend: backend);
      await engine.playQueue([local('/music/a.mp3')], 0);
      expect(backend.fileLoads, ['/music/a.mp3']);
      await pumpEventQueue();
      expect(engine.isPlaying, isTrue);
    });

    test('an engine with no backend or resolver stays inert', () async {
      engine = AudioEngine();
      expect(engine.canPlay, isFalse);
      await engine.playQueue([t('a'), t('b')], 0);
      expect(engine.currentTrack?.id, 'a');
      expect(engine.state, EngineState.unavailable);
    });
  });
}

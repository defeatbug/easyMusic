import '../data/stream_resolver.dart';
import 'audio_engine.dart';

/// Web stand-in: an engine with no backend, so every transport call is
/// a no-op and the bars present the queue without playing — exactly
/// what the screenshot build needs. (just_audio itself would compile
/// for the web, but QuickJS cannot resolve streams there anyway.)
Future<AudioEngine> createPlaybackEngine(StreamResolver? resolver) async =>
    AudioEngine(resolver: resolver);

// Playback wiring by platform, following the plugin_host.dart pattern:
// the real factory (just_audio + audio_service) where dart:io exists,
// an inert engine on the web — whose builds never play (the screenshot
// build replays captured data; see main_shot.dart).
export 'engine_factory_stub.dart'
    if (dart.library.io) 'engine_factory_real.dart';

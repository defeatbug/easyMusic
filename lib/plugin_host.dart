// The plugin host, by platform: the real QuickJS host where dart:ffi
// exists, a throwing stub on the web (whose builds replay captured data
// instead — see main_shot.dart).
export 'plugin_host_stub.dart' if (dart.library.io) 'plugin_host_real.dart';

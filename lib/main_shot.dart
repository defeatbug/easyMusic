import 'package:flutter/material.dart';

import 'data/capture_home_repository.dart';
import 'main.dart';

/// Screenshot entry point (`flutter build web --target=lib/main_shot.dart`):
/// identical UI to the real app, but the home data replays the capture in
/// assets/capture/ — recorded from a live plugin run by
/// test/capture_home_test.dart — because QuickJS cannot run in a web build
/// and a headless browser cannot reach the cover CDN. Never shipped.
void main() {
  runApp(EasyMusicApp(repository: CaptureHomeRepository()));
}

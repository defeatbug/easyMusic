import 'package:flutter/material.dart';

import 'audio/audio_engine.dart';
import 'audio/engine_factory.dart';
import 'data/home_repository.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

/// The app shell, wired by entry point: main.dart passes the live plugin
/// repository and a real playback engine; main_shot.dart passes a capture
/// replay and no engine (the shell substitutes an inert one, so the
/// screenshot build's bars present without playing, as before).
class EasyMusicApp extends StatelessWidget {
  const EasyMusicApp({super.key, required this.repository, this.engine});

  final HomeRepository repository;
  final AudioEngine? engine;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'easyMusic',
      debugShowCheckedModeBanner: false,
      theme: appTheme(),
      home: AppShell(repository: repository, engine: engine),
    );
  }
}

/// Real entry point: live plugin data through QuickJS, playback through
/// the audio engine (just_audio + audio_service, see engine_factory).
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repository = PluginHomeRepository();
  final engine = await createPlaybackEngine(repository);
  runApp(EasyMusicApp(repository: repository, engine: engine));
}

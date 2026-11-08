import 'dart:async';
import 'dart:io';

import 'plugin/sign_in.dart';

/// Web stand-in for the QuickJS plugin host: QuickJS runs through dart:ffi,
/// which does not exist on the web, so this file only satisfies the
/// compiler with the host's public API. Every operation throws — the web
/// build is used with captured data (see main_shot.dart); on IO platforms
/// plugin_host.dart exports plugin_host_real.dart instead.
UnsupportedError _noWeb() =>
    UnsupportedError('插件运行时（QuickJS）不支持 Web 平台');

bool isHostAllowed(String host, Set<String> allowlist) => false;

class PluginHost {
  PluginHost({this.onLog, File? storageFile});

  final void Function(String line)? onLog;

  Set<String> networkAllowlist = <String>{};
  void Function(SignInPromptData prompt)? onSignInPrompt;
  Future<String> Function(WebSignInRequest request)? webSignInHandler;

  final Map<String, dynamic> storage = <String, dynamic>{};

  Future<void> init({
    required String bootstrapSource,
    Map<String, dynamic> settings = const <String, dynamic>{},
    String platform = 'android',
    String arch = 'arm64',
  }) async =>
      throw _noWeb();

  void loadPlugin(String source) => throw _noWeb();

  List<String> get pluginExports => const <String>[];

  Future<Map<String, dynamic>> call(
    String name,
    Map<String, dynamic> args, {
    Duration timeout = const Duration(seconds: 60),
  }) async =>
      throw _noWeb();

  Future<Map<String, dynamic>> probeAudio(
          String url, Map<String, String> headers) async =>
      throw _noWeb();

  String evalString(String code) => throw _noWeb();

  void cancelPendingCall([String error = '操作已取消']) {}

  void dispose() {}
}

/// See plugin_host_real.dart; never called on the web.
HttpClient createHostHttpClient() => throw _noWeb();

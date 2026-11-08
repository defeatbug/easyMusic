import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_js/flutter_js.dart';

/// Minimal MyGo Music plugin host on top of QuickJS (flutter_js).
///
/// The Dart side only provides the async bridges that cannot be synchronous
/// in JS: HTTP (`fetch` channel) and timers (`timer` channel). Everything the
/// desktop host exposes synchronously (host.storage, host.crypto, host.setting)
/// is implemented in assets/bootstrap.js.
class PluginHost {
  PluginHost({this.onLog});

  final void Function(String line)? onLog;

  late final JavascriptRuntime _runtime;
  bool _initialized = false;
  final Map<String, dynamic> storage = <String, dynamic>{};
  Completer<Map<String, dynamic>>? _pendingCall;
  HttpClient? _httpClient;

  void _log(String line) {
    // ignore: avoid_print
    print(line);
    onLog?.call(line);
  }

  HttpClient _client() {
    if (_httpClient != null) return _httpClient!;
    SecurityContext? context;
    // Trust the OS bundle in addition to Dart's bundled roots: this sandbox
    // egress proxy MITMs TLS with a CA that lives in the system bundle.
    final bundle = File('/etc/ssl/certs/ca-certificates.crt');
    if (bundle.existsSync()) {
      try {
        context = SecurityContext(withTrustedRoots: true)
          ..setTrustedCertificatesBytes(bundle.readAsBytesSync());
      } catch (_) {
        context = null;
      }
    }
    final client = HttpClient(context: context);
    final proxyEnv = Platform.environment['https_proxy'] ??
        Platform.environment['HTTPS_PROXY'] ??
        Platform.environment['http_proxy'];
    if (proxyEnv != null && proxyEnv.isNotEmpty) {
      final proxy = Uri.parse(proxyEnv);
      if (proxy.host.isNotEmpty && proxy.port != 0) {
        client.findProxy = (_) => 'PROXY ${proxy.host}:${proxy.port}';
        if (proxy.userInfo.isNotEmpty) {
          final parts = proxy.userInfo.split(':');
          client.addProxyCredentials(
            proxy.host,
            proxy.port,
            '',
            HttpClientBasicCredentials(
              Uri.decodeComponent(parts.first),
              Uri.decodeComponent(parts.sublist(1).join(':')),
            ),
          );
        }
      }
    }
    client.connectionTimeout = const Duration(seconds: 25);
    _httpClient = client;
    return client;
  }

  /// flutter_js hands message payloads to Dart already JSON-decoded when
  /// they look like JSON, so handlers accept either a raw string or a Map.
  static Map<String, dynamic> _asMap(dynamic args) {
    if (args is Map<String, dynamic>) return args;
    if (args is Map) return args.cast<String, dynamic>();
    return jsonDecode(args as String) as Map<String, dynamic>;
  }

  Future<String> _handleFetch(dynamic args) async {
    try {
      final req = _asMap(args);
      final uri = Uri.parse(req['url'] as String);
      final request =
          await _client().openUrl(req['method'] as String? ?? 'GET', uri);
      final reqHeaders = (req['headers'] as Map?) ?? const {};
      reqHeaders.forEach((key, value) {
        if (value != null) request.headers.set('$key', '$value');
      });
      final body = req['body'] as String?;
      if (body != null) request.write(body);
      final response = await request.close();
      final bytes = await response.fold<List<int>>(
          <int>[], (acc, chunk) => acc..addAll(chunk));
      final responseHeaders = <String, List<String>>{};
      response.headers.forEach((name, values) {
        responseHeaders[name.toLowerCase()] = values;
      });
      return jsonEncode(<String, dynamic>{
        'status': response.statusCode,
        'headers': responseHeaders,
        'body': utf8.decode(bytes, allowMalformed: true),
      });
    } catch (e) {
      return jsonEncode(<String, dynamic>{'error': '$e'});
    }
  }

  /// Range-GET verification helper: fetches the first bytes of [url] and
  /// reports status, content type and the first bytes as hex.
  Future<Map<String, dynamic>> probeAudio(String url, Map<String, String> headers) async {
    final uri = Uri.parse(url);
    final request = await _client().openUrl('GET', uri);
    headers.forEach((k, v) => request.headers.set(k, v));
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-2047');
    final response = await request.close();
    final bytes = await response
        .fold<List<int>>(<int>[], (acc, chunk) => acc..addAll(chunk))
        .timeout(const Duration(seconds: 30), onTimeout: () => <int>[]);
    return <String, dynamic>{
      'status': response.statusCode,
      'contentType': response.headers.contentType?.toString(),
      'contentLength': response.headers.contentLength,
      'bytesRead': bytes.length,
      'headHex': bytes
          .take(16)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(' '),
      'headAscii': String.fromCharCodes(
          bytes.take(16).map((b) => (b >= 32 && b < 127) ? b : 46)),
    };
  }

  /// Boots the runtime: registers bridges, evaluates the config prelude and
  /// the bootstrap script (host object, fetch, timers, crypto).
  Future<void> init({
    required String bootstrapSource,
    Map<String, dynamic> settings = const <String, dynamic>{},
    String platform = 'android',
    String arch = 'arm64',
  }) async {
    // xhr: false — flutter_js's own fetch bridge loads a JS asset through
    // rootBundle (needs a ServicesBinding) and is redundant: bootstrap.js
    // provides fetch on top of our 'fetch' channel instead.
    _runtime = getJavascriptRuntime(xhr: false);
    _initialized = true;
    _runtime.onMessage('log', (dynamic args) {
      try {
        final m = _asMap(args);
        _log('[js:${m['level']}] ${m['msg']}');
      } catch (_) {
        _log('[js] $args');
      }
    });
    _runtime.onMessage('fetch', _handleFetch);
    _runtime.onMessage('timer', (dynamic args) async {
      final ms = int.tryParse('$args') ?? 0;
      await Future<void>.delayed(Duration(milliseconds: ms));
      return 'ok';
    });
    _runtime.onMessage('storageSet', (dynamic args) {
      try {
        final m = _asMap(args);
        storage[m['key'] as String] = m['value'];
      } catch (_) {}
    });
    _runtime.onMessage('storageRemove', (dynamic args) {
      try {
        final m = _asMap(args);
        storage.remove(m['key']);
      } catch (_) {}
    });
    _runtime.onMessage('done', (dynamic args) {
      try {
        final m = _asMap(args);
        _pendingCall?.complete(m);
      } catch (e) {
        _pendingCall?.complete(<String, dynamic>{'ok': false, 'error': '$e'});
      }
    });

    final config = jsonEncode(<String, dynamic>{
      'storage': storage,
      'settings': settings,
      'platform': platform,
      'arch': arch,
      'dir': '',
      'dataDir': '',
    });
    final prelude = _runtime.evaluate('globalThis.__hostConfig = $config;');
    if (prelude.isError) {
      throw StateError('prelude failed: ${prelude.stringResult}');
    }
    final boot = _runtime.evaluate(bootstrapSource);
    if (boot.isError) {
      throw StateError('bootstrap failed: ${boot.stringResult}');
    }
  }

  /// Loads a plugin's JS source. MyGo plugins are ES modules; the desktop
  /// host evaluates them after a bundling step, so here we strip `export`
  /// keywords and collect the known export names onto `globalThis.__plugin`.
  void loadPlugin(String source) {
    final transformed =
        source.replaceAll(RegExp(r'^export\s+', multiLine: true), '');
    const names = <String>[
      'signIn', 'signOut', 'account', 'setSetting', 'home', 'browse', 'search',
      'suggest', 'recent', 'played', 'liked', 'isLiked', 'like', 'likeEpisode',
      'album', 'artist', 'saveAlbum', 'followArtist', 'savePlaylist',
      'subscribeShow', 'savedAlbums', 'playlists', 'playlist', 'createPlaylist',
      'renamePlaylist', 'deletePlaylist', 'addToPlaylist', 'removeFromPlaylist',
      'movePlaylistTrack', 'shows', 'show', 'stations', 'stationNext',
      'comments', 'likeComment', 'postComment', 'lyrics', 'stream',
    ];
    final collector = StringBuffer()
      ..writeln('globalThis.__plugin = {};')
      ..writeln('for (const __n of ${jsonEncode(names)}) {')
      ..writeln(
          '  try { const __v = eval(__n); if (typeof __v === "function") __plugin[__n] = __v; } catch (e) {}')
      ..writeln('}');
    final result = _runtime.evaluate('$transformed\n$collector');
    if (result.isError) {
      throw StateError('plugin load failed: ${result.stringResult}');
    }
  }

  List<String> get pluginExports {
    final result = _runtime.evaluate('Object.keys(__plugin).join(",")');
    if (result.isError) return const <String>[];
    return result.stringResult.split(',').where((s) => s.isNotEmpty).toList();
  }

  /// Calls a plugin export with one JSON-encodable argument object and waits
  /// for the returned promise to settle, pumping the QuickJS job queue while
  /// Dart-side async bridges (fetch/timers) complete.
  Future<Map<String, dynamic>> call(
    String name,
    Map<String, dynamic> args, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    if (_pendingCall != null) {
      throw StateError('another plugin call is in flight');
    }
    final completer = Completer<Map<String, dynamic>>();
    _pendingCall = completer;
    final argJson = jsonEncode(args);
    final script = '''
(async () => {
  try {
    const r = await __plugin[${jsonEncode(name)}]($argJson);
    sendMessage("done", JSON.stringify({ ok: true, result: r === undefined ? null : r }));
  } catch (e) {
    sendMessage("done", JSON.stringify({
      ok: false,
      error: String((e && e.message) || e),
      code: (e && e.code) || null,
      stack: String((e && e.stack) || "")
    }));
  }
})();
''';
    final evaluated = _runtime.evaluate(script);
    if (evaluated.isError) {
      _pendingCall = null;
      throw StateError('call dispatch failed: ${evaluated.stringResult}');
    }
    final stopwatch = Stopwatch()..start();
    try {
      while (!completer.isCompleted) {
        _runtime.executePendingJob();
        await Future<void>.delayed(const Duration(milliseconds: 5));
        if (stopwatch.elapsed > timeout) {
          throw TimeoutException('plugin call "$name" timed out', timeout);
        }
      }
    } finally {
      _pendingCall = null;
    }
    return completer.future;
  }

  /// Synchronous evaluation for self-tests; returns the string result.
  String evalString(String code) {
    final result = _runtime.evaluate(code);
    if (result.isError) {
      throw StateError('eval failed: ${result.stringResult}');
    }
    return result.stringResult;
  }

  void dispose() {
    _httpClient?.close(force: true);
    if (_initialized) _runtime.dispose();
  }
}

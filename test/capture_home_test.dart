import 'dart:convert';
import 'dart:io';

import 'package:easymusic/plugin_host.dart';
import 'package:flutter_test/flutter_test.dart';

/// Capture tool (run manually, not a CI test): boots the real NetEase
/// plugin in QuickJS, calls home() / browse(charts) / playlist() live,
/// downloads the covers the home page will show, and writes
/// assets/capture/home_capture.json (+ assets/capture/covers/*.jpg) for
/// the screenshot build's replay repository.
///
/// Run with:
///   LD_LIBRARY_PATH=$HOME/.pub-cache/hosted/pub.dev/flutter_js-0.8.7/linux/shared \
///     flutter test test/capture_home_test.dart
///
/// Plain test(), no TestWidgetsFlutterBinding: the binding would replace
/// HttpClient with a mock (spike lesson).
void main() {
  test('capture home data + covers from the live plugin', () async {
    final bootstrap = File('assets/bootstrap.js').readAsStringSync();
    final pluginSource = File('assets/plugin/index.js').readAsStringSync();

    final host = PluginHost();
    addTearDown(host.dispose);
    await host.init(bootstrapSource: bootstrap);
    host.loadPlugin(pluginSource);

    Future<Map<String, dynamic>> call(String name, Map<String, dynamic> args) async {
      final res = await host.call(name, args, timeout: const Duration(seconds: 90));
      if (res['ok'] != true) {
        throw StateError('$name failed: ${res['error']}');
      }
      return (res['result'] as Map).cast<String, dynamic>();
    }

    final home = await call('home', const {});
    final chartsPage = await call('browse', const {'page': 'charts'});
    final chartSections = (chartsPage['sections'] as List).cast<Map>();
    final charts = (chartSections.first['playlists'] as List)
        .cast<Map<String, dynamic>>()
        .take(10)
        .toList();

    final hotChart = charts.firstWhere(
      (p) => '${p['name']}'.contains('热歌榜'),
      orElse: () => charts.first,
    );
    final hotPlaylist = await call('playlist', {'id': hotChart['id']});
    final hotTracks = (hotPlaylist['tracks'] as List)
        .cast<Map<String, dynamic>>()
        .take(12)
        .toList();

    // Download covers for everything the home page displays, a few at a
    // time: one-by-one through this sandbox's CONNECT proxy is slow
    // enough to outrun the test timeout.
    final client = createHostHttpClient();
    addTearDown(() => client.close(force: true));
    var coverSeq = 0;
    var downloaded = 0;
    var failed = 0;
    final byUrl = <String, String>{};
    final pending = <String, Future<String>>{};

    Future<String> download(String url) async {
      final name = 'cov${(coverSeq++).toString().padLeft(3, '0')}.jpg';
      final assetPath = 'assets/capture/covers/$name';
      try {
        final sized = url.contains('?') ? url : '$url?param=300y300';
        final req = await client.getUrl(Uri.parse(sized));
        req.headers.set('referer', 'https://music.163.com/');
        final resp = await req.close();
        final bytes =
            await resp.fold<List<int>>(<int>[], (a, c) => a..addAll(c));
        final isJpeg = bytes.length > 2 && bytes[0] == 0xFF && bytes[1] == 0xD8;
        final isPng = bytes.length > 1 && bytes[0] == 0x89 && bytes[1] == 0x50;
        if (resp.statusCode != 200 || (!isJpeg && !isPng)) {
          throw StateError('HTTP ${resp.statusCode}, ${bytes.length} bytes');
        }
        await File(assetPath).writeAsBytes(bytes);
        downloaded++;
        return assetPath;
      } catch (e) {
        failed++;
        // ignore: avoid_print
        print('cover failed for $url: $e');
        return '';
      }
    }

    Future<String> coverFor(String url) {
      if (url.isEmpty) return Future.value('');
      return pending[url] ??= download(url).then((p) => byUrl[url] = p);
    }

    Future<void> coverPlaylists(List<Map<String, dynamic>> items) async {
      // Resolve in small parallel batches, write back in order.
      for (var i = 0; i < items.length; i += 8) {
        final batch = items.skip(i).take(8).toList();
        final paths = await Future.wait(
            batch.map((p) => coverFor('${p['imageUrl'] ?? ''}')));
        for (var j = 0; j < batch.length; j++) {
          batch[j]['coverAsset'] = paths[j];
        }
      }
    }

    for (final s in (home['sections'] as List).cast<Map<String, dynamic>>()) {
      final playlists =
          ((s['playlists'] as List?) ?? const []).cast<Map<String, dynamic>>();
      // The home page shows at most 12 of the recommended playlists.
      await coverPlaylists(playlists.take(12).toList());
    }
    await coverPlaylists(charts);
    hotChart['coverAsset'] =
        charts.firstWhere((p) => p['id'] == hotChart['id'])['coverAsset'];
    final albumCovers = await Future.wait(hotTracks.map((t) =>
        coverFor('${(t['album'] as Map)['imageUrl'] ?? ''}')));
    for (var i = 0; i < hotTracks.length; i++) {
      (hotTracks[i]['album'] as Map)['coverAsset'] = albumCovers[i];
    }

    final capture = <String, dynamic>{
      'ranAt': DateTime.now().toIso8601String(),
      'source': 'live plugin run: home() + browse(charts) + playlist(热歌榜)',
      'home': home,
      'charts': charts,
      'hotChart': hotChart,
      'hotTracks': hotTracks,
    };
    File('assets/capture/home_capture.json')
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(capture));

    // Evidence for the log.
    final recs = ((home['sections'] as List).last['playlists'] as List)
        .cast<Map<String, dynamic>>();
    // ignore: avoid_print
    print('home sections: '
        '${(home['sections'] as List).map((s) => s['title']).join(', ')}');
    // ignore: avoid_print
    print('recommended playlists (${recs.length}): '
        '${recs.take(5).map((p) => p['name']).join(' | ')}');
    // ignore: avoid_print
    print('charts (${charts.length}): '
        '${charts.take(5).map((p) => p['name']).join(' | ')}');
    // ignore: avoid_print
    print('hot tracks (${hotTracks.length}): '
        '${hotTracks.take(5).map((t) => t['name']).join(' | ')}');
    // ignore: avoid_print
    print('covers: $downloaded downloaded, $failed failed');
  }, timeout: const Timeout(Duration(minutes: 10)));
}

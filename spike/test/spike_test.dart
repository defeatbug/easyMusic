import 'dart:convert';
import 'dart:io';

import 'package:easymusic_spike/plugin_host.dart';
import 'package:flutter_test/flutter_test.dart';

String readFirstExisting(List<String> paths) {
  for (final p in paths) {
    final f = File(p);
    if (f.existsSync()) return f.readAsStringSync();
  }
  throw StateError('none of $paths exists (cwd=${Directory.current.path})');
}

void main() {
  // NOTE: no TestWidgetsFlutterBinding here on purpose: the binding installs
  // a mock HttpClient (all requests -> 400), which would defeat the spike.
  // flutter_js talks FFI directly and needs no binding.

  test('M0 spike: netease plugin search + stream under QuickJS', () async {
    final bootstrap = readFirstExisting(
        ['assets/bootstrap.js', '../assets/bootstrap.js']);
    final pluginSource = readFirstExisting(
        ['plugins/netease/index.js', '../plugins/netease/index.js']);

    final host = PluginHost();
    addTearDown(host.dispose);
    await host.init(bootstrapSource: bootstrap);

    // --- 1. crypto vectors (the plugin's EAPI depends on both) -------------
    final md5abc = host.evalString('__testMd5("abc")');
    // ignore: avoid_print
    print('md5("abc") = $md5abc');
    expect(md5abc, '900150983cd24fb0d6963f7d28e17f72');
    final md5empty = host.evalString('__testMd5("")');
    expect(md5empty, 'd41d8cd98f00b204e9800998ecf8427e');
    // Chinese text exercises the UTF-8 encoder used for CJK queries/payloads.
    final md5cn = host.evalString('__testMd5("稻香")');
    // ignore: avoid_print
    print('md5("稻香") = $md5cn');

    final aesBlock = host.evalString(
        '__testAesBlock("000102030405060708090a0b0c0d0e0f", "00112233445566778899aabbccddeeff")');
    // ignore: avoid_print
    print('aes-block FIPS-197 = $aesBlock');
    expect(aesBlock, '69c4e0d86a7b0430d8cdb78070b4c55a');

    // Cross-check ECB+PKCS7 against openssl for the plugin's actual key.
    final proc = await Process.start('openssl', [
      'enc', '-aes-128-ecb', '-K',
      utf8.encode('e82ckenh8dichen8').map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
    ]);
    proc.stdin.write('hello netease');
    await proc.stdin.close();
    final opensslOut = await proc.stdout
        .fold<List<int>>(<int>[], (a, c) => a..addAll(c));
    final opensslHex =
        opensslOut.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final jsEcb = host
        .evalString('__testAesEcb("e82ckenh8dichen8", "hello netease")');
    // ignore: avoid_print
    print('aes-ecb js=$jsEcb openssl=$opensslHex');
    expect(jsEcb, opensslHex);

    // --- 2. load the unmodified plugin --------------------------------------
    host.loadPlugin(pluginSource);
    final exports = host.pluginExports;
    // ignore: avoid_print
    print('plugin exports (${exports.length}): ${exports.join(', ')}');
    expect(exports, containsAll(<String>['search', 'stream', 'lyrics']));

    // --- 3. search ------------------------------------------------------------
    final searchRes = await host.call('search', <String, dynamic>{
      'query': '周杰伦 稻香',
      'kind': 'tracks',
      'offset': 0,
    }, timeout: const Duration(seconds: 90));
    // ignore: avoid_print
    print('search ok=${searchRes['ok']} error=${searchRes['error']}');
    expect(searchRes['ok'], isTrue,
        reason: 'search failed: ${searchRes['error']} ${searchRes['stack']}');
    final result = searchRes['result'] as Map<String, dynamic>;
    final tracks = (result['tracks'] as List).cast<Map<String, dynamic>>();
    // ignore: avoid_print
    print('search returned ${tracks.length} tracks, more=${result['more']}');
    expect(tracks, isNotEmpty);
    final first = tracks.first;
    final artists = (first['artists'] as List)
        .cast<Map<String, dynamic>>()
        .map((a) => a['name'])
        .join('/');
    // ignore: avoid_print
    print('first track: id=${first['id']} name=${first['name']} '
        'artists=$artists duration=${first['duration']}');

    // --- 4. stream URL ---------------------------------------------------------
    final streamRes = await host.call('stream', <String, dynamic>{
      'id': first['id'],
      'quality': 'standard',
    }, timeout: const Duration(seconds: 90));
    // ignore: avoid_print
    print('stream ok=${streamRes['ok']} error=${streamRes['error']}');
    expect(streamRes['ok'], isTrue,
        reason: 'stream failed: ${streamRes['error']} ${streamRes['stack']}');
    final stream = streamRes['result'] as Map<String, dynamic>;
    final url = stream['url'] as String;
    // ignore: avoid_print
    print('stream: type=${stream['type']} quality=${stream['quality']} '
        'br=${stream['bitRate']} size=${stream['size']}');
    // ignore: avoid_print
    print('stream url: $url');
    expect(url, startsWith('http'));

    // --- 5. verify the URL actually serves audio bytes -------------------------
    final probeHeaders = <String, String>{};
    final sh = stream['headers'];
    if (sh is Map) {
      sh.forEach((k, v) => probeHeaders['$k'] = '$v');
    }
    final probe = await host.probeAudio(url, probeHeaders);
    // ignore: avoid_print
    print('probe: ${jsonEncode(probe)}');
    expect(probe['status'], anyOf(200, 206));
    expect(probe['bytesRead'] as int, greaterThan(100));
  }, timeout: const Timeout(Duration(minutes: 5)));
}

import 'dart:convert';
import 'dart:io';

import 'package:easymusic_spike/plugin_host.dart';
import 'package:flutter_test/flutter_test.dart';

String fmtDuration(dynamic ms) {
  final total = ((ms as num?) ?? 0) ~/ 1000;
  final m = total ~/ 60;
  final s = (total % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

/// Captures the real spike measurements into capture.json for the result
/// page screenshot. Data comes from a live run of the unmodified plugin.
void main() {
  test('capture spike results to JSON', () async {
    final bootstrap = File('assets/bootstrap.js').readAsStringSync();
    final pluginSource = File('plugins/netease/index.js').readAsStringSync();
    final capture = <String, dynamic>{
      'ranAt': DateTime.now().toIso8601String(),
      'plugin': 'hubandad/mygo-music-netease v1.0.0 (unmodified)',
      'runtime': 'QuickJS via flutter_js 0.8.7, flutter test (Linux host)',
    };

    final host = PluginHost();
    addTearDown(host.dispose);
    await host.init(bootstrapSource: bootstrap);
    capture['crypto'] = <String, dynamic>{
      'md5Abc': host.evalString('__testMd5("abc")'),
      'aesBlockFips197': host.evalString(
          '__testAesBlock("000102030405060708090a0b0c0d0e0f", "00112233445566778899aabbccddeeff")'),
    };
    host.loadPlugin(pluginSource);
    capture['exports'] = host.pluginExports;

    final query = '周杰伦 稻香';
    capture['query'] = query;
    final search = await host.call('search', <String, dynamic>{
      'query': query,
      'kind': 'tracks',
      'offset': 0,
    }, timeout: const Duration(seconds: 90));
    capture['searchOk'] = search['ok'];
    if (search['ok'] != true) {
      capture['error'] = '${search['error']}';
      File('capture.json').writeAsStringSync(jsonEncode(capture));
      return;
    }
    final result = search['result'] as Map<String, dynamic>;
    final tracks = (result['tracks'] as List).cast<Map<String, dynamic>>();
    capture['totalReturned'] = tracks.length;
    capture['more'] = result['more'];
    capture['tracks'] = tracks.take(10).map((t) {
      final artists = (t['artists'] as List)
          .cast<Map<String, dynamic>>()
          .map((a) => a['name'])
          .join(' / ');
      final album = (t['album'] as Map?)?.cast<String, dynamic>();
      return <String, dynamic>{
        'id': t['id'],
        'name': t['name'],
        'artists': artists,
        'album': album?['name'] ?? '',
        'duration': fmtDuration(t['duration']),
        'unavailable': t['unavailable'] ?? false,
      };
    }).toList();

    final first = tracks.first;
    final streamRes = await host.call('stream', <String, dynamic>{
      'id': first['id'],
      'quality': 'standard',
    }, timeout: const Duration(seconds: 90));
    capture['streamOk'] = streamRes['ok'];
    if (streamRes['ok'] == true) {
      final stream = streamRes['result'] as Map<String, dynamic>;
      final url = stream['url'] as String;
      capture['stream'] = <String, dynamic>{
        'forTrack': first['name'],
        'forId': first['id'],
        'type': stream['type'],
        'quality': stream['quality'],
        'bitRate': stream['bitRate'],
        'size': stream['size'],
        'url': url,
        'host': Uri.parse(url).host,
      };
      final probeHeaders = <String, String>{};
      final sh = stream['headers'];
      if (sh is Map) sh.forEach((k, v) => probeHeaders['$k'] = '$v');
      final probe = await host.probeAudio(url, probeHeaders);
      (capture['stream'] as Map<String, dynamic>)['probe'] = probe;
    } else {
      capture['streamError'] = '${streamRes['error']}';
    }

    File('capture.json').writeAsStringSync(jsonEncode(capture));
    // ignore: avoid_print
    print('capture written: ${jsonEncode(capture)}');
  }, timeout: const Timeout(Duration(minutes: 5)));
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'plugin_host.dart';

/// M0 spike self-check page: runs the unmodified NetEase plugin for MyGo
/// Music inside QuickJS (flutter_js), searches, resolves a stream URL and
/// probes it for real audio bytes. Everything is shown as a log on screen.
void main() {
  runApp(const SpikeApp());
}

class SpikeApp extends StatelessWidget {
  const SpikeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'easyMusic M0 Spike',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: const SpikePage(),
    );
  }
}

class SpikePage extends StatefulWidget {
  const SpikePage({super.key});

  @override
  State<SpikePage> createState() => _SpikePageState();
}

class _SpikePageState extends State<SpikePage> {
  final List<String> _lines = <String>[];
  bool _running = false;

  void _log(String line) {
    if (!mounted) return;
    setState(() => _lines.add(line));
  }

  Future<void> _run() async {
    if (_running) return;
    setState(() {
      _running = true;
      _lines.clear();
    });
    final host = PluginHost(onLog: _log);
    try {
      final bootstrap = await rootBundle.loadString('assets/bootstrap.js');
      final pluginSource = await rootBundle.loadString('assets/index.js');
      await host.init(bootstrapSource: bootstrap);
      _log('md5("abc") = ${host.evalString('__testMd5("abc")')}');
      _log('aes block  = ${host.evalString('__testAesBlock("000102030405060708090a0b0c0d0e0f", "00112233445566778899aabbccddeeff")')}');

      host.loadPlugin(pluginSource);
      _log('plugin exports: ${host.pluginExports.join(', ')}');

      final search = await host.call('search', <String, dynamic>{
        'query': '周杰伦 稻香',
        'kind': 'tracks',
        'offset': 0,
      });
      if (search['ok'] != true) {
        _log('SEARCH FAILED: ${search['error']}');
        return;
      }
      final result = search['result'] as Map<String, dynamic>;
      final tracks = (result['tracks'] as List).cast<Map<String, dynamic>>();
      _log('search: ${tracks.length} tracks, more=${result['more']}');
      final first = tracks.first;
      final artists = (first['artists'] as List)
          .cast<Map<String, dynamic>>()
          .map((a) => a['name'])
          .join('/');
      _log('first: ${first['name']} — $artists (id=${first['id']})');

      final streamRes = await host.call('stream', <String, dynamic>{
        'id': first['id'],
        'quality': 'standard',
      });
      if (streamRes['ok'] != true) {
        _log('STREAM FAILED: ${streamRes['error']}');
        return;
      }
      final stream = streamRes['result'] as Map<String, dynamic>;
      _log('stream: ${stream['type']} br=${stream['bitRate']} size=${stream['size']}');
      _log('url: ${stream['url']}');

      final probeHeaders = <String, String>{};
      final sh = stream['headers'];
      if (sh is Map) sh.forEach((k, v) => probeHeaders['$k'] = '$v');
      final probe = await host.probeAudio(stream['url'] as String, probeHeaders);
      _log('probe: ${jsonEncode(probe)}');
      _log((probe['status'] == 200 || probe['status'] == 206)
          ? 'SPIKE OK: stream URL serves audio bytes'
          : 'SPIKE FAIL: unexpected probe status');
    } catch (e) {
      _log('ERROR: $e');
    } finally {
      host.dispose();
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('easyMusic M0 Spike')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: FilledButton.icon(
              onPressed: _running ? null : _run,
              icon: const Icon(Icons.play_arrow),
              label: Text(_running ? 'Running…' : 'Run plugin self-check'),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _lines.length,
              itemBuilder: (context, i) => SelectableText(
                _lines[i],
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

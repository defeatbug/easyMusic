import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../audio/audio_engine.dart';
import '../data/local_music.dart';
import '../data/models.dart';
import 'library_pages.dart' show PageTitle;
import 'theme.dart';
import 'widgets.dart';

/// The local library: the device's own songs, from MediaStore (with a
/// directory-walk fallback behind it — see LocalMusicService). The page
/// owns the permission conversation: ask, explain a refusal, offer the
/// settings route when the system will not ask again. Found songs play
/// through the same engine and row rules as online ones.
class LocalPage extends StatefulWidget {
  const LocalPage({super.key, required this.engine, required this.service});

  final AudioEngine engine;
  final LocalMusicService service;

  @override
  State<LocalPage> createState() => _LocalPageState();
}

enum _Phase { checking, askPermission, denied, deniedForever, scanning, done, failed }

class _LocalPageState extends State<LocalPage> {
  _Phase _phase = _Phase.checking;
  List<Track> _tracks = const [];
  String _errorLine = '';

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final status = await widget.service.permissionStatus();
    if (!mounted) return;
    if (status.isGranted || status.isLimited) {
      _scan();
    } else if (status.isPermanentlyDenied) {
      setState(() => _phase = _Phase.deniedForever);
    } else {
      setState(() => _phase = _Phase.askPermission);
    }
  }

  Future<void> _request() async {
    final status = await widget.service.requestPermission();
    if (!mounted) return;
    if (status.isGranted || status.isLimited) {
      _scan();
    } else if (status.isPermanentlyDenied) {
      setState(() => _phase = _Phase.deniedForever);
    } else {
      setState(() => _phase = _Phase.denied);
    }
  }

  Future<void> _scan() async {
    setState(() => _phase = _Phase.scanning);
    try {
      final tracks = await widget.service.scan();
      if (!mounted) return;
      setState(() {
        _tracks = tracks;
        _phase = _Phase.done;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorLine = '$e';
        _phase = _Phase.failed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return switch (_phase) {
      _Phase.checking => const LoadingState(line: '正在检查音乐权限…'),
      _Phase.scanning => const LoadingState(line: '正在扫描设备音乐…'),
      _Phase.askPermission => EmptyState(
          icon: Icons.folder_outlined,
          title: '本地音乐',
          line: '需要读取设备音频的权限，才能列出手机里已有的歌曲。',
          actionLabel: '允许读取音乐',
          onAction: _request,
        ),
      _Phase.denied => EmptyState(
          icon: Icons.folder_off_outlined,
          title: '没有音乐权限',
          line: '没有权限就看不到设备里的歌曲。可以再试一次，或到系统设置里手动允许。',
          actionLabel: '再试一次',
          onAction: _request,
        ),
      _Phase.deniedForever => EmptyState(
          icon: Icons.folder_off_outlined,
          title: '音乐权限被拒绝',
          line: '系统已不再弹出权限询问。请到系统设置 → 应用 → easyMusic → 权限里打开「音乐和音频」。',
          actionLabel: '打开系统设置',
          onAction: () => widget.service.openSettings(),
        ),
      _Phase.failed => EmptyState(
          icon: Icons.error_outline,
          title: '扫描失败',
          line: _errorLine,
          actionLabel: '重试',
          onAction: _scan,
        ),
      _Phase.done => _library(),
    };
  }

  Widget _library() {
    if (_tracks.isEmpty) {
      return EmptyState(
        icon: Icons.folder_outlined,
        title: '本地音乐',
        line: '没有在设备里找到歌曲。把音乐文件放到 Music 或 Download 文件夹后，重新扫描一次。',
        actionLabel: '重新扫描',
        onAction: _scan,
      );
    }
    final pad = pagePadding(context);
    return ListView(
      padding: EdgeInsets.fromLTRB(pad, 30, pad, 40),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: PageTitle(
                title: '本地音乐',
                subtitle: '共 ${_tracks.length} 首 · 来自这台设备',
              ),
            ),
            IconButton(
              onPressed: _scan,
              icon: const Icon(Icons.refresh, size: 20),
              color: Palette.muted,
              tooltip: '重新扫描',
              splashRadius: 20,
            ),
          ],
        ),
        Row(
          children: [
            FilledButton.icon(
              onPressed: () => widget.engine.playQueue(_tracks, 0),
              style: FilledButton.styleFrom(
                backgroundColor: Palette.accent,
                foregroundColor: Palette.onAccent,
              ),
              icon: const Icon(Icons.play_arrow, size: 19),
              label: const Text('播放全部'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TrackRows(tracks: _tracks, engine: widget.engine),
      ],
    );
  }
}

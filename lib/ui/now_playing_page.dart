import 'package:flutter/material.dart';

import '../audio/audio_engine.dart';
import '../data/home_repository.dart';
import '../data/local_music.dart';
import '../data/lyrics.dart';
import '../data/models.dart';
import 'theme.dart';
import 'widgets.dart';

/// Opens the full-screen now-playing page over the shell — the bars'
/// tap target in both layouts.
void openNowPlaying(
  BuildContext context, {
  required AudioEngine engine,
  required HomeRepository repository,
  required LocalMusicService localMusic,
}) {
  Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => NowPlayingPage(
      engine: engine,
      repository: repository,
      localMusic: localMusic,
    ),
  ));
}

/// The now-playing page: big cover, name and artists, the timed lyrics
/// when the source has them (the plugin's lyrics() for online songs, a
/// same-name .lrc for local files), a seekable progress bar and the
/// full transport — all bound to the same engine as the bars, in the
/// app's light palette.
class NowPlayingPage extends StatefulWidget {
  const NowPlayingPage({
    super.key,
    required this.engine,
    required this.repository,
    required this.localMusic,
  });

  final AudioEngine engine;
  final HomeRepository repository;
  final LocalMusicService localMusic;

  @override
  State<NowPlayingPage> createState() => _NowPlayingPageState();
}

class _NowPlayingPageState extends State<NowPlayingPage> {
  String _lyricsKey = '';
  Lyrics? _lyrics;
  bool _lyricsLoading = false;
  final ScrollController _lyricsScroll = ScrollController();
  int _highlightedLine = -1;

  @override
  void dispose() {
    _lyricsScroll.dispose();
    super.dispose();
  }

  String _keyOf(Track track) => '${track.id}|${track.localPath}';

  void _loadLyrics(Track track) {
    final key = _keyOf(track);
    _lyricsKey = key;
    _lyrics = null;
    _lyricsLoading = true;
    _highlightedLine = -1;
    final future = track.isLocal
        ? widget.localMusic.lyricsFor(track)
        : widget.repository.lyricsFor(track);
    future.then((lyrics) {
      if (!mounted || _lyricsKey != key) return;
      setState(() {
        _lyrics = lyrics;
        _lyricsLoading = false;
      });
    }).catchError((_) {
      if (!mounted || _lyricsKey != key) return;
      setState(() => _lyricsLoading = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.bg,
      appBar: AppBar(
        backgroundColor: Palette.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: Palette.text),
        leading: IconButton(
          icon: const Icon(Icons.expand_more, size: 26),
          tooltip: '收起',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          '正在播放',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Palette.faint,
          ),
        ),
        centerTitle: true,
      ),
      body: ListenableBuilder(
        listenable: widget.engine,
        builder: (context, _) {
          final track = widget.engine.currentTrack;
          if (track == null) {
            return const EmptyState(
              icon: Icons.music_note_outlined,
              title: '未播放',
              line: '先从首页、搜索或歌单里点一首歌吧。',
            );
          }
          if (_lyricsKey != _keyOf(track)) {
            WidgetsBinding.instance
                .addPostFrameCallback((_) => _loadLyrics(track));
          }
          return _content(track);
        },
      ),
    );
  }

  Widget _content(Track track) {
    final width = MediaQuery.sizeOf(context).width;
    final coverSize = (width - 96).clamp(200.0, 320.0);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(40, 10, 40, 36),
      child: Column(
        children: [
          CoverImage(
            imageUrl: track.album.imageUrl,
            coverAsset: track.album.coverAsset,
            size: coverSize,
            radius: 16,
            iconSize: 84,
          ),
          const SizedBox(height: 26),
          Text(
            track.name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              color: Palette.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            track.artistLine.isEmpty ? track.album.name : track.artistLine,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, color: Palette.muted),
          ),
          if (track.isLocal) ...[
            const SizedBox(height: 4),
            Text(
              track.localPath,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Palette.faint),
            ),
          ],
          const SizedBox(height: 22),
          _lyricsBlock(),
          const SizedBox(height: 18),
          _progress(track),
          const SizedBox(height: 10),
          _transport(),
        ],
      ),
    );
  }

  Widget _lyricsBlock() {
    if (_lyricsLoading) {
      return const SizedBox(
        height: 150,
        child: Center(
          child: Text('歌词加载中…',
              style: TextStyle(fontSize: 12.5, color: Palette.faint)),
        ),
      );
    }
    final lyrics = _lyrics;
    if (lyrics == null || lyrics.isEmpty) {
      return const SizedBox(
        height: 150,
        child: Center(
          child: Text('暂无歌词',
              style: TextStyle(fontSize: 12.5, color: Palette.faint)),
        ),
      );
    }
    return SizedBox(
      height: 150,
      child: StreamBuilder<Duration>(
        stream: widget.engine.positionStream,
        builder: (context, snapshot) {
          final index = lyrics.indexAt(
            (snapshot.data ?? Duration.zero).inMilliseconds,
          );
          if (index != _highlightedLine && index >= 0) {
            _highlightedLine = index;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!_lyricsScroll.hasClients) return;
              final target = (index * 30.0 - 60).clamp(
                0.0,
                _lyricsScroll.position.maxScrollExtent,
              );
              _lyricsScroll.animateTo(
                target,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            });
          }
          return ListView.builder(
            controller: _lyricsScroll,
            itemCount: lyrics.lines.length,
            itemBuilder: (context, i) {
              final line = lyrics.lines[i];
              final current = i == index;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Column(
                  children: [
                    Text(
                      line.text,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: current ? 14.5 : 13.5,
                        fontWeight:
                            current ? FontWeight.w700 : FontWeight.w400,
                        color: current ? Palette.accent : Palette.muted,
                      ),
                    ),
                    if (line.translation.isNotEmpty)
                      Text(
                        line.translation,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 12, color: Palette.faint),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _progress(Track track) {
    final engine = widget.engine;
    return StreamBuilder<Duration>(
      stream: engine.positionStream,
      builder: (context, posSnap) {
        final position = posSnap.data ?? Duration.zero;
        return StreamBuilder<Duration?>(
          stream: engine.durationStream,
          builder: (context, durSnap) {
            final total = durSnap.data ??
                Duration(milliseconds: track.durationMs);
            final maxMs = total.inMilliseconds.toDouble();
            final valueMs =
                position.inMilliseconds.toDouble().clamp(0.0, maxMs);
            return Row(
              children: [
                SizedBox(
                  width: 38,
                  child: Text(
                    formatDurationMs(position.inMilliseconds),
                    textAlign: TextAlign.right,
                    style:
                        const TextStyle(fontSize: 11.5, color: Palette.faint),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 12),
                      activeTrackColor: Palette.accent,
                      inactiveTrackColor: Palette.press,
                      thumbColor: Palette.accent,
                    ),
                    child: Slider(
                      value: maxMs > 0 ? valueMs : 0,
                      max: maxMs > 0 ? maxMs : 1,
                      onChanged: engine.canPlay && maxMs > 0
                          ? (v) =>
                              engine.seek(Duration(milliseconds: v.round()))
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 38,
                  child: Text(
                    formatDurationMs(total.inMilliseconds),
                    style:
                        const TextStyle(fontSize: 11.5, color: Palette.faint),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _transport() {
    final engine = widget.engine;
    final canPlay = engine.canPlay;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          onPressed: canPlay
              ? () => engine.setShuffle(!engine.shuffle)
              : null,
          icon: const Icon(Icons.shuffle, size: 20),
          color: engine.shuffle ? Palette.accent : Palette.muted,
          splashRadius: 22,
          tooltip: '随机播放',
        ),
        const SizedBox(width: 14),
        IconButton(
          onPressed: canPlay ? () => engine.previous() : null,
          icon: const Icon(Icons.skip_previous, size: 32),
          color: Palette.text,
          splashRadius: 26,
        ),
        const SizedBox(width: 10),
        if (engine.isBuffering)
          Container(
            width: 58,
            height: 58,
            decoration: const BoxDecoration(
              color: Palette.accent,
              shape: BoxShape.circle,
            ),
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Palette.onAccent,
              ),
            ),
          )
        else
          Container(
            width: 58,
            height: 58,
            decoration: const BoxDecoration(
              color: Palette.accent,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              onPressed: canPlay ? () => engine.togglePlay() : null,
              icon: Icon(
                engine.isPlaying ? Icons.pause : Icons.play_arrow,
                size: 30,
              ),
              color: Palette.onAccent,
              splashRadius: 29,
            ),
          ),
        const SizedBox(width: 10),
        IconButton(
          onPressed: canPlay ? () => engine.next() : null,
          icon: const Icon(Icons.skip_next, size: 32),
          color: Palette.text,
          splashRadius: 26,
        ),
        const SizedBox(width: 14),
        IconButton(
          onPressed: canPlay ? () => engine.cycleRepeat() : null,
          icon: Icon(
            engine.repeat == LoopMode.one ? Icons.repeat_one : Icons.repeat,
            size: 20,
          ),
          color: engine.repeat != LoopMode.off
              ? Palette.accent
              : Palette.muted,
          splashRadius: 22,
          tooltip: '循环模式',
        ),
      ],
    );
  }
}

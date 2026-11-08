import 'package:flutter/material.dart';

import '../audio/audio_engine.dart';
import '../data/models.dart';
import 'theme.dart';
import 'widgets.dart';

/// The home page: what the plugin's home() makes up — a greeting over the
/// day, its link cards and recommended playlists — followed by the official
/// charts and the hot chart's songs, all from the same live plugin calls
/// the desktop app makes. The shell owns the load (the player bar reads
/// the same future for its current song); this page only presents it.
/// Tapping a hot-chart row hands the chart's list to the audio engine
/// as its queue, starting at that row.
class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.future,
    required this.engine,
    required this.onRetry,
    required this.onOpenPage,
    required this.onOpenPlaylist,
  });

  final Future<HomeData> future;
  final AudioEngine engine;
  final VoidCallback onRetry;

  /// Opens a plugin page by id ('daily', 'charts', …) from a link card.
  final void Function(String page) onOpenPage;

  /// Opens a playlist's detail page from a card.
  final void Function(PlaylistItem playlist) onOpenPlaylist;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<HomeData>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Palette.accent),
                SizedBox(height: 16),
                Text('正在加载网易云音乐…',
                    style: TextStyle(fontSize: 13, color: Palette.muted)),
              ],
            ),
          );
        }
        if (snapshot.hasError) {
          return _centered('首页加载失败：${snapshot.error}', retry: onRetry);
        }
        final data = snapshot.data ?? const HomeData();
        if (data.isEmpty) {
          return _centered('暂时没有可显示的内容', retry: onRetry);
        }
        return _HomeContent(
          data: data,
          engine: engine,
          onOpenPage: onOpenPage,
          onOpenPlaylist: onOpenPlaylist,
        );
      },
    );
  }

  Widget _centered(String message, {required VoidCallback retry}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message,
              style: const TextStyle(fontSize: 13.5, color: Palette.muted)),
          const SizedBox(height: 14),
          OutlinedButton(onPressed: retry, child: const Text('重试')),
        ],
      ),
    );
  }
}

class _HomeContent extends StatelessWidget {
  const _HomeContent({
    required this.data,
    required this.engine,
    required this.onOpenPage,
    required this.onOpenPlaylist,
  });

  final HomeData data;
  final AudioEngine engine;
  final void Function(String page) onOpenPage;
  final void Function(PlaylistItem playlist) onOpenPlaylist;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    // The desktop page keeps its generous 40 side padding; at phone
    // widths that would leave barely 300 for content, so it tightens.
    final pad = MediaQuery.sizeOf(context).width < mobileBreakpoint
        ? 20.0
        : pagePad;
    return ListView(
      padding: EdgeInsets.fromLTRB(pad, 30, pad, 40),
      children: [
        // Heading: the day over a greeting, as the desktop home opens.
        Text(
          _dateLine(now),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
            color: Palette.muted,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _greeting(now),
          style: const TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.6,
            color: Palette.text,
          ),
        ),
        const SizedBox(height: 6),
        for (final section in data.sections) ...[
          const SizedBox(height: 28),
          if (section.title.isNotEmpty) SectionTitle(title: section.title),
          if (section.links.isNotEmpty) _linkRow(section.links),
          if (section.playlists.isNotEmpty)
            _cardGrid(section.playlists, limit: 12),
        ],
        if (data.charts.isNotEmpty) ...[
          const SizedBox(height: 34),
          const SectionTitle(title: '排行榜'),
          _cardGrid(data.charts, limit: 10),
        ],
        if (data.hotTracks.isNotEmpty) ...[
          const SizedBox(height: 34),
          SectionTitle(title: data.hotChart?.name ?? '热门歌曲'),
          // The rows follow the engine: the one it is on gets the
          // highlight and the play glyph, and a tap (re)starts the
          // chart queue at that row. Unavailable rows stay inert.
          ListenableBuilder(
            listenable: engine,
            builder: (context, _) => Column(
              children: [
                for (var i = 0; i < data.hotTracks.length && i < 10; i++)
                  TrackRow(
                    index: i,
                    track: data.hotTracks[i],
                    isCurrent: engine.currentTrack?.id == data.hotTracks[i].id,
                    isPlaying: engine.isPlaying &&
                        engine.currentTrack?.id == data.hotTracks[i].id,
                    onTap: data.hotTracks[i].unavailable
                        ? null
                        : () => engine.playQueue(data.hotTracks, i),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _linkRow(List<HomeLink> links) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Side by side, a card's text gets under 60px at phone widths —
        // not enough for a title over its line — so the cards stack
        // full-width instead, as phone layouts usually present them.
        if (constraints.maxWidth < 520) {
          return Column(
            children: [
              for (var i = 0; i < links.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                _LinkCard(link: links[i], onTap: onOpenPage),
              ],
            ],
          );
        }
        return Row(
          children: [
            for (var i = 0; i < links.length; i++) ...[
              if (i > 0) const SizedBox(width: 16),
              Expanded(child: _LinkCard(link: links[i], onTap: onOpenPage)),
            ],
          ],
        );
      },
    );
  }

  Widget _cardGrid(List<PlaylistItem> playlists, {required int limit}) {
    return PlaylistCardGrid(
      playlists: playlists,
      limit: limit,
      onTap: onOpenPlaylist,
    );
  }
}

class _LinkCard extends StatelessWidget {
  const _LinkCard({required this.link, required this.onTap});

  final HomeLink link;
  final void Function(String page) onTap;

  @override
  Widget build(BuildContext context) {
    final icon = switch (link.page) {
      'daily' => Icons.calendar_month_outlined,
      'charts' => Icons.leaderboard_outlined,
      _ => Icons.explore_outlined,
    };
    return Material(
      color: Palette.sidebar,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onTap(link.page),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Palette.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 22, color: Palette.accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      link.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Palette.text,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      link.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(fontSize: 12.5, color: Palette.muted),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 18, color: Palette.faint),
            ],
          ),
        ),
      ),
    );
  }
}

String _greeting(DateTime now) {
  final h = now.hour;
  if (h < 6) return '夜深了';
  if (h < 12) return '上午好';
  if (h < 14) return '中午好';
  if (h < 19) return '下午好';
  return '晚上好';
}

String _dateLine(DateTime now) {
  const weekdays = ['日', '一', '二', '三', '四', '五', '六'];
  return '${now.month}月${now.day}日 · 星期${weekdays[now.weekday % 7]}';
}

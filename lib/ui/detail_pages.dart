import 'package:flutter/material.dart';

import '../audio/audio_engine.dart';
import '../data/home_repository.dart';
import '../data/models.dart';
import 'theme.dart';
import 'widgets.dart';

/// Detail pages for the tappable things: playlists (charts included),
/// albums, artists and shows. Each is a pushed route with the same
/// layout — a header (cover, title, a line under it, description), a
/// play-all button over the track list — and every track list follows
/// the app-wide rule (tap plays the list as the queue at that row).

void openPlaylistDetail(
  BuildContext context, {
  required HomeRepository repository,
  required AudioEngine engine,
  required PlaylistItem playlist,
}) {
  Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => PlaylistDetailPage(
      repository: repository,
      engine: engine,
      playlist: playlist,
    ),
  ));
}

void openAlbumDetail(
  BuildContext context, {
  required HomeRepository repository,
  required AudioEngine engine,
  required AlbumRef album,
}) {
  Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => AlbumDetailPage(
      repository: repository,
      engine: engine,
      album: album,
    ),
  ));
}

void openArtistDetail(
  BuildContext context, {
  required HomeRepository repository,
  required AudioEngine engine,
  required ArtistRef artist,
}) {
  Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => ArtistDetailPage(
      repository: repository,
      engine: engine,
      artist: artist,
    ),
  ));
}

void openShowDetail(
  BuildContext context, {
  required HomeRepository repository,
  required AudioEngine engine,
  required ShowItem show,
}) {
  Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => ShowDetailPage(
      repository: repository,
      engine: engine,
      show: show,
    ),
  ));
}

/// The shared detail-page frame: back button over the page's own
/// scaffold, in the app palette.
class _DetailFrame extends StatelessWidget {
  const _DetailFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.bg,
      appBar: AppBar(
        backgroundColor: Palette.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: Palette.text),
        title: const Text(
          'easyMusic',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Palette.faint,
          ),
        ),
      ),
      body: child,
    );
  }
}

/// The header block: big cover beside the title stack, then the
/// transport row (play all + track count).
class _DetailHeader extends StatelessWidget {
  const _DetailHeader({
    required this.title,
    required this.imageUrl,
    this.coverAsset = '',
    this.subtitle = '',
    this.description = '',
    this.trackCount = 0,
    required this.onPlayAll,
    this.roundCover = false,
  });

  final String title;
  final String imageUrl;
  final String coverAsset;
  final String subtitle;
  final String description;
  final int trackCount;
  final VoidCallback? onPlayAll;
  final bool roundCover;

  @override
  Widget build(BuildContext context) {
    final pad = pagePadding(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 8, pad, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CoverImage(
                imageUrl: imageUrl,
                coverAsset: coverAsset,
                size: 168,
                radius: roundCover ? 84 : 12,
                iconSize: 56,
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 6),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.4,
                        color: Palette.text,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        subtitle,
                        style: const TextStyle(
                            fontSize: 13, color: Palette.muted),
                      ),
                    ],
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        description,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.5,
                          color: Palette.muted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              FilledButton.icon(
                onPressed: onPlayAll,
                style: FilledButton.styleFrom(
                  backgroundColor: Palette.accent,
                  foregroundColor: Palette.onAccent,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                ),
                icon: const Icon(Icons.play_arrow, size: 19),
                label: const Text('播放全部'),
              ),
              const SizedBox(width: 14),
              if (trackCount > 0)
                Text(
                  '$trackCount 首',
                  style: const TextStyle(fontSize: 12.5, color: Palette.faint),
                ),
            ],
          ),
          const SizedBox(height: 14),
        ],
      ),
    );
  }
}

/// Loads one detail future with the standard states: spinner, error
/// with retry, then the content builder.
class _DetailLoader<T> extends StatefulWidget {
  const _DetailLoader({required this.load, required this.builder});

  final Future<T> Function() load;
  final Widget Function(T data) builder;

  @override
  State<_DetailLoader<T>> createState() => _DetailLoaderState<T>();
}

class _DetailLoaderState<T> extends State<_DetailLoader<T>> {
  late Future<T> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.load();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const LoadingState();
        }
        if (snapshot.hasError) {
          return EmptyState(
            icon: Icons.error_outline,
            title: '加载失败',
            line: '${snapshot.error}',
            actionLabel: '重试',
            onAction: () => setState(() => _future = widget.load()),
          );
        }
        return widget.builder(snapshot.data as T);
      },
    );
  }
}

/// A scrollable track list under a header, with the page padding.
class _TrackListBody extends StatelessWidget {
  const _TrackListBody({
    required this.header,
    required this.tracks,
    required this.engine,
    this.below,
  });

  final Widget header;
  final List<Track> tracks;
  final AudioEngine engine;
  final Widget? below;

  @override
  Widget build(BuildContext context) {
    final pad = pagePadding(context);
    return ListView(
      padding: const EdgeInsets.only(bottom: 40),
      children: [
        header,
        Padding(
          padding: EdgeInsets.symmetric(horizontal: pad - 8),
          child: tracks.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(
                    child: Text(
                      '这里还没有歌曲',
                      style: TextStyle(fontSize: 13, color: Palette.muted),
                    ),
                  ),
                )
              : TrackRows(tracks: tracks, engine: engine),
        ),
        ?below,
      ],
    );
  }
}

class PlaylistDetailPage extends StatelessWidget {
  const PlaylistDetailPage({
    super.key,
    required this.repository,
    required this.engine,
    required this.playlist,
  });

  final HomeRepository repository;
  final AudioEngine engine;
  final PlaylistItem playlist;

  @override
  Widget build(BuildContext context) {
    return _DetailFrame(
      child: _DetailLoader<PlaylistDetail>(
        load: () => repository.playlistDetail(playlist.id),
        builder: (detail) {
          final info = detail.info.name.isEmpty ? playlist : detail.info;
          return _TrackListBody(
            header: _DetailHeader(
              title: info.name,
              imageUrl: info.imageUrl,
              coverAsset: info.coverAsset,
              subtitle: info.cardLine,
              description: info.description,
              trackCount: detail.tracks.length,
              onPlayAll: detail.tracks.isEmpty
                  ? null
                  : () => engine.playQueue(detail.tracks, 0),
            ),
            tracks: detail.tracks,
            engine: engine,
          );
        },
      ),
    );
  }
}

class AlbumDetailPage extends StatelessWidget {
  const AlbumDetailPage({
    super.key,
    required this.repository,
    required this.engine,
    required this.album,
  });

  final HomeRepository repository;
  final AudioEngine engine;
  final AlbumRef album;

  @override
  Widget build(BuildContext context) {
    return _DetailFrame(
      child: _DetailLoader<AlbumDetail>(
        load: () => repository.albumDetail(album.id),
        builder: (detail) {
          final info = detail.album.name.isEmpty ? album : detail.album;
          final subtitle = [
            if (info.artistLine.isNotEmpty) info.artistLine,
            if (info.released.isNotEmpty) info.released,
          ].join(' · ');
          return _TrackListBody(
            header: _DetailHeader(
              title: info.name,
              imageUrl: info.imageUrl,
              coverAsset: info.coverAsset,
              subtitle: subtitle,
              trackCount: detail.tracks.length,
              onPlayAll: detail.tracks.isEmpty
                  ? null
                  : () => engine.playQueue(detail.tracks, 0),
            ),
            tracks: detail.tracks,
            engine: engine,
          );
        },
      ),
    );
  }
}

class ArtistDetailPage extends StatelessWidget {
  const ArtistDetailPage({
    super.key,
    required this.repository,
    required this.engine,
    required this.artist,
  });

  final HomeRepository repository;
  final AudioEngine engine;
  final ArtistRef artist;

  @override
  Widget build(BuildContext context) {
    return _DetailFrame(
      child: _DetailLoader<ArtistDetail>(
        load: () => repository.artistDetail(artist.id),
        builder: (detail) {
          final info = detail.artist.name.isEmpty ? artist : detail.artist;
          final pad = pagePadding(context);
          return ListView(
            padding: const EdgeInsets.only(bottom: 40),
            children: [
              _DetailHeader(
                title: info.name,
                imageUrl: info.imageUrl,
                roundCover: true,
                trackCount: detail.tracks.length,
                onPlayAll: detail.tracks.isEmpty
                    ? null
                    : () => engine.playQueue(detail.tracks, 0),
              ),
              if (detail.tracks.isNotEmpty) ...[
                Padding(
                  padding: EdgeInsets.fromLTRB(pad, 6, pad, 0),
                  child: const SectionTitle(title: '热门歌曲'),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: pad - 8),
                  child: TrackRows(tracks: detail.tracks, engine: engine),
                ),
              ],
              if (detail.albums.isNotEmpty) ...[
                const SizedBox(height: 26),
                Padding(
                  padding: EdgeInsets.fromLTRB(pad, 0, pad, 0),
                  child: const SectionTitle(title: '专辑'),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: pad),
                  child: AlbumCardGrid(
                    albums: detail.albums,
                    onTap: (a) => openAlbumDetail(
                      context,
                      repository: repository,
                      engine: engine,
                      album: a,
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class ShowDetailPage extends StatefulWidget {
  const ShowDetailPage({
    super.key,
    required this.repository,
    required this.engine,
    required this.show,
  });

  final HomeRepository repository;
  final AudioEngine engine;
  final ShowItem show;

  @override
  State<ShowDetailPage> createState() => _ShowDetailPageState();
}

class _ShowDetailPageState extends State<ShowDetailPage> {
  late Future<ShowDetail> _future;
  ShowDetail? _detail;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _future = widget.repository.showDetail(widget.show.id).then((d) {
      _detail = d;
      return d;
    });
  }

  Future<void> _loadMore() async {
    final current = _detail;
    if (current == null || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final next = await widget.repository
          .showDetail(widget.show.id, offset: current.episodes.length);
      if (!mounted) return;
      setState(() {
        _detail = ShowDetail(
          show: current.show,
          episodes: [...current.episodes, ...next.episodes],
          more: next.more,
        );
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _DetailFrame(
      child: FutureBuilder<ShowDetail>(
        future: _future,
        builder: (context, snapshot) {
          final detail = _detail ?? snapshot.data;
          if (detail == null) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const LoadingState();
            }
            if (snapshot.hasError) {
              return EmptyState(
                icon: Icons.error_outline,
                title: '加载失败',
                line: '${snapshot.error}',
                actionLabel: '重试',
                onAction: () => setState(() {
                  _detail = null;
                  _future = widget.repository
                      .showDetail(widget.show.id)
                      .then((d) => _detail = d);
                }),
              );
            }
            return const LoadingState();
          }
          final info = detail.show.name.isEmpty ? widget.show : detail.show;
          final subtitle = [
            if (info.publisher.isNotEmpty) info.publisher,
            if (info.episodeCount > 0) '${info.episodeCount} 集',
          ].join(' · ');
          return _TrackListBody(
            header: _DetailHeader(
              title: info.name,
              imageUrl: info.imageUrl,
              subtitle: subtitle,
              description: info.description,
              trackCount: detail.episodes.length,
              onPlayAll: detail.episodes.isEmpty
                  ? null
                  : () => widget.engine.playQueue(detail.episodes, 0),
            ),
            tracks: detail.episodes,
            engine: widget.engine,
            below: detail.more
                ? Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Center(
                      child: OutlinedButton(
                        onPressed: _loadingMore ? null : _loadMore,
                        child: Text(_loadingMore ? '正在加载…' : '加载更多'),
                      ),
                    ),
                  )
                : null,
          );
        },
      ),
    );
  }
}

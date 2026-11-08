import 'package:flutter/material.dart';

import '../audio/audio_engine.dart';
import '../data/home_repository.dart';
import '../data/models.dart';
import 'detail_pages.dart';
import 'theme.dart';
import 'widgets.dart';

/// The library pages behind the sidebar: daily recommendations, liked
/// songs, saved albums, the charts list and subscribed shows. They are
/// content pages (the shell frames them), each loading from the plugin
/// through the repository, with the sign-in gate the plugin's own
/// 'signIn' error code asks for.

/// What a page shows when the plugin says the call needs an account.
class SignInGate extends StatelessWidget {
  const SignInGate({super.key, required this.title, required this.onSignIn});

  final String title;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.lock_outline,
      title: title,
      line: '登录网易云账号后，这里会同步你的内容。',
      actionLabel: '登录网易云',
      onAction: onSignIn,
    );
  }
}

/// Whether [error] is the plugin asking for a sign-in.
bool needsSignIn(Object? error) =>
    error is PluginCallException && error.needsSignIn;

/// A reloadable page scaffold: runs [load], shows spinner / sign-in
/// gate / error-with-retry / content.
class LibraryLoader<T> extends StatefulWidget {
  const LibraryLoader({
    super.key,
    required this.load,
    required this.builder,
    required this.onSignIn,
    required this.gateTitle,
    this.loadingLine = '正在加载…',
  });

  final Future<T> Function() load;
  final Widget Function(T data) builder;
  final VoidCallback onSignIn;
  final String gateTitle;
  final String loadingLine;

  @override
  State<LibraryLoader<T>> createState() => _LibraryLoaderState<T>();
}

class _LibraryLoaderState<T> extends State<LibraryLoader<T>> {
  late Future<T> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.load();
  }

  /// Re-runs the load (pages call this after a sign-in lands).
  void reload() => setState(() => _future = widget.load());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return LoadingState(line: widget.loadingLine);
        }
        if (snapshot.hasError) {
          if (needsSignIn(snapshot.error)) {
            return SignInGate(title: widget.gateTitle, onSignIn: widget.onSignIn);
          }
          return EmptyState(
            icon: Icons.error_outline,
            title: '加载失败',
            line: '${snapshot.error}',
            actionLabel: '重试',
            onAction: reload,
          );
        }
        return widget.builder(snapshot.data as T);
      },
    );
  }
}

/// Page title block used by the library pages (the home greeting's
/// smaller sibling).
class PageTitle extends StatelessWidget {
  const PageTitle({super.key, required this.title, this.subtitle = ''});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            color: Palette.text,
          ),
        ),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(subtitle,
              style: const TextStyle(fontSize: 13, color: Palette.muted)),
        ],
        const SizedBox(height: 22),
      ],
    );
  }
}

class DailyPage extends StatelessWidget {
  const DailyPage({
    super.key,
    required this.repository,
    required this.engine,
    required this.onSignIn,
  });

  final HomeRepository repository;
  final AudioEngine engine;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    return LibraryLoader<DailyData>(
      load: repository.daily,
      gateTitle: '每日推荐',
      onSignIn: onSignIn,
      builder: (data) {
        if (data.isEmpty) {
          return const EmptyState(
            icon: Icons.calendar_month_outlined,
            title: '每日推荐',
            line: '今天还没有生成推荐，稍后再来看看。',
          );
        }
        final pad = pagePadding(context);
        return ListView(
          padding: EdgeInsets.fromLTRB(pad, 30, pad, 40),
          children: [
            const PageTitle(title: '每日推荐', subtitle: '根据你的听歌偏好推荐'),
            if (data.tracks.isNotEmpty) ...[
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: () => engine.playQueue(data.tracks, 0),
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
              TrackRows(tracks: data.tracks, engine: engine),
            ],
            if (data.playlists.isNotEmpty) ...[
              const SizedBox(height: 30),
              const SectionTitle(title: '推荐歌单'),
              PlaylistCardGrid(
                playlists: data.playlists,
                onTap: (p) => openPlaylistDetail(
                  context,
                  repository: repository,
                  engine: engine,
                  playlist: p,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class LikedPage extends StatefulWidget {
  const LikedPage({
    super.key,
    required this.repository,
    required this.engine,
    required this.onSignIn,
  });

  final HomeRepository repository;
  final AudioEngine engine;
  final VoidCallback onSignIn;

  @override
  State<LikedPage> createState() => _LikedPageState();
}

class _LikedPageState extends State<LikedPage> {
  late Future<TrackPage> _future;
  List<Track> _tracks = const [];
  bool _more = false;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _future = _loadFirst();
  }

  Future<TrackPage> _loadFirst() async {
    final page = await widget.repository.likedTracks();
    _tracks = page.tracks;
    _more = page.more;
    return page;
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_more) return;
    setState(() => _loadingMore = true);
    try {
      final page =
          await widget.repository.likedTracks(offset: _tracks.length);
      if (!mounted) return;
      setState(() {
        _tracks = [..._tracks, ...page.tracks];
        _more = page.more;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<TrackPage>(
      future: _future,
      builder: (context, snapshot) {
        if (_tracks.isEmpty) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const LoadingState(line: '正在同步你喜欢的音乐…');
          }
          if (snapshot.hasError) {
            if (needsSignIn(snapshot.error)) {
              return SignInGate(title: '喜欢的音乐', onSignIn: widget.onSignIn);
            }
            return EmptyState(
              icon: Icons.error_outline,
              title: '加载失败',
              line: '${snapshot.error}',
              actionLabel: '重试',
              onAction: () => setState(() => _future = _loadFirst()),
            );
          }
          return const EmptyState(
            icon: Icons.favorite_border,
            title: '喜欢的音乐',
            line: '你还没有喜欢的歌曲。在网易云里点过红心的歌会出现在这里。',
          );
        }
        final pad = pagePadding(context);
        return ListView(
          padding: EdgeInsets.fromLTRB(pad, 30, pad, 40),
          children: [
            PageTitle(title: '喜欢的音乐', subtitle: '共 ${_tracks.length} 首'),
            TrackRows(tracks: _tracks, engine: widget.engine),
            if (_more)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Center(
                  child: OutlinedButton(
                    onPressed: _loadingMore ? null : _loadMore,
                    child: Text(_loadingMore ? '正在加载…' : '加载更多'),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class SavedAlbumsPage extends StatefulWidget {
  const SavedAlbumsPage({
    super.key,
    required this.repository,
    required this.engine,
    required this.onSignIn,
  });

  final HomeRepository repository;
  final AudioEngine engine;
  final VoidCallback onSignIn;

  @override
  State<SavedAlbumsPage> createState() => _SavedAlbumsPageState();
}

class _SavedAlbumsPageState extends State<SavedAlbumsPage> {
  late Future<SavedAlbumsResult> _future;
  List<AlbumRef> _albums = const [];
  bool _more = false;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _future = _loadFirst();
  }

  Future<SavedAlbumsResult> _loadFirst() async {
    final page = await widget.repository.savedAlbums();
    _albums = page.albums;
    _more = page.more;
    return page;
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_more) return;
    setState(() => _loadingMore = true);
    try {
      final page =
          await widget.repository.savedAlbums(offset: _albums.length);
      if (!mounted) return;
      setState(() {
        _albums = [..._albums, ...page.albums];
        _more = page.more;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SavedAlbumsResult>(
      future: _future,
      builder: (context, snapshot) {
        if (_albums.isEmpty) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const LoadingState(line: '正在同步收藏专辑…');
          }
          if (snapshot.hasError) {
            if (needsSignIn(snapshot.error)) {
              return SignInGate(title: '收藏专辑', onSignIn: widget.onSignIn);
            }
            return EmptyState(
              icon: Icons.error_outline,
              title: '加载失败',
              line: '${snapshot.error}',
              actionLabel: '重试',
              onAction: () => setState(() => _future = _loadFirst()),
            );
          }
          return const EmptyState(
            icon: Icons.album_outlined,
            title: '收藏专辑',
            line: '你还没有收藏的专辑。',
          );
        }
        final pad = pagePadding(context);
        return ListView(
          padding: EdgeInsets.fromLTRB(pad, 30, pad, 40),
          children: [
            const PageTitle(title: '收藏专辑'),
            AlbumCardGrid(
              albums: _albums,
              onTap: (a) => openAlbumDetail(
                context,
                repository: widget.repository,
                engine: widget.engine,
                album: a,
              ),
            ),
            if (_more)
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: Center(
                  child: OutlinedButton(
                    onPressed: _loadingMore ? null : _loadMore,
                    child: Text(_loadingMore ? '正在加载…' : '加载更多'),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class ChartsPage extends StatelessWidget {
  const ChartsPage({
    super.key,
    required this.repository,
    required this.engine,
    required this.onSignIn,
  });

  final HomeRepository repository;
  final AudioEngine engine;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    return LibraryLoader<List<PlaylistItem>>(
      load: repository.charts,
      gateTitle: '排行榜',
      onSignIn: onSignIn,
      builder: (charts) {
        if (charts.isEmpty) {
          return const EmptyState(
            icon: Icons.leaderboard_outlined,
            title: '排行榜',
            line: '暂时没有榜单数据，稍后再试。',
          );
        }
        final pad = pagePadding(context);
        return ListView(
          padding: EdgeInsets.fromLTRB(pad, 30, pad, 40),
          children: [
            const PageTitle(title: '排行榜', subtitle: '网易云官方榜单'),
            PlaylistCardGrid(
              playlists: charts,
              onTap: (p) => openPlaylistDetail(
                context,
                repository: repository,
                engine: engine,
                playlist: p,
              ),
            ),
          ],
        );
      },
    );
  }
}

class ShowsPage extends StatelessWidget {
  const ShowsPage({
    super.key,
    required this.repository,
    required this.engine,
    required this.onSignIn,
  });

  final HomeRepository repository;
  final AudioEngine engine;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    return LibraryLoader<List<ShowItem>>(
      load: repository.shows,
      gateTitle: '我的播客',
      onSignIn: onSignIn,
      builder: (shows) {
        if (shows.isEmpty) {
          return const EmptyState(
            icon: Icons.podcasts_outlined,
            title: '我的播客',
            line: '你还没有订阅的播客节目。',
          );
        }
        final pad = pagePadding(context);
        return ListView(
          padding: EdgeInsets.fromLTRB(pad, 30, pad, 40),
          children: [
            const PageTitle(title: '我的播客'),
            Column(
              children: [
                for (final s in shows)
                  ShowRow(
                    show: s,
                    onTap: () => openShowDetail(
                      context,
                      repository: repository,
                      engine: engine,
                      show: s,
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

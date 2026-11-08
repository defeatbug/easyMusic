import 'dart:async';

import 'package:flutter/material.dart';

import '../audio/audio_engine.dart';
import '../data/home_repository.dart';
import '../data/local_music.dart';
import '../data/models.dart';
import 'detail_pages.dart';
import 'home_page.dart';
import 'library_pages.dart';
import 'local_page.dart';
import 'mini_player_bar.dart';
import 'mobile_tab_bar.dart';
import 'now_playing_page.dart';
import 'placeholder_page.dart';
import 'player_bar.dart';
import 'search_page.dart';
import 'settings_page.dart';
import 'sidebar.dart';
import 'sign_in_overlay.dart';
import 'theme.dart';
import 'web_signin_page.dart';

/// The app's frame, in two layouts over one page state:
///
/// - Desktop (width ≥ [mobileBreakpoint]): the desktop app's frame —
///   sidebar at the left (full 232, or a 64 icon rail below 720), the
///   page in the middle, and the player bar along the foot of the
///   content.
/// - Phone (width < [mobileBreakpoint]): no sidebar — the page, a mini
///   player bar, and a bottom tab bar.
///
/// Owns the home load, the account state and the audio engine: the
/// home data presents its queue to the engine (its first playable song
/// is what the bars show before anything plays), row taps start
/// playback from the same queue, engine errors surface as snackbars,
/// and the plugin's sign-in prompt renders as an overlay while its
/// web sign-in presenter pushes the browser page.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.repository, this.engine});

  final HomeRepository repository;

  /// The playback engine from main(); null in the screenshot build,
  /// where the shell substitutes an inert engine (no backend, no
  /// resolver) so the bars present the first song without playing.
  final AudioEngine? engine;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  AppPage _page = AppPage.home;
  late Future<HomeData> _homeFuture;
  late final AudioEngine _engine;
  final LocalMusicService _localMusic = LocalMusicService();
  StreamSubscription<String>? _errorSub;

  AccountInfo? _account;
  List<PlaylistItem> _myPlaylists = const [];
  bool _signingIn = false;

  @override
  void initState() {
    super.initState();
    _engine = widget.engine ?? AudioEngine();
    _homeFuture = widget.repository.loadHome();
    _presentOnLoad(_homeFuture);
    _errorSub = _engine.errors.listen((message) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 3),
        ),
      );
    });
    // The plugin's web sign-in asks the app to show its page; the
    // shell owns the Navigator, so it presents — and an empty answer
    // (page closed, timeout) becomes the plugin's error.
    widget.repository.webSignInPresenter = (request) async {
      final cookie = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => WebSignInPage(request: request)),
      );
      if (cookie == null || cookie.isEmpty) {
        throw StateError('网页登录未完成');
      }
      return cookie;
    };
    _refreshAccount();
  }

  @override
  void dispose() {
    _errorSub?.cancel();
    _engine.dispose();
    super.dispose();
  }

  /// When a home load lands, hand its song list to the engine as the
  /// presented queue (the engine ignores this once playback started).
  void _presentOnLoad(Future<HomeData> future) {
    future.then((data) {
      if (mounted) _engine.presentQueue(data.hotTracks);
    }, onError: (_) {});
  }

  void _reloadHome() {
    setState(() => _homeFuture = widget.repository.loadHome());
    _presentOnLoad(_homeFuture);
  }

  void _select(AppPage page) => setState(() => _page = page);

  void _openPluginPage(String page) {
    _select(switch (page) {
      'daily' => AppPage.daily,
      'charts' => AppPage.charts,
      _ => AppPage.home,
    });
  }

  // --- account ----------------------------------------------------------

  Future<void> _refreshAccount() async {
    try {
      final account = await widget.repository.account();
      if (!mounted) return;
      setState(() => _account = account);
      if (account != null) {
        final playlists = await widget.repository.userPlaylists();
        if (mounted) setState(() => _myPlaylists = playlists);
      } else if (mounted) {
        setState(() => _myPlaylists = const []);
      }
    } catch (_) {
      // Signed-out and offline states both read as "no account" here;
      // the pages surface their own errors when it matters.
    }
  }

  Future<void> _signIn() async {
    if (_signingIn) return;
    _signingIn = true;
    try {
      final account = await widget.repository.signIn();
      if (!mounted) return;
      setState(() => _account = account);
      await _refreshAccount();
      _reloadHome();
    } catch (e) {
      if (mounted) _showMessage('$e');
    } finally {
      _signingIn = false;
    }
  }

  Future<void> _signOut() async {
    try {
      await widget.repository.signOut();
    } catch (_) {
      // Local state clears either way; the plugin drops its session.
    }
    if (!mounted) return;
    setState(() {
      _account = null;
      _myPlaylists = const [];
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  // --- navigation -------------------------------------------------------

  void _openPlaylist(PlaylistItem playlist) {
    openPlaylistDetail(
      context,
      repository: widget.repository,
      engine: _engine,
      playlist: playlist,
    );
  }

  void _openNowPlaying() {
    openNowPlaying(
      context,
      engine: _engine,
      repository: widget.repository,
      localMusic: _localMusic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.bg,
      body: Stack(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              if (width < mobileBreakpoint) return _phoneLayout();
              final rail = width < 720;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Sidebar(
                    selected: _page,
                    onSelect: _select,
                    rail: rail,
                    account: _account,
                    playlists: _myPlaylists,
                    onAccountTap: _signIn,
                    onSignOut: _signOut,
                    onOpenPlaylist: _openPlaylist,
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(child: _content()),
                        PlayerBar(
                          engine: _engine,
                          onOpenNowPlaying: _openNowPlaying,
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
          SignInOverlay(
            controller: widget.repository.signInPrompt,
            onCancel: widget.repository.cancelSignIn,
          ),
        ],
      ),
    );
  }

  /// The phone frame: page, mini player, tab bar — stacked full-width.
  Widget _phoneLayout() {
    return Column(
      children: [
        Expanded(child: _content()),
        MiniPlayerBar(engine: _engine, onOpenNowPlaying: _openNowPlaying),
        MobileTabBar(selected: _page, onSelect: _select),
      ],
    );
  }

  Widget _content() {
    return switch (_page) {
      AppPage.home => HomePage(
          future: _homeFuture,
          engine: _engine,
          onRetry: _reloadHome,
          onOpenPage: _openPluginPage,
          onOpenPlaylist: _openPlaylist,
        ),
      AppPage.daily => DailyPage(
          repository: widget.repository,
          engine: _engine,
          onSignIn: _signIn,
        ),
      AppPage.charts => ChartsPage(
          repository: widget.repository,
          engine: _engine,
          onSignIn: _signIn,
        ),
      AppPage.liked => LikedPage(
          repository: widget.repository,
          engine: _engine,
          onSignIn: _signIn,
        ),
      AppPage.savedAlbums => SavedAlbumsPage(
          repository: widget.repository,
          engine: _engine,
          onSignIn: _signIn,
        ),
      AppPage.shows => ShowsPage(
          repository: widget.repository,
          engine: _engine,
          onSignIn: _signIn,
        ),
      AppPage.local => LocalPage(engine: _engine, service: _localMusic),
      AppPage.search => SearchPage(
          repository: widget.repository,
          engine: _engine,
        ),
      AppPage.settings => SettingsPage(
          repository: widget.repository,
          account: _account,
          onSignIn: _signIn,
          onSignOut: _signOut,
        ),
      AppPage.stations => const PlaceholderPage(page: AppPage.stations),
    };
  }
}

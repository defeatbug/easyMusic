import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../plugin/sign_in.dart';
import '../plugin_host.dart';
import 'json_file_store.dart';
import 'lyrics.dart';
import 'models.dart';
import 'stream_resolver.dart';

/// A plugin call that failed. [code] is the plugin protocol's error
/// code when it set one ('signIn' = the call needs a signed-in account,
/// 'unavailable' = the resource cannot be had); pages branch on it.
class PluginCallException implements Exception {
  PluginCallException(this.message, [this.code]);

  final String message;
  final String? code;

  bool get needsSignIn => code == 'signIn';

  @override
  String toString() => message;
}

/// Where the app's data comes from. The real implementation talks to
/// the plugin through QuickJS; the screenshot build swaps in a capture
/// replay (see capture_home_repository.dart) because QuickJS cannot run
/// in a web build. The two never mix: main.dart wires one, main_shot.dart
/// the other.
///
/// Beyond the home load, this is the whole plugin surface the UI uses —
/// account, library, search, detail pages, lyrics. Methods a build
/// cannot serve answer honestly (signed out, empty, or a thrown
/// [PluginCallException]) rather than faking data.
abstract class HomeRepository {
  Future<HomeData> loadHome();

  /// The sign-in prompt the plugin is asking to show (QR flow). The
  /// shell renders it as an overlay while [signIn] runs.
  final SignInPromptController signInPrompt = SignInPromptController();

  /// Shows a plugin's web sign-in page and answers its Cookie header.
  /// The shell installs this (it owns the Navigator); without it, web
  /// sign-in fails with a clear error and the QR flow still works.
  Future<String> Function(WebSignInRequest request)? webSignInPresenter;

  /// The signed-in account, or null when signed out.
  Future<AccountInfo?> account() async => null;

  /// Runs the plugin's sign-in (QR by default, web when the login
  /// method setting says so) and answers the account it landed on.
  Future<AccountInfo> signIn() async =>
      throw PluginCallException('当前版本未接入登录');

  /// Cancels an in-flight [signIn] (the overlay's cancel button).
  void cancelSignIn() {}

  Future<void> signOut() async {}

  /// The listener's own + collected playlists (playlists()).
  Future<List<PlaylistItem>> userPlaylists() async => const [];

  /// One page of liked songs.
  Future<TrackPage> likedTracks({int offset = 0}) async => const TrackPage();

  /// Daily recommendations (needs sign-in).
  Future<DailyData> daily() async => const DailyData();

  /// The official charts, as playlist cards.
  Future<List<PlaylistItem>> charts() async => const [];

  /// One page of collected albums.
  Future<SavedAlbumsResult> savedAlbums({int offset = 0}) async =>
      const SavedAlbumsResult();

  /// The listener's subscribed shows (needs sign-in).
  Future<List<ShowItem>> shows() async => const [];

  Future<ShowDetail> showDetail(String id, {int offset = 0}) async =>
      ShowDetail(show: ShowItem(id: id, name: ''));

  /// One page of search results for [kind] ('tracks', 'playlists',
  /// 'albums', 'artists', 'shows').
  Future<SearchResults> search(
    String query, {
    String kind = 'tracks',
    int offset = 0,
  }) async =>
      SearchResults(kind: kind);

  /// Keyword suggestions for a partial query.
  Future<List<String>> suggest(String query) async => const [];

  Future<PlaylistDetail> playlistDetail(String id) async =>
      PlaylistDetail(info: PlaylistItem(id: id, name: ''));

  Future<AlbumDetail> albumDetail(String id) async =>
      AlbumDetail(album: AlbumRef(id: id, name: ''));

  Future<ArtistDetail> artistDetail(String id) async =>
      ArtistDetail(artist: ArtistRef(id: id, name: ''));

  /// Timed lyrics for an online track, or null when the plugin has
  /// none. Local tracks read their .lrc sibling instead (local_music).
  Future<Lyrics?> lyricsFor(Track track) async => null;

  /// The plugin's 登录方式 setting: 'qr' (default) or 'web'.
  Future<String> getLoginMethod() async => '';

  Future<void> setLoginMethod(String method) async {}
}

/// Live data: boots the unmodified NetEase plugin in QuickJS (M0-verified
/// host) and calls its exports like the desktop app does. Also resolves
/// streams for the audio engine, through the same host (the QuickJS
/// runtime is not re-entrant, so every call shares the one PluginHost —
/// and a long sign-in therefore blocks other calls until it settles).
///
/// The host's storage (the sign-in session above all) persists to a
/// JSON file in the app support directory, as do the plugin settings.
class PluginHomeRepository extends HomeRepository implements StreamResolver {
  PluginHost? _host;
  Future<PluginHost>? _bootFuture;
  Map<String, dynamic> _settings = <String, dynamic>{};
  bool _settingsLoaded = false;
  File? _settingsFile;

  Future<PluginHost> _ready() => _bootFuture ??= _createAndBoot();

  Future<PluginHost> _createAndBoot() async {
    Directory? supportDir;
    try {
      supportDir = await getApplicationSupportDirectory();
    } catch (_) {
      supportDir = null; // storage stays in memory (tests, odd platforms)
    }
    await _loadSettings(supportDir);
    final host = PluginHost(
      storageFile:
          supportDir == null ? null : File('${supportDir.path}/plugin_storage.json'),
    );
    _host = host;
    try {
      await _boot(host);
    } catch (_) {
      _host = null;
      _bootFuture = null;
      rethrow;
    }
    return host;
  }

  Future<void> _loadSettings(Directory? supportDir) async {
    if (_settingsLoaded) return;
    _settingsLoaded = true;
    if (supportDir == null) return;
    _settingsFile = File('${supportDir.path}/plugin_settings.json');
    _settings = await JsonFileStore(_settingsFile!).load();
  }

  Future<void> _boot(PluginHost host) async {
    final bootstrap = await rootBundle.loadString('assets/bootstrap.js');
    final source = await rootBundle.loadString('assets/plugin/index.js');

    // The plugin's declared network permission becomes the host's
    // fetch allowlist (item G of the v1 pass).
    try {
      final manifest = jsonDecode(
          await rootBundle.loadString('assets/plugin/plugin.json')) as Map;
      final network =
          ((manifest['permissions'] as Map?)?['network'] as List?) ?? const [];
      host.networkAllowlist = network.map((e) => e.toString()).toSet();
    } catch (_) {
      host.networkAllowlist = <String>{};
    }

    host.onSignInPrompt = signInPrompt.show;
    host.webSignInHandler = (request) async {
      final presenter = webSignInPresenter;
      if (presenter == null) throw StateError('此应用未接入网页登录');
      return presenter(request);
    };

    await host.init(bootstrapSource: bootstrap, settings: _settings);
    host.loadPlugin(source);
  }

  /// Calls a plugin export and returns its raw result (Map, List or
  /// null), translating a plugin error into [PluginCallException].
  Future<dynamic> _result(
    PluginHost host,
    String name,
    Map<String, dynamic> args, {
    Duration timeout = const Duration(seconds: 90),
  }) async {
    final res = await host.call(name, args, timeout: timeout);
    if (res['ok'] != true) {
      throw PluginCallException(
        '${res['error'] ?? '插件调用失败'}',
        res['code']?.toString(),
      );
    }
    return res['result'];
  }

  Future<Map<String, dynamic>> _call(
    PluginHost host,
    String name,
    Map<String, dynamic> args, {
    Duration timeout = const Duration(seconds: 90),
  }) async {
    final result = await _result(host, name, args, timeout: timeout);
    return (result as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
  }

  Future<List<Map<String, dynamic>>> _callList(
    PluginHost host,
    String name,
    Map<String, dynamic> args,
  ) async {
    final result = await _result(host, name, args);
    return (result as List? ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
  }

  @override
  Future<HomeData> loadHome() async {
    final host = await _ready();

    final homeJson = await _call(host, 'home', const {});
    final home = HomeData(
      title: homeJson['title']?.toString() ?? '',
      subtitle: homeJson['subtitle']?.toString() ?? '',
      sections: (homeJson['sections'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => HomeSection.fromJson(e.cast<String, dynamic>()))
          .toList(),
    );

    // Charts and the hot chart's tracks enrich the page; if either fails
    // the home sections still stand on their own.
    var charts = <PlaylistItem>[];
    PlaylistItem? hotChart;
    var hotTracks = <Track>[];
    try {
      final chartsJson = await _call(host, 'browse', const {'page': 'charts'});
      final sections = (chartsJson['sections'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
      if (sections.isNotEmpty) {
        charts = ((sections.first['playlists'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => PlaylistItem.fromJson(e.cast<String, dynamic>()))
            .toList();
      }
      if (charts.isNotEmpty) {
        hotChart = charts.firstWhere(
          (p) => p.name.contains('热歌榜'),
          orElse: () => charts.first,
        );
        final plJson = await _call(host, 'playlist', {'id': hotChart.id});
        hotTracks = ((plJson['tracks'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => Track.fromJson(e.cast<String, dynamic>()))
            .toList();
      }
    } catch (_) {
      // Keep whatever home() gave us.
    }

    return HomeData(
      title: home.title,
      subtitle: home.subtitle,
      sections: home.sections,
      charts: charts,
      hotChart: hotChart,
      hotTracks: hotTracks,
    );
  }

  @override
  Future<AccountInfo?> account() async {
    final host = await _ready();
    final res = await _result(host, 'account', const {});
    if (res == null) return null;
    final account =
        AccountInfo.fromJson((res as Map).cast<String, dynamic>());
    return account.id.isEmpty ? null : account;
  }

  @override
  Future<AccountInfo> signIn() async {
    final host = await _ready();
    signInPrompt.begin();
    try {
      // The QR flow polls for up to four minutes inside the plugin;
      // the host call must outlast it (the desktop grants five).
      final res = await _call(
        host,
        'signIn',
        const {},
        timeout: const Duration(minutes: 6),
      );
      final account = AccountInfo.fromJson(res);
      if (account.id.isEmpty) throw PluginCallException('登录未完成，请重试');
      return account;
    } finally {
      signInPrompt.end();
    }
  }

  @override
  void cancelSignIn() {
    signInPrompt.suppress();
    _host?.cancelPendingCall('登录已取消');
  }

  @override
  Future<void> signOut() async {
    final host = await _ready();
    await _result(host, 'signOut', const {});
  }

  @override
  Future<List<PlaylistItem>> userPlaylists() async {
    final host = await _ready();
    final rows = await _callList(host, 'playlists', const {});
    return rows.map(PlaylistItem.fromJson).toList();
  }

  @override
  Future<TrackPage> likedTracks({int offset = 0}) async {
    final host = await _ready();
    final res = await _call(host, 'liked', {'offset': offset});
    return TrackPage.fromJson(res);
  }

  @override
  Future<DailyData> daily() async {
    final host = await _ready();
    final res = await _call(host, 'browse', const {'page': 'daily'});
    var tracks = <Track>[];
    var playlists = <PlaylistItem>[];
    for (final raw in (res['sections'] as List? ?? const [])) {
      if (raw is! Map) continue;
      final section = raw.cast<String, dynamic>();
      tracks = [
        ...tracks,
        ...((section['tracks'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => Track.fromJson(e.cast<String, dynamic>())),
      ];
      playlists = [
        ...playlists,
        ...((section['playlists'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => PlaylistItem.fromJson(e.cast<String, dynamic>())),
      ];
    }
    return DailyData(tracks: tracks, playlists: playlists);
  }

  @override
  Future<List<PlaylistItem>> charts() async {
    final host = await _ready();
    final res = await _call(host, 'browse', const {'page': 'charts'});
    final sections = (res['sections'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
    if (sections.isEmpty) return const [];
    return ((sections.first['playlists'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => PlaylistItem.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  @override
  Future<SavedAlbumsResult> savedAlbums({int offset = 0}) async {
    final host = await _ready();
    final res = await _call(host, 'savedAlbums', {'offset': offset});
    return SavedAlbumsResult.fromJson(res);
  }

  @override
  Future<List<ShowItem>> shows() async {
    final host = await _ready();
    final rows = await _callList(host, 'shows', const {});
    return rows.map(ShowItem.fromJson).toList();
  }

  @override
  Future<ShowDetail> showDetail(String id, {int offset = 0}) async {
    final host = await _ready();
    final res = await _call(host, 'show', {'id': id, 'offset': offset});
    return ShowDetail.fromJson(res);
  }

  @override
  Future<SearchResults> search(
    String query, {
    String kind = 'tracks',
    int offset = 0,
  }) async {
    final host = await _ready();
    final res = await _call(host, 'search', {
      'query': query,
      'kind': kind,
      'offset': offset,
    });
    return SearchResults.fromJson(kind, res);
  }

  @override
  Future<List<String>> suggest(String query) async {
    final host = await _ready();
    final result = await _result(host, 'suggest', {'query': query});
    return (result as List? ?? const []).map((e) => e.toString()).toList();
  }

  @override
  Future<PlaylistDetail> playlistDetail(String id) async {
    final host = await _ready();
    final res = await _call(host, 'playlist', {'id': id});
    return PlaylistDetail.fromJson(res);
  }

  @override
  Future<AlbumDetail> albumDetail(String id) async {
    final host = await _ready();
    final res = await _call(host, 'album', {'id': id});
    return AlbumDetail.fromJson(res);
  }

  @override
  Future<ArtistDetail> artistDetail(String id) async {
    final host = await _ready();
    final res = await _call(host, 'artist', {'id': id});
    return ArtistDetail.fromJson(res);
  }

  @override
  Future<Lyrics?> lyricsFor(Track track) async {
    if (track.isLocal) return null; // local .lrc: see local_music.dart
    final host = await _ready();
    final res = await _call(host, 'lyrics', {'id': track.id});
    final rawLines = res['lines'];
    if (rawLines is List && rawLines.isNotEmpty) {
      return Lyrics(rawLines
          .whereType<Map>()
          .map((e) => LyricLine.fromJson(e.cast<String, dynamic>()))
          .toList());
    }
    final lrc = res['lrc']?.toString() ?? '';
    return lrc.isEmpty ? null : Lyrics(parseLrc(lrc));
  }

  @override
  Future<String> getLoginMethod() async {
    if (!_settingsLoaded) {
      Directory? dir;
      try {
        dir = await getApplicationSupportDirectory();
      } catch (_) {
        dir = null;
      }
      await _loadSettings(dir);
    }
    return _settings['loginMethod']?.toString() ?? '';
  }

  @override
  Future<void> setLoginMethod(String method) async {
    await getLoginMethod(); // make sure the settings file is located
    _settings['loginMethod'] = method;
    final file = _settingsFile;
    if (file != null) await JsonFileStore(file).save(_settings);
    // host.setting() reads the map handed over at boot, so the host
    // reboots; the next call rebuilds it with the new settings (the
    // persisted storage file carries the session across).
    final host = _host;
    _host = null;
    _bootFuture = null;
    host?.dispose();
  }

  /// Resolves one track's playable URL through the plugin's stream()
  /// (M0-verified shape: url/type/bitRate/size, quality 'standard').
  /// Throws when the plugin errors or hands back no URL — the audio
  /// engine treats that as a failed track and moves on.
  @override
  Future<ResolvedStream> resolveStream(Track track) async {
    final host = await _ready();
    final res = await _call(host, 'stream', {
      'id': track.id,
      'quality': 'standard',
    });
    final url = res['url']?.toString() ?? '';
    if (url.isEmpty) {
      throw StateError('插件没有返回播放地址');
    }
    final rawHeaders = res['headers'];
    final headers = <String, String>{};
    if (rawHeaders is Map) {
      rawHeaders.forEach((k, v) {
        if (v != null) headers['$k'] = '$v';
      });
    }
    return ResolvedStream(
      url: url,
      type: res['type']?.toString() ?? '',
      bitRate: res['bitRate'] is num ? (res['bitRate'] as num).toInt() : 0,
      size: res['size'] is num ? (res['size'] as num).toInt() : 0,
      headers: headers,
    );
  }
}

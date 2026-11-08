import 'dart:convert';

import 'package:flutter/services.dart';

import 'home_repository.dart';
import 'models.dart';

/// Screenshot-only repository: replays assets/capture/home_capture.json,
/// which test/capture_home_test.dart recorded from a live plugin run
/// (covers included as local assets, since a headless browser cannot reach
/// the image CDN). Wired in only by lib/main_shot.dart; the real entry
/// point uses [PluginHomeRepository].
///
/// Beyond the home data it serves only what the capture holds: the
/// chart list, and a detail page for the hot chart (the one playlist
/// whose tracks were recorded). Everything else inherits the base
/// class's honest answers — signed out, empty pages.
class CaptureHomeRepository extends HomeRepository {
  Map<String, dynamic>? _capture;

  Future<Map<String, dynamic>> _load() async {
    final cached = _capture;
    if (cached != null) return cached;
    final raw = await rootBundle.loadString('assets/capture/home_capture.json');
    return _capture = jsonDecode(raw) as Map<String, dynamic>;
  }

  @override
  Future<HomeData> loadHome() async {
    final j = await _load();
    final home = (j['home'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    return HomeData(
      title: home['title']?.toString() ?? '',
      subtitle: home['subtitle']?.toString() ?? '',
      sections: (home['sections'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => HomeSection.fromJson(e.cast<String, dynamic>()))
          .toList(),
      charts: (j['charts'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => PlaylistItem.fromJson(e.cast<String, dynamic>()))
          .toList(),
      hotChart: j['hotChart'] is Map
          ? PlaylistItem.fromJson(
              (j['hotChart'] as Map).cast<String, dynamic>())
          : null,
      hotTracks: (j['hotTracks'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => Track.fromJson(e.cast<String, dynamic>()))
          .toList(),
    );
  }

  @override
  Future<List<PlaylistItem>> charts() async => (await loadHome()).charts;

  @override
  Future<PlaylistDetail> playlistDetail(String id) async {
    final data = await loadHome();
    final hot = data.hotChart;
    if (hot != null && hot.id == id) {
      return PlaylistDetail(info: hot, tracks: data.hotTracks);
    }
    // Other playlists appear in the capture without their tracks; the
    // detail page shows their real info over an honest empty list.
    for (final p in [...data.charts, for (final s in data.sections) ...s.playlists]) {
      if (p.id == id) return PlaylistDetail(info: p);
    }
    return PlaylistDetail(info: PlaylistItem(id: id, name: ''));
  }
}

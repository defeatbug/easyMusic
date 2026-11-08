// Data shapes mirroring what a MyGo Music plugin returns (see the plugin
// protocol: search/stream/home/browse/playlist result objects). Parsing is
// tolerant: plugins promise these keys but individual items may omit them.

Map<String, dynamic> _map(dynamic v) =>
    v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};

List<Map<String, dynamic>> _mapList(dynamic v) => v is List
    ? v.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList()
    : <Map<String, dynamic>>[];

String _str(dynamic v) => v?.toString() ?? '';

int _int(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

String formatDurationMs(int ms) {
  if (ms <= 0) return '0:00';
  final total = ms ~/ 1000;
  return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
}

/// Formats a play count the way Chinese music apps do: 12345 → 1.2万.
String formatCount(int n) {
  if (n < 10000) return '$n';
  if (n < 100000000) return '${(n / 10000).toStringAsFixed(1)}万';
  return '${(n / 100000000).toStringAsFixed(1)}亿';
}

class ArtistRef {
  const ArtistRef({required this.id, required this.name, this.imageUrl = ''});

  final String id;
  final String name;
  final String imageUrl;

  factory ArtistRef.fromJson(Map<String, dynamic> j) => ArtistRef(
        id: _str(j['id']),
        name: _str(j['name']),
        imageUrl: _str(j['imageUrl']),
      );
}

class AlbumRef {
  const AlbumRef({
    required this.id,
    required this.name,
    this.imageUrl = '',
    this.coverAsset = '',
    this.artists = const [],
    this.released = '',
  });

  final String id;
  final String name;
  final String imageUrl;

  /// Local asset path of the cover, set only in screenshot captures.
  final String coverAsset;

  /// The album's artists and release date, when the plugin says
  /// (album() and search results carry them; track albums may not).
  final List<ArtistRef> artists;
  final String released;

  String get artistLine => artists.map((a) => a.name).join(' / ');

  factory AlbumRef.fromJson(Map<String, dynamic> j) => AlbumRef(
        id: _str(j['id']),
        name: _str(j['name']),
        imageUrl: _str(j['imageUrl']),
        coverAsset: _str(j['coverAsset']),
        artists: _mapList(j['artists']).map(ArtistRef.fromJson).toList(),
        released: _str(j['released']),
      );
}

class Track {
  const Track({
    required this.id,
    required this.name,
    this.artists = const [],
    this.album = const AlbumRef(id: '', name: ''),
    this.durationMs = 0,
    this.unavailable = false,
    this.localPath = '',
    this.showId = '',
  });

  final String id;
  final String name;
  final List<ArtistRef> artists;
  final AlbumRef album;
  final int durationMs;
  final bool unavailable;

  /// Filesystem path for a local song (see local_music.dart). Local
  /// tracks play from disk: the engine loads the file directly instead
  /// of resolving a plugin stream.
  final String localPath;

  /// Podcast episodes carry the show they belong to ('' for songs).
  final String showId;

  String get artistLine => artists.map((a) => a.name).join(' / ');
  String get durationText => formatDurationMs(durationMs);
  bool get isLocal => localPath.isNotEmpty;

  factory Track.fromJson(Map<String, dynamic> j) => Track(
        id: _str(j['id']),
        name: _str(j['name']),
        artists: _mapList(j['artists']).map(ArtistRef.fromJson).toList(),
        album: AlbumRef.fromJson(_map(j['album'])),
        durationMs: _int(j['duration']),
        unavailable: j['unavailable'] == true,
        showId: _str(j['showId']),
      );
}

class PlaylistItem {
  const PlaylistItem({
    required this.id,
    required this.name,
    this.imageUrl = '',
    this.coverAsset = '',
    this.description = '',
    this.owner = '',
    this.trackCount = 0,
    this.mine = false,
    this.saved = false,
  });

  final String id;
  final String name;
  final String imageUrl;

  /// Local asset path of the cover, set only in screenshot captures.
  final String coverAsset;
  final String description;
  final String owner;
  final int trackCount;

  /// Created by the signed-in listener / collected by them, when the
  /// plugin says (user playlists carry both flags).
  final bool mine;
  final bool saved;

  /// The line under a playlist card's name, as in MyGo: song count · owner.
  String get cardLine {
    final parts = <String>[
      if (trackCount > 0) '$trackCount 首',
      if (owner.isNotEmpty) owner,
    ];
    return parts.join(' · ');
  }

  factory PlaylistItem.fromJson(Map<String, dynamic> j) => PlaylistItem(
        id: _str(j['id']),
        name: _str(j['name']),
        imageUrl: _str(j['imageUrl']),
        coverAsset: _str(j['coverAsset']),
        description: _str(j['description']),
        owner: _str(j['owner']),
        trackCount: _int(j['trackCount']),
        mine: j['mine'] == true,
        saved: j['saved'] == true,
      );
}

class HomeLink {
  const HomeLink({required this.title, this.subtitle = '', this.page = ''});

  final String title;
  final String subtitle;
  final String page;

  factory HomeLink.fromJson(Map<String, dynamic> j) => HomeLink(
        title: _str(j['title']),
        subtitle: _str(j['subtitle']),
        page: _str(j['page']),
      );
}

class HomeSection {
  const HomeSection({this.title = '', this.links = const [], this.playlists = const []});

  final String title;
  final List<HomeLink> links;
  final List<PlaylistItem> playlists;

  factory HomeSection.fromJson(Map<String, dynamic> j) => HomeSection(
        title: _str(j['title']),
        links: _mapList(j['links']).map(HomeLink.fromJson).toList(),
        playlists: _mapList(j['playlists']).map(PlaylistItem.fromJson).toList(),
      );
}

/// Everything the home page shows, assembled from plugin calls.
class HomeData {
  const HomeData({
    this.title = '',
    this.subtitle = '',
    this.sections = const [],
    this.charts = const [],
    this.hotChart,
    this.hotTracks = const [],
  });

  /// Page title/subtitle from the plugin's home() (e.g. 发现音乐 / 网易云音乐).
  final String title;
  final String subtitle;
  final List<HomeSection> sections;

  /// Official chart playlists, from browse({page: 'charts'}).
  final List<PlaylistItem> charts;

  /// The chart whose tracks fill the song-list section (网易云热歌榜).
  final PlaylistItem? hotChart;
  final List<Track> hotTracks;

  /// What the player bar presents as the current song: the queue's first
  /// playable track, as the desktop app starts a queue at firstPlayable.
  Track? get nowPlaying {
    for (final t in hotTracks) {
      if (!t.unavailable) return t;
    }
    return hotTracks.isEmpty ? null : hotTracks.first;
  }

  bool get isEmpty =>
      sections.every((s) => s.links.isEmpty && s.playlists.isEmpty) &&
      charts.isEmpty &&
      hotTracks.isEmpty;
}

/// The signed-in listener, as the plugin's account() answers it.
class AccountInfo {
  const AccountInfo({required this.id, required this.name, this.imageUrl = ''});

  final String id;
  final String name;
  final String imageUrl;

  factory AccountInfo.fromJson(Map<String, dynamic> j) => AccountInfo(
        id: _str(j['id']),
        name: _str(j['name']),
        imageUrl: _str(j['imageUrl']),
      );
}

/// One page of tracks from a paged plugin call (liked songs).
class TrackPage {
  const TrackPage({this.tracks = const [], this.more = false});

  final List<Track> tracks;
  final bool more;

  factory TrackPage.fromJson(Map<String, dynamic> j) => TrackPage(
        tracks: _mapList(j['tracks']).map(Track.fromJson).toList(),
        more: j['more'] == true,
      );
}

/// A playlist with its songs: the plugin's playlist() answer.
class PlaylistDetail {
  const PlaylistDetail({required this.info, this.tracks = const []});

  final PlaylistItem info;
  final List<Track> tracks;

  factory PlaylistDetail.fromJson(Map<String, dynamic> j) => PlaylistDetail(
        info: PlaylistItem.fromJson(j),
        tracks: _mapList(j['tracks']).map(Track.fromJson).toList(),
      );
}

/// An album with its songs: the plugin's album() answer.
class AlbumDetail {
  const AlbumDetail({required this.album, this.tracks = const []});

  final AlbumRef album;
  final List<Track> tracks;

  factory AlbumDetail.fromJson(Map<String, dynamic> j) => AlbumDetail(
        album: AlbumRef.fromJson(_map(j['album'])),
        tracks: _mapList(j['tracks']).map(Track.fromJson).toList(),
      );
}

/// An artist with their hot songs and albums: artist()'s answer.
class ArtistDetail {
  const ArtistDetail({
    required this.artist,
    this.tracks = const [],
    this.albums = const [],
  });

  final ArtistRef artist;
  final List<Track> tracks;
  final List<AlbumRef> albums;

  factory ArtistDetail.fromJson(Map<String, dynamic> j) => ArtistDetail(
        artist: ArtistRef.fromJson(_map(j['artist'])),
        tracks: _mapList(j['tracks']).map(Track.fromJson).toList(),
        albums: _mapList(j['albums']).map(AlbumRef.fromJson).toList(),
      );
}

/// A podcast / radio show (the plugin's toShow shape).
class ShowItem {
  const ShowItem({
    required this.id,
    required this.name,
    this.imageUrl = '',
    this.description = '',
    this.publisher = '',
    this.episodeCount = 0,
    this.subscribed = false,
  });

  final String id;
  final String name;
  final String imageUrl;
  final String description;
  final String publisher;
  final int episodeCount;
  final bool subscribed;

  factory ShowItem.fromJson(Map<String, dynamic> j) => ShowItem(
        id: _str(j['id']),
        name: _str(j['name']),
        imageUrl: _str(j['imageUrl']),
        description: _str(j['description']),
        publisher: _str(j['publisher']),
        episodeCount: _int(j['episodeCount']),
        subscribed: j['subscribed'] == true,
      );
}

/// A show with one page of its episodes: the plugin's show() answer.
class ShowDetail {
  const ShowDetail({required this.show, this.episodes = const [], this.more = false});

  final ShowItem show;
  final List<Track> episodes;
  final bool more;

  factory ShowDetail.fromJson(Map<String, dynamic> j) => ShowDetail(
        show: ShowItem.fromJson(_map(j['show'])),
        episodes: _mapList(j['episodes']).map(Track.fromJson).toList(),
        more: j['more'] == true,
      );
}

/// One page of collected albums: savedAlbums()'s answer.
class SavedAlbumsResult {
  const SavedAlbumsResult({this.albums = const [], this.more = false});

  final List<AlbumRef> albums;
  final bool more;

  factory SavedAlbumsResult.fromJson(Map<String, dynamic> j) =>
      SavedAlbumsResult(
        albums: _mapList(j['albums']).map(AlbumRef.fromJson).toList(),
        more: j['more'] == true,
      );
}

/// The daily recommendations page: browse({page: 'daily'})'s sections
/// flattened to today's songs and recommended playlists.
class DailyData {
  const DailyData({this.tracks = const [], this.playlists = const []});

  final List<Track> tracks;
  final List<PlaylistItem> playlists;

  bool get isEmpty => tracks.isEmpty && playlists.isEmpty;
}

/// One search call's answer: the plugin fills only the requested kind's
/// list and says whether more pages exist.
class SearchResults {
  const SearchResults({
    this.kind = 'tracks',
    this.tracks = const [],
    this.playlists = const [],
    this.albums = const [],
    this.artists = const [],
    this.shows = const [],
    this.more = false,
  });

  final String kind;
  final List<Track> tracks;
  final List<PlaylistItem> playlists;
  final List<AlbumRef> albums;
  final List<ArtistRef> artists;
  final List<ShowItem> shows;
  final bool more;

  bool get isEmpty =>
      tracks.isEmpty &&
      playlists.isEmpty &&
      albums.isEmpty &&
      artists.isEmpty &&
      shows.isEmpty;

  factory SearchResults.fromJson(String kind, Map<String, dynamic> j) =>
      SearchResults(
        kind: kind,
        tracks: _mapList(j['tracks']).map(Track.fromJson).toList(),
        playlists: _mapList(j['playlists']).map(PlaylistItem.fromJson).toList(),
        albums: _mapList(j['albums']).map(AlbumRef.fromJson).toList(),
        artists: _mapList(j['artists']).map(ArtistRef.fromJson).toList(),
        shows: _mapList(j['shows']).map(ShowItem.fromJson).toList(),
        more: j['more'] == true,
      );
}

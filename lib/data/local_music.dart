import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'lyrics.dart';
import 'models.dart';

/// Access to the device's own music, for the 本地音乐 page.
///
/// Primary source: MediaStore, through the small platform channel in
/// MainActivity (title/artist/album/duration/path per song) — the same
/// index every Android player reads, HarmonyOS's Android layer
/// included. If MediaStore answers nothing (an OEM quirk, an empty
/// index), the fallback walks the standard music directories and reads
/// tags itself. Either way the songs become [Track]s with a
/// [Track.localPath] and play through the same audio engine.
class LocalMusicService {
  static const _channel =
      MethodChannel('club.easymusic.easymusic/media_store');

  static const audioExtensions = {
    'mp3', 'flac', 'm4a', 'aac', 'wav', 'ogg', 'oga', 'opus', 'wma', 'aif', 'aiff',
  };

  bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  /// Which permission guards the library on this device: READ_MEDIA_AUDIO
  /// from Android 13 (SDK 33), storage read below it. Null off Android.
  Future<Permission?> _permission() async {
    if (!_isAndroid) return null;
    var sdk = 33;
    try {
      sdk = await _channel.invokeMethod<int>('sdkInt') ?? 33;
    } catch (_) {
      // No channel answer (not our Android build): assume the modern
      // permission, which is also what the manifest declares first.
    }
    return sdk >= 33 ? Permission.audio : Permission.storage;
  }

  Future<PermissionStatus> permissionStatus() async {
    final permission = await _permission();
    if (permission == null) return PermissionStatus.granted;
    return permission.status;
  }

  Future<PermissionStatus> requestPermission() async {
    final permission = await _permission();
    if (permission == null) return PermissionStatus.granted;
    return permission.request();
  }

  Future<bool> openSettings() => openAppSettings();

  /// All device songs, title-sorted. Throws only when MediaStore and
  /// the directory walk both fail outright.
  Future<List<Track>> scan() async {
    var songs = <Track>[];
    try {
      songs = await _queryMediaStore();
    } catch (_) {
      songs = <Track>[];
    }
    if (songs.isEmpty) {
      songs = await scanDirectories(defaultRoots());
    }
    songs.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return songs;
  }

  Future<List<Track>> _queryMediaStore() async {
    if (!_isAndroid) return const [];
    final rows = await _channel.invokeListMethod<dynamic>('querySongs');
    if (rows == null) return const [];
    return [
      for (final raw in rows)
        if (raw is Map) _fromMediaStoreRow(raw.cast<dynamic, dynamic>()),
    ];
  }

  Track _fromMediaStoreRow(Map<dynamic, dynamic> row) {
    String text(String key) {
      final value = row[key]?.toString() ?? '';
      return value == '<unknown>' ? '' : value;
    }

    final path = text('path');
    final artist = text('artist');
    final album = text('album');
    return Track(
      id: 'local:m${row['id'] ?? path}',
      name: text('title').isEmpty ? _fileTitle(path) : text('title'),
      artists: artist.isEmpty
          ? const []
          : [ArtistRef(id: '', name: artist)],
      album: AlbumRef(id: '', name: album),
      durationMs: row['durationMs'] is num
          ? (row['durationMs'] as num).toInt()
          : 0,
      localPath: path,
    );
  }

  /// The directories the fallback walk covers: the standard music
  /// folders of the shared storage, plus a shallow sweep of its other
  /// top-level folders (depth-limited, hidden and Android/ skipped).
  List<String> defaultRoots() => const [
        '/storage/emulated/0/Music',
        '/storage/emulated/0/Download',
        '/storage/emulated/0',
      ];

  /// Timed lyrics from the song's same-name .lrc sibling, if it has one.
  Future<Lyrics?> lyricsFor(Track track) async {
    if (!track.isLocal) return null;
    final path = track.localPath;
    final dot = path.lastIndexOf('.');
    if (dot < 0) return null;
    final file = File('${path.substring(0, dot)}.lrc');
    try {
      if (!await file.exists()) return null;
      final lines = parseLrc(await file.readAsString());
      return lines.isEmpty ? null : Lyrics(lines);
    } catch (_) {
      return null;
    }
  }
}

/// The directory-walk fallback: collects audio files under [roots]
/// (each root's own depth budget applies — the broad storage root is
/// walked shallowly), reads their tags, and answers playable tracks.
/// Missing roots are skipped; unreadable files fall back to their
/// file name. Split out as a top-level function so tests can point it
/// at a fixture tree.
Future<List<Track>> scanDirectories(List<String> roots) async {
  final files = <File>[];
  final seen = <String>{};
  for (final rootPath in roots) {
    final root = Directory(rootPath);
    if (!await root.exists()) continue;
    final shallow = rootPath.split('/').where((s) => s.isNotEmpty).length <= 3;
    await for (final entity
        in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final path = entity.path;
      final relative = path.substring(rootPath.length);
      if (relative.split('/').any((part) => part.startsWith('.'))) continue;
      if (relative.contains('/Android/')) continue;
      if (shallow && relative.split('/').length > 4) continue;
      final ext = path.split('.').last.toLowerCase();
      if (!LocalMusicService.audioExtensions.contains(ext)) continue;
      if (seen.add(path)) files.add(entity);
    }
  }

  final tracks = <Track>[];
  for (var i = 0; i < files.length; i++) {
    tracks.add(await _trackFromFile(files[i]));
    // Tag parsing is synchronous CPU work; yield now and then so a
    // large library does not stall the UI thread for its whole scan.
    if (i % 20 == 19) await Future<void>.delayed(Duration.zero);
  }
  return tracks;
}

Future<Track> _trackFromFile(File file) async {
  var title = _fileTitle(file.path);
  var artist = '';
  var album = '';
  var durationMs = 0;
  try {
    final meta = readMetadata(file, getImage: false);
    if (meta.title != null && meta.title!.trim().isNotEmpty) {
      title = meta.title!.trim();
    }
    artist = meta.artist?.trim() ?? '';
    album = meta.album?.trim() ?? '';
    durationMs = meta.duration?.inMilliseconds ?? 0;
  } catch (_) {
    // No readable tags: the file name has to do.
  }
  return Track(
    id: 'local:f${file.path}',
    name: title,
    artists: artist.isEmpty ? const [] : [ArtistRef(id: '', name: artist)],
    album: AlbumRef(id: '', name: album),
    durationMs: durationMs,
    localPath: file.path,
  );
}

String _fileTitle(String path) {
  final base = path.split('/').last;
  final dot = base.lastIndexOf('.');
  return dot > 0 ? base.substring(0, dot) : base;
}

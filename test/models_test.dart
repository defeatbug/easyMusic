import 'dart:io';

import 'package:easymusic/data/local_music.dart';
import 'package:easymusic/data/lyrics.dart';
import 'package:easymusic/data/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Parsing tests for the shapes the v1 pages consume (account, search,
/// details), the LRC parser behind local lyrics and plugin LRC
/// answers, and the directory-scan fallback for local music.
void main() {
  group('plugin result models', () {
    test('AccountInfo parses the plugin account shape', () {
      final a = AccountInfo.fromJson(const {
        'id': '123',
        'name': '听歌的人',
        'imageUrl': 'https://p1.music.126.net/a.jpg',
      });
      expect(a.id, '123');
      expect(a.name, '听歌的人');
      expect(a.imageUrl, contains('music.126.net'));
    });

    test('PlaylistDetail parses info plus tracks', () {
      final d = PlaylistDetail.fromJson(const {
        'id': '9',
        'name': '热歌榜',
        'trackCount': 2,
        'tracks': [
          {
            'id': '1',
            'name': '歌一',
            'artists': [
              {'id': '7', 'name': '歌手甲'}
            ],
            'album': {'id': '3', 'name': '专辑一', 'imageUrl': 'https://x/y.jpg'},
            'duration': 123000,
          },
          {'id': '2', 'name': '歌二', 'unavailable': true},
        ],
      });
      expect(d.info.name, '热歌榜');
      expect(d.tracks, hasLength(2));
      expect(d.tracks.first.artistLine, '歌手甲');
      expect(d.tracks.first.durationText, '2:03');
      expect(d.tracks.last.unavailable, isTrue);
    });

    test('SearchResults fills only the requested kind', () {
      final r = SearchResults.fromJson('playlists', const {
        'playlists': [
          {'id': '5', 'name': '歌单五', 'trackCount': 30}
        ],
        'more': true,
      });
      expect(r.playlists.single.name, '歌单五');
      expect(r.tracks, isEmpty);
      expect(r.more, isTrue);
      expect(r.isEmpty, isFalse);
    });

    test('TrackPage and SavedAlbumsResult parse their pages', () {
      final page = TrackPage.fromJson(const {
        'tracks': [
          {'id': '1', 'name': '喜欢的一首'}
        ],
        'more': true,
      });
      expect(page.tracks.single.name, '喜欢的一首');
      expect(page.more, isTrue);

      final albums = SavedAlbumsResult.fromJson(const {
        'albums': [
          {
            'id': '8',
            'name': '专辑八',
            'artists': [
              {'id': '1', 'name': '某人'}
            ],
            'released': '2020-05-01',
          }
        ],
        'more': false,
      });
      expect(albums.albums.single.artistLine, '某人');
      expect(albums.albums.single.released, '2020-05-01');
    });

    test('ShowDetail parses episodes as tracks with a show id', () {
      final d = ShowDetail.fromJson(const {
        'show': {'id': '66', 'name': '播客六', 'publisher': '主播'},
        'episodes': [
          {'id': '101', 'name': '第一期', 'showId': '66'}
        ],
        'more': true,
      });
      expect(d.show.publisher, '主播');
      expect(d.episodes.single.showId, '66');
      expect(d.more, isTrue);
    });

    test('a local track knows it is local', () {
      const t = Track(id: 'local:m1', name: '本地歌', localPath: '/s/a.mp3');
      expect(t.isLocal, isTrue);
      const online = Track(id: '1', name: '在线歌');
      expect(online.isLocal, isFalse);
    });
  });

  group('parseLrc', () {
    test('parses stamps, fractions and repeated stamps', () {
      final lines = parseLrc('''
[ti:标题行会被跳过]
[00:01.00]第一句
[00:05.50][00:10.25]重复的一句
[01:00.123]一分钟处
没有时间戳的一行
''');
      expect(lines, hasLength(4));
      expect(lines[0].startMs, 1000);
      expect(lines[0].text, '第一句');
      expect(lines[1].startMs, 5500);
      expect(lines[2].startMs, 10250);
      expect(lines[2].text, '重复的一句');
      expect(lines[3].startMs, 60123);
    });

    test('Lyrics.indexAt finds the current line', () {
      const lyrics = Lyrics([
        LyricLine(startMs: 1000, text: 'a'),
        LyricLine(startMs: 5000, text: 'b'),
      ]);
      expect(lyrics.indexAt(0), -1);
      expect(lyrics.indexAt(1000), 0);
      expect(lyrics.indexAt(4999), 0);
      expect(lyrics.indexAt(9000), 1);
    });
  });

  group('scanDirectories (local fallback)', () {
    test('collects audio files, skips hidden and non-audio', () async {
      final dir = await Directory.systemTemp.createTemp('scan_test');
      addTearDown(() => dir.delete(recursive: true));
      await File('${dir.path}/Song One.mp3').writeAsBytes([0, 1, 2]);
      await Directory('${dir.path}/sub').create();
      await File('${dir.path}/sub/track.flac').writeAsBytes([0]);
      await File('${dir.path}/notes.txt').writeAsString('not audio');
      await Directory('${dir.path}/.hidden').create();
      await File('${dir.path}/.hidden/secret.mp3').writeAsBytes([0]);
      await Directory('${dir.path}/Android').create();
      await File('${dir.path}/Android/app.mp3').writeAsBytes([0]);

      final tracks = await scanDirectories([dir.path]);
      final names = tracks.map((t) => t.name).toSet();
      expect(names, {'Song One', 'track'});
      for (final t in tracks) {
        expect(t.isLocal, isTrue);
        expect(t.localPath, startsWith(dir.path));
      }
    });

    test('a missing root is skipped quietly', () async {
      expect(await scanDirectories(['/no/such/dir/anywhere']), isEmpty);
    });
  });
}

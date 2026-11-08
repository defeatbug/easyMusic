/// Lyrics in the shape the now-playing page renders: timed lines. The
/// NetEase plugin's lyrics() answers word-timed lines when it has them
/// ({start, text, translation?} in ms) and a plain LRC otherwise; local
/// songs may carry a same-name .lrc file. Both normalize to [Lyrics].
class LyricLine {
  const LyricLine({required this.startMs, required this.text, this.translation = ''});

  final int startMs;
  final String text;
  final String translation;

  factory LyricLine.fromJson(Map<String, dynamic> j) => LyricLine(
        startMs: j['start'] is num ? (j['start'] as num).toInt() : 0,
        text: j['text']?.toString() ?? '',
        translation: j['translation']?.toString() ?? '',
      );
}

class Lyrics {
  const Lyrics(this.lines);

  final List<LyricLine> lines;

  bool get isEmpty => lines.isEmpty;

  /// Index of the line current at [positionMs] (the last line whose
  /// start has passed), or -1 before the first line.
  int indexAt(int positionMs) {
    var index = -1;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].startMs <= positionMs) {
        index = i;
      } else {
        break;
      }
    }
    return index;
  }
}

final _lrcStamp = RegExp(r'\[(\d+):(\d+)(?:[.:](\d+))?\]');

/// Parses LRC text into timed lines: every [mm:ss.xx] stamp on a row
/// yields a line with the row's text (a row with several stamps repeats,
/// as LRC intends). Metadata tags ([ti:], [ar:]…) and untimed rows are
/// skipped; the result is sorted by start.
List<LyricLine> parseLrc(String text) {
  final lines = <LyricLine>[];
  for (final row in text.split(RegExp(r'\r?\n'))) {
    final stamps = _lrcStamp.allMatches(row).toList();
    if (stamps.isEmpty) continue;
    final lyric = row.replaceAll(_lrcStamp, '').trim();
    if (lyric.isEmpty) continue;
    for (final m in stamps) {
      final minutes = int.parse(m.group(1)!);
      final seconds = int.parse(m.group(2)!);
      var fraction = m.group(3) ?? '';
      final ms = fraction.isEmpty
          ? 0
          : int.parse(fraction.padRight(3, '0').substring(0, 3));
      lines.add(LyricLine(
        startMs: minutes * 60000 + seconds * 1000 + ms,
        text: lyric,
      ));
    }
  }
  lines.sort((a, b) => a.startMs.compareTo(b.startMs));
  return lines;
}

import 'package:flutter/material.dart';

import '../audio/audio_engine.dart';
import '../data/models.dart';
import 'theme.dart';

/// A square cover: local capture asset when present (screenshot builds),
/// network image otherwise, with the desktop app's neutral placeholder —
/// a hover-tinted box with a note icon — while loading or on error.
class CoverImage extends StatelessWidget {
  const CoverImage({
    super.key,
    required this.imageUrl,
    this.coverAsset = '',
    required this.size,
    this.radius = 10,
    this.iconSize = 40,
  });

  final String imageUrl;
  final String coverAsset;
  final double size;
  final double radius;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: size,
      height: size,
      color: Palette.hover,
      child: Icon(Icons.music_note, size: iconSize, color: Palette.faint),
    );
    Widget image;
    if (coverAsset.isNotEmpty) {
      image = Image.asset(
        coverAsset,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => placeholder,
      );
    } else if (imageUrl.isNotEmpty) {
      // Ask NetEase's CDN for a thumbnail near the display size.
      final url = imageUrl.contains('?')
          ? imageUrl
          : '$imageUrl?param=${(size * 2).round()}y${(size * 2).round()}';
      image = Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => placeholder,
        loadingBuilder: (_, child, progress) =>
            progress == null ? child : placeholder,
      );
    } else {
      image = placeholder;
    }
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Palette.cardShade,
            blurRadius: 8,
            spreadRadius: -2,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: image,
      ),
    );
  }
}

/// A playlist's card, as on the desktop home: square cover, name below in
/// 13/500 over two lines, then the count · owner line in muted 12.
/// Tappable when [onTap] is given (opens the playlist's detail page).
class PlaylistCard extends StatelessWidget {
  const PlaylistCard({
    super.key,
    required this.playlist,
    required this.width,
    this.onTap,
  });

  final PlaylistItem playlist;
  final double width;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CoverImage(
            imageUrl: playlist.imageUrl,
            coverAsset: playlist.coverAsset,
            size: width,
          ),
          const SizedBox(height: 10),
          Text(
            playlist.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.35,
              color: Palette.text,
            ),
          ),
          if (playlist.cardLine.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              playlist.cardLine,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Palette.muted),
            ),
          ],
        ],
      ),
    );
    if (onTap == null) return card;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: card,
    );
  }
}

/// An album's card, same shape as [PlaylistCard]: cover, name, then the
/// artists · year line.
class AlbumCard extends StatelessWidget {
  const AlbumCard({
    super.key,
    required this.album,
    required this.width,
    this.onTap,
  });

  final AlbumRef album;
  final double width;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final line = [
      if (album.artistLine.isNotEmpty) album.artistLine,
      if (album.released.isNotEmpty) album.released.substring(0, 4),
    ].join(' · ');
    final card = SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CoverImage(
            imageUrl: album.imageUrl,
            coverAsset: album.coverAsset,
            size: width,
          ),
          const SizedBox(height: 10),
          Text(
            album.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.35,
              color: Palette.text,
            ),
          ),
          if (line.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              line,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Palette.muted),
            ),
          ],
        ],
      ),
    );
    if (onTap == null) return card;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: card,
    );
  }
}

/// One artist row: round avatar, name, a chevron. Opens the artist page.
class ArtistRow extends StatelessWidget {
  const ArtistRow({super.key, required this.artist, this.onTap});

  final ArtistRef artist;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          CoverImage(
            imageUrl: artist.imageUrl,
            size: 44,
            radius: 22,
            iconSize: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              artist.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Palette.text,
              ),
            ),
          ),
          const Icon(Icons.chevron_right, size: 18, color: Palette.faint),
        ],
      ),
    );
    if (onTap == null) return row;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: row,
      ),
    );
  }
}

/// One show (podcast) row: cover, name over publisher · episode count.
class ShowRow extends StatelessWidget {
  const ShowRow({super.key, required this.show, this.onTap});

  final ShowItem show;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final line = [
      if (show.publisher.isNotEmpty) show.publisher,
      if (show.episodeCount > 0) '${show.episodeCount} 集',
    ].join(' · ');
    final row = Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          CoverImage(imageUrl: show.imageUrl, size: 48, radius: 8, iconSize: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  show.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: Palette.text,
                  ),
                ),
                if (line.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    line,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Palette.muted),
                  ),
                ],
              ],
            ),
          ),
          const Icon(Icons.chevron_right, size: 18, color: Palette.faint),
        ],
      ),
    );
    if (onTap == null) return row;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: row,
      ),
    );
  }
}

/// One song row: number, small cover, name over artists, duration and a
/// heart at the right — the desktop track list's shape. Playable rows
/// take an [onTap] (tap to play); unavailable rows never do and stay
/// dimmed with their 「暂不可播」 tag. The row the engine is currently
/// on shows a play/pause glyph in place of its number.
class TrackRow extends StatelessWidget {
  const TrackRow({
    super.key,
    required this.index,
    required this.track,
    this.onTap,
    this.isCurrent = false,
    this.isPlaying = false,
  });

  final int index;
  final Track track;
  final VoidCallback? onTap;
  final bool isCurrent;
  final bool isPlaying;

  @override
  Widget build(BuildContext context) {
    final dim = track.unavailable;
    final row = Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: isCurrent ? Palette.hover : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: isCurrent
                ? Icon(
                    isPlaying ? Icons.pause : Icons.play_arrow,
                    size: 16,
                    color: Palette.accent,
                  )
                : Text(
                    '${index + 1}',
                    style:
                        const TextStyle(fontSize: 12.5, color: Palette.faint),
                  ),
          ),
          CoverImage(
            imageUrl: track.album.imageUrl,
            coverAsset: track.album.coverAsset,
            size: 40,
            radius: 6,
            iconSize: 18,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: dim ? Palette.muted : Palette.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  track.artistLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Palette.muted),
                ),
              ],
            ),
          ),
          if (dim)
            const Padding(
              padding: EdgeInsets.only(right: 10),
              child: Text(
                '暂不可播',
                style: TextStyle(fontSize: 11.5, color: Palette.faint),
              ),
            ),
          Text(
            track.durationText,
            style: const TextStyle(fontSize: 12, color: Palette.muted),
          ),
          const SizedBox(width: 6),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.favorite_border, size: 17),
            color: Palette.muted,
            splashRadius: 16,
            tooltip: '喜欢',
          ),
        ],
      ),
    );
    if (onTap == null || dim) return row;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: row,
      ),
    );
  }
}

/// A section title on a page: 19/700, as in the desktop app.
class SectionTitle extends StatelessWidget {
  const SectionTitle({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w700,
          color: Palette.text,
          letterSpacing: -0.3,
        ),
      ),
    );
  }
}

/// How many card columns of at least [min] DIPs fit across [innerWidth],
/// the desktop app's columns() rule.
int cardColumns(double innerWidth, double min) {
  final n = ((innerWidth + 20) / (min + 20)).floor();
  return n < 2 ? 2 : n;
}

/// A responsive grid of playlist cards (the home page's card rule),
/// each opening its detail page through [onTap].
class PlaylistCardGrid extends StatelessWidget {
  const PlaylistCardGrid({
    super.key,
    required this.playlists,
    required this.onTap,
    this.limit,
  });

  final List<PlaylistItem> playlists;
  final void Function(PlaylistItem playlist) onTap;
  final int? limit;

  @override
  Widget build(BuildContext context) {
    final shown =
        limit == null ? playlists : playlists.take(limit!).toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final inner = constraints.maxWidth;
        final cols = cardColumns(inner, 168);
        final cardW = (inner - (cols - 1) * 20) / cols;
        return Wrap(
          spacing: 20,
          runSpacing: 28,
          children: [
            for (final p in shown)
              PlaylistCard(playlist: p, width: cardW, onTap: () => onTap(p)),
          ],
        );
      },
    );
  }
}

/// A responsive grid of album cards, same rule as [PlaylistCardGrid].
class AlbumCardGrid extends StatelessWidget {
  const AlbumCardGrid({super.key, required this.albums, required this.onTap});

  final List<AlbumRef> albums;
  final void Function(AlbumRef album) onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final inner = constraints.maxWidth;
        final cols = cardColumns(inner, 168);
        final cardW = (inner - (cols - 1) * 20) / cols;
        return Wrap(
          spacing: 20,
          runSpacing: 28,
          children: [
            for (final a in albums)
              AlbumCard(album: a, width: cardW, onTap: () => onTap(a)),
          ],
        );
      },
    );
  }
}

/// A list of song rows bound to the engine: the current row is
/// highlighted, a tap starts the list as the queue at that row, and
/// unavailable rows stay inert — the rule every track list in the app
/// follows (home chart, detail pages, search, liked, local).
class TrackRows extends StatelessWidget {
  const TrackRows({super.key, required this.tracks, required this.engine});

  final List<Track> tracks;
  final AudioEngine engine;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: engine,
      builder: (context, _) => Column(
        children: [
          for (var i = 0; i < tracks.length; i++)
            TrackRow(
              index: i,
              track: tracks[i],
              isCurrent: engine.currentTrack?.id == tracks[i].id &&
                  engine.currentTrack?.localPath == tracks[i].localPath,
              isPlaying: engine.isPlaying &&
                  engine.currentTrack?.id == tracks[i].id &&
                  engine.currentTrack?.localPath == tracks[i].localPath,
              onTap: tracks[i].unavailable
                  ? null
                  : () => engine.playQueue(tracks, i),
            ),
        ],
      ),
    );
  }
}

/// The app's honest empty state: a soft icon tile, a title, one line.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.line,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String line;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Palette.hover,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(icon, size: 32, color: Palette.muted),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
                color: Palette.text,
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(
                line,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13.5,
                  height: 1.45,
                  color: Palette.muted,
                ),
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              FilledButton(
                onPressed: onAction,
                style: FilledButton.styleFrom(
                  backgroundColor: Palette.accent,
                  foregroundColor: Palette.onAccent,
                ),
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A page-level loading spinner with a line of text.
class LoadingState extends StatelessWidget {
  const LoadingState({super.key, this.line = '正在加载…'});

  final String line;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: Palette.accent),
          const SizedBox(height: 16),
          Text(line,
              style: const TextStyle(fontSize: 13, color: Palette.muted)),
        ],
      ),
    );
  }
}

/// The standard page padding for content pages (the home page's rule:
/// generous on desktop, tighter at phone widths).
double pagePadding(BuildContext context) =>
    MediaQuery.sizeOf(context).width < mobileBreakpoint ? 20.0 : pagePad;

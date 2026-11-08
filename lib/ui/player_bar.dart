import 'package:flutter/material.dart';

import '../audio/audio_engine.dart';
import '../data/models.dart';
import 'theme.dart';
import 'widgets.dart';

/// The bar along the foot of the content, 84 tall as in the desktop app:
/// what plays at the left (48 cover, name over artists, a heart), the
/// transport over its progress in the middle 440, and lyrics / queue /
/// volume at the right.
///
/// Wired to the [AudioEngine]: transport buttons drive it, the progress
/// slider follows the real position and seeks on drag, and the play
/// button becomes a spinner while a track resolves or buffers. With no
/// playback wired (screenshot build) the bar presents the queue's first
/// playable song and the controls stay inert.
class PlayerBar extends StatelessWidget {
  const PlayerBar({super.key, required this.engine, this.onOpenNowPlaying});

  final AudioEngine engine;

  /// Tapping the now-playing block opens the full-screen player.
  final VoidCallback? onOpenNowPlaying;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: playerBarHeight,
      decoration: const BoxDecoration(
        color: Palette.bg,
        border: Border(top: BorderSide(color: Palette.hairline)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: ListenableBuilder(
        listenable: engine,
        builder: (context, _) {
          final track = engine.currentTrack;
          return LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 880;
              return Row(
                children: [
                  // What plays.
                  Expanded(flex: 3, child: _nowPlaying(track)),
                  const SizedBox(width: 12),
                  // Controls over the progress, centred and never wider
                  // than the desktop bar's 440.
                  Expanded(
                    flex: 4,
                    child: Align(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 440),
                        child: _transport(track),
                      ),
                    ),
                  ),
                  // Lyrics, queue and volume — only where they fit.
                  if (wide) ...[
                    const SizedBox(width: 12),
                    Expanded(flex: 3, child: _rightSide(context)),
                  ],
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _transport(Track? track) {
    final canPlay = engine.canPlay && track != null;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _icon(
              Icons.shuffle,
              size: 17,
              color: engine.shuffle ? Palette.accent : Palette.muted,
              onTap: canPlay ? () => engine.setShuffle(!engine.shuffle) : () {},
            ),
            const SizedBox(width: 10),
            _icon(
              Icons.skip_previous,
              size: 23,
              onTap: canPlay ? () => engine.previous() : () {},
            ),
            const SizedBox(width: 6),
            if (engine.isBuffering)
              const SizedBox(
                width: 38,
                height: 38,
                child: Padding(
                  padding: EdgeInsets.all(7),
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Palette.accent,
                  ),
                ),
              )
            else
              _icon(
                engine.isPlaying ? Icons.pause : Icons.play_arrow,
                size: 30,
                onTap: canPlay ? () => engine.togglePlay() : () {},
              ),
            const SizedBox(width: 6),
            _icon(
              Icons.skip_next,
              size: 23,
              onTap: canPlay ? () => engine.next() : () {},
            ),
            const SizedBox(width: 10),
            _icon(
              engine.repeat == LoopMode.one ? Icons.repeat_one : Icons.repeat,
              size: 17,
              color:
                  engine.repeat != LoopMode.off ? Palette.accent : Palette.muted,
              onTap: canPlay ? () => engine.cycleRepeat() : () {},
            ),
          ],
        ),
        const SizedBox(height: 2),
        _progress(track),
      ],
    );
  }

  /// Position text, a seekable slider, total time. The position comes
  /// from the player's own stream (smooth, independent of the engine's
  /// change notifications); the total falls back to the track's plugin
  /// duration until the player reports its own.
  Widget _progress(Track? track) {
    return StreamBuilder<Duration>(
      stream: engine.positionStream,
      builder: (context, posSnap) {
        final position = posSnap.data ?? Duration.zero;
        return StreamBuilder<Duration?>(
          stream: engine.durationStream,
          builder: (context, durSnap) {
            final total = durSnap.data ??
                Duration(milliseconds: track?.durationMs ?? 0);
            final maxMs = total.inMilliseconds.toDouble();
            final valueMs = position.inMilliseconds
                .toDouble()
                .clamp(0.0, maxMs > 0 ? maxMs : 0.0);
            return Row(
              children: [
                SizedBox(
                  width: 34,
                  child: Text(
                    formatDurationMs(position.inMilliseconds),
                    textAlign: TextAlign.right,
                    style:
                        const TextStyle(fontSize: 10.5, color: Palette.faint),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 5),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 10),
                      activeTrackColor: Palette.accent,
                      inactiveTrackColor: Palette.press,
                      thumbColor: Palette.accent,
                    ),
                    child: Slider(
                      value: maxMs > 0 ? valueMs : 0,
                      max: maxMs > 0 ? maxMs : 1,
                      onChanged: engine.canPlay && maxMs > 0
                          ? (v) => engine
                              .seek(Duration(milliseconds: v.round()))
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 34,
                  child: Text(
                    formatDurationMs(total.inMilliseconds),
                    style:
                        const TextStyle(fontSize: 10.5, color: Palette.faint),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _rightSide(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        _icon(Icons.lyrics_outlined, size: 17, color: Palette.muted, onTap: () {}),
        _icon(Icons.queue_music, size: 18, color: Palette.muted, onTap: () {}),
        _icon(
          engine.volume == 0 ? Icons.volume_off : Icons.volume_up,
          size: 17,
          color: Palette.text.withValues(alpha: 0.75),
          onTap: () => engine.setVolume(engine.volume == 0 ? 0.8 : 0),
        ),
        SizedBox(
          width: 90,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 0),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 0),
              activeTrackColor: Palette.text.withValues(alpha: 0.75),
              inactiveTrackColor: Palette.press,
            ),
            child: Slider(
              value: engine.volume,
              onChanged:
                  engine.canPlay ? (v) => engine.setVolume(v) : null,
            ),
          ),
        ),
      ],
    );
  }

  Widget _nowPlaying(Track? track) {
    if (track == null) {
      return Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Palette.hover,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.music_note, size: 18, color: Palette.faint),
          ),
          const SizedBox(width: 12),
          const Text('未播放',
              style: TextStyle(fontSize: 13, color: Palette.muted)),
        ],
      );
    }
    final row = Row(
      children: [
        CoverImage(
          imageUrl: track.album.imageUrl,
          coverAsset: track.album.coverAsset,
          size: 48,
          radius: 8,
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
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: Palette.text,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                track.artistLine,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Palette.muted),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () {},
          icon: const Icon(Icons.favorite_border, size: 17),
          color: Palette.muted,
          splashRadius: 16,
          tooltip: '喜欢',
        ),
      ],
    );
    final open = onOpenNowPlaying;
    if (open == null) return row;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: open,
      child: row,
    );
  }

  Widget _icon(IconData icon,
      {required double size, Color color = Palette.text, required VoidCallback onTap}) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, size: size),
      color: color,
      splashRadius: size * 0.9,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
    );
  }
}

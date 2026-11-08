import 'package:flutter/material.dart';

import '../audio/audio_engine.dart';
import 'theme.dart';
import 'widgets.dart';

/// The phone layout's player: a slim bar that sits directly above the
/// bottom tab bar — the current song's cover, name over artists, play /
/// pause and next, with the progress as one thin line along the bar's
/// top edge. The desktop bar's secondary controls (shuffle, repeat,
/// lyrics, queue, volume) are left out; there is not room for them at
/// phone widths and they are not needed to run the queue.
///
/// Wired to the [AudioEngine]: play / pause and next drive it, the top
/// line follows the real position, and the play button becomes a
/// spinner while a track resolves or buffers. With no playback wired
/// (screenshot build) it presents the queue's first song, inert.
class MiniPlayerBar extends StatelessWidget {
  const MiniPlayerBar({super.key, required this.engine, this.onOpenNowPlaying});

  final AudioEngine engine;

  /// Tapping the bar (outside its buttons) opens the full-screen player.
  final VoidCallback? onOpenNowPlaying;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Palette.bg,
      child: ListenableBuilder(
        listenable: engine,
        builder: (context, _) {
          final track = engine.currentTrack;
          final canPlay = engine.canPlay && track != null;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // The progress as a single thin line along the top edge.
              Container(
                height: 2,
                color: Palette.press,
                alignment: Alignment.centerLeft,
                child: StreamBuilder<Duration>(
                  stream: engine.positionStream,
                  builder: (context, posSnap) {
                    return StreamBuilder<Duration?>(
                      stream: engine.durationStream,
                      builder: (context, durSnap) {
                        final total = durSnap.data ??
                            Duration(milliseconds: track?.durationMs ?? 0);
                        final pos = posSnap.data ?? Duration.zero;
                        final totalMs = total.inMilliseconds;
                        final frac = totalMs > 0
                            ? (pos.inMilliseconds / totalMs)
                                .clamp(0.0, 1.0)
                            : 0.0;
                        return FractionallySizedBox(
                          widthFactor: frac,
                          child: Container(color: Palette.accent),
                        );
                      },
                    );
                  },
                ),
              ),
              SizedBox(
                height: 60,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: track != null ? onOpenNowPlaying : null,
                  child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      if (track != null)
                        CoverImage(
                          imageUrl: track.album.imageUrl,
                          coverAsset: track.album.coverAsset,
                          size: 44,
                          radius: 6,
                          iconSize: 16,
                        )
                      else
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Palette.hover,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(Icons.music_note,
                              size: 16, color: Palette.faint),
                        ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: track == null
                            ? const Text(
                                '未播放',
                                style: TextStyle(
                                    fontSize: 13, color: Palette.muted),
                              )
                            : Column(
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
                                  const SizedBox(height: 2),
                                  Text(
                                    track.artistLine,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 12, color: Palette.muted),
                                  ),
                                ],
                              ),
                      ),
                      if (engine.isBuffering)
                        const SizedBox(
                          width: 40,
                          height: 40,
                          child: Padding(
                            padding: EdgeInsets.all(9),
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Palette.accent,
                            ),
                          ),
                        )
                      else
                        IconButton(
                          onPressed:
                              canPlay ? () => engine.togglePlay() : null,
                          icon: Icon(
                              engine.isPlaying
                                  ? Icons.pause
                                  : Icons.play_arrow,
                              size: 30),
                          color: Palette.text,
                          splashRadius: 20,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 40, minHeight: 40),
                        ),
                      IconButton(
                        onPressed: canPlay ? () => engine.next() : null,
                        icon: const Icon(Icons.skip_next, size: 24),
                        color: Palette.text,
                        splashRadius: 20,
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 40, minHeight: 40),
                      ),
                    ],
                  ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

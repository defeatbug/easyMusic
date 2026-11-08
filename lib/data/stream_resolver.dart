import 'models.dart';

/// A track's playable stream, as resolved by a plugin's stream() call
/// (the shape M0 verified against the NetEase plugin: a signed CDN URL
/// plus format/bitrate/size; some plugins also hand back request headers
/// the URL must be fetched with).
class ResolvedStream {
  const ResolvedStream({
    required this.url,
    this.type = '',
    this.bitRate = 0,
    this.size = 0,
    this.headers = const {},
  });

  final String url;

  /// Container/codec label from the plugin ('mp3', 'flac', …).
  final String type;
  final int bitRate;
  final int size;

  /// Extra headers the stream URL expects (empty for most plugins).
  final Map<String, String> headers;
}

/// Turns a [Track] into a playable [ResolvedStream]. Kept separate from
/// [HomeRepository]: the live plugin repository implements it, the
/// screenshot capture repository deliberately does not (playback is not
/// part of the replay), so the audio engine simply receives no resolver
/// there and stays inert.
abstract class StreamResolver {
  Future<ResolvedStream> resolveStream(Track track);
}

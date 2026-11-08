package club.easymusic.easymusic

import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.concurrent.thread

// AudioServiceActivity (a FlutterActivity) is required by audio_service
// so the activity and the background audio service stay in sync. This
// subclass also serves the local-music library: a small channel that
// queries MediaStore for the device's songs (title/artist/album/
// duration/path), which the Dart side turns into playable tracks.
class MainActivity : AudioServiceActivity() {
    private val mediaChannel = "club.easymusic.easymusic/media_store"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, mediaChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "sdkInt" -> result.success(Build.VERSION.SDK_INT)
                    "getCookies" -> {
                        // The Cookie header a request to this URL would
                        // send, from the WebView's own cookie store —
                        // HttpOnly cookies included, which is what the
                        // web sign-in flow waits for (MUSIC_U). Must be
                        // read on the main thread; channel handlers are.
                        val url = call.arguments as? String ?: ""
                        val header = try {
                            android.webkit.CookieManager.getInstance()
                                .getCookie(url) ?: ""
                        } catch (e: Exception) {
                            ""
                        }
                        result.success(header)
                    }
                    "querySongs" -> thread {
                        val main = Handler(Looper.getMainLooper())
                        try {
                            val songs = querySongs()
                            main.post { result.success(songs) }
                        } catch (e: Exception) {
                            main.post {
                                result.error("mediastore", e.message, null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun querySongs(): List<Map<String, Any?>> {
        val projection = arrayOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.DURATION,
            MediaStore.Audio.Media.DATA,
        )
        val songs = mutableListOf<Map<String, Any?>>()
        contentResolver.query(
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
            projection,
            "${MediaStore.Audio.Media.IS_MUSIC} != 0",
            null,
            "${MediaStore.Audio.Media.TITLE} ASC",
        )?.use { cursor ->
            val idCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
            val titleCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
            val artistCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
            val albumCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM)
            val durationCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
            val dataCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATA)
            while (cursor.moveToNext()) {
                val path = cursor.getString(dataCol) ?: continue
                if (path.isEmpty()) continue
                songs.add(
                    mapOf(
                        "id" to cursor.getLong(idCol),
                        "title" to (cursor.getString(titleCol) ?: ""),
                        "artist" to (cursor.getString(artistCol) ?: ""),
                        "album" to (cursor.getString(albumCol) ?: ""),
                        "durationMs" to cursor.getLong(durationCol),
                        "path" to path,
                    ),
                )
            }
        }
        return songs
    }
}

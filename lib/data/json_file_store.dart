import 'dart:convert';
import 'dart:io';

/// A JSON file holding one string-keyed map — the on-disk form of the
/// plugin host's storage and of the app's plugin settings. Writes go to
/// a sibling temp file renamed over the target, so a crash mid-write
/// leaves the previous good copy in place; reads tolerate a missing or
/// corrupt file by answering an empty map.
class JsonFileStore {
  JsonFileStore(this.file);

  final File file;

  Future<Map<String, dynamic>> load() async {
    try {
      if (!await file.exists()) return <String, dynamic>{};
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } catch (_) {
      // Corrupt or unreadable: start over rather than crash the host.
    }
    return <String, dynamic>{};
  }

  Future<void> save(Map<String, dynamic> data) async {
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(data), flush: true);
    await tmp.rename(file.path);
  }
}

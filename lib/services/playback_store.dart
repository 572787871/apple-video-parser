import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'file_utils.dart';

class PlaybackStore {
  Future<Duration> positionFor(String path) async {
    final values = await _read();
    final item = values[FileUtils.stableKey(path)];
    if (item is! Map) return Duration.zero;
    return Duration(
        milliseconds: int.tryParse('${item['positionMs'] ?? 0}') ?? 0);
  }

  Future<void> save({
    required String path,
    required Duration position,
    required Duration duration,
  }) async {
    final values = await _read();
    final key = FileUtils.stableKey(path);
    if (duration.inMilliseconds <= 0 ||
        position.inMilliseconds < 5000 ||
        position.inMilliseconds > duration.inMilliseconds - 5000) {
      values.remove(key);
    } else {
      values[key] = {
        'positionMs': position.inMilliseconds,
        'durationMs': duration.inMilliseconds,
        'updatedAt': DateTime.now().toIso8601String(),
      };
    }
    await _write(values);
  }

  Future<Map<String, dynamic>> _read() async {
    final file = await _file();
    if (!await file.exists()) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(await file.readAsString());
      return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<void> _write(Map<String, dynamic> values) async {
    final file = await _file();
    await file.writeAsString(jsonEncode(values));
  }

  Future<File> _file() async {
    final docs = await getApplicationDocumentsDirectory();
    return File('${docs.path}/playback_positions.json');
  }
}

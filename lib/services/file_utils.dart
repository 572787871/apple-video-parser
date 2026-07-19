import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/video_resource.dart';

class FileUtils {
  static Future<Directory> videosDirectory() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'videos'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<Directory> thumbnailsDirectory() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'thumbnails'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<Directory> videoPageDirectory(VideoResource resource) async {
    final root = await videosDirectory();
    final pageUrl =
        resource.pageUrl.isNotEmpty ? resource.pageUrl : resource.url;
    final uri = Uri.tryParse(pageUrl);
    final host = uri?.host ?? 'video';
    final baseTitle = resource.title.trim().isEmpty ? host : resource.title;
    final safeTitle = safeFileName(baseTitle, fallback: host);
    final key = stableKey(pageUrl).substring(0, 8);
    final dir = Directory(p.join(root.path, '$safeTitle-$key'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final thumbs = Directory(p.join(dir.path, 'thumbnails'));
    if (!await thumbs.exists()) {
      await thumbs.create(recursive: true);
    }
    return dir;
  }

  static String stableKey(String value) {
    var hash = 0xcbf29ce484222325;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x100000001b3) & 0x7fffffffffffffff;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  static String safeFileName(String value, {String fallback = 'video'}) {
    final cleaned = value
        .replaceAll(RegExp(r'[\\/:*?"<>|\r\n\t]+'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) {
      return fallback;
    }
    return cleaned.length > 80 ? cleaned.substring(0, 80).trim() : cleaned;
  }

  static String extensionFromUrl(String url) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? url.toLowerCase();
    final ext = p.extension(path).replaceFirst('.', '');
    if (['mp4', 'm4v', 'mov', 'ts', 'm3u8'].contains(ext)) {
      return ext;
    }
    return 'mp4';
  }

  static Future<bool> looksLikeHtml(File file) async {
    if (!await file.exists()) {
      return false;
    }
    final bytes = await file.openRead(0, 512).fold<List<int>>(<int>[], (
      previous,
      chunk,
    ) {
      previous.addAll(chunk);
      return previous.length > 512 ? previous.sublist(0, 512) : previous;
    });
    final head = String.fromCharCodes(bytes).toLowerCase();
    return head.contains('<!doctype html') ||
        head.contains('<html') ||
        head.contains('<body') ||
        head.contains('<script');
  }
}

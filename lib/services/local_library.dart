import 'dart:convert';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path/path.dart' as p;
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../models/local_video.dart';
import '../models/video_resource.dart';
import 'file_utils.dart';
import 'playback_store.dart';

class LocalLibrary {
  Future<List<LocalVideo>> scan() async {
    final dir = await FileUtils.videosDirectory();
    final files = await dir
        .list(recursive: true)
        .where((entity) => entity is File)
        .cast<File>()
        .where((file) {
      final lowerPath = file.path.toLowerCase();
      if (lowerPath.contains('/segments_tmp/') ||
          lowerPath.contains('/thumbnails/') ||
          lowerPath.contains('/.tmp/') ||
          lowerPath.endsWith('.part')) {
        return false;
      }
      final ext = p.extension(file.path).toLowerCase();
      return ['.mp4', '.m4v', '.mov'].contains(ext);
    }).toList();

    final videos = <LocalVideo>[];
    final playback = PlaybackStore();
    for (final file in files) {
      final stat = await file.stat();
      final cached = await _readMetadata(file);
      final thumb = await _thumbnailFile(file);
      final resume = await playback.positionFor(file.path);
      videos.add(
        LocalVideo(
          path: file.path,
          name: p.basename(file.path),
          title: cached['title']?.toString().trim().isNotEmpty == true
              ? cached['title'].toString()
              : _titleFromFile(file),
          size: stat.size,
          modifiedAt: stat.modified,
          createdAt: stat.changed,
          thumbnailPath: await thumb.exists() ? thumb.path : '',
          duration: Duration(
              milliseconds: int.tryParse('${cached['durationMs'] ?? 0}') ?? 0),
          width: int.tryParse('${cached['width'] ?? 0}') ?? 0,
          height: int.tryParse('${cached['height'] ?? 0}') ?? 0,
          bitrate: cached['bitrate']?.toString() ?? '',
          codec: cached['codec']?.toString() ?? '',
          sourceSite: cached['sourceSite']?.toString() ?? '',
          pageUrlHash: cached['pageUrlHash']?.toString() ?? '',
          folderIds: ((cached['folderIds'] as List?) ?? const [])
              .map((item) => item.toString())
              .where((item) => item.isNotEmpty)
              .toList(),
          isFavorite: cached['favorite'] == true,
          resumePosition: resume,
        ),
      );
    }
    videos.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    return videos;
  }

  Future<bool> ensureDetails(LocalVideo video) async {
    final file = File(video.path);
    if (!await file.exists()) return false;
    var changed = false;
    final metadata = await _readMetadata(file);
    final thumb = await _thumbnailFile(file);

    if (!await thumb.exists()) {
      changed = await _generateThumbnail(file, thumb) || changed;
    }
    if ((int.tryParse('${metadata['durationMs'] ?? 0}') ?? 0) <= 0 ||
        (int.tryParse('${metadata['width'] ?? 0}') ?? 0) <= 0 ||
        (int.tryParse('${metadata['height'] ?? 0}') ?? 0) <= 0) {
      final probed = await _probeVideo(file);
      metadata
        ..['durationMs'] = probed.duration.inMilliseconds
        ..['width'] = probed.width
        ..['height'] = probed.height
        ..['title'] = metadata['title'] ?? _titleFromFile(file);
      await _writeMetadata(file, metadata);
      changed = true;
    }
    return changed;
  }

  Future<void> writeDownloadMetadata(
      String filePath, VideoResource resource) async {
    final file = File(filePath);
    if (!await file.exists()) return;
    final metadata = await _readMetadata(file);
    final pageUri = Uri.tryParse(resource.pageUrl);
    metadata
      ..['title'] = resource.title
      ..['pageUrl'] = resource.pageUrl
      ..['pageUrlHash'] = FileUtils.stableKey(
        resource.pageUrl.isNotEmpty ? resource.pageUrl : resource.url,
      )
      ..['sourceSite'] = pageUri?.host ?? Uri.tryParse(resource.url)?.host ?? ''
      ..['codec'] = resource.codec
      ..['bitrate'] = resource.bitrate;
    final folderIds = <String>{
      ...(((metadata['folderIds'] as List?) ?? const [])
          .map((item) => item.toString())),
      if (resource.preferredFolderId.isNotEmpty) resource.preferredFolderId,
      if (resource.pageUrl.isNotEmpty)
        'page:${FileUtils.stableKey(resource.pageUrl)}',
      if ((pageUri?.host ?? '').isNotEmpty) 'site:${pageUri!.host}',
    }..removeWhere((item) => item.trim().isEmpty);
    metadata['folderIds'] = folderIds.toList();
    await _writeMetadata(file, metadata);
    await ensureDetails(LocalVideo(
      path: file.path,
      name: p.basename(file.path),
      title: resource.title,
      size: await file.length(),
      modifiedAt: (await file.stat()).modified,
      createdAt: (await file.stat()).changed,
    ));
  }

  Future<void> setFavorite(LocalVideo video, bool favorite) async {
    final file = File(video.path);
    final metadata = await _readMetadata(file);
    metadata['favorite'] = favorite;
    metadata['title'] = video.title;
    await _writeMetadata(file, metadata);
  }

  Future<void> moveToFolder(LocalVideo video, String folderId) async {
    if (folderId.trim().isEmpty) return;
    final file = File(video.path);
    final metadata = await _readMetadata(file);
    final folderIds = <String>{
      ...video.folderIds,
      ...(((metadata['folderIds'] as List?) ?? const [])
          .map((item) => item.toString())),
      folderId,
    }..removeWhere((item) => item.trim().isEmpty);
    metadata
      ..['title'] = video.title
      ..['folderIds'] = folderIds.toList();
    await _writeMetadata(file, metadata);
  }

  Future<void> removeFolderMapping(String folderId) async {
    if (folderId.trim().isEmpty) return;
    final dir = await FileUtils.thumbnailsDirectory();
    if (!await dir.exists()) return;
    final metadataFiles = await dir
        .list(recursive: false)
        .where((entity) => entity is File && entity.path.endsWith('.json'))
        .cast<File>()
        .toList();
    for (final file in metadataFiles) {
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is! Map<String, dynamic>) continue;
        final folderIds = ((decoded['folderIds'] as List?) ?? const [])
            .map((item) => item.toString())
            .where((item) => item != folderId)
            .toList();
        decoded['folderIds'] = folderIds;
        await file.writeAsString(jsonEncode(decoded));
      } catch (_) {}
    }
  }

  Future<void> delete(LocalVideo video) async {
    final file = File(video.path);
    if (await file.exists()) {
      await file.delete();
    }
    final thumb = await _thumbnailFile(file);
    if (await thumb.exists()) {
      await thumb.delete();
    }
    final metadata = await _metadataFile(file);
    if (await metadata.exists()) {
      await metadata.delete();
    }
  }

  Future<void> deleteCollection(String directoryPath) async {
    final root = await FileUtils.videosDirectory();
    final target = Directory(directoryPath);
    if (!target.path.startsWith(root.path) || !await target.exists()) {
      return;
    }
    final files = await target
        .list(recursive: true)
        .where((entity) => entity is File)
        .cast<File>()
        .toList();
    for (final file in files) {
      final ext = p.extension(file.path).toLowerCase();
      if (!['.mp4', '.m4v', '.mov'].contains(ext)) continue;
      final thumb = await _thumbnailFile(file);
      if (await thumb.exists()) {
        await thumb.delete();
      }
      final metadata = await _metadataFile(file);
      if (await metadata.exists()) {
        await metadata.delete();
      }
    }
    await target.delete(recursive: true);
  }

  Future<Map<String, dynamic>> _readMetadata(File file) async {
    final metadata = await _metadataFile(file);
    if (!await metadata.exists()) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(await metadata.readAsString());
      return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<void> _writeMetadata(File file, Map<String, dynamic> metadata) async {
    final target = await _metadataFile(file);
    if (!await target.parent.exists()) {
      await target.parent.create(recursive: true);
    }
    await target.writeAsString(jsonEncode(metadata));
  }

  Future<File> _thumbnailFile(File file) async {
    final dir = await FileUtils.thumbnailsDirectory();
    return File(p.join(dir.path, '${_videoKey(file)}.jpg'));
  }

  Future<File> _metadataFile(File file) async {
    final dir = await FileUtils.thumbnailsDirectory();
    return File(p.join(dir.path, '${_videoKey(file)}.json'));
  }

  Future<bool> _generateThumbnail(File file, File target) async {
    try {
      final generated = await VideoThumbnail.thumbnailFile(
        video: file.path,
        thumbnailPath: target.parent.path,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 640,
        quality: 82,
      );
      if (generated != null && generated.isNotEmpty) {
        final generatedFile = File(generated);
        if (await generatedFile.exists()) {
          if (generatedFile.path != target.path) {
            await generatedFile.copy(target.path);
          }
          return await target.exists();
        }
      }
    } catch (_) {}
    return _generateThumbnailWithFfmpeg(file, target);
  }

  Future<bool> _generateThumbnailWithFfmpeg(File file, File target) async {
    final command = [
      '-y',
      '-ss 00:00:01',
      '-i ${_shellQuote(file.path)}',
      '-frames:v 1',
      '-q:v 2',
      _shellQuote(target.path),
    ].join(' ');
    final session = await FFmpegKit.execute(command);
    final code = await session.getReturnCode();
    return ReturnCode.isSuccess(code) && await target.exists();
  }

  Future<_VideoProbe> _probeVideo(File file) async {
    final controller = VideoPlayerController.file(file);
    try {
      await controller.initialize();
      final size = controller.value.size;
      return _VideoProbe(
        duration: controller.value.duration,
        width: size.width.round(),
        height: size.height.round(),
      );
    } catch (_) {
      return const _VideoProbe();
    } finally {
      await controller.dispose();
    }
  }

  String _titleFromFile(File file) {
    final stem = p.basenameWithoutExtension(file.path);
    return stem
        .replaceFirst(RegExp(r'-\d{10,}$'), '')
        .replaceAll('_', ' ')
        .trim();
  }

  String _videoKey(File file) {
    return FileUtils.stableKey(file.path);
  }

  String _shellQuote(String value) => "'${value.replaceAll("'", "'\\''")}'";
}

class _VideoProbe {
  const _VideoProbe({
    this.duration = Duration.zero,
    this.width = 0,
    this.height = 0,
  });

  final Duration duration;
  final int width;
  final int height;
}

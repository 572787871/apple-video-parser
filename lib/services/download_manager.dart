import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../models/download_task.dart';
import '../models/video_resource.dart';
import 'download_task_store.dart';
import 'file_utils.dart';
import 'local_library.dart';

class DownloadManager extends ChangeNotifier {
  DownloadManager();

  static const MethodChannel _backgroundChannel = MethodChannel(
    'web_video_downloader/background_task',
  );

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(minutes: 30),
      followRedirects: true,
      validateStatus: (status) => status != null && status < 500,
    ),
  );
  final List<DownloadTask> tasks = [];
  final Map<String, CancelToken> _cancelTokens = {};
  final Map<String, FFmpegSession> _ffmpegSessions = {};
  final Map<String, File> _partFiles = {};
  final DownloadTaskStore _taskStore = DownloadTaskStore();
  Timer? _persistTimer;
  bool _restoring = false;

  @override
  void notifyListeners() {
    if (!_restoring) {
      _schedulePersist();
    }
    super.notifyListeners();
  }

  @override
  void dispose() {
    _persistTimer?.cancel();
    unawaited(_persistNow());
    super.dispose();
  }

  Future<void> restoreTasks() async {
    _restoring = true;
    try {
      final restored = await _taskStore.load();
      for (final task in restored) {
        if (task.isActive) {
          task.status = DownloadStatus.paused;
          task.phase = DownloadPhase.preparing;
          task.isIndeterminate = false;
          task.message = '上次下载中断，可继续';
          task.remaining = '剩余时间未知';
        }
        if (task.status == DownloadStatus.completed) {
          final file = File(task.localPath);
          if (task.localPath.isEmpty || !await file.exists()) {
            task.status = DownloadStatus.missing;
            task.phase = DownloadPhase.failed;
            task.message = '文件已不存在';
            task.errorMessage = '文件已不存在';
            task.isIndeterminate = false;
          }
        }
      }
      tasks
        ..clear()
        ..addAll(restored);
    } finally {
      _restoring = false;
    }
    notifyListeners();
  }

  DownloadTask createTask(VideoResource resource) {
    return DownloadTask(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      resource: resource,
      message: '准备中',
      phase: DownloadPhase.preparing,
    );
  }

  void addTask(DownloadTask task) {
    tasks.removeWhere((item) => item.id == task.id);
    tasks.removeWhere(
      (item) =>
          item.resource.normalizedUrl == task.resource.normalizedUrl &&
          item.status == DownloadStatus.failed,
    );
    tasks.insert(0, task);
    notifyListeners();
  }

  DownloadTask enqueue(VideoResource resource) {
    final task = createTask(resource);
    addTask(task);
    unawaited(start(task.id));
    return task;
  }

  String previewPathFor(DownloadTask task) {
    final file = _partFiles[task.id];
    if (file != null) return file.path;
    return task.tempPath;
  }

  Future<bool> canPreviewPartial(DownloadTask task) async {
    final path = previewPathFor(task);
    if (path.isEmpty) return false;
    final file = File(path);
    if (!await file.exists()) return false;
    if (await file.length() < 256 * 1024) return false;
    if (await FileUtils.looksLikeHtml(file)) return false;
    return true;
  }

  Future<void> start(String taskId) async {
    final task = _taskById(taskId);
    if (task == null) {
      return;
    }
    debugPrint('[download] start task=${task.id}');
    task.status = DownloadStatus.preparing;
    task.message = '准备中';
    task.phase = DownloadPhase.preparing;
    task.errorMessage = '';
    task.errorDetails = '';
    task.isIndeterminate = false;
    task.ffmpegLog = '';
    task.ffmpegTime = '--';
    task.ffmpegSpeed = '--';
    task.downloadedSegments = 0;
    task.totalSegments = 0;
    task.tempPath = '';
    task.outputDirectory = '';
    task.playlistDuration = Duration.zero;
    task.elapsed = Duration.zero;
    task.completedAt = null;
    notifyListeners();

    final backgroundId = await _beginBackgroundTask();
    try {
      task.status = DownloadStatus.downloading;
      task.phase = task.resource.isMergeRequired
          ? DownloadPhase.fetchingPlaylist
          : DownloadPhase.downloadingFile;
      task.message = task.resource.isMergeRequired ? '正在获取播放列表' : '正在下载';
      task.isIndeterminate = task.resource.isMergeRequired;
      notifyListeners();

      if (task.resource.isMergeRequired) {
        await _downloadWithFFmpeg(task);
      } else {
        await _downloadDirect(task);
      }
      if (task.status == DownloadStatus.paused ||
          task.status == DownloadStatus.canceled) {
        return;
      }

      final file = File(task.localPath);
      final size = await file.length();
      debugPrint('[download] completed file=${file.path} size=$size');
      task.status = DownloadStatus.completed;
      task.phase = DownloadPhase.completed;
      task.progress = 1;
      task.isIndeterminate = false;
      task.receivedBytes = size;
      task.totalBytes = size;
      task.speed = '完成';
      task.remaining = '00:00';
      task.message = '下载完成';
      task.tempPath = '';
      task.completedAt = DateTime.now();
      unawaited(
        LocalLibrary().writeDownloadMetadata(task.localPath, task.resource),
      );
      unawaited(_writePageMetadata(task));
      notifyListeners();
    } catch (error) {
      debugPrint('[download] failed error=$error');
      if (task.status != DownloadStatus.paused &&
          task.status != DownloadStatus.canceled) {
        task.status = DownloadStatus.failed;
        task.phase = DownloadPhase.failed;
      }
      task.isIndeterminate = false;
      task.errorDetails = _errorDetails(error, task);
      task.errorMessage = _errorSummary(error);
      task.message = task.status == DownloadStatus.paused
          ? '已暂停'
          : (task.status == DownloadStatus.canceled ? '已取消' : '下载失败');
      notifyListeners();
    } finally {
      _cancelTokens.remove(task.id);
      _ffmpegSessions.remove(task.id);
      if (task.status != DownloadStatus.paused) {
        _partFiles.remove(task.id);
      }
      await _endBackgroundTask(backgroundId);
    }
  }

  Future<void> retry(DownloadTask task) async {
    if (!task.canRetry) {
      return;
    }
    task.progress = 0;
    task.status = DownloadStatus.preparing;
    task.phase = DownloadPhase.preparing;
    task.message = '准备重试';
    task.errorMessage = '';
    task.errorDetails = '';
    task.receivedBytes = 0;
    task.totalBytes = 0;
    task.speed = '--';
    task.remaining = '剩余时间未知';
    task.isIndeterminate = false;
    task.ffmpegLog = '';
    task.ffmpegTime = '--';
    task.ffmpegSpeed = '--';
    task.downloadedSegments = 0;
    task.totalSegments = 0;
    notifyListeners();
    await start(task.id);
  }

  Future<void> pause(DownloadTask task) async {
    if (!task.isActive) {
      return;
    }
    _cancelTokens[task.id]?.cancel('paused');
    if (_ffmpegSessions[task.id] != null) {
      await FFmpegKit.cancel();
    }
    task.status = DownloadStatus.paused;
    task.isIndeterminate = false;
    task.message = '已暂停，可继续';
    notifyListeners();
  }

  Future<void> cancel(DownloadTask task) async {
    task.status = DownloadStatus.canceled;
    task.phase = DownloadPhase.canceled;
    task.isIndeterminate = false;
    task.message = '已取消';
    _cancelTokens[task.id]?.cancel('canceled');
    if (_ffmpegSessions[task.id] != null) {
      await FFmpegKit.cancel();
    }
    final partFile = _partFiles.remove(task.id);
    if (partFile != null && await partFile.exists()) {
      await partFile.delete().catchError((_) => partFile);
    }
    if (task.tempPath.isNotEmpty) {
      final file = File(task.tempPath);
      if (await file.exists()) {
        await file.delete().catchError((_) => file);
      }
    }
    tasks.removeWhere((item) => item.id == task.id);
    notifyListeners();
  }

  Future<void> clearHistory() async {
    tasks.removeWhere((task) => !task.isActive);
    notifyListeners();
    await _persistNow();
  }

  Future<void> _downloadDirect(DownloadTask task) async {
    final dir = await FileUtils.videoPageDirectory(task.resource);
    task.outputDirectory = dir.path;
    final extension = FileUtils.extensionFromUrl(task.resource.url);
    final finalFile = File(
      p.join(
        dir.path,
        _targetName(task.resource, extension == 'm3u8' ? 'mp4' : extension),
      ),
    );
    final partFile = File('${finalFile.path}.part');
    _partFiles[task.id] = partFile;
    task.tempPath = partFile.path;

    if (!await partFile.parent.exists()) {
      await partFile.parent.create(recursive: true);
    }

    final resumeFrom = await partFile.exists() ? await partFile.length() : 0;
    final cancelToken = CancelToken();
    _cancelTokens[task.id] = cancelToken;
    final startedAt = DateTime.now();

    task.phase = DownloadPhase.downloadingFile;
    task.isIndeterminate = false;
    notifyListeners();
    debugPrint('[download] request url=${task.resource.url}');
    debugPrint('[download] save path=${finalFile.path}');

    late final Response<ResponseBody> response;
    try {
      response = await _dio.get<ResponseBody>(
        task.resource.url,
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.stream,
          headers: {
            ..._headersFor(task.resource),
            if (resumeFrom > 0) 'Range': 'bytes=$resumeFrom-',
          },
        ),
      );
    } on DioException catch (error) {
      if ((error.error is HandshakeException) ||
          error.message?.contains('HandshakeException') == true) {
        await _downloadWithHttpClient(
          task,
          finalFile,
          partFile,
          resumeFrom,
          startedAt,
        );
        return;
      }
      rethrow;
    }
    final statusCode = response.statusCode ?? 0;
    if (resumeFrom > 0 && statusCode != 206) {
      await partFile.delete().catchError((_) => partFile);
      return _downloadDirect(task);
    }

    final sink = partFile.openWrite(
      mode: resumeFrom > 0 ? FileMode.append : FileMode.write,
    );
    try {
      final contentLength = _contentLength(response.headers) + resumeFrom;
      var received = resumeFrom;
      await for (final chunk in response.data!.stream) {
        if (cancelToken.isCancelled) {
          break;
        }
        sink.add(chunk);
        received += chunk.length;
        _updateProgress(task, received, contentLength, startedAt);
      }
    } finally {
      await sink.close();
    }

    if (task.status == DownloadStatus.paused ||
        task.status == DownloadStatus.canceled) {
      return;
    }
    if (await FileUtils.looksLikeHtml(partFile)) {
      await partFile.delete().catchError((_) => partFile);
      throw StateError('解析到的是网页，不是视频文件');
    }
    if (!await partFile.exists() || await partFile.length() <= 0) {
      throw StateError('没有写入有效视频文件');
    }
    if (await finalFile.exists()) {
      await finalFile.delete();
    }
    await partFile.rename(finalFile.path);
    task.localPath = finalFile.path;
  }

  Future<void> _downloadWithFFmpeg(DownloadTask task) async {
    final dir = await FileUtils.videoPageDirectory(task.resource);
    task.outputDirectory = dir.path;
    final output = File(p.join(dir.path, _targetName(task.resource, 'mp4')));
    final tempDir = Directory(p.join(dir.path, 'segments_tmp'));
    if (!await tempDir.exists()) {
      await tempDir.create(recursive: true);
    }
    final tempOutput = File(p.join(tempDir.path, '${task.id}.mp4'));
    _partFiles[task.id] = tempOutput;
    task.tempPath = tempOutput.path;
    if (await output.exists()) {
      await output.delete();
    }
    if (await tempOutput.exists()) {
      await tempOutput.delete();
    }
    debugPrint('[download] request url=${task.resource.url}');
    debugPrint('[download] save path=${output.path}');
    await _prefetchPlaylist(task);

    final command = [
      '-y',
      '-headers ${_shellQuote(_ffmpegHeaders(task.resource))}',
      '-i ${_shellQuote(task.resource.url)}',
      '-c copy',
      '-movflags +faststart',
      _shellQuote(tempOutput.path),
    ].join(' ');

    var logs = await _runFfmpeg(task, command);
    if (logs != null) {
      if (await tempOutput.exists()) {
        await tempOutput.delete().catchError((_) => tempOutput);
      }
      final fallback = [
        '-y',
        '-headers ${_shellQuote(_ffmpegHeaders(task.resource))}',
        '-i ${_shellQuote(task.resource.url)}',
        '-c:v copy',
        '-c:a aac',
        '-movflags +faststart',
        _shellQuote(tempOutput.path),
      ].join(' ');
      logs = await _runFfmpeg(task, fallback);
    }
    if (logs != null) {
      throw StateError('ffmpeg 合并失败：$logs');
    }

    if (task.status == DownloadStatus.paused ||
        task.status == DownloadStatus.canceled) {
      return;
    }
    task.status = DownloadStatus.merging;
    task.phase = DownloadPhase.merging;
    task.message = '正在写入视频文件';
    task.isIndeterminate = true;
    if (task.progress < 0.96) {
      task.progress = 0.96;
    }
    notifyListeners();
    if (!await tempOutput.exists() || await tempOutput.length() <= 0) {
      throw StateError('m3u8 没有合并出有效 mp4 文件');
    }
    if (await FileUtils.looksLikeHtml(tempOutput)) {
      await tempOutput.delete().catchError((_) => tempOutput);
      throw StateError('解析到的是网页，不是视频文件');
    }
    if (await output.exists()) {
      await output.delete();
    }
    await tempOutput.rename(output.path);
    task.localPath = output.path;
  }

  Future<String?> _runFfmpeg(DownloadTask task, String command) async {
    final logs = StringBuffer();
    final completer = Completer<String?>();
    final startedAt = DateTime.now();
    final session = await FFmpegKit.executeAsync(
      command,
      (session) async {
        final returnCode = await session.getReturnCode();
        completer.complete(
          ReturnCode.isSuccess(returnCode) ? null : logs.toString().trim(),
        );
      },
      (log) {
        if (_isTerminalOrPaused(task)) return;
        final message = log.getMessage().trim();
        if (message.isEmpty) return;
        logs.writeln(message);
        _appendFfmpegLog(task, message);
        if (_looksLikeSegmentLog(message) && task.totalSegments > 0) {
          task.downloadedSegments = (task.downloadedSegments + 1).clamp(
            0,
            task.totalSegments,
          );
          task.progress = task.totalSegments > 0
              ? (task.downloadedSegments / task.totalSegments)
                  .clamp(0, 0.95)
                  .toDouble()
              : task.progress;
          task.isIndeterminate = task.totalSegments <= 0;
          task.phase = DownloadPhase.downloadingSegments;
          task.status = DownloadStatus.downloading;
          task.message =
              '正在下载分片 ${task.downloadedSegments}/${task.totalSegments}';
        }
        notifyListeners();
      },
      (statistics) {
        if (_isTerminalOrPaused(task)) return;
        final timeMs = statistics.getTime();
        task.elapsed = DateTime.now().difference(startedAt);
        if (timeMs > 0) {
          task.status = DownloadStatus.downloading;
          task.phase = DownloadPhase.downloadingSegments;
          task.ffmpegTime = _formatDuration(Duration(milliseconds: timeMs));
          task.ffmpegSpeed = statistics.getSpeed().toStringAsFixed(2);
          if (task.playlistDuration > Duration.zero) {
            task.progress = (timeMs / task.playlistDuration.inMilliseconds)
                .clamp(0, 0.95)
                .toDouble();
            task.isIndeterminate = false;
            final speed = statistics.getSpeed();
            final remainingMs = (task.playlistDuration.inMilliseconds - timeMs)
                .clamp(0, 1 << 31);
            task.remaining = speed > 0
                ? _formatDuration(
                    Duration(milliseconds: (remainingMs / speed).round()),
                  )
                : '剩余时间未知';
          } else {
            task.isIndeterminate = true;
            task.remaining = '剩余时间未知';
          }
          final elapsed = _formatDuration(DateTime.now().difference(startedAt));
          task.message =
              '下载/合并中 time=${task.ffmpegTime} speed=${task.ffmpegSpeed}x 已用 $elapsed';
          notifyListeners();
        }
      },
    );
    _ffmpegSessions[task.id] = session;
    return completer.future;
  }

  Future<void> _prefetchPlaylist(DownloadTask task) async {
    task.phase = DownloadPhase.fetchingPlaylist;
    task.status = DownloadStatus.downloading;
    task.isIndeterminate = true;
    task.message = '正在获取播放列表';
    notifyListeners();
    try {
      final response = await _dio.get<String>(
        task.resource.url,
        options: Options(
          responseType: ResponseType.plain,
          headers: _headersFor(task.resource),
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      final statusCode = response.statusCode ?? 0;
      final body = response.data ?? '';
      if (statusCode >= 400) {
        _appendFfmpegLog(task, 'playlist HTTP $statusCode');
      } else if (_looksLikeHtmlText(body)) {
        throw StateError('m3u8 返回了网页 HTML');
      } else {
        final count = body
            .split('\n')
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty && !line.startsWith('#'))
            .where(
              (line) => RegExp(
                r'\.(?:ts|m4s|mp4|m4v|aac)(?:[?#]|$)',
                caseSensitive: false,
              ).hasMatch(line),
            )
            .length;
        task.totalSegments = count;
        task.downloadedSegments = 0;
        task.playlistDuration = _playlistDuration(body);
      }
    } catch (error) {
      _appendFfmpegLog(task, 'playlist prefetch failed: $error');
    }
    task.phase = DownloadPhase.downloadingSegments;
    task.status = DownloadStatus.downloading;
    task.message =
        task.totalSegments > 0 ? '正在下载分片 0/${task.totalSegments}' : '正在下载分片';
    notifyListeners();
  }

  void _appendFfmpegLog(DownloadTask task, String message) {
    final next =
        task.ffmpegLog.isEmpty ? message : '${task.ffmpegLog}\n$message';
    final lines = next.split('\n');
    task.ffmpegLog =
        lines.length > 20 ? lines.sublist(lines.length - 20).join('\n') : next;
  }

  String _errorSummary(Object error) {
    final text = '$error'.toLowerCase();
    if (text.contains('ffmpeg')) return 'm3u8 合并失败';
    if (text.contains('handshake') ||
        text.contains('connection') ||
        text.contains('network')) {
      return '网络连接失败';
    }
    if (text.contains('html') || text.contains('不是视频') || text.contains('无效')) {
      return '资源无效或已过期';
    }
    if (text.contains('403') || text.contains('401') || text.contains('拒绝')) {
      return '站点拒绝 App 下载';
    }
    return '下载失败，请查看详情';
  }

  String _errorDetails(Object error, DownloadTask task) {
    final lines = <String>[
      '$error',
      if (task.resource.url.isNotEmpty) 'URL: ${task.resource.url}',
      if (task.ffmpegLog.isNotEmpty) 'ffmpeg log:\n${task.ffmpegLog}',
      if ('$error'.contains('过期') ||
          '$error'.contains('403') ||
          '$error'.contains('401'))
        '请回到网页重新播放后再下载。',
    ];
    return lines.join('\n');
  }

  bool _looksLikeHtmlText(String value) {
    final lower = value.trimLeft().toLowerCase();
    return lower.startsWith('<!doctype html') ||
        lower.startsWith('<html') ||
        lower.contains('<body');
  }

  bool _looksLikeSegmentLog(String value) {
    final lower = value.toLowerCase();
    return lower.contains('.ts') || lower.contains('.m4s');
  }

  Duration _playlistDuration(String body) {
    var total = 0.0;
    final matches = RegExp(
      r'#EXTINF:([\d.]+)',
      caseSensitive: false,
    ).allMatches(body);
    for (final match in matches) {
      total += double.tryParse(match.group(1) ?? '') ?? 0;
    }
    return Duration(milliseconds: (total * 1000).round());
  }

  bool _isTerminalOrPaused(DownloadTask task) {
    return task.status == DownloadStatus.completed ||
        task.status == DownloadStatus.failed ||
        task.status == DownloadStatus.canceled ||
        task.status == DownloadStatus.paused;
  }

  Future<void> _downloadWithHttpClient(
    DownloadTask task,
    File finalFile,
    File partFile,
    int resumeFrom,
    DateTime startedAt,
  ) async {
    final uri = Uri.parse(task.resource.url);
    final client = HttpClient();
    try {
      debugPrint('[download] request url=${task.resource.url}');
      debugPrint('[download] save path=${finalFile.path}');
      final request = await client.getUrl(uri);
      for (final entry in _headersFor(task.resource).entries) {
        request.headers.set(entry.key, entry.value);
      }
      if (resumeFrom > 0) {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$resumeFrom-');
      }
      final response = await request.close();
      if (response.statusCode >= 500) {
        throw HttpException('HTTP ${response.statusCode}', uri: uri);
      }
      final total =
          response.contentLength > 0 ? response.contentLength + resumeFrom : 0;
      var received = resumeFrom;
      final sink = partFile.openWrite(
        mode: resumeFrom > 0 ? FileMode.append : FileMode.write,
      );
      try {
        await for (final chunk in response) {
          if (task.status == DownloadStatus.paused ||
              task.status == DownloadStatus.canceled) {
            break;
          }
          sink.add(chunk);
          received += chunk.length;
          _updateProgress(task, received, total, startedAt);
        }
      } finally {
        await sink.close();
      }
      if (task.status == DownloadStatus.paused ||
          task.status == DownloadStatus.canceled) {
        return;
      }
      if (await FileUtils.looksLikeHtml(partFile)) {
        await partFile.delete().catchError((_) => partFile);
        throw StateError('解析到的是网页，不是视频文件');
      }
      if (!await partFile.exists() || await partFile.length() <= 0) {
        throw StateError('没有写入有效视频文件');
      }
      if (await finalFile.exists()) await finalFile.delete();
      await partFile.rename(finalFile.path);
      task.localPath = finalFile.path;
    } catch (e) {
      if (e is HandshakeException) {
        throw StateError('站点拒绝 App 直连下载，需要在网页内播放后再嗅探真实地址');
      }
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  void _updateProgress(
    DownloadTask task,
    int received,
    int total,
    DateTime startedAt,
  ) {
    final elapsed = DateTime.now().difference(startedAt).inMilliseconds / 1000;
    task.elapsed = DateTime.now().difference(startedAt);
    final speedBytes = elapsed <= 0 ? 0 : received / elapsed;
    task.receivedBytes = received;
    task.totalBytes = total;
    task.progress = total > 0 ? (received / total).clamp(0, 1).toDouble() : 0;
    task.phase = DownloadPhase.downloadingFile;
    task.isIndeterminate = total <= 0;
    task.speed =
        speedBytes <= 0 ? '--' : '${_formatBytes(speedBytes.round())}/s';
    task.remaining = total > 0 && speedBytes > 0
        ? _formatDuration(
            Duration(seconds: ((total - received) / speedBytes).ceil()),
          )
        : '剩余时间未知';
    task.message = total > 0
        ? '${_formatBytes(received)} / ${_formatBytes(total)}'
        : _formatBytes(received);
    debugPrint('[download] progress=$received/$total');
    notifyListeners();
  }

  int _contentLength(Headers headers) {
    final value = headers.value(HttpHeaders.contentLengthHeader);
    return int.tryParse(value ?? '') ?? 0;
  }

  DownloadTask? _taskById(String id) {
    for (final task in tasks) {
      if (task.id == id) {
        return task;
      }
    }
    return null;
  }

  String _targetName(VideoResource resource, String extension) {
    final base = FileUtils.safeFileName(resource.title, fallback: 'video');
    final quality = resource.quality == '未知'
        ? ''
        : '-${FileUtils.safeFileName(resource.quality, fallback: '')}';
    return '$base$quality-${DateTime.now().millisecondsSinceEpoch}.$extension';
  }

  Future<void> _writePageMetadata(DownloadTask task) async {
    if (task.outputDirectory.isEmpty) return;
    final file = File(p.join(task.outputDirectory, 'metadata.json'));
    final pageUri = Uri.tryParse(task.resource.pageUrl);
    final pageUrl = task.resource.pageUrl.isNotEmpty
        ? task.resource.pageUrl
        : task.resource.url;
    final collectionId = FileUtils.stableKey(pageUrl);
    final data = <String, dynamic>{
      'collectionId': collectionId,
      'pageUrl': task.resource.pageUrl,
      'pageTitle': task.resource.title,
      'sourceSite':
          pageUri?.host ?? Uri.tryParse(task.resource.url)?.host ?? '',
      'resourceId': task.resource.id,
      'quality': task.resource.quality,
      'format': task.resource.displayFormat,
      'durationMs': task.resource.duration.inMilliseconds,
      'downloadedAt': (task.completedAt ?? DateTime.now()).toIso8601String(),
      'filePath': task.localPath,
      'thumbnailPath': task.thumbnailPath,
      'selectedQuality': task.resource.quality,
      'downloadTime': DateTime.now().toIso8601String(),
      'files': [p.basename(task.localPath)],
      'resources': [_resourceMetadata(task.resource)],
      'headersSummary': {
        'hasUserAgent': task.resource.userAgent.isNotEmpty,
        'hasReferer': task.resource.referer.isNotEmpty,
        'hasCookie': task.resource.cookie.isNotEmpty,
        'hasOrigin': task.resource.origin.isNotEmpty,
      },
    };
    if (await file.exists()) {
      try {
        final existing = jsonDecode(await file.readAsString());
        if (existing is Map<String, dynamic>) {
          final files = [
            ...((existing['files'] as List?) ?? const []),
            p.basename(task.localPath),
          ].map((item) => item.toString()).toSet().toList();
          final resources = [
            ...((existing['resources'] as List?) ?? const []),
            _resourceMetadata(task.resource),
          ];
          data['files'] = files;
          data['resources'] = resources;
        }
      } catch (_) {}
    }
    await file.writeAsString(jsonEncode(data));
  }

  Map<String, dynamic> _resourceMetadata(VideoResource resource) {
    return {
      'url': resource.url,
      'type': resource.displayFormat,
      'quality': resource.quality,
      'size': resource.size,
      'bitrate': resource.bitrate,
      'codec': resource.codec,
      'source': resource.source,
      'isCurrentPlayback': resource.isCurrentPlayback,
      'preferredFolderId': resource.preferredFolderId,
      'preferredFolderName': resource.preferredFolderName,
    };
  }

  Map<String, String> _headersFor(VideoResource resource) {
    return {
      'User-Agent': resource.userAgent.isNotEmpty
          ? resource.userAgent
          : 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15',
      'Referer':
          resource.referer.isNotEmpty ? resource.referer : resource.pageUrl,
      if (resource.origin.isNotEmpty) 'Origin': resource.origin,
      if (resource.cookie.isNotEmpty) 'Cookie': resource.cookie,
      'Accept': '*/*',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      'Connection': 'keep-alive',
    }..removeWhere((_, value) => value.trim().isEmpty);
  }

  String _ffmpegHeaders(VideoResource resource) {
    return _headersFor(
      resource,
    ).entries.map((entry) => '${entry.key}: ${entry.value}\r\n').join();
  }

  String _shellQuote(String value) => "'${value.replaceAll("'", "'\\''")}'";

  String _formatBytes(int value) {
    if (value < 1024) return '$value B';
    if (value < 1024 * 1024) return '${(value / 1024).toStringAsFixed(1)} KB';
    if (value < 1024 * 1024 * 1024) {
      return '${(value / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(value / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hours = duration.inHours;
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  Future<int?> _beginBackgroundTask() async {
    try {
      return await _backgroundChannel.invokeMethod<int>('begin');
    } catch (_) {
      return null;
    }
  }

  Future<void> _endBackgroundTask(int? id) async {
    if (id == null) return;
    try {
      await _backgroundChannel.invokeMethod<void>('end', id);
    } catch (_) {}
  }

  void _schedulePersist() {
    _persistTimer?.cancel();
    _persistTimer = Timer(
      const Duration(milliseconds: 800),
      () => unawaited(_persistNow()),
    );
  }

  Future<void> _persistNow() async {
    try {
      await _taskStore.save(tasks);
    } catch (error) {
      debugPrint('[download] persist failed: $error');
    }
  }
}

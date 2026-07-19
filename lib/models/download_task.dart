import 'video_resource.dart';

enum DownloadStatus {
  idle,
  preparing,
  downloading,
  paused,
  merging,
  completed,
  failed,
  canceled,
  missing,
}

enum DownloadPhase {
  preparing,
  fetchingPlaylist,
  downloadingSegments,
  downloadingFile,
  merging,
  completed,
  failed,
  canceled,
}

class DownloadTask {
  DownloadTask({
    required this.id,
    required this.resource,
    this.progress = 0,
    this.status = DownloadStatus.preparing,
    this.localPath = '',
    this.tempPath = '',
    this.outputDirectory = '',
    this.message = '准备中',
    this.errorMessage = '',
    this.errorDetails = '',
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.speed = '--',
    this.remaining = '剩余时间未知',
    this.phase = DownloadPhase.preparing,
    this.isIndeterminate = false,
    this.totalSegments = 0,
    this.downloadedSegments = 0,
    this.ffmpegTime = '--',
    this.ffmpegSpeed = '--',
    this.ffmpegLog = '',
    this.playlistDuration = Duration.zero,
    this.elapsed = Duration.zero,
    DateTime? createdAt,
    this.completedAt,
    this.thumbnailPath = '',
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  final VideoResource resource;
  double progress;
  DownloadStatus status;
  String localPath;
  String tempPath;
  String outputDirectory;
  String message;
  String errorMessage;
  String errorDetails;
  int receivedBytes;
  int totalBytes;
  String speed;
  String remaining;
  DownloadPhase phase;
  bool isIndeterminate;
  int totalSegments;
  int downloadedSegments;
  String ffmpegTime;
  String ffmpegSpeed;
  String ffmpegLog;
  Duration playlistDuration;
  Duration elapsed;
  DateTime createdAt;
  DateTime? completedAt;
  String thumbnailPath;

  bool get canRetry =>
      status == DownloadStatus.failed ||
      status == DownloadStatus.canceled ||
      status == DownloadStatus.paused;
  bool get isActive =>
      status == DownloadStatus.preparing ||
      status == DownloadStatus.downloading ||
      status == DownloadStatus.merging;

  String get idShort => id.length <= 6 ? id : id.substring(id.length - 6);

  Map<String, dynamic> toJson() {
    return {
      'taskId': id,
      'resource': resource.toJson(),
      'url': resource.url,
      'pageUrl': resource.pageUrl,
      'title': resource.title,
      'state': status.name,
      'phase': phase.name,
      'progress': progress,
      'downloadedBytes': receivedBytes,
      'totalBytes': totalBytes,
      'filePath': localPath,
      'tempPath': tempPath,
      'outputDirectory': outputDirectory,
      'thumbnailPath': thumbnailPath,
      'createdAt': createdAt.toIso8601String(),
      'completedAt': completedAt?.toIso8601String(),
      'errorSummary': errorMessage,
      'errorDetails': errorDetails,
      'message': message,
      'speed': speed,
      'remaining': remaining,
      'isIndeterminate': isIndeterminate,
      'totalSegments': totalSegments,
      'downloadedSegments': downloadedSegments,
      'ffmpegTime': ffmpegTime,
      'ffmpegSpeed': ffmpegSpeed,
      'ffmpegLog': ffmpegLog,
      'playlistDurationMs': playlistDuration.inMilliseconds,
      'elapsedMs': elapsed.inMilliseconds,
    };
  }

  factory DownloadTask.fromJson(Map<String, dynamic> json) {
    final rawResource = json['resource'];
    final resource = rawResource is Map
        ? VideoResource.fromJson(Map<String, dynamic>.from(rawResource))
        : VideoResource(
            url: json['url']?.toString() ?? '',
            title: json['title']?.toString() ?? '网页视频',
            type: VideoResource.typeFromUrl(json['url']?.toString() ?? ''),
            source: 'history',
            pageUrl: json['pageUrl']?.toString() ?? '',
          );
    return DownloadTask(
      id: json['taskId']?.toString() ?? json['id']?.toString() ?? '',
      resource: resource,
      progress: double.tryParse('${json['progress'] ?? 0}') ?? 0,
      status: _statusFromName(json['state']?.toString() ?? ''),
      localPath:
          json['filePath']?.toString() ?? json['localPath']?.toString() ?? '',
      tempPath: json['tempPath']?.toString() ?? '',
      outputDirectory: json['outputDirectory']?.toString() ?? '',
      message: json['message']?.toString() ?? '准备中',
      errorMessage: json['errorSummary']?.toString() ??
          json['errorMessage']?.toString() ??
          '',
      errorDetails: json['errorDetails']?.toString() ?? '',
      receivedBytes: int.tryParse('${json['downloadedBytes'] ?? 0}') ?? 0,
      totalBytes: int.tryParse('${json['totalBytes'] ?? 0}') ?? 0,
      speed: json['speed']?.toString() ?? '--',
      remaining: json['remaining']?.toString() ?? '剩余时间未知',
      phase: _phaseFromName(json['phase']?.toString() ?? ''),
      isIndeterminate: json['isIndeterminate'] == true,
      totalSegments: int.tryParse('${json['totalSegments'] ?? 0}') ?? 0,
      downloadedSegments:
          int.tryParse('${json['downloadedSegments'] ?? 0}') ?? 0,
      ffmpegTime: json['ffmpegTime']?.toString() ?? '--',
      ffmpegSpeed: json['ffmpegSpeed']?.toString() ?? '--',
      ffmpegLog: json['ffmpegLog']?.toString() ?? '',
      playlistDuration: Duration(
        milliseconds: int.tryParse('${json['playlistDurationMs'] ?? 0}') ?? 0,
      ),
      elapsed: Duration(
        milliseconds: int.tryParse('${json['elapsedMs'] ?? 0}') ?? 0,
      ),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      completedAt: DateTime.tryParse(json['completedAt']?.toString() ?? ''),
      thumbnailPath: json['thumbnailPath']?.toString() ?? '',
    );
  }

  static DownloadStatus _statusFromName(String value) {
    for (final status in DownloadStatus.values) {
      if (status.name == value) return status;
    }
    return DownloadStatus.preparing;
  }

  static DownloadPhase _phaseFromName(String value) {
    for (final phase in DownloadPhase.values) {
      if (phase.name == value) return phase;
    }
    return DownloadPhase.preparing;
  }
}

enum VideoResourceType { mp4, hls, ts, unknown }

class VideoResource {
  const VideoResource({
    required this.url,
    required this.title,
    required this.type,
    required this.source,
    this.pageUrl = '',
    this.referer = '',
    this.userAgent = '',
    this.cookie = '',
    this.origin = '',
    this.size = '未知',
    this.quality = '未知',
    this.bitrate = '',
    this.codec = '',
    this.container = '',
    this.contentType = '',
    this.acceptRanges = false,
    this.isAdSuspect = false,
    this.recommendation = '',
    this.detectedAtMs = 0,
    this.duration = Duration.zero,
    this.thumbnailUrl = '',
    this.isCurrentPlayback = false,
    this.playerId = '',
    this.preferredFolderId = '',
    this.preferredFolderName = '',
  });

  final String url;
  final String title;
  final VideoResourceType type;
  final String source;
  final String pageUrl;
  final String referer;
  final String userAgent;
  final String cookie;
  final String origin;
  final String size;
  final String quality;
  final String bitrate;
  final String codec;
  final String container;
  final String contentType;
  final bool acceptRanges;
  final bool isAdSuspect;
  final String recommendation;
  final int detectedAtMs;
  final Duration duration;
  final String thumbnailUrl;
  final bool isCurrentPlayback;
  final String playerId;
  final String preferredFolderId;
  final String preferredFolderName;

  String get id => normalizedUrl;
  String get normalizedUrl =>
      Uri.tryParse(url)?.removeFragment().toString() ?? url;

  String get label {
    switch (type) {
      case VideoResourceType.hls:
        return 'm3u8 / HLS';
      case VideoResourceType.ts:
        return 'TS 分片';
      case VideoResourceType.unknown:
        return 'unknown';
      case VideoResourceType.mp4:
        return 'MP4';
    }
  }

  bool get isMergeRequired => type == VideoResourceType.hls;

  bool get isPlayable =>
      type == VideoResourceType.hls || type == VideoResourceType.mp4;

  bool get isFragment {
    final lower = url.toLowerCase();
    return type == VideoResourceType.ts || lower.contains('.m4s');
  }

  String get displayFormat {
    switch (type) {
      case VideoResourceType.hls:
        return 'M3U8-HLS';
      case VideoResourceType.ts:
        return 'TS 分片';
      case VideoResourceType.mp4:
        final lower = url.toLowerCase();
        if (lower.contains('.mov')) return 'MOV';
        if (lower.contains('.m4v')) return 'M4V';
        return 'MP4';
      case VideoResourceType.unknown:
        return url.toLowerCase().contains('.m4s') ? 'M4S' : 'unknown';
    }
  }

  VideoResource copyWith({
    String? url,
    String? title,
    VideoResourceType? type,
    String? source,
    String? pageUrl,
    String? referer,
    String? userAgent,
    String? cookie,
    String? origin,
    String? size,
    String? quality,
    String? bitrate,
    String? codec,
    String? container,
    String? contentType,
    bool? acceptRanges,
    bool? isAdSuspect,
    String? recommendation,
    int? detectedAtMs,
    Duration? duration,
    String? thumbnailUrl,
    bool? isCurrentPlayback,
    String? playerId,
    String? preferredFolderId,
    String? preferredFolderName,
  }) {
    return VideoResource(
      url: url ?? this.url,
      title: title ?? this.title,
      type: type ?? this.type,
      source: source ?? this.source,
      pageUrl: pageUrl ?? this.pageUrl,
      referer: referer ?? this.referer,
      userAgent: userAgent ?? this.userAgent,
      cookie: cookie ?? this.cookie,
      origin: origin ?? this.origin,
      size: size ?? this.size,
      quality: quality ?? this.quality,
      bitrate: bitrate ?? this.bitrate,
      codec: codec ?? this.codec,
      container: container ?? this.container,
      contentType: contentType ?? this.contentType,
      acceptRanges: acceptRanges ?? this.acceptRanges,
      isAdSuspect: isAdSuspect ?? this.isAdSuspect,
      recommendation: recommendation ?? this.recommendation,
      detectedAtMs: detectedAtMs ?? this.detectedAtMs,
      duration: duration ?? this.duration,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      isCurrentPlayback: isCurrentPlayback ?? this.isCurrentPlayback,
      playerId: playerId ?? this.playerId,
      preferredFolderId: preferredFolderId ?? this.preferredFolderId,
      preferredFolderName: preferredFolderName ?? this.preferredFolderName,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'url': url,
      'title': title,
      'type': type.name,
      'source': source,
      'pageUrl': pageUrl,
      'referer': referer,
      'userAgent': userAgent,
      'cookie': cookie,
      'origin': origin,
      'size': size,
      'quality': quality,
      'bitrate': bitrate,
      'codec': codec,
      'container': container,
      'contentType': contentType,
      'acceptRanges': acceptRanges,
      'isAdSuspect': isAdSuspect,
      'recommendation': recommendation,
      'detectedAtMs': detectedAtMs,
      'durationMs': duration.inMilliseconds,
      'thumbnailUrl': thumbnailUrl,
      'isCurrentPlayback': isCurrentPlayback,
      'playerId': playerId,
      'preferredFolderId': preferredFolderId,
      'preferredFolderName': preferredFolderName,
    };
  }

  factory VideoResource.fromJson(Map<String, dynamic> json) {
    return VideoResource(
      url: json['url']?.toString() ?? '',
      title: json['title']?.toString() ?? '网页视频',
      type: _typeFromName(json['type']?.toString() ?? ''),
      source: json['source']?.toString() ?? 'dom',
      pageUrl: json['pageUrl']?.toString() ?? '',
      referer: json['referer']?.toString() ?? '',
      userAgent: json['userAgent']?.toString() ?? '',
      cookie: json['cookie']?.toString() ?? '',
      origin: json['origin']?.toString() ?? '',
      size: json['size']?.toString() ?? '未知',
      quality: json['quality']?.toString() ?? '未知',
      bitrate: json['bitrate']?.toString() ?? '',
      codec: json['codec']?.toString() ?? '',
      container: json['container']?.toString() ?? '',
      contentType: json['contentType']?.toString() ?? '',
      acceptRanges: json['acceptRanges'] == true,
      isAdSuspect: json['isAdSuspect'] == true,
      recommendation: json['recommendation']?.toString() ?? '',
      detectedAtMs: int.tryParse('${json['detectedAtMs'] ?? 0}') ?? 0,
      duration: Duration(
        milliseconds: int.tryParse('${json['durationMs'] ?? 0}') ?? 0,
      ),
      thumbnailUrl: json['thumbnailUrl']?.toString() ?? '',
      isCurrentPlayback: json['isCurrentPlayback'] == true,
      playerId: json['playerId']?.toString() ?? '',
      preferredFolderId: json['preferredFolderId']?.toString() ?? '',
      preferredFolderName: json['preferredFolderName']?.toString() ?? '',
    );
  }

  static VideoResourceType typeFromUrl(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('.m3u8')) {
      return VideoResourceType.hls;
    }
    if (lower.contains('.ts')) {
      return VideoResourceType.ts;
    }
    if (lower.contains('.mp4') ||
        lower.contains('.m4v') ||
        lower.contains('.mov')) {
      return VideoResourceType.mp4;
    }
    if (lower.contains('.m4s')) {
      return VideoResourceType.unknown;
    }
    if (!lower.contains('.')) {
      return VideoResourceType.unknown;
    }
    return VideoResourceType.mp4;
  }

  static VideoResourceType _typeFromName(String value) {
    for (final type in VideoResourceType.values) {
      if (type.name == value) return type;
    }
    return VideoResourceType.unknown;
  }
}

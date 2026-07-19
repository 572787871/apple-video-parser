class LocalVideo {
  const LocalVideo({
    required this.path,
    required this.name,
    required this.title,
    required this.size,
    required this.modifiedAt,
    required this.createdAt,
    this.thumbnailPath = '',
    this.duration = Duration.zero,
    this.width = 0,
    this.height = 0,
    this.bitrate = '',
    this.codec = '',
    this.sourceSite = '',
    this.pageUrlHash = '',
    this.folderIds = const [],
    this.resumePosition = Duration.zero,
    this.isFavorite = false,
  });

  final String path;
  final String name;
  final String title;
  final int size;
  final DateTime modifiedAt;
  final DateTime createdAt;
  final String thumbnailPath;
  final Duration duration;
  final int width;
  final int height;
  final String bitrate;
  final String codec;
  final String sourceSite;
  final String pageUrlHash;
  final List<String> folderIds;
  final Duration resumePosition;
  final bool isFavorite;

  String get resolutionLabel {
    final longSide = width > height ? width : height;
    final shortSide = width > height ? height : width;
    if (longSide >= 3800 || shortSide >= 2160) return '4K';
    if (longSide >= 2500 || shortSide >= 1440) return '2K';
    if (shortSide >= 1080) return '1080P';
    if (shortSide >= 720) return '720P';
    if (shortSide >= 480) return '480P';
    if (shortSide > 0) return 'SD';
    return '未知';
  }

  LocalVideo copyWith({
    String? path,
    String? name,
    String? title,
    int? size,
    DateTime? modifiedAt,
    DateTime? createdAt,
    String? thumbnailPath,
    Duration? duration,
    int? width,
    int? height,
    String? bitrate,
    String? codec,
    String? sourceSite,
    String? pageUrlHash,
    List<String>? folderIds,
    Duration? resumePosition,
    bool? isFavorite,
  }) {
    return LocalVideo(
      path: path ?? this.path,
      name: name ?? this.name,
      title: title ?? this.title,
      size: size ?? this.size,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      createdAt: createdAt ?? this.createdAt,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      duration: duration ?? this.duration,
      width: width ?? this.width,
      height: height ?? this.height,
      bitrate: bitrate ?? this.bitrate,
      codec: codec ?? this.codec,
      sourceSite: sourceSite ?? this.sourceSite,
      pageUrlHash: pageUrlHash ?? this.pageUrlHash,
      folderIds: folderIds ?? this.folderIds,
      resumePosition: resumePosition ?? this.resumePosition,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }
}

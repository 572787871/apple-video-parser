import 'video_resource.dart';

enum ParseRecordStatus { found, notFound, failed }

class ParseRecord {
  const ParseRecord({
    required this.pageUrl,
    required this.pageTitle,
    required this.parsedAt,
    required this.status,
    this.resources = const [],
    this.message = '',
    this.sourceSite = '',
    this.recommendedUrl = '',
  });

  final String pageUrl;
  final String pageTitle;
  final DateTime parsedAt;
  final ParseRecordStatus status;
  final List<VideoResource> resources;
  final String message;
  final String sourceSite;
  final String recommendedUrl;

  VideoResource? get recommendedResource {
    if (resources.isEmpty) return null;
    for (final resource in resources) {
      if (resource.url == recommendedUrl) return resource;
    }
    for (final resource in resources) {
      if (resource.isPlayable &&
          !resource.isAdSuspect &&
          !resource.isFragment &&
          resource.isCurrentPlayback) {
        return resource;
      }
    }
    for (final resource in resources) {
      if (resource.isPlayable &&
          !resource.isAdSuspect &&
          !resource.isFragment) {
        return resource;
      }
    }
    return resources.first;
  }

  List<VideoResource> get recommendedResources {
    final recommended = recommendedResource;
    if (recommended == null) return const [];
    return [recommended];
  }

  List<VideoResource> get otherResources {
    final recommended = recommendedResource;
    return resources
        .where(
          (resource) =>
              resource != recommended &&
              resource.isPlayable &&
              !resource.isAdSuspect &&
              !resource.isFragment,
        )
        .toList();
  }

  List<VideoResource> get adResources {
    return resources.where((resource) => resource.isAdSuspect).toList();
  }

  List<VideoResource> get fragmentResources {
    return resources.where((resource) => resource.isFragment).toList();
  }

  ParseRecord copyWith({
    String? pageUrl,
    String? pageTitle,
    DateTime? parsedAt,
    ParseRecordStatus? status,
    List<VideoResource>? resources,
    String? message,
    String? sourceSite,
    String? recommendedUrl,
  }) {
    return ParseRecord(
      pageUrl: pageUrl ?? this.pageUrl,
      pageTitle: pageTitle ?? this.pageTitle,
      parsedAt: parsedAt ?? this.parsedAt,
      status: status ?? this.status,
      resources: resources ?? this.resources,
      message: message ?? this.message,
      sourceSite: sourceSite ?? this.sourceSite,
      recommendedUrl: recommendedUrl ?? this.recommendedUrl,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'pageUrl': pageUrl,
      'pageTitle': pageTitle,
      'parsedAt': parsedAt.toIso8601String(),
      'status': status.name,
      'resources': resources.map((resource) => resource.toJson()).toList(),
      'message': message,
      'sourceSite': sourceSite,
      'recommendedUrl': recommendedUrl,
    };
  }

  factory ParseRecord.fromJson(Map<String, dynamic> json) {
    final rawResources = json['resources'];
    return ParseRecord(
      pageUrl: json['pageUrl']?.toString() ?? '',
      pageTitle: json['pageTitle']?.toString() ?? '网页视频',
      parsedAt: DateTime.tryParse(json['parsedAt']?.toString() ?? '') ??
          DateTime.now(),
      status: _statusFromName(json['status']?.toString() ?? ''),
      resources: rawResources is List
          ? rawResources
              .whereType<Map>()
              .map(
                (item) =>
                    VideoResource.fromJson(Map<String, dynamic>.from(item)),
              )
              .toList()
          : const [],
      message: json['message']?.toString() ?? '',
      sourceSite: json['sourceSite']?.toString() ?? '',
      recommendedUrl: json['recommendedUrl']?.toString() ?? '',
    );
  }

  static ParseRecordStatus _statusFromName(String value) {
    for (final status in ParseRecordStatus.values) {
      if (status.name == value) return status;
    }
    return ParseRecordStatus.found;
  }
}

import 'dart:async';

import '../models/video_resource.dart';
import 'video_sniffer.dart';

class SnifferPageContext {
  const SnifferPageContext({
    required this.pageUrl,
    required this.pageTitle,
    required this.userAgent,
    required this.cookie,
  });

  final String pageUrl;
  final String pageTitle;
  final String userAgent;
  final String cookie;
}

class _SnifferCandidate {
  const _SnifferCandidate({
    required this.url,
    required this.source,
    this.title = '',
    this.duration = Duration.zero,
    this.thumbnailUrl = '',
    this.isCurrentPlayback = false,
    this.playerId = '',
  });

  final String url;
  final String source;
  final String title;
  final Duration duration;
  final String thumbnailUrl;
  final bool isCurrentPlayback;
  final String playerId;

  _SnifferCandidate merge(_SnifferCandidate other) {
    final current = isCurrentPlayback || other.isCurrentPlayback;
    return _SnifferCandidate(
      url: other.url.isNotEmpty ? other.url : url,
      source: _mergeSource(source, other.source),
      title: other.title.isNotEmpty ? other.title : title,
      duration: other.duration > Duration.zero ? other.duration : duration,
      thumbnailUrl:
          other.thumbnailUrl.isNotEmpty ? other.thumbnailUrl : thumbnailUrl,
      isCurrentPlayback: current,
      playerId: other.playerId.isNotEmpty ? other.playerId : playerId,
    );
  }

  String _mergeSource(String a, String b) {
    if (a == b || b.isEmpty) return a;
    if (a.isEmpty) return b;
    if (a.toLowerCase().contains('current')) return a;
    if (b.toLowerCase().contains('current')) return b;
    if (a.toLowerCase().contains('video-play')) return a;
    if (b.toLowerCase().contains('video-play')) return b;
    return '$a/$b';
  }
}

class VideoSnifferController {
  VideoSnifferController({
    required this.sniffer,
    required this.loadContext,
    required this.onResourcesChanged,
    this.debounce = const Duration(milliseconds: 800),
    this.maxResources = 50,
  });

  final VideoSniffer sniffer;
  final Future<SnifferPageContext> Function() loadContext;
  final void Function(List<VideoResource> resources) onResourcesChanged;
  final Duration debounce;
  final int maxResources;

  final Map<String, _SnifferCandidate> _pending = {};
  final Map<String, VideoResource> _resources = {};
  Timer? _timer;
  Timer? _emitTimer;
  bool _processing = false;
  String _lastPageUrl = '';

  List<VideoResource> get resources =>
      sniffer.prioritizeResources(_resources.values, limit: maxResources);

  void updatePageUrl(String value) {
    _lastPageUrl = value;
  }

  void reset({String pageUrl = ''}) {
    _timer?.cancel();
    _emitTimer?.cancel();
    _pending.clear();
    _resources.clear();
    _processing = false;
    _lastPageUrl = pageUrl;
    onResourcesChanged(const []);
  }

  void capture(
    String rawUrl,
    String source, {
    String title = '',
    Duration duration = Duration.zero,
    String thumbnailUrl = '',
    bool isCurrentPlayback = false,
    String playerId = '',
  }) {
    if (!sniffer.isLikelyMediaCandidate(rawUrl)) {
      return;
    }
    final base = Uri.tryParse(_lastPageUrl);
    final key = sniffer.dedupeKey(rawUrl, base: base);
    final next = _SnifferCandidate(
      url: rawUrl,
      source: source,
      title: title,
      duration: duration,
      thumbnailUrl: thumbnailUrl,
      isCurrentPlayback: isCurrentPlayback,
      playerId: playerId,
    );
    final existingResource = _resources[key];
    if (existingResource != null) {
      _resources[key] = existingResource.copyWith(
        source: next
            .merge(
              _SnifferCandidate(
                url: existingResource.url,
                source: existingResource.source,
                title: existingResource.title,
                duration: existingResource.duration,
                thumbnailUrl: existingResource.thumbnailUrl,
                isCurrentPlayback: existingResource.isCurrentPlayback,
                playerId: existingResource.playerId,
              ),
            )
            .source,
        title: title.isNotEmpty ? title : existingResource.title,
        duration:
            duration > Duration.zero ? duration : existingResource.duration,
        thumbnailUrl: thumbnailUrl.isNotEmpty
            ? thumbnailUrl
            : existingResource.thumbnailUrl,
        isCurrentPlayback: existingResource.isCurrentPlayback ||
            isCurrentPlayback ||
            source.toLowerCase().contains('current') ||
            source.toLowerCase().contains('video-play'),
        playerId: playerId.isNotEmpty ? playerId : existingResource.playerId,
      );
      _scheduleEmit();
      return;
    }
    final existingPending = _pending[key];
    _pending[key] =
        existingPending == null ? next : existingPending.merge(next);
    _timer?.cancel();
    _timer = Timer(debounce, () => unawaited(flush()));
  }

  Future<void> flush() async {
    _timer?.cancel();
    if (_processing || _pending.isEmpty) {
      return;
    }
    _processing = true;
    final candidates = List<_SnifferCandidate>.from(_pending.values);
    _pending.clear();
    try {
      final context = await loadContext();
      _lastPageUrl = context.pageUrl;
      for (final candidate in candidates) {
        final resource = sniffer.resourceFromUrl(
          candidate.url,
          pageTitle:
              candidate.title.isNotEmpty ? candidate.title : context.pageTitle,
          pageUrl: context.pageUrl,
          source: candidate.source,
          userAgent: context.userAgent,
          cookie: context.cookie,
          duration: candidate.duration,
          thumbnailUrl: candidate.thumbnailUrl,
          isCurrentPlayback: candidate.isCurrentPlayback,
          playerId: candidate.playerId,
          allowUnknown: true,
        );
        if (resource == null) {
          continue;
        }
        final resolved = await sniffer.probeResource(resource);
        for (final item in resolved) {
          _resources[sniffer.dedupeKey(item.url)] = item;
        }
      }
      _scheduleEmit();
    } finally {
      _processing = false;
      if (_pending.isNotEmpty) {
        _timer = Timer(debounce, () => unawaited(flush()));
      }
    }
  }

  void dispose() {
    _timer?.cancel();
    _emitTimer?.cancel();
  }

  void _scheduleEmit() {
    _emitTimer?.cancel();
    _emitTimer = Timer(debounce, () => onResourcesChanged(resources));
  }
}

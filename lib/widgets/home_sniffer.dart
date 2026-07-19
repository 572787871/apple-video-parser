import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../models/parse_record.dart';
import '../models/video_resource.dart';
import '../services/video_sniffer.dart';
import '../services/video_sniffer_controller.dart';

class HomeSniffer extends StatefulWidget {
  const HomeSniffer({
    required this.initialUrl,
    required this.onProgress,
    required this.onFound,
    required this.onNotFound,
    required this.onFailed,
    super.key,
  });

  final String initialUrl;
  final ValueChanged<int> onProgress;
  final ValueChanged<ParseRecord> onFound;
  final void Function(String pageUrl, String pageTitle) onNotFound;
  final void Function(String pageUrl, String pageTitle, Object error) onFailed;

  @override
  State<HomeSniffer> createState() => _HomeSnifferState();
}

class _HomeSnifferState extends State<HomeSniffer> {
  final sniffer = VideoSniffer();
  late final VideoSnifferController snifferController;
  InAppWebViewController? webController;
  Timer? scanTimer;
  Timer? timeoutTimer;
  String currentUrl = '';
  String userAgent = '';
  List<VideoResource> resources = const [];
  bool completed = false;
  bool scanBusy = false;

  @override
  void initState() {
    super.initState();
    currentUrl = _normalized(widget.initialUrl);
    snifferController = VideoSnifferController(
      sniffer: sniffer,
      loadContext: _snifferContext,
      onResourcesChanged: (values) {
        if (!mounted || completed) return;
        resources = values;
        final count = _downloadable(values).length;
        widget.onProgress(count);
        if (count > 0) {
          unawaited(_finishFound(values));
        }
      },
      debounce: const Duration(milliseconds: 350),
    )..updatePageUrl(currentUrl);
  }

  @override
  void dispose() {
    scanTimer?.cancel();
    timeoutTimer?.cancel();
    snifferController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 1,
      height: 1,
      child: Opacity(
        opacity: 0.01,
        child: IgnorePointer(
          child: InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(currentUrl)),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              mediaPlaybackRequiresUserGesture: false,
              allowsInlineMediaPlayback: true,
              useShouldInterceptRequest: true,
              useShouldInterceptAjaxRequest: true,
              useShouldInterceptFetchRequest: true,
            ),
            onWebViewCreated: (controller) async {
              webController = controller;
              controller.addJavaScriptHandler(
                handlerName: 'VidSniffer',
                callback: (args) {
                  for (final arg in args) {
                    final candidate = _candidateFromDynamic(arg);
                    if (candidate != null) {
                      _captureCandidate(candidate);
                    }
                  }
                },
              );
              await _updateUserAgent();
              unawaited(_injectSniffer());
              _startTimers();
            },
            onLoadStart: (controller, url) {
              final value = url?.toString() ?? currentUrl;
              debugPrint('[home-sniffer] load start: $value');
              currentUrl = value;
              snifferController.reset(pageUrl: value);
              _captureCandidate(_CapturedCandidate(url: value, source: 'page'));
              unawaited(_injectSniffer());
            },
            onLoadStop: (controller, url) async {
              currentUrl = url?.toString() ?? currentUrl;
              debugPrint('[home-sniffer] load finish: $currentUrl');
              await _updateUserAgent();
              await _injectSniffer();
              await _scanDom();
              await snifferController.flush();
            },
            onReceivedError: (controller, request, error) {
              debugPrint('[home-sniffer] error: ${error.description}');
              if (!completed && request.isForMainFrame == true) {
                unawaited(_finishFailed(error.description));
              }
            },
            onLoadResource: (controller, resource) {
              _captureCandidate(
                _CapturedCandidate(
                  url: resource.url.toString(),
                  source: 'resource',
                ),
              );
            },
            shouldInterceptRequest: (controller, request) async {
              _captureCandidate(
                _CapturedCandidate(
                  url: request.url.toString(),
                  source: 'resource',
                ),
              );
              return null;
            },
            shouldInterceptFetchRequest: (controller, request) async {
              final url = request.url?.toString();
              if (url != null) {
                _captureCandidate(
                    _CapturedCandidate(url: url, source: 'fetch'));
              }
              return request;
            },
            shouldInterceptAjaxRequest: (controller, request) async {
              final url = request.url?.toString();
              if (url != null) {
                _captureCandidate(_CapturedCandidate(url: url, source: 'xhr'));
              }
              return request;
            },
          ),
        ),
      ),
    );
  }

  void _startTimers() {
    if (completed) return;
    scanTimer?.cancel();
    timeoutTimer?.cancel();
    widget.onProgress(0);
    scanTimer = Timer.periodic(
      const Duration(milliseconds: 700),
      (_) => unawaited(_scanTick()),
    );
    timeoutTimer = Timer(
      const Duration(seconds: 5),
      () => unawaited(_finishNotFound()),
    );
    unawaited(_scanTick());
  }

  Future<void> _scanTick() async {
    if (completed || scanBusy) return;
    scanBusy = true;
    try {
      await _injectSniffer();
      await _scanDom();
      await snifferController.flush();
      final count = _downloadable(resources).length;
      if (count > 0) {
        await _finishFound(resources);
      } else {
        widget.onProgress(0);
      }
    } catch (error) {
      debugPrint('[home-sniffer] scan error: $error');
    } finally {
      scanBusy = false;
    }
  }

  Future<void> _finishFound(List<VideoResource> values) async {
    if (completed) return;
    final downloadable = _downloadable(values);
    if (downloadable.isEmpty) return;
    completed = true;
    scanTimer?.cancel();
    timeoutTimer?.cancel();
    final title = await _pageTitle();
    final prioritized = sniffer.prioritizeResources(values);
    final recommended = _firstDownloadable(prioritized);
    widget.onFound(
      ParseRecord(
        pageUrl: currentUrl,
        pageTitle: title,
        parsedAt: DateTime.now(),
        status: ParseRecordStatus.found,
        resources: prioritized,
        sourceSite: Uri.tryParse(currentUrl)?.host ?? '',
        recommendedUrl: recommended?.url ?? '',
      ),
    );
  }

  Future<void> _finishNotFound() async {
    if (completed) return;
    await _scanTick();
    if (completed) return;
    completed = true;
    scanTimer?.cancel();
    timeoutTimer?.cancel();
    widget.onNotFound(currentUrl, await _pageTitle());
  }

  Future<void> _finishFailed(Object error) async {
    if (completed) return;
    completed = true;
    scanTimer?.cancel();
    timeoutTimer?.cancel();
    widget.onFailed(currentUrl, await _pageTitle(), error);
  }

  Future<void> _scanDom() async {
    final controller = webController;
    if (controller == null || completed) return;
    final result = await controller.evaluateJavascript(source: _domScanScript);
    for (final candidate in _decodeJsCandidates(result)) {
      _captureCandidate(candidate);
    }
  }

  Future<void> _injectSniffer() async {
    final controller = webController;
    if (controller == null || completed) return;
    try {
      await controller.evaluateJavascript(source: _hookScript);
    } catch (_) {}
  }

  Future<void> _updateUserAgent() async {
    try {
      final value = await webController?.evaluateJavascript(
        source: 'navigator.userAgent',
      );
      if (value != null) {
        userAgent = value.toString().replaceAll('"', '');
      }
    } catch (_) {}
  }

  Future<SnifferPageContext> _snifferContext() async {
    return SnifferPageContext(
      pageUrl: currentUrl,
      pageTitle: await _pageTitle(),
      userAgent: userAgent,
      cookie: await _cookiesFor(currentUrl),
    );
  }

  Future<String> _pageTitle() async {
    try {
      final title = await webController?.evaluateJavascript(source: '''
(() => {
  const meta = document.querySelector('meta[property="og:title"], meta[name="twitter:title"], meta[itemprop="name"]');
  const video = document.querySelector('video[title], [data-video-title], [data-title]');
  return (meta && meta.content) || (video && (video.getAttribute('title') || video.getAttribute('data-video-title') || video.getAttribute('data-title'))) || document.title || '';
})();
''');
      final trimmed = title?.toString().replaceAll('"', '').trim();
      if (trimmed != null && trimmed.isNotEmpty) {
        return trimmed;
      }
    } catch (_) {}
    return Uri.tryParse(currentUrl)?.host ?? '网页视频';
  }

  Future<String> _cookiesFor(String pageUrl) async {
    try {
      final cookies = await CookieManager.instance().getCookies(
        url: WebUri(pageUrl),
      );
      return cookies.map((item) => '${item.name}=${item.value}').join('; ');
    } catch (_) {
      return '';
    }
  }

  void _captureCandidate(_CapturedCandidate candidate) {
    if (completed) return;
    snifferController.updatePageUrl(currentUrl);
    snifferController.capture(
      candidate.url,
      candidate.source,
      title: candidate.title,
      duration: candidate.duration,
      thumbnailUrl: candidate.thumbnailUrl,
      isCurrentPlayback: candidate.isCurrentPlayback,
      playerId: candidate.playerId,
    );
  }

  List<VideoResource> _downloadable(List<VideoResource> values) {
    return values
        .where(
            (item) => item.isPlayable && !item.isAdSuspect && !item.isFragment)
        .toList();
  }

  VideoResource? _firstDownloadable(List<VideoResource> values) {
    for (final item in values) {
      if (item.isPlayable && !item.isAdSuspect && !item.isFragment) {
        return item;
      }
    }
    return null;
  }

  List<_CapturedCandidate> _decodeJsCandidates(Object? value) {
    if (value == null) return const [];
    if (value is List) {
      return value
          .map(_candidateFromDynamic)
          .whereType<_CapturedCandidate>()
          .toList();
    }
    final text = value.toString();
    try {
      var decoded = jsonDecode(text);
      if (decoded is String) {
        decoded = jsonDecode(decoded);
      }
      if (decoded is List) {
        return decoded
            .map(_candidateFromDynamic)
            .whereType<_CapturedCandidate>()
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  _CapturedCandidate? _candidateFromDynamic(Object? value) {
    if (value == null) return null;
    if (value is String) {
      return _CapturedCandidate(url: value, source: 'dom');
    }
    if (value is! Map) return null;
    final url = value['url']?.toString() ?? '';
    if (url.isEmpty) return null;
    final seconds = double.tryParse('${value['duration'] ?? ''}') ?? 0;
    return _CapturedCandidate(
      url: url,
      source: value['source']?.toString() ?? 'jsHook',
      title: value['title']?.toString() ?? '',
      duration: seconds > 0
          ? Duration(milliseconds: (seconds * 1000).round())
          : Duration.zero,
      thumbnailUrl: value['poster']?.toString() ??
          value['thumbnailUrl']?.toString() ??
          '',
      isCurrentPlayback: value['current'] == true,
      playerId: value['playerId']?.toString() ?? '',
    );
  }

  String _normalized(String value) {
    final text = value.trim();
    if (text.startsWith('http://') || text.startsWith('https://')) return text;
    if (text.isEmpty || text == 'https://') return 'https://example.com';
    return 'https://$text';
  }

  static const String _domScanScript = r'''
(() => {
  const out = new Map();
  const pageTitle = (() => {
    const meta = document.querySelector('meta[property="og:title"], meta[name="twitter:title"], meta[itemprop="name"]');
    return (meta && meta.content) || document.title || '';
  })();
  const nodeTitle = (node) => {
    if (!node) return pageTitle;
    const video = node.tagName === 'VIDEO' || node.tagName === 'AUDIO' ? node : node.closest && node.closest('video,audio');
    const owner = video || node;
    return owner.getAttribute('title') ||
      owner.getAttribute('data-title') ||
      owner.getAttribute('data-video-title') ||
      owner.getAttribute('aria-label') ||
      pageTitle;
  };
  const playerId = (node) => {
    if (!node) return '';
    const video = node.tagName === 'VIDEO' || node.tagName === 'AUDIO' ? node : node.closest && node.closest('video,audio');
    const owner = video || node;
    return owner.id ||
      owner.getAttribute('data-player') ||
      owner.getAttribute('data-player-id') ||
      owner.getAttribute('data-video-id') ||
      '';
  };
  const poster = (node) => {
    if (!node) return '';
    const video = node.tagName === 'VIDEO' || node.tagName === 'AUDIO' ? node : node.closest && node.closest('video,audio');
    return (video && (video.poster || video.getAttribute('poster'))) || '';
  };
  const duration = (node) => {
    const video = node && (node.tagName === 'VIDEO' || node.tagName === 'AUDIO' ? node : node.closest && node.closest('video,audio'));
    return video && isFinite(video.duration) && video.duration > 0 ? video.duration : 0;
  };
  const isCurrent = (node, source) => {
    const video = node && (node.tagName === 'VIDEO' || node.tagName === 'AUDIO' ? node : node.closest && node.closest('video,audio'));
    return /current|play/i.test(source) || !!(video && (!video.paused || video.currentTime > 0));
  };
  const push = (value, source, node) => {
    try {
      if (!value || typeof value !== 'string') return;
      const absolute = new URL(value, location.href).href;
      out.set(absolute, {
        url: absolute,
        source,
        title: nodeTitle(node),
        duration: duration(node),
        poster: poster(node),
        current: isCurrent(node, source),
        playerId: playerId(node)
      });
    } catch (_) {}
  };
  document.querySelectorAll('video,audio').forEach((node) => {
    push(node.currentSrc, 'video-current', node);
    push(node.src, 'video-tag', node);
    push(node.getAttribute('src'), 'video-tag', node);
    push(node.getAttribute('data-src'), 'video-tag', node);
    node.querySelectorAll('source').forEach((source) => {
      push(source.src, 'video-source', source);
      push(source.getAttribute('src'), 'video-source', source);
      push(source.getAttribute('data-src'), 'video-source', source);
    });
  });
  document.querySelectorAll('a[href]').forEach((node) => {
    const href = node.getAttribute('href') || '';
    if (/\.(mp4|m3u8|m4v|mov|ts|m4s)(\?|$)/i.test(href)) push(href, 'dom-link', node);
  });
  const html = document.documentElement.outerHTML || '';
  const matches = html.match(/https?:[^"'\\\s<>]+?\.(?:mp4|m3u8|m4v|mov|ts|m4s)(?:\?[^"'\\\s<>]*)?/ig) || [];
  matches.forEach((url) => push(url, 'dom-html', null));
  return JSON.stringify(Array.from(out.values()));
})();
''';

  static const String _hookScript = r'''
(() => {
  if (window.__videoDownloaderHooked) return;
  window.__videoDownloaderHooked = true;
  const pageTitle = () => {
    const meta = document.querySelector('meta[property="og:title"], meta[name="twitter:title"], meta[itemprop="name"]');
    return (meta && meta.content) || document.title || '';
  };
  const metaFor = (element, source) => {
    const media = element && (element.tagName === 'VIDEO' || element.tagName === 'AUDIO' ? element : element.closest && element.closest('video,audio'));
    const owner = media || element;
    return {
      title: (owner && (owner.getAttribute('title') || owner.getAttribute('data-title') || owner.getAttribute('data-video-title') || owner.getAttribute('aria-label'))) || pageTitle(),
      duration: media && isFinite(media.duration) && media.duration > 0 ? media.duration : 0,
      poster: (media && (media.poster || media.getAttribute('poster'))) || '',
      current: /current|play/i.test(source) || !!(media && (!media.paused || media.currentTime > 0)),
      playerId: (owner && (owner.id || owner.getAttribute('data-player') || owner.getAttribute('data-player-id') || owner.getAttribute('data-video-id'))) || ''
    };
  };
  const post = (url, source, element) => {
    try {
      if (!url || typeof url !== 'string') return;
      const absolute = new URL(url, location.href).href;
      window.flutter_inappwebview.callHandler('VidSniffer', {url: absolute, source, ...metaFor(element, source)});
    } catch (_) {}
  };
  const originalFetch = window.fetch;
  if (originalFetch) {
    window.fetch = function() {
      try {
        const input = arguments[0];
        post(typeof input === 'string' ? input : input && input.url, 'fetch', null);
      } catch (_) {}
      return originalFetch.apply(this, arguments).then((response) => {
        try { post(response.url, 'fetch-response', null); } catch (_) {}
        return response;
      });
    };
  }
  const originalOpen = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function(method, url) {
    post(url, 'xhr', null);
    return originalOpen.apply(this, arguments);
  };
  const desc = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'src');
  if (desc && desc.set) {
    Object.defineProperty(HTMLMediaElement.prototype, 'src', {
      set: function(value) { post(value, 'media-src', this); return desc.set.call(this, value); },
      get: function() { return desc.get.call(this); }
    });
  }
  const originalPlay = HTMLMediaElement.prototype.play;
  HTMLMediaElement.prototype.play = function() {
    post(this.currentSrc || this.src, 'video-current', this);
    return originalPlay.apply(this, arguments);
  };
  const bind = (node) => {
    if (!node || node.__vidSnifferBound) return;
    node.__vidSnifferBound = true;
    ['play', 'loadedmetadata', 'canplay', 'durationchange'].forEach((event) => {
      node.addEventListener(event, () => post(node.currentSrc || node.src, event === 'play' ? 'video-current' : 'video-tag', node), true);
    });
  };
  document.querySelectorAll('video,audio').forEach(bind);
  new MutationObserver((mutations) => {
    mutations.forEach((mutation) => {
      mutation.addedNodes && mutation.addedNodes.forEach((node) => {
        if (!node.querySelectorAll) return;
        if (node.tagName === 'VIDEO' || node.tagName === 'AUDIO') bind(node);
        node.querySelectorAll('video,audio').forEach(bind);
      });
    });
  }).observe(document.documentElement, {childList: true, subtree: true});
})();
''';
}

class _CapturedCandidate {
  const _CapturedCandidate({
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
}

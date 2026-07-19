import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../models/video_resource.dart';
import '../services/ui_state.dart';
import '../services/video_sniffer.dart';
import '../services/video_sniffer_controller.dart';
import '../widgets/resource_sheet.dart';

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({
    this.initialUrl = '',
    this.autoDiscover = false,
    this.autoParseOnly = false,
    super.key,
  });

  final String initialUrl;
  final bool autoDiscover;
  final bool autoParseOnly;

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  final sniffer = VideoSniffer();
  final addressController = TextEditingController();
  late final VideoSnifferController snifferController;
  InAppWebViewController? webController;
  PullToRefreshController? pullToRefreshController;
  Timer? noResourceHintTimer;
  Timer? autoResultTimer;
  Timer? autoScanTimer;
  double progress = 0;
  String? errorText;
  String currentUrl = '';
  String userAgent = '';
  String autoStatus = '正在解析网页...';
  int autoFoundCount = 0;
  bool browserVisible = true;
  bool toolbarVisible = true;
  bool autoDialogVisible = false;
  bool autoResultFinished = false;
  bool autoScanBusy = false;
  int lastScrollY = 0;

  @override
  void initState() {
    super.initState();
    final initial = _normalized(widget.initialUrl);
    debugPrint('[webview] initialUrl=$initial');
    addressController.text = initial;
    currentUrl = initial;
    browserVisible = !widget.autoParseOnly;
    snifferController = VideoSnifferController(
      sniffer: sniffer,
      loadContext: _snifferContext,
      onResourcesChanged: (resources) {
        if (!mounted) return;
        UiStateScope.of(context).setResources(resources);
        final found = _downloadableResources(resources).length;
        if (found != autoFoundCount && widget.autoParseOnly) {
          setState(() {
            autoFoundCount = found;
            if (found > 0) {
              autoStatus = '已发现 $found 个视频，正在生成下载列表...';
            }
          });
        }
        if (found > 0) {
          _scheduleAutoResult(shortDelay: true);
        }
      },
    )..updatePageUrl(initial);
    pullToRefreshController = PullToRefreshController(
      settings: PullToRefreshSettings(color: const Color(0xff2563eb)),
      onRefresh: () => webController?.reload(),
    );
  }

  @override
  void dispose() {
    noResourceHintTimer?.cancel();
    autoResultTimer?.cancel();
    autoScanTimer?.cancel();
    snifferController.dispose();
    addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = UiStateScope.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final canGoBack = await webController?.canGoBack() ?? false;
        if (canGoBack) {
          await webController?.goBack();
        } else if (context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    height: browserVisible && toolbarVisible ? 50 : 0,
                    curve: Curves.easeOut,
                    child: ClipRect(child: _browserToolbar()),
                  ),
                  if ((browserVisible || !widget.autoParseOnly) &&
                      progress > 0 &&
                      progress < 1)
                    LinearProgressIndicator(value: progress, minHeight: 2),
                  Expanded(
                    child: Stack(
                      children: [
                        Opacity(
                          opacity: browserVisible ? 1 : 0.02,
                          child: IgnorePointer(
                            ignoring: !browserVisible,
                            child: InAppWebView(
                              initialUrlRequest: URLRequest(
                                url: WebUri(currentUrl),
                              ),
                              initialSettings: InAppWebViewSettings(
                                javaScriptEnabled: true,
                                mediaPlaybackRequiresUserGesture: false,
                                allowsInlineMediaPlayback: true,
                                useShouldInterceptRequest: true,
                                useShouldInterceptAjaxRequest: true,
                                useShouldInterceptFetchRequest: true,
                              ),
                              pullToRefreshController: pullToRefreshController,
                              onWebViewCreated: (controller) async {
                                webController = controller;
                                controller.addJavaScriptHandler(
                                  handlerName: 'VidSniffer',
                                  callback: (args) {
                                    for (final arg in args) {
                                      final candidate = _candidateFromDynamic(
                                        arg,
                                      );
                                      if (candidate != null) {
                                        _captureCandidate(candidate);
                                      }
                                    }
                                  },
                                );
                                await _updateUserAgent();
                                unawaited(_injectSniffer());
                                _startAutoParseLoop(reset: true);
                              },
                              onLoadStart: (controller, url) {
                                final value = url?.toString() ?? '';
                                debugPrint('[webview] load start: $value');
                                setState(() {
                                  currentUrl = value;
                                  addressController.text = value;
                                  errorText = null;
                                  progress = 0;
                                });
                                snifferController.reset(pageUrl: value);
                                _captureCandidate(
                                  _CapturedCandidate(
                                    url: value,
                                    source: 'resource',
                                  ),
                                );
                                unawaited(_injectSniffer());
                                _startAutoParseLoop(reset: true);
                              },
                              onProgressChanged: (controller, value) {
                                debugPrint('[webview] progress: $value');
                                if (!widget.autoParseOnly || browserVisible) {
                                  setState(() => progress = value / 100);
                                } else {
                                  progress = value / 100;
                                }
                              },
                              onLoadStop: (controller, url) async {
                                final value = url?.toString() ?? '';
                                debugPrint('[webview] load finish: $value');
                                pullToRefreshController?.endRefreshing();
                                setState(() {
                                  currentUrl = value;
                                  addressController.text = value;
                                  progress = 1;
                                });
                                await _updateUserAgent();
                                await _injectSniffer();
                                await _scanDom();
                                await snifferController.flush();
                                _scheduleNoResourceHint();
                                _scheduleAutoResult();
                              },
                              onReceivedError: (controller, request, error) {
                                debugPrint(
                                  '[webview] error: ${error.description}',
                                );
                                pullToRefreshController?.endRefreshing();
                                setState(() => errorText = error.description);
                              },
                              onLoadResource: (controller, resource) {
                                _captureCandidate(
                                  _CapturedCandidate(
                                    url: resource.url.toString(),
                                    source: 'resource',
                                  ),
                                );
                              },
                              shouldInterceptRequest:
                                  (controller, request) async {
                                    final url = request.url.toString();
                                    _captureCandidate(
                                      _CapturedCandidate(
                                        url: url,
                                        source: 'resource',
                                      ),
                                    );
                                    return null;
                                  },
                              shouldInterceptFetchRequest:
                                  (controller, request) async {
                                    final url = request.url?.toString();
                                    if (url != null) {
                                      _captureCandidate(
                                        _CapturedCandidate(
                                          url: url,
                                          source: 'fetch',
                                        ),
                                      );
                                    }
                                    return request;
                                  },
                              shouldInterceptAjaxRequest:
                                  (controller, request) async {
                                    final url = request.url?.toString();
                                    if (url != null) {
                                      _captureCandidate(
                                        _CapturedCandidate(
                                          url: url,
                                          source: 'xhr',
                                        ),
                                      );
                                    }
                                    return request;
                                  },
                              onScrollChanged: (controller, x, y) {
                                if (!browserVisible) return;
                                final shouldShow = y < lastScrollY || y < 24;
                                if (shouldShow != toolbarVisible && mounted) {
                                  setState(() => toolbarVisible = shouldShow);
                                }
                                lastScrollY = y;
                              },
                            ),
                          ),
                        ),
                        if (errorText != null)
                          Positioned.fill(
                            child: ColoredBox(
                              color: Theme.of(context).colorScheme.surface,
                              child: Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Text(
                                    '网页加载失败：$errorText',
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (!browserVisible) _autoParsingOverlay(),
                      ],
                    ),
                  ),
                ],
              ),
              if (browserVisible)
                Positioned(
                  right: 16,
                  bottom: 18,
                  child: FloatingActionButton.extended(
                    heroTag: 'discoverVideo',
                    onPressed: () async {
                      await _scanDom();
                      await snifferController.flush();
                      if (!context.mounted) return;
                      showResourceSheet(context, state.resources);
                    },
                    icon: const Icon(Icons.video_library_rounded),
                    label: Text(
                      state.resources.isEmpty
                          ? '发现视频'
                          : '发现视频 (${state.resources.length})',
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _browserToolbar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Row(
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            onPressed: _backOrClose,
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            onPressed: () => webController?.goForward(),
            icon: const Icon(Icons.arrow_forward_ios_rounded),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 19,
            onPressed: () => webController?.reload(),
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: SizedBox(
              height: 38,
              child: TextField(
                controller: addressController,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.go,
                style: const TextStyle(fontSize: 13),
                onSubmitted: (_) => _load(),
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.lock_outline_rounded, size: 16),
                  hintText: '输入网址',
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _autoParsingOverlay() {
    return Positioned.fill(
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surface,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 18),
                Text(
                  '正在自动解析视频',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Text(
                  autoStatus,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                if (autoFoundCount > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    '已发现 $autoFoundCount 个视频资源',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                FilledButton.tonalIcon(
                  onPressed: () => setState(() {
                    autoResultFinished = true;
                    autoResultTimer?.cancel();
                    autoScanTimer?.cancel();
                    browserVisible = true;
                    toolbarVisible = true;
                  }),
                  icon: const Icon(Icons.language_rounded),
                  label: const Text('进入网页播放并嗅探'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _backOrClose() async {
    final canGoBack = await webController?.canGoBack() ?? false;
    if (canGoBack) {
      await webController?.goBack();
    } else if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _load() async {
    FocusScope.of(context).unfocus();
    final url = _normalized(addressController.text);
    debugPrint('[webview] load start: $url');
    setState(() {
      currentUrl = url;
      addressController.text = url;
      errorText = null;
      progress = 0;
    });
    snifferController.reset(pageUrl: url);
    await webController?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
  }

  Future<void> _scanDom() async {
    final controller = webController;
    if (controller == null) return;
    final result = await controller.evaluateJavascript(source: _domScanScript);
    final candidates = _decodeJsCandidates(result);
    for (final candidate in candidates) {
      _captureCandidate(candidate);
    }
  }

  Future<void> _injectSniffer() async {
    await webController?.evaluateJavascript(source: _hookScript);
  }

  Future<void> _updateUserAgent() async {
    final value = await webController?.evaluateJavascript(
      source: 'navigator.userAgent',
    );
    if (value != null) {
      userAgent = value.toString().replaceAll('"', '');
    }
  }

  Future<String> _cookiesFor(String pageUrl) async {
    try {
      final uri = WebUri(pageUrl);
      final cookies = await CookieManager.instance().getCookies(url: uri);
      return cookies.map((item) => '${item.name}=${item.value}').join('; ');
    } catch (_) {
      return '';
    }
  }

  void _captureCandidate(_CapturedCandidate candidate) {
    snifferController.updatePageUrl(
      currentUrl.isEmpty ? addressController.text : currentUrl,
    );
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

  Future<SnifferPageContext> _snifferContext() async {
    final pageUrl = currentUrl.isEmpty ? addressController.text : currentUrl;
    return SnifferPageContext(
      pageUrl: pageUrl,
      pageTitle: await _pageTitle(),
      userAgent: userAgent,
      cookie: await _cookiesFor(pageUrl),
    );
  }

  void _scheduleNoResourceHint() {
    if (!widget.autoDiscover || !browserVisible) return;
    noResourceHintTimer?.cancel();
    noResourceHintTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      final state = UiStateScope.of(context);
      if (state.resources.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('请点击播放网页视频后再点发现视频')));
      }
    });
  }

  void _scheduleAutoResult({bool shortDelay = false}) {
    if (!widget.autoParseOnly ||
        browserVisible ||
        autoDialogVisible ||
        autoResultFinished) {
      return;
    }
    autoResultTimer?.cancel();
    autoResultTimer = Timer(
      shortDelay
          ? const Duration(milliseconds: 250)
          : const Duration(seconds: 5),
      () async {
        if (!mounted ||
            browserVisible ||
            autoDialogVisible ||
            autoResultFinished) {
          return;
        }
        await _scanDom();
        await snifferController.flush();
        if (!mounted) return;
        final state = UiStateScope.of(context);
        final downloadable = _downloadableResources(state.resources);
        if (downloadable.isNotEmpty) {
          await _showAutoResources(state.resources);
        } else {
          await _showAutoFailedPrompt();
        }
      },
    );
  }

  void _retryAutoParse() {
    autoDialogVisible = false;
    autoResultFinished = false;
    autoResultTimer?.cancel();
    autoScanTimer?.cancel();
    setState(() {
      browserVisible = false;
      toolbarVisible = false;
      autoFoundCount = 0;
      autoStatus = '正在解析网页...';
    });
    _load();
  }

  void _startAutoParseLoop({bool reset = false}) {
    if (!widget.autoParseOnly || browserVisible) return;
    if (reset) {
      autoResultFinished = false;
      autoFoundCount = 0;
    }
    autoScanTimer?.cancel();
    autoResultTimer?.cancel();
    if (mounted) {
      setState(() => autoStatus = '正在解析网页...');
    }
    autoScanTimer = Timer.periodic(
      const Duration(milliseconds: 700),
      (_) => unawaited(_autoScanTick()),
    );
    unawaited(_autoScanTick());
    _scheduleAutoResult();
  }

  Future<void> _autoScanTick() async {
    if (!widget.autoParseOnly ||
        browserVisible ||
        autoDialogVisible ||
        autoResultFinished ||
        autoScanBusy) {
      return;
    }
    autoScanBusy = true;
    try {
      if (mounted) {
        setState(() {
          autoStatus = autoFoundCount > 0 ? '正在生成下载列表...' : '正在监听视频资源...';
        });
      }
      await _injectSniffer();
      await _scanDom();
      await snifferController.flush();
      if (!mounted || autoResultFinished) return;
      final resources = UiStateScope.of(context).resources;
      final downloadable = _downloadableResources(resources);
      if (downloadable.isNotEmpty) {
        await _showAutoResources(resources);
      }
    } catch (error) {
      debugPrint('[webview] auto scan error: $error');
    } finally {
      autoScanBusy = false;
    }
  }

  Future<void> _showAutoResources(List<VideoResource> resources) async {
    if (!mounted || browserVisible || autoDialogVisible || autoResultFinished) {
      return;
    }
    autoResultFinished = true;
    autoDialogVisible = true;
    autoResultTimer?.cancel();
    autoScanTimer?.cancel();
    setState(() {
      autoFoundCount = _downloadableResources(resources).length;
      autoStatus = '正在生成下载列表...';
    });
    await showResourceSheet(context, resources);
    if (mounted) {
      autoDialogVisible = false;
    }
  }

  Future<void> _showAutoFailedPrompt() async {
    if (!mounted || browserVisible || autoDialogVisible || autoResultFinished) {
      return;
    }
    autoResultFinished = true;
    autoDialogVisible = true;
    autoScanTimer?.cancel();
    autoResultTimer?.cancel();
    setState(() {
      autoStatus = '未自动发现视频资源';
      autoFoundCount = 0;
    });
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('未自动发现视频'),
        content: const Text('部分网站需要先播放视频，请进入网页播放后继续嗅探。'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _retryAutoParse();
            },
            child: const Text('重试自动解析'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                browserVisible = true;
                toolbarVisible = true;
              });
            },
            child: const Text('进入网页播放并嗅探'),
          ),
        ],
      ),
    );
    if (mounted) {
      autoDialogVisible = false;
    }
  }

  List<VideoResource> _downloadableResources(List<VideoResource> resources) {
    return resources
        .where((item) => item.isPlayable && !item.isAdSuspect)
        .toList();
  }

  Future<String> _pageTitle() async {
    final richTitle = await webController?.evaluateJavascript(
      source: '''
(() => {
  const meta = document.querySelector('meta[property="og:title"], meta[name="twitter:title"], meta[itemprop="name"]');
  const video = document.querySelector('video[title], [data-video-title], [data-title]');
  return (meta && meta.content) || (video && (video.getAttribute('title') || video.getAttribute('data-video-title') || video.getAttribute('data-title'))) || document.title || '';
})();
''',
    );
    final rich = richTitle?.toString().replaceAll('"', '').trim();
    if (rich != null && rich.isNotEmpty) {
      return rich;
    }
    final title = await webController?.getTitle();
    final trimmed = title?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return '网页视频';
    }
    return trimmed;
  }

  List<_CapturedCandidate> _decodeJsCandidates(Object? value) {
    if (value == null) return const [];
    if (value is List) {
      return value
          .map(_candidateFromDynamic)
          .whereType<_CapturedCandidate>()
          .toList();
    }
    var text = value.toString();
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
      thumbnailUrl:
          value['poster']?.toString() ??
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

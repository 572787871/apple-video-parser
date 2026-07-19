import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../models/video_resource.dart';
import '../services/ui_state.dart';
import '../services/video_sniffer.dart';

class BrowserScreen extends StatefulWidget {
  const BrowserScreen({super.key});

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen>
    with AutomaticKeepAliveClientMixin {
  final addressController = TextEditingController();
  final sniffer = VideoSniffer();
  final List<String> history = [];
  final Set<String> dedupe = {};
  final Map<String, VideoResource> captured = {};

  InAppWebViewController? controller;
  Timer? deepTimer;
  Timer? flushTimer;
  String currentUrl = 'about:blank';
  String pageTitle = '新窗口';
  String userAgent = '';
  bool loading = false;
  bool canGoBack = false;
  bool canGoForward = false;
  bool deepCapture = false;
  bool showStartPage = true;
  int progress = 0;
  int handledBrowserRequestId = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    addressController.text = '';
  }

  @override
  void dispose() {
    deepTimer?.cancel();
    flushTimer?.cancel();
    addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = UiStateScope.of(context);
    if (state.browserOpenRequestId != handledBrowserRequestId &&
        state.browserOpenUrl.isNotEmpty) {
      handledBrowserRequestId = state.browserOpenRequestId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_loadUrl(state.browserOpenUrl));
      });
    }

    return Scaffold(
      appBar: showStartPage ? _startAppBar() : _browserAppBar(),
      drawer: _TabsDrawer(
        history: history,
        onOpen: (url) {
          Navigator.pop(context);
          unawaited(_loadUrl(url));
        },
        onClear: () {
          setState(history.clear);
          Navigator.pop(context);
        },
      ),
      body: SafeArea(
        child: showStartPage ? _StartPage(onOpen: _loadUrl) : _browserBody(),
      ),
      floatingActionButton: showStartPage
          ? null
          : _DownloadFloatButton(
              count: _downloadable.length,
              busy: deepCapture,
              onPressed: _downloadable.isEmpty
                  ? () => _sniffPage(openPicker: true)
                  : _showDownloadPicker,
            ),
    );
  }

  PreferredSizeWidget _startAppBar() {
    return AppBar(
      leading: Builder(
        builder: (context) => IconButton(
          tooltip: '标签',
          onPressed: () => Scaffold.of(context).openDrawer(),
          icon: _TabCountBadge(count: history.isEmpty ? 1 : history.length),
        ),
      ),
      title: const SizedBox.shrink(),
      actions: [
        IconButton(
          tooltip: '帮助',
          onPressed: _showHelp,
          icon: const Icon(Icons.help_rounded),
        ),
        IconButton(
          tooltip: '设置',
          onPressed: _showSettings,
          icon: const Icon(Icons.settings_rounded),
        ),
        PopupMenuButton<String>(
          onSelected: _handleMenu,
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'paste', child: Text('粘贴并打开')),
            PopupMenuItem(value: 'settings', child: Text('浏览器设置')),
          ],
        ),
      ],
    );
  }

  PreferredSizeWidget _browserAppBar() {
    return AppBar(
      leadingWidth: 40,
      leading: Builder(
        builder: (context) => IconButton(
          tooltip: '标签',
          onPressed: () => Scaffold.of(context).openDrawer(),
          icon: _TabCountBadge(count: history.isEmpty ? 1 : history.length),
        ),
      ),
      titleSpacing: 0,
      title: _AddressBar(
        controller: addressController,
        onSubmitted: _loadUrl,
      ),
      actions: [
        IconButton(
          tooltip: loading ? '停止' : '刷新',
          onPressed: loading ? _stopLoading : _reload,
          icon: Icon(loading ? Icons.close_rounded : Icons.refresh_rounded),
        ),
        PopupMenuButton<String>(
          onSelected: _handleMenu,
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'home', child: Text('主页')),
            PopupMenuItem(value: 'sniff', child: Text('重新解析视频')),
            PopupMenuItem(value: 'copy', child: Text('复制网址')),
            PopupMenuItem(value: 'settings', child: Text('浏览器设置')),
          ],
        ),
      ],
    );
  }

  Widget _browserBody() {
    return Column(
      children: [
        if (loading || deepCapture)
          LinearProgressIndicator(
            value: deepCapture ? null : (progress <= 0 ? null : progress / 100),
            minHeight: 2,
          ),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: InAppWebView(
                  key: const PageStorageKey('video-downloader-browser'),
                  initialUrlRequest: currentUrl.startsWith('about:')
                      ? null
                      : URLRequest(url: WebUri(currentUrl)),
                  initialSettings: _settings(deep: false),
                  onWebViewCreated: _onWebViewCreated,
                  onLoadStart: (_, url) {
                    final next = url?.toString() ?? currentUrl;
                    setState(() {
                      currentUrl = next;
                      addressController.text = next;
                      loading = true;
                      progress = 0;
                      captured.clear();
                      dedupe.clear();
                    });
                    _remember(next);
                  },
                  onLoadStop: (_, url) async {
                    currentUrl = url?.toString() ?? currentUrl;
                    await _syncBrowserState();
                    await _injectHooks();
                    await _scanDom();
                  },
                  onProgressChanged: (_, value) {
                    if (!mounted) return;
                    setState(() {
                      progress = value;
                      loading = value < 100;
                    });
                  },
                  onTitleChanged: (_, title) {
                    final value = title?.trim() ?? '';
                    if (value.isNotEmpty && mounted) {
                      setState(() => pageTitle = value);
                    }
                  },
                  onUpdateVisitedHistory: (_, url, __) {
                    final next = url?.toString();
                    if (next == null) return;
                    setState(() {
                      currentUrl = next;
                      addressController.text = next;
                    });
                    _remember(next);
                  },
                  onLoadResource: (_, resource) {
                    if (deepCapture) {
                      _captureUrl(resource.url.toString(), 'resource');
                    }
                  },
                  shouldInterceptRequest: (_, request) async {
                    if (deepCapture) _captureUrl(request.url.toString(), 'net');
                    return null;
                  },
                  shouldInterceptFetchRequest: (_, request) async {
                    if (deepCapture) {
                      final url = request.url?.toString();
                      if (url != null) _captureUrl(url, 'fetch');
                    }
                    return request;
                  },
                  shouldInterceptAjaxRequest: (_, request) async {
                    if (deepCapture) {
                      final url = request.url?.toString();
                      if (url != null) _captureUrl(url, 'xhr');
                    }
                    return request;
                  },
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: _DetectionBar(
                  count: _downloadable.length,
                  onTap: _downloadable.isEmpty ? null : _showDownloadPicker,
                  onParse: () => _sniffPage(openPicker: true),
                ),
              ),
            ],
          ),
        ),
        _BrowserBottomControls(
          canGoBack: canGoBack,
          canGoForward: canGoForward,
          onBack: _goBack,
          onForward: _goForward,
          onHome: _goHome,
          onNew: _goHome,
        ),
      ],
    );
  }

  Future<void> _onWebViewCreated(InAppWebViewController value) async {
    controller = value;
    value.addJavaScriptHandler(
      handlerName: 'VideoDownloaderCapture',
      callback: (args) {
        for (final arg in args) {
          _captureCandidate(arg);
        }
      },
    );
    await _syncBrowserState();
  }

  InAppWebViewSettings _settings({required bool deep}) {
    return InAppWebViewSettings(
      javaScriptEnabled: true,
      mediaPlaybackRequiresUserGesture: false,
      allowsInlineMediaPlayback: true,
      useShouldInterceptRequest: deep,
      useShouldInterceptAjaxRequest: deep,
      useShouldInterceptFetchRequest: deep,
      supportZoom: true,
    );
  }

  List<VideoResource> get _downloadable {
    final values = captured.values
        .where((item) => item.isPlayable && !item.isAdSuspect && !item.isFragment)
        .toList();
    values.sort((a, b) {
      final current = b.isCurrentPlayback.toString().compareTo(
            a.isCurrentPlayback.toString(),
          );
      if (current != 0) return current;
      return _score(b).compareTo(_score(a));
    });
    return values.take(12).toList(growable: false);
  }

  int _score(VideoResource resource) {
    final quality = resource.quality.toLowerCase();
    if (quality.contains('2160') || quality.contains('4k')) return 4000;
    if (quality.contains('1080')) return 3000;
    if (quality.contains('720')) return 2000;
    if (resource.type == VideoResourceType.hls) return 1200;
    if (resource.type == VideoResourceType.mp4) return 1000;
    return 0;
  }

  Future<void> _loadUrl(String input) async {
    final url = _normalize(input);
    if (url.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      showStartPage = false;
      currentUrl = url;
      addressController.text = url;
    });
    final web = controller;
    if (web == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(controller?.loadUrl(urlRequest: URLRequest(url: WebUri(url))));
      });
    } else {
      await web.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
    }
  }

  Future<void> _goBack() async {
    final web = controller;
    if (web == null) return;
    if (await web.canGoBack()) await web.goBack();
  }

  Future<void> _goForward() async {
    final web = controller;
    if (web == null) return;
    if (await web.canGoForward()) await web.goForward();
  }

  void _goHome() {
    setState(() {
      showStartPage = true;
      currentUrl = 'about:blank';
      pageTitle = '新窗口';
      captured.clear();
      dedupe.clear();
      addressController.clear();
    });
  }

  Future<void> _reload() async => controller?.reload();

  Future<void> _stopLoading() async => controller?.stopLoading();

  Future<void> _syncBrowserState() async {
    final web = controller;
    if (web == null || !mounted) return;
    final url = (await web.getUrl())?.toString() ?? currentUrl;
    final title = await web.getTitle();
    final ua = await web.evaluateJavascript(source: 'navigator.userAgent');
    final back = await web.canGoBack();
    final forward = await web.canGoForward();
    if (!mounted) return;
    setState(() {
      currentUrl = url;
      addressController.text = url;
      pageTitle = title?.trim().isNotEmpty == true ? title!.trim() : pageTitle;
      userAgent = ua?.toString().replaceAll('"', '') ?? userAgent;
      canGoBack = back;
      canGoForward = forward;
      loading = false;
    });
  }

  Future<void> _injectHooks() async {
    try {
      await controller?.evaluateJavascript(source: _hookScript);
    } catch (_) {}
  }

  Future<void> _scanDom() async {
    try {
      final result = await controller?.evaluateJavascript(source: _scanScript);
      _captureCandidate(result);
      _scheduleFlush();
    } catch (_) {}
  }

  Future<void> _sniffPage({required bool openPicker}) async {
    final web = controller;
    if (web == null) return;
    setState(() => deepCapture = true);
    await web.setSettings(settings: _settings(deep: true));
    await _injectHooks();
    await _scanDom();
    deepTimer?.cancel();
    deepTimer = Timer(const Duration(seconds: 6), () async {
      await web.setSettings(settings: _settings(deep: false));
      if (!mounted) return;
      setState(() => deepCapture = false);
      if (openPicker) {
        if (_downloadable.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('请先播放视频，再点击下载按钮')),
          );
        } else {
          _showDownloadPicker();
        }
      }
    });
  }

  void _captureUrl(String url, String source) {
    if (!sniffer.isLikelyMediaCandidate(url)) return;
    _capture(
      url: url,
      source: source,
      title: pageTitle,
      current: false,
      duration: Duration.zero,
      poster: '',
    );
  }

  void _captureCandidate(Object? value) {
    if (value == null) return;
    if (value is List) {
      for (final item in value) {
        _captureCandidate(item);
      }
      return;
    }
    if (value is String) {
      try {
        final decoded = jsonDecode(value);
        _captureCandidate(decoded);
      } catch (_) {
        _captureUrl(value, 'js');
      }
      return;
    }
    if (value is! Map) return;
    final url = value['url']?.toString() ?? '';
    final sources = ((value['sources'] as List?) ?? const [])
        .map((item) => item.toString())
        .where((item) => item.trim().isNotEmpty);
    final seconds = double.tryParse('${value['duration'] ?? ''}') ?? 0;
    final title = value['title']?.toString() ?? pageTitle;
    final poster = value['poster']?.toString() ?? '';
    final current = value['current'] == true;
    for (final item in [url, ...sources]) {
      _capture(
        url: item,
        source: value['source']?.toString() ?? 'video',
        title: title,
        current: current,
        duration: seconds > 0
            ? Duration(milliseconds: (seconds * 1000).round())
            : Duration.zero,
        poster: poster,
      );
    }
  }

  void _capture({
    required String url,
    required String source,
    required String title,
    required bool current,
    required Duration duration,
    required String poster,
  }) {
    final absolute = _absoluteUrl(url);
    if (absolute.isEmpty ||
        absolute.startsWith('blob:') ||
        absolute.startsWith('data:') ||
        absolute.startsWith('about:') ||
        !sniffer.isLikelyMediaCandidate(absolute)) {
      return;
    }
    final key = sniffer.dedupeKey(absolute);
    if (!dedupe.add(key) && captured.containsKey(key)) return;
    final type = VideoResource.typeFromUrl(absolute);
    if (type == VideoResourceType.ts || type == VideoResourceType.unknown) {
      return;
    }
    final resource = VideoResource(
      url: absolute,
      title: title.trim().isEmpty ? _host(currentUrl) : title.trim(),
      type: type,
      source: source,
      pageUrl: currentUrl,
      referer: currentUrl,
      userAgent: userAgent,
      origin: _origin(currentUrl),
      quality: _qualityFromUrl(absolute),
      duration: duration,
      thumbnailUrl: poster,
      isCurrentPlayback: current,
      recommendation: current ? '当前播放' : '检测到的视频',
    );
    captured[key] = resource;
    _scheduleFlush();
  }

  void _scheduleFlush() {
    if (flushTimer?.isActive == true) return;
    flushTimer = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() {});
    });
  }

  Future<void> _showDownloadPicker() async {
    final resources = _downloadable;
    if (resources.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先播放视频，再点击下载按钮')),
      );
      return;
    }
    final appState = UiStateScope.of(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _DownloadPicker(
        title: pageTitle,
        resources: resources,
        onDownload: (resource) {
          Navigator.pop(context);
          appState.downloadResource(resource);
        },
      ),
    );
  }

  Future<void> _handleMenu(String value) async {
    switch (value) {
      case 'home':
        _goHome();
      case 'sniff':
        await _sniffPage(openPicker: true);
      case 'copy':
        await Clipboard.setData(ClipboardData(text: currentUrl));
      case 'paste':
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        final text = data?.text?.trim() ?? '';
        if (text.isNotEmpty) await _loadUrl(text);
      case 'settings':
        _showSettings();
    }
  }

  void _showSettings() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => const _SettingsSheet(),
    );
  }

  void _showHelp() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('使用方法'),
        content: const Text('打开网页并播放视频，右下角会出现下载按钮。未检测到时，先播放几秒再点击下载。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  void _remember(String url) {
    if (url.startsWith('about:')) return;
    history.remove(url);
    history.insert(0, url);
    if (history.length > 20) history.removeRange(20, history.length);
  }

  String _normalize(String value) {
    final text = value.trim();
    if (text.isEmpty) return '';
    if (text.startsWith('http://') || text.startsWith('https://')) return text;
    if (text.contains('.') && !text.contains(' ')) return 'https://$text';
    return 'https://www.google.com/search?q=${Uri.encodeQueryComponent(text)}';
  }

  String _absoluteUrl(String value) {
    try {
      return Uri.parse(currentUrl).resolve(value).toString();
    } catch (_) {
      return value.trim();
    }
  }

  String _host(String url) => Uri.tryParse(url)?.host ?? '网页视频';

  String _origin(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme.isEmpty || uri.host.isEmpty) return '';
    return '${uri.scheme}://${uri.host}';
  }

  String _qualityFromUrl(String url) {
    final lower = url.toLowerCase();
    final match = RegExp(r'([1-9][0-9]{2,3})p').firstMatch(lower);
    if (match != null) return '${match.group(1)}P';
    if (lower.contains('1080')) return '1080P';
    if (lower.contains('720')) return '720P';
    if (lower.contains('480')) return '480P';
    return '未知';
  }

  static const _scanScript = r'''
(() => {
  const title = document.querySelector('meta[property="og:title"],meta[name="twitter:title"]')?.content || document.title || '';
  const out = [];
  const push = (url, source, media) => {
    if (!url) return;
    out.push({
      url,
      source,
      title,
      duration: media && Number.isFinite(media.duration) ? media.duration : 0,
      poster: media ? (media.poster || '') : '',
      current: !!(media && (!media.paused || media.currentTime > 0)),
      sources: media ? Array.from(media.querySelectorAll('source')).map(s => s.src || s.getAttribute('src') || '').filter(Boolean) : []
    });
  };
  document.querySelectorAll('video,audio').forEach(v => {
    push(v.currentSrc || v.src, 'video', v);
    Array.from(v.querySelectorAll('source')).forEach(s => push(s.src || s.getAttribute('src'), 'source', v));
  });
  Array.from(document.querySelectorAll('a[href]')).forEach(a => {
    const href = a.href || '';
    if (/\.(mp4|m4v|mov|webm|m3u8)(\?|#|$)/i.test(href)) push(href, 'link', null);
  });
  return JSON.stringify(out);
})();
''';

  static const _hookScript = r'''
(() => {
  if (window.__videoDownloaderHooked) return;
  window.__videoDownloaderHooked = true;
  const title = () => document.querySelector('meta[property="og:title"],meta[name="twitter:title"]')?.content || document.title || '';
  const likely = u => typeof u === 'string' && /\.(mp4|m4v|mov|webm|m3u8)(\?|#|$)/i.test(u);
  const post = (url, source, media) => {
    try {
      if (!url || !likely(url)) return;
      window.flutter_inappwebview.callHandler('VideoDownloaderCapture', {
        url: new URL(url, location.href).href,
        source,
        title: title(),
        duration: media && Number.isFinite(media.duration) ? media.duration : 0,
        poster: media ? (media.poster || '') : '',
        current: !!(media && (!media.paused || media.currentTime > 0)),
        sources: media ? Array.from(media.querySelectorAll('source')).map(s => s.src || s.getAttribute('src') || '').filter(Boolean) : []
      });
    } catch (_) {}
  };
  const bind = media => {
    if (!media || media.__videoDownloaderBound) return;
    media.__videoDownloaderBound = true;
    ['play','playing','loadedmetadata','canplay','durationchange'].forEach(event => {
      media.addEventListener(event, () => post(media.currentSrc || media.src, event === 'play' || event === 'playing' ? 'current-video' : 'video', media), true);
    });
  };
  document.querySelectorAll('video,audio').forEach(bind);
  new MutationObserver(ms => ms.forEach(m => m.addedNodes.forEach(n => {
    if (!n.querySelectorAll) return;
    if (n.tagName === 'VIDEO' || n.tagName === 'AUDIO') bind(n);
    n.querySelectorAll('video,audio').forEach(bind);
  }))).observe(document.documentElement, {childList:true, subtree:true});
  const oldFetch = window.fetch;
  if (oldFetch) {
    window.fetch = function() {
      try {
        const input = arguments[0];
        const url = typeof input === 'string' ? input : input && input.url;
        post(url, 'fetch', null);
      } catch (_) {}
      return oldFetch.apply(this, arguments).then(r => {
        try { post(r.url, 'fetch-response', null); } catch (_) {}
        return r;
      });
    };
  }
  const oldOpen = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function(method, url) {
    post(url, 'xhr', null);
    return oldOpen.apply(this, arguments);
  };
})();
''';
}

class _StartPage extends StatefulWidget {
  const _StartPage({required this.onOpen});

  final ValueChanged<String> onOpen;

  @override
  State<_StartPage> createState() => _StartPageState();
}

class _StartPageState extends State<_StartPage> {
  final controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
      children: [
        TextField(
          controller: controller,
          textInputAction: TextInputAction.go,
          decoration: InputDecoration(
            hintText: '搜索或输入网址',
            suffixIcon: IconButton(
              icon: const Icon(Icons.keyboard_return_rounded),
              onPressed: () => widget.onOpen(controller.text),
            ),
          ),
          onSubmitted: widget.onOpen,
        ),
        const SizedBox(height: 26),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 4,
          mainAxisSpacing: 20,
          crossAxisSpacing: 14,
          children: [
            _SiteShortcut(label: 'Facebook', color: const Color(0xff1877f2), text: 'f', url: 'https://www.facebook.com', onOpen: widget.onOpen),
            _SiteShortcut(label: 'Instagram', color: const Color(0xffe4405f), text: '◎', url: 'https://www.instagram.com', onOpen: widget.onOpen),
            _SiteShortcut(label: 'Vimeo', color: const Color(0xff1ab7ea), text: 'v', url: 'https://vimeo.com', onOpen: widget.onOpen),
            _SiteShortcut(label: 'Dailymotion', color: const Color(0xff00aaff), text: 'd', url: 'https://www.dailymotion.com', onOpen: widget.onOpen),
            _SiteShortcut(label: 'Twitter', color: const Color(0xff1da1f2), text: 't', url: 'https://twitter.com', onOpen: widget.onOpen),
            _SiteShortcut(label: 'TikTok', color: Colors.black, text: '♪', url: 'https://www.tiktok.com', onOpen: widget.onOpen),
            _SiteShortcut(label: 'WhatsApp', color: const Color(0xff25d366), text: 'w', url: 'https://www.whatsapp.com', onOpen: widget.onOpen),
            _SiteShortcut(label: 'Google', color: const Color(0xff4285f4), text: 'G', url: 'https://www.google.com', onOpen: widget.onOpen),
          ],
        ),
        const SizedBox(height: 42),
        Center(
          child: TextButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.feedback_rounded),
            label: const Text('有反馈或问题吗？联系我们'),
          ),
        ),
      ],
    );
  }
}

class _SiteShortcut extends StatelessWidget {
  const _SiteShortcut({
    required this.label,
    required this.color,
    required this.text,
    required this.url,
    required this.onOpen,
  });

  final String label;
  final Color color;
  final String text;
  final String url;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => onOpen(url),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 27,
            backgroundColor: color,
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _AddressBar extends StatelessWidget {
  const _AddressBar({required this.controller, required this.onSubmitted});

  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      minLines: 1,
      maxLines: 1,
      textInputAction: TextInputAction.go,
      decoration: const InputDecoration(
        isDense: true,
        prefixIcon: Icon(Icons.lock_rounded, size: 18),
        hintText: '搜索或输入网址',
      ),
      onSubmitted: onSubmitted,
    );
  }
}

class _DownloadFloatButton extends StatelessWidget {
  const _DownloadFloatButton({
    required this.count,
    required this.busy,
    required this.onPressed,
  });

  final int count;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      heroTag: 'video-download-fab',
      onPressed: onPressed,
      backgroundColor: count > 0 ? Colors.redAccent : null,
      child: busy
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Badge(
              isLabelVisible: count > 0,
              label: Text('$count'),
              child: const Icon(Icons.file_download_rounded),
            ),
    );
  }
}

class _DetectionBar extends StatelessWidget {
  const _DetectionBar({
    required this.count,
    required this.onTap,
    required this.onParse,
  });

  final int count;
  final VoidCallback? onTap;
  final VoidCallback onParse;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 6,
      color: scheme.surface.withValues(alpha: 0.94),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(
                count > 0 ? Icons.check_circle : Icons.info_outline,
                color: count > 0 ? Colors.green : scheme.primary,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  count > 0 ? '发现 $count 个视频' : '播放视频后点击下载',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              TextButton(
                onPressed: onParse,
                child: const Text('检测'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DownloadPicker extends StatefulWidget {
  const _DownloadPicker({
    required this.title,
    required this.resources,
    required this.onDownload,
  });

  final String title;
  final List<VideoResource> resources;
  final ValueChanged<VideoResource> onDownload;

  @override
  State<_DownloadPicker> createState() => _DownloadPickerState();
}

class _DownloadPickerState extends State<_DownloadPicker> {
  late VideoResource selected = widget.resources.first;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('网络', style: TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(width: 8),
                Icon(Icons.wifi_rounded, color: scheme.primary),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Container(
                  width: 92,
                  height: 74,
                  alignment: Alignment.center,
                  color: scheme.primaryContainer,
                  child: Icon(Icons.movie_rounded, color: scheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.title.trim().isEmpty ? selected.title : widget.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final resource in widget.resources)
                  ChoiceChip(
                    selected: resource.url == selected.url,
                    label: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            resource.quality == '未知'
                                ? resource.displayFormat
                                : resource.quality,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          Text(resource.size),
                        ],
                      ),
                    ),
                    onSelected: (_) => setState(() => selected = resource),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: () => widget.onDownload(selected),
                icon: const Icon(Icons.file_download_rounded),
                label: const Text('下载'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrowserBottomControls extends StatelessWidget {
  const _BrowserBottomControls({
    required this.canGoBack,
    required this.canGoForward,
    required this.onBack,
    required this.onForward,
    required this.onHome,
    required this.onNew,
  });

  final bool canGoBack;
  final bool canGoForward;
  final VoidCallback onBack;
  final VoidCallback onForward;
  final VoidCallback onHome;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          IconButton(onPressed: canGoBack ? onBack : null, icon: const Icon(Icons.arrow_back_rounded)),
          IconButton(onPressed: onHome, icon: const Icon(Icons.home_rounded)),
          IconButton(onPressed: canGoForward ? onForward : null, icon: const Icon(Icons.arrow_forward_rounded)),
          IconButton(onPressed: onNew, icon: const Icon(Icons.add_rounded)),
        ],
      ),
    );
  }
}

class _TabsDrawer extends StatelessWidget {
  const _TabsDrawer({
    required this.history,
    required this.onOpen,
    required this.onClear,
  });

  final List<String> history;
  final ValueChanged<String> onOpen;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            ListTile(
              title: const Text('标签', style: TextStyle(fontSize: 22)),
              trailing: IconButton(
                onPressed: onClear,
                icon: const Icon(Icons.more_vert_rounded),
              ),
            ),
            Expanded(
              child: history.isEmpty
                  ? const Center(child: Text('暂无标签'))
                  : ListView.builder(
                      itemCount: history.length,
                      itemBuilder: (context, index) {
                        final url = history[index];
                        return ListTile(
                          leading: const Text('🏠'),
                          title: Text(
                            Uri.tryParse(url)?.host ?? url,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            url,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: const Icon(Icons.close_rounded),
                          onTap: () => onOpen(url),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabCountBadge extends StatelessWidget {
  const _TabCountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(width: 2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text('$count', style: const TextStyle(fontWeight: FontWeight.w900)),
    );
  }
}

class _SettingsSheet extends StatelessWidget {
  const _SettingsSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: const [
          ListTile(title: Text('浏览器设置', style: TextStyle(fontSize: 22))),
          SwitchListTile(value: true, onChanged: null, title: Text('仅使用 Wi-Fi 下载')),
          ListTile(title: Text('浏览器'), subtitle: Text('默认页面')),
          SwitchListTile(value: true, onChanged: null, title: Text('拦截广告')),
          SwitchListTile(value: true, onChanged: null, title: Text('保存密码')),
          ListTile(title: Text('搜索引擎'), subtitle: Text('Google')),
          ListTile(title: Text('清除缓存')),
          ListTile(title: Text('清除 Cookies')),
        ],
      ),
    );
  }
}

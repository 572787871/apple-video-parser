import 'package:flutter/widgets.dart';

import '../models/download_task.dart';
import '../models/local_video.dart';
import '../models/video_resource.dart';
import 'download_manager.dart';
import 'local_library.dart';
import 'video_sniffer.dart';

class AppState extends ChangeNotifier {
  AppState() {
    downloads.addListener(_onDownloadsChanged);
    refreshLibrary();
  }

  final VideoSniffer sniffer = VideoSniffer();
  final DownloadManager downloads = DownloadManager();
  final LocalLibrary library = LocalLibrary();

  final List<VideoResource> parsedResources = [];
  final List<VideoResource> sniffedResources = [];
  List<LocalVideo> localVideos = [];
  bool parsing = false;
  String status = '准备就绪';

  Future<void> parseUrl(String value) async {
    if (value.trim().isEmpty) {
      status = '请输入网页 URL';
      notifyListeners();
      return;
    }
    parsing = true;
    status = '正在解析网页';
    notifyListeners();
    try {
      final resources = await sniffer.parsePage(value);
      parsedResources
        ..clear()
        ..addAll(resources);
      status = resources.isEmpty
          ? '未发现直链资源，可用内置 WebView 打开网页嗅探'
          : '发现 ${resources.length} 个资源';
    } catch (error) {
      status = '解析失败：$error';
    } finally {
      parsing = false;
      notifyListeners();
    }
  }

  void addSniffed(VideoResource resource) {
    if (sniffedResources.any((item) => item.url == resource.url)) {
      return;
    }
    sniffedResources.insert(0, resource);
    status = '嗅探到 ${sniffedResources.length} 个资源';
    notifyListeners();
  }

  void addSniffedFromUrl({
    required String url,
    required String title,
    required String source,
    required String pageUrl,
  }) {
    final resource = sniffer.resourceFromUrl(
      url,
      pageTitle: title,
      source: source,
      pageUrl: pageUrl,
    );
    if (resource != null) {
      addSniffed(resource);
    }
  }

  DownloadTask startDownload(VideoResource resource) {
    status = '已加入下载';
    final task = downloads.enqueue(resource);
    notifyListeners();
    return task;
  }

  Future<void> refreshLibrary() async {
    localVideos = await library.scan();
    notifyListeners();
  }

  Future<void> retry(DownloadTask task) async {
    await downloads.retry(task);
  }

  Future<void> pause(DownloadTask task) async {
    await downloads.pause(task);
  }

  Future<void> cancel(DownloadTask task) async {
    await downloads.cancel(task);
  }

  void _onDownloadsChanged() {
    if (downloads.tasks.any(
      (task) => task.status == DownloadStatus.completed,
    )) {
      refreshLibrary();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    downloads.removeListener(_onDownloadsChanged);
    downloads.dispose();
    super.dispose();
  }
}

class AppStateScope extends InheritedNotifier<AppState> {
  const AppStateScope({
    required AppState state,
    required super.child,
    super.key,
  }) : super(notifier: state);

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppStateScope>();
    assert(scope != null, 'AppStateScope not found');
    return scope!.notifier!;
  }
}

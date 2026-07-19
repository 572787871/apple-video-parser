import 'dart:async';

import 'package:flutter/widgets.dart';

import '../models/download_task.dart';
import '../models/library_folder.dart';
import '../models/local_video.dart';
import '../models/parse_record.dart';
import '../models/video_resource.dart';
import 'download_manager.dart';
import 'library_folder_store.dart';
import 'local_library.dart';
import 'parse_history_store.dart';
import 'video_sniffer.dart';

enum HomeSnifferState { idle, sniffing, found, notFound, failed }

class UiState extends ChangeNotifier {
  UiState() {
    downloadManager.addListener(_onDownloadsChanged);
    unawaited(downloadManager.restoreTasks());
    refreshLibrary();
    unawaited(_loadFolders());
    unawaited(_loadParseRecords());
  }

  final DownloadManager downloadManager = DownloadManager();
  final VideoSniffer sniffer = VideoSniffer();
  final LocalLibrary library = LocalLibrary();
  final LibraryFolderStore folderStore = LibraryFolderStore();
  final ParseHistoryStore parseHistoryStore = ParseHistoryStore();

  final List<String> recentUrls = [];
  final List<VideoResource> resources = [];
  final List<ParseRecord> recentParses = [];
  final List<LibraryFolder> folders = [];
  List<LocalVideo> videos = [];
  bool _enrichingLibrary = false;

  int selectedTab = 0;
  bool onlyWifi = false;
  bool parsing = false;
  HomeSnifferState homeSnifferState = HomeSnifferState.idle;
  String homeSnifferStatus = '准备就绪';
  String activeSniffUrl = '';
  String browserOpenUrl = '';
  int browserOpenRequestId = 0;
  String status = '准备就绪';

  void addRecent(String url) {
    final value = url.trim();
    if (value.isEmpty) return;
    recentUrls.remove(value);
    recentUrls.insert(0, value);
    notifyListeners();
  }

  void startHomeSniff(String url) {
    final value = url.trim();
    if (value.isEmpty) return;
    addRecent(value);
    activeSniffUrl = value;
    homeSnifferState = HomeSnifferState.sniffing;
    homeSnifferStatus = '正在监听视频资源...';
    status = '正在监听视频资源';
    notifyListeners();
  }

  void updateHomeSniffProgress(int count) {
    if (homeSnifferState != HomeSnifferState.sniffing) return;
    homeSnifferStatus = count <= 0
        ? '正在监听视频资源...'
        : (count == 1 ? '已发现 1 个视频...' : '已发现 $count 个资源...');
    status = homeSnifferStatus;
    notifyListeners();
  }

  Future<void> finishHomeSniffFound(ParseRecord record) async {
    final prioritized = sniffer.prioritizeResources(record.resources);
    final recommended = _firstDownloadable(prioritized);
    final next = record.copyWith(
      status: ParseRecordStatus.found,
      resources: prioritized,
      recommendedUrl: recommended?.url ?? '',
      sourceSite: record.sourceSite.isEmpty
          ? _hostFromUrl(record.pageUrl)
          : record.sourceSite,
    );
    _upsertParseRecord(next);
    homeSnifferState = HomeSnifferState.found;
    homeSnifferStatus = '已发现 ${prioritized.length} 个视频资源';
    status = homeSnifferStatus;
    activeSniffUrl = '';
    notifyListeners();
    await _saveParseRecords();
  }

  Future<void> finishHomeSniffNotFound({
    required String pageUrl,
    required String pageTitle,
  }) async {
    final record = ParseRecord(
      pageUrl: pageUrl,
      pageTitle: pageTitle.trim().isEmpty ? _hostFromUrl(pageUrl) : pageTitle,
      parsedAt: DateTime.now(),
      status: ParseRecordStatus.notFound,
      sourceSite: _hostFromUrl(pageUrl),
      message: '未自动发现视频。部分网站需要先播放视频。',
    );
    _upsertParseRecord(record);
    homeSnifferState = HomeSnifferState.notFound;
    homeSnifferStatus = '未发现视频，请进入网页播放后嗅探。';
    status = homeSnifferStatus;
    activeSniffUrl = '';
    notifyListeners();
    await _saveParseRecords();
  }

  Future<void> finishHomeSniffFailed({
    required String pageUrl,
    required String pageTitle,
    required Object error,
  }) async {
    final record = ParseRecord(
      pageUrl: pageUrl,
      pageTitle: pageTitle.trim().isEmpty ? _hostFromUrl(pageUrl) : pageTitle,
      parsedAt: DateTime.now(),
      status: ParseRecordStatus.failed,
      sourceSite: _hostFromUrl(pageUrl),
      message: '解析失败：$error',
    );
    _upsertParseRecord(record);
    homeSnifferState = HomeSnifferState.failed;
    homeSnifferStatus = '解析失败，请重试或进入网页播放。';
    status = homeSnifferStatus;
    activeSniffUrl = '';
    notifyListeners();
    await _saveParseRecords();
  }

  Future<void> parseUrl(String url) async {
    final value = url.trim();
    if (value.isEmpty) {
      status = '请输入网页 URL';
      notifyListeners();
      return;
    }
    parsing = true;
    status = '正在解析网页';
    resources.clear();
    notifyListeners();
    try {
      final parsed = await sniffer.parsePage(value);
      _replaceResources(parsed);
      status = parsed.isEmpty ? '未发现视频资源' : '发现 ${parsed.length} 个视频资源';
    } catch (error) {
      status = '解析失败：$error';
    } finally {
      parsing = false;
      notifyListeners();
    }
  }

  void setResources(List<VideoResource> values) {
    _replaceResources(values);
    status = resources.isEmpty ? '未发现视频资源' : '发现 ${resources.length} 个视频资源';
    notifyListeners();
  }

  void clearResources({String message = '正在嗅探网页视频'}) {
    resources.clear();
    status = message;
    notifyListeners();
  }

  void addResource(VideoResource resource) {
    if (_shouldSkip(resource.url)) return;
    final normalized = resource.normalizedUrl;
    if (resources.any((item) => item.normalizedUrl == normalized)) return;
    resources.insert(0, resource);
    status = '发现 ${resources.length} 个视频资源';
    notifyListeners();
  }

  void downloadResource(VideoResource resource) {
    debugPrint('[download] click url=${resource.url} type=${resource.label}');
    if (resource.url.startsWith('blob:')) {
      status = 'blob 不是可下载地址，请播放视频后重新嗅探真实地址';
      notifyListeners();
      return;
    }
    final task = downloadManager.createTask(resource);
    downloadManager.addTask(task);
    unawaited(downloadManager.start(task.id));
    selectedTab = 1;
    notifyListeners();
  }

  Future<void> refreshLibrary() async {
    videos = await library.scan();
    notifyListeners();
    unawaited(_ensureLibraryDetails(videos));
  }

  Future<void> deleteVideo(LocalVideo video) async {
    await library.delete(video);
    await refreshLibrary();
  }

  Future<void> deleteCollection(String directoryPath) async {
    await library.deleteCollection(directoryPath);
    await refreshLibrary();
  }

  Future<void> toggleFavorite(LocalVideo video) async {
    await library.setFavorite(video, !video.isFavorite);
    await refreshLibrary();
  }

  void toggleWifi(bool value) {
    onlyWifi = value;
    notifyListeners();
  }

  void selectTab(int index) {
    selectedTab = index;
    notifyListeners();
  }

  void openInBrowser(String url) {
    final value = url.trim();
    if (value.isEmpty) return;
    browserOpenUrl = value;
    browserOpenRequestId++;
    selectedTab = 0;
    notifyListeners();
  }

  Future<LibraryFolder> createFolder(String name) async {
    final folder = folderStore.createManualFolder(name);
    folders.insert(0, folder);
    await _saveFolders();
    notifyListeners();
    return folder;
  }

  Future<void> renameFolder(LibraryFolder folder, String name) async {
    final index =
        folders.indexWhere((item) => item.folderId == folder.folderId);
    if (index < 0) return;
    folders[index] = folder.copyWith(
      name: name.trim().isEmpty ? folder.name : name.trim(),
      updatedAt: DateTime.now(),
    );
    await _saveFolders();
    notifyListeners();
  }

  Future<void> deleteFolder(LibraryFolder folder) async {
    folders.removeWhere((item) => item.folderId == folder.folderId);
    await library.removeFolderMapping(folder.folderId);
    await _saveFolders();
    await refreshLibrary();
  }

  Future<void> moveVideoToFolder(
    LocalVideo video,
    LibraryFolder folder,
  ) async {
    await library.moveToFolder(video, folder.folderId);
    await refreshLibrary();
  }

  void _replaceResources(List<VideoResource> values) {
    resources
      ..clear()
      ..addAll(
        sniffer.prioritizeResources(
          _dedupe(values.where((item) => !_shouldSkip(item.url))),
        ),
      );
  }

  Future<void> _loadParseRecords() async {
    final records = await parseHistoryStore.load();
    recentParses
      ..clear()
      ..addAll(records.take(20));
    recentUrls
      ..clear()
      ..addAll(recentParses.map((record) => record.pageUrl));
    notifyListeners();
  }

  Future<void> _saveParseRecords() async {
    await parseHistoryStore.save(recentParses.take(20).toList());
  }

  Future<void> _loadFolders() async {
    final stored = await folderStore.load();
    folders
      ..clear()
      ..addAll(stored);
    notifyListeners();
  }

  Future<void> _saveFolders() async {
    await folderStore.save(folders);
  }

  void _upsertParseRecord(ParseRecord record) {
    recentParses.removeWhere((item) => item.pageUrl == record.pageUrl);
    recentParses.insert(0, record);
    if (recentParses.length > 20) {
      recentParses.removeRange(20, recentParses.length);
    }
    recentUrls
      ..remove(record.pageUrl)
      ..insert(0, record.pageUrl);
  }

  String _hostFromUrl(String url) {
    return Uri.tryParse(url)?.host ?? url;
  }

  VideoResource? _firstDownloadable(List<VideoResource> values) {
    for (final item in values) {
      if (item.isPlayable && !item.isAdSuspect && !item.isFragment) {
        return item;
      }
    }
    return null;
  }

  List<VideoResource> _dedupe(Iterable<VideoResource> values) {
    final seen = <String>{};
    final out = <VideoResource>[];
    for (final item in values) {
      if (seen.add(item.normalizedUrl)) {
        out.add(item);
      }
    }
    return out;
  }

  bool _shouldSkip(String value) {
    final lower = value.toLowerCase().trim();
    return lower.isEmpty ||
        lower.startsWith('blob:') ||
        lower.startsWith('data:') ||
        lower.startsWith('about:');
  }

  void _onDownloadsChanged() {
    if (downloadManager.tasks.any(
      (task) =>
          task.status == DownloadStatus.completed && task.localPath.isNotEmpty,
    )) {
      unawaited(refreshLibrary());
    }
    notifyListeners();
  }

  Future<void> _ensureLibraryDetails(List<LocalVideo> snapshot) async {
    if (_enrichingLibrary || snapshot.isEmpty) return;
    _enrichingLibrary = true;
    var changed = false;
    try {
      for (final video in snapshot) {
        if (video.thumbnailPath.isEmpty ||
            video.duration == Duration.zero ||
            video.width <= 0 ||
            video.height <= 0) {
          changed = await library.ensureDetails(video) || changed;
        }
      }
      if (changed) {
        videos = await library.scan();
        notifyListeners();
      }
    } finally {
      _enrichingLibrary = false;
    }
  }

  @override
  void dispose() {
    downloadManager.removeListener(_onDownloadsChanged);
    downloadManager.dispose();
    super.dispose();
  }
}

class UiStateScope extends InheritedNotifier<UiState> {
  const UiStateScope({required UiState state, required super.child, super.key})
      : super(notifier: state);

  static UiState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<UiStateScope>();
    assert(scope != null, 'UiStateScope not found');
    return scope!.notifier!;
  }
}

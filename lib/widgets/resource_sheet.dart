import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/video_resource.dart';
import '../screens/resource_preview_screen.dart';
import '../services/ui_state.dart';
import '../services/video_sniffer.dart';
import 'download_confirm_dialog.dart';

Future<void> showResourceSheet(
  BuildContext context,
  List<VideoResource> resources,
) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (context) => ResourceSheet(resources: resources),
  );
}

class ResourceSheet extends StatelessWidget {
  ResourceSheet({required List<VideoResource> resources, super.key})
      : _groups = _ResourceGroups.from(resources);

  final _ResourceGroups _groups;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.82;

    return SafeArea(
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '可下载视频',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                '已自动隐藏广告嫌疑和分片资源。',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              if (_groups.isEmpty)
                _EmptyResources()
              else
                Expanded(
                  child: DefaultTabController(
                    length: 4,
                    child: Column(
                      children: [
                        TabBar(
                          isScrollable: true,
                          tabs: [
                            Tab(text: '推荐资源 ${_groups.recommended.length}'),
                            Tab(text: '全部资源 ${_groups.all.length}'),
                            Tab(text: '广告嫌疑 ${_groups.ads.length}'),
                            Tab(text: '分片/高级 ${_groups.fragments.length}'),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: TabBarView(
                            children: [
                              _ResourceList(
                                resources: _groups.recommended,
                                emptyText: '没有足够可信的推荐资源，可到“全部资源”查看。',
                              ),
                              _ResourceList(resources: _groups.all),
                              _ResourceList(
                                resources: _groups.ads,
                                emptyText: '没有广告嫌疑资源。',
                              ),
                              _ResourceList(
                                resources: _groups.fragments,
                                emptyText: '没有捕获到 ts/m4s 分片。',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResourceGroups {
  _ResourceGroups({
    required this.recommended,
    required this.all,
    required this.ads,
    required this.fragments,
  });

  final List<VideoResource> recommended;
  final List<VideoResource> all;
  final List<VideoResource> ads;
  final List<VideoResource> fragments;

  bool get isEmpty =>
      recommended.isEmpty && all.isEmpty && ads.isEmpty && fragments.isEmpty;

  factory _ResourceGroups.from(List<VideoResource> resources) {
    final sorted = VideoSniffer().prioritizeResources(resources, limit: 50);
    return _ResourceGroups(
      recommended: sorted
          .where(
            (item) => item.isPlayable && !item.isAdSuspect && !item.isFragment,
          )
          .take(5)
          .toList(growable: false),
      all: sorted
          .where((item) => !item.isAdSuspect && !item.isFragment)
          .take(20)
          .toList(growable: false),
      ads: sorted.where((item) => item.isAdSuspect).take(20).toList(
            growable: false,
          ),
      fragments: sorted.where((item) => item.isFragment).take(50).toList(
            growable: false,
          ),
    );
  }
}

class _EmptyResources extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Text('未自动发现视频。部分网站需要先播放视频，请进入网页播放后再点发现视频。'),
    );
  }
}

class _ResourceList extends StatelessWidget {
  const _ResourceList({
    required this.resources,
    this.emptyText = '没有可直接下载的资源。',
  });

  final List<VideoResource> resources;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    if (resources.isEmpty) {
      return Center(child: Text(emptyText, textAlign: TextAlign.center));
    }
    return ListView.separated(
      itemCount: resources.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final resource = resources[index];
        return RepaintBoundary(
          key: ValueKey(resource.id),
          child: _ResourceTile(resource: resource),
        );
      },
    );
  }
}

class _ResourceTile extends StatelessWidget {
  const _ResourceTile({required this.resource});

  final VideoResource resource;

  @override
  Widget build(BuildContext context) {
    final state = UiStateScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final uri = Uri.tryParse(resource.url);
    final host = uri?.host ?? '未知域名';
    final path = _pathLabel(uri);
    final meta = [
      resource.quality,
      if (resource.duration > Duration.zero) _durationLabel(resource.duration),
      if (resource.bitrate.isNotEmpty) resource.bitrate,
      if (resource.size != '未知') resource.size,
      if (resource.container.isNotEmpty) resource.container,
    ].where((item) => item.trim().isNotEmpty && item != '未知').join(' · ');
    final badges = [
      if (resource.isCurrentPlayback) '当前播放',
      if (resource.isAdSuspect)
        '广告嫌疑'
      else if (resource.recommendation.isNotEmpty)
        resource.recommendation
      else
        '可能的视频资源',
    ];

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ResourceThumb(resource: resource, label: _typeLabel(resource)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      resource.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            meta.isEmpty ? resource.displayFormat : meta,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                        for (final badge in badges.take(2)) ...[
                          const SizedBox(width: 6),
                          _Badge(
                            label: badge,
                            danger: badge == '广告嫌疑',
                            highlighted: badge == '当前播放',
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '来源网站：${_siteLabel(host)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '来源方式：${_sourceLabel(resource.source)}${resource.playerId.isEmpty ? '' : ' · 播放器 ${resource.playerId}'}',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    if (resource.codec.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        '编码：${resource.codec}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            path,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            children: [
              OutlinedButton.icon(
                onPressed: resource.isPlayable
                    ? () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => ResourcePreviewScreen.network(
                                resource: resource),
                          ),
                        )
                    : null,
                icon: const Icon(Icons.play_circle_outline_rounded),
                label: const Text('预览'),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: resource.url));
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('已复制真实资源链接')));
                },
                icon: const Icon(Icons.copy_rounded),
                label: const Text('复制链接'),
              ),
              FilledButton.icon(
                onPressed: resource.isFragment
                    ? null
                    : () async {
                        final selected =
                            await showDownloadConfirmDialog(context, resource);
                        if (selected == null || !context.mounted) return;
                        state.downloadResource(selected);
                        Navigator.pop(context);
                      },
                icon: const Icon(Icons.download_rounded),
                label: const Text('下载'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _pathLabel(Uri? uri) {
    if (uri == null) return resource.url;
    final path = uri.path.isEmpty ? '/' : uri.path;
    final query = uri.query.isEmpty ? '' : '?${uri.query}';
    final label = '$path$query';
    return label.length > 120
        ? '...${label.substring(label.length - 120)}'
        : label;
  }

  String _sourceLabel(String value) {
    final lower = value.toLowerCase();
    if (lower.contains('xhr')) return 'XHR';
    if (lower.contains('fetch')) return 'fetch';
    if (lower.contains('dom')) return 'DOM';
    if (lower.contains('play') ||
        lower.contains('current') ||
        lower.contains('media')) {
      return 'video tag';
    }
    return 'resource';
  }

  String _siteLabel(String host) {
    if (host.isEmpty || host == '未知域名') return host;
    final parts = host.split('.').where((item) => item.isNotEmpty).toList();
    if (parts.length >= 2) {
      final name = parts[parts.length - 2];
      return '${name[0].toUpperCase()}${name.substring(1)} ($host)';
    }
    return host;
  }

  String _durationLabel(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  String _typeLabel(VideoResource resource) {
    switch (resource.type) {
      case VideoResourceType.hls:
        return 'HLS';
      case VideoResourceType.ts:
        return 'TS';
      case VideoResourceType.mp4:
        return resource.displayFormat;
      case VideoResourceType.unknown:
        return resource.url.toLowerCase().contains('.m4s') ? 'M4S' : '未知';
    }
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    required this.danger,
    this.highlighted = false,
  });

  final String label;
  final bool danger;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: danger
            ? scheme.errorContainer
            : (highlighted
                ? scheme.tertiaryContainer
                : scheme.primaryContainer),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: danger
              ? scheme.onErrorContainer
              : (highlighted
                  ? scheme.onTertiaryContainer
                  : scheme.onPrimaryContainer),
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ResourceThumb extends StatelessWidget {
  const _ResourceThumb({required this.resource, required this.label});

  final VideoResource resource;
  final String label;

  @override
  Widget build(BuildContext context) {
    final thumb = resource.thumbnailUrl;
    if (thumb.isEmpty ||
        (!thumb.startsWith('http://') && !thumb.startsWith('https://'))) {
      return _TypePill(label: label);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(
        alignment: Alignment.bottomLeft,
        children: [
          Image.network(
            thumb,
            width: 76,
            height: 54,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _TypePill(label: label),
          ),
          Container(
            margin: const EdgeInsets.all(4),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TypePill extends StatelessWidget {
  const _TypePill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xff2563eb), Color(0xff7c3aed)],
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

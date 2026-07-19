import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/parse_record.dart';
import '../models/video_resource.dart';
import '../services/ui_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_card.dart';
import '../widgets/app_text_field.dart';
import '../widgets/download_confirm_dialog.dart';
import '../widgets/gradient_button.dart';
import '../widgets/home_sniffer.dart';
import 'resource_preview_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final controller = TextEditingController();
  String? sniffUrl;
  int sniffRequestId = 0;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = UiStateScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('视频解析下载')),
      body: Stack(
        children: [
          AnimatedBuilder(
            animation: state,
            builder: (context, _) => ListView(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
              children: [
                _HeroPanel(),
                const SizedBox(height: 18),
                AppCard(
                  child: Row(
                    children: [
                      _StatItem(label: '视频数量', value: '${state.videos.length}'),
                      _StatItem(
                        label: '总容量',
                        value: _formatBytes(
                          state.videos.fold<int>(
                            0,
                            (sum, item) => sum + item.size,
                          ),
                        ),
                      ),
                      _StatItem(label: '今日下载', value: '${_todayCount(state)}'),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                AppCard(
                  child: Column(
                    children: [
                      AppTextField(
                        controller: controller,
                        hintText: '粘贴网页 URL',
                        onSubmitted: (_) => _parse(context),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _paste,
                              icon: const Icon(Icons.content_paste_rounded),
                              label: const Text('粘贴链接'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: GradientButton(
                              label: '开始解析',
                              icon: Icons.search_rounded,
                              onPressed: () => _parse(context),
                            ),
                          ),
                        ],
                      ),
                      if (state.homeSnifferState != HomeSnifferState.idle) ...[
                        const SizedBox(height: 12),
                        _SnifferStatusBar(state: state),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  '最近解析',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 12),
                if (state.recentParses.isEmpty)
                  const AppCard(child: Text('暂无解析记录。输入网页 URL 后会在这里显示视频资源。'))
                else
                  for (final record in state.recentParses)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _ParseRecordCard(
                        record: record,
                        onRetry: () => _parse(context, url: record.pageUrl),
                        onOpenWeb: () => _openWebView(context, record.pageUrl),
                      ),
                    ),
              ],
            ),
          ),
          if (sniffUrl != null)
            Positioned(
              right: 0,
              bottom: 0,
              child: HomeSniffer(
                key: ValueKey(sniffRequestId),
                initialUrl: sniffUrl!,
                onProgress: state.updateHomeSniffProgress,
                onFound: (record) {
                  unawaited(state.finishHomeSniffFound(record));
                  if (mounted) setState(() => sniffUrl = null);
                },
                onNotFound: (pageUrl, pageTitle) {
                  unawaited(
                    state.finishHomeSniffNotFound(
                      pageUrl: pageUrl,
                      pageTitle: pageTitle,
                    ),
                  );
                  if (mounted) setState(() => sniffUrl = null);
                },
                onFailed: (pageUrl, pageTitle, error) {
                  unawaited(
                    state.finishHomeSniffFailed(
                      pageUrl: pageUrl,
                      pageTitle: pageTitle,
                      error: error,
                    ),
                  );
                  if (mounted) setState(() => sniffUrl = null);
                },
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text?.trim().isNotEmpty ?? false) {
      setState(() => controller.text = data!.text!.trim());
    }
  }

  void _parse(BuildContext context, {String? url}) {
    FocusScope.of(context).unfocus();
    final value = (url ?? controller.text).trim();
    final state = UiStateScope.of(context);
    if (value.isEmpty) {
      state.clearResources(message: '请输入网页 URL');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入网页 URL')));
      return;
    }
    controller.text = value;
    state.startHomeSniff(value);
    setState(() {
      sniffUrl = value;
      sniffRequestId++;
    });
  }

  void _openWebView(BuildContext context, String url) {
    final value = url.trim();
    if (value.isEmpty) return;
    UiStateScope.of(context).openInBrowser(value);
  }

  int _todayCount(UiState state) {
    final now = DateTime.now();
    return state.videos.where((item) {
      final value = item.modifiedAt;
      return value.year == now.year &&
          value.month == now.month &&
          value.day == now.day;
    }).length;
  }

  String _formatBytes(int value) {
    if (value < 1024) return '$value B';
    if (value < 1024 * 1024) return '${(value / 1024).toStringAsFixed(1)} KB';
    if (value < 1024 * 1024 * 1024) {
      return '${(value / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(value / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
  }
}

class _HeroPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppTheme.primaryGradient,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.play_circle_fill_rounded,
            color: Colors.white,
            size: 42,
          ),
          const SizedBox(height: 18),
          Text(
            '解析网页视频，保存到本地',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            '在首页后台嗅探资源。发现 mp4/m3u8 后可直接下载。',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.86),
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _SnifferStatusBar extends StatelessWidget {
  const _SnifferStatusBar({required this.state});

  final UiState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isBusy = state.homeSnifferState == HomeSnifferState.sniffing;
    final icon = switch (state.homeSnifferState) {
      HomeSnifferState.found => Icons.check_circle_rounded,
      HomeSnifferState.notFound => Icons.info_rounded,
      HomeSnifferState.failed => Icons.error_outline_rounded,
      HomeSnifferState.idle || HomeSnifferState.sniffing => Icons.radar_rounded,
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          if (isBusy)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(icon, size: 20, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              state.homeSnifferStatus,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _ParseRecordCard extends StatelessWidget {
  _ParseRecordCard({
    required this.record,
    required this.onRetry,
    required this.onOpenWeb,
  }) : groups = _RecordGroups.from(record);

  final ParseRecord record;
  final VoidCallback onRetry;
  final VoidCallback onOpenWeb;
  final _RecordGroups groups;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final host = record.sourceSite.isNotEmpty
        ? record.sourceSite
        : (Uri.tryParse(record.pageUrl)?.host ?? '未知来源');
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  record.status == ParseRecordStatus.found
                      ? '来自 $host 的视频资源'
                      : host,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              Text(
                _timeLabel(record.parsedAt),
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            record.pageTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          if (record.status == ParseRecordStatus.found)
            _FoundRecordBody(
              record: record,
              groups: groups,
              onOpenWeb: onOpenWeb,
            )
          else
            _EmptyParseBody(
                record: record, onRetry: onRetry, onOpenWeb: onOpenWeb),
        ],
      ),
    );
  }

  String _timeLabel(DateTime value) {
    final now = DateTime.now();
    final diff = now.difference(value);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
    if (diff.inDays < 1) return '${diff.inHours} 小时前';
    return '${value.month}/${value.day}';
  }
}

class _RecordGroups {
  _RecordGroups({
    required this.recommended,
    required this.other,
    required this.ads,
    required this.fragments,
  });

  final List<VideoResource> recommended;
  final List<VideoResource> other;
  final List<VideoResource> ads;
  final List<VideoResource> fragments;

  factory _RecordGroups.from(ParseRecord record) {
    return _RecordGroups(
      recommended: record.recommendedResources.take(5).toList(growable: false),
      other: record.otherResources.take(20).toList(growable: false),
      ads: record.adResources.take(20).toList(growable: false),
      fragments: record.fragmentResources.take(50).toList(growable: false),
    );
  }
}

class _FoundRecordBody extends StatelessWidget {
  const _FoundRecordBody({
    required this.record,
    required this.groups,
    required this.onOpenWeb,
  });

  final ParseRecord record;
  final _RecordGroups groups;
  final VoidCallback onOpenWeb;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ResourceSection(
          title: '推荐资源',
          resources: groups.recommended,
          pageUrl: record.pageUrl,
          initiallyExpanded: true,
        ),
        if (groups.other.isNotEmpty) ...[
          const SizedBox(height: 8),
          _ResourceSection(
            title: '其它资源',
            resources: groups.other,
            pageUrl: record.pageUrl,
            initiallyExpanded: true,
          ),
        ],
        if (groups.ads.isNotEmpty) ...[
          const SizedBox(height: 8),
          _ResourceSection(
            title: '广告嫌疑资源',
            resources: groups.ads,
            pageUrl: record.pageUrl,
          ),
        ],
        if (groups.fragments.isNotEmpty) ...[
          const SizedBox(height: 8),
          _ResourceSection(
            title: 'TS/M4S 分片',
            resources: groups.fragments,
            pageUrl: record.pageUrl,
          ),
        ],
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: onOpenWeb,
            icon: const Icon(Icons.language_rounded),
            label: const Text('进入网页'),
          ),
        ),
      ],
    );
  }
}

class _EmptyParseBody extends StatelessWidget {
  const _EmptyParseBody({
    required this.record,
    required this.onRetry,
    required this.onOpenWeb,
  });

  final ParseRecord record;
  final VoidCallback onRetry;
  final VoidCallback onOpenWeb;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(record.message.isEmpty ? '未自动发现视频。' : record.message),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: onOpenWeb,
                icon: const Icon(Icons.play_circle_outline_rounded),
                label: const Text('进入网页播放并嗅探'),
              ),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('重试解析'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ResourceSection extends StatelessWidget {
  const _ResourceSection({
    required this.title,
    required this.resources,
    required this.pageUrl,
    this.initiallyExpanded = false,
  });

  final String title;
  final List<VideoResource> resources;
  final String pageUrl;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    if (resources.isEmpty) return const SizedBox.shrink();
    final visibleCount = resources.length > 8 ? 8 : resources.length;
    return ExpansionTile(
      initiallyExpanded: initiallyExpanded,
      tilePadding: EdgeInsets.zero,
      childrenPadding: EdgeInsets.zero,
      title: Text(
        '$title ${resources.length}',
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
      children: [
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: visibleCount,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final resource = resources[index];
            return RepaintBoundary(
              key: ValueKey(resource.id),
              child: _ResourceRow(resource: resource, pageUrl: pageUrl),
            );
          },
        ),
      ],
    );
  }
}

class _ResourceRow extends StatelessWidget {
  const _ResourceRow({required this.resource, required this.pageUrl});

  final VideoResource resource;
  final String pageUrl;

  @override
  Widget build(BuildContext context) {
    final state = UiStateScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final host = Uri.tryParse(resource.url)?.host ?? '未知来源';
    final meta = [
      resource.displayFormat,
      resource.quality,
      if (resource.duration > Duration.zero) _durationLabel(resource.duration),
      resource.size,
    ].where((item) => item.isNotEmpty && item != '未知').join(' · ');
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ResourceThumb(resource: resource),
              const SizedBox(width: 10),
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
                    const SizedBox(height: 4),
                    Text(
                      meta.isEmpty ? resource.displayFormat : meta,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$host · ${_sourceLabel(resource.source)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final badge in badges.take(2))
                _Badge(label: badge, danger: badge == '广告嫌疑'),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: resource.isFragment
                    ? null
                    : () async {
                        final selected =
                            await showDownloadConfirmDialog(context, resource);
                        if (selected == null || !context.mounted) return;
                        state.downloadResource(selected);
                      },
                icon: const Icon(Icons.download_rounded),
                label: const Text('下载'),
              ),
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
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已复制真实资源链接')),
                  );
                },
                icon: const Icon(Icons.copy_rounded),
                label: const Text('复制链接'),
              ),
              OutlinedButton.icon(
                onPressed: () => state.openInBrowser(
                  pageUrl.isNotEmpty ? pageUrl : resource.pageUrl,
                ),
                icon: const Icon(Icons.language_rounded),
                label: const Text('进入网页'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _sourceLabel(String value) {
    final lower = value.toLowerCase();
    if (lower.contains('xhr')) return 'XHR';
    if (lower.contains('fetch')) return 'fetch';
    if (lower.contains('dom')) return 'DOM';
    if (lower.contains('video') || lower.contains('media')) return 'video tag';
    return 'resource';
  }

  String _durationLabel(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }
}

class _ResourceThumb extends StatelessWidget {
  const _ResourceThumb({required this.resource});

  final VideoResource resource;

  @override
  Widget build(BuildContext context) {
    final thumb = resource.thumbnailUrl;
    if (thumb.startsWith('http://') || thumb.startsWith('https://')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          thumb,
          width: 72,
          height: 50,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _TypeBox(label: resource.displayFormat),
        ),
      );
    }
    return _TypeBox(label: resource.displayFormat);
  }
}

class _TypeBox extends StatelessWidget {
  const _TypeBox({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 50,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xff2563eb), Color(0xff7c3aed)],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.danger});

  final String label;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: danger ? scheme.errorContainer : scheme.primaryContainer,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: danger ? scheme.onErrorContainer : scheme.onPrimaryContainer,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

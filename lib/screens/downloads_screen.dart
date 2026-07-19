import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../models/download_task.dart';
import '../services/ui_state.dart';
import '../widgets/app_card.dart';
import '../widgets/empty_state.dart';
import 'player_screen.dart';

class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = UiStateScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('下载中'),
        actions: [
          IconButton(
            tooltip: '清理记录',
            onPressed: () => state.downloadManager.clearHistory(),
            icon: const Icon(Icons.delete_sweep_rounded),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: state,
        builder: (context, _) {
          final tasks = state.downloadManager.tasks
              .where(
                (task) =>
                    task.status != DownloadStatus.completed &&
                    task.status != DownloadStatus.canceled,
              )
              .toList(growable: false);
          if (tasks.isEmpty) {
            return const EmptyState(
              icon: Icons.downloading_rounded,
              title: '暂无下载中任务',
              message: '网页播放时检测到视频后，点击红色下载按钮即可开始下载。',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
            itemBuilder: (context, index) => _DownloadCard(task: tasks[index]),
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemCount: tasks.length,
          );
        },
      ),
    );
  }
}

class _DownloadCard extends StatelessWidget {
  const _DownloadCard({required this.task});

  final DownloadTask task;

  @override
  Widget build(BuildContext context) {
    final state = UiStateScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final isCompleted = task.status == DownloadStatus.completed;
    final isFailed = task.status == DownloadStatus.failed;
    final isMissing = task.status == DownloadStatus.missing;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: isCompleted
                      ? scheme.primaryContainer
                      : (isFailed || isMissing
                          ? scheme.errorContainer
                          : scheme.secondaryContainer),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  isCompleted
                      ? Icons.check_rounded
                      : (isFailed || isMissing
                          ? Icons.error_outline_rounded
                          : Icons.downloading_rounded),
                  color: isCompleted
                      ? scheme.primary
                      : (isFailed || isMissing
                          ? scheme.error
                          : scheme.secondary),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.resource.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${task.resource.label} · ${_phaseLabel(task)} · ${_percent(task)} · ${task.speed} · ${_remainingLabel(task)}',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LinearProgressIndicator(
            value: task.isIndeterminate
                ? null
                : task.progress.clamp(0, 1).toDouble(),
            minHeight: 8,
            borderRadius: BorderRadius.circular(99),
          ),
          const SizedBox(height: 8),
          Text(
            task.errorMessage.isNotEmpty ? task.errorMessage : task.message,
            style: TextStyle(
              color: isFailed ? scheme.error : scheme.onSurfaceVariant,
            ),
          ),
          if (task.resource.isMergeRequired && task.totalSegments > 0) ...[
            const SizedBox(height: 6),
            Text(
              '分片 ${task.downloadedSegments}/${task.totalSegments} · ffmpeg ${task.ffmpegTime} / ${_durationLabel(task.playlistDuration)} · speed ${task.ffmpegSpeed}x · 已用 ${_durationLabel(task.elapsed)}',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (task.status == DownloadStatus.downloading ||
                  task.status == DownloadStatus.preparing ||
                  task.status == DownloadStatus.merging)
                FilledButton.tonalIcon(
                  onPressed: () => state.downloadManager.pause(task),
                  icon: const Icon(Icons.pause_rounded),
                  label: const Text('暂停'),
                ),
              if (task.status == DownloadStatus.paused ||
                  task.status == DownloadStatus.failed ||
                  task.status == DownloadStatus.canceled)
                FilledButton.tonalIcon(
                  onPressed: () => state.downloadManager.retry(task),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(
                    task.status == DownloadStatus.failed ? '重试' : '继续',
                  ),
                ),
              if (!isCompleted && !isMissing)
                OutlinedButton.icon(
                  onPressed: () => state.downloadManager.cancel(task),
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('取消'),
                ),
              if (isCompleted)
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PlayerScreen(
                        title: task.resource.title,
                        filePath: task.localPath,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('播放'),
                ),
              if (isCompleted && task.localPath.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () => Share.shareXFiles([
                    XFile(task.localPath),
                  ], text: task.resource.title),
                  icon: const Icon(Icons.ios_share_rounded),
                  label: const Text('分享'),
                ),
              if (task.ffmpegLog.isNotEmpty || task.errorDetails.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () => _showDetails(context, task),
                  icon: const Icon(Icons.article_outlined),
                  label: const Text('查看详情'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _statusLabel(DownloadStatus status) {
    switch (status) {
      case DownloadStatus.preparing:
        return '准备中';
      case DownloadStatus.idle:
        return '等待中';
      case DownloadStatus.downloading:
        return '下载中';
      case DownloadStatus.merging:
        return '合并中';
      case DownloadStatus.paused:
        return '已暂停';
      case DownloadStatus.completed:
        return '已完成';
      case DownloadStatus.failed:
        return '失败';
      case DownloadStatus.canceled:
        return '已取消';
      case DownloadStatus.missing:
        return '文件缺失';
    }
  }

  String _phaseLabel(DownloadTask task) {
    switch (task.phase) {
      case DownloadPhase.preparing:
        return '准备中';
      case DownloadPhase.fetchingPlaylist:
        return '获取播放列表';
      case DownloadPhase.downloadingSegments:
        return '下载分片';
      case DownloadPhase.downloadingFile:
        return _statusLabel(task.status);
      case DownloadPhase.merging:
        return '合并中';
      case DownloadPhase.completed:
        return '已完成';
      case DownloadPhase.failed:
        return '失败';
      case DownloadPhase.canceled:
        return '已取消';
    }
  }

  String _percent(DownloadTask task) {
    if (task.isIndeterminate) return '未知';
    return '${(task.progress.clamp(0, 1) * 100).round()}%';
  }

  String _remainingLabel(DownloadTask task) {
    if (task.status == DownloadStatus.completed) return '剩余 00:00';
    if (task.remaining.trim().isEmpty || task.remaining == '剩余时间未知') {
      return '剩余时间未知';
    }
    return '剩余 ${task.remaining}';
  }

  String _durationLabel(Duration value) {
    if (value == Duration.zero) return '未知';
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  void _showDetails(BuildContext context, DownloadTask task) {
    final details =
        task.errorDetails.isNotEmpty ? task.errorDetails : task.ffmpegLog;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('任务详情'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(child: SelectableText(details)),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: details));
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('已复制详情日志')));
            },
            child: const Text('复制'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}

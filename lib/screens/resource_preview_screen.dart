import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/video_resource.dart';

class ResourcePreviewScreen extends StatefulWidget {
  const ResourcePreviewScreen.network({required this.resource, super.key})
      : filePath = null,
        title = null,
        subtitle = null;

  const ResourcePreviewScreen.file({
    required this.filePath,
    required this.title,
    required this.subtitle,
    super.key,
  }) : resource = null;

  final VideoResource? resource;
  final String? filePath;
  final String? title;
  final String? subtitle;

  @override
  State<ResourcePreviewScreen> createState() => _ResourcePreviewScreenState();
}

class _ResourcePreviewScreenState extends State<ResourcePreviewScreen> {
  VideoPlayerController? controller;
  String? error;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final resource = widget.resource;
    final title = resource?.title ?? widget.title ?? '视频预览';
    final uri = resource == null ? null : Uri.tryParse(resource.url);
    return Scaffold(
      appBar: AppBar(title: Text(title, maxLines: 1)),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(18),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Center(child: _playerView()),
              ),
            ),
          ),
          if (controller?.value.isInitialized == true) ...[
            const SizedBox(height: 10),
            _PreviewControls(
              controller: controller!,
              onTogglePlay: _togglePlay,
            ),
          ],
          const SizedBox(height: 16),
          _InfoLine('标题', title),
          if (resource != null) ...[
            _InfoLine('格式', resource.displayFormat),
            _InfoLine('分辨率', resource.quality),
            _InfoLine('时长', _durationLabel(resource.duration)),
            _InfoLine('来源域名', uri?.host ?? '未知'),
          ] else ...[
            _InfoLine('格式', '本地临时文件'),
            _InfoLine('进度', widget.subtitle ?? '下载中'),
          ],
        ],
      ),
      floatingActionButton: controller?.value.isInitialized == true
          ? FloatingActionButton(
              onPressed: _togglePlay,
              child: Icon(
                controller!.value.isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
              ),
            )
          : null,
    );
  }

  Widget _playerView() {
    final player = controller;
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.all(18),
        child: Text(
          error!,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70),
        ),
      );
    }
    if (player == null || !player.value.isInitialized) {
      return const CircularProgressIndicator(color: Colors.white);
    }
    return Stack(
      children: [
        Center(
          child: AspectRatio(
            aspectRatio: player.value.aspectRatio <= 0
                ? 16 / 9
                : player.value.aspectRatio,
            child: VideoPlayer(player),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: VideoProgressIndicator(
            player,
            allowScrubbing: true,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            colors: const VideoProgressColors(
              playedColor: Colors.white,
              bufferedColor: Colors.white38,
              backgroundColor: Colors.white24,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _open() async {
    try {
      final resource = widget.resource;
      if (resource != null) {
        final uri = Uri.parse(resource.url);
        controller = VideoPlayerController.networkUrl(
          uri,
          formatHint:
              resource.type == VideoResourceType.hls ? VideoFormat.hls : null,
          httpHeaders: _headers(resource),
        );
      } else {
        final file = File(widget.filePath ?? '');
        if (!await file.exists() || await file.length() <= 0) {
          throw StateError('当前片段暂不可预览');
        }
        controller = VideoPlayerController.file(file);
      }
      controller!.addListener(_onPlayerChanged);
      await controller!.initialize();
      if (!mounted) return;
      setState(() {});
      await controller!.play();
    } catch (error) {
      if (mounted) {
        final expired = widget.resource != null &&
            (widget.resource!.cookie.isNotEmpty ||
                '$error'.contains('401') ||
                '$error'.contains('403'));
        setState(
          () => this.error =
              expired ? '资源已过期，请重新进入网页播放后嗅探。' : '该资源不支持在线播放，请尝试下载后播放。',
        );
      }
    }
  }

  void _togglePlay() {
    final player = controller;
    if (player == null || !player.value.isInitialized) return;
    player.value.isPlaying ? player.pause() : player.play();
    setState(() {});
  }

  void _onPlayerChanged() {
    if (mounted) setState(() {});
  }

  Map<String, String> _headers(VideoResource resource) {
    return {
      'User-Agent': resource.userAgent.isNotEmpty
          ? resource.userAgent
          : 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15',
      if (resource.referer.isNotEmpty || resource.pageUrl.isNotEmpty)
        'Referer':
            resource.referer.isNotEmpty ? resource.referer : resource.pageUrl,
      if (resource.cookie.isNotEmpty) 'Cookie': resource.cookie,
      if (resource.origin.isNotEmpty) 'Origin': resource.origin,
      'Accept': '*/*',
    }..removeWhere((_, value) => value.trim().isEmpty);
  }

  String _durationLabel(Duration duration) {
    if (duration == Duration.zero) return '未知';
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }
}

class _PreviewControls extends StatelessWidget {
  const _PreviewControls({
    required this.controller,
    required this.onTogglePlay,
  });

  final VideoPlayerController controller;
  final VoidCallback onTogglePlay;

  @override
  Widget build(BuildContext context) {
    final value = controller.value;
    final position = value.position;
    final duration = value.duration;
    return Row(
      children: [
        IconButton(
          onPressed: onTogglePlay,
          icon: Icon(
            value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          ),
        ),
        Text(_durationLabel(position)),
        Expanded(
          child: Slider(
            value: duration.inMilliseconds <= 0
                ? 0
                : position.inMilliseconds
                    .clamp(0, duration.inMilliseconds)
                    .toDouble(),
            min: 0,
            max: duration.inMilliseconds <= 0
                ? 1
                : duration.inMilliseconds.toDouble(),
            onChanged: duration.inMilliseconds <= 0
                ? null
                : (value) => controller.seekTo(
                      Duration(milliseconds: value.round()),
                    ),
          ),
        ),
        Text(_durationLabel(duration)),
      ],
    );
  }

  String _durationLabel(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value.isEmpty ? '未知' : value)),
        ],
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/video_resource.dart';
import '../services/ui_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_card.dart';
import '../widgets/app_text_field.dart';
import '../widgets/download_confirm_dialog.dart';
import '../widgets/gradient_button.dart';
import 'resource_preview_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final controller = TextEditingController();
  final FocusNode focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _checkClipboard();
  }

  @override
  void dispose() {
    controller.dispose();
    focusNode.dispose();
    super.dispose();
  }

  Future<void> _checkClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isNotEmpty && text.startsWith('http') && controller.text.isEmpty) {
      if (mounted) setState(() => controller.text = text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = UiStateScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: const Text('视频解析'),
        centerTitle: false,
        scrolledUnderElevation: 0,
      ),
      body: AnimatedBuilder(
        animation: state,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _InputCard(
              controller: controller,
              focusNode: focusNode,
              parsing: state.parsing,
              status: state.status,
              onPaste: _paste,
              onParse: () => _parse(context),
            ),
            const SizedBox(height: 20),
            if (state.recentUrls.isNotEmpty) ...[
              _SectionTitle('最近的链接'),
              const SizedBox(height: 10),
              AppCard(
                child: Column(
                  children: [
                    for (var i = 0; i < state.recentUrls.length; i++) ...[
                      if (i > 0)
                        Divider(height: 1, color: scheme.outlineVariant),
                      _RecentUrlTile(
                        url: state.recentUrls[i],
                        onTap: () {
                          controller.text = state.recentUrls[i];
                          _parse(context);
                        },
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
            _SectionTitle(
              state.parsing
                  ? '正在解析…'
                  : state.resources.isEmpty
                      ? '视频资源'
                      : '发现 ${state.resources.length} 个视频资源',
            ),
            const SizedBox(height: 10),
            if (state.parsing)
              AppCard(
                child: Row(
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '正在抓取页面并提取视频源…',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              )
            else if (state.resources.isEmpty)
              AppCard(
                child: Column(
                  children: [
                    Icon(
                      Icons.movie_outlined,
                      size: 40,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 12),
                    const Text('粘贴视频页链接，自动解析出可下载的视频源'),
                    const SizedBox(height: 4),
                    Text(
                      '支持 mp4 / m3u8 / ts 等常见格式',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              )
            else
              for (final resource in state.resources)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _ResourceCard(resource: resource),
                ),
          ],
        ),
      ),
    );
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text?.trim().isNotEmpty ?? false) {
      setState(() => controller.text = data!.text!.trim());
      focusNode.unfocus();
      _parse(context);
    }
  }

  void _parse(BuildContext context) {
    focusNode.unfocus();
    final value = controller.text.trim();
    final state = UiStateScope.of(context);
    if (value.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入或粘贴视频链接')));
      return;
    }
    unawaited(state.parseUrl(value));
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: scheme.onSurface,
        ),
      ),
    );
  }
}

class _InputCard extends StatelessWidget {
  const _InputCard({
    required this.controller,
    required this.focusNode,
    required this.parsing,
    required this.status,
    required this.onPaste,
    required this.onParse,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool parsing;
  final String status;
  final VoidCallback onPaste;
  final VoidCallback onParse;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            controller: controller,
            focusNode: focusNode,
            hintText: '粘贴或输入视频页链接',
            onSubmitted: (_) => onParse(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onPaste,
                  icon: const Icon(Icons.content_paste_rounded),
                  label: const Text('粘贴'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: parsing ? null : onParse,
                  icon: parsing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.auto_awesome_rounded),
                  label: Text(parsing ? '解析中' : '解析视频'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecentUrlTile extends StatelessWidget {
  const _RecentUrlTile({required this.url, required this.onTap});

  final String url;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final host = Uri.tryParse(url)?.host ?? url;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Row(
          children: [
            const Icon(Icons.history_rounded, size: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                host,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _ResourceCard extends StatelessWidget {
  const _ResourceCard({required this.resource});

  final VideoResource resource;

  @override
  Widget build(BuildContext context) {
    final state = UiStateScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final meta = [
      resource.displayFormat,
      resource.quality,
      if (resource.duration > Duration.zero) _durationLabel(resource.duration),
      resource.size,
    ].where((item) => item.isNotEmpty && item != '未知').join(' · ');
    final host = Uri.tryParse(resource.url)?.host ?? '未知来源';
    final recommended = resource.recommendation.isNotEmpty &&
        !resource.isAdSuspect;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ResourceThumb(resource: resource),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      resource.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      meta.isEmpty ? resource.displayFormat : meta,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      host,
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
              if (recommended)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    resource.recommendation,
                    style: TextStyle(
                      color: scheme.onPrimaryContainer,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton.icon(
                onPressed: resource.isFragment
                    ? null
                    : () async {
                        final selected = await showDownloadConfirmDialog(
                          context,
                          resource,
                        );
                        if (selected == null || !context.mounted) return;
                        state.downloadResource(selected);
                      },
                icon: const Icon(Icons.download_rounded),
                label: const Text('下载'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: resource.isPlayable
                    ? () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => ResourcePreviewScreen.network(
                              resource: resource,
                            ),
                          ),
                        )
                    : null,
                icon: const Icon(Icons.play_circle_outline_rounded),
                label: const Text('预览'),
              ),
              const Spacer(),
              IconButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: resource.url));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已复制真实资源链接')),
                  );
                },
                icon: const Icon(Icons.copy_rounded),
                tooltip: '复制链接',
              ),
            ],
          ),
        ],
      ),
    );
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
          width: 84,
          height: 56,
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
      width: 84,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: AppTheme.primaryGradient,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

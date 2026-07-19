import 'package:flutter/material.dart';

import '../models/library_folder.dart';
import '../models/video_resource.dart';
import '../services/file_utils.dart';
import '../services/ui_state.dart';

enum DownloadSaveTarget { recent, site, page, custom, create }

Future<VideoResource?> showDownloadConfirmDialog(
  BuildContext context,
  VideoResource resource,
) async {
  final state = UiStateScope.of(context);
  final nameController = TextEditingController(
    text: FileUtils.safeFileName(resource.title, fallback: 'video'),
  );
  DownloadSaveTarget target = DownloadSaveTarget.page;
  LibraryFolder? selectedFolder =
      state.folders.isEmpty ? null : state.folders.first;
  try {
    return showDialog<VideoResource>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          final uri = Uri.tryParse(
            resource.pageUrl.isNotEmpty ? resource.pageUrl : resource.url,
          );
          final site = uri?.host ?? '未知来源';
          return AlertDialog(
            title: const Text('确认下载'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _InfoLine('标题', resource.title),
                  _InfoLine('来源网站', site),
                  _InfoLine('格式', resource.displayFormat),
                  _InfoLine('清晰度', resource.quality),
                  if (resource.codec.isNotEmpty)
                    _InfoLine('编码', resource.codec),
                  if (resource.bitrate.isNotEmpty)
                    _InfoLine('码率', resource.bitrate),
                  _InfoLine('大小', resource.size),
                  const _InfoLine('实际位置', 'Documents/videos/页面合集/'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: '文件名'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<DownloadSaveTarget>(
                    initialValue: target,
                    decoration: const InputDecoration(labelText: '保存到'),
                    items: const [
                      DropdownMenuItem(
                        value: DownloadSaveTarget.recent,
                        child: Text('最近下载'),
                      ),
                      DropdownMenuItem(
                        value: DownloadSaveTarget.site,
                        child: Text('来源网站文件夹'),
                      ),
                      DropdownMenuItem(
                        value: DownloadSaveTarget.page,
                        child: Text('当前页面文件夹'),
                      ),
                      DropdownMenuItem(
                        value: DownloadSaveTarget.custom,
                        child: Text('自定义文件夹'),
                      ),
                      DropdownMenuItem(
                        value: DownloadSaveTarget.create,
                        child: Text('新建文件夹'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => target = value);
                    },
                  ),
                  if (target == DownloadSaveTarget.custom) ...[
                    const SizedBox(height: 10),
                    DropdownButtonFormField<LibraryFolder>(
                      initialValue: selectedFolder,
                      decoration: const InputDecoration(labelText: '自定义文件夹'),
                      items: state.folders
                          .map(
                            (folder) => DropdownMenuItem(
                              value: folder,
                              child: Text(folder.name),
                            ),
                          )
                          .toList(),
                      onChanged: (value) =>
                          setState(() => selectedFolder = value),
                    ),
                    if (state.folders.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text('还没有自定义文件夹，可以选择“新建文件夹”。'),
                      ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () async {
                  final folder = await _resolveFolder(
                    dialogContext,
                    state,
                    resource,
                    target,
                    selectedFolder,
                  );
                  if (folder == null && target == DownloadSaveTarget.create) {
                    return;
                  }
                  final name = FileUtils.safeFileName(
                    nameController.text,
                    fallback: resource.title,
                  );
                  if (!dialogContext.mounted) return;
                  Navigator.pop(
                    dialogContext,
                    resource.copyWith(
                      title: name,
                      preferredFolderId: folder?.folderId ?? '',
                      preferredFolderName: folder?.name ?? '',
                    ),
                  );
                },
                child: const Text('下载'),
              ),
            ],
          );
        },
      ),
    );
  } finally {
    nameController.dispose();
  }
}

Future<LibraryFolder?> _resolveFolder(
  BuildContext context,
  UiState state,
  VideoResource resource,
  DownloadSaveTarget target,
  LibraryFolder? selectedFolder,
) async {
  final pageUrl = resource.pageUrl.isNotEmpty ? resource.pageUrl : resource.url;
  final host = Uri.tryParse(pageUrl)?.host ?? '';
  switch (target) {
    case DownloadSaveTarget.recent:
      return null;
    case DownloadSaveTarget.site:
      if (host.isEmpty) return null;
      final now = DateTime.now();
      return LibraryFolder(
        folderId: 'site:$host',
        name: host,
        type: LibraryFolderType.site,
        createdAt: now,
        updatedAt: now,
      );
    case DownloadSaveTarget.page:
      final now = DateTime.now();
      return LibraryFolder(
        folderId: 'page:${FileUtils.stableKey(pageUrl)}',
        name: resource.title.trim().isEmpty ? '当前页面' : resource.title,
        type: LibraryFolderType.page,
        createdAt: now,
        updatedAt: now,
      );
    case DownloadSaveTarget.custom:
      return selectedFolder;
    case DownloadSaveTarget.create:
      final name = await _askFolderName(context);
      if (name == null || name.trim().isEmpty) return null;
      return state.createFolder(name);
  }
}

Future<String?> _askFolderName(BuildContext context) async {
  final controller = TextEditingController();
  try {
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建文件夹'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '文件夹名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
  } finally {
    controller.dispose();
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
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

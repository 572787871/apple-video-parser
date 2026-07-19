import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/library_folder.dart';
import 'file_utils.dart';

class LibraryFolderStore {
  Future<List<LibraryFolder>> load() async {
    final file = await _file();
    if (!await file.exists()) return const [];
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map(
              (item) => LibraryFolder.fromJson(Map<String, dynamic>.from(item)))
          .where((folder) => folder.folderId.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> save(List<LibraryFolder> folders) async {
    final file = await _file();
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    await file.writeAsString(
      jsonEncode(folders.map((folder) => folder.toJson()).toList()),
    );
  }

  LibraryFolder createManualFolder(String name) {
    final now = DateTime.now();
    final safeName = FileUtils.safeFileName(name, fallback: '新建文件夹');
    return LibraryFolder(
      folderId:
          'manual:${FileUtils.stableKey('$safeName-${now.microsecondsSinceEpoch}')}',
      name: safeName,
      type: LibraryFolderType.manual,
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, 'library_folders.json'));
  }
}

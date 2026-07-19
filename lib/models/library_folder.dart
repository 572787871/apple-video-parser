enum LibraryFolderType { manual, site, page, recent, favorite }

class LibraryFolder {
  const LibraryFolder({
    required this.folderId,
    required this.name,
    required this.type,
    required this.createdAt,
    required this.updatedAt,
  });

  final String folderId;
  final String name;
  final LibraryFolderType type;
  final DateTime createdAt;
  final DateTime updatedAt;

  LibraryFolder copyWith({
    String? folderId,
    String? name,
    LibraryFolderType? type,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return LibraryFolder(
      folderId: folderId ?? this.folderId,
      name: name ?? this.name,
      type: type ?? this.type,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'folderId': folderId,
      'name': name,
      'type': type.name,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory LibraryFolder.fromJson(Map<String, dynamic> json) {
    return LibraryFolder(
      folderId: json['folderId']?.toString() ?? '',
      name: json['name']?.toString() ?? '未命名文件夹',
      type: _typeFromName(json['type']?.toString() ?? ''),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  static LibraryFolderType _typeFromName(String value) {
    for (final type in LibraryFolderType.values) {
      if (type.name == value) return type;
    }
    return LibraryFolderType.manual;
  }
}

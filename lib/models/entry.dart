/// Entry model representing a reference to an external directory.
/// Papers always live in entries (symlink-only model).
class Entry {
  final int? id;
  final String path;
  final String name;
  final DateTime addedAt;
  bool isExpanded; // Runtime UI state
  bool isAccessible; // False if folder missing on disk
  int paperCount;
  List<SubfolderNode> subfolderTree; // Top-level subfolder nodes

  Entry({
    this.id,
    required this.path,
    required this.name,
    DateTime? addedAt,
    this.isExpanded = false,
    this.isAccessible = true,
    this.paperCount = 0,
    List<SubfolderNode>? subfolderTree,
  })  : addedAt = addedAt ?? DateTime.now(),
        subfolderTree = subfolderTree ?? [];

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'path': path,
      'name': name,
      'added_at': addedAt.toIso8601String(),
    };
  }

  factory Entry.fromMap(Map<String, dynamic> map) {
    return Entry(
      id: map['id'] as int?,
      path: map['path'] as String,
      name: map['name'] as String,
      addedAt: DateTime.parse(map['added_at'] as String),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Entry && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// A node in an entry's subfolder tree.
///
/// `relativePath` is the full path from the entry root, using forward slashes
/// (e.g. "Avatar/HeadAvatar"). `totalCount` includes all PDFs at this node's
/// path or any descendant; `directCount` only counts PDFs whose parent dir is
/// exactly this node.
class SubfolderNode {
  final String name;
  final String relativePath;
  int directCount;
  int totalCount;
  bool isExpanded;
  final List<SubfolderNode> children;

  SubfolderNode({
    required this.name,
    required this.relativePath,
    this.directCount = 0,
    this.totalCount = 0,
    this.isExpanded = false,
    List<SubfolderNode>? children,
  }) : children = children ?? [];

  bool get hasChildren => children.isNotEmpty;
}

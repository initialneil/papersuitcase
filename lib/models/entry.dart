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
  Map<String, int> subfolderCounts; // relativePath -> count

  Entry({
    this.id,
    required this.path,
    required this.name,
    DateTime? addedAt,
    this.isExpanded = false,
    this.isAccessible = true,
    this.paperCount = 0,
    Map<String, int>? subfolderCounts,
  })  : addedAt = addedAt ?? DateTime.now(),
        subfolderCounts = subfolderCounts ?? {};

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
}

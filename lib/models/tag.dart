/// Tag model representing a category/topic for papers.
/// Tags support hierarchical structure via parentId.
class Tag {
  final int? id;
  final String name;
  final int? parentId;
  int paperCount;
  List<Tag> children;
  bool isExpanded;

  Tag({
    this.id,
    required this.name,
    this.parentId,
    this.paperCount = 0,
    List<Tag>? children,
    this.isExpanded = false,
  }) : children = children ?? [];

  /// Special "Untagged" tag for papers without tags
  static Tag untagged({int paperCount = 0}) => Tag(
        id: -1,
        name: 'Untagged',
        paperCount: paperCount,
      );

  bool get isUntagged => id == -1;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'parent_id': parentId,
    };
  }

  factory Tag.fromMap(Map<String, dynamic> map) {
    return Tag(
      id: map['id'] as int?,
      name: map['name'] as String,
      parentId: map['parent_id'] as int?,
      paperCount: map['paper_count'] as int? ?? 0,
    );
  }

  Tag copyWith({
    int? id,
    String? name,
    int? parentId,
    int? paperCount,
    List<Tag>? children,
    bool? isExpanded,
  }) {
    return Tag(
      id: id ?? this.id,
      name: name ?? this.name,
      parentId: parentId ?? this.parentId,
      paperCount: paperCount ?? this.paperCount,
      children: children ?? this.children,
      isExpanded: isExpanded ?? this.isExpanded,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Tag && other.id == id && other.name == name;
  }

  @override
  int get hashCode => id.hashCode ^ name.hashCode;

  @override
  String toString() => 'Tag(id: $id, name: $name, parentId: $parentId, count: $paperCount)';
}

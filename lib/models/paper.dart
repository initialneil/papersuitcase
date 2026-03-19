import 'tag.dart';

/// Paper model representing a PDF document with metadata.
class Paper {
  final int? id;
  final String title;
  final String filePath;
  final int entryId;
  final String? arxivId;
  final String? authors;
  final String? abstract;
  final String? extractedText;
  final DateTime addedAt;
  final String? arxivUrl;
  final String? bibtex;
  final String bibStatus;
  final String? contentHash;
  final String? syncKey;
  final int? remoteId;
  final DateTime? updatedAt;
  final DateTime? deletedAt;
  final bool dirty;
  List<Tag> tags;

  Paper({
    this.id,
    required this.title,
    required this.filePath,
    required this.entryId,
    this.arxivId,
    this.authors,
    this.abstract,
    this.extractedText,
    DateTime? addedAt,
    this.arxivUrl,
    this.bibtex,
    this.bibStatus = 'none',
    this.contentHash,
    this.syncKey,
    this.remoteId,
    this.updatedAt,
    this.deletedAt,
    this.dirty = true,
    List<Tag>? tags,
  }) : addedAt = addedAt ?? DateTime.now(),
       tags = tags ?? [];

  /// Get formatted date string
  String get formattedDate {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[addedAt.month - 1]} ${addedAt.day}, ${addedAt.year}';
  }

  /// Get truncated title for display
  String get displayTitle {
    if (title.length <= 60) return title;
    return '${title.substring(0, 57)}...';
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'file_path': filePath,
      'entry_id': entryId,
      'arxiv_id': arxivId,
      'authors': authors,
      'abstract': abstract,
      'extracted_text': extractedText,
      'added_at': addedAt.toIso8601String(),
      'arxiv_url': arxivUrl,
      'bibtex': bibtex,
      'bib_status': bibStatus,
      'content_hash': contentHash,
      if (syncKey != null) 'sync_key': syncKey,
      if (remoteId != null) 'remote_id': remoteId,
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
      if (deletedAt != null) 'deleted_at': deletedAt!.toIso8601String(),
      'dirty': dirty ? 1 : 0,
    };
  }

  factory Paper.fromMap(Map<String, dynamic> map, {List<Tag>? tags}) {
    return Paper(
      id: map['id'] as int?,
      title: map['title'] as String,
      filePath: map['file_path'] as String,
      entryId: map['entry_id'] as int,
      arxivId: map['arxiv_id'] as String?,
      authors: map['authors'] as String?,
      abstract: map['abstract'] as String?,
      extractedText: map['extracted_text'] as String?,
      addedAt: DateTime.parse(map['added_at'] as String),
      arxivUrl: map['arxiv_url'] as String?,
      bibtex: map['bibtex'] as String?,
      bibStatus: map['bib_status'] as String? ?? 'none',
      contentHash: map['content_hash'] as String?,
      syncKey: map['sync_key'] as String?,
      remoteId: map['remote_id'] as int?,
      updatedAt: map['updated_at'] != null ? DateTime.parse(map['updated_at'] as String) : null,
      deletedAt: map['deleted_at'] != null ? DateTime.parse(map['deleted_at'] as String) : null,
      dirty: map.containsKey('dirty') ? (map['dirty'] as int?) == 1 : true,
      tags: tags,
    );
  }

  Paper copyWith({
    int? id,
    String? title,
    String? filePath,
    int? entryId,
    String? arxivId,
    String? authors,
    String? abstract,
    String? extractedText,
    DateTime? addedAt,
    String? arxivUrl,
    String? bibtex,
    String? bibStatus,
    String? contentHash,
    String? syncKey,
    int? remoteId,
    DateTime? updatedAt,
    DateTime? deletedAt,
    bool? dirty,
    List<Tag>? tags,
  }) {
    return Paper(
      id: id ?? this.id,
      title: title ?? this.title,
      filePath: filePath ?? this.filePath,
      entryId: entryId ?? this.entryId,
      arxivId: arxivId ?? this.arxivId,
      authors: authors ?? this.authors,
      abstract: abstract ?? this.abstract,
      extractedText: extractedText ?? this.extractedText,
      addedAt: addedAt ?? this.addedAt,
      arxivUrl: arxivUrl ?? this.arxivUrl,
      bibtex: bibtex ?? this.bibtex,
      bibStatus: bibStatus ?? this.bibStatus,
      contentHash: contentHash ?? this.contentHash,
      syncKey: syncKey ?? this.syncKey,
      remoteId: remoteId ?? this.remoteId,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      dirty: dirty ?? this.dirty,
      tags: tags ?? this.tags,
    );
  }

  @override
  String toString() => 'Paper(id: $id, title: $title, tags: ${tags.length})';
}

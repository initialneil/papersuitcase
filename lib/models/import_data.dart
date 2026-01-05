/// Data class for pending paper import before confirmation
class PendingImport {
  final String sourcePath;
  final String fileName;
  final List<String> suggestedTags;
  bool isSelected;
  List<String> assignedTags;

  PendingImport({
    required this.sourcePath,
    required this.fileName,
    List<String>? suggestedTags,
    this.isSelected = true,
    List<String>? assignedTags,
  }) : suggestedTags = suggestedTags ?? [],
       assignedTags = assignedTags ?? [];

  /// Create from file path with folder-based tag suggestions
  factory PendingImport.fromPath(String path, {String? basePath}) {
    final fileName = path.split('/').last;
    List<String> tags = [];

    if (basePath != null && path.startsWith(basePath)) {
      // Extract folder names as tags
      final relativePath = path.substring(basePath.length);
      final parts = relativePath.split('/');
      // Remove empty strings and the file name
      tags = parts.where((p) => p.isNotEmpty && !p.endsWith('.pdf')).toList();
    }

    return PendingImport(
      sourcePath: path,
      fileName: fileName,
      suggestedTags: tags,
      assignedTags: List.from(tags),
    );
  }

  @override
  String toString() => 'PendingImport($fileName, tags: $assignedTags)';
}

/// Type of import being performed
enum ImportType { singleFile, multipleFiles, folder, arxiv }

/// Result of folder scanning
class FolderScanResult {
  final String folderName;
  final String folderPath;
  final List<PendingImport> files;
  final Map<String, List<String>> folderHierarchy;

  FolderScanResult({
    required this.folderName,
    required this.folderPath,
    required this.files,
    required this.folderHierarchy,
  });

  int get fileCount => files.length;
}

/// arXiv paper metadata
class ArxivMetadata {
  final String arxivId;
  final String title;
  final String authors;
  final String abstract;
  final String pdfUrl;
  final String? category;

  ArxivMetadata({
    required this.arxivId,
    required this.title,
    required this.authors,
    required this.abstract,
    required this.pdfUrl,
    this.category,
  });

  @override
  String toString() => 'ArxivMetadata($arxivId: $title)';
}

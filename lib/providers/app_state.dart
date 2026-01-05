import 'package:flutter/widgets.dart';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../database/database_service.dart';
import '../models/paper.dart';
import '../models/tag.dart';
import '../models/import_data.dart';
import '../services/pdf_service.dart';
import '../services/arxiv_service.dart';
import '../services/folder_import_service.dart';

/// Main application state provider
class AppState extends ChangeNotifier {
  final DatabaseService _db = DatabaseService();
  final PdfService _pdfService = PdfService();
  final ArxivService _arxivService = ArxivService();
  final FolderImportService _folderImportService = FolderImportService();

  // State
  List<Paper> _papers = [];
  List<Tag> _tagTree = [];
  List<Tag> _relatedTags = [];
  Tag? _selectedTag;
  List<Tag> _lastActiveTagPath = [];
  String _searchQuery = '';
  bool _isLoading = false;
  String? _error;
  String? _detectedArxivUrl;
  final Set<int> _selectedPaperIds = {};

  // Getters
  List<Paper> get papers => _papers;
  List<Tag> get tagTree => _tagTree;
  List<Tag> get relatedTags => _relatedTags;
  Tag? get selectedTag => _selectedTag;
  List<Tag> get lastActiveTagPath => _lastActiveTagPath;
  String get searchQuery => _searchQuery;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get detectedArxivUrl => _detectedArxivUrl;
  Set<int> get selectedPaperIds => _selectedPaperIds;
  bool get isOthersSelected => _selectedTag?.isOthers ?? false;

  /// Initialize the app state
  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    try {
      await DatabaseService.initialize();
      await refresh();
    } catch (e) {
      _error = 'Failed to initialize: $e';
      print(_error);
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Refresh all data
  Future<void> refresh() async {
    await Future.wait([_loadPapers(), _loadTagTree()]);
    notifyListeners();
  }

  Future<void> _loadPapers() async {
    if (_selectedTag != null) {
      if (_selectedTag!.isOthers) {
        _papers = await _db.getUntaggedPapers();
      } else {
        _papers = await _db.getPapersByTag(_selectedTag!.id!);
      }
    } else if (_searchQuery.isNotEmpty) {
      _papers = await _db.searchPapers(_searchQuery);
      _relatedTags = await _db.getRelatedTags(_searchQuery);
    } else {
      _papers = await _db.getAllPapers();
      _relatedTags = [];
    }
    // Clear selection when loading new papers (optional, but usually good UX)
    _selectedPaperIds.clear();
  }

  Future<void> _loadTagTree() async {
    _tagTree = await _db.getTagTree();
    // Others is handled separately via getUntaggedCount()
  }

  /// Get untagged paper count for "Others" category
  Future<int> getUntaggedCount() async {
    return await _db.getUntaggedPaperCount();
  }

  // ==================== Tag Selection ====================

  /// Select a tag to filter papers
  Future<void> selectTag(Tag? tag) async {
    _selectedTag = tag;
    _searchQuery = '';
    _detectedArxivUrl = null;

    if (tag != null && !tag.isOthers) {
      _lastActiveTagPath = await _db.getTagAncestors(tag.id!);
    } else {
      _lastActiveTagPath = [];
    }

    await _loadPapers();
    notifyListeners();
  }

  /// Clear tag selection (All Papers)
  Future<void> clearSelection() async {
    _selectedTag = null;
    _lastActiveTagPath = []; // Explicit clear for "All Papers"
    _searchQuery = '';
    _detectedArxivUrl = null;
    await _loadPapers();
    notifyListeners();
  }

  // ==================== Search ====================

  /// Update search query
  Future<void> search(String query) async {
    _searchQuery = query.trim();
    _selectedTag = null;
    // DO NOT clear _lastActiveTagPath here to persist context

    // Check for arXiv URL
    if (ArxivService.isArxivUrl(_searchQuery)) {
      _detectedArxivUrl = _searchQuery;
    } else {
      _detectedArxivUrl = null;
    }

    if (_searchQuery.isEmpty) {
      _relatedTags = [];
      _papers = await _db.getAllPapers();
    } else if (_detectedArxivUrl == null) {
      await _loadPapers();
    }

    notifyListeners();
  }

  /// Clear search
  Future<void> clearSearch() async {
    _searchQuery = '';
    _detectedArxivUrl = null;
    await _loadPapers();
    notifyListeners();
  }

  // ==================== Paper Import ====================

  /// Import papers with assigned tags
  Future<List<Paper>> importPapers(
    List<PendingImport> pendingImports,
    bool useFolderTags,
  ) async {
    _isLoading = true;
    notifyListeners();

    final importedPapers = <Paper>[];

    try {
      for (final pending in pendingImports) {
        if (!pending.isSelected) continue;

        // Copy PDF to storage
        final storedPath = await _pdfService.importPdf(pending.sourcePath);

        // Extract title and text
        final title = await _pdfService.extractTitle(storedPath);
        final text = await _pdfService.extractText(storedPath);

        // Create paper record
        final paperId = await _db.insertPaper(
          Paper(title: title, filePath: storedPath, extractedText: text),
        );

        // Create/get tags and associate
        final tagIds = <int>{};

        // Handle folder hierarchy if enabled
        final folderTagNames = <String>{};
        if (useFolderTags && pending.suggestedTags.isNotEmpty) {
          int? parentId;
          for (final tagName in pending.suggestedTags) {
            final tag = await _db.getOrCreateTag(tagName, parentId: parentId);
            parentId = tag.id;
            tagIds.add(tag.id!);
            folderTagNames.add(tagName);
          }
        }

        // Handle other tags (manual/context)
        for (final tagName in pending.assignedTags) {
          // Skip tags that were already handled as part of the folder hierarchy
          if (folderTagNames.contains(tagName)) continue;

          final tag = await _db.getOrCreateTag(tagName);
          tagIds.add(tag.id!);
        }

        await _db.setTagsForPaper(paperId, tagIds.toList());

        // Get the full paper with tags
        final tags = await _db.getTagsForPaper(paperId);
        importedPapers.add(
          Paper(
            id: paperId,
            title: title,
            filePath: storedPath,
            extractedText: text,
            tags: tags,
          ),
        );
      }

      await refresh();
    } catch (e) {
      _error = 'Import failed: $e';
      print(_error);
    }

    _isLoading = false;
    notifyListeners();
    return importedPapers;
  }

  /// Import from arXiv URL
  Future<Paper?> importFromArxiv(String urlOrId, List<String> tagNames) async {
    _isLoading = true;
    notifyListeners();

    try {
      final arxivId = ArxivService.parseArxivId(urlOrId);
      if (arxivId == null) {
        _error = 'Invalid arXiv URL or ID';
        _isLoading = false;
        notifyListeners();
        return null;
      }

      // Fetch metadata
      final metadata = await _arxivService.fetchMetadata(arxivId);
      if (metadata == null) {
        _error = 'Could not fetch arXiv metadata';
        _isLoading = false;
        notifyListeners();
        return null;
      }

      // Download PDF
      final tempPath = await _arxivService.downloadPdf(arxivId);
      if (tempPath == null) {
        _error = 'Could not download PDF';
        _isLoading = false;
        notifyListeners();
        return null;
      }

      // Import PDF
      final storedPath = await _pdfService.importPdf(tempPath);
      final extractedText = await _pdfService.extractText(storedPath);

      // Create paper record
      final paperId = await _db.insertPaper(
        Paper(
          title: metadata.title,
          filePath: storedPath,
          arxivId: arxivId,
          authors: metadata.authors,
          abstract: metadata.abstract,
          extractedText: extractedText,
        ),
      );

      // Create/get tags and associate
      final tagIds = <int>[];
      for (final tagName in tagNames) {
        final tag = await _db.getOrCreateTag(tagName);
        tagIds.add(tag.id!);
      }
      await _db.setTagsForPaper(paperId, tagIds);

      // Clear detected URL
      _detectedArxivUrl = null;
      _searchQuery = '';

      await refresh();

      final tags = await _db.getTagsForPaper(paperId);
      return Paper(
        id: paperId,
        title: metadata.title,
        filePath: storedPath,
        arxivId: arxivId,
        authors: metadata.authors,
        abstract: metadata.abstract,
        extractedText: extractedText,
        tags: tags,
      );
    } catch (e) {
      _error = 'arXiv import failed: $e';
      print(_error);
    }

    _isLoading = false;
    notifyListeners();
    return null;
  }

  /// Scan folder for import preview
  Future<FolderScanResult?> scanFolder(String folderPath) async {
    try {
      return await _folderImportService.scanFolder(folderPath);
    } catch (e) {
      _error = 'Folder scan failed: $e';
      print(_error);
      return null;
    }
  }

  /// Fetch arXiv metadata for preview
  Future<ArxivMetadata?> fetchArxivMetadata(String urlOrId) async {
    final arxivId = ArxivService.parseArxivId(urlOrId);
    if (arxivId == null) return null;
    return await _arxivService.fetchMetadata(arxivId);
  }

  // ==================== Tag Management ====================

  /// Create a new tag
  Future<Tag> createTag(String name, {int? parentId}) async {
    final tag = await _db.getOrCreateTag(name, parentId: parentId);
    await _loadTagTree();
    notifyListeners();
    return tag;
  }

  /// Update paper tags
  Future<void> updatePaperTags(int paperId, List<Tag> tags) async {
    await _db.setTagsForPaper(paperId, tags.map((t) => t.id!).toList());
    await refresh();
  }

  /// Add a tag to selected papers
  Future<void> addTagToSelectedPapers(Tag tag) async {
    if (_selectedPaperIds.isEmpty || tag.id == null) return;

    _isLoading = true;
    notifyListeners();

    try {
      for (final paperId in _selectedPaperIds) {
        await _db.addTagToPaper(paperId, tag.id!);
      }

      // Refresh to show updated tags
      await refresh();
    } catch (e) {
      _error = 'Failed to assign tag: $e';
      print(_error);
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Delete a tag
  Future<void> deleteTag(int tagId) async {
    await _db.deleteTag(tagId);
    if (_selectedTag?.id == tagId) {
      _selectedTag = null;
    }
    await refresh();
  }

  /// Rename a tag
  Future<void> renameTag(int tagId, String newName) async {
    await _db.updateTag(tagId, newName);
    await refresh();
  }

  /// Toggle tag expansion in tree
  void toggleTagExpansion(Tag tag) {
    tag.isExpanded = !tag.isExpanded;
    notifyListeners();
  }

  /// Get all tags (flat list)
  Future<List<Tag>> getAllTags() async {
    return await _db.getAllTags();
  }

  /// Search tags by name
  Future<List<Tag>> searchTags(String query) async {
    return await _db.searchTags(query);
  }

  // ==================== Paper Management ====================

  /// Delete a paper
  Future<void> deletePaper(Paper paper) async {
    await _pdfService.deletePdf(paper.filePath);
    await _db.deletePaper(paper.id!);
    await refresh();
  }

  /// Open paper with system PDF viewer
  Future<bool> openPaper(Paper paper) async {
    return await PdfService.openWithSystemViewer(paper.filePath);
  }

  /// Reveal paper in Finder
  Future<bool> revealPaperInFinder(Paper paper) async {
    return await PdfService.revealInFinder(paper.filePath);
  }

  // ==================== Selection Management ====================

  /// Toggle selection of a paper
  void togglePaperSelection(int paperId) {
    if (_selectedPaperIds.contains(paperId)) {
      _selectedPaperIds.remove(paperId);
    } else {
      _selectedPaperIds.add(paperId);
    }
    notifyListeners();
  }

  /// Select a single paper (clearing others)
  void selectPaper(int paperId) {
    _selectedPaperIds.clear();
    _selectedPaperIds.add(paperId);
    notifyListeners();
  }

  /// Check if papers exist in library
  /// returns a Set of filenames that already exist (based on target path collision)
  Future<Set<String>> checkIfPapersExist(List<PendingImport> files) async {
    if (files.isEmpty) return {};

    final appDocDir = await getApplicationSupportDirectory();
    final predictedPaths =
        <String, String>{}; // predictedPath -> originalFileName

    for (final file in files) {
      // Predict where the file would be saved
      final targetPath = p.join(appDocDir.path, 'papers', file.fileName);
      predictedPaths[targetPath] = file.fileName;
    }

    final existingPaths = await _db.checkPapersExist(
      predictedPaths.keys.toList(),
    );

    // Map existing paths back to filenames
    final existingFilenames = <String>{};
    for (final path in existingPaths) {
      if (predictedPaths.containsKey(path)) {
        existingFilenames.add(predictedPaths[path]!);
      }
    }

    return existingFilenames;
  }

  /// Select all currently visible papers
  void selectAllPapers() {
    _selectedPaperIds.clear();
    _selectedPaperIds.addAll(_papers.map((p) => p.id!));
    notifyListeners();
  }

  /// Deselect all papers
  void deselectAllPapers() {
    _selectedPaperIds.clear();
    notifyListeners();
  }

  /// Check if a paper is selected
  bool isPaperSelected(int paperId) => _selectedPaperIds.contains(paperId);

  /// Delete selected papers
  Future<void> deleteSelectedPapers() async {
    if (_selectedPaperIds.isEmpty) return;

    _isLoading = true;
    notifyListeners();

    // Create a copy of IDs to delete to avoid modification during iteration
    final idsToDelete = _selectedPaperIds.toList();

    try {
      for (final id in idsToDelete) {
        // Find paper to get path for deletion
        // We use firstWhereOrNull logic essentially
        try {
          final paper = _papers.firstWhere((p) => p.id == id);

          // Delete file
          await _pdfService.deletePdf(paper.filePath);

          // Delete from DB (without triggering full refresh yet)
          await _db.deletePaper(id);
        } catch (e) {
          print('Error deleting paper $id: $e');
          // Continue deleting others even if one fails
        }
      }

      // Perform a single refresh at the end
      await refresh();
    } catch (e) {
      _error = 'Failed to delete selected papers: $e';
    }

    _selectedPaperIds.clear(); // Ensure selection is cleared
    _isLoading = false;
    notifyListeners();
  }

  /// Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }
}

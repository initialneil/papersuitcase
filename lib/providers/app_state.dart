import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;

import '../models/settings_enums.dart';
import '../database/database_service.dart';
import '../models/paper.dart';
import '../models/tag.dart';
import '../models/entry.dart';
import '../services/pdf_service.dart';
import '../services/arxiv_service.dart';
import '../services/entry_scanner_service.dart';
import '../services/manifest_service.dart';

class _NavigationState {
  final Tag? tag;
  final int? entryId;
  final String? subfolder;
  final String query;

  _NavigationState(this.tag, this.entryId, this.subfolder, this.query);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _NavigationState &&
          runtimeType == other.runtimeType &&
          tag?.id == other.tag?.id &&
          entryId == other.entryId &&
          subfolder == other.subfolder &&
          query == other.query;

  @override
  int get hashCode => Object.hash(tag?.id, entryId, subfolder, query);
}

/// Main application state provider
class AppState extends ChangeNotifier {
  final DatabaseService _db = DatabaseService();
  final PdfService _pdfService = PdfService();
  final ArxivService _arxivService = ArxivService();
  late final EntryScannerService _scannerService;

  // State
  List<Paper> _papers = [];
  List<Tag> _tagTree = [];
  List<Entry> _entries = [];
  List<Tag> _relatedTags = [];
  Tag? _selectedTag;
  Entry? _selectedEntry;
  String? _selectedSubfolder;
  List<Tag> _lastActiveTagPath = [];
  String _searchQuery = '';

  // Navigation History
  final List<_NavigationState> _history = [];
  int _historyIndex = -1;
  bool _isNavigatingHistory = false;

  bool _isLoading = false;
  String? _error;
  final Set<int> _selectedPaperIds = {};
  Paper? _viewingPaper;
  int _untaggedCount = 0;
  // Open embedded viewer tabs (MRU order)
  final List<Paper> _openTabs = [];

  // Config State
  bool _isConfigMode = false;
  ThemeMode _themeMode = ThemeMode.system;
  PdfReaderType _pdfReaderType = PdfReaderType.embedded;
  String? _customPdfAppPath;
  List<String> _customPdfApps = [];

  // Getters
  List<Paper> get papers => _papers;
  List<Tag> get tagTree => _tagTree;
  List<Entry> get entries => _entries;
  List<Tag> get relatedTags => _relatedTags;
  Tag? get selectedTag => _selectedTag;
  Entry? get selectedEntry => _selectedEntry;
  String? get selectedSubfolder => _selectedSubfolder;
  List<Tag> get lastActiveTagPath => _lastActiveTagPath;
  String get searchQuery => _searchQuery;
  bool get isLoading => _isLoading;
  String? get error => _error;
  Set<int> get selectedPaperIds => _selectedPaperIds;
  Paper? get viewingPaper => _viewingPaper;
  int get untaggedCount => _untaggedCount;
  List<Paper> get openTabs => List.unmodifiable(_openTabs);

  // Config Getters
  bool get isConfigMode => _isConfigMode;
  ThemeMode get themeMode => _themeMode;
  PdfReaderType get pdfReaderType => _pdfReaderType;
  String? get customPdfAppPath => _customPdfAppPath;
  List<String> get customPdfApps => _customPdfApps;

  // Navigation History Getters
  bool get canGoBack => _historyIndex > 0;
  bool get canGoForward => _historyIndex < _history.length - 1;

  /// Initialize the app state
  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    try {
      await DatabaseService.initialize();
      _scannerService = EntryScannerService(_db, _pdfService);
      await _loadSettings();

      // Auto-add test entry on first launch if entries are empty
      _entries = await _db.getAllEntries();
      if (_entries.isEmpty) {
        final testPath = '/Users/neil/Library/CloudStorage/Nutstore-initialneil@gmail.com/Nutstore/Reading/Papers';
        if (await Directory(testPath).exists()) {
          await addEntry(testPath);
        }
      }

      // Push initial state
      _pushHistory();
      await refresh();
    } catch (e) {
      _error = 'Failed to initialize: $e';
      print(_error);
    }

    _isLoading = false;
    notifyListeners();
  }

  void _pushHistory() {
    if (_isNavigatingHistory) return;

    final newState = _NavigationState(
      _selectedTag,
      _selectedEntry?.id,
      _selectedSubfolder,
      _searchQuery,
    );

    // Don't push duplicates if nothing changed
    if (_historyIndex >= 0 && _history[_historyIndex] == newState) {
      return;
    }

    // Truncate future history if we're not at the end
    if (_historyIndex < _history.length - 1) {
      _history.removeRange(_historyIndex + 1, _history.length);
    }

    _history.add(newState);
    _historyIndex = _history.length - 1;
  }

  Future<void> navigateBack() async {
    if (!canGoBack) return;

    _isNavigatingHistory = true;
    _historyIndex--;
    final state = _history[_historyIndex];

    _selectedTag = state.tag;
    _selectedEntry = state.entryId != null
        ? _entries.where((e) => e.id == state.entryId).firstOrNull
        : null;
    _selectedSubfolder = state.subfolder;
    _searchQuery = state.query;

    await _loadPapers();
    _isNavigatingHistory = false;
    notifyListeners();
  }

  Future<void> navigateForward() async {
    if (!canGoForward) return;

    _isNavigatingHistory = true;
    _historyIndex++;
    final state = _history[_historyIndex];

    _selectedTag = state.tag;
    _selectedEntry = state.entryId != null
        ? _entries.where((e) => e.id == state.entryId).firstOrNull
        : null;
    _selectedSubfolder = state.subfolder;
    _searchQuery = state.query;

    await _loadPapers();
    _isNavigatingHistory = false;
    notifyListeners();
  }

  /// Refresh all data
  Future<void> refresh() async {
    await Future.wait([_loadPapers(), _loadTagTree(), _loadEntries()]);
    notifyListeners();
  }

  Future<void> _loadPapers() async {
    if (_searchQuery.isNotEmpty) {
      _papers = await _db.searchPapers(_searchQuery);
      _relatedTags = await _db.getRelatedTags(_searchQuery);
    } else if (_selectedTag != null && _selectedTag!.isUntagged) {
      _papers = await _db.getUntaggedPapers(
        entryId: _selectedEntry?.id,
      );
      _relatedTags = [];
    } else if (_selectedTag != null) {
      _papers = await _db.getPapersByTag(
        _selectedTag!.id!,
        entryId: _selectedEntry?.id,
      );
      _relatedTags = [];
    } else if (_selectedEntry != null && _selectedSubfolder != null) {
      _papers = await _db.getPapersByEntryAndSubfolder(
        _selectedEntry!.id!,
        _selectedSubfolder!,
      );
      _relatedTags = [];
    } else if (_selectedEntry != null) {
      _papers = await _db.getPapersByEntry(_selectedEntry!.id!);
      _relatedTags = [];
    } else {
      _papers = await _db.getAllPapers();
      _relatedTags = [];
    }

    _untaggedCount = await _db.getUntaggedPaperCount();
    // Clear selection when loading new papers
    _selectedPaperIds.clear();
  }

  Future<void> _loadTagTree() async {
    _tagTree = await _db.getTagTree();
  }

  Future<void> _loadEntries() async {
    _entries = await _db.getAllEntries();

    // Update paper counts and subfolder counts
    final counts = await _db.getEntryPaperCounts();
    for (final entry in _entries) {
      entry.paperCount = counts[entry.id] ?? 0;

      // Compute subfolder counts from papers
      if (entry.id != null) {
        final entryPapers = await _db.getPapersByEntry(entry.id!);
        final subCounts = <String, int>{};
        for (final paper in entryPapers) {
          final dir = p.dirname(paper.filePath);
          if (dir != '.' && dir.isNotEmpty) {
            // Get top-level subfolder
            final parts = p.split(dir);
            if (parts.isNotEmpty) {
              final topFolder = parts.first;
              subCounts[topFolder] = (subCounts[topFolder] ?? 0) + 1;
            }
          }
        }
        entry.subfolderCounts = subCounts;
      }
    }
  }

  /// Get untagged paper count
  Future<int> getUntaggedCount() async {
    return await _db.getUntaggedPaperCount();
  }

  // ==================== Entry Management ====================

  /// Add a new entry (folder reference)
  Future<void> addEntry(String folderPath) async {
    try {
      // Check if entry already exists
      final existing = await _db.getEntryByPath(folderPath);
      if (existing != null) {
        _error = 'Entry already exists for this folder';
        notifyListeners();
        return;
      }

      final name = p.basename(folderPath);
      final entry = Entry(path: folderPath, name: name);
      final id = await _db.insertEntry(entry);
      final insertedEntry = Entry(
        id: id,
        path: folderPath,
        name: name,
        addedAt: entry.addedAt,
      );

      // Recover from manifest if available
      await _scannerService.recoverFromManifest(insertedEntry);

      // Scan for papers
      await _scannerService.scanEntry(insertedEntry);

      // Process new papers in background
      await _processNewPapersForEntry(insertedEntry);

      await refresh();
    } catch (e) {
      _error = 'Failed to add entry: $e';
      print(_error);
      notifyListeners();
    }
  }

  /// Remove an entry and all its papers from the database
  Future<void> removeEntry(int entryId) async {
    try {
      // Clear selection if this entry is selected
      if (_selectedEntry?.id == entryId) {
        _selectedEntry = null;
        _selectedSubfolder = null;
      }

      // Close any open tabs for papers in this entry
      final entryPapers = await _db.getPapersByEntry(entryId);
      final entryPaperIds = entryPapers.map((p) => p.id).toSet();
      _openTabs.removeWhere((tab) => entryPaperIds.contains(tab.id));
      if (_viewingPaper != null &&
          entryPaperIds.contains(_viewingPaper!.id)) {
        _viewingPaper = _openTabs.isNotEmpty ? _openTabs.first : null;
      }

      // Delete entry (CASCADE will remove papers)
      await _db.deleteEntry(entryId);

      await refresh();
    } catch (e) {
      _error = 'Failed to remove entry: $e';
      print(_error);
      notifyListeners();
    }
  }

  /// Scan all entries for new, removed, and renamed papers
  Future<void> scanAllEntries() async {
    _isLoading = true;
    notifyListeners();

    try {
      final results = await _scannerService.scanAllEntries();

      // Process new papers in background for each entry, matched by ID
      final entries = await _db.getAllEntries();
      final entriesById = {for (final e in entries) e.id: e};
      for (final result in results) {
        final entry = result.entryId != null ? entriesById[result.entryId] : null;
        if (entry == null) continue;

        if (result.newPapers.isNotEmpty) {
          for (final paper in result.newPapers) {
            await _scannerService.processNewPaper(paper, entry,
                skipBibtex: true);
          }
        }

        // Update accessibility
        entry.isAccessible = result.entryAccessible;
      }

      await refresh();
    } catch (e) {
      _error = 'Failed to scan entries: $e';
      print(_error);
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Refresh a single entry by re-scanning it
  Future<void> refreshEntry(Entry entry) async {
    try {
      final result = await _scannerService.scanEntry(entry);

      // Process new papers
      if (result.newPapers.isNotEmpty) {
        for (final paper in result.newPapers) {
          await _scannerService.processNewPaper(paper, entry);
        }
      }

      entry.isAccessible = result.entryAccessible;

      await refresh();
    } catch (e) {
      _error = 'Failed to refresh entry: $e';
      print(_error);
      notifyListeners();
    }
  }

  /// Process new papers for an entry (extract text, thumbnails, etc.)
  Future<void> _processNewPapersForEntry(Entry entry) async {
    final papers = await _db.getPapersByEntry(entry.id!);
    for (final paper in papers) {
      // Only process papers that haven't been processed yet
      if (paper.extractedText == null || paper.extractedText!.isEmpty) {
        await _scannerService.processNewPaper(paper, entry,
            skipBibtex: true);
      }
    }
  }

  // ==================== Config Methods ====================

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    // Theme
    final themeIndex = prefs.getInt('themeMode');
    if (themeIndex != null &&
        themeIndex >= 0 &&
        themeIndex < ThemeMode.values.length) {
      _themeMode = ThemeMode.values[themeIndex];
    }

    // PDF Reader
    final pdfTypeIndex = prefs.getInt('pdfReaderType');
    if (pdfTypeIndex != null &&
        pdfTypeIndex >= 0 &&
        pdfTypeIndex < PdfReaderType.values.length) {
      _pdfReaderType = PdfReaderType.values[pdfTypeIndex];
    }

    _customPdfAppPath = prefs.getString('customPdfAppPath');
    _customPdfApps = prefs.getStringList('customPdfApps') ?? [];
  }

  void toggleConfigMode() {
    _isConfigMode = !_isConfigMode;
    if (_isConfigMode) {
      _viewingPaper = null; // Exit viewer if entering config
    }
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('themeMode', mode.index);
  }

  Future<void> setPdfReaderType(PdfReaderType type) async {
    _pdfReaderType = type;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('pdfReaderType', type.index);
  }

  Future<void> setCustomPdfAppPath(String path) async {
    _customPdfAppPath = path;
    if (!_customPdfApps.contains(path)) {
      _customPdfApps.add(path);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('customPdfApps', _customPdfApps);
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('customPdfAppPath', path);
  }

  // ==================== Selection (Entry/Tag) ====================

  /// Select a tag to filter papers (co-selection: keeps entry)
  Future<void> selectTag(Tag? tag) async {
    _selectedTag = tag;
    _searchQuery = '';

    if (tag != null && !tag.isUntagged) {
      _lastActiveTagPath = await _db.getTagAncestors(tag.id!);
    } else {
      _lastActiveTagPath = [];
    }

    _pushHistory();
    await _loadPapers();
    notifyListeners();
  }

  /// Select an entry to filter papers (co-selection: keeps tag)
  Future<void> selectEntry(Entry? entry, {String? subfolder}) async {
    _selectedEntry = entry;
    _selectedSubfolder = subfolder;
    _searchQuery = '';

    _pushHistory();
    await _loadPapers();
    notifyListeners();
  }

  /// Select all papers (clear entry, tag, and search)
  Future<void> selectAllPapersView() async {
    _selectedTag = null;
    _selectedEntry = null;
    _selectedSubfolder = null;
    _lastActiveTagPath = [];
    _searchQuery = '';

    _pushHistory();
    await _loadPapers();
    notifyListeners();
  }

  /// Toggle entry expansion in sidebar
  void toggleEntryExpansion(Entry entry) {
    entry.isExpanded = !entry.isExpanded;
    notifyListeners();
  }

  // ==================== Search ====================

  /// Update search query
  Future<void> setSearchQuery(String query) async {
    _searchQuery = query.trim();

    if (_searchQuery.isEmpty) {
      _relatedTags = [];
    }

    _pushHistory();
    await _loadPapers();
    notifyListeners();
  }

  /// Clear search
  Future<void> clearSearch() async {
    _searchQuery = '';
    _pushHistory();
    await _loadPapers();
    notifyListeners();
  }

  /// Clear all selection (Tag/Entry/Search)
  Future<void> clearSelection() async {
    _selectedTag = null;
    _selectedEntry = null;
    _selectedSubfolder = null;
    _lastActiveTagPath = [];
    _searchQuery = '';

    _pushHistory();
    await _loadPapers();
    notifyListeners();
  }

  // ==================== Paper Management ====================

  /// Update paper
  Future<void> updatePaper(Paper paper) async {
    await _db.updatePaper(paper);
    await refresh();
  }

  /// Remove a paper from the DB, manifest, and cache. Never deletes from disk.
  Future<void> removePaper(Paper paper) async {
    try {
      // Find the entry for this paper
      final entry = _entries.where((e) => e.id == paper.entryId).firstOrNull;

      // Remove from DB
      await _db.deletePaper(paper.id!);

      // Remove from manifest and cache if entry exists
      if (entry != null) {
        await ManifestService.removePaperFromManifest(
            entry.path, paper.filePath);
        await ManifestService.deleteThumbnail(entry.path, paper.filePath);
        await ManifestService.deleteTextCache(entry.path, paper.filePath);
      }

      // Close tab if open
      _openTabs.removeWhere((p) => p.id == paper.id);
      if (_viewingPaper?.id == paper.id) {
        _viewingPaper = _openTabs.isNotEmpty ? _openTabs.first : null;
      }

      await refresh();
    } catch (e) {
      _error = 'Failed to remove paper: $e';
      print(_error);
      notifyListeners();
    }
  }

  /// Rebuild title for a paper by extracting from PDF
  Future<void> rebuildPaperTitle(int paperId) async {
    try {
      final paper = _papers.firstWhere((p) => p.id == paperId);

      // Resolve full path via entry
      final entry = _entries.where((e) => e.id == paper.entryId).firstOrNull;
      if (entry == null) return;

      final fullPath = p.join(entry.path, paper.filePath);
      final newTitle = await _pdfService.extractTitle(fullPath);

      if (newTitle.isNotEmpty) {
        await _db.updatePaper(paper.copyWith(title: newTitle));
        await refresh();
      }
    } catch (e) {
      _error = 'Failed to rebuild title: $e';
      print(_error);
      notifyListeners();
    }
  }

  /// Fetch arXiv metadata for preview
  Future<ArxivMetadata?> fetchArxivMetadata(String urlOrId) async {
    final arxivId = ArxivService.parseArxivId(urlOrId);
    if (arxivId == null) return null;
    return await _arxivService.fetchMetadata(arxivId);
  }

  /// Open paper with preferred PDF viewer
  Future<bool> openPaper(Paper paper) async {
    // Resolve full path via entry
    final entry = _entries.where((e) => e.id == paper.entryId).firstOrNull;
    final fullPath =
        entry != null ? p.join(entry.path, paper.filePath) : paper.filePath;

    if (_pdfReaderType == PdfReaderType.embedded) {
      // Maintain MRU open tabs list
      _openTabs.removeWhere((p) => p.id == paper.id);
      _openTabs.insert(0, paper);
      _viewingPaper = paper;
      _isConfigMode = false;
      notifyListeners();
      return true;
    } else if (_pdfReaderType == PdfReaderType.custom &&
        _customPdfAppPath != null) {
      return await PdfService.openWithCustomApp(
        fullPath,
        _customPdfAppPath!,
      );
    } else {
      return await PdfService.openWithSystemViewer(fullPath);
    }
  }

  /// Close embedded viewer
  void closePaperViewer() {
    _viewingPaper = null;
    notifyListeners();
  }

  /// Switch to an already-open tab (or add if missing)
  void switchToTab(Paper paper) {
    _openTabs.removeWhere((p) => p.id == paper.id);
    _openTabs.insert(0, paper);
    _viewingPaper = paper;
    _isConfigMode = false;
    notifyListeners();
  }

  /// Close a specific open tab
  void closeTab(Paper paper) {
    final closingCurrent = _viewingPaper?.id == paper.id;
    _openTabs.removeWhere((p) => p.id == paper.id);
    if (closingCurrent) {
      _viewingPaper = _openTabs.isNotEmpty ? _openTabs.first : null;
    }
    notifyListeners();
  }

  /// Reveal paper in Finder
  Future<bool> revealPaperInFinder(Paper paper) async {
    final entry = _entries.where((e) => e.id == paper.entryId).firstOrNull;
    final fullPath =
        entry != null ? p.join(entry.path, paper.filePath) : paper.filePath;
    return await PdfService.revealInFinder(fullPath);
  }

  /// Resolve full file path for a paper
  String resolveFullPath(Paper paper) {
    final entry = _entries.where((e) => e.id == paper.entryId).firstOrNull;
    return entry != null ? p.join(entry.path, paper.filePath) : paper.filePath;
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

  /// Parse hierarchical tag path (e.g., "A/B/C") and create tags recursively
  /// Returns the ID of the leaf tag
  Future<int> _getOrCreateTagFromPath(String tagPath) async {
    // Split by '/' and create hierarchy
    final parts = tagPath
        .split('/')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      throw ArgumentError('Invalid tag path: $tagPath');
    }

    int? parentId;
    Tag? leafTag;

    for (final tagName in parts) {
      leafTag = await _db.getOrCreateTag(tagName, parentId: parentId);
      parentId = leafTag.id;
    }

    return leafTag!.id!;
  }

  /// Get all tags (flat list)
  Future<List<Tag>> getAllTags() async {
    return await _db.getAllTags();
  }

  /// Search tags by name
  Future<List<Tag>> searchTags(String query) async {
    return await _db.searchTags(query);
  }

  /// Get a paper by title from the database
  Future<Paper?> getPaperByTitle(String title) async {
    return await _db.getPaperByTitle(title);
  }

  /// Get tags for a specific paper
  Future<List<Tag>> getTagsForPaper(int paperId) async {
    return await _db.getTagsForPaper(paperId);
  }

  /// Get tag ancestors (full path from root to tag)
  Future<List<Tag>> getTagAncestors(int tagId) async {
    return await _db.getTagAncestors(tagId);
  }

  /// Set tags for a specific paper
  Future<void> setTagsForPaper(int paperId, List<int> tagIds) async {
    await _db.setTagsForPaper(paperId, tagIds);
    await refresh();
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

  /// Clear all paper selections
  void clearPaperSelection() {
    _selectedPaperIds.clear();
    notifyListeners();
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

  /// Delete selected papers (removes from DB/manifest, not from disk)
  Future<void> deleteSelectedPapers() async {
    if (_selectedPaperIds.isEmpty) return;

    _isLoading = true;
    notifyListeners();

    final idsToDelete = _selectedPaperIds.toList();

    try {
      for (final id in idsToDelete) {
        try {
          final paper = _papers.firstWhere((p) => p.id == id);
          await removePaper(paper);
        } catch (e) {
          print('Error deleting paper $id: $e');
        }
      }

      await refresh();
    } catch (e) {
      _error = 'Failed to delete selected papers: $e';
    }

    _selectedPaperIds.clear();
    _isLoading = false;
    notifyListeners();
  }

  // ==================== BibTeX Management ====================

  /// Update bibtex and bib_status for a paper
  Future<void> updatePaperBibtex(
      int paperId, String bibtex, String bibStatus) async {
    try {
      final paper = _papers.firstWhere((p) => p.id == paperId);
      final updated = paper.copyWith(bibtex: bibtex, bibStatus: bibStatus);
      await _db.updatePaper(updated);
      await _loadPapers();
      notifyListeners();
    } catch (e) {
      _error = 'Failed to update BibTeX: $e';
      print(_error);
      notifyListeners();
    }
  }

  /// Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }
}

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../models/download_task.dart';
import '../models/entry.dart';
import '../models/paper.dart';
import '../models/tag.dart';
import '../providers/app_state.dart';
import '../database/database_service.dart';
import '../services/arxiv_service.dart';
import '../services/pdf_service.dart';

const _kTitleStopWords = {
  'the', 'and', 'for', 'with', 'from', 'that', 'this', 'are',
  'was', 'were', 'been', 'being', 'have', 'has', 'had', 'does',
  'did', 'will', 'would', 'could', 'should', 'may', 'might',
  'shall', 'can', 'need', 'dare', 'ought', 'used', 'using',
  'based', 'via', 'through', 'into', 'over', 'under', 'between',
  'each', 'every', 'both', 'more', 'most', 'other', 'some',
  'such', 'than', 'very', 'just', 'about', 'also', 'only',
};

/// Significant (topical) words of a title: lowercased, longer than 3 chars,
/// stop-words removed, de-duplicated. Used to score title relevance.
Set<String> significantTitleWords(String title) {
  return title
      .toLowerCase()
      .replaceAll(RegExp(r'[^\w\s]'), ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.length > 3 && !_kTitleStopWords.contains(w))
      .toSet();
}

/// Pick the default download folder for a new paper titled [title] by finding
/// the most title-relevant existing paper (in a known entry) and returning its
/// entry + entry-relative subfolder (`''` = entry root).
///
/// Relevance is an **IDF-weighted** overlap of significant title words, not a
/// raw count: a word shared with few library titles (a distinctive keyword like
/// "glove") weighs far more than one shared with many ("high", "performance"),
/// so a folder that merely happens to share generic words doesn't win. A paper
/// must still share at least [minOverlap] words (a floor against noise); among
/// those, the highest weighted score wins. Null when nothing qualifies. Broader
/// than dup-detection on purpose: topically-related, not near-identical.
({int entryId, String subfolder})? suggestFolderByTitle(
    String title, List<Paper> corpus, Set<int> knownEntryIds,
    {int minOverlap = 2}) {
  final qWords = significantTitleWords(title);
  if (qWords.isEmpty) return null;

  // Candidate papers (known entries) with their title word-sets, computed once.
  final candidates = <(Paper, Set<String>)>[];
  for (final paper in corpus) {
    if (!knownEntryIds.contains(paper.entryId)) continue;
    candidates.add((paper, significantTitleWords(paper.title)));
  }
  if (candidates.isEmpty) return null;

  // IDF weight per query word: 1 + ln((N+1)/(df+1)). df = library titles
  // containing it. The `1 +` floor means every shared word counts as overlap;
  // the ln term adds bias so a rare keyword outweighs a common one (and it's
  // never exactly 0, which would collapse on a tiny library).
  final n = candidates.length;
  final weight = <String, double>{};
  for (final w in qWords) {
    var df = 0;
    for (final c in candidates) {
      if (c.$2.contains(w)) df++;
    }
    weight[w] = 1 + math.log((n + 1) / (df + 1));
  }

  Paper? best;
  double bestScore = 0;
  for (final c in candidates) {
    final shared = qWords.where(c.$2.contains).toList();
    if (shared.length < minOverlap) continue;
    var score = 0.0;
    for (final w in shared) {
      score += weight[w]!;
    }
    if (score > bestScore) {
      bestScore = score;
      best = c.$1;
    }
  }
  if (best == null) return null;
  final dir = p.dirname(best.filePath);
  return (
    entryId: best.entryId,
    subfolder: (dir == '.' || dir.isEmpty) ? '' : dir,
  );
}

/// Dialog for downloading papers from arXiv with smart context-aware suggestions
/// and duplicate detection.
class DownloadDialog extends StatefulWidget {
  final String? arxivUrl;
  final String? pdfUrl;
  final Entry? contextEntry;
  final String? contextSubfolder;
  final Tag? contextTag;

  const DownloadDialog({
    super.key,
    this.arxivUrl,
    this.pdfUrl,
    this.contextEntry,
    this.contextSubfolder,
    this.contextTag,
  });

  bool get isDirectPdf => pdfUrl != null && arxivUrl == null;

  static Future<void> show(BuildContext context, {String? arxivUrl, String? pdfUrl}) {
    final appState = context.read<AppState>();
    return showDialog(
      context: context,
      builder: (ctx) => DownloadDialog(
        arxivUrl: arxivUrl,
        pdfUrl: pdfUrl,
        contextEntry: appState.selectedEntry,
        contextSubfolder: appState.selectedSubfolder,
        contextTag: appState.selectedTag,
      ),
    );
  }

  @override
  State<DownloadDialog> createState() => _DownloadDialogState();
}

class _DownloadDialogState extends State<DownloadDialog> {
  final ArxivService _arxivService = ArxivService();
  final TextEditingController _subfolderController = TextEditingController();
  final TextEditingController _titleController = TextEditingController();

  ArxivMetadata? _metadata;
  Entry? _selectedEntry;
  bool _isFetchingMetadata = true;
  bool _isDownloading = false;
  String? _error;
  String? _prefetchedPath;
  String _fetchingStatus = '';
  Timer? _searchDebounce;

  // Tag suggestions
  List<Tag> _suggestedTags = [];
  Set<int> _selectedTagIds = {};
  List<String> _subfolderSuggestions = [];
  bool _isCustomSubfolder = false;
  List<String> _newTagNames = [];
  // True once the user manually picks an Entry/Subfolder, so the fuzzy default
  // (applied after the title/similar search resolves) stops overriding them.
  bool _userPickedLocation = false;

  // Duplicate detection
  List<Paper> _similarPapers = [];
  // Whole library, loaded once, for fuzzy folder-suggestion scoring
  List<Paper> _corpus = [];

  @override
  void initState() {
    super.initState();
    _initContext();
    _loadCorpus();
    _fetchMetadata();
    _titleController.addListener(_onTitleChanged);
  }

  void _initContext() {
    final appState = context.read<AppState>();
    final entries = appState.entries;

    if (widget.contextEntry != null) {
      _selectedEntry = entries
          .where((e) => e.id == widget.contextEntry!.id)
          .firstOrNull;
    }
    _selectedEntry ??= entries.isNotEmpty ? entries.first : null;

    if (widget.contextSubfolder != null) {
      _subfolderController.text = widget.contextSubfolder!;
    }

    if (widget.contextTag != null &&
        !widget.contextTag!.isUntagged &&
        widget.contextTag!.id != null) {
      _selectedTagIds.add(widget.contextTag!.id!);
    }

    _buildSuggestions(appState);
  }

  void _buildSuggestions(AppState appState) {
    final allTags = <Tag>[];
    void collectTags(List<Tag> tags) {
      for (final t in tags) {
        allTags.add(t);
        collectTags(t.children);
      }
    }
    collectTags(appState.tagTree);

    final tagScores = <int, int>{};
    for (final t in allTags) {
      if (t.id == null) continue;
      tagScores[t.id!] = 0;
    }
    if (widget.contextTag != null && widget.contextTag!.id != null) {
      tagScores[widget.contextTag!.id!] = 1000;
    }
    for (final paper in appState.papers) {
      for (final tag in paper.tags) {
        if (tag.id != null) {
          tagScores[tag.id!] = (tagScores[tag.id!] ?? 0) + 10;
        }
      }
    }
    allTags.sort((a, b) {
      final scoreA = tagScores[a.id] ?? 0;
      final scoreB = tagScores[b.id] ?? 0;
      if (scoreA != scoreB) return scoreB.compareTo(scoreA);
      return a.name.compareTo(b.name);
    });
    _suggestedTags = allTags.where((t) => !t.isUntagged).toList();

    final subfolders = <String, int>{};
    if (widget.contextTag != null) {
      // Suggest where most papers under this tag already live. Scope to the
      // currently selected entry so suggestions match the destination root.
      for (final paper in appState.papers) {
        if (_selectedEntry != null && paper.entryId != _selectedEntry!.id) {
          continue;
        }
        final dir = p.dirname(paper.filePath);
        if (dir != '.' && dir.isNotEmpty) {
          subfolders[dir] = (subfolders[dir] ?? 0) + 1;
        }
      }
    } else if (_selectedEntry != null) {
      void walk(List<SubfolderNode> nodes) {
        for (final n in nodes) {
          subfolders[n.relativePath] =
              (subfolders[n.relativePath] ?? 0) + n.totalCount;
          walk(n.children);
        }
      }
      walk(_selectedEntry!.subfolderTree);
    }
    final sorted = subfolders.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    _subfolderSuggestions = sorted.map((e) => e.key).toList();

    if (widget.contextSubfolder != null) {
      if (!_subfolderSuggestions.contains(widget.contextSubfolder)) {
        _subfolderSuggestions.insert(0, widget.contextSubfolder!);
      }
      _subfolderController.text = widget.contextSubfolder!;
    } else if (widget.contextTag != null && _subfolderSuggestions.isNotEmpty) {
      _subfolderController.text = _subfolderSuggestions.first;
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _titleController.removeListener(_onTitleChanged);
    _titleController.dispose();
    _subfolderController.dispose();
    final orphan = _prefetchedPath;
    if (orphan != null) {
      _prefetchedPath = null;
      Future.microtask(() async {
        try {
          await File(orphan).delete();
        } catch (_) {}
      });
    }
    super.dispose();
  }

  void _onTitleChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 500), () async {
      if (!mounted || _isFetchingMetadata) return;
      final title = _titleController.text.trim();
      if (title.isEmpty) return;
      final arxivId =
          widget.isDirectPdf ? '' : (_metadata?.arxivId ?? '');
      final similar = await _findSimilarPapers(title, arxivId);
      if (!mounted) return;
      setState(() {
        _similarPapers = similar;
        _applyFuzzyDefaultLocation(title);
      });
    });
  }

  Future<void> _fetchMetadata() async {
    if (widget.isDirectPdf) {
      await _fetchDirectPdfMetadata();
      return;
    }

    final arxivId = ArxivService.parseArxivId(widget.arxivUrl ?? '');
    if (arxivId == null) {
      setState(() {
        _isFetchingMetadata = false;
        _error = 'Could not parse arXiv ID from URL';
      });
      return;
    }

    try {
      final metadata = await _arxivService.fetchMetadata(arxivId);
      if (!mounted) return;

      if (metadata == null) {
        setState(() {
          _isFetchingMetadata = false;
          _error = 'Could not fetch metadata for arXiv:$arxivId';
        });
      } else {
        // Search for similar existing papers
        final similar = await _findSimilarPapers(metadata.title, arxivId);

        setState(() {
          _metadata = metadata;
          _titleController.text = metadata.title;
          _similarPapers = similar;
          _applyFuzzyDefaultLocation(metadata.title);
          _isFetchingMetadata = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isFetchingMetadata = false;
        _error = 'Error fetching metadata: $e';
      });
    }
  }

  Future<void> _fetchDirectPdfMetadata() async {
    final pdfUrl = widget.pdfUrl!;
    String? prefetched;
    String parsedTitle = '';

    try {
      if (pdfUrl.startsWith('file://')) {
        final localPath = Uri.parse(pdfUrl).toFilePath();
        if (mounted) {
          setState(() => _fetchingStatus = 'Reading PDF…');
        }
        final result = await PdfService().extractInIsolate(localPath);
        parsedTitle = (result['title'] ?? '').trim();
      } else {
        if (mounted) {
          setState(() => _fetchingStatus = 'Downloading PDF…');
        }
        final tempPath = p.join(
          Directory.systemTemp.path,
          'papersuitcase_${DateTime.now().microsecondsSinceEpoch}.pdf',
        );
        final response = await http.get(Uri.parse(pdfUrl));
        if (response.statusCode != 200) {
          throw Exception('HTTP ${response.statusCode}');
        }
        final tempFile = File(tempPath);
        await tempFile.writeAsBytes(response.bodyBytes);
        prefetched = tempPath;
        if (mounted) {
          setState(() => _fetchingStatus = 'Reading PDF title…');
        }
        final result = await PdfService().extractInIsolate(tempPath);
        parsedTitle = (result['title'] ?? '').trim();
      }
    } catch (_) {
      // fall through to filename-derived title
    }

    // Strip the syncfusion fallback that returns basenameWithoutExtension —
    // for prefetched temp files that's our generated junk name.
    if (prefetched != null &&
        parsedTitle == p.basenameWithoutExtension(prefetched)) {
      parsedTitle = '';
    }

    if (parsedTitle.isEmpty) {
      final uri = Uri.parse(pdfUrl);
      var filename =
          uri.pathSegments.isNotEmpty ? uri.pathSegments.last : 'paper';
      if (filename.toLowerCase().endsWith('.pdf')) {
        filename = filename.substring(0, filename.length - 4);
      }
      parsedTitle = filename
          .replaceAll(RegExp(r'[-_]+'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (parsedTitle.isEmpty) parsedTitle = 'Untitled';
    }

    if (!mounted) {
      if (prefetched != null) {
        try {
          await File(prefetched).delete();
        } catch (_) {}
      }
      return;
    }

    final similar = await _findSimilarPapers(parsedTitle, '');
    if (!mounted) {
      if (prefetched != null) {
        try {
          await File(prefetched).delete();
        } catch (_) {}
      }
      return;
    }

    setState(() {
      _metadata = ArxivMetadata(
        arxivId: '',
        title: parsedTitle,
        authors: '',
        abstract: '',
        pdfUrl: pdfUrl,
      );
      _titleController.text = parsedTitle;
      _prefetchedPath = prefetched;
      _similarPapers = similar;
      _applyFuzzyDefaultLocation(parsedTitle);
      _isFetchingMetadata = false;
      _fetchingStatus = '';
    });
  }

  /// Load every paper once so the fuzzy folder-suggestion can score against the
  /// whole library (not just the current view, which may be a filtered list).
  Future<void> _loadCorpus() async {
    try {
      final all = await DatabaseService().getAllPapers();
      if (!mounted) return;
      _corpus = all;
      // Metadata may have arrived before the corpus finished loading — apply now.
      if (_metadata != null) {
        setState(() => _applyFuzzyDefaultLocation(_titleController.text.trim()));
      }
    } catch (_) {}
  }

  /// When the download was launched from a non-folder view (All Papers /
  /// Recent / Read Later / a tag / search — no real entry is the current view),
  /// default the destination to where the most title-relevant existing paper
  /// lives: its entry + subfolder. A real source folder, or a location the user
  /// already picked, is left untouched. Call inside a setState.
  void _applyFuzzyDefaultLocation(String title) {
    if (widget.contextEntry != null || _userPickedLocation || _corpus.isEmpty) {
      return;
    }
    final appState = context.read<AppState>();
    final loc = suggestFolderByTitle(title, _corpus,
        {for (final e in appState.entries) if (e.id != null) e.id!});
    if (loc == null) return;
    final entry =
        appState.entries.where((e) => e.id == loc.entryId).firstOrNull;
    if (entry == null) return;
    _selectedEntry = entry;
    _buildSuggestions(appState); // suggestions for the matched entry
    if (loc.subfolder.isNotEmpty &&
        !_subfolderSuggestions.contains(loc.subfolder)) {
      _subfolderSuggestions.insert(0, loc.subfolder);
    }
    _subfolderController.text = loc.subfolder;
    _isCustomSubfolder = false;
  }

  /// Fuzzy search for existing papers by title keywords and arxiv ID
  Future<List<Paper>> _findSimilarPapers(
      String title, String arxivId) async {
    final db = DatabaseService();
    final results = <Paper>[];
    final seenIds = <int>{};

    // 1. Exact arXiv ID match (skip when no arXiv ID is known)
    if (arxivId.isNotEmpty) {
      try {
        final allPapers = await db.getAllPapers();
        for (final paper in allPapers) {
          if (paper.arxivId == arxivId) {
            results.add(paper);
            if (paper.id != null) seenIds.add(paper.id!);
          }
        }
      } catch (_) {}
    }

    // 1b. Exact title match (case-insensitive) — catches dedup regardless of source.
    try {
      final normalized = title.trim().toLowerCase();
      if (normalized.isNotEmpty) {
        final allPapers = await db.getAllPapers();
        for (final paper in allPapers) {
          if (paper.id != null &&
              !seenIds.contains(paper.id!) &&
              paper.title.trim().toLowerCase() == normalized) {
            results.add(paper);
            seenIds.add(paper.id!);
          }
        }
      }
    } catch (_) {}

    // 2. FTS search with significant words from title
    final words = title
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 3) // skip short words
        .where((w) => !_kTitleStopWords.contains(w))
        .take(5) // top 5 significant words
        .toList();

    if (words.isNotEmpty) {
      try {
        final query = words.join(' ');
        final ftsResults = await db.searchPapers(query);
        for (final paper in ftsResults) {
          if (paper.id != null && !seenIds.contains(paper.id!)) {
            // Score by word overlap
            final paperTitle = paper.title.toLowerCase();
            int matches = 0;
            for (final w in words) {
              if (paperTitle.contains(w)) matches++;
            }
            // Only include if at least 40% word overlap
            if (matches >= (words.length * 0.4).ceil()) {
              results.add(paper);
              seenIds.add(paper.id!);
            }
          }
        }
      } catch (_) {}
    }

    return results.take(5).toList(); // max 5 similar papers
  }

  void _showAddTagDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Tag'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Tag name',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onSubmitted: (value) {
            final name = value.trim();
            if (name.isNotEmpty) {
              setState(() => _newTagNames.add(name));
              Navigator.of(ctx).pop();
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                setState(() => _newTagNames.add(name));
                Navigator.of(ctx).pop();
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _download() async {
    if (_metadata == null || _selectedEntry == null) return;
    final editedTitle = _titleController.text.trim();
    if (editedTitle.isEmpty) {
      setState(() => _error = 'Title cannot be empty');
      return;
    }
    setState(() => _isDownloading = true);

    // Snapshot user-selected state before tearing down the dialog.
    final appState = context.read<AppState>();
    final entry = _selectedEntry!;
    final subfolder = _subfolderController.text.trim();
    final metadata = _metadata!;
    final tagIds = Set<int>.from(_selectedTagIds);
    final newTagNames = List<String>.from(_newTagNames);
    final isDirectPdf = widget.isDirectPdf;
    final prefetched = _prefetchedPath;
    _prefetchedPath = null; // ownership transferred to _runDownload

    final taskId = DateTime.now().microsecondsSinceEpoch.toString();
    appState.enqueueDownload(DownloadTask(id: taskId, title: editedTitle));

    // Close the dialog; the download runs in the background with progress in
    // the sidebar footer. Keep the window visible — hiding it stranded the app
    // (there is no dock-reopen handler that calls windowManager.show()) and
    // read as a crash.
    Navigator.of(context).pop();

    unawaited(_runDownload(
      appState: appState,
      taskId: taskId,
      entry: entry,
      subfolder: subfolder,
      metadata: metadata,
      editedTitle: editedTitle,
      tagIds: tagIds,
      newTagNames: newTagNames,
      isDirectPdf: isDirectPdf,
      prefetchedPath: prefetched,
    ));
  }

  static Future<void> _runDownload({
    required AppState appState,
    required String taskId,
    required Entry entry,
    required String subfolder,
    required ArxivMetadata metadata,
    required String editedTitle,
    required Set<int> tagIds,
    required List<String> newTagNames,
    required bool isDirectPdf,
    String? prefetchedPath,
  }) async {
    try {
      var destDir = entry.path;
      if (subfolder.isNotEmpty) {
        destDir = p.join(destDir, subfolder);
        await Directory(destDir).create(recursive: true);
      }

      final pdfUrl = metadata.pdfUrl;
      final fileName = '${_sanitizeFilenameStatic(editedTitle)}.pdf';
      final filePath = p.join(destDir, fileName);

      if (prefetchedPath != null) {
        // We already downloaded the PDF for title parsing. Just move it.
        final size = await File(prefetchedPath).length();
        appState.updateDownloadProgress(taskId, 0, size);
        await File(prefetchedPath).copy(filePath);
        try {
          await File(prefetchedPath).delete();
        } catch (_) {}
        appState.updateDownloadProgress(taskId, size, size);
      } else if (pdfUrl.startsWith('file://')) {
        final sourcePath = Uri.parse(pdfUrl).toFilePath();
        final bytes = await File(sourcePath).length();
        appState.updateDownloadProgress(taskId, 0, bytes);
        await File(sourcePath).copy(filePath);
        appState.updateDownloadProgress(taskId, bytes, bytes);
      } else {
        final client = http.Client();
        try {
          final request = http.Request('GET', Uri.parse(pdfUrl));
          final response = await client.send(request);
          if (response.statusCode != 200) {
            throw Exception(
                'Download failed with status ${response.statusCode}');
          }
          final total = response.contentLength;
          appState.updateDownloadProgress(taskId, 0, total);

          final sink = File(filePath).openWrite();
          var received = 0;
          try {
            await for (final chunk in response.stream) {
              sink.add(chunk);
              received += chunk.length;
              appState.updateDownloadProgress(taskId, received, total);
            }
          } finally {
            await sink.close();
          }
        } finally {
          client.close();
        }
      }

      final relativePath = p.relative(filePath, from: entry.path);
      final db = DatabaseService();
      final paper = Paper(
        title: editedTitle,
        filePath: relativePath,
        entryId: entry.id!,
        arxivId: isDirectPdf ? null : metadata.arxivId,
        authors: metadata.authors.isNotEmpty ? metadata.authors : null,
        abstract: metadata.abstract.isNotEmpty ? metadata.abstract : null,
        arxivUrl: isDirectPdf
            ? null
            : metadata.pdfUrl
                .replaceAll('/pdf/', '/abs/')
                .replaceAll('.pdf', ''),
      );
      final paperId = await db.insertPaper(paper);

      for (final tagId in tagIds) {
        await db.addTagToPaper(paperId, tagId);
      }
      for (final tagName in newTagNames) {
        final tag = await db.getOrCreateTag(tagName);
        await db.addTagToPaper(paperId, tag.id!);
      }

      await appState.scanAllEntries();
      appState.completeDownload(taskId);
    } catch (e) {
      if (prefetchedPath != null) {
        try {
          await File(prefetchedPath).delete();
        } catch (_) {}
      }
      appState.failDownload(taskId, e.toString());
    }
  }

  static String _sanitizeFilenameStatic(String name) {
    return name
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  @override
  Widget build(BuildContext context) {
    final entries = context.read<AppState>().entries;
    final hasEntries = entries.isNotEmpty;
    final hasSimilar = _similarPapers.isNotEmpty && _metadata != null;

    return AlertDialog(
      title: Text(widget.isDirectPdf
          ? (widget.pdfUrl?.startsWith('file://') == true ? 'Import PDF' : 'Download PDF')
          : 'Download from arXiv'),
      content: SizedBox(
        width: hasSimilar ? 850 : 550,
        child: _isFetchingMetadata
            ? Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Center(child: CircularProgressIndicator()),
                    if (_fetchingStatus.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(_fetchingStatus,
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ],
                ),
              )
            : _error != null && _metadata == null
                ? Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error))
                : hasSimilar
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Left: download form
                          Expanded(
                            flex: 3,
                            child: _buildContent(entries, hasEntries),
                          ),
                          const SizedBox(width: 16),
                          // Divider
                          SizedBox(
                            height: 400,
                            child: VerticalDivider(width: 1),
                          ),
                          const SizedBox(width: 16),
                          // Right: similar papers
                          Expanded(
                            flex: 2,
                            child: _buildSimilarPanel(),
                          ),
                        ],
                      )
                    : _buildContent(entries, hasEntries),
      ),
      actions: [
        TextButton(
          onPressed:
              _isDownloading ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isDownloading || _metadata == null || !hasEntries
              ? null
              : _download,
          child: _isDownloading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_similarPapers.isNotEmpty
                  ? 'Download Anyway'
                  : widget.pdfUrl?.startsWith('file://') == true
                      ? 'Import'
                      : 'Download'),
        ),
      ],
    );
  }

  /// Right panel showing similar/duplicate papers
  Widget _buildSimilarPanel() {
    final colorScheme = Theme.of(context).colorScheme;
    final appState = context.read<AppState>();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                size: 18, color: colorScheme.error),
            const SizedBox(width: 6),
            Text(
              'Similar papers found',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: colorScheme.error,
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ..._similarPapers.map((paper) {
          // Find which entry this paper belongs to
          final entry = appState.entries
              .where((e) => e.id == paper.entryId)
              .firstOrNull;
          final location = entry != null
              ? '${entry.name}/${paper.filePath}'
              : paper.filePath;

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colorScheme.errorContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: colorScheme.error.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Match indicator
                if (paper.arxivId == _metadata?.arxivId &&
                    paper.arxivId != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: colorScheme.error,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'EXACT MATCH (same arXiv ID)',
                      style: TextStyle(
                        color: colorScheme.onError,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                else
                  Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: colorScheme.tertiary,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'SIMILAR TITLE',
                      style: TextStyle(
                        color: colorScheme.onTertiary,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                Text(
                  paper.title,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  location,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.5),
                      fontSize: 10),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (paper.tags.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 4,
                    children: paper.tags.take(3).map((t) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(t.name,
                            style: TextStyle(
                                fontSize: 9,
                                color: colorScheme.onSurfaceVariant)),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildContent(List<Entry> entries, bool hasEntries) {
    final meta = _metadata!;
    final abstractPreview = meta.abstract.length > 200
        ? '${meta.abstract.substring(0, 200)}...'
        : meta.abstract;
    final colorScheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _titleController,
            enabled: !_isDownloading,
            minLines: 1,
            maxLines: 3,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              isDense: true,
              labelText: 'Title',
              border: const OutlineInputBorder(),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            ),
          ),
          if (meta.authors.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              meta.authors,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.6)),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (abstractPreview.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              abstractPreview,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.5)),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: TextStyle(color: colorScheme.error, fontSize: 12)),
          ],
          const Divider(height: 24),
          if (!hasEntries) ...[
            Text('Add an entry folder first',
                style: TextStyle(color: colorScheme.error)),
          ] else ...[
            // Entry picker
            Row(
              children: [
                Text('Entry:',
                    style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButton<Entry>(
                    value: _selectedEntry,
                    isExpanded: true,
                    isDense: true,
                    items: entries.map((entry) {
                      return DropdownMenuItem(
                          value: entry, child: Text(entry.name));
                    }).toList(),
                    onChanged: _isDownloading
                        ? null
                        : (entry) {
                            setState(() {
                              _userPickedLocation = true;
                              _selectedEntry = entry;
                              _buildSuggestions(context.read<AppState>());
                            });
                          },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Subfolder dropdown
            Row(
              children: [
                Text('Subfolder:',
                    style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(width: 12),
                Expanded(
                  child: _isCustomSubfolder
                      ? TextField(
                          controller: _subfolderController,
                          autofocus: true,
                          decoration: InputDecoration(
                            hintText: 'Type subfolder name...',
                            border: const OutlineInputBorder(),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.close, size: 16),
                              onPressed: () => setState(() {
                                _isCustomSubfolder = false;
                                _subfolderController.clear();
                              }),
                            ),
                          ),
                          enabled: !_isDownloading,
                          style: Theme.of(context).textTheme.bodyMedium,
                        )
                      : DropdownButton<String>(
                          value: _subfolderSuggestions
                                  .contains(_subfolderController.text)
                              ? _subfolderController.text
                              : '',
                          isExpanded: true,
                          isDense: true,
                          items: [
                            const DropdownMenuItem(
                              value: '',
                              child: Text('(root)',
                                  style:
                                      TextStyle(fontStyle: FontStyle.italic)),
                            ),
                            ..._subfolderSuggestions.map((sf) {
                              return DropdownMenuItem(
                                  value: sf, child: Text(sf));
                            }),
                            const DropdownMenuItem(
                              value: '__custom__',
                              child: Row(
                                children: [
                                  Icon(Icons.edit, size: 14),
                                  SizedBox(width: 6),
                                  Text('New subfolder...'),
                                ],
                              ),
                            ),
                          ],
                          onChanged: _isDownloading
                              ? null
                              : (value) {
                                  _userPickedLocation = true;
                                  if (value == '__custom__') {
                                    setState(() {
                                      _isCustomSubfolder = true;
                                      _subfolderController.clear();
                                    });
                                  } else {
                                    setState(() {
                                      _subfolderController.text = value ?? '';
                                    });
                                  }
                                },
                        ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Tags
            Row(
              children: [
                Text('Tags:',
                    style: Theme.of(context).textTheme.labelLarge),
                const Spacer(),
                SizedBox(
                  height: 28,
                  child: TextButton.icon(
                    onPressed: _isDownloading ? null : _showAddTagDialog,
                    icon: const Icon(Icons.add, size: 14),
                    label:
                        const Text('New tag', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Selected tags
            if (_newTagNames.isNotEmpty || _selectedTagIds.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    ..._suggestedTags
                        .where((t) =>
                            t.id != null && _selectedTagIds.contains(t.id))
                        .map((tag) => Chip(
                              label: Text(tag.name,
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: colorScheme.onPrimary,
                                      fontWeight: FontWeight.w500)),
                              deleteIcon: Icon(Icons.close,
                                  size: 14, color: colorScheme.onPrimary),
                              backgroundColor: colorScheme.primary,
                              visualDensity: VisualDensity.compact,
                              onDeleted: _isDownloading
                                  ? null
                                  : () => setState(
                                      () => _selectedTagIds.remove(tag.id!)),
                            )),
                    ..._newTagNames.map((name) => Chip(
                          label: Text(name,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: colorScheme.onTertiary,
                                  fontWeight: FontWeight.w500)),
                          deleteIcon: Icon(Icons.close,
                              size: 14, color: colorScheme.onTertiary),
                          backgroundColor: colorScheme.tertiary,
                          visualDensity: VisualDensity.compact,
                          onDeleted: _isDownloading
                              ? null
                              : () => setState(
                                  () => _newTagNames.remove(name)),
                        )),
                  ],
                ),
              ),

            // Available tags
            if (_suggestedTags.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 100),
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: _suggestedTags
                        .where((t) =>
                            t.id != null && !_selectedTagIds.contains(t.id))
                        .take(20)
                        .map((tag) {
                      return ActionChip(
                        label: Text(tag.name,
                            style: const TextStyle(fontSize: 11)),
                        avatar: const Icon(Icons.add, size: 12),
                        visualDensity: VisualDensity.compact,
                        onPressed: _isDownloading
                            ? null
                            : () =>
                                setState(() => _selectedTagIds.add(tag.id!)),
                      );
                    }).toList(),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

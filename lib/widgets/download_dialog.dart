import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../models/entry.dart';
import '../models/paper.dart';
import '../models/tag.dart';
import '../providers/app_state.dart';
import '../database/database_service.dart';
import '../services/arxiv_service.dart';

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

  ArxivMetadata? _metadata;
  Entry? _selectedEntry;
  bool _isFetchingMetadata = true;
  bool _isDownloading = false;
  String? _error;

  // Tag suggestions
  List<Tag> _suggestedTags = [];
  Set<int> _selectedTagIds = {};
  List<String> _subfolderSuggestions = [];
  bool _isCustomSubfolder = false;
  List<String> _newTagNames = [];

  // Duplicate detection
  List<Paper> _similarPapers = [];

  @override
  void initState() {
    super.initState();
    _initContext();
    _fetchMetadata();
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
      for (final paper in appState.papers) {
        final dir = p.dirname(paper.filePath);
        if (dir != '.' && dir.isNotEmpty) {
          subfolders[dir] = (subfolders[dir] ?? 0) + 1;
        }
      }
    }
    if (_selectedEntry != null) {
      for (final key in _selectedEntry!.subfolderCounts.keys) {
        subfolders[key] = (subfolders[key] ?? 0) +
            _selectedEntry!.subfolderCounts[key]!;
      }
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
    _subfolderController.dispose();
    super.dispose();
  }

  Future<void> _fetchMetadata() async {
    if (widget.isDirectPdf) {
      // Direct PDF URL — derive title from filename
      final uri = Uri.parse(widget.pdfUrl!);
      var filename = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : 'paper';
      if (filename.toLowerCase().endsWith('.pdf')) {
        filename = filename.substring(0, filename.length - 4);
      }
      // Convert hyphens/underscores to spaces for a readable title
      final title = filename
          .replaceAll(RegExp(r'[-_]+'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      setState(() {
        _metadata = ArxivMetadata(
          arxivId: '',
          title: title.isNotEmpty ? title : 'Untitled',
          authors: '',
          abstract: '',
          pdfUrl: widget.pdfUrl!,
        );
        _isFetchingMetadata = false;
      });
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
          _similarPapers = similar;
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

  /// Fuzzy search for existing papers by title keywords and arxiv ID
  Future<List<Paper>> _findSimilarPapers(
      String title, String arxivId) async {
    final db = DatabaseService();
    final results = <Paper>[];
    final seenIds = <int>{};

    // 1. Exact arXiv ID match
    try {
      final allPapers = await db.getAllPapers();
      for (final paper in allPapers) {
        if (paper.arxivId == arxivId) {
          results.add(paper);
          if (paper.id != null) seenIds.add(paper.id!);
        }
      }
    } catch (_) {}

    // 2. FTS search with significant words from title
    final words = title
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 3) // skip short words
        .where((w) => !_stopWords.contains(w))
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

  static const _stopWords = {
    'the', 'and', 'for', 'with', 'from', 'that', 'this', 'are',
    'was', 'were', 'been', 'being', 'have', 'has', 'had', 'does',
    'did', 'will', 'would', 'could', 'should', 'may', 'might',
    'shall', 'can', 'need', 'dare', 'ought', 'used', 'using',
    'based', 'via', 'through', 'into', 'over', 'under', 'between',
    'each', 'every', 'both', 'more', 'most', 'other', 'some',
    'such', 'than', 'very', 'just', 'about', 'also', 'only',
  };

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

  String _sanitizeFilename(String name) {
    return name
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Future<void> _download() async {
    if (_metadata == null || _selectedEntry == null) return;
    setState(() => _isDownloading = true);

    try {
      var destDir = _selectedEntry!.path;
      final subfolder = _subfolderController.text.trim();
      if (subfolder.isNotEmpty) {
        destDir = p.join(destDir, subfolder);
        await Directory(destDir).create(recursive: true);
      }

      final pdfUrl = _metadata!.pdfUrl;
      final sanitizedTitle = _sanitizeFilename(_metadata!.title);
      final fileName = '$sanitizedTitle.pdf';
      final filePath = p.join(destDir, fileName);

      if (pdfUrl.startsWith('file://')) {
        // Local file — copy it
        final sourcePath = Uri.parse(pdfUrl).toFilePath();
        await File(sourcePath).copy(filePath);
      } else {
        // Remote URL — download it
        final response = await http.get(Uri.parse(pdfUrl));
        if (response.statusCode != 200) {
          throw Exception('Download failed with status ${response.statusCode}');
        }
        await File(filePath).writeAsBytes(response.bodyBytes);
      }

      final relativePath = p.relative(filePath, from: _selectedEntry!.path);

      if (!mounted) return;
      final db = DatabaseService();
      final paper = Paper(
        title: _metadata!.title,
        filePath: relativePath,
        entryId: _selectedEntry!.id!,
        arxivId: widget.isDirectPdf ? null : _metadata!.arxivId,
        authors: _metadata!.authors.isNotEmpty ? _metadata!.authors : null,
        abstract: _metadata!.abstract.isNotEmpty ? _metadata!.abstract : null,
        arxivUrl: widget.isDirectPdf
            ? null
            : _metadata!.pdfUrl
                .replaceAll('/pdf/', '/abs/')
                .replaceAll('.pdf', ''),
      );
      final paperId = await db.insertPaper(paper);

      for (final tagId in _selectedTagIds) {
        await db.addTagToPaper(paperId, tagId);
      }
      for (final tagName in _newTagNames) {
        final tag = await db.getOrCreateTag(tagName);
        await db.addTagToPaper(paperId, tag.id!);
      }

      if (!mounted) return;
      final appState = context.read<AppState>();
      await appState.scanAllEntries();

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Downloaded: ${_metadata!.title}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isDownloading = false;
        _error = 'Download failed: $e';
      });
    }
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
            ? const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
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
          Text(
            meta.title,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            meta.authors,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.6)),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          if (abstractPreview.isNotEmpty)
            Text(
              abstractPreview,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.5)),
            ),
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

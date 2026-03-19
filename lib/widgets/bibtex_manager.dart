import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_selector/file_selector.dart';
import 'dart:io';

import '../models/paper.dart';
import '../providers/app_state.dart';
import '../services/bibtex_service.dart';

/// Full-screen two-panel BibTeX manager.
/// Left: paper list with status. Right: editor for selected paper.
class BibtexManager extends StatefulWidget {
  final List<Paper> papers;
  final String title; // e.g. tag name

  const BibtexManager({
    super.key,
    required this.papers,
    required this.title,
  });

  static Future<void> show(BuildContext context,
      {required List<Paper> papers, required String title}) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => BibtexManager(papers: papers, title: title),
    );
  }

  @override
  State<BibtexManager> createState() => _BibtexManagerState();
}

class _BibtexManagerState extends State<BibtexManager> {
  Paper? _selectedPaper;
  List<Paper> _papers = [];

  // Search state
  final TextEditingController _searchController = TextEditingController();
  List<BibResult> _searchResults = [];
  bool _isSearching = false;
  String _searchSource = 'DBLP';

  // Editor state
  final TextEditingController _editorController = TextEditingController();
  bool _editorDirty = false;

  // Batch state
  bool _isBatchSearching = false;
  int _batchProgress = 0;
  int _batchTotal = 0;

  // Fetching bibtex for a specific result
  int? _fetchingResultIndex;

  @override
  void initState() {
    super.initState();
    _papers = List.from(widget.papers);
    if (_papers.isNotEmpty) {
      _selectPaper(_papers.first);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _editorController.dispose();
    super.dispose();
  }

  int get _hasBibCount =>
      _papers.where((p) => p.bibtex != null && p.bibtex!.isNotEmpty).length;
  int get _missingCount => _papers.length - _hasBibCount;

  void _selectPaper(Paper paper) {
    // Save current editor if dirty
    if (_editorDirty && _selectedPaper != null) {
      _saveCurrentEditor();
    }

    setState(() {
      _selectedPaper = paper;
      _editorController.text = paper.bibtex ?? '';
      _editorDirty = false;
      _searchResults = [];
      _searchController.text = paper.title;
    });
  }

  Future<void> _saveCurrentEditor() async {
    if (_selectedPaper == null) return;
    final text = _editorController.text.trim();
    final bibtex = text.isEmpty ? null : text;
    final status =
        bibtex != null ? 'verified' : 'none'; // Manual edit = verified

    await context
        .read<AppState>()
        .updatePaperBibtex(_selectedPaper!.id!, bibtex ?? '', status);

    // Update local list
    final idx = _papers.indexWhere((p) => p.id == _selectedPaper!.id);
    if (idx >= 0) {
      _papers[idx] = _papers[idx].copyWith(bibtex: bibtex, bibStatus: status);
      _selectedPaper = _papers[idx];
    }
    _editorDirty = false;
  }

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isSearching = true;
      _searchResults = [];
    });

    try {
      final results = await BibtexService.search(query, _searchSource);
      if (mounted) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSearching = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Search failed: $e')),
        );
      }
    }
  }

  Future<void> _useResult(BibResult result, int index) async {
    setState(() => _fetchingResultIndex = index);
    try {
      final bibtex = await BibtexService.fetchBibtexFor(result);
      if (mounted) {
        setState(() {
          _editorController.text = bibtex;
          _editorDirty = true;
          _fetchingResultIndex = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _fetchingResultIndex = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to fetch BibTeX: $e')),
        );
      }
    }
  }

  Future<void> _batchSearch() async {
    final missing =
        _papers.where((p) => p.bibtex == null || p.bibtex!.isEmpty).toList();
    if (missing.isEmpty) return;

    setState(() {
      _isBatchSearching = true;
      _batchProgress = 0;
      _batchTotal = missing.length;
    });

    final appState = context.read<AppState>();
    int found = 0;

    for (int i = 0; i < missing.length; i++) {
      if (!mounted || !_isBatchSearching) break;

      final paper = missing[i];
      try {
        final bib = await BibtexService.autoFetch(paper);
        if (bib != null && paper.id != null) {
          await appState.updatePaperBibtex(paper.id!, bib, 'auto_fetched');
          final idx = _papers.indexWhere((p) => p.id == paper.id);
          if (idx >= 0) {
            _papers[idx] =
                _papers[idx].copyWith(bibtex: bib, bibStatus: 'auto_fetched');
          }
          found++;
        }
      } catch (_) {}

      setState(() => _batchProgress = i + 1);
      // Rate limit
      await Future.delayed(const Duration(milliseconds: 500));
    }

    if (mounted) {
      setState(() => _isBatchSearching = false);
      // Refresh selected paper if it was updated
      if (_selectedPaper != null) {
        final updated =
            _papers.where((p) => p.id == _selectedPaper!.id).firstOrNull;
        if (updated != null) {
          _selectedPaper = updated;
          _editorController.text = updated.bibtex ?? '';
          _editorDirty = false;
        }
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Found BibTeX for $found of ${missing.length} papers')),
      );
    }
  }

  Future<void> _exportAll() async {
    final combined = BibtexService.exportBibtex(_papers);
    if (combined.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No BibTeX to export')),
      );
      return;
    }

    final location = await getSaveLocation(
      suggestedName: 'references.bib',
      acceptedTypeGroups: [
        const XTypeGroup(label: 'BibTeX', extensions: ['bib']),
      ],
    );
    if (location == null) return;

    await File(location.path).writeAsString(combined);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Exported to ${location.path}')),
      );
    }
  }

  void _copyAll() {
    final combined = BibtexService.exportBibtex(_papers);
    if (combined.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No BibTeX to copy')),
      );
      return;
    }
    Clipboard.setData(ClipboardData(text: combined));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('All BibTeX copied to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return Dialog(
      insetPadding: const EdgeInsets.all(32),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: 1000,
          height: 650,
          child: Column(
            children: [
              // Top bar
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  border: Border(
                    bottom: BorderSide(
                        color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.menu_book_rounded,
                        size: 20, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      'BibTeX Manager — ${widget.title}',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${_papers.length} papers · $_hasBibCount have BibTeX · $_missingCount missing',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                    const Spacer(),
                    // Batch actions
                    if (_isBatchSearching) ...[
                      SizedBox(
                        width: 100,
                        child: LinearProgressIndicator(
                          value: _batchTotal > 0
                              ? _batchProgress / _batchTotal
                              : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('$_batchProgress/$_batchTotal',
                          style: theme.textTheme.bodySmall),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () =>
                            setState(() => _isBatchSearching = false),
                        child: const Text('Stop'),
                      ),
                    ] else ...[
                      TextButton.icon(
                        onPressed: _missingCount > 0 ? _batchSearch : null,
                        icon: const Icon(Icons.cloud_download_outlined,
                            size: 16),
                        label: const Text('Auto-fetch missing'),
                      ),
                      const SizedBox(width: 4),
                      TextButton.icon(
                        onPressed: _hasBibCount > 0 ? _copyAll : null,
                        icon: const Icon(Icons.copy_all, size: 16),
                        label: const Text('Copy all'),
                      ),
                      const SizedBox(width: 4),
                      TextButton.icon(
                        onPressed: _hasBibCount > 0 ? _exportAll : null,
                        icon: const Icon(Icons.save_alt, size: 16),
                        label: const Text('Export .bib'),
                      ),
                    ],
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () async {
                        if (_editorDirty) await _saveCurrentEditor();
                        if (mounted) Navigator.of(context).pop();
                      },
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),

              // Two-panel body
              Expanded(
                child: Row(
                  children: [
                    // Left panel: paper list
                    SizedBox(
                      width: 320,
                      child: _buildPaperList(colorScheme, theme),
                    ),

                    // Divider
                    VerticalDivider(
                        width: 1,
                        color:
                            colorScheme.outlineVariant.withValues(alpha: 0.3)),

                    // Right panel: editor
                    Expanded(
                      child: _selectedPaper != null
                          ? _buildEditorPanel(colorScheme, theme)
                          : Center(
                              child: Text('Select a paper',
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                      color: colorScheme.onSurfaceVariant)),
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPaperList(ColorScheme colorScheme, ThemeData theme) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: _papers.length,
      itemBuilder: (context, index) {
        final paper = _papers[index];
        final isSelected = paper.id == _selectedPaper?.id;
        final hasBib = paper.bibtex != null && paper.bibtex!.isNotEmpty;
        final citKey = _extractCitationKey(paper.bibtex);

        return InkWell(
          onTap: () => _selectPaper(paper),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? colorScheme.primaryContainer.withValues(alpha: 0.5)
                  : null,
              border: Border(
                left: BorderSide(
                  color: isSelected ? colorScheme.primary : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
            child: Row(
              children: [
                // Status icon
                _buildStatusIcon(paper),
                const SizedBox(width: 8),
                // Title + citation key
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        paper.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                      if (citKey != null)
                        Text(
                          citKey,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontFamily: 'monospace',
                            color: colorScheme.primary,
                            fontSize: 10,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEditorPanel(ColorScheme colorScheme, ThemeData theme) {
    final paper = _selectedPaper!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Paper info header
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            border: Border(
              bottom: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(paper.title,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
              if (paper.authors != null && paper.authors!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(paper.authors!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: colorScheme.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ],
          ),
        ),

        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              // Source selector
              SizedBox(
                width: 100,
                child: DropdownButton<String>(
                  value: _searchSource,
                  isExpanded: true,
                  isDense: true,
                  underline: const SizedBox(),
                  items: BibtexService.bibSources.map((s) {
                    return DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 13)));
                  }).toList(),
                  onChanged: (v) => setState(() => _searchSource = v!),
                ),
              ),
              const SizedBox(width: 8),
              // Search field
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search by title, author, or keywords...',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                    suffixIcon: _isSearching
                        ? const Padding(
                            padding: EdgeInsets.all(8),
                            child: SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2)),
                          )
                        : IconButton(
                            icon: const Icon(Icons.search, size: 18),
                            onPressed: _search,
                          ),
                  ),
                  style: const TextStyle(fontSize: 13),
                  onSubmitted: (_) => _search(),
                ),
              ),
            ],
          ),
        ),

        // Search results
        if (_searchResults.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxHeight: 160),
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            decoration: BoxDecoration(
              border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: _searchResults.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final result = _searchResults[index];
                final isFetching = _fetchingResultIndex == index;

                return InkWell(
                  onTap: isFetching ? null : () => _useResult(result, index),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(result.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.w500)),
                              Text(
                                '${result.authors} · ${result.venue} ${result.year} · ${result.source}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (isFetching)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          TextButton(
                            onPressed: () => _useResult(result, index),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8),
                              visualDensity: VisualDensity.compact,
                            ),
                            child: const Text('Use',
                                style: TextStyle(fontSize: 12)),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

        const SizedBox(height: 4),

        // BibTeX editor
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('BibTeX',
                        style: theme.textTheme.labelLarge
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const Spacer(),
                    if (_editorDirty)
                      TextButton.icon(
                        onPressed: () async {
                          await _saveCurrentEditor();
                          if (mounted) {
                            setState(() {});
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('BibTeX saved'),
                                  duration: Duration(seconds: 1)),
                            );
                          }
                        },
                        icon: const Icon(Icons.save, size: 16),
                        label: const Text('Save'),
                        style: TextButton.styleFrom(
                          foregroundColor: colorScheme.primary,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    if (paper.bibtex != null && paper.bibtex!.isNotEmpty) ...[
                      IconButton(
                        onPressed: () {
                          Clipboard.setData(
                              ClipboardData(text: _editorController.text));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Copied'),
                                duration: Duration(seconds: 1)),
                          );
                        },
                        icon: const Icon(Icons.copy, size: 16),
                        tooltip: 'Copy BibTeX',
                        visualDensity: VisualDensity.compact,
                      ),
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _editorController.clear();
                            _editorDirty = true;
                          });
                        },
                        icon: const Icon(Icons.delete_outline, size: 16),
                        tooltip: 'Clear BibTeX',
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: TextField(
                    controller: _editorController,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      height: 1.5,
                      color: colorScheme.onSurface,
                    ),
                    decoration: InputDecoration(
                      hintText:
                          'Paste BibTeX here, or search above to find it...',
                      hintStyle: TextStyle(
                          color:
                              colorScheme.onSurface.withValues(alpha: 0.3)),
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.all(10),
                    ),
                    onChanged: (_) {
                      if (!_editorDirty) setState(() => _editorDirty = true);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusIcon(Paper paper) {
    if (paper.bibtex != null && paper.bibtex!.isNotEmpty) {
      if (paper.bibStatus == 'verified') {
        return const Tooltip(
          message: 'Verified',
          child: Icon(Icons.check_circle, color: Colors.green, size: 16),
        );
      }
      return const Tooltip(
        message: 'Auto-fetched (unverified)',
        child:
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 16),
      );
    }
    return const Tooltip(
      message: 'Missing',
      child: Icon(Icons.cancel, color: Colors.red, size: 16),
    );
  }

  String? _extractCitationKey(String? bibtex) {
    if (bibtex == null || bibtex.isEmpty) return null;
    final match = RegExp(r'@\w+\{([^,]+),').firstMatch(bibtex);
    return match?.group(1);
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/import_data.dart';
import '../models/tag.dart';
import '../providers/app_state.dart';

/// Universal import confirmation dialog
class ImportDialog extends StatefulWidget {
  final ImportType importType;
  final List<PendingImport>? pendingFiles;
  final FolderScanResult? folderScanResult;
  final ArxivMetadata? arxivMetadata;
  final Tag? currentTag;

  const ImportDialog({
    super.key,
    required this.importType,
    this.pendingFiles,
    this.folderScanResult,
    this.arxivMetadata,
    this.currentTag,
  });

  /// Show dialog for PDF file import
  static Future<bool?> showForFiles(
    BuildContext context,
    List<String> filePaths, {
    Tag? currentTag,
  }) async {
    final pendingFiles = filePaths
        .map(
          (path) => PendingImport(
            sourcePath: path,
            fileName: path.split('/').last,
            assignedTags: currentTag != null && !currentTag.isOthers
                ? [currentTag.name]
                : [],
          ),
        )
        .toList();

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ImportDialog(
        importType: filePaths.length == 1
            ? ImportType.singleFile
            : ImportType.multipleFiles,
        pendingFiles: pendingFiles,
        currentTag: currentTag,
      ),
    );
  }

  /// Show dialog for folder import
  static Future<bool?> showForFolder(
    BuildContext context,
    FolderScanResult scanResult, {
    Tag? currentTag,
  }) async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ImportDialog(
        importType: ImportType.folder,
        folderScanResult: scanResult,
        currentTag: currentTag,
      ),
    );
  }

  /// Show dialog for arXiv import
  static Future<bool?> showForArxiv(
    BuildContext context,
    ArxivMetadata metadata, {
    Tag? currentTag,
  }) async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ImportDialog(
        importType: ImportType.arxiv,
        arxivMetadata: metadata,
        currentTag: currentTag,
      ),
    );
  }

  @override
  State<ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<ImportDialog> {
  late List<PendingImport> _files;
  List<PendingImport> _existingFiles = [];
  bool _useFolderTags = true;
  bool _applyCurrentTag = false;
  final Set<String> _additionalTags = {};
  final TextEditingController _tagController = TextEditingController();
  List<Tag> _allTags = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _initializeFiles();
    _loadTags();
    // Defer check to next frame to allow context access if needed, though read works
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkDuplicates());
  }

  void _initializeFiles() {
    if (widget.importType == ImportType.folder &&
        widget.folderScanResult != null) {
      _files = List.from(widget.folderScanResult!.files);
    } else if (widget.pendingFiles != null) {
      _files = List.from(widget.pendingFiles!);
    } else {
      _files = [];
    }

    // Set applyCurrentTag if we have a current tag that's not "Others"
    if (widget.currentTag != null && !widget.currentTag!.isOthers) {
      _applyCurrentTag = true;
    }
  }

  Future<void> _checkDuplicates() async {
    final appState = context.read<AppState>();
    // Check all files initially
    final existingNames = await appState.checkIfPapersExist(_files);

    if (existingNames.isNotEmpty) {
      setState(() {
        final newFiles = <PendingImport>[];
        _existingFiles = <PendingImport>[];

        for (final file in _files) {
          if (existingNames.contains(file.fileName)) {
            _existingFiles.add(file);
            file.isSelected = false; // Default unselected for existing
          } else {
            newFiles.add(file);
          }
        }
        _files = newFiles;
      });
    }
  }

  Future<void> _loadTags() async {
    final appState = context.read<AppState>();
    _allTags = await appState.getAllTags();
    setState(() {});
  }

  void _addTag(String tagName) {
    if (tagName.trim().isEmpty) return;

    setState(() {
      _additionalTags.add(tagName.trim());
      _tagController.clear();
    });
  }

  void _removeTag(String tagName) {
    setState(() {
      _additionalTags.remove(tagName);
    });
  }

  int get _selectedFileCount =>
      _files.where((f) => f.isSelected).length +
      _existingFiles.where((f) => f.isSelected).length;

  List<String> _getTagsForFile(PendingImport file) {
    final tags = <String>{};

    // Add folder tags if enabled
    if (_useFolderTags && widget.importType == ImportType.folder) {
      tags.addAll(file.suggestedTags);
    }

    // Add current tag if enabled
    if (_applyCurrentTag &&
        widget.currentTag != null &&
        !widget.currentTag!.isOthers) {
      tags.add(widget.currentTag!.name);
    }

    // Add additional tags
    tags.addAll(_additionalTags);

    return tags.toList();
  }

  Future<void> _import() async {
    setState(() => _isLoading = true);

    final appState = context.read<AppState>();

    try {
      if (widget.importType == ImportType.arxiv &&
          widget.arxivMetadata != null) {
        // arXiv import
        final tags = <String>[];
        if (_applyCurrentTag &&
            widget.currentTag != null &&
            !widget.currentTag!.isOthers) {
          tags.add(widget.currentTag!.name);
        }
        tags.addAll(_additionalTags);

        await appState.importFromArxiv(widget.arxivMetadata!.arxivId, tags);
      } else {
        // File/folder import
        // Combine both lists for import
        final allFiles = [..._files, ..._existingFiles];
        for (final file in allFiles) {
          if (file.isSelected) {
            file.assignedTags = _getTagsForFile(file);
          }
        }

        await appState.importPapers(allFiles, _useFolderTags);
      }

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Import failed: $e')));
      }
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: _existingFiles.isNotEmpty ? 900 : 600,
        constraints: const BoxConstraints(maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildContent(),
                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 20),
                    _buildTagSection(),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    String title;
    switch (widget.importType) {
      case ImportType.singleFile:
        title = 'Import Paper';
        break;
      case ImportType.multipleFiles:
        title = 'Import Papers';
        break;
      case ImportType.folder:
        title = 'Import Folder';
        break;
      case ImportType.arxiv:
        title = 'Import from arXiv';
        break;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Icon(
            widget.importType == ImportType.arxiv
                ? Icons.cloud_download_outlined
                : widget.importType == ImportType.folder
                ? Icons.folder_open
                : Icons.picture_as_pdf,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context, false),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    switch (widget.importType) {
      case ImportType.arxiv:
        return _buildArxivContent();
      case ImportType.folder:
        return _buildFolderContent();
      default:
        return _buildFileContent();
    }
  }

  Widget _buildArxivContent() {
    final metadata = widget.arxivMetadata!;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.error.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.picture_as_pdf,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      metadata.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      metadata.authors,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.7),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.tertiaryContainer,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'arXiv:${metadata.arxivId}${metadata.category != null ? " [${metadata.category}]" : ""}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(
                            context,
                          ).colorScheme.onTertiaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (metadata.abstract.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Abstract:',
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              metadata.abstract.length > 300
                  ? '${metadata.abstract.substring(0, 300)}...'
                  : metadata.abstract,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFolderContent() {
    final scanResult = widget.folderScanResult!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.folder, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                scanResult.folderName,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Text(
              '${scanResult.fileCount} PDF files discovered',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildSplitFileList(),
        const SizedBox(height: 16),
        CheckboxListTile(
          value: _useFolderTags,
          onChanged: (value) => setState(() => _useFolderTags = value ?? true),
          title: const Text('Use folder names as tags'),
          subtitle: const Text(
            'Creates tag hierarchy matching folder structure',
          ),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
        ),
      ],
    );
  }

  Widget _buildFileContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_existingFiles.isEmpty)
          Text(
            'Files to import:',
            style: Theme.of(context).textTheme.labelLarge,
          ),
        const SizedBox(height: 8),
        _buildSplitFileList(),
      ],
    );
  }

  Widget _buildSplitFileList() {
    if (_existingFiles.isEmpty) {
      return _buildFileList(_files);
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // New Files Column
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildListHeader('New Papers', _files),
              const SizedBox(height: 8),
              _buildFileList(_files),
            ],
          ),
        ),
        const SizedBox(width: 16),
        VerticalDivider(width: 1, color: Theme.of(context).dividerColor),
        const SizedBox(width: 16),
        // Existing Files Column
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildListHeader('Already in Library', _existingFiles),
              const SizedBox(height: 8),
              _buildFileList(_existingFiles),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildListHeader(String title, List<PendingImport> files) {
    bool allSelected = files.isNotEmpty && files.every((f) => f.isSelected);
    return Row(
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const Spacer(),
        if (files.isNotEmpty)
          Row(
            children: [
              Checkbox(
                value: allSelected,
                onChanged: (value) {
                  setState(() {
                    for (var f in files) {
                      f.isSelected = value ?? false;
                    }
                  });
                },
                visualDensity: VisualDensity.compact,
              ),
              Text('Select All', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
      ],
    );
  }

  Widget _buildFileList(List<PendingImport> files) {
    if (files.isEmpty) {
      return Container(
        height: 100,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text('No files', style: Theme.of(context).textTheme.bodySmall),
      );
    }

    return Container(
      constraints: const BoxConstraints(
        maxHeight: 300,
      ), // Increased height for better view
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: files.length,
        itemBuilder: (context, index) {
          final file = files[index];
          final allTags = _getTagsForFile(file);
          return CheckboxListTile(
            dense: true,
            value: file.isSelected,
            onChanged: (value) {
              setState(() => file.isSelected = value ?? true);
            },
            secondary: Icon(
              Icons.picture_as_pdf,
              color: Theme.of(context).colorScheme.error,
              size: 20,
            ),
            title: Text(
              file.fileName,
              style: Theme.of(context).textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: allTags.isNotEmpty
                ? Wrap(
                    spacing: 4,
                    children: allTags
                        .map(
                          (tag) => Chip(
                            label: Text(tag),
                            labelStyle: const TextStyle(fontSize: 10),
                            padding: EdgeInsets.zero,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                        )
                        .toList(),
                  )
                : null,
          );
        },
      ),
    );
  }

  Widget _buildTagSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Tags:', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 12),

        // Current tag option
        if (widget.currentTag != null && !widget.currentTag!.isOthers) ...[
          CheckboxListTile(
            value: _applyCurrentTag,
            onChanged: (value) =>
                setState(() => _applyCurrentTag = value ?? false),
            title: Row(
              children: [
                const Text('Apply current tag: '),
                Chip(
                  label: Text(widget.currentTag!.name),
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.primaryContainer,
                ),
              ],
            ),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 8),
        ],

        // Additional tags
        Text(
          'Additional tags:',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
          ),
        ),
        const SizedBox(height: 8),

        // Tag input with autocomplete
        Autocomplete<Tag>(
          optionsBuilder: (textEditingValue) {
            if (textEditingValue.text.isEmpty) {
              return const Iterable<Tag>.empty();
            }
            return _allTags.where(
              (tag) => tag.name.toLowerCase().contains(
                textEditingValue.text.toLowerCase(),
              ),
            );
          },
          displayStringForOption: (tag) => tag.name,
          fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
            return Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    decoration: InputDecoration(
                      hintText: 'Type to search or create tags',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      isDense: true,
                    ),
                    onSubmitted: (value) {
                      _addTag(value);
                      controller.clear();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: () {
                    _addTag(controller.text);
                    controller.clear();
                  },
                  icon: const Icon(Icons.add),
                ),
              ],
            );
          },
          onSelected: (tag) {
            _addTag(tag.name);
            // The controller is cleared automatically or kept?
            // Usually Autocomplete keeps the selected value.
            // We want to clear it to allow adding more.
            // We can't easily clear the controller here without access to it.
            // But _addTag adds it to our list.
            // If we want to clear the text after selection, we might need a workaround
            // OR rely on the fact that the user might want to add another.
            // Let's rely on the user clearing or typing new.
            // Actually, for a "tag adder", clearing is better.
            // But we don't have controller ref here.

            // Wait, if I'm using the `_addTag` logic, I'm maintaining `_additionalTags`.
            // The Autocomplete field is just an input.
            // If they pick from list, it adds.
            // If they type and hit enter/plus, it adds.

            // To clear after selection:
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _tagController.clear(); // This _tagController is useless now.
              // We need a way to clear the Autocomplete's controller.
              // Since we can't access it here, maybe we shouldn't worry about clearing on selection
              // OR we use the approach of passing a controller to RawAutocomplete.

              // But for now, let's stick to the FieldViewBuilder fix which solves the "+" button.
              // Selection clearing is a secondary polish.
            });
          },
        ),

        // Selected tags
        if (_additionalTags.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _additionalTags.map((tag) {
              return Chip(
                label: Text(tag),
                deleteIcon: const Icon(Icons.close, size: 16),
                onDeleted: () => _removeTag(tag),
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.secondaryContainer,
              );
            }).toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildFooter() {
    String buttonText;
    int count;

    switch (widget.importType) {
      case ImportType.arxiv:
        buttonText = 'Download & Import';
        count = 1;
        break;
      case ImportType.folder:
        buttonText = 'Import $_selectedFileCount Papers';
        count = _selectedFileCount;
        break;
      default:
        buttonText =
            'Import $_selectedFileCount ${_selectedFileCount == 1 ? "Paper" : "Papers"}';
        count = _selectedFileCount;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: _isLoading ? null : () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: (_isLoading || count == 0) ? null : _import,
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(buttonText),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _tagController.dispose();
    super.dispose();
  }
}

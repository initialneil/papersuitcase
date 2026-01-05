import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../widgets/tag_sidebar.dart';
import '../widgets/search_bar.dart';
import '../widgets/tag_cards.dart';
import '../widgets/paper_grid.dart';
import '../widgets/drop_zone.dart';
import '../widgets/import_dialog.dart';
import '../widgets/settings_view.dart';
import '../widgets/embedded_pdf_viewer.dart';
import 'package:flutter/services.dart';

/// Main application screen
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        return KeyboardListener(
          focusNode: _focusNode..requestFocus(),
          onKeyEvent: (event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.escape) {
              if (appState.viewingPaper != null) {
                appState.closePaperViewer();
              } else if (appState.isConfigMode) {
                appState.toggleConfigMode();
              }
            }
          },
          child: Scaffold(
            body: DropZone(
              onPdfFilesDropped: (paths) =>
                  _handlePdfDrop(context, paths, appState),
              onFolderDropped: (path) =>
                  _handleFolderDrop(context, path, appState),
              child: Row(
                children: [
                  // Left sidebar
                  const TagSidebar(),

                  // Main content area
                  Expanded(
                    child: appState.viewingPaper != null
                        ? EmbeddedPdfViewer(
                            paper: appState.viewingPaper!,
                            onBack: () => appState.closePaperViewer(),
                          )
                        : appState.isConfigMode
                        ? const SettingsView()
                        : _MainContent(
                            onImportArxiv: () =>
                                _handleArxivImport(context, appState),
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _handlePdfDrop(
    BuildContext context,
    List<String> paths,
    AppState appState,
  ) async {
    final result = await ImportDialog.showForFiles(
      context,
      paths,
      currentTag: appState.selectedTag,
    );

    if (result == true) {
      // Import was successful
    }
  }

  Future<void> _handleFolderDrop(
    BuildContext context,
    String path,
    AppState appState,
  ) async {
    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Text('Scanning folder...'),
          ],
        ),
      ),
    );

    // Scan folder
    final scanResult = await appState.scanFolder(path);

    // Close loading dialog
    if (context.mounted) {
      Navigator.pop(context);
    }

    if (scanResult == null || scanResult.files.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No PDF files found in folder')),
        );
      }
      return;
    }

    // Show import dialog
    if (context.mounted) {
      await ImportDialog.showForFolder(
        context,
        scanResult,
        currentTag: appState.selectedTag,
      );
    }
  }

  Future<void> _handleArxivImport(
    BuildContext context,
    AppState appState,
  ) async {
    final url = appState.detectedArxivUrl;
    if (url == null) return;

    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Text('Fetching arXiv metadata...'),
          ],
        ),
      ),
    );

    // Fetch metadata
    final metadata = await appState.fetchArxivMetadata(url);

    // Close loading dialog
    if (context.mounted) {
      Navigator.pop(context);
    }

    if (metadata == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not fetch arXiv metadata')),
        );
      }
      return;
    }

    // Show import dialog
    if (context.mounted) {
      await ImportDialog.showForArxiv(
        context,
        metadata,
        currentTag: appState.selectedTag,
      );
    }
  }
}

/// Main content area with search, tags, and papers
class _MainContent extends StatelessWidget {
  final VoidCallback onImportArxiv;

  const _MainContent({required this.onImportArxiv});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Search bar
            Padding(
              padding: const EdgeInsets.all(16),
              child: SearchBarWidget(onImportArxiv: onImportArxiv),
            ),

            // Current context indicator
            if (appState.selectedTag != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Icon(
                      appState.isOthersSelected
                          ? Icons.folder_off_outlined
                          : Icons.label_outline,
                      size: 18,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      appState.selectedTag!.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () => appState.clearSelection(),
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('Clear'),
                    ),
                  ],
                ),
              ),

            // Related tags (shown during search)
            if (appState.relatedTags.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: TagCards(
                  tags: appState.relatedTags,
                  title: 'Related Tags',
                  selectedTag: appState.selectedTag,
                  onTagTap: (tag) => appState.selectTag(tag),
                ),
              ),

            // Paper grid
            Expanded(
              child: appState.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : const PaperGrid(),
            ),
          ],
        );
      },
    );
  }
}

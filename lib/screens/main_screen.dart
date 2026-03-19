import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../widgets/tag_sidebar.dart';
import '../widgets/search_bar.dart';
import '../widgets/tag_cards.dart';
import '../widgets/paper_grid.dart';
import '../widgets/drop_zone.dart';
import '../widgets/settings_view.dart';
import '../widgets/embedded_pdf_viewer.dart';
import '../widgets/auth_screen.dart';
import '../widgets/discover_tab.dart';
import 'package:flutter/services.dart';

/// Main application screen
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class CloseIntent extends Intent {
  const CloseIntent();
}

class _MainScreenState extends State<MainScreen> {
  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    if (appState.showAuthScreen) {
      return Scaffold(
        body: AuthScreen(onContinueOffline: () => appState.skipAuth()),
      );
    }

    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.escape): const CloseIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          CloseIntent: CallbackAction<CloseIntent>(
            onInvoke: (intent) {
              final appState = context.read<AppState>();
              if (appState.viewingPaper != null) {
                appState.closePaperViewer();
              } else if (appState.isConfigMode) {
                appState.toggleConfigMode();
              }
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            body: DropZone(
              child: Row(
                children: [
                  // Left sidebar
                  const TagSidebar(),

                  // Main content area
                  Expanded(
                    child: Consumer<AppState>(
                      builder: (context, appState, child) {
                        if (appState.showDiscover) {
                          return const DiscoverTab();
                        } else if (appState.viewingPaper != null) {
                          return EmbeddedPdfViewer(
                            paper: appState.viewingPaper!,
                            onBack: () => appState.closePaperViewer(),
                          );
                        } else if (appState.isConfigMode) {
                          return const SettingsView();
                        } else {
                          return const _MainContent();
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

}

/// Main content area with search, tags, and papers
class _MainContent extends StatelessWidget {
  const _MainContent();

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
              child: const SearchBarWidget(),
            ),

            // Current context indicator
            if (appState.selectedTag != null || appState.selectedEntry != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    if (appState.selectedEntry != null) ...[
                      Icon(
                        Icons.folder_outlined,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${appState.selectedEntry!.name}${appState.selectedSubfolder != null ? " / ${appState.selectedSubfolder}" : ""}',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (appState.selectedEntry != null && appState.selectedTag != null)
                      const SizedBox(width: 12),
                    if (appState.selectedTag != null) ...[
                      Icon(
                        appState.selectedTag?.isUntagged == true
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
                    ],
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

            // Background processing indicator
            if (appState.processingCount > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Processing ${appState.processingCount} papers...',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
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

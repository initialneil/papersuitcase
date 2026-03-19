import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import 'bibtex_manager.dart';
import 'entry_sidebar_section.dart';
import 'tag_sidebar_section.dart';

/// Sidebar composing All Papers, Entries section, Tags section, and Settings.
class TagSidebar extends StatelessWidget {
  const TagSidebar({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        return Container(
          width: 250,
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.black.withValues(alpha: 0.2)
              : const Color(0xFFF5F5F7).withValues(alpha: 0.5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // All Papers item
              _AllPapersItem(
                isSelected: appState.selectedTag == null &&
                    appState.selectedEntry == null &&
                    appState.searchQuery.isEmpty,
                paperCount: appState.papers.length,
                onTap: () => appState.selectAllPapersView(),
              ),

              const Divider(height: 1),

              // Entries and Tags as separate scrollable sections
              // Each gets at least 1/4 of available height
              Expanded(
                child: appState.isConfigMode
                    ? _ConfigNavigation(
                        selectedCategory: 'Appearance',
                        onSelect: (category) {},
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final minHeight = constraints.maxHeight * 0.25;
                          return Column(
                            children: [
                              // Entries section — takes available space, min 1/4
                              Expanded(
                                flex: 3,
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(minHeight: minHeight),
                                  child: const SingleChildScrollView(
                                    padding: EdgeInsets.only(top: 8),
                                    child: EntrySidebarSection(),
                                  ),
                                ),
                              ),
                              const Divider(height: 1),
                              // Tags section — takes available space, min 1/4
                              Expanded(
                                flex: 2,
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(minHeight: minHeight),
                                  child: const SingleChildScrollView(
                                    padding: EdgeInsets.only(top: 8, bottom: 8),
                                    child: TagSidebarSection(),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
              ),

              const Divider(height: 1),

              // Settings button
              _SettingsButton(appState: appState),
            ],
          ),
        );
      },
    );
  }
}

/// All Papers list item at the top of the sidebar.
class _AllPapersItem extends StatelessWidget {
  final bool isSelected;
  final int paperCount;
  final VoidCallback onTap;

  const _AllPapersItem({
    required this.isSelected,
    required this.paperCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected
          ? Theme.of(context)
              .colorScheme
              .primaryContainer
              .withValues(alpha: 0.3)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(
                Icons.library_books_outlined,
                size: 20,
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.7),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'All Papers',
                  style: TextStyle(
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Settings toggle button at the bottom of the sidebar.
class _SettingsButton extends StatelessWidget {
  final AppState appState;

  const _SettingsButton({required this.appState});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          if (appState.isConfigMode)
            Expanded(
              child: TextButton.icon(
                onPressed: () => appState.toggleConfigMode(),
                icon: const Icon(Icons.arrow_back, size: 18),
                label: const Text('Back'),
                style: TextButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  foregroundColor: Theme.of(context).colorScheme.primary,
                ),
              ),
            )
          else ...[
            IconButton(
              onPressed: () => BibtexManager.show(
                context,
                papers: appState.papers,
                title: appState.selectedTag?.name ?? 'All Papers',
              ),
              icon: const Icon(Icons.menu_book_outlined, size: 20),
              tooltip: 'BibTeX Manager',
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.6),
            ),
            IconButton(
              onPressed: () => appState.toggleConfigMode(),
              icon: const Icon(Icons.settings_outlined, size: 20),
              tooltip: 'Settings',
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.6),
            ),
          ],
        ],
      ),
    );
  }
}

/// Config navigation shown when settings mode is active.
class _ConfigNavigation extends StatelessWidget {
  final String selectedCategory;
  final Function(String) onSelect;

  const _ConfigNavigation({
    required this.selectedCategory,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _ConfigItem(
          icon: Icons.palette_outlined,
          label: 'Appearance',
          isSelected: selectedCategory == 'Appearance',
          onTap: () => onSelect('Appearance'),
        ),
        _ConfigItem(
          icon: Icons.picture_as_pdf_outlined,
          label: 'PDF Viewer',
          isSelected: selectedCategory == 'PDF Viewer',
          onTap: () => onSelect('PDF Viewer'),
        ),
      ],
    );
  }
}

class _ConfigItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ConfigItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      selected: isSelected,
      selectedTileColor: Theme.of(context)
          .colorScheme
          .primaryContainer
          .withValues(alpha: 0.3),
      leading: Icon(
        icon,
        size: 20,
        color: isSelected
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context)
                .colorScheme
                .onSurface
                .withValues(alpha: 0.7),
      ),
      title: Text(
        label,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      onTap: onTap,
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import 'bibtex_manager.dart';
import 'paper_card.dart';

/// Grid of paper cards
class PaperGrid extends StatefulWidget {
  const PaperGrid({super.key});

  @override
  State<PaperGrid> createState() => _PaperGridState();
}

class _PaperGridState extends State<PaperGrid> {
  final FocusNode _focusNode = FocusNode();
  // _showBibtexPanel removed — now uses BibtexManager dialog

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  Widget _buildEmptyState(BuildContext context) {
    final appState = context.read<AppState>();
    return _EmptyState(
      hasSearch: appState.searchQuery.isNotEmpty,
      hasTagFilter: appState.selectedTag != null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final papers = appState.papers;

    if (papers.isEmpty) {
      if (appState.isLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      return _buildEmptyState(context);
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyA, meta: true): () {
          appState.selectAllPapers();
        },
        const SingleActivator(LogicalKeyboardKey.escape): () {
          appState.deselectAllPapers();
        },
      },
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            appState.deselectAllPapers();
            _focusNode.requestFocus();
          },
          child: LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount = (constraints.maxWidth / 300).floor().clamp(
                1,
                6,
              );

              final showBibtexButton = appState.selectedTag != null &&
                  !appState.selectedTag!.isUntagged;

              return CustomScrollView(
                slivers: [
                  // BibTeX Manager button
                  if (showBibtexButton)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                        child: Row(
                          children: [
                            const Spacer(),
                            TextButton.icon(
                              onPressed: () => BibtexManager.show(
                                context,
                                papers: papers,
                                title: appState.selectedTag!.name,
                              ),
                              icon: const Icon(Icons.menu_book_rounded, size: 16),
                              label: const Text('BibTeX Manager'),
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Papers
                  if (papers.isNotEmpty)
                    SliverPadding(
                      padding: const EdgeInsets.all(20),
                      sliver: SliverGrid(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          childAspectRatio: 0.8,
                          crossAxisSpacing: 20,
                          mainAxisSpacing: 20,
                        ),
                        delegate: SliverChildBuilderDelegate((context, index) {
                          final paper = papers[index];
                          return PaperCard(
                            key: ValueKey(paper.id),
                            paper: paper,
                            isSelected: appState.isPaperSelected(paper.id!),
                            onTap: () {
                              final isMetaPressed =
                                  HardwareKeyboard.instance.isMetaPressed ||
                                  HardwareKeyboard.instance.isControlPressed;

                              if (isMetaPressed) {
                                appState.togglePaperSelection(paper.id!);
                              } else {
                                appState.selectPaper(paper.id!);
                              }
                              _focusNode.requestFocus();
                            },
                            onDoubleTap: () => appState.openPaper(paper),
                          );
                        }, childCount: papers.length),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Empty state widget
class _EmptyState extends StatelessWidget {
  final bool hasSearch;
  final bool hasTagFilter;

  const _EmptyState({required this.hasSearch, required this.hasTagFilter});

  @override
  Widget build(BuildContext context) {
    String message;
    IconData icon;

    if (hasSearch) {
      message = 'No papers match your search';
      icon = Icons.search_off;
    } else if (hasTagFilter) {
      message = 'No papers with this tag';
      icon = Icons.label_off_outlined;
    } else {
      message = 'No papers yet\nDrag PDF files or folders here to get started';
      icon = Icons.article_outlined;
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 64,
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.2),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
          if (!hasSearch && !hasTagFilter) ...[
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(
                    context,
                  ).colorScheme.outline.withValues(alpha: 0.3),
                  width: 2,
                  style: BorderStyle.solid,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.file_download_outlined,
                    size: 48,
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Drop PDFs or folders here',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'or paste an arXiv URL in the search bar',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/paper.dart';

import '../services/pdf_service.dart';
import '../providers/app_state.dart';

/// Single paper card widget
class PaperCard extends StatefulWidget {
  final Paper paper;
  final bool isSelected;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;

  const PaperCard({
    super.key,
    required this.paper,
    this.isSelected = false,
    this.onTap,
    this.onDoubleTap,
  });

  @override
  State<PaperCard> createState() => _PaperCardState();
}

class _PaperCardState extends State<PaperCard> {
  String? _thumbnailPath;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  @override
  void didUpdateWidget(PaperCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.paper.id != widget.paper.id) {
      _thumbnailPath = null;
      _loadThumbnail();
    }
  }

  Future<void> _loadThumbnail() async {
    if (widget.paper.filePath == null || widget.paper.id == null) return;

    // Don't block UI
    Future.microtask(() async {
      if (!mounted) return;
      final path = await PdfService.generateThumbnail(
        widget.paper.filePath!,
        widget.paper.id!,
      );

      if (mounted && path != null) {
        setState(() => _thumbnailPath = path);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        color: widget.isSelected
            ? colorScheme.primary.withOpacity(0.2)
            : colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.isSelected
              ? colorScheme.primary
              : Theme.of(context).brightness == Brightness.dark
              ? Colors.white.withOpacity(0.1)
              : Colors.transparent,
          width: widget.isSelected ? 2 : 1,
        ),
        boxShadow: [
          if (!widget.isSelected &&
              Theme.of(context).brightness == Brightness.light)
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          onDoubleTap: widget.onDoubleTap,
          onSecondaryTapDown: (details) => _showContextMenu(context, details),
          borderRadius: BorderRadius.circular(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top Half: Info
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title row with small PDF icon
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.error.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.picture_as_pdf,
                            color: Theme.of(context).colorScheme.error,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.paper.title,
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w600),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (widget.paper.authors != null &&
                                  widget.paper.authors!.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  widget.paper.authors!,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withOpacity(0.6),
                                      ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Tags
                    if (widget.paper.tags.isNotEmpty)
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: widget.paper.tags.map((tag) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              tag.name,
                              style: TextStyle(
                                fontSize: 10,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onPrimaryContainer,
                              ),
                            ),
                          );
                        }).toList(),
                      )
                    else
                      Text(
                        'No tags',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.4),
                          fontStyle: FontStyle.italic,
                          fontSize: 10,
                        ),
                      ),

                    const SizedBox(height: 12),

                    // Date and Badge
                    Row(
                      children: [
                        Icon(
                          Icons.calendar_today_outlined,
                          size: 14,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.4),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          widget.paper.formattedDate,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withOpacity(0.5),
                                fontSize: 10,
                              ),
                        ),
                        if (widget.paper.arxivId != null) ...[
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.tertiaryContainer,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'arXiv',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onTertiaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // Bottom Half: Preview Image
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(
                    0,
                  ), // Full bleed attempt, but respecting border radius
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(11),
                    ), // -1 for border width
                    child: Container(
                      width: double.infinity,
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest.withOpacity(0.3),
                      child: _thumbnailPath != null
                          ? Image.file(
                              File(_thumbnailPath!),
                              fit: BoxFit.cover,
                              alignment: Alignment.topCenter,
                              errorBuilder: (context, error, stackTrace) =>
                                  Center(
                                    child: Icon(
                                      Icons.broken_image_outlined,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant
                                          .withOpacity(0.5),
                                    ),
                                  ),
                            )
                          : Center(
                              child: Icon(
                                Icons.image_outlined,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant.withOpacity(0.2),
                                size: 48,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showContextMenu(BuildContext context, TapDownDetails details) {
    final appState = context.read<AppState>();
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    // If not selected, select it (unless modifier key held, but for right click standard is select)
    if (!widget.isSelected) {
      appState.selectPaper(widget.paper.id!);
    }

    final selectedCount = appState.selectedPaperIds.length;
    final isMultiSelection = selectedCount > 1;

    showMenu<void>(
      context: context,
      position: RelativeRect.fromRect(
        details.globalPosition & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: <PopupMenuEntry<void>>[
        PopupMenuItem(
          child: const Row(
            children: [
              Icon(Icons.open_in_new, size: 18),
              SizedBox(width: 8),
              Text('Open PDF'),
            ],
          ),
          onTap: () => appState.openPaper(widget.paper),
        ),
        PopupMenuItem(
          child: const Row(
            children: [
              Icon(Icons.folder_open_outlined, size: 18),
              SizedBox(width: 8),
              Text('Reveal in Finder'),
            ],
          ),
          onTap: () => appState.revealPaperInFinder(widget.paper),
        ),
        if (!isMultiSelection)
          PopupMenuItem(
            enabled: false, // Placeholder
            child: const Row(
              children: [
                Icon(Icons.edit_outlined, size: 18),
                SizedBox(width: 8),
                Text('Edit tags'),
              ],
            ),
            onTap: () {
              // Will be implemented with import dialog
            },
          ),

        // Assign Tags from persistent context
        if (appState.lastActiveTagPath.isNotEmpty) ...[
          const PopupMenuDivider(),
          PopupMenuItem(
            padding: EdgeInsets.zero,
            enabled:
                false, // Disable default handling to let child handle events
            child: _AssignTagsMenuItem(appState: appState),
          ),
        ],
        const PopupMenuDivider(),
        PopupMenuItem(
          child: Row(
            children: [
              Icon(
                Icons.delete_outline,
                size: 18,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(width: 8),
              Text(
                isMultiSelection ? 'Delete $selectedCount Papers' : 'Delete',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ),
          onTap: () {
            Future.delayed(Duration.zero, () {
              if (context.mounted) {
                if (isMultiSelection) {
                  _showBatchDeleteConfirmation(
                    context,
                    appState,
                    selectedCount,
                  );
                } else {
                  _showDeleteConfirmation(context, appState);
                }
              }
            });
          },
        ),
      ],
    );
  }

  void _showDeleteConfirmation(BuildContext context, AppState appState) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Paper'),
        content: Text(
          'Are you sure you want to delete "${widget.paper.title}"? This will also delete the PDF file.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              appState.deletePaper(widget.paper);
              Navigator.pop(context);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showBatchDeleteConfirmation(
    BuildContext context,
    AppState appState,
    int count,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete $count Papers'),
        content: const Text(
          'Are you sure you want to delete the selected papers? This will also delete the PDF files.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              appState.deleteSelectedPapers();
              Navigator.pop(context);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _AssignTagsMenuItem extends StatefulWidget {
  final AppState appState;

  const _AssignTagsMenuItem({required this.appState});

  @override
  State<_AssignTagsMenuItem> createState() => _AssignTagsMenuItemState();
}

class _AssignTagsMenuItemState extends State<_AssignTagsMenuItem> {
  OverlayEntry? _overlayEntry;
  Timer? _hoverTimer;
  bool _isSubmenuOpen = false;

  @override
  void dispose() {
    _cleanUp();
    super.dispose();
  }

  void _cleanUp() {
    _hoverTimer?.cancel();
    _overlayEntry?.remove();
    _overlayEntry = null;
    _isSubmenuOpen = false;
  }

  void _openSubmenu() {
    if (_isSubmenuOpen || !mounted) return;

    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;
    final offset = renderBox.localToGlobal(Offset.zero);

    // Position to the right
    final left = offset.dx + size.width;
    final top = offset.dy;

    _overlayEntry = OverlayEntry(
      builder: (context) {
        return Positioned(
          left: left,
          top: top,
          child: MouseRegion(
            onEnter: (_) {
              // Keep open if gathering mouse
              _hoverTimer?.cancel();
            },
            onExit: (_) {
              // Close if leaving submenu
              _hoverTimer = Timer(const Duration(milliseconds: 300), _cleanUp);
            },
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(4),
              color: Theme.of(this.context).cardColor,
              child: IntrinsicWidth(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: widget.appState.lastActiveTagPath
                      .asMap()
                      .entries
                      .map((entry) {
                        final index = entry.key;
                        final tag = entry.value;
                        final displayName = widget.appState.lastActiveTagPath
                            .sublist(0, index + 1)
                            .map((t) => t.name)
                            .join('/');

                        return InkWell(
                          onTap: () {
                            widget.appState.addTagToSelectedPapers(tag);
                            _cleanUp();
                            // Close the main menu
                            Navigator.of(this.context).pop();
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16.0,
                              vertical: 12.0,
                            ),
                            child: Text(
                              displayName,
                              style: Theme.of(
                                this.context,
                              ).textTheme.bodyMedium,
                            ),
                          ),
                        );
                      })
                      .toList(),
                ),
              ),
            ),
          ),
        );
      },
    );

    Overlay.of(context).insert(_overlayEntry!);
    _isSubmenuOpen = true;
  }

  @override
  Widget build(BuildContext context) {
    // We use a Container with explicit styling because 'enabled: false' on PopupMenuItem
    // might remove standard InkWell effect. usage of Material/InkWell here restores interaction.
    return MouseRegion(
      onEnter: (_) {
        _hoverTimer?.cancel();
        _hoverTimer = Timer(const Duration(milliseconds: 50), _openSubmenu);
      },
      onExit: (_) {
        _hoverTimer?.cancel();
        _hoverTimer = Timer(const Duration(milliseconds: 300), _cleanUp);
      },
      child: InkWell(
        onTap: _openSubmenu,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            children: const [
              Icon(Icons.label_outlined, size: 18),
              SizedBox(width: 8),
              Expanded(child: Text('Assign Tags')),
              Icon(Icons.arrow_right, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

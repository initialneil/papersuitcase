import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../models/paper.dart';
import '../services/manifest_service.dart';
import '../services/pdf_service.dart';
import '../providers/app_state.dart';
import 'edit_tags_dialog.dart';

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
    if (widget.paper.id == null) return;

    // Don't block UI
    Future.microtask(() async {
      if (!mounted) return;

      final appState = context.read<AppState>();
      final entry = appState.entries
          .where((e) => e.id == widget.paper.entryId)
          .firstOrNull;
      if (entry == null) return;

      final thumbPath = ManifestService.thumbnailPath(
        entry.path,
        widget.paper.filePath,
      );

      // Check if thumbnail exists
      if (await File(thumbPath).exists()) {
        if (mounted) setState(() => _thumbnailPath = thumbPath);
        return;
      }

      // Generate on demand if missing (lazy thumbnail generation)
      final fullPath = p.join(entry.path, widget.paper.filePath);
      final result =
          await PdfService.generateThumbnailToPath(fullPath, thumbPath);
      if (mounted && result != null) {
        setState(() => _thumbnailPath = result);
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
            ? colorScheme.primary.withValues(alpha: 0.2)
            : colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.isSelected
              ? colorScheme.primary
              : Theme.of(context).brightness == Brightness.dark
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.transparent,
          width: widget.isSelected ? 2 : 1,
        ),
        boxShadow: [
          if (!widget.isSelected &&
              Theme.of(context).brightness == Brightness.light)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
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
                            ).colorScheme.error.withValues(alpha: 0.1),
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
                                            .withValues(alpha: 0.6),
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
                          ).colorScheme.onSurface.withValues(alpha: 0.4),
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
                          ).colorScheme.onSurface.withValues(alpha: 0.4),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          widget.paper.formattedDate,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.5),
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
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.3),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _thumbnailPath != null
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
                                              .withValues(alpha: 0.5),
                                        ),
                                      ),
                                )
                              : Center(
                                  child: Icon(
                                    Icons.image_outlined,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant
                                        .withValues(alpha: 0.2),
                                    size: 48,
                                  ),
                                ),
                          // BibTeX status indicator
                          if (widget.paper.bibStatus == 'verified' ||
                              widget.paper.bibStatus == 'auto_fetched')
                            Positioned(
                              bottom: 8,
                              right: 8,
                              child: Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: widget.paper.bibStatus == 'verified'
                                      ? Colors.green
                                      : Colors.orange,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 1.5,
                                  ),
                                ),
                              ),
                            ),
                        ],
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
        // Open / Reveal — "Open PDF" is a non-clickable submenu parent.
        PopupMenuItem(
          padding: EdgeInsets.zero,
          enabled: false, // parent not clickable; child handles hover/submenu
          child: _OpenPdfMenuItem(appState: appState, paper: widget.paper),
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

        const PopupMenuDivider(),

        // Edit: tags + rename
        PopupMenuItem(
          child: const Row(
            children: [
              Icon(Icons.edit_outlined, size: 18),
              SizedBox(width: 8),
              Text('Edit tags'),
            ],
          ),
          onTap: () {
            Future.delayed(Duration.zero, () {
              if (context.mounted) {
                _showEditTagsDialog(context, appState);
              }
            });
          },
        ),
        PopupMenuItem(
          child: const Row(
            children: [
              Icon(Icons.drive_file_rename_outline, size: 18),
              SizedBox(width: 8),
              Text('Rename'),
            ],
          ),
          onTap: () {
            Future.delayed(Duration.zero, () {
              if (context.mounted) {
                _showRenameDialog(context, appState);
              }
            });
          },
        ),
        PopupMenuItem(
          child: const Row(
            children: [
              Icon(Icons.auto_fix_high, size: 18),
              SizedBox(width: 8),
              Text('Auto rename from PDF'),
            ],
          ),
          onTap: () async {
            await appState.rebuildPaperTitle(widget.paper.id!);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Title updated from PDF'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          },
        ),

        const PopupMenuDivider(),

        // Read Later toggle
        PopupMenuItem(
          child: Row(
            children: [
              Icon(
                widget.paper.readLater
                    ? Icons.bookmark_remove_outlined
                    : Icons.bookmark_add_outlined,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(widget.paper.readLater
                  ? 'Remove from Read Later'
                  : 'Add to Read Later'),
            ],
          ),
          onTap: () => appState.toggleReadLater(widget.paper),
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

        // Destructive
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
                isMultiSelection
                    ? 'Move $selectedCount to Trash'
                    : 'Move to Trash',
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

  void _showRenameDialog(BuildContext context, AppState appState) {
    final controller = TextEditingController(text: widget.paper.title);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Paper'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Title'),
          onSubmitted: (value) async {
            final newTitle = value.trim();
            if (newTitle.isNotEmpty && newTitle != widget.paper.title) {
              await appState.updatePaper(widget.paper.copyWith(title: newTitle));
            }
            if (ctx.mounted) Navigator.of(ctx).pop();
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final newTitle = controller.text.trim();
              if (newTitle.isNotEmpty && newTitle != widget.paper.title) {
                await appState.updatePaper(widget.paper.copyWith(title: newTitle));
              }
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  void _showEditTagsDialog(BuildContext context, AppState appState) {
    showDialog(
      context: context,
      builder: (context) =>
          EditTagsDialog(paperIds: appState.selectedPaperIds.toList()),
    ).then((result) {
      if (result == true) {
        // Tags were updated, refresh will happen automatically via AppState
      }
    });
  }

  void _showDeleteConfirmation(BuildContext context, AppState appState) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Move to Trash'),
        content: Text(
          'Move "${widget.paper.title}" to the Trash? The PDF file is moved to your system Trash (recoverable from there).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              appState.removePaper(widget.paper);
              Navigator.pop(context);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Move to Trash'),
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
        title: Text('Move $count Papers to Trash'),
        content: const Text(
          'Move the selected papers to the Trash? Their PDF files are moved to your system Trash (recoverable from there).',
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
            child: const Text('Move to Trash'),
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

/// "Open PDF" as a non-clickable submenu parent with a hover flyout:
/// Open in app · Open with system default · Open with…
class _OpenPdfMenuItem extends StatefulWidget {
  final AppState appState;
  final Paper paper;

  const _OpenPdfMenuItem({required this.appState, required this.paper});

  @override
  State<_OpenPdfMenuItem> createState() => _OpenPdfMenuItemState();
}

class _OpenPdfMenuItemState extends State<_OpenPdfMenuItem> {
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

  /// Run [action], then dismiss the submenu and the main context menu.
  void _run(void Function() action) {
    action();
    _cleanUp();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _pickAppAndOpen() async {
    final appState = widget.appState;
    final paper = widget.paper;
    _cleanUp();
    if (mounted) Navigator.of(context).pop(); // close the main menu first
    const XTypeGroup typeGroup =
        XTypeGroup(label: 'Applications', extensions: ['app', 'exe']);
    final XFile? file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file != null) {
      await appState.openPaperWithApp(paper, file.path);
    }
  }

  void _openSubmenu() {
    if (_isSubmenuOpen || !mounted) return;

    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;
    final offset = renderBox.localToGlobal(Offset.zero);
    final left = offset.dx + size.width;
    final top = offset.dy;

    _overlayEntry = OverlayEntry(
      builder: (_) {
        return Positioned(
          left: left,
          top: top,
          child: MouseRegion(
            onEnter: (_) => _hoverTimer?.cancel(),
            onExit: (_) => _hoverTimer =
                Timer(const Duration(milliseconds: 300), _cleanUp),
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(4),
              color: Theme.of(context).cardColor,
              child: IntrinsicWidth(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _submenuRow(Icons.picture_as_pdf_outlined, 'Open in app',
                        () => _run(
                            () => widget.appState.openPaperInApp(widget.paper))),
                    _submenuRow(
                        Icons.open_in_new,
                        'Open with system default',
                        () => _run(() => widget.appState
                            .openPaperWithSystemDefault(widget.paper))),
                    _submenuRow(Icons.apps, 'Open with…', _pickAppAndOpen),
                  ],
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

  Widget _submenuRow(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Row(
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 8),
            Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            children: [
              Icon(Icons.open_in_new, size: 18),
              SizedBox(width: 8),
              Expanded(child: Text('Open PDF')),
              Icon(Icons.arrow_right, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

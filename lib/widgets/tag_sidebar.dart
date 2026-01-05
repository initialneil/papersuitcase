import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../models/tag.dart';

/// Sidebar widget showing hierarchical tag tree
class TagSidebar extends StatefulWidget {
  const TagSidebar({super.key});

  @override
  State<TagSidebar> createState() => _TagSidebarState();
}

class _TagSidebarState extends State<TagSidebar> {
  int _untaggedCount = 0;

  @override
  void initState() {
    super.initState();
    _loadUntaggedCount();
  }

  Future<void> _loadUntaggedCount() async {
    final appState = context.read<AppState>();
    final count = await appState.getUntaggedCount();
    if (mounted) {
      setState(() => _untaggedCount = count);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        // Reload untagged count when papers change
        _loadUntaggedCount();

        // Simulate frosted glass with semi-transparent background
        // Real blur requires flutter_acrylic or BackdropFilter, but plain opacity works well with window vibrancy
        return Container(
          width: 250,
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.black.withOpacity(0.2) // Dark vibrant imitation
              : const Color(
                  0xFFF5F5F7,
                ).withOpacity(0.5), // Light vibrant imitation
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      Icons.folder_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Tags',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              // Tag tree
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    // All Papers option
                    _AllPapersItem(
                      isSelected:
                          appState.selectedTag == null &&
                          appState.searchQuery.isEmpty,
                      onTap: () => appState.clearSelection(),
                    ),

                    const SizedBox(height: 8),

                    // Tag tree
                    ...appState.tagTree.map(
                      (tag) => _TagTreeItem(
                        tag: tag,
                        level: 0,
                        selectedTag: appState.selectedTag,
                        onTap: () => appState.selectTag(tag),
                        onToggleExpand: () => appState.toggleTagExpansion(tag),
                      ),
                    ),

                    const SizedBox(height: 16),
                    const Divider(),

                    // Others category
                    _OthersItem(
                      count: _untaggedCount,
                      isSelected: appState.isOthersSelected,
                      onTap: () => appState.selectTag(
                        Tag.others(paperCount: _untaggedCount),
                      ),
                    ),
                  ],
                ),
              ),

              // Add tag button
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(8),
                child: TextButton.icon(
                  onPressed: () => _showAddTagDialog(context, appState),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('New Tag'),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showAddTagDialog(BuildContext context, AppState appState) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Tag'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Tag name',
            hintText: 'Enter tag name',
          ),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              appState.createTag(value.trim());
              Navigator.pop(context);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                appState.createTag(controller.text.trim());
                Navigator.pop(context);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}

/// All Papers list item
class _AllPapersItem extends StatelessWidget {
  final bool isSelected;
  final VoidCallback onTap;

  const _AllPapersItem({required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      selected: isSelected,
      selectedTileColor: Theme.of(
        context,
      ).colorScheme.primaryContainer.withOpacity(0.3),
      leading: Icon(
        Icons.library_books_outlined,
        size: 20,
        color: isSelected
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
      ),
      title: Text(
        'All Papers',
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      onTap: onTap,
    );
  }
}

/// Others category item
class _OthersItem extends StatelessWidget {
  final int count;
  final bool isSelected;
  final VoidCallback onTap;

  const _OthersItem({
    required this.count,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      selected: isSelected,
      selectedTileColor: Theme.of(
        context,
      ).colorScheme.primaryContainer.withOpacity(0.3),
      leading: Icon(
        Icons.folder_off_outlined,
        size: 20,
        color: isSelected
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
      ),
      title: Text(
        'Others',
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      trailing: count > 0
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            )
          : null,
      onTap: onTap,
    );
  }
}

/// Single tag tree item with expand/collapse
class _TagTreeItem extends StatelessWidget {
  final Tag tag;
  final int level;
  final Tag? selectedTag;
  final VoidCallback onTap;
  final VoidCallback onToggleExpand;

  const _TagTreeItem({
    required this.tag,
    required this.level,
    required this.selectedTag,
    required this.onTap,
    required this.onToggleExpand,
  });

  bool get isSelected => selectedTag?.id == tag.id;
  bool get hasChildren => tag.children.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final appState = context.read<AppState>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: isSelected
              ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3)
              : Colors.transparent,
          child: InkWell(
            onTap: onTap,
            onSecondaryTapUp: (details) =>
                _showContextMenu(context, appState, details.globalPosition),
            child: Padding(
              padding: EdgeInsets.only(
                left: 16.0 + (level * 16),
                right: 8,
                top: 8,
                bottom: 8,
              ),
              child: Row(
                children: [
                  // Expand/collapse button
                  if (hasChildren)
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: onToggleExpand,
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: Icon(
                          tag.isExpanded
                              ? Icons.expand_more
                              : Icons.chevron_right,
                          size: 18,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.5),
                        ),
                      ),
                    )
                  else
                    const SizedBox(width: 22), // 18 + padding

                  const SizedBox(width: 4),

                  // Tag icon
                  Icon(
                    Icons.label_outline,
                    size: 18,
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.7),
                  ),

                  const SizedBox(width: 8),

                  // Tag name
                  Expanded(
                    child: Text(
                      tag.name,
                      style: TextStyle(
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),

                  // Paper count
                  if (tag.paperCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Theme.of(
                                context,
                              ).colorScheme.primary.withOpacity(0.2)
                            : Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${tag.paperCount}',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: isSelected
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),

        // Children
        if (tag.isExpanded && hasChildren)
          ...tag.children.map(
            (child) => _TagTreeItem(
              tag: child,
              level: level + 1,
              selectedTag: selectedTag,
              onTap: () => appState.selectTag(child),
              onToggleExpand: () => appState.toggleTagExpansion(child),
            ),
          ),
      ],
    );
  }

  void _showContextMenu(
    BuildContext context,
    AppState appState,
    Offset position,
  ) {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    showMenu(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          child: const Row(
            children: [
              Icon(Icons.edit_outlined, size: 18),
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
              Icon(Icons.add, size: 18),
              SizedBox(width: 8),
              Text('Add child tag'),
            ],
          ),
          onTap: () {
            Future.delayed(Duration.zero, () {
              if (context.mounted) {
                _showAddChildDialog(context, appState);
              }
            });
          },
        ),
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
                'Delete',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ),
          onTap: () {
            Future.delayed(Duration.zero, () {
              if (context.mounted) {
                _showDeleteConfirmation(context, appState);
              }
            });
          },
        ),
      ],
    );
  }

  void _showRenameDialog(BuildContext context, AppState appState) {
    final controller = TextEditingController(text: tag.name);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Tag'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Tag name'),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              appState.renameTag(tag.id!, value.trim());
              Navigator.pop(context);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                appState.renameTag(tag.id!, controller.text.trim());
                Navigator.pop(context);
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  void _showAddChildDialog(BuildContext context, AppState appState) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add child to "${tag.name}"'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Tag name',
            hintText: 'Enter child tag name',
          ),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              appState.createTag(value.trim(), parentId: tag.id);
              Navigator.pop(context);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                appState.createTag(controller.text.trim(), parentId: tag.id);
                Navigator.pop(context);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context, AppState appState) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Tag'),
        content: Text(
          'Are you sure you want to delete "${tag.name}"? Papers with this tag will not be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              appState.deleteTag(tag.id!);
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

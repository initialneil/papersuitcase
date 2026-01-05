import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';

/// Search bar with arXiv URL detection
class SearchBarWidget extends StatefulWidget {
  final VoidCallback? onImportArxiv;

  const SearchBarWidget({super.key, this.onImportArxiv});

  @override
  State<SearchBarWidget> createState() => _SearchBarWidgetState();
}

class _SearchBarWidgetState extends State<SearchBarWidget> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounceTimer;

  @override
  void dispose() {
    _controller.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String value, AppState appState) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      appState.search(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        // Sync controller with state if needed
        if (_controller.text != appState.searchQuery &&
            appState.searchQuery.isEmpty &&
            _controller.text.isNotEmpty) {
          // State was cleared externally
        }

        return Container(
          height: 48,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const SizedBox(width: 16),
              Icon(
                Icons.search,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: InputDecoration(
                    hintText: 'Search papers or paste arXiv URL...',
                    hintStyle: TextStyle(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.5),
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    isDense: true,
                  ),
                  style: Theme.of(context).textTheme.bodyLarge,
                  onChanged: (value) => _onSearchChanged(value, appState),
                ),
              ),

              // Clear button
              if (_controller.text.isNotEmpty)
                IconButton(
                  icon: Icon(
                    Icons.close,
                    size: 20,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.5),
                  ),
                  onPressed: () {
                    _controller.clear();
                    appState.clearSearch();
                  },
                ),

              // Import from arXiv button (shown when arXiv URL detected)
              if (appState.detectedArxivUrl != null) ...[
                Container(
                  height: 32,
                  margin: const EdgeInsets.only(right: 8),
                  child: FilledButton.icon(
                    onPressed: widget.onImportArxiv,
                    icon: const Icon(Icons.download, size: 18),
                    label: const Text('Import'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      textStyle: const TextStyle(fontSize: 14),
                    ),
                  ),
                ),
              ] else
                const SizedBox(width: 8),
            ],
          ),
        );
      },
    );
  }
}

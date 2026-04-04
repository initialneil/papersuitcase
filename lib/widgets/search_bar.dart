import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../services/arxiv_service.dart';
import 'download_dialog.dart';

/// Search bar with arXiv/DOI URL detection
class SearchBarWidget extends StatefulWidget {
  const SearchBarWidget({super.key});

  @override
  State<SearchBarWidget> createState() => _SearchBarWidgetState();
}

enum _DetectedUrlType { none, arxiv, doi, pdf }

class _SearchBarWidgetState extends State<SearchBarWidget> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounceTimer;
  _DetectedUrlType _detectedType = _DetectedUrlType.none;

  static final _arxivPattern =
      RegExp(r'arxiv\.org/(abs|pdf)/(\d+\.\d+(v\d+)?)');
  static final _doiPattern = RegExp(r'doi\.org/10\.\S+');
  static final _pdfUrlPattern =
      RegExp(r'^(https?://|file://).+\.pdf(\?\S*)?$', caseSensitive: false);

  @override
  void dispose() {
    _controller.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  _DetectedUrlType _detectUrlType(String value) {
    if (_arxivPattern.hasMatch(value) || ArxivService.isArxivUrl(value)) {
      return _DetectedUrlType.arxiv;
    }
    if (_doiPattern.hasMatch(value)) {
      return _DetectedUrlType.doi;
    }
    if (_pdfUrlPattern.hasMatch(value.trim())) {
      return _DetectedUrlType.pdf;
    }
    return _DetectedUrlType.none;
  }

  void _onSearchChanged(String value, AppState appState) {
    final detected = _detectUrlType(value);
    if (detected != _detectedType) {
      setState(() => _detectedType = detected);
    }

    // Only perform search if it's not a URL
    if (detected == _DetectedUrlType.none) {
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 300), () {
        appState.setSearchQuery(value);
      });
    }
  }

  void _handleFetch() {
    final text = _controller.text.trim();
    if (_detectedType == _DetectedUrlType.arxiv) {
      DownloadDialog.show(context, arxivUrl: text);
    } else if (_detectedType == _DetectedUrlType.pdf) {
      DownloadDialog.show(context, pdfUrl: text);
    } else if (_detectedType == _DetectedUrlType.doi) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('DOI support coming soon'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        return Container(
          height: 48,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              // Navigation Buttons
              IconButton(
                icon: const Icon(Icons.arrow_back, size: 20),
                onPressed: appState.canGoBack ? appState.navigateBack : null,
                tooltip: 'Back',
              ),
              IconButton(
                icon: const Icon(Icons.arrow_forward, size: 20),
                onPressed: appState.canGoForward
                    ? appState.navigateForward
                    : null,
                tooltip: 'Forward',
              ),
              const SizedBox(width: 8),

              const SizedBox(width: 8),
              Icon(
                Icons.search,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: InputDecoration(
                    hintText: 'Search papers or paste arXiv/PDF URL...',
                    hintStyle: TextStyle(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.5),
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
                    ).colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                  onPressed: () {
                    _controller.clear();
                    setState(() => _detectedType = _DetectedUrlType.none);
                    appState.clearSearch();
                  },
                ),

              // Fetch button (shown when URL detected)
              if (_detectedType == _DetectedUrlType.arxiv ||
                  _detectedType == _DetectedUrlType.pdf) ...[
                Container(
                  height: 32,
                  margin: const EdgeInsets.only(right: 8),
                  child: FilledButton.icon(
                    onPressed: _handleFetch,
                    icon: const Icon(Icons.download, size: 18),
                    label: const Text('Fetch'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      textStyle: const TextStyle(fontSize: 14),
                    ),
                  ),
                ),
              ] else if (_detectedType == _DetectedUrlType.doi) ...[
                Container(
                  height: 32,
                  margin: const EdgeInsets.only(right: 8),
                  child: Tooltip(
                    message: 'DOI support coming soon',
                    child: FilledButton.icon(
                      onPressed: _handleFetch,
                      icon: const Icon(Icons.download, size: 18),
                      label: const Text('Fetch'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        textStyle: const TextStyle(fontSize: 14),
                      ),
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

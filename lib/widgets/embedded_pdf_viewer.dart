import 'dart:io';
import 'dart:ui' show PointerChange;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import '../models/paper.dart';
import '../providers/app_state.dart';

class EmbeddedPdfViewer extends StatefulWidget {
  final Paper paper;
  final VoidCallback onBack;

  const EmbeddedPdfViewer({
    super.key,
    required this.paper,
    required this.onBack,
  });

  @override
  State<EmbeddedPdfViewer> createState() => _EmbeddedPdfViewerState();
}

class _EmbeddedPdfViewerState extends State<EmbeddedPdfViewer> {
  final PdfViewerController _controller = PdfViewerController();
  final GlobalKey<SfPdfViewerState> _pdfViewerKey = GlobalKey();

  // Annotation mode
  bool _isHighlightMode = false;
  bool _isUnderlineMode = false;

  // Track selected text for right-click context menu
  String? _selectedText;

  // Trackpad pinch-to-zoom state
  double _zoomAtPinchStart = 1.0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _showContextMenu(BuildContext context, Offset position) {
    final appState = context.read<AppState>();
    final text = _selectedText;

    final items = <PopupMenuEntry<String>>[
      if (text != null && text.isNotEmpty) ...[
        const PopupMenuItem(
          value: 'copy',
          child: Row(
            children: [
              Icon(Icons.copy, size: 18),
              SizedBox(width: 8),
              Text('Copy'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'search',
          child: Row(
            children: [
              const Icon(Icons.search, size: 18),
              const SizedBox(width: 8),
              Text(
                'Search "${text.length > 30 ? '${text.substring(0, 30)}...' : text}"',
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
      ],
      const PopupMenuItem(
        value: 'zoom_in',
        child: Row(
          children: [
            Icon(Icons.zoom_in, size: 18),
            SizedBox(width: 8),
            Text('Zoom In'),
          ],
        ),
      ),
      const PopupMenuItem(
        value: 'zoom_out',
        child: Row(
          children: [
            Icon(Icons.zoom_out, size: 18),
            SizedBox(width: 8),
            Text('Zoom Out'),
          ],
        ),
      ),
      const PopupMenuItem(
        value: 'zoom_reset',
        child: Row(
          children: [
            Icon(Icons.fit_screen_outlined, size: 18),
            SizedBox(width: 8),
            Text('Reset Zoom'),
          ],
        ),
      ),
    ];

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      items: items,
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'copy':
          if (text != null) {
            Clipboard.setData(ClipboardData(text: text));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Copied to clipboard'),
                duration: Duration(seconds: 1),
              ),
            );
          }
        case 'search':
          if (text != null) {
            appState.setSearchQuery(text.trim());
            widget.onBack();
          }
        case 'zoom_in':
          _controller.zoomLevel = _controller.zoomLevel + 0.25;
        case 'zoom_out':
          _controller.zoomLevel = (_controller.zoomLevel - 0.25).clamp(0.5, 5.0);
        case 'zoom_reset':
          _controller.zoomLevel = 1.0;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onBack,
        ),
        title: Text(
          widget.paper.title,
          style: const TextStyle(fontSize: 16),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: Icon(
              Icons.highlight,
              color: _isHighlightMode ? Colors.amber : null,
            ),
            tooltip: 'Highlight',
            onPressed: () {
              setState(() {
                _isHighlightMode = !_isHighlightMode;
                if (_isHighlightMode) _isUnderlineMode = false;
              });
            },
          ),
          IconButton(
            icon: Icon(
              Icons.format_underline,
              color: _isUnderlineMode ? Colors.blue : null,
            ),
            tooltip: 'Underline',
            onPressed: () {
              setState(() {
                _isUnderlineMode = !_isUnderlineMode;
                if (_isUnderlineMode) _isHighlightMode = false;
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.zoom_in),
            tooltip: 'Zoom In',
            onPressed: () =>
                _controller.zoomLevel = _controller.zoomLevel + 0.25,
          ),
          IconButton(
            icon: const Icon(Icons.zoom_out),
            tooltip: 'Zoom Out',
            onPressed: () =>
                _controller.zoomLevel = (_controller.zoomLevel - 0.25).clamp(0.5, 5.0),
          ),
          if (appState.isLoggedIn)
            IconButton(
              icon: Icon(
                appState.showChatPanel ? Icons.chat : Icons.chat_outlined,
              ),
              tooltip: 'Chat about this paper',
              onPressed: () => appState.toggleChatPanel(),
            ),
        ],
      ),
      body: Stack(
        children: [
          Listener(
            onPointerDown: (event) {
              // Right-click (secondary button)
              if (event.buttons == kSecondaryMouseButton) {
                _showContextMenu(context, event.position);
              }
            },
            onPointerPanZoomStart: (event) {
              _zoomAtPinchStart = _controller.zoomLevel;
            },
            onPointerPanZoomUpdate: (event) {
              final next = (_zoomAtPinchStart * event.scale).clamp(0.5, 5.0);
              if ((next - _controller.zoomLevel).abs() > 0.001) {
                _controller.zoomLevel = next;
              }
            },
            child: SfPdfViewer.file(
              File(context.read<AppState>().resolveFullPath(widget.paper)),
              key: _pdfViewerKey,
              controller: _controller,
              enableHyperlinkNavigation: false,
              onTextSelectionChanged: (details) {
                _selectedText = details.selectedText;
                if (_isHighlightMode || _isUnderlineMode) {
                  if (details.selectedText != null &&
                      details.selectedText!.isNotEmpty) {
                    debugPrint(
                      '${_isHighlightMode ? "Highlight" : "Underline"}: ${details.selectedText}',
                    );
                  }
                }
              },
            ),
          ),
          if (_isHighlightMode || _isUnderlineMode)
            Positioned(
              top: 8,
              left: 0,
              right: 0,
              child: Center(
                child: Card(
                  color: _isHighlightMode ? Colors.amber : Colors.blue,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Text(
                      '${_isHighlightMode ? "Highlight" : "Underline"} mode - Select text to annotate',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import '../models/paper.dart';

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
  final PdfViewerController _pdfViewerController = PdfViewerController();
  final GlobalKey<SfPdfViewerState> _pdfViewerKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
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
            icon: const Icon(Icons.highlight),
            tooltip: 'Highlight',
            onPressed: () {
              // Note: Syncfusion PDF Viewer for desktop/mobile supports programmatic selection
              // but actual "drawing" of highlights and persistence needs more complex setup.
              // For now, we'll demonstrate the UI action.
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Highlighting is not yet persistent'),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.format_underlined),
            tooltip: 'Underline',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Underlining is not yet persistent'),
                ),
              );
            },
          ),
          const VerticalDivider(width: 1, indent: 12, endIndent: 12),
          IconButton(
            icon: const Icon(Icons.zoom_in),
            onPressed: () {
              _pdfViewerController.zoomLevel =
                  _pdfViewerController.zoomLevel + 0.25;
            },
          ),
          IconButton(
            icon: const Icon(Icons.zoom_out),
            onPressed: () {
              _pdfViewerController.zoomLevel =
                  _pdfViewerController.zoomLevel - 0.25;
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SfPdfViewer.file(
        File(widget.paper.filePath),
        controller: _pdfViewerController,
        key: _pdfViewerKey,
      ),
    );
  }
}

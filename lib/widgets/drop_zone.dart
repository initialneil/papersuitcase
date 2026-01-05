import 'dart:io';
import 'package:flutter/material.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:cross_file/cross_file.dart';

import '../services/pdf_service.dart';

/// Full-window drop zone overlay
class DropZone extends StatefulWidget {
  final Widget child;
  final void Function(List<String> pdfPaths)? onPdfFilesDropped;
  final void Function(String folderPath)? onFolderDropped;

  const DropZone({
    super.key,
    required this.child,
    this.onPdfFilesDropped,
    this.onFolderDropped,
  });

  @override
  State<DropZone> createState() => _DropZoneState();
}

class _DropZoneState extends State<DropZone> {
  bool _isDragging = false;
  bool _isFolder = false;

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      onDragEntered: (details) {
        setState(() {
          _isDragging = true;
          _isFolder = false;
        });
      },
      onDragExited: (details) {
        setState(() {
          _isDragging = false;
          _isFolder = false;
        });
      },
      onDragDone: (details) async {
        setState(() {
          _isDragging = false;
          _isFolder = false;
        });

        await _handleDrop(details.files);
      },
      child: Stack(
        children: [
          widget.child,
          if (_isDragging)
            Positioned.fill(child: _DropOverlay(isFolder: _isFolder)),
        ],
      ),
    );
  }

  Future<void> _handleDrop(List<XFile> files) async {
    if (files.isEmpty) return;

    final pdfPaths = <String>[];
    String? folderPath;

    for (final file in files) {
      final path = file.path;

      // Check if it's a directory
      if (await FileSystemEntity.isDirectory(path)) {
        folderPath = path;
        break; // Only handle one folder at a time
      } else if (PdfService.isPdf(path)) {
        pdfPaths.add(path);
      }
    }

    if (folderPath != null) {
      widget.onFolderDropped?.call(folderPath);
    } else if (pdfPaths.isNotEmpty) {
      widget.onPdfFilesDropped?.call(pdfPaths);
    }
  }
}

/// Visual overlay shown during drag
class _DropOverlay extends StatelessWidget {
  final bool isFolder;

  const _DropOverlay({required this.isFolder});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(40),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Theme.of(context).colorScheme.primary,
              width: 3,
              style: BorderStyle.solid,
            ),
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).shadowColor.withOpacity(0.2),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isFolder ? Icons.folder_open : Icons.file_download_outlined,
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                isFolder ? 'Drop folder to import' : 'Drop PDF files to import',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isFolder
                    ? 'Folder structure will be used as tags'
                    : 'Files will be imported with current tag',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

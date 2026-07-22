import 'dart:io';
import 'package:flutter/material.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:cross_file/cross_file.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../services/pdf_service.dart';
import 'download_dialog.dart';

/// Full-window drop zone overlay
class DropZone extends StatefulWidget {
  final Widget child;

  const DropZone({
    super.key,
    required this.child,
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
    if (!mounted) return;

    final appState = context.read<AppState>();

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
      // Folder drop: create an entry directly
      await appState.addEntry(folderPath);
    } else if (pdfPaths.isNotEmpty) {
      if (!mounted) return;
      await _handlePdfDrop(pdfPaths, appState);
    }
  }

  Future<void> _handlePdfDrop(List<String> pdfPaths, AppState appState) async {
    if (appState.entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Drop a folder to create an entry first'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Import each dropped PDF through the same dialog as paste/download — it
    // extracts the title, dedups against existing papers, and files it into the
    // chosen entry/subfolder (not a raw copy). Sequential so the dialogs don't
    // stack when several PDFs are dropped at once.
    for (final path in pdfPaths) {
      if (!mounted) return;
      await DownloadDialog.show(context, pdfUrl: Uri.file(path).toString());
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
      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
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
                color: Theme.of(context).shadowColor.withValues(alpha: 0.2),
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
                isFolder
                    ? 'Drop folder to add as entry'
                    : 'Drop PDF files to add to an entry',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isFolder
                    ? 'Folder will be linked as an entry'
                    : 'Choose which entry to copy files into',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

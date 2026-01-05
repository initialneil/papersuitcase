import 'dart:io';
import 'package:path/path.dart' as p;

import '../models/import_data.dart';
import 'pdf_service.dart';

/// Service for scanning and importing folders
class FolderImportService {
  /// Scan a folder recursively for PDF files
  Future<FolderScanResult> scanFolder(String folderPath) async {
    final directory = Directory(folderPath);
    if (!await directory.exists()) {
      throw Exception('Folder not found: $folderPath');
    }

    final folderName = p.basename(folderPath);
    final files = <PendingImport>[];
    final folderHierarchy = <String, List<String>>{};

    // Use parent path as base to include the folder name itself in tags
    final parentPath = Directory(folderPath).parent.path;
    await _scanRecursively(directory, parentPath, files, folderHierarchy);

    return FolderScanResult(
      folderName: folderName,
      folderPath: folderPath,
      files: files,
      folderHierarchy: folderHierarchy,
    );
  }

  Future<void> _scanRecursively(
    Directory directory,
    String basePath,
    List<PendingImport> files,
    Map<String, List<String>> folderHierarchy,
  ) async {
    try {
      await for (final entity in directory.list()) {
        if (entity is File && PdfService.isPdf(entity.path)) {
          files.add(PendingImport.fromPath(entity.path, basePath: basePath));
        } else if (entity is Directory) {
          // Track folder hierarchy
          final relativePath = entity.path.substring(basePath.length);
          final parts = relativePath
              .split('/')
              .where((p) => p.isNotEmpty)
              .toList();

          if (parts.isNotEmpty) {
            // Build parent-child relationships
            for (int i = 0; i < parts.length; i++) {
              final parent = i == 0 ? null : parts.sublist(0, i).join('/');
              if (parent != null) {
                folderHierarchy.putIfAbsent(parent, () => []);
                if (!folderHierarchy[parent]!.contains(parts[i])) {
                  folderHierarchy[parent]!.add(parts[i]);
                }
              }
            }
          }

          await _scanRecursively(entity, basePath, files, folderHierarchy);
        }
      }
    } catch (e) {
      print('Error scanning directory ${directory.path}: $e');
    }
  }

  /// Get unique tag names from a list of pending imports
  Set<String> getUniqueTags(List<PendingImport> files) {
    final tags = <String>{};
    for (final file in files) {
      tags.addAll(file.assignedTags);
    }
    return tags;
  }

  /// Build tag hierarchy from folder structure
  Map<String, List<String>> buildTagHierarchy(List<PendingImport> files) {
    final hierarchy = <String, List<String>>{};

    for (final file in files) {
      for (int i = 0; i < file.suggestedTags.length; i++) {
        if (i > 0) {
          final parent = file.suggestedTags[i - 1];
          final child = file.suggestedTags[i];
          hierarchy.putIfAbsent(parent, () => []);
          if (!hierarchy[parent]!.contains(child)) {
            hierarchy[parent]!.add(child);
          }
        }
      }
    }

    return hierarchy;
  }
}

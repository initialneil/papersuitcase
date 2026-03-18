import 'dart:io';
import 'package:path/path.dart' as p;

import '../database/database_service.dart';
import '../models/entry.dart';
import '../models/paper.dart';
import '../services/bibtex_service.dart';
import '../services/manifest_service.dart';
import '../services/pdf_service.dart';

/// Result of scanning a single entry directory.
class ScanResult {
  final int? entryId;
  final List<Paper> newPapers;
  final List<Paper> removedPapers;
  final List<Paper> renamedPapers;
  final bool entryAccessible;

  ScanResult({
    this.entryId,
    required this.newPapers,
    required this.removedPapers,
    required this.renamedPapers,
    required this.entryAccessible,
  });

  bool get hasChanges =>
      newPapers.isNotEmpty ||
      removedPapers.isNotEmpty ||
      renamedPapers.isNotEmpty;
}

/// Scans entry directories for new, removed, and renamed PDFs.
class EntryScannerService {
  final DatabaseService _db;
  final PdfService _pdfService;

  EntryScannerService(this._db, this._pdfService);

  /// Scan all entries from the database.
  Future<List<ScanResult>> scanAllEntries() async {
    final results = <ScanResult>[];
    try {
      final entries = await _db.getAllEntries();
      for (final entry in entries) {
        final result = await scanEntry(entry);
        results.add(result);
      }
    } catch (e) {
      print('Error scanning all entries: $e');
    }
    return results;
  }

  /// Scan a single entry directory for changes.
  Future<ScanResult> scanEntry(Entry entry) async {
    try {
      final entryDir = Directory(entry.path);
      if (!await entryDir.exists()) {
        return ScanResult(
          entryId: entry.id,
          newPapers: [],
          removedPapers: [],
          renamedPapers: [],
          entryAccessible: false,
        );
      }

      // Get all PDF paths on disk (relative to entry path)
      final diskPaths = await _walkForPdfs(entry.path);

      // Get all papers in DB for this entry
      final dbPapers = await _db.getPapersByEntry(entry.id!);
      final dbPathSet = <String>{};
      final dbPapersByPath = <String, Paper>{};
      for (final paper in dbPapers) {
        dbPathSet.add(paper.filePath);
        dbPapersByPath[paper.filePath] = paper;
      }

      final diskPathSet = diskPaths.toSet();

      // Paths on disk but not in DB -> potentially new
      final newPaths = diskPathSet.difference(dbPathSet);
      // Paths in DB but not on disk -> potentially removed or renamed
      final missingPaths = dbPathSet.difference(diskPathSet);

      final removedPapers = <Paper>[];
      final renamedPapers = <Paper>[];
      final newPapers = <Paper>[];

      // Build content hash map for missing papers (potential rename sources)
      final missingByHash = <String, Paper>{};
      for (final missingPath in missingPaths) {
        final paper = dbPapersByPath[missingPath]!;
        if (paper.contentHash != null && paper.contentHash!.isNotEmpty) {
          missingByHash[paper.contentHash!] = paper;
        }
      }

      // Process new paths: check for renames first
      for (final newPath in newPaths) {
        final fullPath = p.join(entry.path, newPath);
        final hash = await ManifestService.computeContentHash(fullPath);

        if (hash != null && missingByHash.containsKey(hash)) {
          // Rename detected: same content hash as a missing paper
          final renamedPaper = missingByHash.remove(hash)!;
          await _db.updatePaperPath(renamedPaper.id!, newPath);

          // Update manifest: remove old, will be updated when processNewPaper
          // or caller handles it
          final oldRelPath = renamedPaper.filePath;
          await ManifestService.removePaperFromManifest(
              entry.path, oldRelPath);
          await ManifestService.deleteThumbnail(entry.path, oldRelPath);
          await ManifestService.deleteTextCache(entry.path, oldRelPath);

          renamedPapers.add(renamedPaper.copyWith(filePath: newPath));
        } else {
          // Genuinely new paper
          final title = p.basenameWithoutExtension(newPath);
          final paper = Paper(
            title: title,
            filePath: newPath,
            entryId: entry.id!,
            contentHash: hash,
          );
          final id = await _db.insertPaper(paper);
          newPapers.add(paper.copyWith(id: id));
        }
      }

      // Collect IDs of papers that were matched as rename sources
      final renamedIds = renamedPapers.map((rp) => rp.id).toSet();

      // Remaining missing papers (not matched by rename) are truly removed
      for (final missingPath in missingPaths) {
        final paper = dbPapersByPath[missingPath]!;
        if (renamedIds.contains(paper.id)) continue; // Was a rename source

        // Truly removed
        await _db.deletePaper(paper.id!);
        await ManifestService.removePaperFromManifest(
            entry.path, missingPath);
        await ManifestService.deleteThumbnail(entry.path, missingPath);
        await ManifestService.deleteTextCache(entry.path, missingPath);
        removedPapers.add(paper);
      }

      return ScanResult(
        entryId: entry.id,
        newPapers: newPapers,
        removedPapers: removedPapers,
        renamedPapers: renamedPapers,
        entryAccessible: true,
      );
    } catch (e) {
      print('Error scanning entry ${entry.path}: $e');
      return ScanResult(
        entryId: entry.id,
        newPapers: [],
        removedPapers: [],
        renamedPapers: [],
        entryAccessible: false,
      );
    }
  }

  /// Background processing for a newly detected paper.
  /// Set [skipBibtex] to true during bulk scans to avoid overwhelming DBLP.
  Future<void> processNewPaper(Paper paper, Entry entry,
      {bool skipBibtex = false}) async {
    try {
      final fullPath = p.join(entry.path, paper.filePath);
      final relativePath = paper.filePath;

      // Extract text
      String extractedText = '';
      try {
        extractedText = await _pdfService.extractText(fullPath);
      } catch (e) {
        print('Error extracting text for ${paper.filePath}: $e');
      }

      // Extract title
      String title = paper.title;
      try {
        title = await _pdfService.extractTitle(fullPath);
      } catch (e) {
        print('Error extracting title for ${paper.filePath}: $e');
      }

      // Generate thumbnail
      final thumbPath =
          ManifestService.thumbnailPath(entry.path, relativePath);
      try {
        await PdfService.generateThumbnailToPath(fullPath, thumbPath);
      } catch (e) {
        print('Error generating thumbnail for ${paper.filePath}: $e');
      }

      // Save extracted text to cache
      if (extractedText.isNotEmpty) {
        try {
          await ManifestService.saveExtractedText(
              entry.path, relativePath, extractedText);
        } catch (e) {
          print('Error saving extracted text for ${paper.filePath}: $e');
        }
      }

      // Compute content hash if not already set
      String? contentHash = paper.contentHash;
      if (contentHash == null || contentHash.isEmpty) {
        contentHash = await ManifestService.computeContentHash(fullPath);
      }

      // Update DB with extracted metadata
      final updatedPaper = paper.copyWith(
        title: title,
        extractedText: extractedText,
        contentHash: contentHash,
      );
      await _db.updatePaper(updatedPaper);

      // Auto-fetch BibTeX (best effort, skipped during bulk scans)
      String? bibtex;
      String bibStatus = 'none';
      if (!skipBibtex) {
        try {
          // Add delay to avoid rate limiting (429 errors)
          await Future.delayed(const Duration(milliseconds: 500));
          bibtex = await _tryFetchBibtex(title);
          if (bibtex != null && bibtex.isNotEmpty) {
            bibStatus = 'found';
          }
        } catch (e) {
          print('Error fetching BibTeX for ${paper.filePath}: $e');
        }

        if (bibtex != null && bibtex.isNotEmpty) {
          final withBib = updatedPaper.copyWith(
            bibtex: bibtex,
            bibStatus: bibStatus,
          );
          await _db.updatePaper(withBib);
        }
      }

      // Update manifest
      try {
        await ManifestService.updatePaperInManifest(
          entry.path,
          relativePath,
          title: title,
          authors: paper.authors,
          abstract_: paper.abstract,
          arxivId: paper.arxivId,
          bibtex: bibtex,
          bibStatus: bibStatus,
          addedAt: paper.addedAt.toIso8601String(),
        );
      } catch (e) {
        print('Error updating manifest for ${paper.filePath}: $e');
      }
    } catch (e) {
      print('Error processing new paper ${paper.filePath}: $e');
    }
  }

  /// Recover papers from manifest.json for a fresh install.
  Future<void> recoverFromManifest(Entry entry) async {
    try {
      final manifest = await ManifestService.readManifest(entry.path);
      if (manifest == null) return;

      final papers =
          (manifest['papers'] as Map<String, dynamic>?) ?? {};

      for (final mapEntry in papers.entries) {
        final relativePath = mapEntry.key;
        final data = mapEntry.value as Map<String, dynamic>;

        // Check file exists on disk
        final fullPath = p.join(entry.path, relativePath);
        if (!await File(fullPath).exists()) continue;

        // Check not already in DB
        final existing = await _db.getPaperByFilePath(relativePath);
        if (existing != null) continue;

        // Compute content hash
        final contentHash =
            await ManifestService.computeContentHash(fullPath);

        // Insert paper with cached metadata
        final paper = Paper(
          title: (data['title'] as String?) ?? p.basenameWithoutExtension(relativePath),
          filePath: relativePath,
          entryId: entry.id!,
          authors: data['authors'] as String?,
          abstract: data['abstract'] as String?,
          arxivId: (data['arxiv_id'] as String?)?.isNotEmpty == true
              ? data['arxiv_id'] as String
              : null,
          bibtex: (data['bibtex'] as String?)?.isNotEmpty == true
              ? data['bibtex'] as String
              : null,
          bibStatus: (data['bib_status'] as String?) ?? 'none',
          contentHash: contentHash,
          addedAt: data['added_at'] != null
              ? DateTime.tryParse(data['added_at'] as String)
              : null,
        );

        final paperId = await _db.insertPaper(paper);

        // Load extracted text from cache
        try {
          final text = await ManifestService.loadExtractedText(
              entry.path, relativePath);
          if (text != null && text.isNotEmpty) {
            final withText = paper.copyWith(
              id: paperId,
              extractedText: text,
            );
            await _db.updatePaper(withText);
          }
        } catch (e) {
          print('Error loading cached text for $relativePath: $e');
        }

        // Recover tags from manifest
        try {
          final tags = data['tags'];
          if (tags is List && tags.isNotEmpty) {
            for (final tagPath in tags) {
              if (tagPath is! String || tagPath.isEmpty) continue;
              final tagId = await _resolveTagPath(tagPath);
              if (tagId != null) {
                await _db.addTagToPaper(paperId, tagId);
              }
            }
          }
        } catch (e) {
          print('Error recovering tags for $relativePath: $e');
        }
      }
    } catch (e) {
      print('Error recovering from manifest for ${entry.path}: $e');
    }
  }

  /// Resolve a tag path string (e.g., "ML/Transformers") into a tag ID,
  /// creating tags as needed.
  Future<int?> _resolveTagPath(String tagPath) async {
    try {
      final parts = tagPath.split('/');
      int? parentId;
      int? lastId;

      for (final part in parts) {
        final trimmed = part.trim();
        if (trimmed.isEmpty) continue;
        final tag = await _db.getOrCreateTag(trimmed, parentId: parentId);
        parentId = tag.id;
        lastId = tag.id;
      }

      return lastId;
    } catch (e) {
      print('Error resolving tag path "$tagPath": $e');
      return null;
    }
  }

  /// Try to fetch BibTeX from DBLP by title.
  /// Returns null on failure, including rate limiting (429) or connection errors.
  Future<String?> _tryFetchBibtex(String title) async {
    try {
      final results = await BibtexService.searchDblp(title);
      if (results.isEmpty) return null;

      // Find best match (first result is usually most relevant)
      final best = results.first;
      final bibtex = await BibtexService.fetchBibtex(best.url);
      return bibtex;
    } on HttpException catch (e) {
      print('HTTP error fetching BibTeX: $e');
      return null;
    } on SocketException catch (e) {
      print('Connection error fetching BibTeX: $e');
      return null;
    } catch (e) {
      // Best effort — don't propagate
      return null;
    }
  }

  /// Recursively walk an entry directory finding all PDF files.
  /// Returns relative paths (relative to entryPath).
  /// Skips .papersuitecase directory.
  Future<List<String>> _walkForPdfs(String entryPath) async {
    final pdfs = <String>[];
    try {
      final dir = Directory(entryPath);
      await for (final entity in dir.list(recursive: true, followLinks: true)) {
        if (entity is! File) continue;

        final relativePath = p.relative(entity.path, from: entryPath);

        // Skip .papersuitecase directory
        if (relativePath.startsWith('.papersuitecase')) continue;

        // Skip hidden files/directories
        if (p.basename(entity.path).startsWith('.')) continue;

        if (PdfService.isPdf(entity.path)) {
          pdfs.add(relativePath);
        }
      }
    } catch (e) {
      print('Error walking directory $entryPath: $e');
    }
    return pdfs;
  }
}

# Symlink-Only Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign Paper Suitecase around a symlink-only model where the app links to external folders ("entries"), uses `.papersuitecase/` cache per entry for portability, and provides tag-scoped BibTeX management.

**Architecture:** Clean break from v4 schema. New `entries` table replaces `folders`. Papers always reference files in entries (no copy mode). `.papersuitecase/` stores manifest, thumbnails, extracted text, and combined BibTeX per entry. Live folder scanning on window focus. Sidebar shows entries + subfolders and global tags as separate sections.

**Tech Stack:** Flutter/Dart, sqflite_common_ffi (SQLite), syncfusion_flutter_pdf, pdf_render, provider (ChangeNotifier), window_manager, desktop_drop, http

**Spec:** `docs/superpowers/specs/2026-03-18-symlink-only-redesign.md`

---

## File Structure

### New Files
- `lib/models/entry.dart` — Entry model (replaces PaperFolder)
- `lib/services/entry_scanner_service.dart` — Live folder scanning, rename detection, background processing
- `lib/services/manifest_service.dart` — `.papersuitecase/` management (manifest.json, thumbnails, texts, references.bib)
- `lib/widgets/bibtex_panel.dart` — Tag-scoped BibTeX management panel
- `lib/widgets/entry_sidebar_section.dart` — Entries section of sidebar with subfolder tree
- `lib/widgets/tag_sidebar_section.dart` — Tags section of sidebar (extracted from tag_sidebar.dart)
- `lib/widgets/download_dialog.dart` — Download paper dialog (entry/subfolder picker + metadata preview)

### Modified Files
- `lib/database/database_service.dart` — v5 schema (entries table, updated papers table, new queries)
- `lib/models/paper.dart` — Remove `isSymbolicLink`, `folderId`; add `entryId`, `bibStatus`, `contentHash`
- `lib/models/tag.dart` — Rename `others` to `untagged`
- `lib/services/pdf_service.dart` — Remove copy mode and app storage; thumbnails write to `.papersuitecase/`
- `lib/services/bibtex_service.dart` — Add batch fetch, auto-fetch by arXiv ID, status tracking
- `lib/services/arxiv_service.dart` — Keep, minor updates for download flow
- `lib/providers/app_state.dart` — Major refactor: entry management, scanner integration, co-selection filters
- `lib/widgets/tag_sidebar.dart` — Restructure: entries section + tags section using new sub-widgets
- `lib/widgets/search_bar.dart` — URL detection (arXiv, DOI), dual search mode
- `lib/widgets/drop_zone.dart` — Folder drop creates entry directly
- `lib/widgets/paper_card.dart` — Update for new Paper model
- `lib/widgets/paper_grid.dart` — BibTeX panel integration when tag selected
- `lib/screens/main_screen.dart` — Minor layout updates
- `lib/main.dart` — Window focus listener for scan trigger

### Delete Files
- `lib/models/paper_folder.dart`
- `lib/models/import_data.dart`
- `lib/services/folder_import_service.dart`
- `lib/services/reference_service.dart`
- `lib/widgets/import_dialog.dart`
- `lib/widgets/folder_drop_dialog.dart`
- `lib/widgets/folder_card.dart`
- `lib/widgets/reference_tooltip.dart`
- `lib/widgets/paper_attributes_editor.dart`

---

## Task 1: Database Schema v5 & Entry Model

**Files:**
- Create: `lib/models/entry.dart`
- Modify: `lib/database/database_service.dart`
- Modify: `lib/models/paper.dart`

- [ ] **Step 1: Create Entry model**

Create `lib/models/entry.dart`:

```dart
class Entry {
  final int? id;
  final String path;
  final String name;
  final DateTime addedAt;
  bool isExpanded; // Runtime UI state
  bool isAccessible; // False if folder missing on disk
  int paperCount;
  Map<String, int> subfolderCounts; // relativePath -> count

  Entry({
    this.id,
    required this.path,
    required this.name,
    DateTime? addedAt,
    this.isExpanded = false,
    this.isAccessible = true,
    this.paperCount = 0,
    Map<String, int>? subfolderCounts,
  })  : addedAt = addedAt ?? DateTime.now(),
        subfolderCounts = subfolderCounts ?? {};

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'path': path,
      'name': name,
      'added_at': addedAt.toIso8601String(),
    };
  }

  factory Entry.fromMap(Map<String, dynamic> map) {
    return Entry(
      id: map['id'] as int?,
      path: map['path'] as String,
      name: map['name'] as String,
      addedAt: DateTime.parse(map['added_at'] as String),
    );
  }
}
```

- [ ] **Step 2: Update Paper model**

Modify `lib/models/paper.dart` — remove `isSymbolicLink`, `folderId`; add `entryId`, `bibStatus`, `contentHash`:

```dart
class Paper {
  final int? id;
  final String title;
  final String filePath;
  final int entryId;
  final String? arxivId;
  final String? authors;
  final String? abstract;
  final String? extractedText;
  final DateTime addedAt;
  final String? arxivUrl;
  final String? bibtex;
  final String bibStatus; // 'none' | 'auto_fetched' | 'verified'
  final String? contentHash; // SHA256 of first 64KB
  List<Tag> tags;
  // ... constructor, toMap, fromMap, copyWith updated accordingly
}
```

Update `toMap()`: remove `is_symbolic_link`, `folder_id`; add `entry_id`, `bib_status`, `content_hash`.
Update `fromMap()`: match new fields.
Update `copyWith()`: match new fields.

- [ ] **Step 3: Rewrite database schema**

Modify `lib/database/database_service.dart` — replace `_onCreate` with v5 schema:

- Delete existing database file on startup (clean break per spec). In `_initDatabase`, before `openDatabase`, check if db exists and delete it.
- Set `version: 5`
- `_onCreate` creates: `entries`, `papers` (with `entry_id NOT NULL`, `bib_status`, `content_hash`), `tags`, `paper_tags`, `papers_fts`, triggers, indexes
- Remove `_onUpgrade` (clean break)
- Remove all folder-related methods (`insertFolder`, `getAllFolders`, `updatePaperFolder`, `deleteFolder`, `getPapersByFolder`)
- Keep existing methods that still work: `paperExistsByPath`, `checkPapersExist`, `getOrCreateTag`, `getTagsForPaper`, `searchTags`, `getRelatedTags`, `getAllTags`, `getTagTree`, `getTagAncestors`, `insertTag`, `deleteTag`, `updateTag`, `addTagToPaper`, `removeTagFromPaper`, `setTagsForPaper`, `searchPapers`, `getUntaggedPaperCount`
- Update `insertPaper` and `updatePaper` to handle new schema fields (`entry_id`, `bib_status`, `content_hash` instead of `folder_id`, `is_symbolic_link`)
- Add entry methods: `insertEntry`, `getAllEntries`, `deleteEntry`, `getEntryByPath`
- Update `getPapersByTag` to support optional `entryId` filter parameter
- Add `getPapersByEntry(int entryId)` — gets all papers for an entry
- Add `getPapersByEntryAndSubfolder(int entryId, String subfolderPrefix)` — filters by file_path LIKE 'entryPath/subfolder%'
- Update `getUntaggedPapers` to support optional `entryId` filter
- Add `getPaperByFilePath(String filePath)` — returns Paper or null
- Add `getContentHashesForEntry(int entryId)` — returns Map<String, String> (filePath -> contentHash) for rename detection
- Add `updatePaperPath(int paperId, String newPath)` — for rename detection
- Add `getEntryPaperCounts()` — returns Map<int, int> (entryId -> count) for sidebar display

- [ ] **Step 4: Update Tag model**

In `lib/models/tag.dart`: rename `others` factory to `untagged`, rename `isOthers` to `isUntagged`. Update the display name from 'Others' to 'Untagged'.

- [ ] **Step 5: Verify compilation**

Run: `flutter analyze`
Expected: No errors in modified files (warnings OK at this stage since other files still reference old models)

- [ ] **Step 6: Commit**

```bash
git add lib/models/entry.dart lib/models/paper.dart lib/models/tag.dart lib/database/database_service.dart
git commit -m "feat: v5 schema with entries table, updated paper and tag models"
```

---

## Task 2: Manifest Service

**Files:**
- Create: `lib/services/manifest_service.dart`

- [ ] **Step 1: Create ManifestService**

Create `lib/services/manifest_service.dart`:

```dart
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart'; // Add to pubspec.yaml
import 'package:path/path.dart' as p;

class ManifestService {
  static const String _cacheDir = '.papersuitecase';
  static const String _manifestFile = 'manifest.json';
  static const String _thumbnailsDir = 'thumbnails';
  static const String _textsDir = 'texts';
  static const String _referencesBib = 'references.bib';

  /// Get the .papersuitecase directory path for an entry
  static String cachePath(String entryPath) => p.join(entryPath, _cacheDir);

  /// Generate file key from relative path (SHA1 hash)
  static String fileKey(String relativePath) {
    final bytes = utf8.encode(relativePath);
    return sha1.convert(bytes).toString().substring(0, 12);
  }

  /// Compute content hash (SHA256 of first 64KB) for rename detection
  static Future<String?> computeContentHash(String filePath) async {
    try {
      final file = File(filePath);
      final raf = await file.open();
      final bytes = await raf.read(65536); // 64KB
      await raf.close();
      return sha256.convert(bytes).toString();
    } catch (e) {
      return null;
    }
  }

  /// Ensure .papersuitecase directory structure exists
  static Future<void> ensureCacheDir(String entryPath) async {
    final base = cachePath(entryPath);
    await Directory(p.join(base, _thumbnailsDir)).create(recursive: true);
    await Directory(p.join(base, _textsDir)).create(recursive: true);
  }

  /// Get thumbnail path for a paper
  static String thumbnailPath(String entryPath, String relativePath) {
    final key = fileKey(relativePath);
    return p.join(cachePath(entryPath), _thumbnailsDir, '$key.png');
  }

  /// Get extracted text file path
  static String textPath(String entryPath, String relativePath) {
    final key = fileKey(relativePath);
    return p.join(cachePath(entryPath), _textsDir, '$key.txt');
  }

  /// Save extracted text to .papersuitecase/texts/
  static Future<void> saveExtractedText(
      String entryPath, String relativePath, String text) async {
    final path = textPath(entryPath, relativePath);
    await File(path).writeAsString(text);
  }

  /// Load extracted text from cache
  static Future<String?> loadExtractedText(
      String entryPath, String relativePath) async {
    final path = textPath(entryPath, relativePath);
    final file = File(path);
    if (await file.exists()) return await file.readAsString();
    return null;
  }

  /// Read manifest.json for an entry
  static Future<Map<String, dynamic>?> readManifest(String entryPath) async {
    final path = p.join(cachePath(entryPath), _manifestFile);
    final file = File(path);
    if (!await file.exists()) return null;
    try {
      final content = await file.readAsString();
      return json.decode(content) as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }

  /// Write manifest.json for an entry
  static Future<void> writeManifest(
      String entryPath, Map<String, dynamic> manifest) async {
    await ensureCacheDir(entryPath);
    final path = p.join(cachePath(entryPath), _manifestFile);
    final content = const JsonEncoder.withIndent('  ').convert(manifest);
    await File(path).writeAsString(content);
  }

  /// Update a single paper's entry in the manifest
  static Future<void> updatePaperInManifest(
    String entryPath,
    String relativePath, {
    required String title,
    String? authors,
    String? abstract_,
    String? extractedTextHash,
    String? arxivId,
    String? bibtex,
    String bibStatus = 'none',
    List<String> tags = const [],
    required String addedAt,
  }) async {
    final manifest = await readManifest(entryPath) ?? {'version': 1, 'papers': {}};
    final papers = (manifest['papers'] as Map<String, dynamic>?) ?? {};
    papers[relativePath] = {
      'title': title,
      'authors': authors ?? '',
      'abstract': abstract_ ?? '',
      'extracted_text_hash': extractedTextHash ?? '',
      'arxiv_id': arxivId ?? '',
      'bibtex': bibtex ?? '',
      'bib_status': bibStatus,
      'tags': tags,
      'added_at': addedAt,
    };
    manifest['papers'] = papers;
    await writeManifest(entryPath, manifest);
  }

  /// Remove a paper from the manifest
  static Future<void> removePaperFromManifest(
      String entryPath, String relativePath) async {
    final manifest = await readManifest(entryPath);
    if (manifest == null) return;
    final papers = (manifest['papers'] as Map<String, dynamic>?) ?? {};
    papers.remove(relativePath);
    manifest['papers'] = papers;
    await writeManifest(entryPath, manifest);
  }

  /// Regenerate references.bib from all papers with bibtex in manifest
  static Future<void> regenerateReferencesBib(String entryPath) async {
    final manifest = await readManifest(entryPath);
    if (manifest == null) return;
    final papers = (manifest['papers'] as Map<String, dynamic>?) ?? {};
    final buffer = StringBuffer();
    for (final entry in papers.entries) {
      final bibtex = entry.value['bibtex'] as String?;
      if (bibtex != null && bibtex.isNotEmpty) {
        buffer.writeln(bibtex);
        buffer.writeln();
      }
    }
    final path = p.join(cachePath(entryPath), _referencesBib);
    await File(path).writeAsString(buffer.toString());
  }

  /// Delete thumbnail for a paper
  static Future<void> deleteThumbnail(
      String entryPath, String relativePath) async {
    final path = thumbnailPath(entryPath, relativePath);
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  /// Delete text cache for a paper
  static Future<void> deleteTextCache(
      String entryPath, String relativePath) async {
    final path = textPath(entryPath, relativePath);
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}
```

- [ ] **Step 2: Add crypto dependency**

Add to `pubspec.yaml` under dependencies:
```yaml
  crypto: ^3.0.3
```

Run: `flutter pub get`

- [ ] **Step 3: Verify compilation**

Run: `flutter analyze`
Expected: ManifestService compiles cleanly

- [ ] **Step 4: Commit**

```bash
git add lib/services/manifest_service.dart pubspec.yaml pubspec.lock
git commit -m "feat: manifest service for .papersuitecase/ cache management"
```

---

## Task 3: Entry Scanner Service

**Files:**
- Create: `lib/services/entry_scanner_service.dart`

- [ ] **Step 1: Create EntryScannerService**

Create `lib/services/entry_scanner_service.dart`:

```dart
import 'dart:io';
import 'package:path/path.dart' as p;
import '../database/database_service.dart';
import '../models/entry.dart';
import '../models/paper.dart';
import '../services/manifest_service.dart';
import '../services/pdf_service.dart';
import '../services/bibtex_service.dart';

/// Result of scanning an entry folder
class ScanResult {
  final List<Paper> newPapers;
  final List<Paper> removedPapers;
  final List<MapEntry<Paper, String>> renamedPapers; // paper -> new path
  final bool entryAccessible;

  ScanResult({
    required this.newPapers,
    required this.removedPapers,
    required this.renamedPapers,
    required this.entryAccessible,
  });
}

class EntryScannerService {
  final DatabaseService _db;
  final PdfService _pdfService;

  EntryScannerService(this._db, this._pdfService);

  /// Scan all entries
  Future<void> scanAllEntries() async {
    final entries = await _db.getAllEntries();
    for (final entry in entries) {
      await scanEntry(entry);
    }
  }

  /// Scan a single entry for changes
  Future<ScanResult> scanEntry(Entry entry) async {
    final dir = Directory(entry.path);
    final entryAccessible = await dir.exists();

    if (!entryAccessible) {
      return ScanResult(
        newPapers: [],
        removedPapers: [],
        renamedPapers: [],
        entryAccessible: false,
      );
    }

    // 1. Walk directory, find all PDFs
    final diskPaths = <String>{};
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File && PdfService.isPdf(entity.path)) {
        // Skip .papersuitecase directory
        final rel = p.relative(entity.path, from: entry.path);
        if (!rel.startsWith('.papersuitecase')) {
          diskPaths.add(entity.path);
        }
      }
    }

    // 2. Get current DB papers for this entry
    final dbPapers = await _db.getPapersByEntry(entry.id!);
    final dbPathMap = <String, Paper>{};
    for (final paper in dbPapers) {
      dbPathMap[paper.filePath] = paper;
    }

    // 3. Find new and missing paths
    final newPaths = diskPaths.difference(dbPathMap.keys.toSet());
    final missingPaths = dbPathMap.keys.toSet().difference(diskPaths);

    // 4. Rename detection: match missing -> new by content hash
    final renamedPapers = <MapEntry<Paper, String>>[];
    final resolvedNewPaths = Set<String>.from(newPaths);
    final resolvedMissingPaths = Set<String>.from(missingPaths);

    if (missingPaths.isNotEmpty && newPaths.isNotEmpty) {
      // Get content hashes for missing papers
      final missingHashes = <String, Paper>{};
      for (final path in missingPaths) {
        final paper = dbPathMap[path]!;
        if (paper.contentHash != null) {
          missingHashes[paper.contentHash!] = paper;
        }
      }

      // Check new paths against missing hashes
      for (final newPath in newPaths.toList()) {
        final hash = await ManifestService.computeContentHash(newPath);
        if (hash != null && missingHashes.containsKey(hash)) {
          final paper = missingHashes[hash]!;
          renamedPapers.add(MapEntry(paper, newPath));
          resolvedNewPaths.remove(newPath);
          resolvedMissingPaths.remove(paper.filePath);
          missingHashes.remove(hash);
        }
      }
    }

    // 5. Process renames
    for (final rename in renamedPapers) {
      final paper = rename.key;
      final newPath = rename.value;
      final relativePath = p.relative(newPath, from: entry.path);
      await _db.updatePaperPath(paper.id!, newPath);
      // Update manifest: remove old, add new
      final oldRelPath = p.relative(paper.filePath, from: entry.path);
      await ManifestService.removePaperFromManifest(entry.path, oldRelPath);
      await ManifestService.updatePaperInManifest(
        entry.path, relativePath,
        title: paper.title,
        authors: paper.authors,
        abstract_: paper.abstract,
        arxivId: paper.arxivId,
        bibtex: paper.bibtex,
        bibStatus: paper.bibStatus,
        tags: paper.tags.map((t) => t.name).toList(),
        addedAt: paper.addedAt.toIso8601String(),
      );
    }

    // 6. Remove missing papers
    final removedPapers = <Paper>[];
    for (final path in resolvedMissingPaths) {
      final paper = dbPathMap[path]!;
      final relativePath = p.relative(path, from: entry.path);
      await _db.deletePaper(paper.id!);
      await ManifestService.removePaperFromManifest(entry.path, relativePath);
      await ManifestService.deleteThumbnail(entry.path, relativePath);
      await ManifestService.deleteTextCache(entry.path, relativePath);
      removedPapers.add(paper);
    }

    // 7. Add new papers (immediate insert with filename as title)
    final newPapers = <Paper>[];
    for (final path in resolvedNewPaths) {
      final relativePath = p.relative(path, from: entry.path);
      final fileName = p.basenameWithoutExtension(path);
      final contentHash = await ManifestService.computeContentHash(path);

      final paper = Paper(
        title: fileName,
        filePath: path,
        entryId: entry.id!,
        bibStatus: 'none',
        contentHash: contentHash,
      );

      final id = await _db.insertPaper(paper);
      final insertedPaper = paper.copyWith(id: id);
      newPapers.add(insertedPaper);
    }

    return ScanResult(
      newPapers: newPapers,
      removedPapers: removedPapers,
      renamedPapers: renamedPapers,
      entryAccessible: true,
    );
  }

  /// Background processing for a newly added paper:
  /// extract text, generate thumbnail, auto-fetch bibtex
  Future<void> processNewPaper(Paper paper, Entry entry) async {
    final relativePath = p.relative(paper.filePath, from: entry.path);

    // 1. Extract text and title
    final text = await _pdfService.extractText(paper.filePath);
    final title = await _pdfService.extractTitle(paper.filePath);

    // 2. Generate thumbnail to .papersuitecase/thumbnails/
    await _generateThumbnail(paper.filePath, entry.path, relativePath);

    // 3. Save extracted text to .papersuitecase/texts/
    if (text.isNotEmpty) {
      await ManifestService.saveExtractedText(entry.path, relativePath, text);
    }

    // 4. Update DB
    final updated = paper.copyWith(
      title: title,
      extractedText: text.isNotEmpty ? text : null,
    );
    await _db.updatePaper(updated);

    // 5. Auto-fetch BibTeX (best effort)
    String? bibtex;
    String bibStatus = 'none';
    if (paper.arxivId != null && paper.arxivId!.isNotEmpty) {
      // Try arXiv-based DBLP lookup
      try {
        final results = await BibtexService.searchDblp(paper.arxivId!);
        if (results.isNotEmpty) {
          bibtex = await BibtexService.fetchBibtex(results.first.url);
          bibStatus = 'auto_fetched';
        }
      } catch (_) {}
    }
    if (bibtex == null && title.isNotEmpty) {
      // Try title-based search
      try {
        final results = await BibtexService.searchDblp(title);
        if (results.isNotEmpty) {
          bibtex = await BibtexService.fetchBibtex(results.first.url);
          bibStatus = 'auto_fetched';
        }
      } catch (_) {}
    }

    if (bibtex != null) {
      final withBib = updated.copyWith(bibtex: bibtex, bibStatus: bibStatus);
      await _db.updatePaper(withBib);
    }

    // 6. Update manifest
    final textHash = text.isNotEmpty
        ? ManifestService.computeContentHash(paper.filePath)
        : null;
    await ManifestService.updatePaperInManifest(
      entry.path, relativePath,
      title: title,
      authors: updated.authors,
      abstract_: updated.abstract,
      arxivId: updated.arxivId,
      bibtex: bibtex,
      bibStatus: bibStatus,
      tags: [],
      addedAt: updated.addedAt.toIso8601String(),
    );
  }

  /// Generate thumbnail into .papersuitecase/thumbnails/
  Future<String?> _generateThumbnail(
      String pdfPath, String entryPath, String relativePath) async {
    final thumbPath = ManifestService.thumbnailPath(entryPath, relativePath);
    // Delegate to PdfService but with custom output path
    return await PdfService.generateThumbnailToPath(pdfPath, thumbPath);
  }

  /// Recover from manifest on fresh install
  Future<void> recoverFromManifest(Entry entry) async {
    final manifest = await ManifestService.readManifest(entry.path);
    if (manifest == null) return;

    final papers = (manifest['papers'] as Map<String, dynamic>?) ?? {};
    for (final mapEntry in papers.entries) {
      final relativePath = mapEntry.key;
      final data = mapEntry.value as Map<String, dynamic>;
      final filePath = p.join(entry.path, relativePath);

      // Skip if file doesn't exist on disk
      if (!await File(filePath).exists()) continue;
      // Skip if already in DB
      if (await _db.paperExistsByPath(filePath)) continue;

      final contentHash = await ManifestService.computeContentHash(filePath);

      // Load cached extracted text
      final cachedText = await ManifestService.loadExtractedText(
          entry.path, relativePath);

      final paper = Paper(
        title: data['title'] as String? ?? p.basenameWithoutExtension(relativePath),
        filePath: filePath,
        entryId: entry.id!,
        authors: data['authors'] as String?,
        abstract: data['abstract'] as String?,
        extractedText: cachedText,
        arxivId: _nonEmpty(data['arxiv_id'] as String?),
        bibtex: _nonEmpty(data['bibtex'] as String?),
        bibStatus: data['bib_status'] as String? ?? 'none',
        contentHash: contentHash,
        addedAt: DateTime.tryParse(data['added_at'] as String? ?? '') ?? DateTime.now(),
      );

      final paperId = await _db.insertPaper(paper);

      // Recover tags
      final tagNames = (data['tags'] as List<dynamic>?)?.cast<String>() ?? [];
      for (final tagPath in tagNames) {
        // tagPath like "ML/Transformers" -> create hierarchy
        final parts = tagPath.split('/');
        int? parentId;
        for (final part in parts) {
          final tag = await _db.getOrCreateTag(part, parentId: parentId);
          parentId = tag.id;
        }
        if (parentId != null) {
          await _db.addTagToPaper(paperId, parentId);
        }
      }
    }
  }

  String? _nonEmpty(String? s) => (s != null && s.isNotEmpty) ? s : null;
}
```

- [ ] **Step 2: Add `updatePaperPath` and `generateThumbnailToPath` methods**

Add to `lib/database/database_service.dart`:

```dart
Future<void> updatePaperPath(int paperId, String newPath) async {
  final db = await database;
  await db.update('papers', {'file_path': newPath},
      where: 'id = ?', whereArgs: [paperId]);
}
```

Add to `lib/services/pdf_service.dart` — a static method that renders a thumbnail to a specific path:

```dart
/// Generate thumbnail to a specific output path
static Future<String?> generateThumbnailToPath(String pdfPath, String outputPath) async {
  try {
    final thumbFile = File(outputPath);
    if (await thumbFile.exists()) return outputPath;

    await Directory(p.dirname(outputPath)).create(recursive: true);

    PdfDocument document;
    try {
      document = await PdfDocument.openFile(pdfPath);
    } catch (e) {
      final bytes = await File(pdfPath).readAsBytes();
      document = await PdfDocument.openData(bytes);
    }

    final page = await document.getPage(1);
    final width = 300;
    final height = (width * page.height / page.width).toInt();
    final pageImage = await page.render(width: width, height: height);

    final image = img.Image.fromBytes(
      width: pageImage.width,
      height: pageImage.height,
      bytes: pageImage.pixels.buffer,
      order: img.ChannelOrder.rgba,
      numChannels: 4,
    );

    final pngBytes = img.encodePng(image);
    await thumbFile.writeAsBytes(pngBytes);
    await document.dispose();
    return outputPath;
  } catch (e) {
    print('Error generating thumbnail: $e');
    return null;
  }
}
```

- [ ] **Step 3: Verify compilation**

Run: `flutter analyze`

- [ ] **Step 4: Commit**

```bash
git add lib/services/entry_scanner_service.dart lib/database/database_service.dart lib/services/pdf_service.dart
git commit -m "feat: entry scanner service with rename detection and manifest recovery"
```

---

## Task 4: Delete Legacy Files & Clean Up Imports

**Files:**
- Delete: `lib/models/paper_folder.dart`, `lib/models/import_data.dart`, `lib/services/folder_import_service.dart`, `lib/services/reference_service.dart`, `lib/widgets/import_dialog.dart`, `lib/widgets/folder_drop_dialog.dart`, `lib/widgets/folder_card.dart`, `lib/widgets/reference_tooltip.dart`, `lib/widgets/paper_attributes_editor.dart`

- [ ] **Step 1: Delete legacy files**

```bash
rm lib/models/paper_folder.dart
rm lib/models/import_data.dart
rm lib/services/folder_import_service.dart
rm lib/services/reference_service.dart
rm lib/widgets/import_dialog.dart
rm lib/widgets/folder_drop_dialog.dart
rm lib/widgets/folder_card.dart
rm lib/widgets/reference_tooltip.dart
rm lib/widgets/paper_attributes_editor.dart
```

- [ ] **Step 2: Remove imports of deleted files**

Search all remaining `.dart` files for imports of deleted files and remove those import lines. Key files to check:
- `lib/providers/app_state.dart` — remove imports of `paper_folder.dart`, `import_data.dart`, `folder_import_service.dart`, `reference_service.dart`
- `lib/database/database_service.dart` — remove import of `paper_folder.dart`
- `lib/screens/main_screen.dart` — remove imports of deleted widgets
- `lib/widgets/tag_sidebar.dart` — remove imports of `folder_card.dart`, `reference_tooltip.dart`

Comment out (don't delete yet) any code blocks in `app_state.dart`, `tag_sidebar.dart`, `main_screen.dart` that reference deleted types. These will be rewritten in subsequent tasks.

- [ ] **Step 3: Remove copy mode from PdfService**

In `lib/services/pdf_service.dart`:
- Remove `storageDirectory` getter and `_storageDir` field
- Remove `sanitizeFilename` method
- Remove `importPdf` method
- Remove `deletePdf` method
- Remove old `generateThumbnail` (keep `generateThumbnailToPath` from Task 3)
- Remove old `deleteThumbnail`
- Keep: `extractText`, `extractTitle`, `isPdf`, `openWithCustomApp`, `openWithSystemViewer`, `revealInFinder`, `generateThumbnailToPath`

- [ ] **Step 4: Verify compilation**

Run: `flutter analyze`
Expected: Errors only in app_state.dart, tag_sidebar.dart, main_screen.dart (commented-out sections). No errors in models, services, database.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore: remove legacy files (copy mode, folder import, import dialog)"
```

---

## Task 5: Refactor AppState

**Files:**
- Modify: `lib/providers/app_state.dart`

This is the largest task. AppState needs to be rewritten to use entries instead of folders, integrate the scanner, and support entry+tag co-selection.

- [ ] **Step 1: Rewrite state fields**

Replace folder-related state with entry state:

```dart
// Remove:
List<PaperFolder> _folders = [];
List<PaperFolder> _folderTree = [];
PaperFolder? _selectedFolder;
// All import-related fields (_isImporting, _importStatus, etc.)
// FolderImportService reference

// Add:
List<Entry> _entries = [];
Entry? _selectedEntry;
String? _selectedSubfolder; // relative path within entry, null = all
final EntryScannerService _scannerService;
```

- [ ] **Step 2: Rewrite initialization**

```dart
Future<void> initialize() async {
  _isLoading = true;
  notifyListeners();

  try {
    _entries = await _db.getAllEntries();
    await _loadTagTree();
    await _loadPapers();
    _untaggedCount = await _db.getUntaggedPaperCount();
  } catch (e) {
    _error = e.toString();
  } finally {
    _isLoading = false;
    notifyListeners();
  }
}
```

- [ ] **Step 3: Add entry management methods**

```dart
Future<void> addEntry(String folderPath) async {
  final name = p.basename(folderPath);
  final entry = Entry(path: folderPath, name: name);
  final id = await _db.insertEntry(entry);
  final insertedEntry = Entry(id: id, path: folderPath, name: name);

  // Try manifest recovery first
  await _scannerService.recoverFromManifest(insertedEntry);

  // Then scan for new files
  await _scannerService.scanEntry(insertedEntry);

  // Reload state
  _entries = await _db.getAllEntries();
  await _loadPapers();
  await _loadTagTree();
  _untaggedCount = await _db.getUntaggedPaperCount();
  notifyListeners();
}

Future<void> removeEntry(int entryId) async {
  await _db.deleteEntry(entryId);
  if (_selectedEntry?.id == entryId) {
    _selectedEntry = null;
    _selectedSubfolder = null;
  }
  _entries = await _db.getAllEntries();
  await _loadPapers();
  await _loadTagTree();
  _untaggedCount = await _db.getUntaggedPaperCount();
  notifyListeners();
}

Future<void> scanAllEntries() async {
  await _scannerService.scanAllEntries();
  _entries = await _db.getAllEntries();
  await _loadPapers();
  _untaggedCount = await _db.getUntaggedPaperCount();
  notifyListeners();
}
```

- [ ] **Step 4: Rewrite `_loadPapers` for co-selection filtering**

```dart
Future<void> _loadPapers() async {
  if (_searchQuery != null && _searchQuery!.isNotEmpty) {
    _papers = await _db.searchPapers(_searchQuery!);
  } else if (_selectedTag != null && _selectedTag!.isOthers) {
    _papers = await _db.getUntaggedPapers(entryId: _selectedEntry?.id);
  } else if (_selectedTag != null) {
    _papers = await _db.getPapersByTag(_selectedTag!.id!, entryId: _selectedEntry?.id);
  } else if (_selectedEntry != null && _selectedSubfolder != null) {
    _papers = await _db.getPapersByEntryAndSubfolder(
        _selectedEntry!.id!, _selectedSubfolder!);
  } else if (_selectedEntry != null) {
    _papers = await _db.getPapersByEntry(_selectedEntry!.id!);
  } else {
    _papers = await _db.getAllPapers();
  }
  notifyListeners();
}
```

- [ ] **Step 5: Add selection methods with co-selection support**

```dart
void selectEntry(Entry? entry, {String? subfolder}) {
  _selectedEntry = entry;
  _selectedSubfolder = subfolder;
  // Keep _selectedTag (co-selection)
  _pushHistory();
  _loadPapers();
}

void selectTag(Tag? tag) {
  _selectedTag = tag;
  // Keep _selectedEntry (co-selection)
  _pushHistory();
  _loadPapers();
  _loadTagTree();
}

void selectAllPapers() {
  _selectedEntry = null;
  _selectedSubfolder = null;
  _selectedTag = null;
  _searchQuery = null;
  _pushHistory();
  _loadPapers();
}
```

- [ ] **Step 6: Update navigation history for new model**

Navigation state now tracks: `selectedEntry?.id`, `selectedSubfolder`, `selectedTag?.id`, `searchQuery`.

- [ ] **Step 7: Add paper un-index and background processing**

Add `removePaper` method (un-index only, never delete from disk):
```dart
Future<void> removePaper(Paper paper) async {
  final entry = _entries.firstWhere((e) => e.id == paper.entryId);
  final relativePath = p.relative(paper.filePath, from: entry.path);
  await _db.deletePaper(paper.id!);
  await ManifestService.removePaperFromManifest(entry.path, relativePath);
  await ManifestService.deleteThumbnail(entry.path, relativePath);
  await ManifestService.deleteTextCache(entry.path, relativePath);
  await refresh();
}
```

Wire up background processing after scan: in `addEntry` and `scanAllEntries`, after `scanEntry` returns, call `_scannerService.processNewPaper` for each new paper in an async loop (non-blocking).

- [ ] **Step 8: Remove all legacy import methods**

Remove: `importPapers`, `importFromArxiv`, `_handleFolderDrop`, `_handleFileDrop`, all `_import*` fields and methods, folder expansion/scanning methods.

- [ ] **Step 9: Verify compilation**

Run: `flutter analyze`
Expected: Errors only in widget files that haven't been updated yet

- [ ] **Step 10: Commit**

```bash
git add lib/providers/app_state.dart
git commit -m "feat: refactor AppState for entries, co-selection, scanner integration"
```

---

## Task 6: Sidebar Redesign

**Files:**
- Create: `lib/widgets/entry_sidebar_section.dart`
- Create: `lib/widgets/tag_sidebar_section.dart`
- Modify: `lib/widgets/tag_sidebar.dart`

- [ ] **Step 1: Create entry sidebar section**

Create `lib/widgets/entry_sidebar_section.dart` — renders the ENTRIES section with:
- Section header "ENTRIES" with + button to add entry via folder picker
- List of entries with expand/collapse for subfolders
- Subfolder tree derived from papers' file paths
- Paper counts per entry and subfolder
- Right-click context menu: remove entry, refresh, reveal in Finder
- Drop target for folders to create new entries
- Selected state highlighting (matches `_selectedEntry` and `_selectedSubfolder`)
- Warning badge if entry folder is inaccessible

- [ ] **Step 2: Create tag sidebar section**

Create `lib/widgets/tag_sidebar_section.dart` — extract and adapt the tag tree rendering from current `tag_sidebar.dart`:
- Section header "TAGS"
- Hierarchical tag tree with expand/collapse
- Paper counts (recursive)
- "Untagged" item at bottom
- Tag CRUD (add, rename, delete, reparent)
- Drag-and-drop papers onto tags
- Selected state highlighting

- [ ] **Step 3: Rewrite tag_sidebar.dart as the container**

Rewrite `lib/widgets/tag_sidebar.dart` as a thin container that composes:
```
Column(
  children: [
    _AllPapersItem(),
    Divider(),
    EntrySidebarSection(),
    Divider(),
    TagSidebarSection(),
    Spacer(),
    _SettingsButton(),
  ],
)
```

Keep the 250px width, scroll behavior, and theme styling from current sidebar.

- [ ] **Step 4: Verify compilation**

Run: `flutter analyze`

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/entry_sidebar_section.dart lib/widgets/tag_sidebar_section.dart lib/widgets/tag_sidebar.dart
git commit -m "feat: redesigned sidebar with entries section and tags section"
```

---

## Task 7: Drop Zone & Search Bar Updates

**Files:**
- Modify: `lib/widgets/drop_zone.dart`
- Modify: `lib/widgets/search_bar.dart`
- Create: `lib/widgets/download_dialog.dart`

- [ ] **Step 1: Simplify drop zone**

Modify `lib/widgets/drop_zone.dart`:
- Folder drop → call `appState.addEntry(folderPath)` directly (no dialog)
- PDF file drop → if entries exist, show simple dialog to pick target entry/subfolder, then move/copy file there. If no entries, show "Add an entry folder first" message.
- Remove all references to ImportDialog and FolderDropDialog

- [ ] **Step 2: Add URL detection to search bar**

Modify `lib/widgets/search_bar.dart`:
- Detect arXiv URLs: `RegExp(r'arxiv\.org/(abs|pdf)/(\d+\.\d+)')`
- Detect DOI URLs: `RegExp(r'doi\.org/10\.\S+')`
- When URL detected, show a "Fetch" button/icon next to search
- Plain text: existing local FTS search + add arXiv API search results below

- [ ] **Step 3: Create download dialog**

Create `lib/widgets/download_dialog.dart`:
- Shows metadata preview (title, authors, abstract) for fetched paper
- Entry picker dropdown (required)
- Subfolder picker (optional, shows subfolders of selected entry)
- Download button → downloads PDF to selected location
- After download, calls `appState.scanAllEntries()` to pick up the new file

- [ ] **Step 4: Verify compilation**

Run: `flutter analyze`

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/drop_zone.dart lib/widgets/search_bar.dart lib/widgets/download_dialog.dart
git commit -m "feat: folder drop creates entry, search bar with URL detection"
```

---

## Task 8: BibTeX Panel & Tag-Scoped Export

**Files:**
- Create: `lib/widgets/bibtex_panel.dart`
- Modify: `lib/services/bibtex_service.dart`
- Modify: `lib/widgets/paper_grid.dart`

- [ ] **Step 1: Add batch fetch to BibtexService**

Add to `lib/services/bibtex_service.dart`:

```dart
/// Auto-fetch BibTeX for a paper by arXiv ID or title
static Future<String?> autoFetch(Paper paper) async {
  // 1. Try arXiv ID
  if (paper.arxivId != null && paper.arxivId!.isNotEmpty) {
    try {
      final results = await searchDblp(paper.arxivId!);
      if (results.isNotEmpty) {
        return await fetchBibtex(results.first.url);
      }
    } catch (_) {}
  }

  // 2. Try title
  if (paper.title.isNotEmpty) {
    try {
      final results = await searchDblp(paper.title);
      if (results.isNotEmpty) {
        return await fetchBibtex(results.first.url);
      }
    } catch (_) {}
    // 3. Try ACM
    try {
      final results = await _searchAcm(paper.title);
      if (results.isNotEmpty) {
        return await _fetchBibtexFromAcm(results.first.url);
      }
    } catch (_) {}
  }

  return null;
}

/// Batch auto-fetch for multiple papers
static Future<Map<int, String>> batchAutoFetch(List<Paper> papers) async {
  final results = <int, String>{};
  for (final paper in papers) {
    if (paper.bibtex != null && paper.bibtex!.isNotEmpty) continue;
    final bib = await autoFetch(paper);
    if (bib != null && paper.id != null) {
      results[paper.id!] = bib;
    }
    // Rate limit: small delay between requests
    await Future.delayed(const Duration(milliseconds: 500));
  }
  return results;
}

/// Export combined BibTeX for a list of papers
static String exportBibtex(List<Paper> papers) {
  final buffer = StringBuffer();
  for (final paper in papers) {
    if (paper.bibtex != null && paper.bibtex!.isNotEmpty) {
      buffer.writeln(paper.bibtex);
      buffer.writeln();
    }
  }
  return buffer.toString();
}
```

- [ ] **Step 2: Create BibTeX panel widget**

Create `lib/widgets/bibtex_panel.dart` — shown when a tag is selected:

- Status bar: "N papers — X have BibTeX, Y missing"
- Per-paper rows with:
  - Paper title
  - Status icon: ✓ (verified, green) / ⚠ (auto_fetched, orange) / ✗ (missing, red)
  - Citation key (if bibtex exists)
  - Actions: Fetch, Edit, Verify, Copy key
- "Batch Fetch All Missing" button
- "Export .bib" button → file picker dialog
- "Copy All BibTeX" button → clipboard

- [ ] **Step 3: Integrate BibTeX panel into paper_grid**

Modify `lib/widgets/paper_grid.dart`:
- When a tag is selected, show a collapsible BibTeX panel at the top of the grid area
- Toggle button: "BibTeX" to show/hide the panel

- [ ] **Step 4: Verify compilation**

Run: `flutter analyze`

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/bibtex_panel.dart lib/services/bibtex_service.dart lib/widgets/paper_grid.dart
git commit -m "feat: tag-scoped BibTeX panel with batch fetch and export"
```

---

## Task 9: Update Remaining Widgets & Main Screen

**Files:**
- Modify: `lib/widgets/paper_card.dart`
- Modify: `lib/widgets/embedded_pdf_viewer.dart`
- Modify: `lib/screens/main_screen.dart`
- Modify: `lib/main.dart`

- [ ] **Step 1: Update paper_card.dart**

- Remove references to `isSymbolicLink`, `folderId`
- Add BibTeX status indicator (small icon in card corner)
- Update context menu: keep "Reveal in Finder", "Open with...", tag management. Remove "Delete file" — replace with "Remove from library" (un-index only)

- [ ] **Step 2: Update main_screen.dart**

- Remove import dialog references
- Ensure DropZone wraps correctly with new behavior
- Remove any folder-related UI elements

- [ ] **Step 3: Add window focus listener to main.dart**

In `lib/main.dart`, add window focus callback:

```dart
// In _MyAppState or equivalent:
@override
void initState() {
  super.initState();
  windowManager.addListener(_windowListener);
}

// Window listener class:
class _WindowFocusListener extends WindowListener {
  final AppState appState;
  _WindowFocusListener(this.appState);

  @override
  void onWindowFocus() {
    appState.scanAllEntries();
  }
}
```

- [ ] **Step 4: Update edit_tags_dialog.dart**

Review `lib/widgets/edit_tags_dialog.dart` — ensure it works with updated Paper model (no `folderId`, `isSymbolicLink`).

- [ ] **Step 5: Full compilation check**

Run: `flutter analyze`
Expected: Zero errors

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: update widgets and main screen for symlink-only model"
```

---

## Task 10: Integration Testing & Final Polish

- [ ] **Step 1: Run the app**

```bash
flutter run -d macos
```

Verify:
- App launches with empty state (no entries)
- Sidebar shows "All Papers (0)", ENTRIES (empty), TAGS (empty), Settings

- [ ] **Step 2: Test entry creation**

- Drop a folder with PDFs onto the sidebar
- Verify: entry appears, papers populate, thumbnails generate
- Verify: `.papersuitecase/` created in the folder

- [ ] **Step 3: Test tag workflow**

- Create a tag
- Assign papers to it
- Verify: tag count updates, filtering works
- Verify: entry + tag co-selection filters to intersection

- [ ] **Step 4: Test BibTeX workflow**

- Select a tag with papers
- Open BibTeX panel
- Click "Batch Fetch All Missing"
- Verify: BibTeX populates for found papers
- Click "Export .bib" — verify file contains correct entries

- [ ] **Step 5: Test search bar**

- Type a search query → verify local FTS results
- Paste an arXiv URL → verify metadata fetch and download flow

- [ ] **Step 6: Test window focus scanning**

- Add a PDF file to an entry folder externally (via Finder)
- Switch back to the app
- Verify: new paper appears automatically

- [ ] **Step 7: Test fresh install recovery**

- Note current state (entries, papers, tags)
- Delete the database file (`~/Library/Application Support/paper_suitecase/paper_suitecase.db`)
- Restart app
- Re-add the same entry folders
- Verify: papers, tags, and BibTeX recovered from `.papersuitecase/manifest.json`

- [ ] **Step 8: Final commit**

```bash
git add -A
git commit -m "feat: complete symlink-only redesign"
```

---

## Deferred Features (Not in This Plan)

These are mentioned in the spec but intentionally deferred to a future iteration:

- **DOI URL resolution**: spec mentions `doi.org/...` handling but no service exists. For now, DOI URLs are detected but show "DOI resolution coming soon". Implement when needed.
- **Other URL handling**: `openreview.net`, `semanticscholar.org` — same, detected but deferred.
- **Manifest debouncing**: spec says "debounced, not on every keystroke". For initial implementation, manifest writes happen synchronously. Add debouncing if performance becomes an issue.
- **Overlapping entries**: the UNIQUE constraint on `papers.file_path` naturally prevents duplicates. If a user adds overlapping entry folders, the scanner will skip files already in the DB. No special UI warning needed initially.

## Implementation Notes

- `BibtexService._searchAcm` and `_fetchBibtexFromAcm` already exist in the current codebase — no new implementation needed for ACM support.
- `PdfService.isPdf` is already a static method in the current codebase.
- `crypto` package must be added to `pubspec.yaml` for SHA1/SHA256 in ManifestService.
- `pdf_render` and `image` packages are already in `pubspec.yaml`.

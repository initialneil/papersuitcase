import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

class ManifestService {
  static const String _cacheDir = '.papersuitecase';
  static const String _manifestFile = 'manifest.json';
  static const String _thumbnailsDir = 'thumbnails';
  static const String _textsDir = 'texts';
  static const String _referencesBib = 'references.bib';

  /// Get the .papersuitecase directory path for an entry
  static String cachePath(String entryPath) => p.join(entryPath, _cacheDir);

  /// Generate file key from relative path (SHA1 hash, first 12 chars)
  static String fileKey(String relativePath) {
    final bytes = utf8.encode(relativePath);
    return sha1.convert(bytes).toString().substring(0, 12);
  }

  /// Compute content hash (SHA256 of first 64KB) for rename detection
  static Future<String?> computeContentHash(String filePath) async {
    try {
      final file = File(filePath);
      final raf = await file.open();
      final bytes = await raf.read(65536);
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
    final filePath = textPath(entryPath, relativePath);
    await Directory(p.dirname(filePath)).create(recursive: true);
    await File(filePath).writeAsString(text);
  }

  /// Load extracted text from cache
  static Future<String?> loadExtractedText(
      String entryPath, String relativePath) async {
    final filePath = textPath(entryPath, relativePath);
    final file = File(filePath);
    if (await file.exists()) return await file.readAsString();
    return null;
  }

  /// Recursively convert all nested maps to `Map<String, dynamic>`.
  static Map<String, dynamic> _deepCast(Map map) {
    return map.map((key, value) {
      if (value is Map) {
        return MapEntry(key.toString(), _deepCast(value));
      } else if (value is List) {
        return MapEntry(
            key.toString(),
            value.map((e) => e is Map ? _deepCast(e) : e).toList());
      }
      return MapEntry(key.toString(), value);
    });
  }

  /// Read manifest.json for an entry
  static Future<Map<String, dynamic>?> readManifest(String entryPath) async {
    final filePath = p.join(cachePath(entryPath), _manifestFile);
    final file = File(filePath);
    if (!await file.exists()) return null;
    try {
      final content = await file.readAsString();
      final decoded = json.decode(content);
      if (decoded is Map) {
        return _deepCast(decoded);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Write manifest.json for an entry
  static Future<void> writeManifest(
      String entryPath, Map<String, dynamic> manifest) async {
    await ensureCacheDir(entryPath);
    final filePath = p.join(cachePath(entryPath), _manifestFile);
    final content = const JsonEncoder.withIndent('  ').convert(manifest);
    await File(filePath).writeAsString(content);
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
    final manifest =
        await readManifest(entryPath) ?? {'version': 1, 'papers': {}};
    final papers = Map<String, dynamic>.from(
        (manifest['papers'] as Map<String, dynamic>?) ?? {});
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
    final papers = Map<String, dynamic>.from(
        (manifest['papers'] as Map<String, dynamic>?) ?? {});
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
      final data = entry.value as Map<String, dynamic>;
      final bibtex = data['bibtex'] as String?;
      if (bibtex != null && bibtex.isNotEmpty) {
        buffer.writeln(bibtex);
        buffer.writeln();
      }
    }
    await ensureCacheDir(entryPath);
    final filePath = p.join(cachePath(entryPath), _referencesBib);
    await File(filePath).writeAsString(buffer.toString());
  }

  /// Delete thumbnail for a paper
  static Future<void> deleteThumbnail(
      String entryPath, String relativePath) async {
    final filePath = thumbnailPath(entryPath, relativePath);
    final file = File(filePath);
    if (await file.exists()) await file.delete();
  }

  /// Delete text cache for a paper
  static Future<void> deleteTextCache(
      String entryPath, String relativePath) async {
    final filePath = textPath(entryPath, relativePath);
    final file = File(filePath);
    if (await file.exists()) await file.delete();
  }
}

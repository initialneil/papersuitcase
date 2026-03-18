import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/paper.dart';
import '../models/tag.dart';
import '../models/entry.dart';

/// Database service for managing papers and tags
class DatabaseService {
  static Database? _database;
  static const String _dbName = 'paper_suitecase.db';

  /// Initialize the database
  static Future<void> initialize() async {
    // Initialize FFI for desktop
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  /// Get database instance
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final appDir = await getApplicationSupportDirectory();
    final dbPath = p.join(appDir.path, _dbName);

    // Ensure directory exists
    await Directory(appDir.path).create(recursive: true);

    // Clean break: delete existing database if it exists
    final dbFile = File(dbPath);
    if (await dbFile.exists()) {
      await dbFile.delete();
    }

    return await openDatabase(
      dbPath,
      version: 5,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // Create entries table (referenced by papers)
    await db.execute('''
      CREATE TABLE entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        path TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        added_at TEXT NOT NULL
      )
    ''');

    // Create papers table
    await db.execute('''
      CREATE TABLE papers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entry_id INTEGER NOT NULL REFERENCES entries(id) ON DELETE CASCADE,
        file_path TEXT NOT NULL UNIQUE,
        title TEXT NOT NULL,
        authors TEXT,
        abstract TEXT,
        extracted_text TEXT,
        arxiv_id TEXT,
        arxiv_url TEXT,
        bibtex TEXT,
        bib_status TEXT NOT NULL DEFAULT 'none',
        content_hash TEXT,
        added_at TEXT NOT NULL
      )
    ''');

    // Create tags table with hierarchy support
    await db.execute('''
      CREATE TABLE tags (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        parent_id INTEGER,
        FOREIGN KEY (parent_id) REFERENCES tags(id) ON DELETE SET NULL,
        UNIQUE(name, parent_id)
      )
    ''');

    // Create paper_tags junction table
    await db.execute('''
      CREATE TABLE paper_tags (
        paper_id INTEGER NOT NULL,
        tag_id INTEGER NOT NULL,
        PRIMARY KEY (paper_id, tag_id),
        FOREIGN KEY (paper_id) REFERENCES papers(id) ON DELETE CASCADE,
        FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE
      )
    ''');

    // Create FTS5 virtual table for full-text search
    await db.execute('''
      CREATE VIRTUAL TABLE papers_fts USING fts5(
        title,
        authors,
        abstract,
        extracted_text,
        content='papers',
        content_rowid='id'
      )
    ''');

    // Create triggers to keep FTS in sync
    await db.execute('''
      CREATE TRIGGER papers_ai AFTER INSERT ON papers BEGIN
        INSERT INTO papers_fts(rowid, title, authors, abstract, extracted_text)
        VALUES (new.id, new.title, new.authors, new.abstract, new.extracted_text);
      END
    ''');

    await db.execute('''
      CREATE TRIGGER papers_ad AFTER DELETE ON papers BEGIN
        INSERT INTO papers_fts(papers_fts, rowid, title, authors, abstract, extracted_text)
        VALUES ('delete', old.id, old.title, old.authors, old.abstract, old.extracted_text);
      END
    ''');

    await db.execute('''
      CREATE TRIGGER papers_au AFTER UPDATE ON papers BEGIN
        INSERT INTO papers_fts(papers_fts, rowid, title, authors, abstract, extracted_text)
        VALUES ('delete', old.id, old.title, old.authors, old.abstract, old.extracted_text);
        INSERT INTO papers_fts(rowid, title, authors, abstract, extracted_text)
        VALUES (new.id, new.title, new.authors, new.abstract, new.extracted_text);
      END
    ''');

    // Create indexes
    await db.execute('CREATE INDEX idx_papers_arxiv ON papers(arxiv_id)');
    await db.execute('CREATE INDEX idx_papers_entry ON papers(entry_id)');
    await db.execute('CREATE INDEX idx_tags_parent ON tags(parent_id)');
    await db.execute(
      'CREATE INDEX idx_paper_tags_paper ON paper_tags(paper_id)',
    );
    await db.execute('CREATE INDEX idx_paper_tags_tag ON paper_tags(tag_id)');
  }

  // ==================== Entry Operations ====================

  /// Insert a new entry
  Future<int> insertEntry(Entry entry) async {
    final db = await database;
    return await db.insert('entries', entry.toMap());
  }

  /// Get all entries
  Future<List<Entry>> getAllEntries() async {
    final db = await database;
    final maps = await db.query('entries', orderBy: 'name ASC');
    return maps.map((map) => Entry.fromMap(map)).toList();
  }

  /// Delete an entry
  Future<void> deleteEntry(int id) async {
    final db = await database;
    await db.delete('entries', where: 'id = ?', whereArgs: [id]);
  }

  /// Get entry by path
  Future<Entry?> getEntryByPath(String path) async {
    final db = await database;
    final maps = await db.query('entries',
        where: 'path = ?', whereArgs: [path], limit: 1);
    if (maps.isEmpty) return null;
    return Entry.fromMap(maps.first);
  }

  // ==================== Paper Operations ====================

  /// Insert a new paper
  Future<int> insertPaper(Paper paper) async {
    final db = await database;
    return await db.insert('papers', paper.toMap());
  }

  /// Get all papers
  Future<List<Paper>> getAllPapers() async {
    final db = await database;
    final maps = await db.query('papers', orderBy: 'added_at DESC');

    List<Paper> papers = [];
    for (final map in maps) {
      final tags = await getTagsForPaper(map['id'] as int);
      papers.add(Paper.fromMap(map, tags: tags));
    }
    return papers;
  }

  /// Get a paper by its exact title (case-insensitive)
  Future<Paper?> getPaperByTitle(String title) async {
    final db = await database;
    final maps = await db.query(
      'papers',
      where: 'LOWER(title) = ?',
      whereArgs: [title.toLowerCase()],
      limit: 1,
    );

    if (maps.isEmpty) return null;

    final id = maps.first['id'] as int;
    final tags = await getTagsForPaper(id);
    return Paper.fromMap(maps.first, tags: tags);
  }

  /// Get papers by entry
  Future<List<Paper>> getPapersByEntry(int entryId) async {
    final db = await database;
    final maps = await db.query('papers',
        where: 'entry_id = ?',
        whereArgs: [entryId],
        orderBy: 'added_at DESC');
    List<Paper> papers = [];
    for (final map in maps) {
      final tags = await getTagsForPaper(map['id'] as int);
      papers.add(Paper.fromMap(map, tags: tags));
    }
    return papers;
  }

  /// Get papers by entry and subfolder prefix
  Future<List<Paper>> getPapersByEntryAndSubfolder(
      int entryId, String subfolderPrefix) async {
    final db = await database;
    final maps = await db.query('papers',
        where: 'entry_id = ? AND file_path LIKE ?',
        whereArgs: [entryId, '$subfolderPrefix%'],
        orderBy: 'added_at DESC');
    List<Paper> papers = [];
    for (final map in maps) {
      final tags = await getTagsForPaper(map['id'] as int);
      papers.add(Paper.fromMap(map, tags: tags));
    }
    return papers;
  }

  /// Get a paper by its file path
  Future<Paper?> getPaperByFilePath(String filePath) async {
    final db = await database;
    final maps = await db.query('papers',
        where: 'file_path = ?', whereArgs: [filePath], limit: 1);
    if (maps.isEmpty) return null;
    final tags = await getTagsForPaper(maps.first['id'] as int);
    return Paper.fromMap(maps.first, tags: tags);
  }

  /// Update paper file path
  Future<void> updatePaperPath(int paperId, String newPath) async {
    final db = await database;
    await db.update('papers', {'file_path': newPath},
        where: 'id = ?', whereArgs: [paperId]);
  }

  /// Get paper counts grouped by entry
  Future<Map<int, int>> getEntryPaperCounts() async {
    final db = await database;
    final maps = await db.rawQuery(
        'SELECT entry_id, COUNT(*) as count FROM papers GROUP BY entry_id');
    return {
      for (final m in maps) m['entry_id'] as int: m['count'] as int
    };
  }

  /// Get papers by tag (including descendant tags)
  Future<List<Paper>> getPapersByTag(int tagId, {int? entryId}) async {
    final db = await database;
    String entryFilter = entryId != null ? 'AND p.entry_id = $entryId' : '';
    final maps = await db.rawQuery(
      '''
      WITH RECURSIVE descendant_tags AS (
        SELECT id FROM tags WHERE id = ?
        UNION ALL
        SELECT t.id FROM tags t
        INNER JOIN descendant_tags dt ON t.parent_id = dt.id
      )
      SELECT DISTINCT p.* FROM papers p
      INNER JOIN paper_tags pt ON p.id = pt.paper_id
      INNER JOIN descendant_tags dt ON pt.tag_id = dt.id
      WHERE 1=1 $entryFilter
      ORDER BY p.added_at DESC
    ''',
      [tagId],
    );

    List<Paper> papers = [];
    for (final map in maps) {
      final tags = await getTagsForPaper(map['id'] as int);
      papers.add(Paper.fromMap(map, tags: tags));
    }
    return papers;
  }

  /// Get untagged papers
  Future<List<Paper>> getUntaggedPapers({int? entryId}) async {
    final db = await database;
    String entryFilter = entryId != null ? 'AND p.entry_id = $entryId' : '';
    final maps = await db.rawQuery('''
      SELECT p.* FROM papers p
      LEFT JOIN paper_tags pt ON p.id = pt.paper_id
      WHERE pt.paper_id IS NULL $entryFilter
      ORDER BY p.added_at DESC
    ''');

    return maps.map((map) => Paper.fromMap(map, tags: [])).toList();
  }

  /// Search papers using FTS
  Future<List<Paper>> searchPapers(String query) async {
    final db = await database;

    // Escape apostrophes for FTS5 by doubling them
    final escapedQuery = query.replaceAll("'", "''");

    // Split by spaces, escape each word, and add wildcard
    final searchQuery = escapedQuery
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => '$w*')
        .join(' ');

    final maps = await db.rawQuery(
      '''
      SELECT p.*, bm25(papers_fts) as rank
      FROM papers p
      INNER JOIN papers_fts ON p.id = papers_fts.rowid
      WHERE papers_fts MATCH ?
      ORDER BY rank
    ''',
      [searchQuery],
    );

    List<Paper> papers = [];
    for (final map in maps) {
      final tags = await getTagsForPaper(map['id'] as int);
      papers.add(Paper.fromMap(map, tags: tags));
    }
    return papers;
  }

  /// Delete a paper
  Future<void> deletePaper(int id) async {
    final db = await database;
    await db.delete('papers', where: 'id = ?', whereArgs: [id]);
  }

  /// Update a paper
  Future<void> updatePaper(Paper paper) async {
    if (paper.id == null) {
      throw ArgumentError('Cannot update paper without an ID');
    }
    final db = await database;
    await db.update(
      'papers',
      paper.toMap(),
      where: 'id = ?',
      whereArgs: [paper.id],
    );

    // Update FTS index
    await db.rawUpdate(
      '''
      UPDATE papers_fts SET
        title = ?,
        authors = ?,
        abstract = ?,
        extracted_text = ?
      WHERE rowid = ?
      ''',
      [
        paper.title,
        paper.authors ?? '',
        paper.abstract ?? '',
        paper.extractedText ?? '',
        paper.id,
      ],
    );
  }

  /// Check if paper exists by file path
  Future<bool> paperExistsByPath(String filePath) async {
    final db = await database;
    final result = await db.query(
      'papers',
      where: 'file_path = ?',
      whereArgs: [filePath],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  /// Check which papers exist from a list of paths
  /// Returns a set of paths that already exist in the database
  Future<Set<String>> checkPapersExist(List<String> filePaths) async {
    final db = await database;
    // Split into chunks if too many parameters (SQLite limit defaults to 999)
    final existingPaths = <String>{};

    // Simple implementation: check in chunks of 500
    for (var i = 0; i < filePaths.length; i += 500) {
      final end = (i + 500 < filePaths.length) ? i + 500 : filePaths.length;
      final chunk = filePaths.sublist(i, end);

      final placeholders = List.filled(chunk.length, '?').join(',');
      final result = await db.query(
        'papers',
        columns: ['file_path'],
        where: 'file_path IN ($placeholders)',
        whereArgs: chunk,
      );

      existingPaths.addAll(result.map((row) => row['file_path'] as String));
    }

    return existingPaths;
  }

  // ==================== Tag Operations ====================

  /// Insert a new tag
  Future<int> insertTag(Tag tag) async {
    final db = await database;
    return await db.insert('tags', tag.toMap());
  }

  /// Get or create tag by name (with optional parent)
  Future<Tag> getOrCreateTag(String name, {int? parentId}) async {
    final db = await database;

    // Try to find existing tag
    final results = await db.query(
      'tags',
      where: parentId == null
          ? 'name = ? AND parent_id IS NULL'
          : 'name = ? AND parent_id = ?',
      whereArgs: parentId == null ? [name] : [name, parentId],
    );

    if (results.isNotEmpty) {
      return Tag.fromMap(results.first);
    }

    // Create new tag
    final id = await db.insert('tags', {'name': name, 'parent_id': parentId});

    return Tag(id: id, name: name, parentId: parentId);
  }

  /// Get all tags with recursive paper counts (including descendants)
  Future<List<Tag>> getAllTags() async {
    final db = await database;
    final maps = await db.rawQuery('''
      WITH RECURSIVE tag_descendants(root_id, descendant_id) AS (
        SELECT id, id FROM tags
        UNION ALL
        SELECT td.root_id, t.id
        FROM tags t
        JOIN tag_descendants td ON t.parent_id = td.descendant_id
      )
      SELECT t.*, COUNT(DISTINCT pt.paper_id) as paper_count
      FROM tags t
      LEFT JOIN tag_descendants td ON t.id = td.root_id
      LEFT JOIN paper_tags pt ON td.descendant_id = pt.tag_id
      GROUP BY t.id
      ORDER BY t.name
    ''');

    return maps.map((map) => Tag.fromMap(map)).toList();
  }

  /// Get tags as a tree structure
  Future<List<Tag>> getTagTree() async {
    final allTags = await getAllTags();

    // Build tree structure
    final Map<int?, List<Tag>> childrenMap = {};
    for (final tag in allTags) {
      childrenMap.putIfAbsent(tag.parentId, () => []).add(tag);
    }

    // Get root tags and recursively build children
    List<Tag> buildTree(int? parentId) {
      final children = childrenMap[parentId] ?? [];
      for (final tag in children) {
        tag.children.addAll(buildTree(tag.id));
      }
      return children;
    }

    return buildTree(null);
  }

  /// Get ancestors of a tag (ordered from root to leaf, including the tag itself)
  Future<List<Tag>> getTagAncestors(int tagId) async {
    final db = await database;
    final ancestors = <Tag>[];

    // First get the target tag
    var currentTagResult = await db.query(
      'tags',
      where: 'id = ?',
      whereArgs: [tagId],
    );
    if (currentTagResult.isEmpty) return [];

    var currentTag = Tag.fromMap(currentTagResult.first);
    ancestors.add(currentTag);

    // Traverse upwards
    while (currentTag.parentId != null) {
      currentTagResult = await db.query(
        'tags',
        where: 'id = ?',
        whereArgs: [currentTag.parentId],
      );
      if (currentTagResult.isEmpty) break;

      currentTag = Tag.fromMap(currentTagResult.first);
      ancestors.insert(0, currentTag); // Prepend to keep root-to-leaf order
    }

    return ancestors;
  }

  /// Get tags for a specific paper
  Future<List<Tag>> getTagsForPaper(int paperId) async {
    final db = await database;
    final maps = await db.rawQuery(
      '''
      SELECT t.* FROM tags t
      INNER JOIN paper_tags pt ON t.id = pt.tag_id
      WHERE pt.paper_id = ?
    ''',
      [paperId],
    );

    return maps.map((map) => Tag.fromMap(map)).toList();
  }

  /// Get count of untagged papers
  Future<int> getUntaggedPaperCount() async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT COUNT(*) as count FROM papers p
      LEFT JOIN paper_tags pt ON p.id = pt.paper_id
      WHERE pt.paper_id IS NULL
    ''');
    return result.first['count'] as int;
  }

  /// Delete a tag
  Future<void> deleteTag(int id) async {
    final db = await database;
    await db.delete('tags', where: 'id = ?', whereArgs: [id]);
  }

  /// Update tag name
  Future<void> updateTag(int id, String newName) async {
    final db = await database;
    await db.update(
      'tags',
      {'name': newName},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ==================== Paper-Tag Relations ====================

  /// Add tag to paper
  Future<void> addTagToPaper(int paperId, int tagId) async {
    final db = await database;
    await db.insert('paper_tags', {
      'paper_id': paperId,
      'tag_id': tagId,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  /// Remove tag from paper
  Future<void> removeTagFromPaper(int paperId, int tagId) async {
    final db = await database;
    await db.delete(
      'paper_tags',
      where: 'paper_id = ? AND tag_id = ?',
      whereArgs: [paperId, tagId],
    );
  }

  /// Set tags for a paper (replaces existing)
  Future<void> setTagsForPaper(int paperId, List<int> tagIds) async {
    final db = await database;
    await db.transaction((txn) async {
      // Remove existing tags
      await txn.delete(
        'paper_tags',
        where: 'paper_id = ?',
        whereArgs: [paperId],
      );

      // Add new tags
      for (final tagId in tagIds) {
        await txn.insert('paper_tags', {'paper_id': paperId, 'tag_id': tagId});
      }
    });
  }

  /// Search tags by name
  Future<List<Tag>> searchTags(String query) async {
    final db = await database;
    final maps = await db.rawQuery(
      '''
      SELECT t.*, COUNT(pt.paper_id) as paper_count
      FROM tags t
      LEFT JOIN paper_tags pt ON t.id = pt.tag_id
      WHERE t.name LIKE ?
      GROUP BY t.id
      ORDER BY t.name
    ''',
      ['%$query%'],
    );

    return maps.map((map) => Tag.fromMap(map)).toList();
  }

  /// Get tags related to a search result (tags of papers matching the search)
  Future<List<Tag>> getRelatedTags(String searchQuery) async {
    final db = await database;
    final query = searchQuery.split(' ').map((w) => '$w*').join(' ');

    final maps = await db.rawQuery(
      '''
      SELECT t.*, COUNT(DISTINCT pt.paper_id) as paper_count
      FROM tags t
      INNER JOIN paper_tags pt ON t.id = pt.tag_id
      INNER JOIN papers_fts ON pt.paper_id = papers_fts.rowid
      WHERE papers_fts MATCH ?
      GROUP BY t.id
      ORDER BY paper_count DESC
    ''',
      [query],
    );

    return maps.map((map) => Tag.fromMap(map)).toList();
  }

  /// Close database
  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }
}

# Coding Conventions

**Analysis Date:** 2026-04-16

## Naming Patterns

**Files:**
- Dart files use `snake_case`: `app_state.dart`, `database_service.dart`, `paper_card.dart`
- Widgets in `lib/widgets/`, services in `lib/services/`, models in `lib/models/`
- Database logic in `lib/database/`, screen components in `lib/screens/`

**Functions:**
- Public functions use `camelCase`: `extractInIsolate()`, `scanEntry()`, `fetchMetadata()`
- Private/static functions use `camelCase` with leading underscore: `_extractPdfDataSync()`, `_initDatabase()`, `_deepCast()`
- Async functions use `Future<T>` as return type: `Future<List<Paper>>`, `Future<void>`
- Boolean getters use `is` or `has` prefix: `isLoading`, `isExpanded`, `hasChanges`, `isSyncing`

**Variables:**
- Instance variables use `camelCase` with leading underscore: `_papers`, `_selectedTag`, `_db`, `_pdfService`
- Public getters expose state without underscore: `papers`, `selectedTag`, `entries`
- Local variables use `camelCase`: `diskPaths`, `dbPapers`, `themode`, `response`
- Constants use `UPPER_SNAKE_CASE` for top-level, or `static const` in classes:
  - `static const String _dbName = 'paper_suitcase.db'`
  - `static const String _baseApiUrl = 'http://export.arxiv.org/api/query'`
  - `const primaryColor = Color(0xFF007AFF)`

**Types:**
- Model classes use PascalCase: `Paper`, `Tag`, `Entry`, `ArxivMetadata`, `ChatMessage`
- Service classes use PascalCase: `PdfService`, `ArxivService`, `DatabaseService`
- Widget classes use PascalCase: `PaperCard`, `TagSidebar`, `SearchBarWidget`
- Enum values use camelCase: `PdfReaderType.embedded`, `Brightness.light`, `TitleBarStyle.hidden`

## Code Style

**Formatting:**
- Dart conventions via Flutter Lints (`package:flutter_lints/flutter.yaml`)
- Line length: standard Dart convention (follows linter)
- Indentation: 2 spaces (Dart standard)
- Imports organized in groups separated by blank lines:
  1. Dart imports: `import 'dart:io'`
  2. Package imports: `import 'package:flutter/material.dart'`
  3. Relative imports: `import '../models/paper.dart'`
- Use `as` aliases for package paths: `import 'package:path/path.dart' as p`

**Linting:**
- Tool: `flutter analyze` via Flutter Lints
- Config: `analysis_options.yaml` includes `package:flutter_lints/flutter.yaml`
- No custom linting rules enabled (all defaults)
- Suppression syntax: `// ignore: rule_name` for single line, `// ignore_for_file: rule_name` for file

## Import Organization

**Order (observed pattern):**
1. `dart:` imports (core libraries): `dart:io`, `dart:async`, `dart:convert`, `dart:isolate`
2. `package:flutter/` imports: `flutter/material.dart`, `flutter/widgets.dart`, `flutter/services.dart`
3. Other package imports: `package:provider/provider.dart`, `package:sqflite_common_ffi/sqflite_ffi.dart`
4. Third-party packages: `package:http/http.dart as http`, `package:xml/xml.dart`, `package:crypto/crypto.dart`
5. Relative imports: `import '../models/paper.dart'`, `import '../services/pdf_service.dart'`

**Path Aliases:**
- `package:path/path.dart` → aliased as `as p` for path operations
- No other path aliases configured; full relative paths used for internal imports

## Error Handling

**Patterns:**
- Try-catch with generic catch: `catch (e) { ... }`
- Nested try-catch in recursive operations: `_walkForPdfs()` has 30+ try-catch blocks for robustness
- Silent failures with null returns: `catch (_) => null` for optional operations
- Error propagation with messages: `throw Exception('Failed to search DBLP: ${response.statusCode}')`
- Print statements for non-critical errors: `print('arXiv API error: ${response.statusCode}')`
- Nullable returns for recoverable errors: functions return `T?` on failure: `Future<ArxivMetadata?>`, `Future<String?>`
- Empty list returns for collection operations: `catch (e) { return []; }`
- State-based error tracking: `String? _error` field in `AppState` with notifyListeners() on error

**Error handling in services:**
- `ArxivService`: Returns `null` or empty list on network error
- `PdfService`: Returns empty string/map on extraction failure, falls back to filename
- `EntryScannerService`: Catches file system errors, marks entry as inaccessible
- `ManifestService`: Catches JSON decode and I/O errors, returns `null` on failure
- Database operations: Use `ConflictAlgorithm.ignore` for constraint violations

## Logging

**Framework:** `print()` and `debugPrint()` from Flutter

**Patterns:**
- `debugPrint()` for initialization messages and soft errors: `debugPrint('Supabase init failed (offline mode): $e')`
- `print()` for service-level debug output: `print('arXiv API error: ...')`, `print('Error scanning all entries: ...')`
- 51 total logging calls across codebase (average ~2 per file)
- No centralized logger; logging mixed throughout services
- Error messages inline with state: `_error = 'Failed to initialize: $e'; print(_error)`
- Debug messages in try-catch blocks for non-critical failures

## Comments

**When to Comment:**
- Classes with public API: Always add doc comment explaining purpose
  - Example: `/// Service for PDF file operations`
  - Example: `/// Paper model representing a PDF document with metadata.`
- Complex algorithms: Comment non-obvious logic
  - `// Build content hash map for missing papers (potential rename sources)`
  - `// Process new paths: check for renames first`
- Regex patterns: Explain matching intent:
  - `// Pattern for arXiv IDs: YYMM.NNNNN or category/YYMMNNN`
  - `// Fallback: first line of first page`

**JSDoc/TSDoc:**
- Format: `///` for doc comments (Dart convention)
- Used consistently on classes, public methods, and complex functions
- 241 doc comment instances across 29 files
- Parameters documented with `///` above function: `/// Fetch paper metadata from arXiv API`
- Return types always specified: `Future<ArxivMetadata?>`, `String get formattedDate`

## Function Design

**Size:** Functions typically 20-100 lines; some service methods up to 200+ lines
- Single responsibility encouraged but not strictly enforced
- Complex operations (e.g., `scanEntry()`, `processNewPaper()`) span 100+ lines with multiple nested loops

**Parameters:**
- Named parameters preferred: `Future<void> saveExtractedText(String entryPath, String relativePath, String text)`
- Optional named parameters with defaults: `Future<String?> computeContentHash(String filePath)`
- Positional parameters used for required args in public APIs
- Builder callbacks for widget state: `builder: (context, child) => ...`

**Return Values:**
- Nullable returns for optional results: `Future<Paper?>`, `String?`, `int?`
- Collections default to empty rather than null: `return []`, `return <Paper>[]`
- Getters use arrow syntax for simple returns: `bool get hasChanges => newPapers.isNotEmpty || ...`
- Compound getters use full body: `String get formattedDate { ... }`

## Module Design

**Exports:**
- No barrel files (`index.dart`) used
- Each file exports its own public classes/functions
- Relative imports used throughout: `import '../models/paper.dart'`

**Model Pattern (copyWith, toMap, fromMap, toString):**
All data models implement consistent serialization:
- `toMap()` → converts to `Map<String, dynamic>` for database
- `fromMap()` → factory constructor from database row
- `copyWith()` → immutable updates with named parameters
- `toString()` → human-readable debug output

Example from `lib/models/paper.dart`:
```dart
Map<String, dynamic> toMap() {
  return {
    'id': id,
    'title': title,
    'file_path': filePath,
    // ... conditional fields
    if (syncKey != null) 'sync_key': syncKey,
  };
}

factory Paper.fromMap(Map<String, dynamic> map, {List<Tag>? tags}) {
  return Paper(
    id: map['id'] as int?,
    title: map['title'] as String,
    // ... type-safe extraction
  );
}

Paper copyWith({
  String? title,
  String? filePath,
  // ... named parameters
}) {
  return Paper(
    title: title ?? this.title,
    // ... fallback to existing
  );
}
```

**Service Pattern:**
Services are stateless utility classes with:
- Public static methods and constants: `static Future<String?> parseArxivId()`
- No constructor initialization needed
- Instance methods for stateful services: `class EntryScannerService { EntryScannerService(this._db, this._pdfService); }`
- Dependency injection via constructor for database/service dependencies

Example: `lib/services/manifest_service.dart`
```dart
class ManifestService {
  static const String _cacheDir = '.papersuitcase';
  
  static String cachePath(String entryPath) => ...
  static Future<String?> computeContentHash(String filePath) async { ... }
}
```

## State Management

**Pattern:** Single `AppState` class extending `ChangeNotifier` (provider pattern)
- All app state centralized in `lib/providers/app_state.dart`
- Private fields with underscore: `List<Paper> _papers`
- Public getter accessors: `List<Paper> get papers => _papers`
- `notifyListeners()` called after state mutations
- No Riverpod or other state management

**Widget Pattern:**
- StatelessWidget for pure UI: `class PaperCard extends StatefulWidget`
- StatefulWidget for interactive components
- Local state with `setState()`: `_loadThumbnail()` sets `_thumbnailPath`
- Provider watch for app state: `context.watch<AppState>().papers`
- Provider read for one-time access: `context.read<AppState>().scanAllEntries()`

---

*Convention analysis: 2026-04-16*

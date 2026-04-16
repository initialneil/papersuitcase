# Testing Patterns

**Analysis Date:** 2026-04-16

## Test Framework

**Runner:**
- `flutter_test` (built-in Flutter testing framework)
- Version: included in Flutter SDK (Dart ^3.10.1)
- Config: `test/widget_test.dart` is the only test file

**Assertion Library:**
- Flutter's built-in `expect()` function: `expect(actual, matcher)`
- Matchers: `equals()`, `isTrue`, `isFalse`, `isNull`, `isNotNull`, `greaterThan()`, `contains()`

**Run Commands:**
```bash
flutter test                    # Run all tests
flutter test test/widget_test.dart  # Run specific test file
flutter test --coverage         # Run with coverage report
```

## Test File Organization

**Location:**
- Single test file: `test/widget_test.dart`
- Co-located with source code in `lib/` (not implemented)
- No separate `test/` directory structure for organized tests

**Naming:**
- File: `widget_test.dart` (standard Flutter convention)
- Test functions: `testWidgets('App smoke test', ...)` (descriptive names)

**Structure:**
```
test/
└── widget_test.dart          # Single widget test (currently disabled)
```

## Test Structure

**Suite Organization:**
```dart
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Pump widget
    await tester.pumpWidget(const PaperSuitcaseApp());
    // Assert expected behavior
  });
}
```

**Patterns:**
- `void main()` as entry point
- `testWidgets('description', (WidgetTester tester) async { ... })` for widget tests
- No setUp/tearDown lifecycle methods currently used
- No test grouping with `group()` function

## Test Coverage

**Requirements:** Not enforced
- No coverage threshold configured
- No CI/CD test execution configured
- Tests commented out due to FFI mocking requirements

**Current Status:**
- Widget test commented out with explanation:
  ```dart
  void main() {
    testWidgets('App smoke test', (WidgetTester tester) async {
      // Test pumps the widget.
      // Commented out as it requires mocking FFI and MethodChannels for sqflite and window_manager
      // await tester.pumpWidget(const PaperSuitcaseApp());
    });
  }
  ```

## Mocking

**Framework:** None currently configured
- Would require: `mockito` or `mocktail` package (not in dependencies)
- Manual mocking needed for:
  - `sqflite_common_ffi`: Database FFI layer
  - `window_manager`: Native window management (MethodChannel)
  - `supabase_flutter`: Network requests
  - `http.Client`: HTTP calls for arXiv/DBLP APIs
  - File I/O operations

**What to Mock:**
- Database layer: `DatabaseService` and its SQLite operations
- External APIs: `ArxivService`, `BibtexService` HTTP requests
- File system: `File`, `Directory` operations
- Native channels: `window_manager`, `MethodChannel`

**What NOT to Mock:**
- Business logic in services and models
- State management (AppState)
- Widget build methods (use real widgets in integration tests)

## Fixtures and Factories

**Test Data:**
Not implemented. Would follow patterns like:
```dart
// Hypothetical fixture for Paper model
Paper samplePaper() {
  return Paper(
    id: 1,
    title: 'Sample Paper',
    filePath: 'test/fixtures/sample.pdf',
    entryId: 1,
    addedAt: DateTime.now(),
  );
}
```

**Location:**
- Would live in `test/fixtures/` or `test/factories/` directory
- Or co-located in test files using factory functions

## Test Types

**Unit Tests:**
- Not implemented
- Would test service classes:
  - `ArxivService.parseArxivId()` with various URL formats
  - `ManifestService` file operations and hashing
  - `BibtexService` DBLP/ACM parsing
  - Model factories: `Paper.fromMap()`, `Tag.copyWith()`
- Scope: Pure functions, data transformations, parsing logic

**Integration Tests:**
- Not implemented
- Would test:
  - `DatabaseService` SQLite operations with real database
  - `EntryScannerService.scanEntry()` with test directory structure
  - `PdfService.extractInIsolate()` with test PDF files
  - State management with full dependency graph

**Widget Tests:**
- Single test file: `test/widget_test.dart`
- Currently disabled due to FFI/MethodChannel mocking requirements
- Would test:
  - `PaperCard` widget rendering and selection
  - `SearchBarWidget` input and URL detection
  - `TagSidebar` tree expansion/collapse
  - Main screen layout and navigation

**E2E Tests:**
- Not implemented
- Would require integration_test framework
- Not configured in pubspec.yaml

## Common Testing Gaps

**Areas Without Tests:**
1. **PDF Processing:** `PdfService.extractInIsolate()` and `PdfService.generateThumbnail()` - critical for core functionality
2. **Database Layer:** `DatabaseService` CRUD operations, schema migrations, FTS5 queries
3. **File System Operations:** `EntryScannerService` scanning, `ManifestService` cache management
4. **State Management:** `AppState` initialization, tag selection, navigation history
5. **External APIs:** `ArxivService.fetchMetadata()`, `BibtexService.searchDblp()` - network calls
6. **Sync Logic:** `SyncService` bidirectional sync operations
7. **Widget Interactions:** `PaperCard` selection, `PaperGrid` filtering, context menus

**Why Tests Are Disabled:**
The single widget test in `test/widget_test.dart` is commented out because:
1. `sqflite_common_ffi` requires FFI initialization on desktop platforms
2. `window_manager` uses MethodChannels that need native platform mocking
3. No FFI/MethodChannel mocking setup exists in the project
4. Full app initialization would require mocking database, Supabase, file system

## How to Enable Testing

**To implement unit tests:**
1. Add test dependencies to `pubspec.yaml`:
   ```yaml
   dev_dependencies:
     test: ^1.25.0
     mockito: ^5.0.0
   ```
2. Create test files in `test/` matching service structure
3. Mock external dependencies (HTTP, file I/O, database)

**To implement widget tests:**
1. Mock FFI for sqflite:
   ```dart
   setUpAll(() {
     sqfliteFfiInit();
     databaseFactory = databaseFactoryFfiNoIsolate;
   });
   ```
2. Mock MethodChannels:
   ```dart
   TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
       .setMockMethodCallHandler(...);
   ```
3. Create test stubs for `Supabase` and other services

**To implement E2E tests:**
1. Add `integration_test` to dev_dependencies
2. Create `integration_test/app_test.dart`
3. Use real database and file system in tests

---

*Testing analysis: 2026-04-16*

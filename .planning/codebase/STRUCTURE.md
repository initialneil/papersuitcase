# Codebase Structure

**Analysis Date:** 2026-04-16

## Directory Layout

```
lib/
├── main.dart                          # App entry point, window setup, theme
├── providers/
│   └── app_state.dart                 # Central ChangeNotifier state (all app state)
├── screens/
│   └── main_screen.dart               # Main UI layout: sidebar + content + viewer
├── widgets/                           # Reusable UI components
│   ├── auth_screen.dart               # Login/signup with email, Google, GitHub
│   ├── bibtex_import_dialog.dart      # BibTeX file import dialog
│   ├── bibtex_manager.dart            # BibTeX management UI
│   ├── bibtex_panel.dart              # Inline bibtex editor
│   ├── discover_tab.dart              # Trending/recommendations tab
│   ├── download_dialog.dart           # arXiv paper download dialog
│   ├── drop_zone.dart                 # Drag-and-drop import zone
│   ├── edit_tags_dialog.dart          # Tag selection/creation dialog
│   ├── embedded_pdf_viewer.dart       # In-app PDF viewer (Syncfusion)
│   ├── entry_sidebar_section.dart     # Entry list in sidebar with actions
│   ├── paper_card.dart                # Single paper card (grid item)
│   ├── paper_chat_panel.dart          # Chat-with-paper sidebar
│   ├── paper_grid.dart                # Grid of paper cards
│   ├── search_bar.dart                # Search input with FTS
│   ├── settings_view.dart             # Settings/preferences UI
│   ├── tag_cards.dart                 # Tag chips display
│   ├── tag_sidebar.dart               # Left sidebar with tags + entries
│   └── tag_sidebar_section.dart       # Hierarchical tag tree in sidebar
├── services/
│   ├── arxiv_service.dart             # arXiv API queries (metadata, download)
│   ├── bibtex_service.dart            # BibTeX string parsing → Paper object
│   ├── entry_scanner_service.dart     # Detect new/removed/renamed PDFs via hashing
│   ├── llm_chat_service.dart          # Chat-with-paper via Supabase Edge Functions
│   ├── manifest_service.dart          # .papersuitcase/ cache management
│   ├── pdf_service.dart               # PDF extraction (isolates) + file operations
│   ├── recommendation_service.dart    # Trending/discover from Supabase
│   ├── supabase_service.dart          # Static auth/client wrapper
│   └── sync_service.dart              # Unidirectional sync (local → Supabase)
├── database/
│   └── database_service.dart          # SQLite schema, migrations, CRUD
├── models/
│   ├── paper.dart                     # Paper entity with tags list
│   ├── tag.dart                       # Tag with hierarchy (parentId, children)
│   ├── entry.dart                     # External directory reference
│   ├── chat_message.dart              # LLM chat message
│   └── settings_enums.dart            # Enums: ThemeMode, PdfReaderType
└── utils/                             # (empty)

pubspec.yaml                            # Project dependencies, Flutter config
pubspec.lock                            # Dependency lock file
```

## Directory Purposes

**lib/providers/:**
- Purpose: State management layer (single ChangeNotifier provider)
- Contains: `AppState` class with all mutable app state
- Key files: `app_state.dart` (650+ lines)

**lib/screens/:**
- Purpose: Route/layout level widgets (main app shell)
- Contains: `MainScreen` with layout routing (sidebar + content area + viewer)
- Key files: `main_screen.dart` (layout + conditional rendering)
- Note: Single file; most UI is in lib/widgets/

**lib/widgets/:**
- Purpose: Reusable, composable UI components
- Contains: 18 widget files (dialogs, panels, sidebars, cards, grids)
- Key files:
  - `tag_sidebar.dart`: Left sidebar navigation (entries + tag tree)
  - `paper_grid.dart`: Grid of papers with thumbnail cards
  - `embedded_pdf_viewer.dart`: In-app PDF viewer
  - `paper_card.dart`: Single paper card (thumbnail + metadata + actions)
  - `tag_sidebar_section.dart`: Hierarchical tag tree renderer
  - `entry_sidebar_section.dart`: Entry list with expand/collapse
- Pattern: Each widget is self-contained, reads AppState via context.watch()

**lib/services/:**
- Purpose: Domain logic and external integrations (stateless)
- Contains: 9 service classes
- Key responsibilities:
  - PDF processing: text/title extraction (isolate-based), thumbnail generation
  - File system: entry scanning (new/removed/renamed detection via hashing)
  - Cache management: Per-entry `.papersuitcase/` directories
  - Database sync: Unidirectional sync to Supabase
  - External APIs: arXiv XML queries, Supabase auth/Edge Functions
  - File parsing: BibTeX string → Paper model

**lib/database/:**
- Purpose: SQLite persistence layer
- Contains: `DatabaseService` with schema, migrations, CRUD
- Key concepts:
  - Tables: entries, papers, tags, paper_tags, papers_fts (virtual)
  - Indexes: On foreign keys, arxiv_id, parent_id
  - Schema version: Currently v6 with migration support
  - FTS5: Full-text search on papers table with BM25 ranking
  - Triggers: Auto-update FTS on papers INSERT/UPDATE/DELETE

**lib/models/:**
- Purpose: Type-safe value objects and domain models
- Contains: 5 model files (Paper, Tag, Entry, ChatMessage, enums)
- Pattern: toMap/fromMap for serialization, copyWith for immutability
- Key properties:
  - Paper: id, title, filePath (relative), entryId, arxivId, bibtex, dirty (sync flag)
  - Tag: id, name, parentId (hierarchy), paperCount, children (runtime), isExpanded (runtime)
  - Entry: id, path (absolute), name, isExpanded (runtime), isAccessible, paperCount, subfolderCounts

## Key File Locations

**Entry Points:**
- `lib/main.dart`: App startup, window init, theme setup, root widget
- `lib/screens/main_screen.dart`: Main layout and routing logic
- `lib/providers/app_state.dart`: State initialization and lifecycle

**Configuration:**
- `pubspec.yaml`: Dependencies and project metadata

**Core Logic:**
- `lib/database/database_service.dart`: SQLite schema v6, CRUD operations
- `lib/providers/app_state.dart`: Central state container (650+ lines)
- `lib/services/entry_scanner_service.dart`: Entry scanning and change detection
- `lib/services/manifest_service.dart`: Cache directory management

**Testing:**
- Not detected in codebase (test/ directory does not exist)

## Naming Conventions

**Files:**
- Snake_case: `paper_grid.dart`, `entry_scanner_service.dart`, `database_service.dart`
- Classes: PascalCase: `PaperCard`, `AppState`, `DatabaseService`
- Private classes: `_MainScreenState`, `_TitleBar` (underscore prefix)

**Directories:**
- Snake_case: `lib/widgets/`, `lib/services/`, `lib/models/`, `lib/providers/`
- Organized by layer/concern (not by feature)

**Dart Code:**
- Fields: camelCase with underscore prefix for private: `_papers`, `_selectedTag`, `_db`
- Methods: camelCase: `scanAllEntries()`, `viewPaper()`, `setSearchQuery()`
- Constants: camelCase or UPPER_CASE: `_cacheDir`, `_dbName`, `primaryColor`
- Getters: camelCase: `papers`, `isLoading`, `selectedTag`

**Database:**
- Tables: snake_case: `papers`, `tags`, `entries`, `paper_tags`, `papers_fts`
- Columns: snake_case: `file_path`, `entry_id`, `parent_id`, `arxiv_id`, `added_at`
- Indexes: Prefixed `idx_`: `idx_papers_arxiv`, `idx_tags_parent`

**Services:**
- Pattern: CamelCaseService (stateless): `PdfService`, `ArxivService`, `DatabaseService`
- Static utilities: PdfService.isPdf(), ManifestService.fileKey()

## Where to Add New Code

**New Feature (e.g., annotations/highlighting):**
- Primary logic: `lib/services/` (new service class, e.g., `annotation_service.dart`)
- Database: Add schema in `lib/database/database_service.dart` (new table + migration)
- UI components: `lib/widgets/` (new widget files for UI)
- State: Add fields to `AppState` in `lib/providers/app_state.dart` (getter/setter methods)
- Models: New model in `lib/models/` (e.g., `annotation.dart`)

**New Component/Module:**
- Implementation: Place in appropriate directory (`lib/widgets/` for UI, `lib/services/` for logic)
- Naming: Follow convention (snake_case files, PascalCase classes)
- Example: New entry editor would go in `lib/widgets/entry_editor.dart`
- AppState integration: Add methods to handle component state

**Utilities:**
- Shared helpers: `lib/utils/` (currently empty, use for helper functions)
- Service utilities: Keep within service file or create extension file
- Example: File utilities should go in `lib/services/file_utils.dart`

**Tests:**
- Location: Create `test/` directory at project root
- Pattern: Mirror lib/ structure: `test/widgets/`, `test/services/`, `test/models/`
- Naming: `{file}_test.dart` (e.g., `paper_card_test.dart`)
- Framework: flutter_test (included in dev_dependencies)

## Special Directories

**.papersuitcase/ (Per-entry Cache):**
- Purpose: Cache directory inside each entry folder
- Generated: Yes (created by `ManifestService`)
- Committed: No (git-ignored)
- Contents:
  - `manifest.json`: Metadata for papers in entry (title, authors, arxiv_id, bibtex, tags, added_at)
  - `thumbnails/`: Paper preview images (PNG, named by file key SHA1)
  - `texts/`: Extracted text cache (TXT, named by file key SHA1)
  - `references.bib`: Combined BibTeX for all papers in entry
- Key concept: Files named by SHA1 hash of relative path (first 12 chars) to decouple from actual paper filenames

**SQLite Database:**
- Location: `~/Library/Application Support/paper_suitcase.db` (macOS)
- Generated: Yes (on first run)
- Committed: No (local data, not in git)
- Schema version: 6 (with auto-migration)

**SharedPreferences:**
- Purpose: App settings and UI state
- Stored in: macOS system preferences (platform-specific)
- Contains: Theme, PDF reader type, custom PDF app path, last viewed tag

## Dependencies Organization

**Core Flutter:**
- `flutter`, `flutter_lints`

**Database:**
- `sqflite_common_ffi` (SQLite for desktop)
- `path`, `path_provider` (file system)

**PDF Handling:**
- `syncfusion_flutter_pdf` (extraction)
- `syncfusion_flutter_pdfviewer` (viewer)
- `pdf_render` (rendering)
- `image` (image encoding)

**State Management:**
- `provider` (ChangeNotifier)

**Desktop UI:**
- `window_manager` (custom title bar, window control)
- `desktop_drop` (drag-and-drop)

**External APIs & Auth:**
- `http` (arXiv API)
- `xml` (arXiv XML parsing)
- `supabase_flutter` (auth, sync, Edge Functions)

**Utilities:**
- `shared_preferences` (local settings)
- `package_info_plus` (version info)
- `file_selector` (file picker dialogs)
- `url_launcher` (open URLs)
- `crypto` (SHA1/SHA256 hashing)
- `html_unescape` (HTML entity decoding)
- `cupertino_icons` (macOS icons)

---

*Structure analysis: 2026-04-16*

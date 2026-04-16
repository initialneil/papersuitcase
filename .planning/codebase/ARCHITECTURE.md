# Architecture

**Analysis Date:** 2026-04-16

## Pattern Overview

**Overall:** Layered single-state ChangeNotifier with local-first persistence

**Key Characteristics:**
- **Centralized state:** Single `AppState` managed via `provider` ChangeNotifier holds all app state (papers, tags, entries, navigation, UI state, settings, sync, auth)
- **Local-first data:** All persistent data stored in SQLite (`sqflite_common_ffi`) with optional cloud sync to Supabase
- **Desktop-focused:** Custom title bar, macOS window management, desktop file operations (no mobile considerations)
- **Symlink-only entries:** Papers always exist in external directories; entry scanning detects new/removed/renamed PDFs via hash-based rename detection
- **Service layer:** Stateless services handle specific concerns (PDF extraction, arXiv lookup, Supabase sync, manifest/cache management)
- **UI-driven scanning:** Auto-scanning triggers on window focus (10-second debounce), on-demand rescans via AppState methods

## Layers

**Presentation Layer (Widgets):**
- Purpose: Flutter widget hierarchy for macOS-style UI
- Location: `lib/widgets/`, `lib/screens/`
- Contains: StatefulWidget implementations, dialog components, UI state per widget
- Depends on: AppState (via `context.watch()` / `context.read()`), models, services for file operations
- Used by: Flutter framework, MaterialApp

**State Management Layer (AppState):**
- Purpose: Single source of truth for entire app state
- Location: `lib/providers/app_state.dart`
- Contains: Papers, tags, entries, navigation history, auth state, sync state, recommendations, UI toggles (viewingPaper, isConfigMode, etc.)
- Depends on: DatabaseService, all service classes (PdfService, ArxivService, EntryScannerService, SyncService, SupabaseService, etc.)
- Used by: All widgets via `context.watch<AppState>()`
- Note: Single ChangeNotifier — no Riverpod or segmented providers. All mutations via AppState methods.

**Service Layer:**
- Purpose: Encapsulate domain logic and external integrations
- Location: `lib/services/`
- Contains: PDF processing, arXiv API, entry scanning, Supabase sync, manifest/cache, bibtex parsing, LLM chat, recommendations
- Dependencies:
  - `PdfService`: Syncfusion PDF extraction in isolates (CPU-intensive)
  - `ArxivService`: arXiv XML API queries
  - `EntryScannerService`: Detects new/removed/renamed PDFs via hash-based comparison
  - `ManifestService`: Per-entry `.papersuitcase/` cache (thumbnails, extracted text, manifest.json, references.bib)
  - `BibtexService`: BibTeX string → Paper object parsing
  - `SyncService`: Unidirectional sync (local → Supabase) for papers, tags, associations
  - `SupabaseService`: Static auth/client wrapper (email/password, OAuth, profile fetch)
  - `LlmChatService`: Chat-with-paper Edge Functions
  - `RecommendationService`: Trending/discover recommendations via Supabase

**Data Access Layer (DatabaseService):**
- Purpose: SQLite persistence with manual migrations
- Location: `lib/database/database_service.dart`
- Contains: Schema (v6), CRUD methods for papers/tags/entries, FTS5 virtual table
- Depends on: `sqflite_common_ffi` (FFI-based SQLite for desktop)
- Used by: AppState, EntryScannerService, SyncService

**Models (Value Objects):**
- Purpose: Type-safe data representation
- Location: `lib/models/`
- Contains: `Paper` (with tags list), `Tag` (hierarchical), `Entry` (external directory ref), `ChatMessage`, `SettingsEnums`
- Pattern: toMap/fromMap serialization for DB, copyWith for immutability

## Data Flow

**App Startup Flow:**

1. `main()` initializes:
   - Window manager for custom title bar
   - Supabase service (optional, falls back to offline)
   - AppState via `ChangeNotifierProvider`
2. `AppState.initialize()` called:
   - Opens local SQLite database
   - Loads entries from DB
   - Loads tags with hierarchy
   - Triggers first `scanAllEntries()` (detects new PDFs)
   - Restores last viewed tag/search
   - Checks auth state via Supabase
3. Presentation layer renders `MainScreen`

**Paper Import Flow (Drag-and-Drop or Scan):**

1. User drags PDF(s) into `DropZone` widget or window refocuses
2. `EntryScannerService.scanEntry()` called:
   - Walks entry directory for `.pdf` files
   - Compares disk PDFs against DB papers (by path)
   - Detects renames via content hash (SHA256 of first 64KB)
   - Returns `ScanResult` (new, removed, renamed)
3. `AppState.scanAllEntries()` processes results:
   - For each new paper: `EntryScannerService.processNewPaper()`
     - Extracts title + text in background isolate (via `PdfService.extractInIsolate`)
     - Generates thumbnail (lazy, on demand by UI)
     - Saves extracted text cache
     - Generates content hash
   - Updates database
   - Notifies listeners

**Paper Search Flow:**

1. User types in search bar → `AppState.setSearchQuery()`
2. AppState queries FTS5 virtual table `papers_fts` with BM25 ranking
3. FTS kept in sync via SQL triggers on papers table (INSERT/UPDATE/DELETE)
4. Results re-render `PaperGrid`

**Viewing Paper Flow:**

1. User double-clicks paper card or selects and presses Enter
2. `AppState.viewPaper(paper)` sets `_viewingPaper` and opens `EmbeddedPdfViewer`
3. EmbeddedPdfViewer uses `syncfusion_flutter_pdfviewer` to render PDF in-app
4. Optional: `PaperChatPanel` opens if user logged in and toggles chat
5. `AppState.closePaperViewer()` clears `_viewingPaper`

**Cloud Sync Flow (if authenticated):**

1. User logs in via `AuthScreen` → Supabase email/password or OAuth
2. `AppState` initializes `SyncService`
3. On demand: `AppState.syncWithCloud()` triggers unidirectional sync:
   - Syncs dirty tags to `user_tags` table
   - Syncs dirty papers to `user_papers` table (via sync_key)
   - Syncs tag associations to `user_paper_tags` table
   - Marks synced records as clean (`dirty = 0`)
4. Incoming: Recommendations/trending computed server-side via Edge Functions
5. Chat: Paper Q&A via `chat-with-paper` Edge Function (LLM response)

**Navigation History Flow:**

1. Each tag/entry/search selection pushes `_NavigationState` to `_history`
2. Back/Forward buttons pop/push on `_historyIndex`
3. `_isNavigatingHistory` prevents re-pushing during navigation

**State Notification:**

- `AppState extends ChangeNotifier`
- All mutations call `notifyListeners()`
- Widgets watch with `context.watch<AppState>()` or read with `context.read<AppState>()`

## Key Abstractions

**Paper:**
- Purpose: Core document entity
- Location: `lib/models/paper.dart`
- Properties: id, title, filePath (relative to entry), entryId (FK), authors, abstract, extractedText, arxivId, bibtex, bibStatus ('none'/'imported'/'manual'), contentHash (for rename detection), syncKey (composite: arxiv/hash/title), remoteId, dirty flag
- Pattern: toMap/fromMap for serialization, copyWith for safe updates
- Relationships: Holds List<Tag> tags (loaded from paper_tags junction table)

**Tag (Hierarchical):**
- Purpose: Category/topic grouping
- Location: `lib/models/tag.dart`
- Properties: id, name, parentId (self-referencing for hierarchy), paperCount, children (runtime), isExpanded (runtime UI state)
- Special case: `Tag.untagged()` for papers without tags (id = -1, not persisted)
- Pattern: toMap/fromMap, copyWith
- Relationships: Tree structure via parentId + children list

**Entry (External Directory Reference):**
- Purpose: Root folder containing PDF files
- Location: `lib/models/entry.dart`
- Properties: id, path (absolute), name, addedAt, isExpanded (runtime), isAccessible (if dir exists), paperCount, subfolderCounts (Map<relativePath, count>)
- Pattern: One-to-many relationship with papers (via paper.entryId)
- Manifest: Entry has `.papersuitcase/` cache directory with manifest.json (metadata for papers), thumbnails/, texts/ (extracted text cache), references.bib

**ChatMessage:**
- Purpose: LLM chat message model
- Location: `lib/models/chat_message.dart`
- Properties: id, paperId, role ('user'/'assistant'), content, createdAt
- Pattern: In-memory storage (AppState._chatHistories)

**EntryScannerService:**
- Purpose: Detect changes in entry directories
- Methods:
  - `scanAllEntries()` — scan all entries, return list of ScanResult
  - `scanEntry(entry)` — scan single entry, detect new/removed/renamed PDFs
  - `processNewPaper()` — extract metadata, generate thumbnail, cache text
- Rename detection: Hash-based (SHA256 of first 64KB)
- Manifest sync: Updates .papersuitcase/manifest.json per entry
- Optimization: Skips bibtex/manifest updates during bulk scans (batch at end)

**ManifestService:**
- Purpose: Manage per-entry `.papersuitcase/` cache
- Key concepts:
  - File key: SHA1 hash of relative path (first 12 chars) used for cache filenames
  - Content hash: SHA256 of first 64KB used for rename detection
  - Thumbnails stored as: `.papersuitcase/thumbnails/{fileKey}.png`
  - Extracted text stored as: `.papersuitcase/texts/{fileKey}.txt`
  - Manifest: `.papersuitcase/manifest.json` with paper metadata, arxiv_id, bibtex, tags, etc.
  - Lock mechanism: Per-entry path serialization to prevent concurrent writes

**SyncService:**
- Purpose: Unidirectional sync (local → Supabase)
- Flow: Tags → Papers → Deletions → Tag associations
- Sync keys: Used to match papers across devices (arxiv_id > contentHash > title-hash)
- Progress callback: Reports (current, total, phase) for UI feedback
- Result: SyncResult with counts or error

## Entry Points

**main.dart:**
- Location: `lib/main.dart`
- Triggers: Flutter app startup
- Responsibilities:
  - Initialize window manager (macOS custom title bar)
  - Initialize Supabase (catch offline)
  - Create AppState via ChangeNotifierProvider
  - Render MaterialApp with theme
- UI structure: Custom _TitleBar + MainScreen

**MainScreen:**
- Location: `lib/screens/main_screen.dart`
- Triggers: After auth check
- Responsibilities:
  - Route to AuthScreen (if not logged in/skipped) or main content
  - Main layout: TagSidebar (left) + content area (center) + optional PDF viewer + chat panel (right)
  - Show DiscoverTab (if showDiscover), EmbeddedPdfViewer (if viewingPaper), SettingsView (if isConfigMode), or _MainContent (default)
  - Handle keyboard shortcuts (Escape to close viewer, Cmd+W to close window)

**AppState.initialize():**
- Location: `lib/providers/app_state.dart`
- Triggers: On app startup (via ChangeNotifierProvider create)
- Responsibilities:
  - Open database
  - Load entries, tags, papers from SQLite
  - Trigger scanAllEntries() (detect new PDFs)
  - Setup EntryScannerService
  - Check auth state
  - Initialize sync service if logged in
  - Load user profile

## Error Handling

**Strategy:** Try-catch with silent fallbacks and user-facing error toasts

**Patterns:**
- PDF extraction: Returns default title (filename) if parsing fails
- Thumbnail generation: Skipped if timeout (3s) or error; lazy-generated on demand by UI
- arXiv lookup: Fails silently; title remains unchanged
- Supabase operations: Marked as dirty, can retry on next sync
- File operations: Check existence before read/write; handle missing entry directories gracefully
- Database: Transactions for multi-step operations (e.g., paper insert + manifest update)

## Cross-Cutting Concerns

**Logging:** 
- Pattern: `debugPrint()` for app-level events, service errors
- No centralized logger; stderr output for CLI debugging

**Validation:**
- PDF detection: `PdfService.isPdf()` (extension check)
- File existence: Check before operations
- Database constraints: Foreign keys (papers.entry_id → entries.id), unique constraints (papers.file_path, tags.name+parent_id)
- Schema version: Database v6 with migration tracking

**Authentication:**
- Provider: Supabase (email/password, Google OAuth, GitHub OAuth)
- State: `AppState._currentUser` (null = offline/unauthenticated)
- Optional: Users can skip auth and work offline with local papers only
- Sync: Only enabled for logged-in users

**Theme:**
- System: Light/Dark mode via `ThemeMode`
- Storage: Persisted in SharedPreferences
- macOS style: SF Pro Display font, custom color scheme, rounded buttons

---

*Architecture analysis: 2026-04-16*

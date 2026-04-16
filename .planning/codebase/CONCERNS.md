# Codebase Concerns

**Analysis Date:** 2026-04-16

## Tech Debt

**Monolithic AppState Provider:**
- Issue: `AppState` is 1317 lines with 100+ methods and 70+ state fields managing papers, tags, entries, sync, auth, chat, recommendations, and UI state all in one class. This violates single responsibility principle and makes testing/debugging difficult.
- Files: `lib/providers/app_state.dart`
- Impact: 
  - Hard to locate state mutations (scattered across methods)
  - Difficult to reason about state dependencies
  - Notifier fires too frequently, causing unnecessary widget rebuilds
  - Future feature additions (e.g., nested tagging) will further bloat this class
- Fix approach: Split into domain-specific providers (PaperProvider, TagProvider, AuthProvider, SyncProvider, ChatProvider, RecommendationProvider) using Riverpod or multiple ChangeNotifier classes. Consider using StateNotifier for complex state logic.

**N+1 Query Pattern in Database Operations:**
- Issue: Every time papers are fetched (`getAllPapers`, `getPapersByEntry`, `searchPapers`, etc.), tags are loaded separately for each paper via `getTagsForPaper(map['id'])` in a loop, causing one query per paper.
- Files: `lib/database/database_service.dart` (lines 249-256, 279-288, 300-304, 356-360, 402-407)
- Impact: 
  - With 1000 papers, 1000+ SQL queries occur for a single `getAllPapers()` call
  - Significant performance degradation on large libraries
  - Noticeable UI lag during list rendering
- Fix approach: Use a single JOIN query to fetch papers with tags in one pass, or use raw SQL INNER JOIN to `paper_tags` and aggregate tags by paper_id in Dart.

**FTS5 Triggers Always Update on Paper Changes:**
- Issue: Every paper update triggers full FTS row delete + reinsert (lines 133-139 in database_service.dart), even when only one field changes.
- Files: `lib/database/database_service.dart` (FTS triggers)
- Impact: Unnecessary disk writes and slower updates for frequently modified papers (e.g., adding tags)
- Fix approach: Only update FTS when searchable fields (title, authors, abstract, extracted_text) actually change.

**Manual Database Migration Management:**
- Issue: Version bumping (currently v6) requires manually writing ALTER TABLE statements in `_onUpgrade`. No automated schema generation or migration framework.
- Files: `lib/database/database_service.dart` (lines 151-162)
- Impact: 
  - Easy to introduce migration bugs (missing columns, wrong types)
  - Hard to test migrations (no rollback)
  - Future version upgrades are error-prone
- Fix approach: Consider using `drift` package (if moving away from manual sqflite) or document migration procedure clearly with validation checks.

**Bare `print()` Calls Instead of Structured Logging:**
- Issue: 619 occurrences of `print()`, `debugPrint()`, and `throw` across codebase without consistent error handling or logging levels. Production builds will lose all debugging information.
- Files: All service files, widgets (e.g., `lib/providers/app_state.dart` line 227, `lib/services/entry_scanner_service.dart` lines 50, 159)
- Impact: 
  - Difficult to diagnose issues in production
  - No log rotation or persistence
  - No error categorization (network errors vs. file errors)
- Fix approach: Implement structured logging with severity levels (info, warn, error) and persistence to disk for crash analysis. Use a logger package (e.g., `logger` or `talker`).

**Fire-and-Forget Background Processing Without Error Visibility:**
- Issue: `_processNewPapersBackground` and background manifest updates fire without awaiting or user feedback on failures. Errors are only logged to console.
- Files: `lib/providers/app_state.dart` (lines 522-557, 548-551), `lib/services/entry_scanner_service.dart` (lines 194-212)
- Impact: 
  - Users don't know when text extraction or thumbnail generation fails
  - Silent data loss (papers processed but never persisted)
  - Difficult to debug "missing" papers
- Fix approach: Track processing status in AppState (e.g., `processingErrors` map) and surface failures in UI (e.g., toast notifications or error panel).

**Syncfusion License Tracking:**
- Issue: `syncfusion_flutter_pdf` v24.2.8 requires license registration. No license key is configured in the app.
- Files: `lib/services/pdf_service.dart`, `pubspec.yaml`
- Impact: May trigger licensing warnings or limitations in production. PDF text extraction may degrade or require user interaction.
- Fix approach: Verify Syncfusion licensing terms and either register a valid license key or consider open-source alternatives (e.g., `pdf` package + native PDF.js).

## Known Bugs

**Manifest Lock Mechanism is Incomplete:**
- Symptoms: `_withLock` in `ManifestService` only queues operations but doesn't prevent concurrent file I/O on the same entry path if called from different app instances or crash during write.
- Files: `lib/services/manifest_service.dart` (lines 115-126)
- Trigger: Multiple fast operations on manifest (e.g., add paper + update manifest simultaneously)
- Workaround: Manifest write is atomic (single `writeAsString`) so partial corruption unlikely, but multiple instances of the app could cause race conditions.
- Fix: Add filesystem locking (e.g., `.lock` file) instead of in-memory locks.

**FTS5 Virtual Table Not Re-synchronized on Upgrade:**
- Symptoms: Papers added before v6 migration may not appear in search results if FTS is out of sync.
- Files: `lib/database/database_service.dart` (lines 151-162), `lib/services/pdf_service.dart`
- Trigger: Upgrade from pre-v6 database with existing papers
- Workaround: Manual rebuild by re-extracting all paper text (slow but not exposed in UI)
- Fix: Add FTS rebuild step in `_onUpgrade` to re-populate FTS table for existing papers.

**Renamed Paper Path Update Doesn't Clear Old Manifest Entries:**
- Symptoms: When a PDF is detected as renamed (content hash match), old manifest entry is removed but new entry might not be immediately written, causing temporary inconsistency.
- Files: `lib/services/entry_scanner_service.dart` (lines 108-119)
- Trigger: Rename detected, manifest removed, but manifest write deferred
- Workaround: Manifest is eventually written in batch update
- Fix: Write manifest atomically after rename detection before continuing scan.

**BibTeX Rate Limiting Not Enforced:**
- Symptoms: Bulk paper import can trigger 429 rate limits from DBLP without backoff, causing silent BibTeX fetch failures.
- Files: `lib/services/entry_scanner_service.dart` (lines 232-242)
- Trigger: Import 100+ papers with `skipBibtex=false`
- Workaround: Set `skipBibtex=true` during bulk import, fetch BibTeX manually later
- Fix: Implement exponential backoff or queue BibTeX requests to stagger them over time.

**Embedded PDF Viewer Lifecycle Issues:**
- Symptoms: Opening/closing multiple PDF tabs rapidly can cause memory leaks or widget state inconsistencies.
- Files: `lib/widgets/embedded_pdf_viewer.dart`, `lib/providers/app_state.dart` (lines 813-845)
- Trigger: Rapid double-click on paper cards
- Workaround: Close previous tab before opening new one
- Fix: Add dispose cleanup for PDF viewer instances and debounce rapid opens.

## Security Considerations

**Supabase Anonymous Key Exposed in Source Code:**
- Risk: The Supabase anonymous key is hardcoded in `supabase_service.dart` and will be embedded in the macOS app binary. This key is technically meant to be public (for client-side code), but still represents a surface for abuse.
- Files: `lib/services/supabase_service.dart` (lines 5-6)
- Current mitigation: Key appears to be role-limited on Supabase backend (read/write only to user-owned data). OAuth is preferred for sensitive operations.
- Recommendations: 
  - Ensure Supabase RLS (Row-Level Security) policies strictly enforce user ownership
  - Monitor for suspicious API usage patterns
  - Consider moving sensitive API calls (sync, chat) to Edge Functions with server-side verification

**Local SQLite Database Not Encrypted:**
- Risk: SQLite database stored in unencrypted local filesystem. Sensitive data (papers, tags, extracted text) is readable by any user/process with file access.
- Files: `lib/database/database_service.dart` (line 33)
- Current mitigation: macOS sandbox (if app is signed) provides some filesystem isolation
- Recommendations:
  - Use `sqflite_common_ffi` with encryption (requires using `sqlcipher` backend)
  - Or encrypt sensitive fields at rest (title, abstract, bibtex)
  - Document that local data is not encrypted

**Extracted PDF Text Stored Unencrypted:**
- Risk: Full-text extracted from PDFs is stored as plaintext in `.papersuitcase/texts/*.txt` files.
- Files: `lib/services/manifest_service.dart` (lines 58-72), `lib/services/entry_scanner_service.dart` (lines 206-213)
- Current mitigation: Files are in user-owned `.papersuitcase` directory, not world-readable
- Recommendations: Consider encrypting extracted text files, especially if PDFs contain sensitive content (unpublished research, private notes).

**Path Traversal Vulnerability in PDF File Walking:**
- Risk: `_walkForPdfs` recursively lists entry directories without validating resolved paths. Symlinks could theoretically point outside the entry directory.
- Files: `lib/services/entry_scanner_service.dart` (lines 405-431, line 412)
- Current mitigation: `followLinks: true` is set, but no validation of final resolved path
- Recommendations:
  - Validate that resolved file path is within entry directory (use `p.normalize` and startsWith check)
  - Option to disable symlink following via settings

**No Password Reset Mechanism:**
- Risk: Users can sign up with email/password but Supabase email verification and password recovery flows are not fully configured in the app.
- Files: `lib/services/supabase_service.dart` (lines 38-51)
- Current mitigation: OAuth (Google, GitHub) is preferred auth method
- Recommendations: Ensure Supabase email templates are configured for password recovery, add forgot password flow to auth screen.

## Performance Bottlenecks

**getAllPapers Loads All Papers and Tags Into Memory:**
- Problem: `getAllPapers` queries entire papers table and loads tags for every row in a loop, then builds full list in memory before returning.
- Files: `lib/database/database_service.dart` (lines 247-257)
- Cause: No pagination or lazy loading
- Improvement path: 
  - Implement cursor-based pagination (load 100 papers at a time)
  - Use lazy loading in UI (infinite scroll)
  - Cache paper list with invalidation strategy

**FTS Search Rebuilds Full Paper List on Every Query:**
- Problem: Every search reloads all matching papers from disk, even if query hasn't changed.
- Files: `lib/providers/app_state.dart` (lines 302-326), `lib/database/database_service.dart` (lines 378-408)
- Cause: No search result caching
- Improvement path: Cache search results with query as key, invalidate on tag/paper changes.

**Thumbnail Generation on Demand in UI Thread:**
- Problem: `_loadThumbnail` in `PaperCard` generates thumbnails lazily on first display, blocking the UI thread for 1-2 seconds per PDF.
- Files: `lib/widgets/paper_card.dart` (lines 51-83)
- Cause: `PdfService.generateThumbnailToPath` is CPU-intensive (PDF parsing + image rendering)
- Improvement path: 
  - Generate thumbnails during `processNewPaper` background phase
  - Show placeholder while generating
  - Cache thumbnail paths in database

**Manifest Read/Write on Every Paper Update:**
- Problem: Each paper update may trigger manifest.json rewrite, blocking I/O on paper edits.
- Files: `lib/services/entry_scanner_service.dart` (lines 254-266), `lib/providers/app_state.dart` (lines 560-580)
- Cause: No batching; manifest written immediately even for single-paper changes
- Improvement path: 
  - Batch manifest writes (e.g., every 10 changes or 5 seconds)
  - Use `_withLock` to prevent concurrent writes
  - Write to temporary file then rename atomically

**PDF Text Extraction Happens Serially During Bulk Import:**
- Problem: `processNewPaper` extracts text from each PDF sequentially with 50ms yields, slowing bulk imports.
- Files: `lib/providers/app_state.dart` (lines 526-543), `lib/services/entry_scanner_service.dart` (lines 173-227)
- Cause: Isolate.run is only used per paper, not in parallel
- Improvement path: 
  - Use pool of background isolates to extract text in parallel
  - Profile to find optimal parallelism (CPU cores)
  - Show progress UI with estimated time remaining

**Tag Tree Rebuild Recalculates Paper Counts on Every Data Load:**
- Problem: `getTagTree` and `getAllTags` recalculate paper counts for all tags using complex CTEs on every refresh.
- Files: `lib/database/database_service.dart` (lines 537-578, 559-578)
- Cause: No materialized view or cached counts
- Improvement path: 
  - Maintain a `tag_paper_counts` table updated via triggers
  - Or cache CTE results in memory with invalidation

**Full-Text Search Extracts from Papers on Every Query:**
- Problem: If extracted_text is missing for older papers, search results may be incomplete because full-text search only works on indexed columns.
- Files: `lib/database/database_service.dart` (lines 378-408), `lib/services/entry_scanner_service.dart` (lines 179-191)
- Cause: FTS only indexes at insert time; background text extraction doesn't update FTS
- Improvement path: Async text extraction should automatically update FTS after completion.

## Fragile Areas

**AppState Navigation History Management:**
- Files: `lib/providers/app_state.dart` (lines 25-45, 66-68, 234-294)
- Why fragile: 
  - History state (`_historyIndex`, `_history`) can become out-of-sync if state changes without pushing history
  - `_NavigationState` equality check relies on tag ID which could be null
  - Forward/back navigation directly mutates UI state without validation
- Safe modification: 
  - Add assertions that `_historyIndex` is always valid
  - Log all history mutations
  - Test forward/back/add transitions exhaustively
- Test coverage: No unit tests for history navigation logic

**Database Migration Chain (v1-v6):**
- Files: `lib/database/database_service.dart` (lines 46-162)
- Why fragile: 
  - Each migration is sequential and irreversible
  - Missing migration (e.g., skip v5) can corrupt schema
  - No validation that schema is correct after migration
- Safe modification: 
  - Add migration status table to track which migrations ran
  - Add schema validation in `_initDatabase`
  - Document expected schema for each version
- Test coverage: No migration tests (can't test without recreating v1-v5 database states)

**Entry Scanner Rename Detection by Content Hash:**
- Files: `lib/services/entry_scanner_service.dart` (lines 92-149)
- Why fragile: 
  - Rename detection depends on content hash matching (first 64KB)
  - If two different PDFs have same first 64KB, false positive rename
  - Missing hash breaks rename detection silently
- Safe modification: 
  - Use full-file hash instead of first 64KB
  - Validate hash is non-empty before matching
  - Log rename detection with before/after paths
- Test coverage: No unit tests for rename logic

**BibTeX Fetch with DBLP Rate Limiting:**
- Files: `lib/services/entry_scanner_service.dart` (lines 382-403), `lib/services/bibtex_service.dart`
- Why fragile: 
  - 500ms delay between requests is hardcoded
  - No exponential backoff for 429 responses
  - Bulk import can exhaust quota silently
- Safe modification: 
  - Implement queue with configurable rate limit
  - Retry with exponential backoff
  - Return failed papers in result for retry
- Test coverage: No tests for rate limiting

**Supabase Sync Conflict Resolution:**
- Files: `lib/services/sync_service.dart` (lines 46-242)
- Why fragile: 
  - Sync assumes local data always wins (upsert on sync_key)
  - No merge strategy for conflicts (e.g., if remote is newer)
  - Topological sort for tags could fail silently on cycles
- Safe modification: 
  - Validate tag hierarchy is acyclic before sort
  - Compare `updated_at` timestamps to choose winner
  - Log conflicts for manual review
- Test coverage: No conflict resolution tests

**Manifest.json Encoding and Parsing:**
- Files: `lib/services/manifest_service.dart` (lines 75-103, 106-112, 129-200)
- Why fragile: 
  - Manual JSON encoding with custom `_deepCast`
  - No schema validation for manifest structure
  - Silent failures on malformed JSON
- Safe modification: 
  - Add manifest schema validation (e.g., `Map<String, dynamic>` with known keys)
  - Add version field and migration logic for manifest format changes
  - Log parse errors with full manifest content (first 100 chars)
- Test coverage: No manifest serialization tests

## Scaling Limits

**SQLite Concurrent Write Limits:**
- Current capacity: 1 concurrent write transaction
- Limit: With FTS triggers, paper updates serialize (lock contention)
- Scaling path: 
  - Migrate to PostgreSQL via Supabase (already in sync flow)
  - Implement conflict-free replicated data type (CRDT) for offline-first
  - Or use SQLite with WAL mode (write-ahead logging) for better concurrent reads

**PDF Text Extraction CPU Cost:**
- Current capacity: ~2-3 seconds per paper (depends on PDF size)
- Limit: 100-paper import takes 200+ seconds; user sees frozen UI despite background processing
- Scaling path: 
  - Parallel isolate pool instead of sequential
  - Move to server-side extraction (Edge Function)
  - Or use cheaper extraction library (e.g., `pdf` package for text-only)

**Manifest.json File Size:**
- Current capacity: ~1KB per paper (title, authors, abstract, bibtex, tags)
- Limit: 100,000 papers = 100MB manifest per entry
- Scaling path: 
  - Move manifest to SQLite (already local database exists)
  - Or split manifest by date range
  - Lazy-load manifest sections on demand

**Memory Usage of AppState:**
- Current capacity: ~1KB per paper in memory
- Limit: 100,000 papers = 100MB+ in AppState notifier (plus UI widgets)
- Scaling path: 
  - Pagination in UI (load 100 papers at a time)
  - Lazy load paper metadata (defer loading authors, abstract until display)
  - Use `ChangeNotifier` per paper instead of single provider

**FTS5 Search Index Size:**
- Current capacity: ~2-3KB per paper (title, authors, abstract, text)
- Limit: 100,000 papers = 200-300MB FTS index on disk
- Scaling path: 
  - Compress FTS column (extract_text only)
  - Or move search to server with Supabase full-text search
  - Implement incremental indexing

## Dependencies at Risk

**Syncfusion Packages (syncfusion_flutter_pdf, syncfusion_flutter_pdfviewer):**
- Risk: Commercial package with licensing requirements. Versions 24.2.8+ may require valid license key. Package is heavy (~50MB download) and has known issues with large PDFs.
- Impact: Text extraction may fail silently, PDF viewer may degrade, licensing warnings possible.
- Migration plan: 
  - For text extraction: Switch to `pdf` package + `pdfx` for lightweight text-only extraction
  - For viewing: Keep embedded Syncfusion viewer (no good free alternative), but add fallback to system viewer
  - Cost: Medium effort, reduced feature set (no annotations in viewer)

**supabase_flutter (v2.8.0):**
- Risk: Relatively new package in active development. API changes possible in future versions. OAuth redirect URL is hardcoded.
- Impact: OAuth login might break on major version bump. No easy rollback path.
- Migration plan: 
  - Pin to exact version in pubspec.lock
  - Monitor breaking changes in release notes
  - Consider alternative: `firebase_auth` (more stable but different backend)
  - Cost: Low effort, monitoring required

**desktop_drop (v0.7.0):**
- Risk: Package is unmaintained (last update 2022). May break on macOS updates or Flutter SDK updates.
- Impact: Drag-and-drop import would fail. Users forced to use file picker.
- Migration plan: 
  - Implement drag-and-drop via native macOS code (NSPasteboard)
  - Or switch to `file_picker` package (more reliable)
  - Cost: Medium effort, native code required for macOS

**pdf_render (v1.4.12) and image (v4.7.2):**
- Risk: Used only for thumbnail generation. Heavy dependencies (especially for just image resizing).
- Impact: Large app binary size, thumbnail generation is slow.
- Migration plan: 
  - For thumbnails: Use `pdf` package + Dart `image` package (lighter)
  - Or generate thumbnails on backend via Edge Function
  - Cost: Low-medium effort, reduces binary size

**sqflite_common_ffi (v2.4.0+2):**
- Risk: FFI-based SQLite may have platform-specific issues. No automatic schema migration tools.
- Impact: Edge cases on M1/ARM Macs (if not tested), migration bugs.
- Migration plan: 
  - If scaling to 100k+ papers, migrate to Supabase PostgreSQL
  - Otherwise, stay with sqflite but add comprehensive migration tests
  - Cost: High effort if migrating, low if staying

## Missing Critical Features

**Paper Deduplication:**
- Problem: Users can import the same paper multiple times from different directories. No detection of duplicates.
- Blocks: Maintaining a unified library across multiple locations
- Gap: No duplicate detection UI or merge functionality
- Priority: Medium (workaround: manual deletion, but tedious with large libraries)

**Offline Sync Resolution:**
- Problem: If user adds papers offline and syncs, then adds same papers on another device, no merge strategy exists.
- Blocks: Multi-device workflows (laptop + desktop)
- Gap: No conflict detection or resolution UI
- Priority: Medium-High (affects sync feature legitimacy)

**Paper Full-Text Backup:**
- Problem: Extracted text is cached locally but not backed up to Supabase. If local device dies, extracted text is lost.
- Blocks: Full recovery of papers after device loss
- Gap: No backup/restore mechanism for extracted text
- Priority: Medium (affects data loss risk)

**Tag Auto-Completion:**
- Problem: When adding papers, tag suggestions are shown but no auto-complete in tag input field.
- Blocks: Faster tagging workflow
- Gap: Manual typing required for every tag
- Priority: Low (nice-to-have, doesn't block core workflow)

**Scheduled Sync:**
- Problem: Sync is manual or triggered on login. No background sync (e.g., every 30 min).
- Blocks: Multi-device real-time sync
- Gap: No background isolate or push notifications for sync
- Priority: Medium (affects sync usefulness)

**Collaborative Tagging:**
- Problem: No shared tagging or tagging rights (all-or-nothing auth).
- Blocks: Shared research group workflows
- Gap: No multi-user tag ownership or permissions
- Priority: Low (advanced feature, out of initial scope)

## Test Coverage Gaps

**AppState State Mutations:**
- What's not tested: Navigation history, tag/entry selection, paper filtering, sync state transitions
- Files: `lib/providers/app_state.dart`
- Risk: Regressions in navigation (back/forward), state inconsistencies
- Priority: High (core app logic)

**Database N+1 Queries:**
- What's not tested: Query performance, correct tag loading, FTS results
- Files: `lib/database/database_service.dart`
- Risk: Slow performance, incorrect results (missing tags)
- Priority: High (critical for user experience)

**Entry Scanner Rename Detection:**
- What's not tested: Rename scenarios, hash collision handling, manifest sync
- Files: `lib/services/entry_scanner_service.dart`
- Risk: False positives (files misidentified as renames), data loss
- Priority: High (data integrity)

**Sync Conflict Resolution:**
- What's not tested: Tag hierarchy cycles, upsert conflicts, partial sync failures
- Files: `lib/services/sync_service.dart`
- Risk: Corrupted tag hierarchy, duplicate papers in cloud, failed syncs
- Priority: High (cloud feature)

**PDF Text Extraction Edge Cases:**
- What's not tested: Corrupted PDFs, encrypted PDFs, very large PDFs, timeout handling
- Files: `lib/services/pdf_service.dart`
- Risk: Crashes, timeouts, silent failures
- Priority: Medium (affects paper import reliability)

**BibTeX Fetch Rate Limiting:**
- What's not tested: 429 responses, exponential backoff, partial failures
- Files: `lib/services/entry_scanner_service.dart`
- Risk: Exhausted quota, silent failures, race conditions
- Priority: Medium (affects BibTeX import feature)

**Manifest Serialization:**
- What's not tested: Malformed JSON recovery, format upgrades, concurrent access
- Files: `lib/services/manifest_service.dart`
- Risk: Manifest corruption, data loss
- Priority: Medium (affects cache consistency)

**Auth State Persistence:**
- What's not tested: Session recovery, logout/login cycles, OAuth callback handling
- Files: `lib/services/supabase_service.dart`, `lib/providers/app_state.dart`
- Risk: Auth token expiration, infinite login loops, broken OAuth
- Priority: Medium (affects cloud features)

---

*Concerns audit: 2026-04-16*

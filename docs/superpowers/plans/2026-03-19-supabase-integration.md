# Supabase Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Supabase backend to Paper Suitcase for auth, metadata sync, collaborative recommendations, and MiniMax-powered paper chat — while keeping the app fully functional offline.

**Architecture:** Local-first hybrid. SQLite remains source of truth. Supabase adds auth (email + Google + GitHub), unidirectional metadata sync, shared paper catalog for recommendations, and Edge Function proxy to MiniMax M2.5 for paper understanding chat. All cloud features are additive — the app works identically without an account.

**Tech Stack:** Flutter (existing), Supabase (auth, Postgres, Edge Functions, RPC), MiniMax M2.5 API, Deno (Edge Functions runtime)

**Spec:** `docs/superpowers/specs/2026-03-19-supabase-integration-design.md`

---

## File Structure

### New Files

```
supabase/                                    — Supabase project root (created by supabase init)
├── config.toml                              — Supabase local dev config
├── migrations/
│   └── 00001_initial_schema.sql             — All tables, RLS, indexes, RPC functions
├── functions/
│   ├── chat-with-paper/
│   │   └── index.ts                         — MiniMax proxy Edge Function
│   └── compute-trending/
│       └── index.ts                         — Daily trending score computation
└── seed.sql                                 — (empty, for future test data)

lib/
├── services/
│   ├── supabase_service.dart                — Supabase init, auth, session management
│   ├── sync_service.dart                    — Local→cloud metadata sync
│   ├── recommendation_service.dart          — Fetch recommendations via RPC
│   └── llm_chat_service.dart                — Chat proxy via Edge Function
├── models/
│   └── chat_message.dart                    — Chat message model for LLM conversations
├── widgets/
│   ├── auth_screen.dart                     — Login/signup/continue-offline screen
│   ├── discover_tab.dart                    — Recommendations UI
│   └── paper_chat_panel.dart                — Chat panel for paper understanding
```

### Modified Files

```
lib/database/database_service.dart           — Add migration v6 (sync columns)
lib/models/paper.dart                        — Add sync_key, remote_id, updated_at, deleted_at, dirty fields
lib/models/tag.dart                          — Add remote_id, dirty fields
lib/providers/app_state.dart                 — Add auth state, sync state, recommendations, chat state
lib/screens/main_screen.dart                 — Add auth gate, Discover tab, chat panel, sync indicator
lib/widgets/tag_sidebar.dart                 — Add Discover button, sync indicator, account button
lib/main.dart                                — Initialize Supabase before app start
pubspec.yaml                                 — Add supabase_flutter dependency
```

---

## Task 1: Supabase Project Setup & Schema

**Files:**
- Create: `supabase/migrations/00001_initial_schema.sql`
- Create: `supabase/seed.sql`

This task sets up the Supabase project locally and creates all cloud database tables, RLS policies, indexes, and RPC functions.

**Prerequisites:** Install Supabase CLI (`brew install supabase/tap/supabase`). Create a Supabase project at https://supabase.com/dashboard.

- [ ] **Step 1: Initialize Supabase project**

```bash
cd /Users/neil/Playground/trae_projects/PaperFlutter
supabase init
```

Expected: Creates `supabase/` directory with `config.toml`.

- [ ] **Step 2: Write the initial migration**

Create `supabase/migrations/00001_initial_schema.sql` with all tables from the spec:

```sql
-- ============================================================
-- PROFILES (extends auth.users)
-- ============================================================
CREATE TABLE profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name TEXT,
  tier TEXT NOT NULL DEFAULT 'free' CHECK (tier IN ('free', 'pro')),
  llm_calls_this_month INTEGER NOT NULL DEFAULT 0,
  llm_calls_reset_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Auto-create profile on signup
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO profiles (id, display_name)
  VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.email));
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- ============================================================
-- USER PAPERS (per-user metadata synced from local)
-- ============================================================
CREATE TABLE user_papers (
  id BIGSERIAL PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  arxiv_id TEXT,
  title TEXT NOT NULL,
  authors TEXT,
  abstract TEXT,
  bibtex TEXT,
  sync_key TEXT NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ,
  synced_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(user_id, sync_key)
);

-- ============================================================
-- USER TAGS (per-user tag hierarchy)
-- ============================================================
CREATE TABLE user_tags (
  id BIGSERIAL PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  parent_id BIGINT REFERENCES user_tags(id) ON DELETE SET NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(user_id, name, parent_id)
);

-- ============================================================
-- USER PAPER TAGS (junction)
-- ============================================================
CREATE TABLE user_paper_tags (
  user_paper_id BIGINT NOT NULL REFERENCES user_papers(id) ON DELETE CASCADE,
  user_tag_id BIGINT NOT NULL REFERENCES user_tags(id) ON DELETE CASCADE,
  PRIMARY KEY (user_paper_id, user_tag_id)
);

-- ============================================================
-- SHARED CATALOG (deduplicated across users)
-- ============================================================
CREATE TABLE shared_catalog (
  id BIGSERIAL PRIMARY KEY,
  arxiv_id TEXT UNIQUE,
  doi TEXT UNIQUE,
  title_hash TEXT,
  title TEXT NOT NULL,
  authors TEXT,
  abstract TEXT,
  reader_count INTEGER NOT NULL DEFAULT 1,
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (arxiv_id IS NOT NULL OR doi IS NOT NULL OR title_hash IS NOT NULL)
);

-- ============================================================
-- CATALOG TAGS (aggregated tag associations)
-- ============================================================
CREATE TABLE catalog_tags (
  id BIGSERIAL PRIMARY KEY,
  catalog_id BIGINT NOT NULL REFERENCES shared_catalog(id) ON DELETE CASCADE,
  tag_name TEXT NOT NULL,
  usage_count INTEGER NOT NULL DEFAULT 1,
  UNIQUE(catalog_id, tag_name)
);

-- ============================================================
-- TRENDING SCORES (computed daily)
-- ============================================================
CREATE TABLE trending_scores (
  id BIGSERIAL PRIMARY KEY,
  catalog_id BIGINT NOT NULL REFERENCES shared_catalog(id) ON DELETE CASCADE,
  score FLOAT NOT NULL DEFAULT 0,
  computed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- INDEXES
-- ============================================================
CREATE INDEX idx_user_papers_user ON user_papers(user_id);
CREATE INDEX idx_user_papers_arxiv ON user_papers(arxiv_id);
CREATE INDEX idx_user_papers_sync_key ON user_papers(user_id, sync_key);
CREATE INDEX idx_shared_catalog_arxiv ON shared_catalog(arxiv_id);
CREATE INDEX idx_shared_catalog_title_hash ON shared_catalog(title_hash);
CREATE INDEX idx_catalog_tags_catalog ON catalog_tags(catalog_id);
CREATE INDEX idx_trending_scores_score ON trending_scores(score DESC);

-- ============================================================
-- ROW-LEVEL SECURITY
-- ============================================================
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY profiles_select ON profiles FOR SELECT USING (auth.uid() = id);
CREATE POLICY profiles_update ON profiles FOR UPDATE USING (auth.uid() = id);

ALTER TABLE user_papers ENABLE ROW LEVEL SECURITY;
CREATE POLICY user_papers_select ON user_papers FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY user_papers_insert ON user_papers FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY user_papers_update ON user_papers FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY user_papers_delete ON user_papers FOR DELETE USING (auth.uid() = user_id);

ALTER TABLE user_tags ENABLE ROW LEVEL SECURITY;
CREATE POLICY user_tags_select ON user_tags FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY user_tags_insert ON user_tags FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY user_tags_update ON user_tags FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY user_tags_delete ON user_tags FOR DELETE USING (auth.uid() = user_id);

ALTER TABLE user_paper_tags ENABLE ROW LEVEL SECURITY;
CREATE POLICY user_paper_tags_select ON user_paper_tags FOR SELECT
  USING (EXISTS (SELECT 1 FROM user_papers WHERE id = user_paper_id AND user_id = auth.uid()));
CREATE POLICY user_paper_tags_insert ON user_paper_tags FOR INSERT
  WITH CHECK (
    EXISTS (SELECT 1 FROM user_papers WHERE id = user_paper_id AND user_id = auth.uid())
    AND EXISTS (SELECT 1 FROM user_tags WHERE id = user_tag_id AND user_id = auth.uid())
  );
CREATE POLICY user_paper_tags_delete ON user_paper_tags FOR DELETE
  USING (EXISTS (SELECT 1 FROM user_papers WHERE id = user_paper_id AND user_id = auth.uid()));

ALTER TABLE shared_catalog ENABLE ROW LEVEL SECURITY;
CREATE POLICY shared_catalog_select ON shared_catalog FOR SELECT USING (auth.role() = 'authenticated');

ALTER TABLE catalog_tags ENABLE ROW LEVEL SECURITY;
CREATE POLICY catalog_tags_select ON catalog_tags FOR SELECT USING (auth.role() = 'authenticated');

ALTER TABLE trending_scores ENABLE ROW LEVEL SECURITY;
CREATE POLICY trending_scores_select ON trending_scores FOR SELECT USING (auth.role() = 'authenticated');

-- ============================================================
-- RPC: Upsert to shared catalog (SECURITY DEFINER)
-- ============================================================
CREATE OR REPLACE FUNCTION upsert_shared_catalog(
  p_arxiv_id TEXT DEFAULT NULL,
  p_doi TEXT DEFAULT NULL,
  p_title_hash TEXT DEFAULT NULL,
  p_title TEXT DEFAULT NULL,
  p_authors TEXT DEFAULT NULL,
  p_abstract TEXT DEFAULT NULL,
  p_tag_names TEXT[] DEFAULT '{}'
)
RETURNS BIGINT AS $$
DECLARE
  v_catalog_id BIGINT;
  v_tag TEXT;
BEGIN
  -- Try to find existing entry by any identifier
  SELECT id INTO v_catalog_id FROM shared_catalog
  WHERE (p_arxiv_id IS NOT NULL AND arxiv_id = p_arxiv_id)
     OR (p_doi IS NOT NULL AND doi = p_doi)
     OR (p_title_hash IS NOT NULL AND title_hash = p_title_hash)
  LIMIT 1;

  IF v_catalog_id IS NOT NULL THEN
    -- Update existing: increment reader_count, update last_seen
    UPDATE shared_catalog
    SET reader_count = reader_count + 1,
        last_seen_at = NOW(),
        -- Fill in identifiers if missing
        arxiv_id = COALESCE(shared_catalog.arxiv_id, p_arxiv_id),
        doi = COALESCE(shared_catalog.doi, p_doi),
        title_hash = COALESCE(shared_catalog.title_hash, p_title_hash)
    WHERE id = v_catalog_id;
  ELSE
    -- Insert new entry
    INSERT INTO shared_catalog (arxiv_id, doi, title_hash, title, authors, abstract)
    VALUES (p_arxiv_id, p_doi, p_title_hash, p_title, p_authors, p_abstract)
    RETURNING id INTO v_catalog_id;
  END IF;

  -- Upsert tags
  FOREACH v_tag IN ARRAY p_tag_names LOOP
    INSERT INTO catalog_tags (catalog_id, tag_name, usage_count)
    VALUES (v_catalog_id, LOWER(TRIM(v_tag)), 1)
    ON CONFLICT (catalog_id, tag_name)
    DO UPDATE SET usage_count = catalog_tags.usage_count + 1;
  END LOOP;

  RETURN v_catalog_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- RPC: Collaborative filtering recommendations
-- ============================================================
CREATE OR REPLACE FUNCTION get_collaborative_recommendations(p_user_id UUID, p_limit INT DEFAULT 20)
RETURNS TABLE(
  catalog_id BIGINT,
  arxiv_id TEXT,
  title TEXT,
  authors TEXT,
  abstract TEXT,
  reader_count INT,
  match_score BIGINT
) AS $$
BEGIN
  RETURN QUERY
  WITH my_arxiv_ids AS (
    SELECT up.arxiv_id
    FROM user_papers up
    WHERE up.user_id = p_user_id AND up.arxiv_id IS NOT NULL AND up.deleted_at IS NULL
  ),
  similar_users AS (
    SELECT up2.user_id, COUNT(*) AS shared_count
    FROM user_papers up2
    JOIN my_arxiv_ids mai ON up2.arxiv_id = mai.arxiv_id
    WHERE up2.user_id != p_user_id AND up2.deleted_at IS NULL
    GROUP BY up2.user_id
    HAVING COUNT(*) >= 3
  ),
  their_papers AS (
    SELECT up3.arxiv_id, SUM(su.shared_count) AS match_score
    FROM user_papers up3
    JOIN similar_users su ON up3.user_id = su.user_id
    WHERE up3.arxiv_id IS NOT NULL
      AND up3.deleted_at IS NULL
      AND up3.arxiv_id NOT IN (SELECT arxiv_id FROM my_arxiv_ids)
    GROUP BY up3.arxiv_id
  )
  SELECT sc.id, sc.arxiv_id, sc.title, sc.authors, sc.abstract, sc.reader_count, tp.match_score
  FROM their_papers tp
  JOIN shared_catalog sc ON sc.arxiv_id = tp.arxiv_id
  ORDER BY tp.match_score DESC
  LIMIT p_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- RPC: Tag-based recommendations
-- ============================================================
CREATE OR REPLACE FUNCTION get_tag_recommendations(p_user_id UUID, p_limit INT DEFAULT 20)
RETURNS TABLE(
  catalog_id BIGINT,
  arxiv_id TEXT,
  title TEXT,
  authors TEXT,
  abstract TEXT,
  reader_count INT,
  tag_relevance BIGINT
) AS $$
BEGIN
  RETURN QUERY
  WITH my_tags AS (
    SELECT LOWER(TRIM(ut.name)) AS tag_name
    FROM user_tags ut
    WHERE ut.user_id = p_user_id
  ),
  my_sync_keys AS (
    SELECT up.sync_key
    FROM user_papers up
    WHERE up.user_id = p_user_id AND up.deleted_at IS NULL
  ),
  relevant_catalog AS (
    SELECT ct.catalog_id, SUM(ct.usage_count) AS tag_relevance
    FROM catalog_tags ct
    JOIN my_tags mt ON ct.tag_name = mt.tag_name
    GROUP BY ct.catalog_id
  )
  SELECT sc.id, sc.arxiv_id, sc.title, sc.authors, sc.abstract, sc.reader_count, rc.tag_relevance
  FROM relevant_catalog rc
  JOIN shared_catalog sc ON sc.id = rc.catalog_id
  WHERE NOT EXISTS (
    SELECT 1 FROM my_sync_keys msk
    WHERE msk.sync_key = 'arxiv:' || sc.arxiv_id
       OR msk.sync_key = 'hash:' || sc.title_hash
  )
  ORDER BY rc.tag_relevance DESC, sc.reader_count DESC
  LIMIT p_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- RPC: Trending recommendations
-- ============================================================
CREATE OR REPLACE FUNCTION get_trending_recommendations(p_user_id UUID, p_limit INT DEFAULT 20)
RETURNS TABLE(
  catalog_id BIGINT,
  arxiv_id TEXT,
  title TEXT,
  authors TEXT,
  abstract TEXT,
  reader_count INT,
  trending_score FLOAT
) AS $$
BEGIN
  RETURN QUERY
  WITH my_tags AS (
    SELECT LOWER(TRIM(ut.name)) AS tag_name
    FROM user_tags ut
    WHERE ut.user_id = p_user_id
  ),
  my_sync_keys AS (
    SELECT up.sync_key
    FROM user_papers up
    WHERE up.user_id = p_user_id AND up.deleted_at IS NULL
  )
  SELECT sc.id, sc.arxiv_id, sc.title, sc.authors, sc.abstract, sc.reader_count, ts.score
  FROM trending_scores ts
  JOIN shared_catalog sc ON sc.id = ts.catalog_id
  -- Only show trending in user's tag areas
  WHERE EXISTS (
    SELECT 1 FROM catalog_tags ct
    JOIN my_tags mt ON ct.tag_name = mt.tag_name
    WHERE ct.catalog_id = sc.id
  )
  -- Exclude papers user already has
  AND NOT EXISTS (
    SELECT 1 FROM my_sync_keys msk
    WHERE msk.sync_key = 'arxiv:' || sc.arxiv_id
       OR msk.sync_key = 'hash:' || sc.title_hash
  )
  ORDER BY ts.score DESC
  LIMIT p_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- CRON: Monthly LLM call counter reset (requires pg_cron extension)
-- ============================================================
-- Run this manually in Supabase dashboard SQL editor after enabling pg_cron:
-- SELECT cron.schedule('reset-llm-calls', '0 0 1 * *', $$
--   UPDATE profiles SET llm_calls_this_month = 0, llm_calls_reset_at = NOW();
-- $$);
```

- [ ] **Step 3: Create empty seed file**

Create `supabase/seed.sql`:
```sql
-- Seed data for development/testing
-- (empty for now)
```

- [ ] **Step 4: Link to remote Supabase project**

```bash
supabase link --project-ref <YOUR_PROJECT_REF>
```

Replace `<YOUR_PROJECT_REF>` with the project reference from your Supabase dashboard.

- [ ] **Step 5: Push migration to remote**

```bash
supabase db push
```

Expected: Migration applies successfully. Verify tables exist in Supabase dashboard → Table Editor.

- [ ] **Step 6: Configure auth providers**

In Supabase Dashboard → Authentication → Providers:
1. Enable Email (already enabled by default)
2. Enable Google: add OAuth client ID + secret from Google Cloud Console
3. Enable GitHub: add OAuth client ID + secret from GitHub Developer Settings

Add redirect URL for desktop app: `io.supabase.papersuitecase://login-callback`

- [ ] **Step 7: Enable pg_cron for monthly reset**

In Supabase Dashboard → SQL Editor, run:
```sql
SELECT cron.schedule('reset-llm-calls', '0 0 1 * *', $$
  UPDATE profiles SET llm_calls_this_month = 0, llm_calls_reset_at = NOW();
$$);
```

- [ ] **Step 8: Commit**

```bash
git add supabase/
git commit -m "feat: add Supabase project with schema, RLS, and RPC functions"
```

---

## Task 2: Local SQLite Migration v6 (Sync Columns)

**Files:**
- Modify: `lib/database/database_service.dart`
- Modify: `lib/models/paper.dart`
- Modify: `lib/models/tag.dart`

This task adds sync-related columns to the local SQLite database and models so papers and tags can track their sync state.

- [ ] **Step 1: Add sync fields to Paper model**

In `lib/models/paper.dart`, add fields to the `Paper` class:

```dart
// Add these fields to the class:
final String? syncKey;
final int? remoteId;
final DateTime? updatedAt;
final DateTime? deletedAt;
final bool dirty;
```

Add them to the constructor:
```dart
Paper({
  // ... existing params ...
  this.syncKey,
  this.remoteId,
  this.updatedAt,
  this.deletedAt,
  this.dirty = true,
})
```

Add to `toMap()`:
```dart
if (syncKey != null) 'sync_key': syncKey,
if (remoteId != null) 'remote_id': remoteId,
if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
if (deletedAt != null) 'deleted_at': deletedAt!.toIso8601String(),
'dirty': dirty ? 1 : 0,
```

Add to `fromMap()`:
```dart
syncKey: map['sync_key'] as String?,
remoteId: map['remote_id'] as int?,
updatedAt: map['updated_at'] != null ? DateTime.parse(map['updated_at'] as String) : null,
deletedAt: map['deleted_at'] != null ? DateTime.parse(map['deleted_at'] as String) : null,
dirty: map.containsKey('dirty') ? (map['dirty'] as int?) == 1 : true,
```

Add to `copyWith()`:
```dart
String? syncKey,
int? remoteId,
DateTime? updatedAt,
DateTime? deletedAt,
bool? dirty,
// ... in body:
syncKey: syncKey ?? this.syncKey,
remoteId: remoteId ?? this.remoteId,
updatedAt: updatedAt ?? this.updatedAt,
deletedAt: deletedAt ?? this.deletedAt,
dirty: dirty ?? this.dirty,
```

- [ ] **Step 2: Add sync fields to Tag model**

In `lib/models/tag.dart`, add fields:

```dart
final int? remoteId;
final bool dirty;
```

Add to constructor: `this.remoteId, this.dirty = true`

Add to `toMap()`: `if (remoteId != null) 'remote_id': remoteId, 'dirty': dirty ? 1 : 0,`

Add to `fromMap()`: `remoteId: map['remote_id'] as int?, dirty: (map['dirty'] as int?) == 1,`

Add to `copyWith()`: `int? remoteId, bool? dirty,` with corresponding body assignments.

- [ ] **Step 3: Add migration v6 to database_service.dart**

In `lib/database/database_service.dart`, update the `_initDatabase` method to bump version from 5 to 6 and add `onUpgrade`:

```dart
return await openDatabase(
  dbPath,
  version: 6,
  onCreate: _onCreate,
  onUpgrade: _onUpgrade,
);
```

Add the `_onUpgrade` method. Note: the app previously had no `onUpgrade` handler — all databases in the wild were created at version 5 via `onCreate`. If a user had an older version, the DB would have been recreated. So we only need to handle the 5→6 upgrade path:

```dart
Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
  if (oldVersion < 6) {
    await db.execute('ALTER TABLE papers ADD COLUMN sync_key TEXT');
    await db.execute('ALTER TABLE papers ADD COLUMN remote_id INTEGER');
    await db.execute('ALTER TABLE papers ADD COLUMN updated_at TEXT');
    await db.execute('ALTER TABLE papers ADD COLUMN deleted_at TEXT');
    await db.execute('ALTER TABLE papers ADD COLUMN dirty INTEGER NOT NULL DEFAULT 1');
    await db.execute('ALTER TABLE tags ADD COLUMN remote_id INTEGER');
    await db.execute('ALTER TABLE tags ADD COLUMN dirty INTEGER NOT NULL DEFAULT 1');

    // Backfill sync_key for existing papers
    await _backfillSyncKeys(db);
  }
}
```

Add the backfill method:

```dart
Future<void> _backfillSyncKeys(Database db) async {
  final papers = await db.query('papers');
  for (final paper in papers) {
    final id = paper['id'] as int;
    final arxivId = paper['arxiv_id'] as String?;
    final contentHash = paper['content_hash'] as String?;
    final title = paper['title'] as String? ?? '';
    final authors = paper['authors'] as String? ?? '';

    String syncKey;
    if (arxivId != null && arxivId.isNotEmpty) {
      syncKey = 'arxiv:$arxivId';
    } else if (contentHash != null && contentHash.isNotEmpty) {
      syncKey = 'hash:$contentHash';
    } else {
      final input = '${title.toLowerCase()}${authors.toLowerCase()}';
      final hash = sha256.convert(utf8.encode(input)).toString();
      syncKey = 'title:$hash';
    }

    await db.update('papers', {'sync_key': syncKey, 'updated_at': DateTime.now().toIso8601String()}, where: 'id = ?', whereArgs: [id]);
  }
}
```

Add import at top of file: `import 'dart:convert'; import 'package:crypto/crypto.dart';`

Also update `_onCreate` to include the new columns in the initial `papers` and `tags` CREATE TABLE statements.

- [ ] **Step 4: Update database methods to set dirty flag on mutations**

In `database_service.dart`, update `insertPaper`, `updatePaper`, `deletePaper`, `insertTag`, `updateTag`, `deleteTag`, `addTagToPaper`, `removeTagFromPaper`, `setTagsForPaper` to set `dirty = 1` and `updated_at = NOW()` on the affected paper/tag rows.

The current `insertPaper` calls `db.insert('papers', paper.toMap())`. Modify it to extract the map and add sync fields:

```dart
Future<int> insertPaper(Paper paper) async {
  final db = await database;
  final values = paper.toMap();
  // Compute sync_key if not already set
  if (values['sync_key'] == null) {
    values['sync_key'] = _computeSyncKey(
      arxivId: values['arxiv_id'] as String?,
      contentHash: values['content_hash'] as String?,
      title: values['title'] as String? ?? '',
      authors: values['authors'] as String? ?? '',
    );
  }
  values['dirty'] = 1;
  values['updated_at'] = DateTime.now().toIso8601String();
  return await db.insert('papers', values);
}
```

For `updatePaper`, add dirty flag and updated_at to the values map before the update call:
```dart
// In updatePaper, before db.update():
final values = paper.toMap();
values['dirty'] = 1;
values['updated_at'] = DateTime.now().toIso8601String();
// ... then use values in db.update()
```

**CRITICAL: Convert `deletePaper` to soft delete** (the spec requires soft deletes for sync):
```dart
Future<void> deletePaper(int id) async {
  final db = await database;
  // Soft delete: set deleted_at timestamp and mark dirty for sync
  await db.update(
    'papers',
    {
      'deleted_at': DateTime.now().toIso8601String(),
      'dirty': 1,
    },
    where: 'id = ?',
    whereArgs: [id],
  );
  // Also remove from FTS index
  await db.rawDelete('INSERT INTO papers_fts(papers_fts, rowid, title, authors, abstract, extracted_text) '
      'SELECT \'delete\', id, title, authors, abstract, extracted_text FROM papers WHERE id = ?', [id]);
}
```

Add a method to hard-delete old soft-deleted papers (called periodically):
```dart
Future<void> purgeOldDeletedPapers({int daysOld = 30}) async {
  final db = await database;
  final cutoff = DateTime.now().subtract(Duration(days: daysOld)).toIso8601String();
  await db.delete('papers', where: 'deleted_at IS NOT NULL AND deleted_at < ?', whereArgs: [cutoff]);
}
```

Update `getAllPapers` and other paper query methods to exclude soft-deleted papers:
```dart
// Add to WHERE clauses: AND deleted_at IS NULL
// e.g., in getAllPapers:
final maps = await db.query('papers', where: 'deleted_at IS NULL', orderBy: 'added_at DESC');
```

For tag mutations (`insertTag`, `updateTag`, `addTagToPaper`, etc.), set `dirty = 1` on the affected tags:
```dart
// After any tag insert/update:
await db.update('tags', {'dirty': 1}, where: 'id = ?', whereArgs: [tagId]);
```

Add the sync_key computation helper:
```dart
String _computeSyncKey({String? arxivId, String? contentHash, required String title, required String authors}) {
  if (arxivId != null && arxivId.isNotEmpty) return 'arxiv:$arxivId';
  if (contentHash != null && contentHash.isNotEmpty) return 'hash:$contentHash';
  final input = '${title.toLowerCase()}${authors.toLowerCase()}';
  final hash = sha256.convert(utf8.encode(input)).toString();
  return 'title:$hash';
}
```

- [ ] **Step 5: Verify the app still runs**

```bash
cd /Users/neil/Playground/trae_projects/PaperFlutter
flutter run -d macos
```

Expected: App launches, existing data loads correctly. New columns have default values. No crashes. Check that papers load in the grid and tags appear in sidebar.

- [ ] **Step 6: Commit**

```bash
git add lib/database/database_service.dart lib/models/paper.dart lib/models/tag.dart
git commit -m "feat: add SQLite migration v6 with sync columns and sync_key backfill"
```

---

## Task 3: Supabase Flutter Integration & Auth Service

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/main.dart`
- Create: `lib/services/supabase_service.dart`
- Create: `lib/widgets/auth_screen.dart`
- Modify: `lib/providers/app_state.dart`
- Modify: `lib/screens/main_screen.dart`
- Modify: `lib/widgets/tag_sidebar.dart`

This task adds the `supabase_flutter` package, creates the auth service, builds the login UI, and wires auth state into AppState.

- [ ] **Step 1: Add supabase_flutter dependency**

In `pubspec.yaml`, add under `dependencies:`:
```yaml
  supabase_flutter: ^2.8.0
```

Then run:
```bash
flutter pub get
```

- [ ] **Step 2: Create Supabase service**

Create `lib/services/supabase_service.dart`:

```dart
import 'package:supabase_flutter/supabase_flutter.dart';

/// Service for Supabase initialization and auth operations.
class SupabaseService {
  static const String _supabaseUrl = 'YOUR_SUPABASE_URL';
  static const String _supabaseAnonKey = 'YOUR_SUPABASE_ANON_KEY';

  static SupabaseClient get client => Supabase.instance.client;

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: _supabaseUrl,
      anonKey: _supabaseAnonKey,
    );
  }

  static User? get currentUser => client.auth.currentUser;
  static Session? get currentSession => client.auth.currentSession;
  static bool get isLoggedIn => currentUser != null;

  static Stream<AuthState> get authStateChanges => client.auth.onAuthStateChange;

  /// Sign up with email/password.
  static Future<AuthResponse> signUpWithEmail(String email, String password) async {
    return await client.auth.signUp(email: email, password: password);
  }

  /// Sign in with email/password.
  static Future<AuthResponse> signInWithEmail(String email, String password) async {
    return await client.auth.signInWithPassword(email: email, password: password);
  }

  /// Sign in with Google OAuth.
  static Future<bool> signInWithGoogle() async {
    return await client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: 'io.supabase.papersuitecase://login-callback',
    );
  }

  /// Sign in with GitHub OAuth.
  static Future<bool> signInWithGitHub() async {
    return await client.auth.signInWithOAuth(
      OAuthProvider.github,
      redirectTo: 'io.supabase.papersuitecase://login-callback',
    );
  }

  /// Sign out.
  static Future<void> signOut() async {
    await client.auth.signOut();
  }

  /// Get user profile from profiles table.
  static Future<Map<String, dynamic>?> getProfile() async {
    if (currentUser == null) return null;
    final response = await client
        .from('profiles')
        .select()
        .eq('id', currentUser!.id)
        .maybeSingle();
    return response;
  }
}
```

- [ ] **Step 3: Initialize Supabase in main.dart**

In `lib/main.dart`, add Supabase initialization before `runApp`:

```dart
import 'services/supabase_service.dart';

// In main(), after WidgetsFlutterBinding.ensureInitialized():
await SupabaseService.initialize();
```

Note: Supabase init is fire-and-forget safe — if it fails (no internet), the app still works. Wrap in try-catch:
```dart
try {
  await SupabaseService.initialize();
} catch (e) {
  debugPrint('Supabase init failed (offline mode): $e');
}
```

- [ ] **Step 4: Add auth state to AppState**

In `lib/providers/app_state.dart`, add auth-related state and methods:

```dart
import '../services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Add to state fields:
User? _currentUser;
Map<String, dynamic>? _userProfile;
bool _isAuthLoading = false;

// Add getters:
User? get currentUser => _currentUser;
Map<String, dynamic>? get userProfile => _userProfile;
bool get isLoggedIn => _currentUser != null;
bool get isAuthLoading => _isAuthLoading;
String get userTier => (_userProfile?['tier'] as String?) ?? 'free';
int get llmCallsThisMonth => (_userProfile?['llm_calls_this_month'] as int?) ?? 0;
int get llmCallsLimit => userTier == 'pro' ? 300 : 30;
```

In `initialize()`, add after existing init:
```dart
// Listen to auth state changes
_currentUser = SupabaseService.currentUser;
if (_currentUser != null) {
  _userProfile = await SupabaseService.getProfile();
}
SupabaseService.authStateChanges.listen((authState) {
  _currentUser = authState.session?.user;
  if (_currentUser != null) {
    SupabaseService.getProfile().then((profile) {
      _userProfile = profile;
      notifyListeners();
    });
  } else {
    _userProfile = null;
  }
  notifyListeners();
});
```

Add auth action methods:
```dart
Future<String?> signInWithEmail(String email, String password) async {
  _isAuthLoading = true;
  notifyListeners();
  try {
    await SupabaseService.signInWithEmail(email, password);
    return null; // success
  } on AuthException catch (e) {
    return e.message;
  } finally {
    _isAuthLoading = false;
    notifyListeners();
  }
}

Future<String?> signUpWithEmail(String email, String password) async {
  _isAuthLoading = true;
  notifyListeners();
  try {
    await SupabaseService.signUpWithEmail(email, password);
    return null;
  } on AuthException catch (e) {
    return e.message;
  } finally {
    _isAuthLoading = false;
    notifyListeners();
  }
}

Future<void> signInWithGoogle() async {
  await SupabaseService.signInWithGoogle();
}

Future<void> signInWithGitHub() async {
  await SupabaseService.signInWithGitHub();
}

Future<void> signOut() async {
  await SupabaseService.signOut();
  _currentUser = null;
  _userProfile = null;
  notifyListeners();
}
```

- [ ] **Step 5: Configure macOS deep link for OAuth callback**

In `macos/Runner/Info.plist`, add a URL scheme handler inside the `<dict>` block so OAuth callbacks return to the app:

```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLName</key>
    <string>io.supabase.papersuitecase</string>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>io.supabase.papersuitecase</string>
    </array>
  </dict>
</array>
```

Without this, Google/GitHub OAuth will open a browser but the callback will never return to the app.

- [ ] **Step 6: Create auth screen**

Create `lib/widgets/auth_screen.dart` (email/password + social login + continue offline):

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';

/// Login/signup screen with email, Google, GitHub, and "Continue offline" option.
class AuthScreen extends StatefulWidget {
  final VoidCallback onContinueOffline;
  const AuthScreen({super.key, required this.onContinueOffline});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSignUp = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submitEmail() async {
    final appState = context.read<AppState>();
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Please enter email and password');
      return;
    }

    String? error;
    if (_isSignUp) {
      error = await appState.signUpWithEmail(email, password);
    } else {
      error = await appState.signInWithEmail(email, password);
    }

    if (error != null && mounted) {
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final theme = Theme.of(context);

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.article_outlined, size: 64, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('Paper Suitcase', style: theme.textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text(
              'Sign in to sync your library and get recommendations',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),

            // Email field
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),

            // Password field
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
              obscureText: true,
              onSubmitted: (_) => _submitEmail(),
            ),
            const SizedBox(height: 8),

            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ),

            // Submit button
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: appState.isAuthLoading ? null : _submitEmail,
                child: appState.isAuthLoading
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(_isSignUp ? 'Sign Up' : 'Sign In'),
              ),
            ),
            const SizedBox(height: 8),

            // Toggle sign in/up
            TextButton(
              onPressed: () => setState(() {
                _isSignUp = !_isSignUp;
                _error = null;
              }),
              child: Text(_isSignUp ? 'Already have an account? Sign in' : "Don't have an account? Sign up"),
            ),
            const SizedBox(height: 16),

            // Divider
            Row(children: [
              const Expanded(child: Divider()),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text('or', style: theme.textTheme.bodySmall)),
              const Expanded(child: Divider()),
            ]),
            const SizedBox(height: 16),

            // Social login buttons
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => appState.signInWithGoogle(),
                icon: const Icon(Icons.g_mobiledata, size: 24),
                label: const Text('Continue with Google'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => appState.signInWithGitHub(),
                icon: const Icon(Icons.code, size: 20),
                label: const Text('Continue with GitHub'),
              ),
            ),
            const SizedBox(height: 24),

            // Continue offline (prominent)
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: widget.onContinueOffline,
                child: const Text('Continue without account'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 7: Wire auth into main screen**

In `lib/screens/main_screen.dart`, add an auth gate. The app should show the auth screen on first launch if not logged in, but allow skipping. Store the "skipped auth" preference:

In `AppState`, add:
```dart
bool _hasSkippedAuth = false;
bool get showAuthScreen => !isLoggedIn && !_hasSkippedAuth;

void skipAuth() {
  _hasSkippedAuth = true;
  notifyListeners();
}
```

Load from SharedPreferences in `_loadSettings()`:
```dart
_hasSkippedAuth = prefs.getBool('has_skipped_auth') ?? false;
```

Save in `skipAuth()`:
```dart
final prefs = await SharedPreferences.getInstance();
await prefs.setBool('has_skipped_auth', true);
```

In `MainScreen.build()`, wrap the existing scaffold body:
```dart
final appState = context.watch<AppState>();
if (appState.showAuthScreen) {
  return AuthScreen(onContinueOffline: () => appState.skipAuth());
}
// ... existing scaffold
```

- [ ] **Step 8: Add account indicator to sidebar**

In `lib/widgets/tag_sidebar.dart`, add an account button at the bottom of the sidebar (near settings):

If logged in: show avatar/email with sign-out option.
If not logged in: show "Sign in" button that resets `_hasSkippedAuth`.

```dart
// Small account indicator widget
Widget _buildAccountIndicator(AppState appState) {
  if (appState.isLoggedIn) {
    return Tooltip(
      message: appState.currentUser?.email ?? 'Signed in',
      child: IconButton(
        icon: const Icon(Icons.account_circle, size: 20),
        onPressed: () => _showAccountMenu(appState),
      ),
    );
  }
  return TextButton.icon(
    icon: const Icon(Icons.login, size: 16),
    label: const Text('Sign in', style: TextStyle(fontSize: 12)),
    onPressed: () {
      // Reset skip flag to show auth screen
      appState.skipAuth(); // need a resetAuth method instead
    },
  );
}
```

Add `resetSkipAuth()` to AppState:
```dart
Future<void> resetSkipAuth() async {
  _hasSkippedAuth = false;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('has_skipped_auth', false);
  notifyListeners();
}
```

- [ ] **Step 9: Verify auth flow works**

```bash
flutter run -d macos
```

Expected:
1. First launch shows auth screen with email form, Google/GitHub buttons, and "Continue without account" button
2. Clicking "Continue without account" shows the normal app
3. Signing in with email works and navigates to main app
4. Account indicator shows in sidebar
5. Signing out returns to auth screen

- [ ] **Step 10: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/main.dart lib/services/supabase_service.dart lib/widgets/auth_screen.dart lib/providers/app_state.dart lib/screens/main_screen.dart lib/widgets/tag_sidebar.dart macos/Runner/Info.plist
git commit -m "feat: add Supabase auth with email, Google, GitHub login and offline mode"
```

---

## Task 4: Sync Service (Local → Cloud)

**Files:**
- Create: `lib/services/sync_service.dart`
- Modify: `lib/providers/app_state.dart`
- Modify: `lib/database/database_service.dart`

This task implements the unidirectional sync from local SQLite to Supabase, including paper metadata, tags, paper-tag associations, and shared catalog contribution.

- [ ] **Step 1: Add sync query methods to DatabaseService**

In `lib/database/database_service.dart`, add:

```dart
/// Get all papers marked dirty (need sync).
Future<List<Paper>> getDirtyPapers() async {
  final db = await database;
  final maps = await db.query('papers', where: 'dirty = 1 AND deleted_at IS NULL');
  return maps.map((m) => Paper.fromMap(m)).toList();
}

/// Get all soft-deleted papers that need sync.
Future<List<Paper>> getDeletedPapers() async {
  final db = await database;
  final maps = await db.query('papers', where: 'deleted_at IS NOT NULL AND dirty = 1');
  return maps.map((m) => Paper.fromMap(m)).toList();
}

/// Get all tags marked dirty.
Future<List<Tag>> getDirtyTags() async {
  final db = await database;
  final maps = await db.query('tags', where: 'dirty = 1');
  return maps.map((m) => Tag.fromMap(m)).toList();
}

/// Mark a paper as synced (dirty=0, store remote_id).
Future<void> markPaperSynced(int localId, int remoteId) async {
  final db = await database;
  await db.update('papers', {'dirty': 0, 'remote_id': remoteId}, where: 'id = ?', whereArgs: [localId]);
}

/// Mark a tag as synced.
Future<void> markTagSynced(int localId, int remoteId) async {
  final db = await database;
  await db.update('tags', {'dirty': 0, 'remote_id': remoteId}, where: 'id = ?', whereArgs: [localId]);
}

/// Get all tags for a paper (returns tag names for catalog contribution).
Future<List<String>> getTagNamesForPaper(int paperId) async {
  final db = await database;
  final results = await db.rawQuery('''
    SELECT t.name FROM tags t
    JOIN paper_tags pt ON t.id = pt.tag_id
    WHERE pt.paper_id = ?
  ''', [paperId]);
  return results.map((r) => r['name'] as String).toList();
}

/// Get all tags with their remote IDs for sync mapping.
Future<Map<int, int?>> getTagRemoteIdMap() async {
  final db = await database;
  final results = await db.query('tags', columns: ['id', 'remote_id']);
  return {for (final r in results) r['id'] as int: r['remote_id'] as int?};
}
```

- [ ] **Step 2: Create SyncService**

Create `lib/services/sync_service.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../database/database_service.dart';
import '../models/paper.dart';
import '../models/tag.dart';
import 'supabase_service.dart';

/// Handles unidirectional sync from local SQLite to Supabase.
class SyncService {
  final DatabaseService _db;

  SyncService(this._db);

  /// Run a full sync cycle. Returns number of items synced.
  Future<SyncResult> sync() async {
    if (!SupabaseService.isLoggedIn) return SyncResult.notLoggedIn();

    final userId = SupabaseService.currentUser!.id;
    int papersSynced = 0;
    int tagsSynced = 0;
    int deletionsSynced = 0;

    try {
      // 1. Sync tags first (papers reference tags via associations)
      tagsSynced = await _syncTags(userId);

      // 2. Sync papers
      papersSynced = await _syncPapers(userId);

      // 3. Sync deletions
      deletionsSynced = await _syncDeletions(userId);

      // 4. Sync paper-tag associations
      await _syncPaperTagAssociations(userId);

      return SyncResult(
        success: true,
        papersSynced: papersSynced,
        tagsSynced: tagsSynced,
        deletionsSynced: deletionsSynced,
      );
    } catch (e) {
      debugPrint('Sync error: $e');
      return SyncResult(success: false, error: e.toString());
    }
  }

  Future<int> _syncTags(String userId) async {
    final dirtyTags = await _db.getDirtyTags();
    if (dirtyTags.isEmpty) return 0;

    // Topological sort: sync parents before children
    final sorted = _topologicalSortTags(dirtyTags);
    int count = 0;

    for (final tag in sorted) {
      // Resolve parent remote_id
      int? parentRemoteId;
      if (tag.parentId != null) {
        final parentMap = await _db.getTagRemoteIdMap();
        parentRemoteId = parentMap[tag.parentId];
      }

      final data = {
        'user_id': userId,
        'name': tag.name,
        'parent_id': parentRemoteId,
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (tag.remoteId != null) {
        // Update existing
        await SupabaseService.client
            .from('user_tags')
            .update(data)
            .eq('id', tag.remoteId!);
        await _db.markTagSynced(tag.id!, tag.remoteId!);
      } else {
        // Insert new
        final response = await SupabaseService.client
            .from('user_tags')
            .upsert(data, onConflict: 'user_id,name,parent_id')
            .select('id')
            .single();
        await _db.markTagSynced(tag.id!, response['id'] as int);
      }
      count++;
    }

    return count;
  }

  Future<int> _syncPapers(String userId) async {
    final dirtyPapers = await _db.getDirtyPapers();
    if (dirtyPapers.isEmpty) return 0;

    int count = 0;
    // Batch in groups of 50
    for (int i = 0; i < dirtyPapers.length; i += 50) {
      final batch = dirtyPapers.skip(i).take(50).toList();

      for (final paper in batch) {
        final tagNames = await _db.getTagNamesForPaper(paper.id!);
        final titleHash = paper.syncKey?.startsWith('title:') == true
            ? paper.syncKey!.substring(6)
            : null;

        final data = {
          'user_id': userId,
          'arxiv_id': paper.arxivId,
          'title': paper.title,
          'authors': paper.authors,
          'abstract': paper.abstract,
          'bibtex': paper.bibtex,
          'sync_key': paper.syncKey,
          'updated_at': (paper.updatedAt ?? DateTime.now()).toIso8601String(),
        };

        final response = await SupabaseService.client
            .from('user_papers')
            .upsert(data, onConflict: 'user_id,sync_key')
            .select('id')
            .single();

        final remoteId = response['id'] as int;
        await _db.markPaperSynced(paper.id!, remoteId);

        // Contribute to shared catalog
        await _contributeToSharedCatalog(paper, tagNames, titleHash);
        count++;
      }
    }

    return count;
  }

  Future<int> _syncDeletions(String userId) async {
    final deletedPapers = await _db.getDeletedPapers();
    if (deletedPapers.isEmpty) return 0;

    int count = 0;
    for (final paper in deletedPapers) {
      if (paper.remoteId != null) {
        await SupabaseService.client
            .from('user_papers')
            .update({'deleted_at': paper.deletedAt!.toIso8601String()})
            .eq('id', paper.remoteId!);
      }
      await _db.markPaperSynced(paper.id!, paper.remoteId ?? 0);
      count++;
    }

    return count;
  }

  Future<void> _syncPaperTagAssociations(String userId) async {
    // Get all papers that have remote_ids (already synced)
    final db = _db;
    final allPapers = await db.getAllPapers();
    final tagRemoteIds = await db.getTagRemoteIdMap();

    for (final paper in allPapers) {
      if (paper.remoteId == null) continue;

      // Get local tags for this paper
      final tags = await db.getTagsForPaper(paper.id!);
      final remoteTagIds = <int>[];
      for (final tag in tags) {
        final remoteTagId = tagRemoteIds[tag.id];
        if (remoteTagId != null) remoteTagIds.add(remoteTagId);
      }

      if (remoteTagIds.isEmpty) continue;

      // Delete existing associations in cloud for this paper, then re-insert
      await SupabaseService.client
          .from('user_paper_tags')
          .delete()
          .eq('user_paper_id', paper.remoteId!);

      final associations = remoteTagIds.map((tagId) => {
        'user_paper_id': paper.remoteId!,
        'user_tag_id': tagId,
      }).toList();

      await SupabaseService.client
          .from('user_paper_tags')
          .insert(associations);
    }
  }

  Future<void> _contributeToSharedCatalog(Paper paper, List<String> tagNames, String? titleHash) async {
    try {
      await SupabaseService.client.rpc('upsert_shared_catalog', params: {
        'p_arxiv_id': paper.arxivId,
        'p_title_hash': titleHash,
        'p_title': paper.title,
        'p_authors': paper.authors,
        'p_abstract': paper.abstract,
        'p_tag_names': tagNames,
      });
    } catch (e) {
      // Non-critical — don't fail sync if catalog contribution fails
      debugPrint('Shared catalog contribution failed: $e');
    }
  }

  /// Topological sort: parents before children.
  List<Tag> _topologicalSortTags(List<Tag> tags) {
    final tagMap = {for (final t in tags) t.id!: t};
    final sorted = <Tag>[];
    final visited = <int>{};

    void visit(Tag tag) {
      if (visited.contains(tag.id!)) return;
      visited.add(tag.id!);
      if (tag.parentId != null && tagMap.containsKey(tag.parentId)) {
        visit(tagMap[tag.parentId!]!);
      }
      sorted.add(tag);
    }

    for (final tag in tags) {
      visit(tag);
    }
    return sorted;
  }
}

class SyncResult {
  final bool success;
  final int papersSynced;
  final int tagsSynced;
  final int deletionsSynced;
  final String? error;

  SyncResult({
    required this.success,
    this.papersSynced = 0,
    this.tagsSynced = 0,
    this.deletionsSynced = 0,
    this.error,
  });

  factory SyncResult.notLoggedIn() => SyncResult(success: false, error: 'Not logged in');

  int get totalSynced => papersSynced + tagsSynced + deletionsSynced;
}
```

- [ ] **Step 3: Wire sync into AppState**

In `lib/providers/app_state.dart`, add sync state and methods:

```dart
import '../services/sync_service.dart';

// Add to state fields:
SyncService? _syncService;
bool _isSyncing = false;
DateTime? _lastSyncedAt;
String? _syncError;

// Add getters:
bool get isSyncing => _isSyncing;
DateTime? get lastSyncedAt => _lastSyncedAt;
String? get syncError => _syncError;
```

In `initialize()`, after DB init:
```dart
_syncService = SyncService(_db);

// Load last sync time from prefs
final prefs = await SharedPreferences.getInstance();
final lastSyncStr = prefs.getString('last_synced_at');
if (lastSyncStr != null) _lastSyncedAt = DateTime.parse(lastSyncStr);
```

Add sync methods:
```dart
/// Trigger a sync. Called after login, on manual trigger, or periodically.
Future<void> triggerSync() async {
  if (_isSyncing || !isLoggedIn) return;
  _isSyncing = true;
  _syncError = null;
  notifyListeners();

  try {
    final result = await _syncService!.sync();
    if (result.success) {
      _lastSyncedAt = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_synced_at', _lastSyncedAt!.toIso8601String());
      _syncError = null;
    } else {
      _syncError = result.error;
    }
  } catch (e) {
    _syncError = e.toString();
  } finally {
    _isSyncing = false;
    notifyListeners();
  }
}
```

In the auth state change listener, trigger sync after login:
```dart
SupabaseService.authStateChanges.listen((authState) {
  _currentUser = authState.session?.user;
  if (_currentUser != null) {
    SupabaseService.getProfile().then((profile) {
      _userProfile = profile;
      notifyListeners();
      // Auto-sync on login
      triggerSync();
    });
  } else {
    _userProfile = null;
  }
  notifyListeners();
});
```

- [ ] **Step 4: Add sync indicator to sidebar**

In `lib/widgets/tag_sidebar.dart`, add a sync status indicator near the bottom:

```dart
Widget _buildSyncIndicator(AppState appState) {
  if (!appState.isLoggedIn) return const SizedBox.shrink();

  if (appState.isSyncing) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 8),
          Text('Syncing...', style: TextStyle(fontSize: 11)),
        ],
      ),
    );
  }

  final lastSync = appState.lastSyncedAt;
  final syncText = lastSync != null
      ? 'Synced ${_timeAgo(lastSync)}'
      : 'Not synced';

  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    child: Row(
      children: [
        Icon(
          appState.syncError != null ? Icons.sync_problem : Icons.sync,
          size: 14,
          color: appState.syncError != null ? Colors.orange : Colors.grey,
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(syncText, style: const TextStyle(fontSize: 11, color: Colors.grey))),
        InkWell(
          onTap: () => appState.triggerSync(),
          child: const Icon(Icons.refresh, size: 14, color: Colors.grey),
        ),
      ],
    ),
  );
}

String _timeAgo(DateTime dateTime) {
  final diff = DateTime.now().difference(dateTime);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}
```

- [ ] **Step 5: Verify sync works**

```bash
flutter run -d macos
```

Expected:
1. Sign in with an account
2. Sync triggers automatically
3. Sync indicator shows "Syncing..." then "Synced just now"
4. Check Supabase dashboard → Table Editor → `user_papers` to see synced data
5. Check `shared_catalog` for papers with arxiv_ids
6. Manual refresh button re-triggers sync

- [ ] **Step 6: Commit**

```bash
git add lib/services/sync_service.dart lib/providers/app_state.dart lib/database/database_service.dart lib/widgets/tag_sidebar.dart
git commit -m "feat: add local-to-cloud sync service with shared catalog contribution"
```

---

## Task 5: Recommendation Service & Discover Tab

**Files:**
- Create: `lib/services/recommendation_service.dart`
- Create: `lib/widgets/discover_tab.dart`
- Modify: `lib/providers/app_state.dart`
- Modify: `lib/screens/main_screen.dart`
- Modify: `lib/widgets/tag_sidebar.dart`

This task adds the recommendation service that calls Supabase RPC functions and the Discover tab UI to display recommendations.

- [ ] **Step 1: Create RecommendationService**

Create `lib/services/recommendation_service.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'supabase_service.dart';

class RecommendedPaper {
  final int catalogId;
  final String? arxivId;
  final String title;
  final String? authors;
  final String? abstract;
  final int readerCount;
  final num score; // match_score, tag_relevance, or trending_score

  RecommendedPaper({
    required this.catalogId,
    this.arxivId,
    required this.title,
    this.authors,
    this.abstract,
    required this.readerCount,
    required this.score,
  });

  factory RecommendedPaper.fromMap(Map<String, dynamic> map) {
    return RecommendedPaper(
      catalogId: map['catalog_id'] as int,
      arxivId: map['arxiv_id'] as String?,
      title: map['title'] as String,
      authors: map['authors'] as String?,
      abstract: map['abstract'] as String?,
      readerCount: map['reader_count'] as int,
      score: (map['match_score'] ?? map['tag_relevance'] ?? map['trending_score'] ?? 0) as num,
    );
  }
}

class Recommendations {
  final List<RecommendedPaper> collaborative;
  final List<RecommendedPaper> tagBased;
  final List<RecommendedPaper> trending;

  Recommendations({
    this.collaborative = const [],
    this.tagBased = const [],
    this.trending = const [],
  });

  bool get isEmpty => collaborative.isEmpty && tagBased.isEmpty && trending.isEmpty;
}

class RecommendationService {
  Future<Recommendations> fetchAll() async {
    if (!SupabaseService.isLoggedIn) return Recommendations();

    final userId = SupabaseService.currentUser!.id;

    try {
      final results = await Future.wait([
        _fetchCollaborative(userId),
        _fetchTagBased(userId),
        _fetchTrending(userId),
      ]);

      return Recommendations(
        collaborative: results[0],
        tagBased: results[1],
        trending: results[2],
      );
    } catch (e) {
      debugPrint('Recommendations fetch error: $e');
      return Recommendations();
    }
  }

  Future<List<RecommendedPaper>> _fetchCollaborative(String userId) async {
    final response = await SupabaseService.client
        .rpc('get_collaborative_recommendations', params: {'p_user_id': userId, 'p_limit': 20});
    return (response as List).map((r) => RecommendedPaper.fromMap(r as Map<String, dynamic>)).toList();
  }

  Future<List<RecommendedPaper>> _fetchTagBased(String userId) async {
    final response = await SupabaseService.client
        .rpc('get_tag_recommendations', params: {'p_user_id': userId, 'p_limit': 20});
    return (response as List).map((r) => RecommendedPaper.fromMap(r as Map<String, dynamic>)).toList();
  }

  Future<List<RecommendedPaper>> _fetchTrending(String userId) async {
    final response = await SupabaseService.client
        .rpc('get_trending_recommendations', params: {'p_user_id': userId, 'p_limit': 20});
    return (response as List).map((r) => RecommendedPaper.fromMap(r as Map<String, dynamic>)).toList();
  }
}
```

- [ ] **Step 2: Add recommendation state to AppState**

In `lib/providers/app_state.dart`:

```dart
import '../services/recommendation_service.dart';

// Add to state fields:
final RecommendationService _recommendationService = RecommendationService();
Recommendations _recommendations = Recommendations();
bool _isLoadingRecommendations = false;
bool _showDiscover = false;

// Add getters:
Recommendations get recommendations => _recommendations;
bool get isLoadingRecommendations => _isLoadingRecommendations;
bool get showDiscover => _showDiscover;

// Add methods:
Future<void> fetchRecommendations() async {
  if (!isLoggedIn) return;
  _isLoadingRecommendations = true;
  notifyListeners();

  try {
    _recommendations = await _recommendationService.fetchAll();
  } catch (e) {
    debugPrint('Failed to fetch recommendations: $e');
  } finally {
    _isLoadingRecommendations = false;
    notifyListeners();
  }
}

void showDiscoverTab() {
  _showDiscover = true;
  _viewingPaper = null;
  _isConfigMode = false;
  notifyListeners();
}

void hideDiscoverTab() {
  _showDiscover = false;
  notifyListeners();
}
```

After sync completes in `triggerSync()`, fetch recommendations:
```dart
if (result.success) {
  // ... existing success handling ...
  fetchRecommendations(); // fire-and-forget after sync
}
```

Also fetch on login (in auth state listener).

- [ ] **Step 3: Create Discover tab UI**

Create `lib/widgets/discover_tab.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../services/recommendation_service.dart';

class DiscoverTab extends StatelessWidget {
  const DiscoverTab({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final theme = Theme.of(context);
    final recs = appState.recommendations;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => appState.hideDiscoverTab(),
                tooltip: 'Back to library',
              ),
              const SizedBox(width: 8),
              Text('Discover', style: theme.textTheme.titleLarge),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () => appState.fetchRecommendations(),
                tooltip: 'Refresh recommendations',
              ),
            ],
          ),
        ),

        if (appState.isLoadingRecommendations)
          const Center(child: Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(),
          ))
        else if (recs.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  Icon(Icons.explore_outlined, size: 64, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(height: 16),
                  Text('No recommendations yet', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    'Recommendations improve as more users join and tag papers. Keep syncing your library!',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                if (recs.collaborative.isNotEmpty) ...[
                  _SectionHeader(title: 'Users like you also read', icon: Icons.people_outline),
                  ...recs.collaborative.map((r) => _RecommendationCard(paper: r)),
                  const SizedBox(height: 24),
                ],
                if (recs.tagBased.isNotEmpty) ...[
                  _SectionHeader(title: 'Based on your interests', icon: Icons.label_outline),
                  ...recs.tagBased.map((r) => _RecommendationCard(paper: r)),
                  const SizedBox(height: 24),
                ],
                if (recs.trending.isNotEmpty) ...[
                  _SectionHeader(title: 'Trending in your areas', icon: Icons.trending_up),
                  ...recs.trending.map((r) => _RecommendationCard(paper: r)),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(title, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
        ],
      ),
    );
  }
}

class _RecommendationCard extends StatelessWidget {
  final RecommendedPaper paper;
  const _RecommendationCard({required this.paper});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(paper.title, style: theme.textTheme.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
            if (paper.authors != null) ...[
              const SizedBox(height: 4),
              Text(paper.authors!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
            if (paper.abstract != null) ...[
              const SizedBox(height: 8),
              Text(paper.abstract!, style: theme.textTheme.bodySmall, maxLines: 3, overflow: TextOverflow.ellipsis),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.people, size: 14, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text('${paper.readerCount} readers', style: theme.textTheme.labelSmall),
                if (paper.arxivId != null) ...[
                  const SizedBox(width: 12),
                  Icon(Icons.link, size: 14, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text('arXiv:${paper.arxivId}', style: theme.textTheme.labelSmall),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Add Discover button to sidebar and route in main screen**

In `lib/widgets/tag_sidebar.dart`, add a Discover button (only shown when logged in):
```dart
if (appState.isLoggedIn)
  ListTile(
    leading: const Icon(Icons.explore, size: 20),
    title: const Text('Discover'),
    dense: true,
    selected: appState.showDiscover,
    onTap: () => appState.showDiscoverTab(),
  ),
```

In `lib/screens/main_screen.dart`, add the Discover tab route in the content area:
```dart
// In the Expanded content area, before existing routes:
if (appState.showDiscover)
  const DiscoverTab()
else if (appState.viewingPaper != null)
  // ... existing viewer
```

- [ ] **Step 5: Verify recommendations UI**

```bash
flutter run -d macos
```

Expected:
1. Sign in
2. "Discover" button appears in sidebar
3. Clicking it shows the Discover tab
4. If no data yet, shows "No recommendations yet" message
5. Back button returns to library
6. After more users sync data, recommendations will populate

- [ ] **Step 6: Commit**

```bash
git add lib/services/recommendation_service.dart lib/widgets/discover_tab.dart lib/providers/app_state.dart lib/screens/main_screen.dart lib/widgets/tag_sidebar.dart
git commit -m "feat: add recommendation engine with Discover tab UI"
```

---

## Task 6: LLM Chat Edge Function

**Files:**
- Create: `supabase/functions/chat-with-paper/index.ts`

This task creates the Supabase Edge Function that proxies chat requests to MiniMax M2.5 with rate limiting.

- [ ] **Step 1: Create the Edge Function**

Create `supabase/functions/chat-with-paper/index.ts`:

```typescript
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const MINIMAX_API_KEY = Deno.env.get("MINIMAX_API_KEY")!;
const MINIMAX_API_URL = "https://api.minimax.chat/v1/text/chatcompletion_v2";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const TIER_LIMITS: Record<string, number> = {
  free: 30,
  pro: 300,
};

const MAX_HISTORY_TURNS = 10;

Deno.serve(async (req) => {
  // CORS
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
        "Access-Control-Allow-Headers": "authorization, content-type, apikey",
      },
    });
  }

  try {
    // Verify auth
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401 });
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
    const token = authHeader.replace("Bearer ", "");
    const { data: { user }, error: authError } = await supabase.auth.getUser(token);

    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401 });
    }

    // Get profile for rate limiting
    const { data: profile } = await supabase
      .from("profiles")
      .select("tier, llm_calls_this_month")
      .eq("id", user.id)
      .single();

    if (!profile) {
      return new Response(JSON.stringify({ error: "Profile not found" }), { status: 404 });
    }

    const limit = TIER_LIMITS[profile.tier] || 30;
    if (profile.llm_calls_this_month >= limit) {
      return new Response(
        JSON.stringify({
          error: "Rate limit exceeded",
          limit,
          used: profile.llm_calls_this_month,
          tier: profile.tier,
        }),
        { status: 429 }
      );
    }

    // Pessimistic counting: increment BEFORE calling MiniMax
    await supabase
      .from("profiles")
      .update({ llm_calls_this_month: profile.llm_calls_this_month + 1 })
      .eq("id", user.id);

    // Parse request
    const { paper_title, authors, abstract: paperAbstract, bibtex, user_question, conversation_history } = await req.json();

    // Build messages
    const systemPrompt = `You are a research assistant helping understand academic papers. Be concise and precise. Here is the paper context:

Title: ${paper_title || "Unknown"}
${authors ? `Authors: ${authors}` : ""}
${paperAbstract ? `Abstract: ${paperAbstract}` : ""}
${bibtex ? `BibTeX: ${bibtex}` : ""}

Answer questions about this paper based on the context provided. If you don't have enough information to answer, say so clearly.`;

    const messages: Array<{ role: string; content: string }> = [
      { role: "system", content: systemPrompt },
    ];

    // Add conversation history (limited to MAX_HISTORY_TURNS)
    if (conversation_history && Array.isArray(conversation_history)) {
      const truncated = conversation_history.slice(-MAX_HISTORY_TURNS);
      for (const msg of truncated) {
        messages.push({ role: msg.role, content: msg.content });
      }
    }

    // Add current question
    messages.push({ role: "user", content: user_question });

    // Call MiniMax API with streaming
    const minimaxResponse = await fetch(MINIMAX_API_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${MINIMAX_API_KEY}`,
      },
      body: JSON.stringify({
        model: "MiniMax-Text-01",
        messages,
        stream: true,
        max_tokens: 2048,
        temperature: 0.7,
      }),
    });

    if (!minimaxResponse.ok) {
      const errorText = await minimaxResponse.text();
      console.error("MiniMax API error:", errorText);
      return new Response(
        JSON.stringify({ error: "LLM service error" }),
        { status: 502 }
      );
    }

    // Stream response back to client
    return new Response(minimaxResponse.body, {
      headers: {
        "Content-Type": "text/event-stream",
        "Cache-Control": "no-cache",
        "Connection": "keep-alive",
        "Access-Control-Allow-Origin": "*",
      },
    });
  } catch (error) {
    console.error("Edge function error:", error);
    return new Response(
      JSON.stringify({ error: "Internal server error" }),
      { status: 500 }
    );
  }
});
```

- [ ] **Step 2: Set MiniMax API key as secret**

```bash
supabase secrets set MINIMAX_API_KEY=your_minimax_api_key_here
```

- [ ] **Step 3: Deploy the Edge Function**

```bash
supabase functions deploy chat-with-paper
```

Expected: Function deploys successfully. Test with:
```bash
curl -X POST 'https://<your-project>.supabase.co/functions/v1/chat-with-paper' \
  -H 'Authorization: Bearer <user-jwt>' \
  -H 'Content-Type: application/json' \
  -d '{"paper_title":"Attention Is All You Need","authors":"Vaswani et al.","user_question":"What is the main contribution?"}'
```

- [ ] **Step 4: Commit**

```bash
git add supabase/functions/chat-with-paper/
git commit -m "feat: add chat-with-paper Edge Function with MiniMax proxy and rate limiting"
```

---

## Task 7: LLM Chat Flutter Service & UI

**Files:**
- Create: `lib/services/llm_chat_service.dart`
- Create: `lib/models/chat_message.dart`
- Create: `lib/widgets/paper_chat_panel.dart`
- Modify: `lib/providers/app_state.dart`
- Modify: `lib/screens/main_screen.dart`

This task adds the Flutter-side chat service and chat panel UI for paper understanding.

- [ ] **Step 1: Create ChatMessage model**

Create `lib/models/chat_message.dart`:

```dart
class ChatMessage {
  final String role; // 'user' or 'assistant'
  final String content;
  final DateTime timestamp;

  ChatMessage({
    required this.role,
    required this.content,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {'role': role, 'content': content};
}
```

- [ ] **Step 2: Create LLM chat service**

Create `lib/services/llm_chat_service.dart`:

```dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/chat_message.dart';
import 'supabase_service.dart';

class LlmChatService {
  /// Send a chat message about a paper. Returns the assistant's response.
  Future<String> chat({
    required String paperTitle,
    String? authors,
    String? abstract,
    String? bibtex,
    required String question,
    required List<ChatMessage> history,
  }) async {
    final session = SupabaseService.currentSession;
    if (session == null) throw Exception('Not logged in');

    // Truncate history to last 10 messages
    final truncatedHistory = history.length > 10
        ? history.sublist(history.length - 10)
        : history;

    final response = await SupabaseService.client.functions.invoke(
      'chat-with-paper',
      body: {
        'paper_title': paperTitle,
        'authors': authors,
        'abstract': abstract,
        'bibtex': bibtex,
        'user_question': question,
        'conversation_history': truncatedHistory.map((m) => m.toJson()).toList(),
      },
    );

    if (response.status != 200) {
      final body = response.data;
      if (response.status == 429) {
        throw RateLimitException(
          body['limit'] as int? ?? 30,
          body['used'] as int? ?? 0,
        );
      }
      throw Exception(body['error'] ?? 'Chat failed');
    }

    // Parse streamed SSE response into full text
    // For simplicity in v1, collect the full response
    final data = response.data;
    if (data is String) {
      return _parseStreamedResponse(data);
    }
    return data.toString();
  }

  String _parseStreamedResponse(String sseData) {
    final buffer = StringBuffer();
    for (final line in sseData.split('\n')) {
      if (line.startsWith('data: ')) {
        final jsonStr = line.substring(6).trim();
        if (jsonStr == '[DONE]') break;
        try {
          final json = jsonDecode(jsonStr);
          final delta = json['choices']?[0]?['delta']?['content'];
          if (delta != null) buffer.write(delta);
        } catch (e) {
          // Skip malformed lines
        }
      }
    }
    return buffer.toString();
  }
}

class RateLimitException implements Exception {
  final int limit;
  final int used;
  RateLimitException(this.limit, this.used);

  @override
  String toString() => 'Rate limit exceeded: $used/$limit calls used this month';
}
```

- [ ] **Step 3: Add chat state to AppState**

In `lib/providers/app_state.dart`:

```dart
import '../services/llm_chat_service.dart';
import '../models/chat_message.dart';

// Add to state fields:
final LlmChatService _llmChatService = LlmChatService();
final Map<int, List<ChatMessage>> _chatHistories = {}; // paperId → messages
bool _isChatLoading = false;
bool _showChatPanel = false;

// Add getters:
bool get isChatLoading => _isChatLoading;
bool get showChatPanel => _showChatPanel;
List<ChatMessage> getChatHistory(int paperId) => _chatHistories[paperId] ?? [];

// Add methods:
void toggleChatPanel() {
  _showChatPanel = !_showChatPanel;
  notifyListeners();
}

Future<void> sendChatMessage(Paper paper, String question) async {
  if (!isLoggedIn || paper.id == null) return;

  final history = _chatHistories.putIfAbsent(paper.id!, () => []);
  history.add(ChatMessage(role: 'user', content: question));
  _isChatLoading = true;
  notifyListeners();

  try {
    final response = await _llmChatService.chat(
      paperTitle: paper.title,
      authors: paper.authors,
      abstract: paper.abstract,
      bibtex: paper.bibtex,
      question: question,
      history: history,
    );

    history.add(ChatMessage(role: 'assistant', content: response));
  } on RateLimitException catch (e) {
    history.add(ChatMessage(
      role: 'assistant',
      content: 'You\'ve reached your monthly chat limit (${ e.used}/${e.limit}). Upgrade to Pro for more.',
    ));
  } catch (e) {
    history.add(ChatMessage(role: 'assistant', content: 'Sorry, something went wrong: $e'));
  } finally {
    _isChatLoading = false;
    notifyListeners();
  }
}

void clearChatHistory(int paperId) {
  _chatHistories.remove(paperId);
  notifyListeners();
}
```

- [ ] **Step 4: Create chat panel UI**

Create `lib/widgets/paper_chat_panel.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/paper.dart';

class PaperChatPanel extends StatefulWidget {
  final Paper paper;
  const PaperChatPanel({super.key, required this.paper});

  @override
  State<PaperChatPanel> createState() => _PaperChatPanelState();
}

class _PaperChatPanelState extends State<PaperChatPanel> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    context.read<AppState>().sendChatMessage(widget.paper, text);
    // Scroll to bottom after send
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final theme = Theme.of(context);
    final messages = appState.getChatHistory(widget.paper.id!);

    return Container(
      width: 350,
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: theme.dividerColor)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: theme.dividerColor)),
            ),
            child: Row(
              children: [
                const Icon(Icons.chat_outlined, size: 18),
                const SizedBox(width: 8),
                const Expanded(child: Text('Chat about this paper', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: () => appState.clearChatHistory(widget.paper.id!),
                  tooltip: 'Clear chat',
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => appState.toggleChatPanel(),
                  tooltip: 'Close chat',
                ),
              ],
            ),
          ),

          // Usage indicator
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                Text(
                  '${appState.llmCallsThisMonth}/${appState.llmCallsLimit} calls this month',
                  style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),

          // Messages
          Expanded(
            child: messages.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Ask questions about "${widget.paper.title}"',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(12),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      final isUser = msg.role == 'user';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
                          children: [
                            if (!isUser) ...[
                              CircleAvatar(
                                radius: 12,
                                backgroundColor: theme.colorScheme.primaryContainer,
                                child: Icon(Icons.smart_toy, size: 14, color: theme.colorScheme.primary),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: isUser ? theme.colorScheme.primaryContainer : theme.colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: SelectableText(msg.content, style: const TextStyle(fontSize: 13)),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),

          // Loading indicator
          if (appState.isChatLoading)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Row(
                children: [
                  SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 8),
                  Text('Thinking...', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),

          // Input
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: theme.dividerColor)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      hintText: 'Ask about this paper...',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      isDense: true,
                    ),
                    style: const TextStyle(fontSize: 13),
                    maxLines: 3,
                    minLines: 1,
                    onSubmitted: (_) => _send(),
                    enabled: !appState.isChatLoading,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send, size: 20),
                  onPressed: appState.isChatLoading ? null : _send,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: Wire chat panel into main screen**

In `lib/screens/main_screen.dart`, when viewing a paper and the user is logged in, show a chat toggle button and the chat panel:

```dart
// In the content area where EmbeddedPdfViewer is shown:
if (appState.viewingPaper != null)
  Row(
    children: [
      Expanded(child: EmbeddedPdfViewer(/* existing */)),
      if (appState.isLoggedIn && appState.showChatPanel && appState.viewingPaper != null)
        PaperChatPanel(paper: appState.viewingPaper!),
    ],
  )
```

Add a chat toggle button to the PDF viewer toolbar or as a floating action:
```dart
// Near the viewer, add a toggle button (only when logged in):
if (appState.isLoggedIn)
  IconButton(
    icon: Icon(appState.showChatPanel ? Icons.chat : Icons.chat_outlined),
    onPressed: () => appState.toggleChatPanel(),
    tooltip: 'Chat about this paper',
  ),
```

- [ ] **Step 6: Verify chat works end-to-end**

```bash
flutter run -d macos
```

Expected:
1. Sign in, open a paper in the viewer
2. Chat icon appears in toolbar
3. Clicking it opens the 350px chat panel on the right
4. Type a question, press Enter or send button
5. Loading indicator shows, then assistant response appears
6. Usage counter updates
7. Close button hides the panel
8. Clear chat empties history

- [ ] **Step 7: Commit**

```bash
git add lib/services/llm_chat_service.dart lib/models/chat_message.dart lib/widgets/paper_chat_panel.dart lib/providers/app_state.dart lib/screens/main_screen.dart
git commit -m "feat: add LLM chat panel for paper understanding via MiniMax"
```

---

## Task 8: Trending Computation Edge Function

**Files:**
- Create: `supabase/functions/compute-trending/index.ts`

This task creates the daily cron Edge Function that computes trending scores.

- [ ] **Step 1: Create the Edge Function**

Create `supabase/functions/compute-trending/index.ts`:

```typescript
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

Deno.serve(async (req) => {
  try {
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

    // Clear old trending scores
    await supabase.from("trending_scores").delete().neq("id", 0);

    // Compute trending: papers with most new readers in last 30 days
    // We approximate this by looking at shared_catalog entries with recent last_seen_at
    // and high reader_count
    const thirtyDaysAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString();

    const { data: candidates } = await supabase
      .from("shared_catalog")
      .select("id, reader_count, last_seen_at")
      .gte("last_seen_at", thirtyDaysAgo)
      .gt("reader_count", 1)
      .order("reader_count", { ascending: false })
      .limit(100);

    if (candidates && candidates.length > 0) {
      const maxReaderCount = candidates[0].reader_count;

      const scores = candidates.map((c: any) => {
        // Score = normalized reader_count * recency_weight
        const recencyDays = (Date.now() - new Date(c.last_seen_at).getTime()) / (1000 * 60 * 60 * 24);
        const recencyWeight = Math.max(0.1, 1 - recencyDays / 30);
        const normalizedReaders = c.reader_count / maxReaderCount;
        return {
          catalog_id: c.id,
          score: normalizedReaders * recencyWeight,
        };
      });

      // Insert trending scores
      await supabase.from("trending_scores").insert(scores);
    }

    return new Response(
      JSON.stringify({ success: true, computed: candidates?.length ?? 0 }),
      { headers: { "Content-Type": "application/json" } }
    );
  } catch (error) {
    console.error("Trending computation error:", error);
    return new Response(
      JSON.stringify({ error: "Computation failed" }),
      { status: 500 }
    );
  }
});
```

- [ ] **Step 2: Deploy and schedule**

```bash
supabase functions deploy compute-trending
```

Schedule as daily cron in Supabase Dashboard → SQL Editor:
```sql
SELECT cron.schedule(
  'compute-trending-daily',
  '0 2 * * *',
  $$
  SELECT net.http_post(
    url := 'https://<your-project>.supabase.co/functions/v1/compute-trending',
    headers := jsonb_build_object('Authorization', 'Bearer ' || current_setting('supabase.service_role_key'))
  );
  $$
);
```

Alternatively, use `pg_net` extension if available, or invoke manually for testing.

- [ ] **Step 3: Commit**

```bash
git add supabase/functions/compute-trending/
git commit -m "feat: add daily trending score computation Edge Function"
```

---

## Task 9: Settings Account Section & Final Polish

**Files:**
- Modify: `lib/widgets/settings_view.dart`
- Modify: `lib/providers/app_state.dart`

This task adds account management to the settings view and final polish.

- [ ] **Step 1: Add account section to settings**

In `lib/widgets/settings_view.dart`, add an account section showing:
- Login status (email, provider)
- Current tier (Free/Pro)
- LLM usage (X/Y calls this month)
- Sign out button
- If not logged in: "Sign in to unlock cloud features" with sign-in button

```dart
Widget _buildAccountSection(AppState appState, ThemeData theme) {
  if (!appState.isLoggedIn) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.cloud_off),
        title: const Text('Not signed in'),
        subtitle: const Text('Sign in to sync, get recommendations, and chat with papers'),
        trailing: FilledButton(
          onPressed: () => appState.resetSkipAuth(),
          child: const Text('Sign in'),
        ),
      ),
    );
  }

  return Card(
    child: Column(
      children: [
        ListTile(
          leading: const Icon(Icons.account_circle),
          title: Text(appState.currentUser?.email ?? 'Unknown'),
          subtitle: Text('${appState.userTier.toUpperCase()} tier'),
        ),
        ListTile(
          leading: const Icon(Icons.chat),
          title: const Text('Chat usage this month'),
          subtitle: Text('${appState.llmCallsThisMonth} / ${appState.llmCallsLimit} calls'),
          trailing: SizedBox(
            width: 100,
            child: LinearProgressIndicator(
              value: appState.llmCallsThisMonth / appState.llmCallsLimit,
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.sync),
          title: Text(appState.lastSyncedAt != null
              ? 'Last synced: ${appState.lastSyncedAt}'
              : 'Not synced yet'),
          trailing: TextButton(
            onPressed: () => appState.triggerSync(),
            child: const Text('Sync now'),
          ),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('Sign out'),
          onTap: () => appState.signOut(),
        ),
      ],
    ),
  );
}
```

- [ ] **Step 2: Refresh profile after chat calls**

In AppState, after each chat call, refresh the profile to get updated `llm_calls_this_month`:

```dart
// In sendChatMessage, after successful response:
SupabaseService.getProfile().then((profile) {
  _userProfile = profile;
  notifyListeners();
});
```

- [ ] **Step 3: Add .env to .gitignore**

Ensure Supabase secrets and local config are not committed:

```bash
echo "supabase/.env" >> .gitignore
echo "supabase/.temp/" >> .gitignore
```

- [ ] **Step 4: Update CLAUDE.md with Supabase commands**

In `CLAUDE.md`, add under Common Commands:

```bash
supabase start           # Start local Supabase (Docker)
supabase db push         # Push migrations to remote
supabase functions deploy # Deploy all Edge Functions
supabase secrets set KEY=VAL # Set environment secret
```

And add to Architecture section: a brief note about the Supabase backend for auth, sync, recommendations, and LLM chat.

- [ ] **Step 5: Final verification**

```bash
flutter run -d macos
```

Verify the complete flow:
1. App launches, shows auth screen
2. Sign in with email or social
3. Main app loads, sync triggers automatically
4. Sync indicator shows progress and completion
5. Discover tab shows recommendations (or empty state)
6. Open a paper, click chat icon, ask questions
7. Chat responses stream in
8. Settings shows account info and usage
9. Sign out returns to auth screen
10. "Continue without account" works — full app minus cloud features

- [ ] **Step 6: Commit**

```bash
git add lib/widgets/settings_view.dart lib/providers/app_state.dart .gitignore CLAUDE.md
git commit -m "feat: add settings account section, finalize Supabase integration"
```

---

## Summary

| Task | Description | Dependencies |
|------|-------------|-------------|
| 1 | Supabase project + schema + RLS + RPC | None |
| 2 | Local SQLite migration v6 | None |
| 3 | Auth service + login UI | Tasks 1, 2 |
| 4 | Sync service (local → cloud) | Task 3 |
| 5 | Recommendation service + Discover tab | Tasks 1, 4 |
| 6 | LLM chat Edge Function | Task 1 |
| 7 | LLM chat Flutter service + UI | Tasks 3, 6 |
| 8 | Trending computation cron | Task 1 |
| 9 | Settings account section + polish | Tasks 3-7 |

Tasks 1 and 2 can be done in parallel. Tasks 6 and 8 can be done in parallel with Tasks 4-5. Task 9 is the final integration step.

# External Integrations

**Analysis Date:** 2026-04-16

## APIs & External Services

**arXiv:**
- Service: arXiv.org API for academic paper metadata
- SDK/Client: `http` package + XML parsing
- Implementation: `lib/services/arxiv_service.dart`
- Endpoints:
  - Query: `http://export.arxiv.org/api/query?id_list={arxivId}`
  - PDF download: `https://arxiv.org/pdf/{arxivId}.pdf`
- Usage: Fetch paper titles, authors, abstracts, categories by arXiv ID
- Auth: None (public API, no authentication)

**DBLP Computer Science Bibliography:**
- Service: DBLP for BibTeX metadata and publication venues
- SDK/Client: `http` package + JSON parsing
- Implementation: `lib/services/bibtex_service.dart`
- Endpoints:
  - Search: `https://dblp.org/search/publ/api?q={query}&h=10&format=json`
- Usage: Search paper metadata (title, authors, venue, year) for BibTeX import
- Auth: None (public API)

**ACM Digital Library:**
- Service: ACM.org for paper publication records
- SDK/Client: `http` package + HTML parsing (via `html_unescape`)
- Implementation: `lib/services/bibtex_service.dart`
- Endpoints:
  - Search: `https://dl.acm.org/action/doSearch` (form-encoded query)
- Usage: Alternative paper search source for BibTeX generation
- Auth: None (public search)

**MiniMax AI (Chat API):**
- Service: LLM inference for paper Q&A
- SDK/Client: Called via Supabase Edge Function only (not direct)
- Configuration: `MINIMAX_API_KEY` secret set in Supabase
- API URL: `https://api.minimax.chat/v1/text/chatcompletion_v2`
- Usage: `supabase/functions/chat-with-paper/index.ts` sends requests
- Auth: API key in Supabase secret, not exposed to client

## Data Storage

**Local Database:**
- Type: SQLite 3
- Client: `sqflite_common_ffi` (FFI-based for desktop)
- Location: `~/Library/Application Support/paper_suitcase.db` (macOS)
- Schema version: 6 (migrations in `lib/database/database_service.dart`)
- Tables:
  - `entries` - External directory references
  - `papers` - Paper metadata (title, authors, abstract, extracted_text, arxiv_id, bibtex, etc.)
  - `tags` - Hierarchical tag tree (parent_id self-references)
  - `paper_tags` - Junction table for many-to-many paper-tag associations
  - `papers_fts` - FTS5 virtual table for full-text search (BM25 ranking)
- Special: FTS table kept in sync with `papers` via SQL triggers (INSERT, UPDATE, DELETE)

**Cloud Database:**
- Type: PostgreSQL (hosted by Supabase)
- Client: `supabase_flutter` (PostgREST client)
- Connection: Authenticated via Supabase JWT token
- Tables (cloud):
  - `profiles` - User profiles (tier: free/pro, llm_calls_this_month, llm_calls_reset_at)
  - `user_papers` - User's papers synced from local (sync_key, remote_id, dirty flag)
  - `user_tags` - User's tags synced from local (remote_id, dirty flag)
  - `user_paper_tags` - Junction for synced paper-tag associations
  - `shared_catalog` - Deduplicated papers across all users (arxiv_id, doi, title_hash, reader_count)
  - `catalog_tags` - Aggregated tags on shared catalog
  - `trending_scores` - Computed daily by `compute-trending` function

**Cache Storage:**
- Type: Filesystem (macOS Application Support directory)
- Location: `{entry_path}/.papersuitcase/` per entry
- Contents (managed by `ManifestService`):
  - `manifest.json` - Index of papers and metadata
  - `{sha1}.txt` - Extracted PDF text (keyed by SHA1)
  - `{sha1}.png` - PDF thumbnails (keyed by SHA1)
  - `references.bib` - BibTeX export for the entry

## Authentication & Identity

**Auth Provider:**
- Service: Supabase Auth (PostgreSQL + JWT)
- Implementation: `lib/services/supabase_service.dart`
- Supported Methods:
  - Email/password: `signUpWithEmail()`, `signInWithEmail()`
  - Google OAuth: `signInWithOAuth(OAuthProvider.google)` with redirect to `io.supabase.papersuitcase://login-callback`
  - GitHub OAuth: `signInWithOAuth(OAuthProvider.github)` with redirect to `io.supabase.papersuitcase://login-callback`
- Token Management:
  - Access token: JWT in `Authorization: Bearer {token}` header
  - Refresh token: Stored in secure storage by `supabase_flutter`
- Session Handling:
  - `SupabaseService.currentUser` - Currently authenticated user (UUID)
  - `SupabaseService.currentSession` - Auth session with tokens
  - Stream: `SupabaseService.authStateChanges` - Reactive auth state updates
- Profile Auto-creation: Trigger `handle_new_user()` creates profile record on signup

## Monitoring & Observability

**Error Tracking:**
- None (not detected)
- Default: Errors logged to console via `debugPrint()` and `print()`

**Logs:**
- Approach: Console logging (stdout/stderr)
- Implementation: `debugPrint()` in app, `console.error()` in Edge Functions
- No centralized log aggregation

## CI/CD & Deployment

**Hosting:**
- Cloud Backend: Supabase (PostgreSQL, Auth, Edge Functions, realtime)
- Local Development: Docker-based Supabase via `supabase start`
- App Distribution: Not detected (manual macOS app build)

**Edge Functions Deployment:**
- Platform: Supabase Edge Functions (Deno runtime)
- Deployed functions:
  - `chat-with-paper` - LLM chat with rate limiting per user tier
  - `compute-trending` - Daily scheduled job to compute trending scores
- Deployment: `supabase functions deploy` (via CLI)
- Environment Variables:
  - `MINIMAX_API_KEY` - LLM API key
  - `SUPABASE_URL` - Supabase project URL
  - `SUPABASE_SERVICE_ROLE_KEY` - Service role key for admin access

## Environment Configuration

**Required env vars (Supabase backend/Edge Functions):**
- `SUPABASE_URL` - Project URL (e.g., `https://rdfwekkbpsdwzytbttlk.supabase.co`)
- `SUPABASE_SERVICE_ROLE_KEY` - Admin-level Supabase key (for Edge Functions)
- `MINIMAX_API_KEY` - MiniMax LLM API key (for chat function)

**App-side Configuration:**
- Hardcoded in `lib/services/supabase_service.dart`:
  - Supabase URL: `https://rdfwekkbpsdwzytbttlk.supabase.co`
  - Anon public key: `sb_publishable_Qcl9dCHY5RVt3DPasp3IlQ_6DxmHGFo` (safe to expose)
- Deep link callback: `io.supabase.papersuitcase://login-callback` (registered in macOS app)

**Secrets location:**
- Client secrets: Not used (public anon key only)
- Server secrets: Supabase secrets management CLI (`supabase secrets set KEY=VAL`)

## Webhooks & Callbacks

**Incoming:**
- None detected

**Outgoing:**
- OAuth callback: Deep link `io.supabase.papersuitcase://login-callback` for Google/GitHub OAuth
- Sync webhooks: None (unidirectional sync via polling/API calls, not event-driven)

## Real-time Communication

**Supabase Realtime:**
- Enabled in `supabase/config.toml`: `[realtime] enabled = true`
- Usage: Not explicitly detected in app code (potential for future use)
- Current sync: Polling-based via `SyncService` (unidirectional to cloud)

## Data Sync Architecture

**Direction:** Unidirectional (local SQLite → cloud Supabase)

**Mechanism:**
- Local dirty tracking: `papers.dirty`, `tags.dirty`, `papers.deleted_at`
- Sync key strategy (in `lib/database/database_service.dart`):
  - `arxiv:` + arxivId (primary identifier)
  - `hash:` + content hash (fallback for PDFs without arXiv)
  - `title:` + SHA256(title + authors) (last resort)
- Sync process in `lib/services/sync_service.dart`:
  1. Sync tags (topologically sorted to respect parent_id constraints)
  2. Sync papers (bulk upsert by sync_key)
  3. Sync deletions (set deleted_at timestamp, soft delete)
  4. Sync paper-tag associations (junction table)

**Rate Limiting:**
- Per-user monthly LLM calls tracked in `profiles.llm_calls_this_month`
- Free tier: 30 calls/month
- Pro tier: 300 calls/month
- Enforced in `chat-with-paper` Edge Function (returns 429 if exceeded)

---

*Integration audit: 2026-04-16*

# Paper Suitecase: Symlink-Only Redesign

## Overview

Redesign Paper Suitecase around a symlink-only model. The app never copies PDFs — it links to external folders ("entries") that can be synced by OneDrive, Dropbox, or any other mechanism. A `.papersuitecase` cache folder in each entry makes metadata portable across installs.

## Migration Strategy

Clean break — drop the existing database and start fresh. This is a personal-use app; no backward compatibility needed. Users re-add their entry folders. If those folders have `.papersuitecase/` caches from a prior install, metadata is recovered automatically.

## Preserved Features (Not Part of Redesign)

The following existing features are kept as-is:
- Embedded PDF viewer with tab management
- Theme settings (light/dark/system)
- PDF reader type selection (embedded/system/custom)
- Paper selection, drag-and-drop papers onto tags
- Reveal paper in Finder
- Settings view

## Core Concepts

### Entries

An entry is a top-level reference to an external directory. Entries are shown in the sidebar under "ENTRIES". Users create entries by dropping a folder onto the sidebar.

- Flat list (no nesting of entries inside entries)
- Subfolder structure within an entry is preserved and navigable in the sidebar
- No default entry — users must add at least one before they can do anything
- Subfolders are derived from the filesystem at scan time, not stored in the database

### Papers

Papers are always references to PDF files inside entries. No copy mode.

- A paper belongs to exactly one entry (determined by its file path)
- Papers can have zero or more global tags
- Papers appear as soon as they're detected on disk; metadata populates in the background

### Tags

Tags are global across all entries. They serve as project workspaces for organizing papers and managing BibTeX.

- Hierarchical (parent/child)
- A tag can contain papers from any entry
- Primary BibTeX workflow is tag-scoped

## Data Model

### Database Schema (v5)

```sql
entries (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  path TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  added_at TEXT NOT NULL
)

papers (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  entry_id INTEGER NOT NULL REFERENCES entries(id) ON DELETE CASCADE,
  file_path TEXT NOT NULL UNIQUE,
  title TEXT,
  authors TEXT,
  abstract TEXT,
  extracted_text TEXT,
  arxiv_id TEXT,
  arxiv_url TEXT,
  bibtex TEXT,
  bib_status TEXT NOT NULL DEFAULT 'none',  -- none | auto_fetched | verified
  content_hash TEXT,  -- SHA256 of first 64KB, for rename detection
  added_at TEXT NOT NULL
)

tags (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  parent_id INTEGER REFERENCES tags(id) ON DELETE SET NULL,
  UNIQUE(name, parent_id)
)

paper_tags (
  paper_id INTEGER REFERENCES papers(id) ON DELETE CASCADE,
  tag_id INTEGER REFERENCES tags(id) ON DELETE CASCADE,
  PRIMARY KEY (paper_id, tag_id)
)

papers_fts USING fts5(title, authors, abstract, extracted_text, content=papers)
-- Sync triggers same as current
```

### `.papersuitecase/` Cache Per Entry

Created at the entry root directory:

```
~/OneDrive/Research/.papersuitecase/
├── manifest.json
├── thumbnails/
│   ├── a1b2c3.png
│   └── d4e5f6.png
├── texts/
│   ├── a1b2c3.txt
│   └── d4e5f6.txt
└── references.bib
```

**File key**: SHA1 hash of the relative path from entry root (e.g., `sha1("ML/transformers.pdf")` → `a1b2c3`). Stable across machines if folder structure is the same.

**texts/**: Extracted text per paper, stored as plain `.txt` files. Keeps manifest small while making text portable for fresh install recovery without re-extraction.

**manifest.json**:

```json
{
  "version": 1,
  "papers": {
    "ML/transformers.pdf": {
      "title": "Attention Is All You Need",
      "authors": "Vaswani et al.",
      "abstract": "...",
      "extracted_text_hash": "sha256:...",
      "arxiv_id": "1706.03762",
      "bibtex": "@article{vaswani2017attention, ...}",
      "bib_status": "verified",
      "tags": ["Machine Learning", "ML/Transformers"],
      "added_at": "2026-03-15T10:00:00Z"
    }
  }
}
```

Tags stored as flat string arrays with full hierarchical path (e.g., `"ML/Transformers"`). On recovery, tag hierarchy is recreated.

Manifest updated on metadata changes, debounced (not on every keystroke).

**references.bib**: Combined BibTeX for all papers in the entry. Regenerated when any paper's BibTeX changes.

### Fresh Install Recovery

1. User adds entry folders (same folders as before)
2. App finds `.papersuitecase/manifest.json` in each
3. Rebuilds central DB from manifests — papers, tags, bibtex all restored
4. Thumbnails already cached, no regeneration needed
5. Only papers not in manifest (new files since last run) need text extraction

## Sidebar & Navigation

### Layout

```
┌─────────────────────┐
│ Search Bar           │
├─────────────────────┤
│ All Papers (42)     │
├─────────────────────┤
│ ENTRIES             │
│ ▼ Research (15)     │
│   ├── ML (8)        │
│   ├── CV (5)        │
│   └── NLP (2)       │
│ ▼ Reading List (7)  │
│ ► Course Notes (20) │
├─────────────────────┤
│ TAGS                │
│ ▼ Machine Learning  │
│   ├── Transformers  │
│   └── RL            │
│ Untagged (12)       │
├─────────────────────┤
│ Settings             │
└─────────────────────┘
```

### Behavior

- **All Papers**: shows every paper across all entries
- **Entry**: shows all papers in that folder + subfolders; subfolders are expandable/collapsible
- **Tag**: shows papers with that tag across all entries
- **Untagged**: papers with no tags assigned
- **Entry + tag co-selection**: clicking a tag keeps the current entry selection (filters to intersection). Clicking an entry keeps the current tag. Clicking "All Papers" clears both.
- Drop a folder onto the ENTRIES section to create a new entry
- Counts shown next to each item, scoped to current filters
- Navigation history tracks: selected entry/subfolder path, selected tag, search query. Subfolders identified by relative path string (not DB ID since they're filesystem-derived).

## Live Folder Scanning

### Scan Triggers

- App window gains focus
- Manual refresh button per entry
- On entry creation (first scan)

### Scan Logic

1. Walk entry directory recursively, find all `.pdf` files
2. Compare against DB by relative path
3. **New path**: check if any paper removed in this same scan cycle has matching `content_hash` (SHA256 of first 64KB) → treat as rename (update path, preserve tags/bibtex). Otherwise treat as new paper.
4. **Missing path**: remove from DB, delete thumbnail. Content hash is checked against new paths (step 3) before deletion is finalized.
5. Renamed + content changed = new file (no fuzzy matching)

### Background Processing for New Papers

Papers appear in grid immediately (title = filename). Then in background:

1. Extract text → update title/metadata
2. Generate thumbnail → write to `.papersuitecase/thumbnails/`
3. Auto-fetch BibTeX: arXiv ID first → DBLP → ACM. Set `bib_status = auto_fetched`
4. Update manifest.json

## Search Bar & Paper Acquisition

### Input Detection

- **arXiv URL** (`arxiv.org/abs/...` or `arxiv.org/pdf/...`): fetch metadata, offer to download PDF
- **DOI URL** (`doi.org/...`): resolve metadata, try to find open-access PDF
- **Other URL** (`openreview.net`, `semanticscholar.org`, etc.): attempt metadata extraction, offer download if PDF available
- **Plain text**: dual mode — search local papers (FTS5, immediate) + search arXiv API (below local results)

### Download Flow

1. Show metadata preview (title, authors, abstract)
2. User picks target entry + subfolder (required)
3. PDF downloaded to that folder on disk
4. Paper inserted directly into DB with pre-populated metadata (title, authors, abstract, arxiv_id, bibtex). Next scan sees the path already exists and skips it.
5. If no entries exist: download action disabled with message "Add an entry folder first"

### Paper Deletion

"Delete" in the app only un-indexes the paper — removes from DB, tags, and manifest. **Never deletes files from disk.** Users delete actual PDFs via Finder if desired (use "Reveal in Finder").

### Error Handling

- **Entry folder missing**: if an entry's root path no longer exists at scan time, show a warning badge on the entry. Papers remain in DB but marked as inaccessible.
- **Permission errors / symlink loops**: skip the problematic path, log a warning, continue scanning.
- **Overlapping entries**: if the same PDF path falls under two entries, it belongs to whichever entry was added first (first match by path prefix).

## BibTeX Management

### Tag-Scoped Workflow

1. User creates tag for a project (e.g., "CVPR 2026 Submission")
2. Tags relevant papers from any entry
3. Selects the tag → sees all related papers
4. BibTeX panel on the tag view:
   - **Status overview**: "12 papers — 8 have BibTeX, 4 missing"
   - **Per-paper status**: checkmark (verified) / warning (auto_fetched, needs review) / X (missing)
   - **Batch auto-fetch**: search for all missing BibTeX in one action
   - **Per-paper actions**: fetch, edit, verify, mark as reviewed
   - **Export**: "Copy all BibTeX" or "Save as .bib file" — combined `.bib` for just papers in this tag
   - **Citation keys** shown inline, easy to copy individually

### BibTeX Status Field

`bib_status` per paper:
- `none`: no BibTeX found or attempted
- `auto_fetched`: found automatically, not human-verified
- `verified`: user has reviewed and confirmed

### Auto-Fetch Sources (priority order)

1. arXiv ID (if available) — fastest, most reliable
2. DBLP (by title search)
3. ACM (by title search)

## Legacy Code Removal

### Remove Entirely

- **Copy mode**: `PdfService.storageDirectory` (`~/.config/Paper Suitecase/papers/`), all file copy logic, `is_symbolic_link` field
- **FolderDropDialog**: replaced by direct entry creation on folder drop
- **ImportDialog**: replaced by entry creation (folders) and search bar (URLs/arXiv)
- **FolderImportService**: replaced by automatic live scanning
- **ReferenceService**: absorbed into BibTeX management on tag view

### Significantly Refactor

- **AppState** (~51KB): split into focused concerns — entry management, paper state, tag state, search, UI state
- **TagSidebar** (~52KB): restructure for entries section + tags section
- **DatabaseService**: v5 migration, folders→entries, remove `is_symbolic_link`, add `bib_status`
- **PdfService**: remove copy/storage, keep extraction + thumbnails (write to `.papersuitecase/thumbnails/`)
- **BibtexService**: add batch fetch, status tracking, tag-scoped export

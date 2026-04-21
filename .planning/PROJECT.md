# Paper Suitcase — Download Queue

## What This Is

A queued download system for Paper Suitcase's arXiv import flow. Currently, fetching an arXiv paper blocks the UI while the PDF downloads. This replaces that with a background download queue — parallel downloads with full progress detail, a floating download manager panel, auto-import on completion, and persistence across app restarts.

## Core Value

The user can keep working (browsing, tagging, reading papers) while arXiv PDFs download in the background.

## Requirements

### Validated

- ✓ arXiv metadata fetch via URL — existing (`lib/services/arxiv_service.dart`)
- ✓ PDF import and text extraction — existing (`lib/services/pdf_service.dart`)
- ✓ Entry scanning and manifest management — existing (`lib/services/entry_scanner_service.dart`, `lib/services/manifest_service.dart`)
- ✓ SQLite persistence with manual migrations — existing (`lib/database/database_service.dart`, v6)
- ✓ Single AppState with ChangeNotifier/Provider — existing (`lib/providers/app_state.dart`)
- ✓ Custom macOS title bar and sidebar layout — existing (`lib/screens/main_screen.dart`)

### Active

- [ ] Fetching arXiv metadata auto-queues PDF download (no extra "Download" click)
- [ ] Downloads run in parallel in the background (non-blocking)
- [ ] Download manager shows full detail per job: progress bar, speed, file size, retry, cancel
- [ ] New sidebar item above "Synced 2d ago" opens the download manager as a floating overlay
- [ ] Completed downloads auto-import into the current entry and appear in paper grid
- [ ] Failed downloads auto-retry once, then show manual retry button
- [ ] Download queue persists to disk and resumes on app restart

### Out of Scope

- Batch arXiv import (paste multiple URLs at once) — separate feature, not part of this work
- Download from non-arXiv sources (generic URL download) — arXiv-only for now
- Download speed throttling / bandwidth limits — not needed for academic PDFs
- Cloud sync of download queue state — queue is local-only

## Context

Paper Suitcase is a mature Flutter desktop (macOS) app for managing academic PDFs. The existing arXiv flow (`ArxivService`) fetches metadata from the arXiv API and downloads PDFs via HTTP. The download currently happens synchronously in the UI flow, blocking user interaction.

The app uses a single `AppState` ChangeNotifier for all state. SQLite (via `sqflite_common_ffi`) handles persistence with manual schema migrations (currently v6). Services are stateless and injected into AppState.

The sidebar (`TagSidebar`) has an existing sync status indicator ("Synced 2d ago") at the bottom — the download manager trigger goes above this.

## Constraints

- **State management**: Must use existing Provider/ChangeNotifier pattern — no Riverpod
- **Database**: SQLite with manual migrations — new table for download queue (v7 migration)
- **Platform**: macOS desktop only — can use platform-specific file I/O
- **HTTP client**: Use existing `http` package for downloads
- **UI style**: Match existing macOS-style design (SF Pro, rounded corners, dark/light theme support)

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Parallel downloads (no concurrency limit) | Academic PDFs are small (~1-5MB), network isn't the bottleneck | — Pending |
| Persist queue to SQLite (not JSON file) | Consistent with existing data layer, supports queries | — Pending |
| Auto-queue on metadata fetch | Reduces clicks — user wants the PDF, no need for confirmation step | — Pending |
| Floating overlay for download manager | Non-intrusive, can be dismissed, doesn't rearrange sidebar layout | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? -> Move to Out of Scope with reason
2. Requirements validated? -> Move to Validated with phase reference
3. New requirements emerged? -> Add to Active
4. Decisions to log? -> Add to Key Decisions
5. "What This Is" still accurate? -> Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-04-21 after initialization*

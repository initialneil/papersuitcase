# Windows Release Pipeline — Design

**Date:** 2026-05-13
**Status:** Approved, ready for implementation plan
**Repo:** initialneil/papersuitcase

## Goal

Every invocation of the `/release` skill produces both a macOS DMG (existing behavior) and a Windows NSIS installer (new), both attached to the same GitHub Release. Existing installs on both platforms auto-update via a shared Sparkle/WinSparkle appcast served from `docs/`.

## Non-goals

- Code signing the Windows installer. SmartScreen warning on first run is acceptable for v1, matching the existing unsigned Mac flow (which already documents "right-click → Open").
- EdDSA signing of WinSparkle updates. Skipped for v1; can be added later as a pure CI change without rebuilding the Windows app.
- MSIX / winget / Microsoft Store distribution.
- Linux release.
- File-association registration for `.pdf` on Windows.

## Decisions (resolved during brainstorming)

| Decision | Choice | Rationale |
|---|---|---|
| Build location | GitHub Actions `windows-latest` runner | User has no Windows machine; CI is free for public repos and avoids two-machine coordination. |
| Artifact format | NSIS installer (`.exe`) | Familiar Windows UX (Start Menu shortcut, uninstaller). Requires only `makensis` on the runner. |
| Code signing | None for v1 | Consistent with existing unsigned Mac flow. SmartScreen "More info → Run anyway" mirrors macOS "right-click → Open". |
| Auto-update | WinSparkle, integrated in `windows/runner/` | User explicitly wants auto-update parity with Mac. |
| Update signing | Skipped for v1 | Consistent with unsigned installer decision. Threat model: attacker who can replace release assets can also replace appcast, so signing only helps if those are compromised separately. |
| CI behavior | Skill waits for CI via `gh run watch` | Single atomic "release done" moment. ~5–10 min wait is acceptable vs. coming back to verify later. |
| Appcast structure | Single `docs/appcast.xml` with per-item `sparkle:os` attribute | Both Sparkle and WinSparkle filter by OS. One file to maintain. |

## Architecture

### Components added

1. `windows/` — Flutter Windows scaffold (generated via `flutter create --platforms=windows .`)
2. `windows/CMakeLists.txt` modification — `FetchContent` pulls WinSparkle release ZIP
3. `windows/runner/flutter_window.cpp` modification — WinSparkle init after main window creation
4. `installer/papersuitcase.nsi` — NSIS installer script
5. `.github/workflows/release-windows.yml` — Windows build & upload workflow

### Components modified

- `.claude/skills/release/SKILL.md` — new steps for Windows orchestration
- `docs/appcast.xml` — extended to per-item `sparkle:os` attribute; each release writes two `<item>` entries

## Component details

### Flutter Windows scaffold

One-time setup: `flutter create --platforms=windows .` at repo root, then commit the generated `windows/` directory. The codebase has no `Platform.isMacOS` / `Platform.isWindows` branches today, so the app should build for Windows without source changes. The first CI run is the smoke test. Any platform-specific bugs (file paths, window chrome, focus traversal) get filed as follow-up fixes — not blocking this design.

The `window_manager` plugin already supports Windows, `sqflite_common_ffi` works the same on Windows desktop, `desktop_drop` supports Windows, and syncfusion PDF viewer supports Windows. No deps need changing.

### WinSparkle integration

`windows/CMakeLists.txt` additions:

```cmake
include(FetchContent)
FetchContent_Declare(
  winsparkle
  URL https://github.com/vslavik/winsparkle/releases/download/v0.8.1/WinSparkle-0.8.1.zip
  URL_HASH SHA256=<pin-this-on-implementation>
)
FetchContent_MakeAvailable(winsparkle)
target_link_libraries(${BINARY_NAME} PRIVATE winsparkle)
```

`winsparkle.dll` ships next to `PaperSuitcase.exe` (NSIS bundles both).

`windows/runner/flutter_window.cpp` — after main window creation, before `Show()`:

```cpp
#include <winsparkle.h>

win_sparkle_set_appcast_url(
    "https://initialneil.github.io/papersuitcase/appcast.xml");
win_sparkle_set_app_details(
    L"PaperSuitcase", L"PaperSuitcase", L"<version-from-rc>");
win_sparkle_init();
```

Version string is read from the version-info resource embedded by NSIS/CMake. WinSparkle auto-checks on a default schedule (24 h). No method channel from Flutter — auto-check is sufficient for v1; a manual "Check for Updates" menu item can be added later.

### NSIS installer

File: `installer/papersuitcase.nsi`. Output filename: `PaperSuitcase-Windows-v${VERSION}-Setup.exe`.

- Install dir: `$PROGRAMFILES64\PaperSuitcase\`
- Bundles: `PaperSuitcase.exe`, `winsparkle.dll`, `flutter_windows.dll`, plugin DLLs, `data/` folder
- Start Menu shortcut: "Paper Suitcase"
- Uninstaller registered under `HKLM\Software\Microsoft\Windows\CurrentVersion\Uninstall\PaperSuitcase`
- No file associations in v1

The NSIS script reads `VERSION` from an env var passed by the workflow, so a single script works across releases.

### CI workflow `release-windows.yml`

```yaml
name: release-windows
on:
  push:
    tags: ['v*']
jobs:
  build:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
          flutter-version: <pinned-to-match-local>
      - run: flutter pub get
      - run: flutter build windows --release
      - run: choco install nsis -y --no-progress
      - shell: pwsh
        env:
          VERSION: ${{ github.ref_name }}  # e.g. "v1.2.0"
        run: |
          $v = $env:VERSION.TrimStart('v')
          makensis /DVERSION=$v installer\papersuitcase.nsi
      - shell: pwsh
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          gh release upload "$env:GITHUB_REF_NAME" `
            "PaperSuitcase-Windows-$env:GITHUB_REF_NAME-Setup.exe"
```

Requires no GitHub secrets (uses default `GITHUB_TOKEN`).

### Shared appcast schema

Each release writes two `<item>` entries. Schema for one release:

```xml
<item>
  <title>Version X.Y.Z (macOS)</title>
  <sparkle:os>macos</sparkle:os>
  <pubDate>...</pubDate>
  <sparkle:version>BUILD</sparkle:version>
  <sparkle:shortVersionString>X.Y.Z</sparkle:shortVersionString>
  <sparkle:minimumSystemVersion>12.0</sparkle:minimumSystemVersion>
  <description><![CDATA[ ... ]]></description>
  <enclosure
    url="https://github.com/initialneil/papersuitcase/releases/download/vX.Y.Z/PaperSuitcase-macOS-vX.Y.Z.zip"
    length="..."
    type="application/octet-stream"
    sparkle:edSignature="..."/>
</item>
<item>
  <title>Version X.Y.Z (Windows)</title>
  <sparkle:os>windows</sparkle:os>
  <pubDate>...</pubDate>
  <sparkle:version>BUILD</sparkle:version>
  <sparkle:shortVersionString>X.Y.Z</sparkle:shortVersionString>
  <description><![CDATA[ ... ]]></description>
  <enclosure
    url="https://github.com/initialneil/papersuitcase/releases/download/vX.Y.Z/PaperSuitcase-Windows-vX.Y.Z-Setup.exe"
    type="application/octet-stream"/>
</item>
```

Windows enclosure has no `length` (skipped — WinSparkle doesn't require it) and no `sparkle:edSignature` (per v1 decision). Patch releases REPLACE the top pair; minor/major PREPEND a new pair.

### `/release` skill flow changes

Insertions to `.claude/skills/release/SKILL.md`:

**Step 7 (release notes)** — installation section now lists both platforms:
```markdown
### Installation
**macOS:** Download `PaperSuitcase-macOS-vX.Y.Z.dmg`, open, drag to Applications, right-click → Open.
**Windows:** Download `PaperSuitcase-Windows-vX.Y.Z-Setup.exe`, run installer, click "More info → Run anyway" if SmartScreen warns.
```

**Step 8 (appcast)** — emit two items per release per the schema above. Windows URL is templated (we know the filename pattern before CI completes).

**New step 10a (after `gh release create`):**
```bash
RUN_ID=$(gh run list --workflow=release-windows.yml --branch="v${VERSION}" --limit=1 --json databaseId -q '.[0].databaseId')
gh run watch "$RUN_ID" --exit-status
```
This blocks until CI finishes; non-zero exit on failure.

**New step 10b:** verify both assets present.
```bash
gh release view "v${VERSION}" --json assets -q '.assets[].name'
```
Skill confirms presence of `*.dmg` AND `*-Setup.exe` before reporting done.

Existing step 11 (cleanup) unchanged.

## Per-release data flow

1. User runs `/release patch` (or `minor`/`major`) on Mac, cwd = repo root.
2. Skill bumps version in `pubspec.yaml`.
3. Skill builds Mac: `flutter clean && flutter pub get && flutter build macos --release`.
4. Skill packages DMG + ZIP, signs ZIP with Sparkle (local, unchanged).
5. Skill generates release notes from `git log`.
6. Skill updates `docs/appcast.xml` — writes both Mac and Windows `<item>` entries (Mac signature/length filled in; Windows URL templated).
7. Skill commits `pubspec.yaml` + `docs/appcast.xml` + any other release changes.
8. Skill creates git tag `vX.Y.Z`, pushes tag + HEAD. **The tag push triggers the Windows workflow on GitHub Actions.**
9. Skill creates GitHub release with Mac assets via `gh release create`.
10. **NEW:** Skill calls `gh run watch` on the Windows workflow — blocks ~5–10 min.
11. **NEW:** CI uploads `PaperSuitcase-Windows-vX.Y.Z-Setup.exe` to the same release via `gh release upload`.
12. **NEW:** Skill verifies both assets present via `gh release view`.
13. Skill cleans up local artifacts.
14. Skill reports release URL + Pages-deploy reminder.

The appcast is correct from the moment Pages deploys (~1–2 min after step 7's push), regardless of when Windows CI finishes — because the Windows URL is templated from the known filename pattern. No second commit needed.

**Note on ordering:** The Windows workflow's `gh release upload` is the LAST step in CI and runs after `flutter build windows` (which alone takes several minutes). The local skill's `gh release create` completes in seconds. By the time CI reaches the upload step, the release definitely exists — no race condition.

## Failure modes

| Failure | Behavior | Recovery |
|---|---|---|
| Windows CI build fails | `gh run watch` exits non-zero; skill reports failure with link to logs. Mac release is already published. | Fix the issue, re-trigger via `gh workflow run release-windows.yml -r vX.Y.Z`. Or delete the release entirely and re-run `/release`. |
| CI runner unavailable / queueing | `gh run watch` blocks; user can Ctrl-C. | Wait it out, or re-trigger manually later. Mac release is already public. |
| NSIS install via Chocolatey fails | Workflow fails at `choco install nsis` step. | Re-run workflow; if persistent, pin a specific NSIS version or vendor `makensis.exe` in the repo. |
| `winsparkle.dll` missing from installer | App crashes on launch with DLL-not-found. | NSIS script must explicitly include `winsparkle.dll`; first CI run catches this in manual smoke test. |
| `win_sparkle_init()` crashes | Bricks Windows app on launch. | Init code wrapped in try/catch with stderr logging. WinSparkle init is historically very stable. |
| Tag pushed twice (re-running `/release` after a CI failure) | Workflow re-triggers if tag re-created. | For patch releases the skill already deletes-and-recreates the tag — workflow will re-fire automatically. |

## Testing plan

- **First Windows build:** CI's first run after merging this work is the smoke test. Manually download the installer on a Windows machine, install, launch, verify the app runs and a PDF can be opened.
- **WinSparkle update flow:** After the first Windows release (call it v1.2.0), bump to v1.2.1 and confirm a v1.2.0 install detects and installs v1.2.1 via WinSparkle.
- **Appcast schema:** After release commit, `curl https://initialneil.github.io/papersuitcase/appcast.xml` and verify both `<sparkle:os>` items present and parse correctly.
- **Mac flow regression:** Existing Mac release behavior is untouched — Sparkle on Mac should ignore the new Windows items via `sparkle:os` filter.

## Open follow-ups (not in this scope)

- Windows code signing (e.g. Certum OV cert at ~$80/yr)
- WinSparkle EdDSA update signing
- Manual "Check for Updates" menu item via Flutter method channel
- Linux build (flatpak/snap)
- File association: `.pdf` → Paper Suitcase

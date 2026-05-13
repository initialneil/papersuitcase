---
name: release
description: Build, package, and release PaperSuitcase to GitHub Releases for macOS and Windows. Bumps version, creates DMG+ZIP (Mac, local) and NSIS installer (Windows, via GitHub Actions), signs Mac ZIP with Sparkle, uploads assets, updates shared appcast for Sparkle+WinSparkle. Supports patch (replace), minor, and major releases.
user_invocable: true
---

# Release Skill

Build and publish PaperSuitcase to GitHub Releases AND update the Sparkle appcast (which lives in `docs/` of the same repo) so existing installs auto-update.

**All commands below assume the current working directory is the repo root.** This skill uses only repo-relative paths so it stays portable across machines. If your cwd is elsewhere, start with `cd` into the repo.

## Repo layout

Single monorepo `initialneil/papersuitcase`. Flutter source at the root, website and appcast at `docs/`. Pages deploys via `.github/workflows/pages.yml` on pushes touching `docs/`. Appcast is served at `https://initialneil.github.io/papersuitcase/appcast.xml`.

## Tools

- `sign_update` for Sparkle EdDSA signing (Mac) — vendored in `macos/Pods/Sparkle/bin/sign_update`
- `create-dmg` (homebrew) — Mac DMG packaging
- `gh` CLI — release management and workflow watching
- GitHub Actions runs the Windows build via `.github/workflows/release-windows.yml` (triggered by the tag push in step 10). The skill waits for it via `gh run watch`. No Windows machine is required locally.

## Arguments

- `patch` or no argument — Patch bump (e.g. 1.1.0 → 1.1.1). **Replaces** the existing release with the same minor version on GitHub (deletes old patch release first, then creates new one with same minor tag).
- `minor` — Minor bump (e.g. 1.1.0 → 1.2.0). Creates a **new** release.
- `major` — Major bump (e.g. 1.1.0 → 2.0.0). Creates a **new** release.

## Steps

Follow these steps in order. Stop and report to the user if any step fails.

### 1. Read current version

Read `pubspec.yaml` and extract the current `version:` field (format: `MAJOR.MINOR.PATCH+BUILD`).

### 2. Compute new version

Based on the bump type argument:
- **patch**: increment PATCH, keep MAJOR.MINOR, increment BUILD
- **minor**: increment MINOR, reset PATCH to 0, increment BUILD
- **major**: increment MAJOR, reset MINOR and PATCH to 0, increment BUILD

Example: `1.1.2+5` with `minor` → `1.2.0+6`

### 3. Update pubspec.yaml

Edit the `version:` line in `pubspec.yaml` to the new version string.

### 4. Build

```bash
flutter clean && flutter pub get && flutter build macos --release
```

If the build fails, stop and report the error.

### 5. Package

The built app is at `build/macos/Build/Products/Release/PaperSuitcase.app`. Create a DMG and a ZIP with filenames using `vMAJOR.MINOR.PATCH`.

**ZIP** (build it inside the Release dir, then move to repo root):
```bash
( cd build/macos/Build/Products/Release && zip -r -y -q "PaperSuitcase-macOS-v${VERSION}.zip" PaperSuitcase.app )
mv "build/macos/Build/Products/Release/PaperSuitcase-macOS-v${VERSION}.zip" .
```

**DMG** — must run with cwd at repo root (`create-dmg` resolves the background path relative to cwd):
```bash
create-dmg \
  --volname "PaperSuitcase" \
  --background "installer/dmg-background.png" \
  --window-pos 200 120 \
  --window-size 660 400 \
  --icon-size 160 \
  --icon "PaperSuitcase.app" 180 170 \
  --app-drop-link 480 170 \
  --no-internet-enable \
  "PaperSuitcase-macOS-v${VERSION}.dmg" \
  "build/macos/Build/Products/Release/PaperSuitcase.app"
```

If create-dmg fails partway, clean up leftovers before retrying:
```bash
hdiutil detach /Volumes/dmg.* 2>/dev/null; rm -f rw.*.dmg build/macos/Build/Products/Release/rw.*.dmg
```

### 6. Sign the ZIP for Sparkle

```bash
./macos/Pods/Sparkle/bin/sign_update "PaperSuitcase-macOS-v${VERSION}.zip"
```

It prints `sparkle:edSignature="..." length=...`. Capture both values — needed in step 8.

### 7. Generate release notes

```bash
git log "$(git describe --tags --abbrev=0)..HEAD" --oneline
```

Summarize into release notes with sections like "New Features", "Fixes", "Changes" as appropriate. Always end with:

```markdown
### Installation

**macOS:**
1. Download `PaperSuitcase-macOS-vX.Y.Z.dmg`
2. Open the DMG and drag Paper Suitcase to Applications
3. On first launch, right-click the app → **Open** (required for unsigned apps)

**Windows:**
1. Download `PaperSuitcase-Windows-vX.Y.Z-Setup.exe`
2. Run the installer (click "More info → Run anyway" if SmartScreen warns — installer is unsigned)
3. Launch Paper Suitcase from the Start Menu

### Requirements
- macOS 12+ or Windows 10+
```

### 8. Update the appcast in docs/

Edit `docs/appcast.xml`. Each release writes TWO `<item>` entries — one for macOS, one for Windows. The Windows item's URL is templated from the known filename pattern; CI uploads the actual installer later in step 10.

- **Patch releases**: REPLACE the existing top pair of `<item>` entries (both Mac + Windows of the most recent patch in the same minor series). Do not accumulate multiple patches of the same minor.
- **Minor/major releases**: PREPEND a new pair at the top of the channel, keeping older items below.

**macOS item template** (signature/length come from step 6):

```xml
    <item>
      <title>Version VERSION (macOS)</title>
      <sparkle:os>macos</sparkle:os>
      <pubDate>PUB_DATE</pubDate>
      <sparkle:version>BUILD_NUMBER</sparkle:version>
      <sparkle:shortVersionString>VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>12.0</sparkle:minimumSystemVersion>
      <description><![CDATA[
        <h2>vVERSION</h2>
        NOTES_HTML
      ]]></description>
      <enclosure
        url="https://github.com/initialneil/papersuitcase/releases/download/vVERSION/PaperSuitcase-macOS-vVERSION.zip"
        length="LENGTH"
        type="application/octet-stream"
        sparkle:edSignature="SIGNATURE"
      />
    </item>
```

**Windows item template** (no length, no signature for v1 — WinSparkle treats as unsigned):

```xml
    <item>
      <title>Version VERSION (Windows)</title>
      <sparkle:os>windows</sparkle:os>
      <pubDate>PUB_DATE</pubDate>
      <sparkle:version>BUILD_NUMBER</sparkle:version>
      <sparkle:shortVersionString>VERSION</sparkle:shortVersionString>
      <description><![CDATA[
        <h2>vVERSION</h2>
        NOTES_HTML
      ]]></description>
      <enclosure
        url="https://github.com/initialneil/papersuitcase/releases/download/vVERSION/PaperSuitcase-Windows-vVERSION-Setup.exe"
        type="application/octet-stream"
      />
    </item>
```

- `BUILD_NUMBER` is the build number from `pubspec.yaml` (the part after `+`).
- `PUB_DATE` is RFC 822 format (e.g. `Thu, 09 Apr 2026 13:46:00 +0800`) — same value for both items.
- `NOTES_HTML` is a short HTML version of the release notes — same value for both items.
- `LENGTH` and `SIGNATURE` (Mac only) come from step 6.
- The Windows URL is templated from the known filename pattern; no signature is included for v1.

After editing, validate the XML:

```bash
xmllint --noout docs/appcast.xml
```

### 9. Commit

Stage `pubspec.yaml`, `docs/appcast.xml`, and any other changes that are part of this release. Commit with a meaningful message describing what's in the release. The Pages workflow auto-deploys the new appcast when `docs/` is pushed.

### 10. Tag and release (and wait for Windows CI)

**Patch releases** (replace existing minor release):
1. Find the existing tag matching `vMAJOR.MINOR.*` using `gh release list`
2. Delete that release AND its git tag:
   ```bash
   gh release delete vOLD_TAG --yes --cleanup-tag
   ```
3. Create the new tag and push:
   ```bash
   git tag "v${VERSION}"
   git push origin "v${VERSION}"
   git push origin HEAD
   ```

**Minor/major releases**:
```bash
git tag "v${VERSION}"
git push origin "v${VERSION}"
git push origin HEAD
```

**The tag push above triggers `.github/workflows/release-windows.yml`** on GitHub Actions. The workflow builds the Windows installer and uploads it to the release we're about to create.

Create the release with Mac assets:
```bash
gh release create "v${VERSION}" \
  --title "Paper Suitcase v${VERSION}" \
  --notes "RELEASE_NOTES" \
  "PaperSuitcase-macOS-v${VERSION}.dmg" \
  "PaperSuitcase-macOS-v${VERSION}.zip"
```

Wait for the Windows workflow to finish and upload its installer:
```bash
sleep 5  # give GitHub a moment to register the workflow run
RUN_ID=$(gh run list --workflow=release-windows.yml --branch="v${VERSION}" --limit=1 --json databaseId -q '.[0].databaseId')
gh run watch "$RUN_ID" --exit-status
```

If `gh run watch` exits non-zero, the Windows build failed. The Mac release is already published with Mac-only assets. Inspect logs (`gh run view "$RUN_ID" --log-failed`), fix the issue on a branch, and re-trigger the workflow against the same tag:
```bash
gh workflow run release-windows.yml -r "v${VERSION}"
```

Verify both assets are now attached to the release:
```bash
gh release view "v${VERSION}" --json assets -q '.assets[].name'
```
Expected output should include:
- `PaperSuitcase-macOS-v${VERSION}.dmg`
- `PaperSuitcase-macOS-v${VERSION}.zip`
- `PaperSuitcase-Windows-v${VERSION}-Setup.exe`

### 11. Clean up and report

```bash
rm "PaperSuitcase-macOS-v${VERSION}.dmg" "PaperSuitcase-macOS-v${VERSION}.zip"
```

Report to the user:
- Release URL: `https://github.com/initialneil/papersuitcase/releases/tag/v${VERSION}`
- Mac users: Sparkle picks up the new appcast within ~1–2 min of the Pages workflow finishing.
- Windows users: WinSparkle checks for updates on the next app launch (or per its 24h check schedule).

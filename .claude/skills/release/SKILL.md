---
name: release
description: Build, package, and release PaperSuitcase to GitHub Releases. Bumps version, creates DMG+ZIP, signs with Sparkle, uploads assets, updates appcast. Supports patch (replace), minor, and major releases.
user_invocable: true
---

# Release Skill

Build and publish PaperSuitcase to GitHub Releases AND update the Sparkle appcast (which lives in `docs/` of the same repo) so existing installs auto-update.

## Repo

Single monorepo: `/Users/neil/Playground/paper_suitecase_project/PaperFlutter` (remote: `initialneil/papersuitcase`). Contains Flutter source at the root and the GitHub Pages website at `docs/`. Pages is deployed by `.github/workflows/pages.yml` on pushes that touch `docs/`. The appcast is served at `https://initialneil.github.io/papersuitcase/appcast.xml`.

## Tools

- `sign_update` for Sparkle EdDSA signing: `/Users/neil/Playground/paper_suitecase_project/PaperFlutter/macos/Pods/Sparkle/bin/sign_update`
- `create-dmg` (homebrew)
- `gh` CLI

## Arguments

The user provides a bump type as the argument:

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

Run from the PaperFlutter directory:

```bash
flutter clean && flutter pub get && flutter build macos --release
```

If the build fails, stop and report the error.

### 5. Package

The built app is at: `build/macos/Build/Products/Release/PaperSuitcase.app`

Create both a DMG and a ZIP. Use version format `vMAJOR.MINOR.PATCH` for filenames.

**ZIP** (build it inside the Release dir, then move to PaperFlutter root):
```bash
cd build/macos/Build/Products/Release && zip -r -y -q "PaperSuitcase-macOS-v${VERSION}.zip" PaperSuitcase.app
mv build/macos/Build/Products/Release/PaperSuitcase-macOS-v${VERSION}.zip ./
```

**DMG** (run from PaperFlutter directory — `create-dmg` resolves the background path relative to cwd, so this MUST be run with cwd=PaperFlutter):
```bash
cd /Users/neil/Playground/paper_suitecase_project/PaperFlutter && create-dmg \
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

If create-dmg fails partway, clean up `rw.*.dmg` leftovers and stale `/Volumes/dmg.*` mounts before retrying:
```bash
hdiutil detach /Volumes/dmg.* 2>/dev/null; rm -f rw.*.dmg build/macos/Build/Products/Release/rw.*.dmg
```

### 6. Sign the ZIP for Sparkle

Run sign_update on the ZIP. It outputs `sparkle:edSignature="..." length=...`:

```bash
/Users/neil/Playground/paper_suitecase_project/PaperFlutter/macos/Pods/Sparkle/bin/sign_update PaperSuitcase-macOS-v${VERSION}.zip
```

Capture both the signature and the length value — you'll need them in step 9.

### 7. Generate release notes

Run `git log <last-tag>..HEAD --oneline` from the PaperFlutter directory. Summarize the changes into release notes with sections like "New Features", "Fixes", "Changes" as appropriate. Always end with:

```markdown
### Installation
1. Download `PaperSuitcase-macOS-vX.Y.Z.dmg`
2. Open the DMG and drag Paper Suitcase to Applications
3. On first launch, right-click the app → **Open** (required for unsigned apps)

### Requirements
- macOS 12+
```

### 8. Update the appcast in docs/

Edit `docs/appcast.xml`.

**For patch releases**: REPLACE the existing top `<item>` (the most recent patch in the same minor series) with the new entry. Do not keep multiple patches of the same minor.

**For minor/major releases**: PREPEND a new `<item>` at the top of the channel, keeping older items below.

The new `<item>` template (substitute VERSION, BUILD_NUMBER, PUB_DATE, NOTES_HTML, LENGTH, SIGNATURE):

```xml
    <item>
      <title>Version VERSION</title>
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

- `BUILD_NUMBER` is the build number from `pubspec.yaml` (the part after `+`).
- `PUB_DATE` is RFC 822 format (e.g. `Thu, 09 Apr 2026 13:46:00 +0800`).
- `NOTES_HTML` is a short HTML version of the release notes (a `<ul>` of bullet points works well — match the tone of existing entries in the file).
- `LENGTH` and `SIGNATURE` come from step 6.

### 9. Commit version bump, appcast, and any other changes

Stage `pubspec.yaml`, `docs/appcast.xml`, and any other changes that are part of this release. Commit with a meaningful message describing what's in the release. The Pages workflow will auto-deploy the new appcast when `docs/` is pushed.

### 10. Tag and release

**For patch releases** (replace existing minor release):
1. Find the existing release tag matching `vMAJOR.MINOR.*` using `gh release list --repo initialneil/papersuitcase`
2. If found, delete that release AND its git tag:
   ```bash
   gh release delete vOLD_TAG --repo initialneil/papersuitcase --yes --cleanup-tag
   ```
3. Create the new tag, push tag and HEAD:
   ```bash
   git tag "vMAJOR.MINOR.PATCH"
   git push origin "vMAJOR.MINOR.PATCH"
   git push origin HEAD
   ```

**For minor/major releases**:
```bash
git tag "vMAJOR.MINOR.PATCH"
git push origin "vMAJOR.MINOR.PATCH"
git push origin HEAD
```

Then create the release with assets:
```bash
gh release create "vMAJOR.MINOR.PATCH" \
  --repo initialneil/papersuitcase \
  --title "Paper Suitcase vMAJOR.MINOR.PATCH" \
  --notes "RELEASE_NOTES" \
  "PaperSuitcase-macOS-vMAJOR.MINOR.PATCH.dmg" \
  "PaperSuitcase-macOS-vMAJOR.MINOR.PATCH.zip"
```

### 11. Clean up and report

Remove the local DMG and ZIP files:
```bash
rm PaperSuitcase-macOS-v${VERSION}.dmg PaperSuitcase-macOS-v${VERSION}.zip
```

Report to the user:
- Release URL: `https://github.com/initialneil/papersuitcase/releases/tag/vVERSION`
- Note that the Pages workflow will auto-deploy the updated appcast in a minute or two, so existing installs will see the update via Sparkle

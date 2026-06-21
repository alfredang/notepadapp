---
name: ios-app-update
description: Ship a NEW version of NotePad (Tertiary NotePad) to App Store Connect from the command line — the local, controllable update pipeline (e.g. 1.4 → 1.5). Bump the version, archive + sign + upload the build, create the new App Store version, set "What's New" from CHANGELOG, attach the build, and submit for review. Use when submitting the next NotePad release by hand instead of via the ios-release.yml CI.
license: MIT
metadata:
  version: "1.0.0"
---

# Update NotePad to a new App Store version (local pipeline)

Submit the next version of **Tertiary NotePad** (already live on the App Store) by hand from
the command line, so every step is observable. This is the "1.4 → 1.5" path used when you've
finished features, tested on device, and want to ship now.

Complements: **app-store-submission** (first submission + API gotchas) and **ios-auto-release**
(the GitHub Actions equivalent in `.github/workflows/ios-release.yml`).

## NotePad concrete values

```
App name (ASC):  Tertiary NotePad
App ID (ASC):    6779909944
Bundle ID:       com.tertiaryinfotech.notepadapp
Team ID:         GU9WTSTX9M
Signing:         Apple Distribution: Alfred Ang (GU9WTSTX9M)  [manual]
Profile:         NotePad App Store 1.1
iCloud:          iCloud.com.tertiaryinfotech.notepadapp  (CloudKit Production for release)
Device family:   1,2 (universal — iPad editor; iPhone/Mac view-only)
ASC key:         .env (ASC_KEY_ID / ASC_ISSUER_ID / ASC_PRIVATE_KEY_PATH); .p8 in
                 ~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8
Helper:          scripts/ci_submit.py   ExportOptions:  ExportOptions.plist
```

## ⚠️ Version bump = TWO files (Info.plist holds literals, not $(VAR))

`project.yml` has `GENERATE_INFOPLIST_FILE: NO` and `App/Info.plist` stores **literal**
version strings, so `xcodebuild`'s `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` settings
do **not** flow into the binary. Bump both:

1. `project.yml` → `MARKETING_VERSION: "1.5"` (read by `ci_submit.py next-version`).
2. `App/Info.plist` → `CFBundleShortVersionString = 1.5` and `CFBundleVersion = 16`
   (integer build number, must exceed the last uploaded build — 1.4 shipped as build 15).
3. `CHANGELOG.md` → add a `## [1.5]` section with `- ` bullets (becomes "What's New").

## Pipeline (verified for the 1.5 submission)

```bash
cd /Users/alfredang/projects/mobile/iOS/notepadapp
set -a; source .env; set +a

# (bump project.yml + App/Info.plist + CHANGELOG.md first, per above)

xcodegen generate

xcodebuild -project NotePadApp.xcodeproj -scheme NotePadApp -configuration Release \
  -archivePath /tmp/NotePad.xcarchive \
  CODE_SIGN_STYLE=Manual \
  "CODE_SIGN_IDENTITY=Apple Distribution: Alfred Ang" \
  "PROVISIONING_PROFILE_SPECIFIER=NotePad App Store 1.1" \
  DEVELOPMENT_TEAM=GU9WTSTX9M \
  clean archive

# sanity check the embedded values
APPPL=/tmp/NotePad.xcarchive/Products/Applications/NotePadApp.app/Info.plist
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APPPL"   # 1.5
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APPPL"              # 16

xcodebuild -exportArchive -archivePath /tmp/NotePad.xcarchive \
  -exportPath /tmp/notepad-export -exportOptionsPlist ExportOptions.plist

xcrun altool --validate-app -f /tmp/notepad-export/NotePadApp.ipa -t ios \
  --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
xcrun altool --upload-app   -f /tmp/notepad-export/NotePadApp.ipa -t ios \
  --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"

python3 scripts/ci_submit.py wait-build --build 16          # → build 16: VALID
python3 scripts/ci_submit.py submit --version 1.5 --build 16
```

### Screenshots auto-inherit — don't let ci_submit upload the README

`ci_submit.py submit` defaults `--screenshots-dir ci/screenshots/APP_IPHONE_67`, which here
contains only a `README.md`. **It only uploads when it creates a brand-new version.** Verified
behavior: creating version 1.5 via the API **auto-carried 1.4's screenshots** (iPad
`APP_IPAD_PRO_3GEN_129` ×2 + iPhone `APP_IPHONE_65` ×2), so no upload is needed. To be safe,
run create/submit via a small script that calls `ensure_version(tok, aid, "1.5", None)` (None
= skip the dir upload) then `attach_build` + `submit_for_review`, OR confirm the sets are
populated before submitting. NotePad uses iPad 12.9" + iPhone 6.5" sets (no 6.7").

### Verify

```bash
python3 - <<'PY'
import importlib.util
s=importlib.util.spec_from_file_location("cs","scripts/ci_submit.py")
cs=importlib.util.module_from_spec(s); s.loader.exec_module(cs)
tok=cs.token(); aid=cs.app_id(tok)
for v in cs.versions(tok, aid):
    a=v["attributes"]
    if a["versionString"]=="1.5":
        print(a["appStoreState"], a.get("releaseType"))   # WAITING_FOR_REVIEW AFTER_APPROVAL
PY
```

## NotePad-specific gotchas

- **`[skip ci]` in the commit that bumps the version.** `.github/workflows/ios-release.yml`
  auto-builds + submits on push to `main` (it ignores `**.md`, `.github/**`, `scripts/**`,
  `ci/screenshots/**`, but **not** `project.yml` / `App/Info.plist` / Swift). After a manual
  submit, append `[skip ci]` so CI doesn't build a second, duplicate build.
- **`CFBundleIconName` "missing" at top level is fine.** The source `Info.plist` has no
  top-level `CFBundleIconName`; the asset-catalog compiler injects the nested
  `CFBundleIcons → CFBundlePrimaryIcon → CFBundleIconName = AppIcon` at build time. This is
  the exact config that shipped 1.0–1.4, so ASC processing accepts it. Don't "fix" it.
- **CloudKit Production schema deploy** only if the release **changed `@Model` types/props**
  (`Notebook` / `Page` / `AudioNote` / `AppSettings`). UI/logic-only updates (toolbar,
  import flows, PencilKit warm-up, etc.) need no deploy. Release uses
  `App/NotePadApp.Release.entitlements` → Production CloudKit.
- **Build number history:** 1.4 = build 15, 1.5 = build 16. Keep incrementing the integer.
- **App Privacy / age rating / availability** persist across versions — no per-update action
  unless data collection changes.

## When CI is the better choice

If you just want "push to main → it ships", use the existing `ios-release.yml` (the
**ios-auto-release** skill). This local skill is for hands-on submissions and for debugging
when CI misbehaves.

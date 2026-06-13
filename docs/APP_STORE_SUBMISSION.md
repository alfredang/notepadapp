# App Store Submission — NotePad

Status: **ready for first submission** (v1.0, build 1). This doc is the checklist
and the metadata to paste into App Store Connect.

## 1. App identity

| Field | Value |
|---|---|
| App name | NotePad |
| Bundle ID | `com.tertiaryinfotech.notepadapp` |
| iCloud container | `iCloud.com.tertiaryinfotech.notepadapp` |
| Team | Alfred Ang — `GU9WTSTX9M` (App Store Connect: Chew Hoe Ang) |
| Platform | iPadOS 18+ (iPad only — `TARGETED_DEVICE_FAMILY = 2`) |
| Version / Build | 1.0 / 1 |
| Category | Productivity (secondary: Education) |
| Price | Free (set in App Store Connect) |

## 2. Pre-submission checklist (code) — done

- [x] App icon 1024×1024 (no alpha) in `Assets.xcassets/AppIcon`.
- [x] `CFBundleShortVersionString` 1.0, `CFBundleVersion` 1.
- [x] `ITSAppUsesNonExemptEncryption = false` (no export-compliance prompt).
- [x] `NSMicrophoneUsageDescription` (audio notes).
- [x] `UIRequiredDeviceCapabilities = arm64` (was the invalid `armv7`).
- [x] **Privacy manifest** `Resources/PrivacyInfo.xcprivacy` — no tracking, no data
      collected; required-reason APIs declared (UserDefaults, file timestamp, disk space).
- [x] **Per-config entitlements**: Debug → `aps-environment = development`,
      Release → `production` (CloudKit Production for App Store builds).
- [x] iPad-only orientations + multiple scenes + pointer/indirect input.

## 3. Steps to do in the consoles (manual)

1. **CloudKit — deploy schema to Production.** In the CloudKit Console for
   `iCloud.com.tertiaryinfotech.notepadapp`, **Deploy Schema Changes** from
   Development → Production. App Store builds use the Production environment; sync
   will fail for shipped users if the schema isn't deployed.
2. **App Store Connect — create the app record** (bundle ID above), set category,
   price, and availability.
3. **Privacy "Nutrition Label"** (App Privacy section): select **Data Not Collected**
   (data lives in the user's private iCloud; we don't collect or track).
4. **Encryption**: answer "No" (matches `ITSAppUsesNonExemptEncryption = false`).
5. Provide a **support URL** and **privacy policy URL** (required).

## 4. Build & upload

```bash
xcodegen generate
# Archive a Release build in Xcode (Product ▸ Archive) with automatic signing,
# then Distribute App ▸ App Store Connect ▸ Upload.
```
Verify in the Organizer that the archive's entitlements show
`aps-environment = production`.

## 5. Screenshots (required)

App Store requires iPad screenshots at **13" (2064 × 2752)** and optionally
**11"**. Capture on device (Top + Volume Up) and upload 3–5:
1. Editor with handwriting + a flowchart (white paper).
2. Blackboard template with notes.
3. Notebook dashboard with tagged notebooks.
4. PDF annotation.
5. Sidebar page thumbnails / multi-select.

(Drop the same images into `docs/screenshots/editor.png` and `dashboard.png` to
refresh the README.)

## 6. Metadata (paste into App Store Connect)

**Subtitle (30 chars):** Apple Pencil notes & flowcharts

**Promotional text:** A fast, native iPad notebook for Apple Pencil — handwriting,
shapes, flowcharts, PDF markup, and blackboard mode, synced with iCloud.

**Description:**
```
NotePad is a clean, native iPad note-taking app built for Apple Pencil. It feels
like a paper notebook with the power of digital ink.

• Handwriting with pressure & tilt, low latency, and palm rejection — the Pencil
  draws while a finger scrolls and two fingers zoom.
• GoodNotes-style tool bar: pen, highlighter, erasers, color dropdown and widths.
• White paper or blackboard templates, applied across the whole notebook.
• Shapes and flowcharts (process, decision, start/end, connectors) with editable
  vector overlays; connectors re-route when you move a node.
• Type directly into sticky notes and flowchart nodes (multi-line, with background
  colors).
• Lasso to move, delete or copy multiple strokes; recolor and edit shapes.
• Import PDFs and annotate them; export pages or whole notebooks to PDF/PNG/JPG.
• Organize with nested notebooks and tags, and search inside your handwriting.
• Record voice memos per notebook.
• Everything syncs across your devices with iCloud.

Powered by Tertiary Infotech Academy Pte Ltd.
```

**Keywords:** notes,handwriting,apple pencil,notebook,flowchart,pdf,annotate,
blackboard,ipad,drawing,study,diagram

**Support URL:** https://www.tertiaryinfotech.com
**Marketing URL (optional):** https://www.tertiaryinfotech.com

## 7. Known follow-ups (not blockers)

- Live collaboration (current sharing is file-based `.notebook`).
- Lined / grid paper templates.
- Handwriting-to-text conversion.

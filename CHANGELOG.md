# Changelog

All notable changes to NotePad are documented here. The release pipeline
(`.github/workflows/ios-release.yml`) reads the section matching the version
being submitted — falling back to `[Unreleased]` — and sets it as the App
Store "What's New" text. Use `## [x.y]` headers and `- ` bullet lines.

## [Unreleased]

## [1.6]

- Lock the page: pin the zoom and screen orientation so a resting palm can't accidentally resize or rotate your page while you write.
- Shape and line snapping now waits for a deliberate hold at the end of your stroke, so it won't trigger by accident.
- Fixed undo for snapped shapes and straightened lines.
- Even smoother first stroke when you open a brand-new notebook.

## [1.5]

- Import and migrate notes from GoodNotes, Notability, Apple Notes, or any PDF — each becomes a new notebook you can annotate.
- Insert an image straight from the clipboard onto a page and annotate on top of it.
- Share a notebook as an iCloud link — anyone who opens it gets their own copy, your original stays private.
- Cleaner, distraction-free editor with its own notebook header.
- Receive notebooks and PDFs shared via AirDrop or "Open in NotePad", and export via AirDrop too.
- New Notebook and Import are now always one tap away in the toolbar; sort, filter, and sync moved into a tidy More menu.
- Smoother first stroke when you open a brand-new notebook.
- Faster, automatic iCloud restore on a fresh install or reinstall.

## [1.3]

- Restore your notebooks automatically from iCloud after reinstalling.
- Sync your settings and default notebook template across devices via iCloud.
- New pages now inherit the notebook's paper template.
- Added a synced date/time stamp setting.

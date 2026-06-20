# Changelog

All notable changes to NotePad are documented here. The release pipeline
(`.github/workflows/ios-release.yml`) reads the section matching the version
being submitted — falling back to `[Unreleased]` — and sets it as the App
Store "What's New" text. Use `## [x.y]` headers and `- ` bullet lines.

## [Unreleased]

- Faster, automatic iCloud restore on a fresh install or reinstall.

## [1.3]

- Restore your notebooks automatically from iCloud after reinstalling.
- Sync your settings and default notebook template across devices via iCloud.
- New pages now inherit the notebook's paper template.
- Added a synced date/time stamp setting.

# Settings consolidation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cut the Settings tree from 17 root rows / ~25 pages to 13 root rows, with no duplicated controls and no info-only pages, modelled on the iOS 26 Health profile sheet.

**Architecture:** Pages become compositions of small `Section`-returning views, so one control lives in exactly one place. Removed pages either fold into a neighbour as a section (Sync, Power saving, Storage, Siri, Shortcuts Export, Test Centre) or are deleted (Apple Watch data, Limitations, Using NOOP on iPhone, the Apple Health data viewer). `SettingsPage` loses the dead cases.

**Tech Stack:** SwiftUI `Form` + `.settingsPage()` / `.settingsPicker()` (Strand/Settings/SettingsView.swift), XcodeGen, iOS 26 simulator demo harness.

## Global Constraints

- iOS is the target that matters; macOS (`Strand` scheme, `RootView` sidebar) must still compile.
- No explanatory prose: rows + values; only dynamic status/errors and one-line write warnings.
- Every `@AppStorage` key and model call keeps its exact current key/wiring — this is a move, not a behaviour change.
- New user-visible strings get Russian entries in `Strand/Resources/Localizable.xcstrings`, patched textually (never re-dump the JSON).
- `project.yml` globs sources; after adding/removing files regenerate `StrandNoWatch.xcodeproj` (copy of project.yml without the NOOPWatch dependency).
- Never commit the staged `android/` deletions: commit with `git commit -- <paths>`.

## Target root

```
[avatar + name]
Health Details
Strap:        <active device name>   Connected · 82% ›   (→ Devices)
App:          General · Display · Notifications · Shortcuts
Features:     Workouts · Scores · AI Coach [toggle] · Hydration [toggle]
Data:         Apple Health · Import · Backup
About NOOP · Developer
```

---

### Task 1: Strap sections into Devices

**Files:**
- Create: `Strand/Settings/StrapSettingsSections.swift`
- Modify: `Strand/Screens/DevicesView.swift` (deviceForm, remove strapSwitcher + ECG menu entry)
- Delete: `Strand/Screens/PowerSavingView.swift`

**Produces:** `StrapSyncSection`, `PowerSavingSection`, `StrapGesturesSection` (double-tap picker/test/bond row + recent moments), `StrapHapticsSection` (4 haptic toggles + HR-zone coaching), `HeartRateBroadcastSection` (phone broadcaster owning its `HrBroadcaster`, + strap broadcast toggle for 5/MG), `StrapConnectionSection` (Re-scan, Disconnect), `AppleWatchSetupRow`.

- [ ] Move the bodies verbatim from SyncSettingsPage, PowerSavingView, AutomationsView (double-tap, moments, haptics, zone coaching), DataSourcesView (broadcast), DeveloperSettingsPage (Re-scan/Disconnect).
- [ ] DevicesView form order: repair guide → sync status → device cards (always `showsMakeActive`) → Add device + Set up Apple Watch → Sync → Power saving → Double-tap → Haptics → HR broadcast → Connection → compare → removed.
- [ ] Remove `strapSwitcher`, the `onEcgProbe` entry, `ecgEnabled`, `EcgProbeSheets`/`EcgWristSheet`/`EcgProbeResultView`.
- [ ] Build iOS; screenshot `--settings-page devices`.

### Task 2: Notifications page (rest of Automations)

**Files:**
- Create: `Strand/Settings/NotificationsSettingsPage.swift`
- Delete: `Strand/Screens/AutomationsView.swift`

- [ ] Sections: wrist alerts master (iOS) · inactivity reminder · stress check-ins · illness · battery alerts · strain target. Fix the warning to not point at a non-existent screen (drop the sentence; keep the dot + "Wrist alerts are off").
- [ ] `SettingsPage.notifications` routes here on iOS; macOS keeps `NotificationSettingsView` under its sidebar item and maps `.automation` → this page.

### Task 3: Shortcuts page

**Files:**
- Create: `Strand/Settings/ShortcutsSettingsPage.swift`
- Delete: `StrandiOS/App/SiriShortcutsSettingsView.swift`, `StrandiOS/App/ShortcutExportSettingsView.swift`

- [ ] Sections: Siri tips (iOS) · Shortcuts link (iOS) · run a Shortcut when taken off / put back on (+ macOS lock toggle) · Export for Shortcuts toggle (iOS).

### Task 4: Scores gains HRV window, cycle, scoring guide; Workouts unchanged

**Files:** Modify `Strand/Settings/SettingsFeaturePages.swift`

- [ ] Add HRV window picker (from Developer, same re-score call) to an "HRV" section.
- [ ] Add cycle-awareness toggles (from Automations, same gating/side effects) under "Cycle".
- [ ] Add "How your scores work" sheet row. Delete `SyncSettingsPage`.

### Task 5: Import page (Data Sources)

**Files:** Modify `Strand/Screens/DataSourcesView.swift`

- [ ] One card of import rows (WHOOP export, Apple Health export.zip, Mi Fitness, Nutrition CSV, Hevy/Liftosaur, GPX/TCX/FIT, Oura/Fitbit/Garmin), each row: title, spinner while importing, result dot-line below when present. WHOOP stored-days value row on top. Destructive "Remove Apple Health data" last. Remove both broadcast sections (moved in Task 1). Title "Import". Include `wearableImporting` in `localImportBusy`.

### Task 6: Apple Health page = sync only

**Files:** Modify `Strand/Screens/AppleHealthView.swift`

- [ ] Keep `AppleHealthLoadCache` / `AppleHealthLoadKey` (Repository + tests use them) and the iOS live-sync section; delete the range/summary/charts and previews. macOS body: a single row explaining import lives in Import.

### Task 7: Backup gains Storage

**Files:** Modify `Strand/Settings/BackupSyncView.swift`, `Strand/Screens/StorageView.swift` (→ `StorageSections`)

- [ ] Folder section first, then backup-now/auto, restore, export/import, storage footprint + clean up. Fix the stale "Backup & restore" path in the oversize message.

### Task 8: Developer = Test Centre + developer rows

**Files:** Modify `Strand/Screens/TestCentreView.swift` (Form → content, rename title), `Strand/Settings/DeveloperSettingsPage.swift`, `Strand/Screens/LiveView.swift:1300`, `Strand/App/RootView.swift`

- [ ] Remove from Test Centre: "Copy environment dump", Recalibrate Charge section + dialog, strap broadcast toggle, legacy R22 section.
- [ ] Developer page: `Form { TestCentreContent }` plus diagnostics sheet (iOS), raw CSV export, 4.0 strap rename, continuous HRV; all experiment toggles (Live Sessions, Sleep V2, motion-aware wake, SpO₂ estimate, PPG sub-lag, HRV readiness, Rhythm) in one "Experiments" section.

### Task 9: About trimmed

**Files:** Modify `Strand/Settings/AboutSettingsPage.swift`; delete `Strand/Screens/AppleWatchAboutView.swift`, `Strand/Screens/NoopLimitationsView.swift`

- [ ] Remove Name row, Apple Watch data, Limitations, Scoring guide (moved), Using NOOP on iPhone; show sideload expiry as one value row (iOS). Move `DiagnosticsSheet` to Developer.

### Task 10: Root + routing + General

**Files:** Modify `Strand/Settings/SettingsView.swift`, `Strand/Settings/SettingsGeneralPages.swift`, `Strand/Settings/ProfileDetailsView.swift`, `StrandiOS/App/StrandiOSApp.swift` (demo names), `Strand/App/RootView.swift`

- [ ] Root per "Target root"; strap row shows active device name + status + battery.
- [ ] `SettingsPage`: drop sync, powerSaving, storage, shortcutsExport, siri, automations, appleWatch, limitations, iphone, testCentre; add shortcuts; notifications on iOS too.
- [ ] General: remove Storage link. ProfileSheet: "Data Sources" → "Import".
- [ ] macOS sidebar: drop `.powerSaving`, `.noopLimitations`; `.automation` → NotificationsSettingsPage; `.testCentre` → DeveloperSettingsPage.

### Task 11: Localize, build both targets, screenshot, commit

- [ ] Add ru entries for new keys (Import, Shortcuts, Notifications section titles, etc.).
- [ ] `xcodegen` (StrandNoWatch + Strand), build NOOPiOS and Strand (macOS) with `CODE_SIGNING_ALLOWED=NO`.
- [ ] Screenshot every page via `--demo-seed --demo-screen settings --settings-page <p>` (launch with `--terminate-running-process`).
- [ ] `git commit -- <changed paths>`.

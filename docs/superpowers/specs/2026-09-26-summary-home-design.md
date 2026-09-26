# Summary home (Apple Health style, native Liquid Glass) — design

Date: 2026-09-26. Scope: the Today tab root on iOS (`NOOPiOS`) and macOS (`Strand`). Android untouched.

## Goal

Replace the current home (`LiquidTodayView`, custom Canvas "liquid metal" sky + vessels) with a new,
minimal screen modelled on the iOS 26 Apple Health **Summary**, using SwiftUI's **native Liquid Glass**
APIs (`glassEffect`, `.buttonStyle(.glass)`, `GlassEffectContainer`). Visual reference: the approved
mockup `.superpowers/brainstorm/…/content/summary-v5.html` (light + dark).

## Non-goals

- No analytics / scoring / storage change. Every number comes from the same sources the old home reads.
- Old `LiquidTodayView` / `TodayView` are NOT deleted in this change (other screens use their helpers,
  e.g. `TodayView.lastScoredRecoveryDay`, `TodayView.freshRestScore`, `HeroScoreCell`). Deleting them is a
  follow-up once the Summary is settled.
- Other tabs (Trends, Sleep, Coach, More) are not restyled yet.

## Platform / availability

- Deployment targets stay iOS 17 / macOS 13.
- Native glass is applied only when BOTH hold: `#if compiler(>=6.2)` (Xcode 26 toolchain) and
  `if #available(iOS 26.0, macOS 26.0, *)`. Otherwise the fallback is `.ultraThinMaterial` in the same
  shape. The compiler guard keeps an Xcode 16 build (upstream CI `macos-15`) compiling.
- One helper file owns this branching (`SummaryGlass.swift`); no view calls `glassEffect` directly.
- Colour scheme follows the existing `AppearanceMode` (system by default); every colour is a
  `StrandPalette` token so light and dark both work.

## Screen structure (top → bottom)

1. **Background** — `StrandPalette.surfaceBase` with a soft top wash (a vertical gradient built from the
   three score tokens at low opacity, fading to `surfaceBase` by ~40% height). Scrolls with content.
2. **Header** — large title "Summary" (localized). Trailing glass circle buttons:
   - **Add** (`plus`): iOS → `router.requestQuickActions()`; macOS → starts a Live Session directly.
     Hidden on macOS when `LiveSessionPrefs.betaKey` is off.
   - **Strap** (battery glyph from `StrapBatteryDisplay.resolve(...)` over `LiveState`) → `router.openDevices()`.
   - **Avatar** (`ProfileAvatarView`) → Settings sheet (same presentation as the old home).
3. **Rings card** ("Today", or the selected date when not today, with a chevron):
   - Three concentric Apple-Watch-style rings, outer→inner: Charge (recovery %, 0–100), Effort
     (strain, stored 0–100, displayed on the user's `UnitPrefs.effortScaleKey` scale 21 or 100),
     Rest (sleep performance %, 0–100). Ring fill = value / max, clamped to [0, 1]; no overlap laps.
     Gradient per ring `xColor → xBright`, round caps, SF Symbol glyph at the ring start
     (bolt / flame / moon), faint track in the same hue.
   - Right column: label + value in ring colour. Missing value → "—" and an empty ring.
     Charge uses `ChargeDisplay` (scored / carried / calibrating / no data); carried and calibrating show
     their caption under the value.
   - Tap a value row → `TabRoute.metric(.charge/.effort/.rest)` (existing `MetricDetailView`).
   - Tap the header ("Today ›") → graphical `DatePicker` popover (same bounds as today:
     logical day rolls at 04:00, not before `repo.freshness.earliestDay`, not after today).
   - Horizontal swipe anywhere on the screen changes day (existing `daySwipeDelta` / clamp logic),
     with a selection haptic.
4. **Pinned** section — header "Pinned" + trailing "Edit" button.
   - Items = `KeyMetricPrefs.decodeEnabled(@AppStorage today.keyMetrics)` minus charge/effort/rest.
   - Card: coloured icon + title (from `KeyMetric.customizationIcon/Tint`), trailing time-or-day label +
     chevron; body: bold value + unit, secondary caption (e.g. "latest", "from profile", norm range when
     available), 7-day mini chart on the right (line for continuous metrics, bars for steps / calories).
   - Tap → `MetricDetailView` for that metric (same resolution the old tile used).
   - "Edit" → `TodayCustomizationSheet(initialDestination: .keyMetrics, …)`.
   - Empty list → a single card "Pin metrics you care about" that opens the same editor.
5. **Highlights** section — up to 3 cards from `ReadinessEngine.evaluate(...).signals` whose flag is not
   `.neutral`, ordered bad → watch → good. Card: coloured icon + signal label, chevron, one semibold
   sentence (`signal.detail`). Tap → `TabRoute.metric(key)` for hrv / rhr / resp_rate; acwr / monotony
   route to Effort. Section hidden when nothing qualifies (incl. `.insufficient`).
6. **Pull to refresh** — native `.refreshable`: if `ble.state.historyReady` then `ble.syncNow()`; then
   `await repo.refresh()`; then reload.

Removed from home (still reachable elsewhere): greeting + readiness pills, live HR chart, recovery
vitals, workouts, Your Cards, hosted cards, journal, cycle, data sources card, coach launcher,
hydration, sky / photo background. Live Session start moves to the iOS quick-action sheet (new row,
shown only when `LiveSessionPrefs.betaKey` is on) and to the macOS header "+" button.

## Code layout (new folder `Strand/Summary/`, shared by both app targets)

| File | Responsibility |
|---|---|
| `SummaryView.swift` | Screen: scroll, header, sections, day state, sheets, refresh. No formatting logic. |
| `SummaryLoader.swift` | `@MainActor` async loader → `SummarySnapshot` value (scores, pinned readings, highlights) for a given day key. Reuses the Repository calls the old home uses. |
| `SummaryMetricReading.swift` | Pure: `KeyMetric` + raw inputs → `SummaryMetricReading { value, unit, caption, series7d, chartStyle, detailKey }`. Replaces the old home's private inline mapping. |
| `SummaryHighlights.swift` | Pure: `Readiness` → `[SummaryHighlight]` (filter, order, cap 3, route key). |
| `ActivityRingsView.swift` | Pure drawing of the three rings from fractions + tokens. `RingFraction.of(value:max:)` helper. |
| `SummaryCards.swift` | `SummaryRingsCard`, `SummaryMetricCard`, `SummaryHighlightCard`, section header. |
| `SummaryGlass.swift` | `summaryGlassCircle()` modifier + fallback, the only place with glass availability branching. |

Wiring: `StrandiOS/App/RootTabView.swift` `todayTabRoot` and `Strand/App/RootView.swift` Today case
render `SummaryView()`. The `noop.liquidTodayEnabled` switch is no longer consulted for the root (left in
storage untouched). `project.yml` needs no change if `Strand/` sources are globbed — verify, then
`xcodegen generate`.

Design tokens: any new colour (wash stops) is added to `StrandPalette` as a `Color(light:dark:)` token;
no literals in views. Spacing via `NoopMetrics` where a token exists.

## Testing

- `StrandTests` table-driven tests (stdlib XCTest, no new deps):
  - `SummaryMetricReading` for every `KeyMetric` case incl. missing data → "—", effort scale 21 vs 100.
  - `SummaryHighlights`: filtering neutral, ordering, cap 3, `.insufficient` → empty, route keys.
  - `RingFraction`: nil, negative, > max, exact max.
- Build both schemes with Xcode 26 (`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`):
  `NOOPiOS` (iOS Simulator) and `Strand` (macOS); run `StrandTests`.
- Launch in the iOS 26 simulator, screenshot light + dark, compare against the approved mockup.
- `Tools/doc_comment_lint.py` and `Tools/i18n_audit.py` stay green (new strings added to the catalogue).

# Handbook for agents porting Denis's iOS redesign to Android (Material 3)

Repo: `/Users/ant1/Documents/reNOOP` (fork "reNOOP" of NOOP, a WHOOP-strap companion app). Read `AGENTS.md` first
(hard rules: offline, no telemetry, BLE safety, design tokens only, migrations, cross-platform parity).

## What we are doing
Denis rebuilt the iOS app (commits 2026-09-26..30, `git log --author=Денис`) as a 1:1 clone of Apple's iOS 26
apps (Health, Fitness, Settings, Messages, Clock). The user wants ALL of it on Android, in **Material 3 / Google's
own apps style** (Fitbit, Pixel Settings, Google Messages, Google Clock) — same structure, same features, same
removals, same copy; Android-native look. The user approved mockups (Material You colour from the wallpaper;
Summary has a layout choice A = Denis structure / B = compact Fitbit grid; reNOOP ring palette).

Sources of truth, in order:
1. `SCRATCH/ios-anatomy.md` — top-to-bottom anatomy of every redesigned iOS screen with exact strings.
2. The iOS code itself under `Strand/` and `StrandiOS/` (read it when the anatomy is not enough).
3. Mockups `SCRATCH/mockups/*.dc.html` (HTML; open with Read) — the approved Android look:
   Main.dc.html = Summary A, 02 = Summary B, 03 = metric page, 04 = Browse, 05 = Sleep, 06 = Workouts,
   07 = live recording, 08 = sleep schedule, 09 = Settings, 10 = Coach, 11 = Devices, 12 = onboarding.
   The mockups are a style reference; the iOS anatomy decides WHAT is on screen.
   Where the iOS anatomy notes an Android change (e.g. visible night picker on Sleep), follow the note.

`SCRATCH` = `docs/superpowers/plans/2026-09-30-android-m3-port` (this folder). Screenshots: write them to a temp dir (e.g. `$TMPDIR/renoop-shots/`), never into the repo.

## Android code map
- App module `android/app`, Kotlin + Compose, package `com.noop` (applicationId `com.renoop.whoop`).
- Shell: `ui/AppRoot.kt` (one NavHost, `Destination` enum). Theme: `ui/Theme.kt` (`NoopTheme` = Material You;
  legacy `Palette.*` tokens are bridged to the Material scheme so old screens still render).
- NEW design system for rebuilt screens: `ui/m3/` — `HealthColors.kt` (`Health.colors.heart`, `.charge`,
  stage/zone/score colours, `LocalTonalIcons` for settings icon circles), `M3Components.kt` (`LargeTitle`,
  `SectionHeader`, `HealthCard`, `CardTitleRow`, `ValueWithUnit`, `ListGroup { item { shape -> ListRow(...) } }`,
  `SwitchRow`, `M3Switch`, `TonalIcon`, `RowIcon`, `PeriodSegmented`, `SyncFooter`, `NoticeCard`, `EmptyState`,
  `M3Dimens`), `M3Charts.kt` (`MiniLineChart`, `MiniBarChart`, `WeekColumnsChart`, `ActivityRings`,
  `ProgressRing`, `ringFraction`). Extend `ui/m3/` when a piece is reusable; keep screen code in its own file.
- Rebuilt screens use ONLY `MaterialTheme.colorScheme`, `MaterialTheme.typography`, `Health.colors`,
  `LocalTonalIcons`, `M3Dimens` — never `Palette.*`, never `Color(0x…)` literals, never raw text sizes.
  Material 3 components (NavigationBar, TopAppBar, Switch, SegmentedButton, AlertDialog, ModalBottomSheet,
  DatePicker, TimePicker, SearchBar, FilterChip, AssistChip…) wherever one exists. Library: material3 1.2.1
  (Compose BOM 2024.06.00, Kotlin 1.9.24) — no M3 Expressive APIs, no PullToRefreshBox (use the
  `PullToRefreshContainer` + `rememberPullToRefreshState` pattern TodayScreen.kt already uses).
- Data: reuse the existing Android data/analytics layer (Repository/ViewModel/logic helpers the old screens
  use). This port is UI + navigation. Do NOT change analytics formulas, stored values, migrations or BLE.
  If a redesigned screen needs data Android does not have, show what exists and list the gap in your report.
- Removals: when Denis deleted a screen, delete the Android screen and its dead code/tests too (grep for every
  reference; tests that only pin a deleted screen go with it). Never delete Room entities/DAOs/migrations.

## Strings (all nine locales, always)
Every new user-facing string goes into `values/strings.xml` AND `values-{de,es,fr,it,pl,pt-rPT,ru,zh}`.
Use the helper, which pulls Denis's translations from the iOS catalogue when the English text is an iOS key:
```
python3 SCRATCH/tools/addstr.py lookup "Show All Metrics"
python3 SCRATCH/tools/addstr.py add summary_show_all_metrics "Show All Metrics"
python3 SCRATCH/tools/addstr.py add sleep_nights_until "%1$d sleep sessions until results" --ru "…" --de "…" …
python3 SCRATCH/tools/addstr.py addjson file.json   # batch: [{"name":..,"en":..,"ru":..}, ...]
```
It refuses (writes nothing) when a locale has no translation — then pass them explicitly (write real, natural
translations; Russian matters most: the user reads Russian). Use Android format specifiers (%1$s, %1$d). Name
new keys by screen (`summary_…`, `sleep_…`, `workouts_…`, `browse_…`, `settings_…`). Reuse existing keys when
the meaning is identical. Use plurals (`<plurals>`) only if you add them to all locales by hand.

## Build, test, look (ONE gradle process at a time — the Mac has 8 GB RAM)
```
cd /Users/ant1/Documents/reNOOP/android
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
./gradlew assembleDemoDebug --console=plain -q 2>&1 | grep -E '^e: |error:|FAIL' | head -40   # compile + APK
JAVA_TOOL_OPTIONS="-Duser.language=en -Duser.country=US" ./gradlew testFullDebugUnitTest --continue --console=plain 2>&1 | grep -E 'tests completed| FAILED$'
```
Known pre-existing failures (ignore unless you touch them): RecoveryDriversTest ×2 (float rounding),
StressPersonalBaselineSurfaceTest, TodayWorkoutTapTest ×4 (they read iOS files Denis deleted — delete/rewrite
them when you replace the Android screen they pin). Add pure-logic unit tests for any non-trivial new logic.
Incremental compile ≈ 2–4 min. Run gradle in the foreground (timeout 600000) — never two at once.

Emulator (demo flavour has 120 days of synthetic data — use it for screenshots):
```
ADB=~/Library/Android/sdk/platform-tools/adb
$ADB devices                       # emulator-5554 should be listed (the orchestrator starts it)
$ADB install -r app/build/outputs/apk/demo/debug/app-demo-debug.apk
$ADB shell am start -n com.renoop.whoop.demo.debug/com.noop.ui.MainActivity
$ADB exec-out screencap -p > $TMPDIR/renoop-shots/<name>.png   # then Read the PNG to look at it
$ADB shell input tap X Y ; $ADB shell input swipe x1 y1 x2 y2 300 ; $ADB shell input keyevent BACK
$ADB shell "cmd uimode night yes|no"                     # dark / light check
```
SPEED RULE (user wants it faster): screenshot each rebuilt screen in LIGHT only, plus ONE dark spot-check of the main screen of your task; keep emulator time short (stop the Gradle daemon first, batch adb commands). Task 09 does the full dark pass.
Look at every screen you build before committing. Compare against the mockup and the iOS
anatomy; fix what is off. If the emulator is not running, say so in your report (do not start another one).

## Commits (straight to main, like Denis; never push, never rebase)
- Small commits per coherent step. Stage only paths you changed: `git add -- <paths>` (never `git add -A`,
  never commit `android/local.properties`, never `git stash`, never reset other people's work).
- Message style: `android <area>: <what> (refs Denis <sha>)`, body = short bullets, then a blank line and
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Build must compile before each commit; run the unit tests before the last commit of your task.

## Report back
End with: commits made (sha + subject), what each screen now shows, screenshots taken (paths), known gaps /
things you could not port and why, test results. Keep it factual; do not claim a check you did not run.

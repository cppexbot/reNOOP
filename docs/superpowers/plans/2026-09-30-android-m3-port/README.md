# Android port of Denis's iOS 26 redesign (Material 3)

Plan and working notes for bringing the reNOOP iOS redesign (Denis, 2026-09-26..30) to the Android app in
Material 3 / Google-app style. Decisions (user, 2026-09-30): Material You colour from the wallpaper; reNOOP ring
palette (Charge green, Effort blue, Rest violet); the Summary offers two layouts (Denis's "Detailed" and a
"Compact" Fitbit-like grid, pref `noop.summaryLayout`); work is committed step by step to the `android-m3` branch (main is merged into it; see HANDBOOK "On the Windows PC" for the PC set-up).

- `HANDBOOK.md` — rules every implementing agent follows (design system, strings in 9 locales, build/test/emulator).
- `ios-anatomy.md` — screen-by-screen anatomy of Denis's iOS screens with exact strings.
- `tasks/01…09` — the port broken into tasks; `mockups/` — the approved Material 3 references
  (Design canvas: https://claude.ai/artifact/WrtJBAqCxTcr8rpBkEFL2E); `tools/addstr.py` — adds a string in all
  nine Android locales, reusing Denis's iOS translations.

## Status
| Task | State | Commits |
|---|---|---|
| Rebrand + Material You theme + `ui/m3` | done | 9e40ed9b, 4c5610b2 |
| 01 Shell, Browse, removals | done | 42c828cc, cec7f311 |
| 02 Metric page, All Metrics, Trends | done | 3f6e4e2b, 097122d1 |
| 03 Summary (A/B) replacing Today | done | 052c956e, 2021324b, 531311f8 |
| 04 Sleep, Vitals, More Sleep Data, Sleep Schedule | done (WIP 8246e461 finished on the PC, merged with main's sleep fixes) | 8246e461 + merge |
| 05 Workouts | done (no Lift Log / gym session on Android; the route map is the offline drawing, no tiles) | e3462f91, 9046e481 |
| 06 Settings | done (Devices must still link Sync, Power saving, HR broadcast; Coach settings must take the on-device-signals switch: see the task report) | c6b5f47a, 9af446e5, 172fa05c, ab0e6c3c |
| 07 Coach, Devices, Onboarding | todo | |
| 08 Heart Rate, Mindfulness, Journal, What Moves You, Lab Results | todo | |
| 09 Audit, widgets, notifications, i18n, dead code, dark pass | todo | |

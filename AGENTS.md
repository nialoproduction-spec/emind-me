# Notes for AI coding assistants

Read this before you change anything. `README.md` explains what the app does;
this file covers how the code fits together and the rules that keep it working.

## What it is

**Remind Me** is a macOS 14+ menu bar app for Apple Silicon. It uses Swift 5.9
(SwiftPM, Swift 5 language mode), SwiftUI, SwiftData and an AppKit `NSPanel`.
Everything stays on the Mac: no network, no account, no cloud.

## Building

- **You need full Xcode.** The Command Line Tools alone fail. `@Model`,
  `@Query` and `@State` are macros whose plugins only ship with Xcode, and
  without them you get "SwiftUIMacros not found" plus a cascade of `$x` errors.
- To run the tests locally, use `swift test --skip UIPreviewTests`.
- To build, run `./build.sh`. It produces `dist/Remind Me.dmg` with an ad-hoc
  signature.
- **Without a Mac:** push to `main`. `.github/workflows/build-dmg.yml` runs the
  tests on a GitHub macOS runner, renders UI previews, builds the `.dmg` and
  publishes it all as a GitHub Release named `build-N`.
- The build fails if any test fails. Keep the tests passing.

## Map

```
Sources/RemindMe/
  App/RemindMeApp.swift          @main entry
  App/AppDelegate.swift          menu bar item, start-up, right-click menu
  Models/
    Item.swift                   @Model: a routine (repeating / at a time) or a goal
    Occurrence.swift             @Model: one firing of a routine (done/skipped/missed…)
    ItemParser.swift             plain text → ParsedItem ("drink water every 40 min #health")
    ExtraSettings.swift          PersistedSettings<T> + AppSettings (snooze, weekly, smart, categories)
    PanelTheme / PanelPlacement / EscalationSettings / EndOfDaySettings
  Services/
    ReminderScheduler.swift      THE core loop: 20 s tick, firing, nagging, snooze, pause-resume,
                                 away hold, end-of-day + weekly summary triggers, shortcuts
    ItemActions.swift            pause / resume / edit / apply suggestion; OccurrenceActions (checklist)
    GoalCheckIn.swift            goal answers per day (Done / Not today), unanswered goals
    ItemDeletion.swift           the ONLY way to delete an Item (removes its occurrences too)
    StoreRepair.swift            raw SQLite clean-up of orphaned rows, runs before SwiftData opens
    Insights.swift               history, streaks, weekly summary, smart suggestions (pure functions)
    AwayDetector.swift           idle time → "away" (no permissions needed)
    GlobalHotkeys.swift          ⌃⌥D / ⌃⌥S / ⌃⌥K via Carbon RegisterEventHotKey, only while a reminder shows
    BreakCycle.swift             break timer ("rest every 40 min and take a 10 min break"): pure
                                 BreakCycleState + BreakCycleManager; state in UserDefaults (not
                                 SwiftData), countdown at the notch (not the menu bar), pauses while the Mac sleeps
    NotificationService.swift    local UNUserNotifications
    FocusGuard.swift             full-screen / Focus detection
    PersistenceController.swift  ModelContainer
  Panel/
    ReminderPanel.swift          borderless non-activating NSPanel
    NoticePill.swift             reminders' popup: the habit card's look (theme, a face-kit face, title)
                                 with no buttons, a short quote (ReminderQuotes) instead;  sent off by its ×,
                                 a double-click, or a 0.9 s rest of the pointer (`ReminderPopupSettings
                                 .dismiss`): last words + shake, "Sayonara." / "accepts fate", dissolve
    BreakIsland.swift            the break timer's home, at the camera notch: solid colours (the pick
                                 shows exactly; glass was tried and dropped), living faces (blink /
                                 sleepy bob + drifting z's / angry shake), breathing break with
                                 rotating prompts; "Working" / "Break" + countdown, or
                                 "Come back!" with a red pulsing left side and red +time away; work
                                 countdown kept or hidden (`BreakTimerSettings.keepWorkCountdown`);
                                 colours per state (`IslandPalette`: work black, break #C5D2E5, time
                                 away counted up in red), set in Settings → Smart;
                                 BreakIslandRules / IslandGeometry = pure, tested
    ReminderPanelController.swift  show/hide fades, auto-hide, sizes, placement, overlays
  Views/
    PanelRootView.swift          picks the layer: live reminder > end of day > weekly > list > pill
    ExpandedPanelView.swift      the list (Goals → Reminders → Today), swipe/context actions,
                                 inner pages (Edit, History, Weekly), add field, suggestions
    LiveReminderView.swift       the pop-up card: face, Done / Snooze (lengths) / Skip
    EditItemView, ItemHistoryView, WeeklySummaryView, SmartSettingsView, ThemeSettingsView,
    ManageRemindersView, ReminderRowView, ChecklistRowView, CollapsedPillView, EndOfDaySummaryView
  Faces/                         24 traced kaomoji faces, animation, menu bar face; Kaomoji.swift = the
                                 face kit (26 eyes × 27 mouths × 11 extras = 7,722 faces, 9 moods);
                                 MenuBarFace wakes near the pointer and its pupils follow it
                                 (`look`/`watchImage`, polled 10×/s, 30×/s while awake)
Tests/RemindMeTests/             XCTest; UIPreviewTests renders PNGs when PREVIEW_DIR is set (CI attaches
                                 them to the release: look at them after any visual change)
Design/, scripts/trace_faces.py  source art + the tracer that generated Faces/FaceArt.swift
```

## Rules that matter

1. **Delete items only through `ItemDeletion.delete`.** `Occurrence.item` is a
   one-way link with no inverse. If you delete an `Item` directly, its
   occurrences point at nothing, and SwiftData crashes the app at launch. This
   happened in build 8.
2. **New `@Model` fields must be optional, or have a default.** That way
   SwiftData's automatic lightweight migration keeps people's data. Never
   rename or remove a stored property without writing a migration plan.
   `MigrationTests` opens a store written in the old shape, so extend it when
   you change the models.
3. **All due times are absolute `Date`s** (`Item.nextFireDate`,
   `Occurrence.nextEscalationAt`). Never use countdown timers; the tick only
   compares dates.
4. **A pending occurrence blocks its routine's next firing.** Anything that
   resolves one must set `status` away from `.pending` and set
   `nextEscalationAt = nil`. In the checklist, "Not done" is stored as
   `.unfinished` for this reason.
5. **The reminder on screen is answered through the scheduler**
   (`markDone`, `skip`, `snooze(minutes:)`, `resolveActive(as:)`). Never set
   its status directly, because the card would stay up.
6. **Tests must not touch real system services.** `ReminderScheduler.init` and
   the `ItemActions` / `ItemDeletion` functions take injectable closures for
   the clock, Focus, away, notifications and settings. `UNUserNotificationCenter`
   crashes outside an app bundle, so always pass no-ops in tests. Use
   `PersistedSettings.testing(...)` for settings.
7. **The panel never steals focus.** It is a non-activating `NSPanel`. Put
   inner screens inside the panel as pages (see `ExpandedPanelView`), not in
   new windows or sheets.
8. **Concurrency.** UI, settings stores and the scheduler are `@MainActor`.
   A default argument must not read main-actor state, because that is a
   compile error with the current compiler.
9. **Previews.** `ImageRenderer` can't draw AppKit-backed controls (text
   fields, pickers, toggles, menus, `List`, `ScrollView`); they show up as
   yellow boxes. That is expected. Lay views out so the content can be
   rendered without a `ScrollView` (see `scrolls:` on `EditItemView`).

## Style

- The person using the app reads every string. Keep them short and plain,
  with no jargon.
- Keep pure logic (parsing, scheduling maths, insights) in testable functions
  separate from views. Add tests next to any change in behaviour.

## Types (v2)
- Reminder = `Item.style == .justRemind`: popup only, no Occurrence, no Done/Snooze/Skip, no notification.
- Habit = `.habit` (nil `styleRaw` counts as habit): the full card and notification.
- Goal = `kind == .goal`: no schedule. Answered once a day, Done or Not today, at the check-in time
  (`GoalNudgeSettings`, 8 PM default, editable in Settings → Smart) via `GoalCheckInView` in the panel.
  Answers are stored as done / skipped `Occurrence`s (`Services/GoalCheckIn.swift`), never pending,
  and are kept out of the Today checklist. `isAchieved` = finished for good (stops the asking).
- Type is picked for you as you type (a time → Reminder, none → Goal) and shown by `TypePicker`,
  three icons beside the send arrow: the chosen one lit blue, the rest grey; click to switch
  (Habit also ⌘↩). No preview bar pops up while typing. "remind me to" and typos of "every" / units are
  cleaned up by the parser first.
- Rows show "N total" and "N days in a row". A habit card has three buttons only: Done, Snooze
  (shortest length; right-click for the others), Skip.
- All sounds are off. Don't add any.
- Enter saves at once.
- The break timer is listed in its own "Break timer" section (`BreakTimerSection`): `stop()` greys it
  out but keeps `config`, `resume()` restarts it, `remove()` forgets it. Lengths are in seconds.
- A break that ends with no input for 20 s goes to phase `.waiting` ("Break's over" stays at the
  notch); the next work stretch starts counting at the first key press / mouse move (idle ≤ 2 s).
  The idle time is injected (`idleSeconds:`) so tests never read the real one.
- A menu bar click opens the list directly (`openMainPage`), not the small pill.

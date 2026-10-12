# Remind Me

A macOS 14+, Apple Silicon–only menu bar reminder app. SwiftUI + SwiftData
for storage, an AppKit `NSPanel` for the floating panel. Everything is local
— no cloud, no account, no login.

## Build

**Requires full Xcode** (free, App Store), not just the Command Line Tools.
SwiftUI's `@State` and SwiftData's `@Model`/`@Query` are compiler macros
whose plugins only ship inside Xcode.app. With CLT alone the build fails with
"plugin for module 'SwiftUIMacros' not found" and a cascade of `$x` /
`PersistentModel` errors. After installing Xcode, point the tools at it once:

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

Then:

```sh
./build.sh
open "dist/Remind Me.dmg"
```

`build.sh` builds the release binary, assembles `Remind Me.app`, signs it,
then packages a `.dmg` (app + an `Applications` symlink to drag into) and
signs that too. To open the project in Xcode instead, just `open
Package.swift`.

**Signing:** ad-hoc (`-`) by default — satisfies Gatekeeper only on the Mac
that built it. To hand the `.dmg` to someone else without a Gatekeeper
warning, you need a paid Apple Developer Program membership and a
"Developer ID Application" certificate:

```sh
export CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
./build.sh
```

Even then, a `.dmg` someone downloads needs **notarization** to avoid the
warning entirely — not scripted here, since it needs your own Apple ID /
API key:

```sh
xcrun notarytool submit "dist/Remind Me.dmg" --keychain-profile "<profile>" --wait
xcrun stapler staple "dist/Remind Me.dmg"
```

## How it works

- **Natural-language input** (`ItemParser`) — type plain text into the
  panel's field ("drink water every 40 minutes", "walk at 4am every day",
  "go to Godavari"). A local, regex-based parser (no network, no on-device
  model) classifies it into one of three kinds and shows a confirmation
  banner — kind, title, schedule — with Discard / Edit / Save before
  anything is created:
  - **Repeating routine** — an explicit interval ("every 40 minutes", "every
    3 days") → fires on that interval, repeatedly.
  - **Scheduled routine** — a clock time ("at 4am", "at seven a.m.") →
    fires daily by default, or on specific weekdays if named ("every
    Monday and Wednesday"). A time with no explicit repeat word defaults to
    daily — that's what the confirmation step is for.
  - **Goal** — no time at all → never alerts, just tracked, with an
    optional target date picked up from phrases like "by Friday" via
    `NSDataDetector`.
- **Status item** (`AppDelegate`) — left-click toggles the panel, right-click
  quits. No Dock icon (`LSUIElement` in Info.plist).
- **Panel** (`ReminderPanel` / `ReminderPanelController`) — a borderless,
  non-activating `NSPanel`. `isMovableByWindowBackground = true` makes it
  draggable anywhere on screen without any manual mouse tracking; dragged
  position is saved to `UserDefaults` and restored on next launch.
  `canBecomeKey = true` lets its text field take typed input, but the panel
  never activates the app or steals focus from whatever app is frontmost.
  Collapse/expand is an animated `NSPanel.setFrame`, anchored at the
  top-left corner so growing never jumps the panel somewhere unexpected.
- **Auto-hide** (`PanelAutoHide`) — the panel fades in and out
  (0.18s / 0.3s) instead of sitting on screen:
  - The time / next-reminder pill appears on a menu bar click and fades
    out after 6 seconds (stays while hovered; a click elsewhere hides it).
  - The expanded list stays while it's being used and fades out on a click
    elsewhere, after 15 seconds idle, or right after a new reminder is
    saved. Half-typed text is kept (`PanelDraft`) for next time.
  - A live reminder **stays until Done, Snooze or Skip**. While it waits it
    nags in place (the face's mood steps up and the panel comes forward,
    count and gap from Settings); after the last nag it's counted as
    unfinished for the day but stays on screen to be answered. During a
    Focus or a full-screen app it's tucked away and comes back afterwards.
    Clicking the menu bar icon brings it forward rather than hiding it.
- **Placement** (`PanelPlacement`, Settings → Position) — top right
  (default), top left, bottom right, bottom left, a custom spot (drag the
  panel anywhere to save it), or under the menu bar icon like a drop-down.
  Resizing keeps the chosen corner anchored.
- **Managing reminders** (Settings → Your reminders) — every routine and
  goal (active first, then paused / achieved), each with a delete button
  and a confirmation before removal. Deleting goes through `ItemDeletion`,
  which removes the item's occurrences too and closes its reminder if it's
  on screen. Older builds deleted only the item, leaving occurrences linked
  to nothing — SwiftData then stopped the app at launch. `StoreRepair`
  clears those leftovers from the database file before SwiftData opens it.
- **Menu bar icon** (`MenuBarFace`) — the —ω— logo. Hover it and it wakes up
  with a random little reaction (happy, shocked, scared, silly, shy, dizzy,
  smug, huffy), then goes back to the logo. While a reminder is waiting it
  shows that reminder's mood face, so it's obvious something's due.
- **Storage** (`Item`, `PersistenceController`) — a SwiftData `@Model`
  covering all three kinds, local `ModelConfiguration` with
  `cloudKitDatabase: .none`.
- **Notifications** (`NotificationService`) — local `UNUserNotification`.
  Repeating routines use `UNTimeIntervalNotificationTrigger`; scheduled
  routines use `UNCalendarNotificationTrigger` (one per weekday if specific
  days were given); goals never get a notification.
- **Theme** (`PanelTheme`, `ThemeStore`) — background/accent/text colors,
  font, size and corner radius, all user-editable from the panel's paintbrush
  button, persisted as JSON in `UserDefaults`.
- **Scheduler** (`ReminderScheduler`) — the reliability-critical piece.
  Every due time lives as an absolute `Date`: `Item.nextFireDate` for the
  next routine firing, `Occurrence.nextEscalationAt` for the next nag. A
  20-second poll compares these to `Date.now` — cheap date math, no
  accumulating countdown to drift. `NSWorkspace.didWakeNotification` forces
  an immediate catch-up check on wake; a routine due during sleep fires
  once on wake rather than flooding with every missed interval, or being
  silently dropped. Nothing schedules the Mac to wake itself, per the spec.
- **Occurrence / escalation** — each firing is its own `Occurrence` row:
  Done / Snooze 5m / Skip, or N unanswered pops M minutes apart before it's
  marked `unfinished` and stops nagging. N and M are set in Settings →
  Reminders ("Pop-ups before giving up" / "Minutes between pop-ups",
  `EscalationSettings`) — default 3 pops, 15 minutes apart. Today's
  occurrences, grouped under "Today — X of Y done," live at the top of the
  expanded panel.
- **Faces** (`Faces/`) — the 24 kaomoji expressions from
  `Design/expressions.jpg`, traced to vector outlines by
  `scripts/trace_faces.py` (re-run it if the sheet changes). The live
  reminder shows an animated face whose mood rises with each unanswered
  pop: cute and blinking on the first, pouty in the middle, angry and
  shaking on the last. Done / Snooze / Skip each play a short reaction
  (happy hop, dozing off, crying) before the panel closes. Line art takes
  the theme's text colour; tears stay brown. Honours Reduce Motion.
- **Logo** — the —ω— face (`Design/logo.png`) is the app icon
  (`Resources/AppIcon.icns`) and the idle menu bar icon (a template image,
  so it follows light/dark menu bars).
- **End of day** (`EndOfDaySettings`, `EndOfDaySummaryView`) — optional,
  off by default. At the chosen time: completion count, unfinished items,
  one-tap reschedule for today.
- **Focus/full-screen** (`FocusGuard`) — full-screen detection is solid
  (public `CGWindowListCopyWindowInfo`). Do Not Disturb/Focus has **no
  public API** on macOS 14; this reads the same undocumented local
  assertions file other menu-bar utilities have used, which Apple can break
  on any update without notice. If that read ever fails, it defaults to
  *not* suppressing — see the comment in `FocusGuard.swift`.

## Where this came from

The panel's window configuration (borderless + non-activating style mask,
`isMovableByWindowBackground` for dragging, floating level, transparent
background hosting SwiftUI) follows the same pattern used by Vorssaint's
pinned floating panels (`github.com/vorssaint/vorssaint-utils`,
GPL-3.0-or-later) — specifically their `OverlayPanel`/`ScreenshotPinWindow`
classes, not their much larger notch-shape engine (`NotchWindowHost`), which
does something different (a hard-anchored, shape-morphing island) and isn't
what a draggable reminder panel needs.

**License note:** none of this project's files are copied from vorssaint-
utils — everything here is written from scratch. But if you later copy
actual code from that repo (rather than just the technique), GPL-3.0 is
copyleft: this project would then have to ship under GPL-3.0 too, source
included. Worth knowing before you decide how to distribute Remind Me.

## Not done yet

- Launch-at-login toggle
- Notification action buttons (snooze / complete from the system banner
  itself — the panel's own Done/Snooze/Skip work today)
- Voice input, keep-awake, calendar sync, wake-from-sleep
  scheduling — explicitly out of scope for this version per your spec
- iCloud sync (explicitly out of scope — local-only, no account — noting in
  case you change your mind later)

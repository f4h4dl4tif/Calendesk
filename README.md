# Calendesk: desktop calendar for macOS

A native SwiftUI calendar and desktop widget for macOS 14+, the companion to **Tickdesk** (desktop clock). It uses the same appearance options, fonts and color combinations, so the two widgets match.

## Features
- **Four calendar styles**: Month Grid, Agenda (upcoming events), Day Page (tear-off), Week Strip
- **Desktop widget**: borderless calendar pinned to the desktop (or normal / always-on-top). Drag it to move it. Browse months with the ‹ • › controls or by scrolling or swiping over it (• or the month title jumps back to today). Click a day to see its events below the grid, double-click to open the app, right-click for quick options. Also: size, opacity, optional background panel, lock position
- **Appearance**: Light, Dark or System (follows macOS automatically)
- **Fonts**: the same 14 font styles × 8 weights as Tickdesk
- **Color combinations**: the same 10 presets as Tickdesk (each with a light and a dark variant), plus custom colors (background, card, text, accent) per mode
- **Match Tickdesk**: copy Tickdesk's theme, font and colors once, or follow them automatically
- **Events**: shows events from the calendars already set up in the Calendar app (iCloud, Google, Exchange…), event dots on the grid, per-calendar show/hide, 12/24-hour times, agenda range 1–30 days, add new events
- **Calendar options**: week starts on System/Sunday/Monday/Saturday, week numbers, weekend highlighting (follows your region's weekend), days from adjacent months
- Menu bar item (icon, icon + day, or short date) listing today's events, and launch at login
- Settings work as a draft with Save / Revert and a live preview, the same as Tickdesk

## Build
```bash
./build_app.sh        # produces build/Calendesk.app
open build/Calendesk.app
./build_installer.sh  # optional: dist/Calendesk-1.0.dmg and .pkg
```

Shortcuts: ⌘, Settings · ⌘T Today · ⌘← / ⌘→ change month · ⌘N New Event · ⇧⌘W toggle the desktop widget.

Developer aids: `Calendesk --selftest` and `Calendesk --snapshot <dir>` (renders every style with sample events).

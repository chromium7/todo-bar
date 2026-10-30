# TodoBar

A tiny always-on-top todo list for macOS (14+). SwiftUI + AppKit, no dependencies.

## Build & install

```sh
./build.sh            # builds build/TodoBar.app
./build.sh --install  # also copies it to ~/Applications and launches it
```

On first launch it registers itself as a login item (toggle in Settings, the
menu bar icon, or System Settings → General → Login Items).

## Using it

- **Move**: drag the header. **Resize**: drag the grip in the bottom-right corner.
- **Collapse to side**: press Esc, click the collapse button in the header, or double-click the header.
  The panel slides into a slim tab on the nearest screen edge showing the number of
  open tasks (and a red badge with the overdue count). Click the tab to expand; drag it
  to move it (it snaps to the nearest left/right edge).
- **Workspaces** (e.g. Office / Personal): the title in the header is the current
  workspace — click it for the Workspaces page, which lists each one with its open and done
  counts. Click a workspace to open it, + to add one, and hover for rename and delete (a
  workspace with tasks asks first, in place; ⌘Z undoes). ⌘1…⌘9 switch directly,
  ⇧⌘N makes a new one, and the menu bar ✓ icon switches without opening the panel.
  New tasks go into the workspace you're in; right-click a task → Move to… to move it.
  The collapsed tab shows the workspace's first letter. Reminders fire for all workspaces.
- **Add**: type in "Add a task…" and press Return (⌘N jumps there). The calendar icon
  next to it sets a deadline for the new task. Adding a task automatically switches
  to By Deadline sorting: soonest first, with tasks without a deadline last.
- **Deadline**: hover a task → calendar icon, or click its deadline to change it.
  Overdue deadlines show in red, today's in orange. The collapsed tab shows a red
  badge with the number of overdue tasks.
- **Repeat**: in the deadline popover, pick Every day / weekday / week / month. Ticking a
  repeating task moves it to Done and adds a fresh copy with the next date.
- **Reminders**: a notification 15 min before and at a timed deadline, or at 9:00 on
  the day for date-only ones. Turn off in Settings → Deadline reminders.
- **Reorder**: drag a task up or down; the others move aside as you go.
  Settings → Sort → By Deadline orders by date instead (dragging is off in that mode).
- **Complete**: click the circle. Finished tasks slide into a collapsible **Done** section.
- **Edit / notes**: double-click a task to edit its title and add a note (links in notes
  are clickable; ⌥↩ for a new line). Right-click for more.
- **Undo**: ⌘Z / ⇧⌘Z undo and redo deletes, completes, edits, reorders and "Clear done".
- **Keyboard**: see [Keyboard shortcuts](#keyboard-shortcuts) below.
- **Fade when idle**: the panel goes semi-transparent when the mouse isn't over it
  (and you're not typing). Turn off in Settings → Fade when idle.
- **Settings**: the gear button in the header (or `⌘,`, or the menu bar ✓ icon) slides in a
  settings page for theme, style, the look shuffle, sorting, clearing Done, reminders, fading,
  launch at login and quitting. Esc or the back arrow returns to the list.
- **Theme**: sun/moon button switches light/dark; Settings → Theme also offers System and
  Soft Pink (a light theme with a pink wash and rose accents, in every style).
- **Style**: Settings → Style → Liquid Glass (default), Standard, Doodles (a chat-wallpaper look:
  hand-drawn line doodles over a soft gradient, near-black in dark, green-cream in light,
  pink with Soft Pink), or Rilakkuma (faint Rilakkuma, Korilakkuma and Kiiroitori stickers
  with polka dots on honey-cream, dark chocolate in dark, or pink with Soft Pink, plus
  honey-brown accents), or Quby (faint Quby stickers with polka dots on baby blue, deep navy
  in dark, or pink with Soft Pink, plus blush-pink accents); all work in light and dark. The
  sticker images live in `Resources/Rilakkuma` and `Resources/Quby` and are copied into the
  app by `build.sh`.
  Built with the macOS 26 SDK (Command Line Tools / Xcode 26+), this uses Apple's real
  Liquid Glass (`NSGlassEffectView`). With an older SDK it falls back to an imitation
  (clearer blur, top highlight, bright rim). Rebuild after updating the tools to switch.
- **Shuffle look**: Settings → Shuffle look → Change automatically picks a random theme and
  style every 12 hours (at midnight and noon) or every day (at midnight), from the themes and
  styles you tick. Picking a look yourself keeps it until the next change; Shuffle now
  changes it straight away.
- There's no Dock icon; the menu bar ✓ icon can show, collapse, or quit the app.

## Keyboard shortcuts

Shortcuts work while the TodoBar panel is focused (the last thing you clicked).

**General**

| Shortcut | Action |
| --- | --- |
| `Esc` | Close Settings or Workspaces, or collapse the panel to the side |
| `⌘N` | New task (expands the panel and focuses "Add a task…") |
| `⌘,` | Settings |
| `⌘Z` | Undo |
| `⇧⌘Z` | Redo |
| `⌘Q` | Quit TodoBar |

**Workspaces**

| Shortcut | Action |
| --- | --- |
| `⌘1` … `⌘9` | Switch to workspace 1–9 (in the order on the Workspaces page) |
| `⇧⌘N` | New workspace |

**Task list** (click a task to select it)

| Shortcut | Action |
| --- | --- |
| `↑` / `↓` | Select the previous / next task |
| `↑` on the first task | Back to "Add a task…" |
| `Space` | Mark the selected task done / not done |
| `Return` | Edit the selected task's title and note |
| `⌫` or `⌦` | Delete the selected task |
| `⌘↑` / `⌘↓` | Move the selected task up / down (manual sort only) |

**Adding and editing**

| Shortcut | Action |
| --- | --- |
| `Return` in "Add a task…" | Add the task |
| `↓` in "Add a task…" | Jump into the task list |
| `Esc` in "Add a task…" | Collapse the panel |
| `Return` while editing | Save the title and note |
| `⌥Return` in a note | New line |
| `Esc` while editing | Cancel the edit (also cancels a workspace rename) |
| `⌘C` / `⌘V` / `⌘X` / `⌘A` | Copy / paste / cut / select all in text fields |

## Data

Tasks are stored in `~/Library/Application Support/TodoBar/tasks.json`, workspaces in
`workspaces.json` next to it.

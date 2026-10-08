# Tuloy

*Tuloy* means "keep going" in Filipino.

A small macOS app that starts your Claude usage window on a schedule, so it resets when you want it to.

Claude's usage limit runs in 5-hour windows that start with your first message. Tell Tuloy when you want a fresh window (say 11:00 AM) and it sends a tiny message through Claude Code at 6:00 AM. By the time you're deep in work, your allowance resets.

For how it all works inside, step by step, see [HOW_IT_WORKS.md](HOW_IT_WORKS.md). Ideas for what to add next are in [helpideas.txt](helpideas.txt).

## Requirements

- macOS 14 or later
- Xcode 16 or later, to build it
- [Claude Code](https://code.claude.com/docs), signed in with your Claude plan

**Claude Code has its own sign-in.** Being signed in to the Claude desktop app or claude.ai doesn't count. Tuloy's Connection screen checks this and signs you in with one click; by hand it's `claude auth login` in Terminal.

Tuloy uses nothing else: no packages, no accounts, no server.

## Install

```sh
make install
```

That builds Tuloy, copies it to /Applications and starts it. The first time, a welcome window walks you through four steps: what Tuloy does, connecting to Claude, picking your fresh time, and where to find it afterwards. Run `make install` again after changing the code to update the copy that's running.

| Command | What it does |
|---|---|
| `make demo` | Starts Tuloy with made-up data, to look around |
| `make app` | Builds `build/Tuloy.app` |
| `make run` | Builds it and starts it |
| `make test` | Runs the tests |

## Where everything is

Tuloy lives in the menu bar (no Dock icon) and has four windows. Closing any of them leaves Tuloy running. To quit, click the menu bar icon and choose Quit Tuloy.

### The Tuloy window

Opens when you open the app, and from **Open Tuloy…** in the menu bar.

| Screen | What it's for |
|---|---|
| **Home** | What's happening now: the usage ring, when your fresh window is, Ping Now, Pause, and the last pings with what came back |
| **Schedule** | When you want your fresh window and on which days, Keep going, and a picture of the day that follows |
| **Connection** | Checks Claude Code step by step, signs you in, sends a test ping, and connects live usage |
| **Preferences** | The menu bar icon's look, which windows open at start, notifications, launch at login |
| **Help** | The idea, where everything is, what the icon means, iPhone steps, and common questions |

### The mini window

A small panel that floats above your other windows, on every desktop: the ring, your fresh time, Ping Now and Pause. Open it from Home or the menu bar. Preferences can open it every time Tuloy starts.

### The step-by-step guide

Every command for connecting, in order, in a window that stays on top so you can follow along in Terminal. Open it from Connection or Help.

### The menu bar icon

Pick a look in Preferences:

| Mode | What it shows |
|---|---|
| Classic | ✓ running, ⏸ paused, ⚠ needs attention |
| Usage | A ring that fills as you use your allowance, with the % inside |
| Timer | A countdown to your next fresh window |
| Ultra | The usage ring with the countdown inside |

A problem always shows ⚠, whatever the mode. Click the icon for the menu:

```
Tuloy
Fresh window at 11:00 AM · in 3:12
This window: 23% used · as of 7:48 AM
This week: 41% used · resets Thu 9:00 AM
Next ping Tue 6:00 AM
Last ping 6:00 AM ✓
──────────────────────────
Open Tuloy…
Show Mini Window
──────────────────────────
Pause
Ping Now
Recent Pings                ▸
──────────────────────────
Settings…
Help
Quit Tuloy
```

When something needs you, the menu says what, how to fix it, and gains a **Fix This…** item that opens Connection.

## Connecting to Claude

Open **Connection**. It has four steps, each with a tick when it's done:

1. **Claude Code is installed.** If not, it shows the install command to paste into Terminal.
2. **Signed in with your Claude plan.** **Sign In…** opens Terminal and your browser. Sign in there, come back, and Tuloy checks again by itself. This is the step most people are missing.
3. **Send a test ping.** The real thing. A green "It works" shows when your window resets and how many tokens the ping used. If it fails, it says why and what to do.
4. **Live usage** (optional, below).

Prefer to do it by hand? **Open the Step-by-Step Guide** lists every command with a Copy button.

## Keep going

After your fresh window, Keep going starts a new one each time one ends, until the time you pick. With a fresh window at 11:00 AM and keep going until 6:00 PM, windows start at 6:00 AM, 11:00 AM and 4:00 PM. It never starts one that would get in the way of tomorrow's ping.

## Demo mode

```sh
make demo
```

Tuloy starts with made-up data and opens the main and mini windows. It sends no pings, never runs Claude Code, shows no notifications, and keeps its settings apart from yours. The menu gains a **Demo Scene** submenu to switch between a window in progress, almost out, no window yet, a problem, and a used-up week. Ping Now and Sign In pretend. Quit it from the menu when you're done.

To see the welcome window instead:

```sh
open -n build/Tuloy.app --args --demo --setup
```

## How it works

- **Pings go through Claude Code.** Tuloy runs `claude -p` and never reads your login: Anthropic only allows subscription logins inside its own apps, so the official `claude` command does the talking.
- **Each ping is as small as it gets.** The smallest model (Haiku) with thinking off, no tools, none of your hooks, plugins or CLAUDE.md, and no saved transcript. The message is "hi" and the reply is one word. Recent pings shows how many tokens each one used.
- **Missed pings still go out.** Tuloy checks the clock every 30 seconds instead of setting one long timer. If your Mac was asleep, off or offline when a ping was due, it sends it as soon as it can, as long as that can still help (within 5 hours).
- **It waits for an open window.** A ping only starts a window if none is open. If you were up late and a window is still running at ping time, Tuloy waits for it to end, then pings.
- **Failed pings retry.** After 1 minute, then 2, 5, 15 and 30. If it's something only you can fix, like Claude Code being signed out, Tuloy sends a notification.
- **Usage comes from Claude Code too.** Each ping reports exactly when your window resets, and how much you've used once you're getting close. That feeds the ring, the countdown and the notification.

## Live usage (optional)

The ring updates after each ping. Live usage keeps it current in between, and brings in your weekly limit.

**It only updates while you use Claude Code in Terminal.** It comes from Claude Code's status line, which the Claude desktop app and claude.ai don't run. If that's how you use Claude, skip this: usage still updates with every ping.

To turn it on, open **Connection**, find step 4 and choose **Connect…**. It shows what will change and asks before doing it:

- Adds a small script, `~/.tuloy/statusline.sh`, and points the `statusLine` setting in `~/.claude/settings.json` at it. Nothing else in that file changes, and a copy of the old file is kept at `~/.tuloy/settings-backup.json`.
- Claude Code runs the script as its status line. The script saves the data for Tuloy, then runs the status line you already had, so yours keeps working.
- **Disconnect** puts your settings back the way they were.

Good to know: if you had no status line before, Claude Code now has a blank one, and with any status line set it hides some of its keyboard hints at the bottom of the screen.

<details>
<summary>Connect by hand instead</summary>

In `~/.claude/settings.json`:

```json
"statusLine": { "type": "command", "command": "cat > ~/.tuloy/statusline.json" }
```

Already have a status line script? Change `input=$(cat)` to `input=$(tee ~/.tuloy/statusline.json)` in it instead.
</details>

## When your Mac is closed

A closed or sleeping Mac can't ping. If your Mac is usually asleep at ping time, let your phone send the early ping, and let Tuloy do the rest. These steps are in Help too.

**iPhone (recommended):**

1. Open **Shortcuts** and go to **Automation**. Tap **+**.
2. Choose **Time of Day**. Set your ping time (6:00 AM for an 11:00 AM fresh window) and your days.
3. Pick **Run Immediately**, so it doesn't ask first.
4. Add the **Ask Claude** action with the message "Reply with only the word ok."
5. Run it once with your phone locked, to make sure it goes through.

Needs the Claude app on iOS 18 or later.

**Anything else:** `extras/cloud-ping.yml` runs the same ping on GitHub Actions. The steps are at the top of the file.

Either way, keep Tuloy running. When your Mac wakes, its catch-up ping lands in the window your phone opened and picks up the real reset time, so the countdown, the usage ring and the "fresh window" notification all still work. On days your Mac is awake, Tuloy sends the ping itself, and keep going carries on from there.

## If something's wrong

Open **Connection** first: it shows which step isn't done.

| Tuloy says | What to do |
|---|---|
| Can't find Claude Code | Install [Claude Code](https://code.claude.com/docs). Connection shows the command |
| Claude Code is signed out | Choose **Sign In…** in Connection, or run `claude auth login` in Terminal. Being signed in to the desktop app isn't enough |
| The ping couldn't use your Claude login | Claude Code says you're signed in, but the ping wasn't allowed to use that login. Sign in again, then send a test ping. If it keeps happening after a Claude Code update, see the note below |
| Claude Code isn't using your Claude plan | It's set up with an API key. Sign in with your Claude account instead |
| Couldn't reach Claude | Check your internet. Tuloy retries on its own |
| Weekly limit used up | Nothing to do. Tuloy rests until it resets |

**Recent pings** on Home, and in the menu, lists the last pings: when they went out, what came back, and how many tokens each used.

**A Claude Code change to watch for.** Claude Code's docs say a "bare" mode will one day become the default for `claude -p`, and bare mode doesn't use your Claude login. If that ships, pings will fail with "The ping couldn't use your Claude login" until Tuloy is updated to ask for the normal mode. Tuloy already refuses bare mode where it can, and tells this case apart from simply being signed out.

## Files

| File | What it does |
|---|---|
| `Tuloy/TuloyApp.swift` | Entry point: the menu bar item, the four windows, and what opens at start |
| `Tuloy/AppModel.swift` | The brain: settings, the 30-second loop, pings and state |
| **`Tuloy/Core/`** | **The thinking. No clock, no network, all tested** |
| `Schedule.swift` | Turns "fresh at 11:00" into "ping at 6:00", plus keep going |
| `Planner.swift` | Decides what to do right now: wait, ping, or skip |
| `Usage.swift` | A reading of one of your limits, and the ping history |
| `Format.swift` | Time and countdown text |
| **`Tuloy/Claude/`** | **Talking to Claude Code** |
| `ClaudeCLI.swift` | Finds `claude`, sends the ping, checks your sign-in |
| `PingOutput.swift` | Reads the usage report a ping prints |
| `StatusLineFile.swift` | Reads the live usage file |
| `StatusLineLink.swift` | Connect and Disconnect for live usage |
| `Shell.swift` | Runs a command with a time limit |
| **`Tuloy/UI/`** | **What you see** |
| `Windows.swift` | The list of windows and screens, and the shared pieces: buttons, cards, the big ring |
| `MainWindow.swift` | The Tuloy window, its sidebar, and Home |
| `ConnectionScreen.swift` | The Connection steps, the test ping, and the step-by-step guide |
| `SettingsScreens.swift` | Schedule and Preferences |
| `HelpScreen.swift` | Help |
| `SetupWindow.swift` | The welcome |
| `MiniWindow.swift` | The mini window |
| `MenuBarLabel.swift` | The menu bar icon's four looks |
| `MenuContent.swift` | The dropdown menu |
| `Ring.swift` | The small ring in the menu bar |
| `DayTimeline.swift` | The picture of your day |
| **`Tuloy/System/`** | |
| `System.swift` | Notifications and launch at login |
| `Demo.swift` | Demo mode |
| **Everything else** | |
| `HOW_IT_WORKS.md` | Everything Tuloy stores and does, step by step |
| `helpideas.txt` | Ideas for what to add next |
| `Tests/` | Tests for the schedule, the planner, everything read from or written for Claude Code, and every screen |
| `Package.swift`, `Makefile`, `scripts/`, `Support/Info.plist` | Building the app |

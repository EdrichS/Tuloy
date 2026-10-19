# Tuloy

*Tuloy* means "keep going" in Filipino.

A small macOS app that starts your Claude usage window on a schedule, so it resets when you want it to.

> Tuloy is an independent app. It is not made, endorsed or supported by Anthropic. It doesn't raise any limit: it only changes when a window starts, and each ping uses about 350 tokens of your own plan's usage (no money, no API credit). Read Anthropic's terms and usage policy to decide whether using it is right for you.

Claude's usage limit runs in 5-hour windows that start with your first message. Tell Tuloy when you want a fresh window (say 11:00 AM) and it sends a tiny message through Claude Code at 6:00 AM. By the time you're deep in work, your allowance resets.

For how it all works inside, step by step, see [HOW_IT_WORKS.md](HOW_IT_WORKS.md).

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

That builds Tuloy for both Apple silicon and Intel Macs, copies it to /Applications and starts it. The first time, a welcome window walks you through four steps: what Tuloy does, connecting to Claude, picking your fresh time, and where to find it afterwards. Run `make install` again after changing the code to update the copy that's running.

| Command | What it does |
|---|---|
| `make demo` | Starts Tuloy with made-up data, to look around |
| `make app` | Builds `build/Tuloy.app` |
| `make run` | Builds it and starts it |
| `make test` | Runs the tests |
| `make icon` | Redraws the app icon from `scripts/make-icon.swift` |

## Where everything is

Tuloy lives in the menu bar and has four windows. While the main window, the welcome or the guide is open, it also shows in the Dock, with its own menu bar (Copy and Paste work in every window, and ⌘1 to ⌘8 switch screens). Closing the windows leaves Tuloy running in the menu bar. To quit, choose Quit Tuloy from the panel's (…) button, or from the Tuloy menu while it's in the Dock.

### The Tuloy window

Opens when you open the app, and from **Open Tuloy…** in the menu bar.

| Screen | What it's for |
|---|---|
| **Home** | What's happening now (the same panel as under the menu bar icon), today's real windows on one bar, and the last pings with what came back |
| **History** | A square for each day, darker for more pings, like a contribution chart; then every ping of the last month, with what came back, its tokens, and why it was late if it was |
| **Schedule** | When you want your fresh window and on which days, Keep going, and a picture of the day that follows |
| **Messages** | Messages of your own for Claude, sent later: once, every day, or the moment your next fresh window opens. Choose the folder, the model, the effort, and what Claude may do there. The replies are kept, and a conversation can be carried on in Terminal |
| **Connection** | Checks Claude Code step by step, signs you in, sends a test ping, and connects live usage |
| **Preferences** | The menu bar icon's look, the free usage check, which windows open at start, notifications, launch at login. It says when macOS is blocking notifications or launch at login, with a button to fix it |
| **Help** | The idea, where everything is, what the icon means, iPhone steps, and common questions |
| **About** | What Tuloy is and isn't, what it uses, and what it can't promise |

### The mini window

The same panel, floating above your other windows on every desktop. Open it from Home or the menu bar. Preferences can open it every time Tuloy starts.

### The step-by-step guide

Every command for connecting, in order, in a window that stays on top so you can follow along in Terminal. Open it from Connection or Help.

### The menu bar icon

Pick a look in Preferences:

| Mode | What it shows |
|---|---|
| Classic | Tuloy's own symbol, an open ring: a dot on its way round when running, two bars when paused, a moon when resting, "!" when something needs you |
| Usage | A ring that fills as you use your allowance, with the % inside |
| Timer | A countdown to your next fresh window ("3:41") |
| Ultra | The usage ring with the time left inside: whole hours ("5h", "4h", "3h") while more than two hours are left, then minutes from "120" down to "1" |

A problem always shows the symbol with "!", whatever the mode. A ring that's faded is showing a number more than 15 minutes old. The symbol and the app icon are provisional until the logo is chosen.

### The panel

Click the menu bar icon for a small panel:

```
 (ring)   Fresh at 8:00 PM
  56%     Resets in 41 min
          Usage 2 min ago  ↻

 This week  ▓▓▓▓▓▓▓▓▓░░░  83%

 [ Ping Now ]  [ Pause ]

 Next ping 8:01 PM: when this window ends
 ✓ Pinged. Fresh window at 8:00 PM.
 ─────────────────────────────────────
 Open Tuloy    Mini Window        (…)
```

- **Ping Now** and **Pause** are right there. Escape closes the panel. Ping Now has no keyboard shortcut on purpose: a ping spends tokens and can start a window.
- **↻** checks your usage now. Free: no message is sent, so it uses no tokens and can't start a window.
- **Next ping** always comes with its reason.
- The last line says what just happened, for a few seconds after anything you do.
- **(…)** holds Settings, Connection, History, Help, the last 10 pings and Quit.

When something needs you, the top of the panel becomes the problem, with a **Fix It…** button that opens Connection.

## Connecting to Claude

Open **Connection**. It has four steps, each with a tick when it's done:

1. **Claude Code is installed.** If not, it shows the install command to paste into Terminal.
2. **Signed in with your Claude plan.** **Sign In…** opens Terminal and your browser. Sign in there. The moment it finishes, Tuloy notices by itself, turns the step green and comes to the front. This is the step most people are missing.
3. **Send a test ping.** The real thing. A green "It works" shows when your window resets and how many tokens the ping used. If it fails, it says why and what to do.
4. **Live usage** (optional, below).

Prefer to do it by hand? **Open the Step-by-Step Guide** lists every command with a Copy button.

## Scheduled messages

Open **Messages** and choose **New Message**. Write it the way you would in Claude Code, then choose:

| | |
|---|---|
| **When** | Once, at a date and time; every day at a time, on the days you pick; or at your next fresh window (a minute after your open window resets, so a big job gets a whole window) |
| **Where** | A folder for Claude to work in, or none |
| **What Claude may do** | Answer only (no tools) · Read the folder · Read and edit files in the folder (no commands) · Anything, without asking (asks you to confirm first). Optionally, search the web |
| **Model and effort** | Claude Code's default, Haiku, Sonnet, Opus, Fable or any model name; effort from low to max |
| **More** | Keep the conversation (to carry on later), notify when done, use your Claude Code setup (CLAUDE.md, MCP servers, hooks) or safe mode, stop after 10 minutes to 2 hours, extra instructions |

The editor shows the exact command Tuloy will run. The message runs in the background, so pings carry on; one message at a time. When it's done, the reply is on the Messages screen (and in a notification), with what Claude wasn't allowed to do, and **Continue in Terminal** to carry on the conversation.

Good to know:

- Nobody is there to approve anything, so Claude Code refuses whatever the message doesn't allow, and the reply says so.
- A message sent while no window is open starts one, like a ping. Sent at your scheduled ping's time, it does that ping's job.
- Your Mac has to be awake, with Tuloy running. If it was asleep, the message goes when it wakes, up to 3 hours late (or is skipped, if you say so).
- It never costs money: no API key, no paid extra usage, and nothing sent while your week is used up. It uses your plan's allowance, much more than a ping.
- Pause stops pings, not messages. Each message has its own switch.

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
- **Each ping is as small as it gets.** The smallest model (Haiku) with thinking off, no tools, none of your hooks, plugins or CLAUDE.md, and no saved transcript. The message is "hi" and the reply is one word: 350 tokens of your plan's usage. History shows the count for each one.
- **A ping never costs money.** It counts toward your plan's usage like any message, never API billing: API keys are removed before every ping, and if Claude Code finds one in its own settings anyway, Tuloy sends nothing until it's gone. If you've switched on Claude's paid extra usage, Tuloy sends no ping while a limit is used up, because that one would be paid for.
- **Usage is checked every 5 minutes, free.** Tuloy runs Claude Code's own `/usage`, which looks your usage up without sending Claude a message: 0 tokens, and no window starts. It sees your use from anywhere (the desktop app, claude.ai, your phone), keeps the ring and the week current, and spots a window you started yourself so the scheduled ping waits for it. If a check ever cost anything, Tuloy would stop checking and tell you. You can switch it off in Preferences.
- **Missed pings still go out.** Tuloy checks the clock every 30 seconds instead of setting one long timer. If your Mac was asleep, off or offline when a ping was due, it sends it as soon as it can, as long as that can still help (within 5 hours). History marks it late and says why.
- **It waits for an open window.** A ping only starts a window if none is open. If you were up late and a window is still running at ping time, Tuloy waits for it to end, then pings. Pinging by hand in the meantime doesn't cancel that.
- **One Tuloy at a time.** Open a second copy and it brings the first one forward and quits, so two can never ping on the same schedule.
- **Failed pings retry, when retrying can help.** After 1 minute, then 2, 5, 15 and 30. If it's something only you can fix, like signing in, Tuloy tries once, tells you, and then waits: it looks in with a free check (no message sent) and pings again as soon as you've fixed it.
- **It checks before it matters.** An hour before each scheduled ping, the same free check runs. If Claude Code has been signed out, you hear about it while there's still time.
- **It warns you when you're nearly out.** At 80% and 95% of a window, and of your week. Only on a current reading, and once each.
- **It says why.** Every "next ping" comes with its reason, and if today's fresh window isn't when you asked, Tuloy says why not. Claude starts each window on a 10-minute mark, so a fresh time like 10:07 comes out as 10:00, and Tuloy tells you so afterwards.
- **It rests when your week is used up**, even across a restart, and carries on as soon as the week has room again.

## Live usage (optional)

Usage already updates every 5 minutes. Live usage adds an update the moment you use Claude Code in Terminal, in between.

**It only updates while you use Claude Code in Terminal.** It comes from Claude Code's status line, which the Claude desktop app and claude.ai don't run. Most people can skip it.

To turn it on, open **Connection**, find step 4 and choose **Connect…**. It shows what will change and asks before doing it:

- Adds a small script, `~/.tuloy/statusline.sh`, and points the `statusLine` setting in `~/.claude/settings.json` at it. Nothing else in that file changes, and a copy of the old file is kept at `~/.tuloy/settings-backup.json`, readable only by you and deleted after a week.
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

A closed or sleeping Mac can't be relied on to ping. macOS may wake it briefly now and then, and Tuloy will ping in one of those moments if it's long enough, but that can be half an hour late or not at all. If your Mac is usually asleep at ping time, let your phone send the early ping, and let Tuloy do the rest. These steps are in Help too.

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
| Claude Code needs its own sign-in | Choose **Sign In…** in Connection, or run `claude auth login` in Terminal. Being signed in to the desktop app isn't enough |
| The ping couldn't use your Claude login | Claude Code says you're signed in, but the ping wasn't allowed to use that login. Sign in again, then send a test ping. If it keeps happening after a Claude Code update, see the note below |
| Claude Code isn't using your Claude plan | It's set up with an API key. Sign in with your Claude account instead |
| Couldn't reach Claude | Check your internet. Tuloy retries on its own |
| Weekly limit used up | Nothing to do. Tuloy rests until it resets |
| This window is used up | You've reached this window's limit. Tuloy shows when it resets |

**History** lists every ping of the last month: when it went out, what came back, how many tokens it used, and why it was late if it was. A failure that repeats shows as one line with a count.

**A Claude Code change to watch for.** Claude Code's docs say a "bare" mode will one day become the default for `claude -p`, and bare mode doesn't use your Claude login. If that ships, pings will fail with "The ping couldn't use your Claude login" until Tuloy is updated to ask for the normal mode. Tuloy already refuses bare mode where it can, and tells this case apart from simply being signed out.

## Files

| File | What it does |
|---|---|
| `Tuloy/TuloyApp.swift` | Entry point: the menu bar item, the four windows, the menus, and what opens at start |
| `Tuloy/AppModel.swift` | The wiring: the 30-second loop, waking and reconnecting, the windows and the Dock icon, live usage, what macOS allows |
| **`Tuloy/Core/`** | **The thinking. No clock, no network, all tested** |
| `Engine.swift` | The brain: what to do with a ping's result and a usage check's, when to retry, when to wait for you or rest, what to keep in History, what to tell you |
| `Sockets.swift` | The four things the Engine plugs into (clock, Claude Code, storage, notifications), so tests can swap in pretend ones |
| `Schedule.swift` | Turns "fresh at 11:00" into "ping at 6:00", plus keep going |
| `Planner.swift` | Decides what to do right now (wait, ping, or skip), and forecasts the next ping with its reason |
| `Usage.swift` | A reading of one of your limits, a ping, and a day's count |
| `Messages.swift` | A scheduled message: what, when, where, how; and one time it went out |
| `Format.swift` | Time and countdown text |
| **`Tuloy/Claude/`** | **Talking to Claude Code** |
| `ClaudeCLI.swift` | Finds `claude`, sends the ping and your messages, checks your usage and your sign-in |
| `PingOutput.swift` | Reads the usage report a ping prints |
| `UsageOutput.swift` | Reads what the free usage check prints |
| `MessageOutput.swift` | Reads what Claude Code prints after one of your messages |
| `StatusLineFile.swift` | Reads the live usage file |
| `StatusLineLink.swift` | Connect and Disconnect for live usage |
| `Shell.swift` | Runs a command with a time limit |
| **`Tuloy/UI/`** | **What you see** |
| `Windows.swift` | The list of windows and screens, and the shared pieces: buttons, cards, the big ring |
| `MainWindow.swift` | The Tuloy window, its sidebar, and Home |
| `HistoryScreen.swift` | History: the squares for each day, and every ping of the month |
| `MessagesScreen.swift` | Messages: your scheduled messages, the editor, and the replies |
| `ConnectionScreen.swift` | The Connection steps, the test ping, and the step-by-step guide |
| `SettingsScreens.swift` | Schedule and Preferences |
| `HelpScreen.swift` | Help |
| `SetupWindow.swift` | The welcome |
| `MiniWindow.swift` | The mini window: the panel, floating |
| `MenuBarLabel.swift` | The menu bar icon's four looks |
| `Panel.swift` | The panel (under the menu bar icon, in the mini window, on Home) and today's timeline |
| `Ring.swift` | The small ring in the menu bar |
| `Glyph.swift` | Tuloy's own symbol, in its four states (provisional) |
| `DayTimeline.swift` | The picture of your day |
| **`Tuloy/System/`** | |
| `System.swift` | Notifications and launch at login, and whether macOS is blocking them |
| `Demo.swift` | Demo mode |
| **Everything else** | |
| `HOW_IT_WORKS.md` | Everything Tuloy stores and does, step by step |
| `LICENSE` | The MIT licence: anyone may use, change and share the code |
| `Tests/` | Tests for the schedule, the planner, everything read from or written for Claude Code, and every screen |
| `Package.swift`, `Makefile`, `scripts/`, `Support/` | Building the app, and its icon (`Support/AppIcon.icns`, drawn by `scripts/make-icon.swift`) |

## Licence

MIT. See [LICENSE](LICENSE). Tuloy is an independent project and is not affiliated with Anthropic.

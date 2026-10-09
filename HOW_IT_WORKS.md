# How Tuloy works

Everything Tuloy stores and everything it does, step by step. The [README](README.md) is the user guide; this is the map of the inside.

**Contents**

1. [The idea](#1-the-idea)
2. [The parts](#2-the-parts)
3. [What Tuloy stores](#3-what-tuloy-stores)
4. [What Tuloy reads from Claude Code](#4-what-tuloy-reads-from-claude-code)
5. [What Tuloy does, step by step](#5-what-tuloy-does-step-by-step)
6. [What a ping costs](#6-what-a-ping-costs)
7. [What Tuloy never does](#7-what-tuloy-never-does)
8. [Not confirmed yet](#8-not-confirmed-yet)
9. [Words used here](#9-words-used-here)

---

## 1. The idea

Claude's usage limit runs in **5-hour windows**. A window starts with your first message and resets 5 hours later. You can't choose when it resets, only when it starts.

So Tuloy starts one early. Want a fresh window at 11:00 AM? Tuloy sends a tiny message (a **ping**) at 6:00 AM:

```
 12 AM          6 AM          11 AM          4 PM
   |─────────────|──────────────|──────────────|────
                 ▲              ▲
                 ping           the window the ping opened resets:
                 opens a        you get a FRESH window here,
                 window         in the middle of your work
```

Without the ping, a window that started when you sat down at 9:00 AM wouldn't reset until 2:00 PM.

---

## 2. The parts

```
  every 30 seconds
        │
        ▼
   ┌──────────┐  "ping now?"  ┌───────────┐
   │ AppModel │──────────────▶│  Planner  │   decides: wait, ping or skip
   │ the brain│◀──────────────│ (no clock,│
   └──────────┘   decision    │ no network)│
        │                     └───────────┘
        │ ping
        ▼
   ┌──────────┐   runs    ┌──────────────┐   talks to   ┌────────┐
   │ ClaudeCLI│──────────▶│ claude -p hi │─────────────▶│ Claude │
   └──────────┘           └──────────────┘              └────────┘
        │                        │ prints one JSON event per line
        │                        ▼
        │                 ┌────────────┐
        └────────────────▶│ PingOutput │  reads: when the window resets,
           the report     └────────────┘  how much is used, what it cost
                                 │
                                 ▼
                       menu bar · menu · notification
```

| Folder | What's in it |
|---|---|
| `Tuloy/Core/` | The thinking: `Schedule` (when to ping), `Planner` (what to do now, and what happens next), `Engine` (what to do with a ping's result), the data shapes. No clock and no network, so every case has a test. |
| `Tuloy/Claude/` | Everything that touches Claude Code: running it, reading what it prints, the live usage file. |
| `Tuloy/UI/` | The menu bar icon and its menu, and the four windows: the main one (Home, Schedule, Connection, Preferences, Help), the welcome, the mini window and the step-by-step guide. |
| `Tuloy/System/` | Notifications, launch at login, demo mode. |
| `Tuloy/AppModel.swift` | The wiring: runs the loop, listens for waking and reconnecting, opens the windows. It is the Engine plus everything specific to this Mac. |

**The Engine and its four sockets.** The Engine never looks at the Mac's clock, runs `claude`, saves a file or posts a notification by itself. It asks four "sockets" to (`Sockets.swift`): a clock, Claude Code, storage, and notifications. The app plugs in the real ones. Tests plug in pretend ones, so a whole afternoon of pings can be played out in a second, and demo mode plugs in a pretend Claude Code so nothing real is ever sent.

**Dependencies:** none beyond macOS and Claude Code. No Swift packages, no server, no account. Building needs Xcode 16 or later.

---

## 3. What Tuloy stores

### 3.1 Your settings

Saved in macOS's preferences for the app (`com.edrichsilva.tuloy`) the moment you change them.

| Key | Type | Starts as | Meaning |
|---|---|---|---|
| `freshMinutes` | number | `660` | When you want a fresh window, in minutes after midnight. 660 = 11:00 AM. |
| `weekdays` | list of numbers | `[1,2,3,4,5,6,7]` | The days you want one. 1 = Sunday … 7 = Saturday. |
| `keepGoing` | yes/no | no | After your fresh window, start a new one each time one ends. |
| `untilMinutes` | number | `1080` | When keep going stops, in minutes after midnight. 1080 = 6:00 PM. At or before `freshMinutes` means "after midnight". |
| `displayMode` | text | `classic` | `classic`, `usage`, `timer` or `ultra`. |
| `notify` | yes/no | yes | Notify when a fresh window opens. |
| `warnNearlyOut` | yes/no | yes | Notify at 80% and 95% of a window. |
| `warnWeek` | yes/no | yes | Notify at 80% and 95% of your week. |
| `openAtLaunch` | yes/no | yes | Show the main window when you open Tuloy. |
| `miniAtLaunch` | yes/no | no | Show the mini window whenever Tuloy starts. |
| `isPaused` | yes/no | no | Paused from the menu. |

### 3.2 What Tuloy remembers between launches

Saved in the same place, so quitting or restarting loses nothing.

| Key | Type | Meaning |
|---|---|---|
| `nextPingAt` | date | The next scheduled ping. Because it's saved, a ping missed while the Mac was off is noticed at the next launch. |
| `window` | a reading (3.4) | Your current 5-hour window, as last reported. |
| `week` | a reading (3.4) | Your weekly limit, as last reported. |
| `history` | list of pings (3.4) | The last 20 pings, newest first. |
| `windows` | list of windows | Every window seen in the last two weeks: when it began and ended, who opened it (Tuloy, or you), and the highest usage seen. Feeds the "Today" bar on Home. |
| `pingMemory` | a small record | Which ping command last worked (small or plain) and on which Claude Code version. |
| `planNote` | a sentence | Why today's fresh window isn't when you asked, if it isn't. |
| `announced` | a small table | The "nearly out" levels already announced for the current window and week, so a restart can't repeat them. |
| `claudeFoundAt` | text | Where the `claude` command was last found, so the search isn't repeated. |
| `hasLaunched` | yes/no | So the welcome window opens by itself only the first time. |

### 3.3 What Tuloy keeps only while it runs

| Name | Meaning |
|---|---|
| `problem` | Why the last ping failed. Cleared by the next ping that gets through. |
| `waitingOn` | The problem only you can fix, while pings wait on it (5.5). |
| `problemNote` | An extra line, such as "This started after Claude Code updated from 2.1.288 to 2.2.0." |
| `notice` | The one line saying what just happened. Gone after 8 seconds. |
| `setup` | Whether Claude Code is installed and signed in (from `claude auth status`). |
| `claudePath` | Where the `claude` command was found. |
| `windowRequests`, `mainTab` | Windows waiting to be opened, and which screen the main window is showing. |
| `weekLimitUntil` | Set while your weekly limit is used up. |
| `holdUntil`, `failures` | "Don't ping before this" and how many pings have failed in a row. |
| `liveUsageAt` | When the live usage file last changed. |
| `isOnline` | Whether the Mac has a connection. |
| `now` | The time, refreshed every tick so countdowns move. |

### 3.4 The shapes

**A reading** (`UsageReading`): what Tuloy knows about one limit.

| Field | Meaning |
|---|---|
| `percent` | How much is used, 0 to 100. Empty if Claude Code didn't say. |
| `resetsAt` | When it resets. |
| `asOf` | When Tuloy learned this. A newer reading replaces an older one. |
| `isEstimate` | Yes when Claude Code didn't report a reset time and Tuloy assumed "5 hours from the ping". The menu then says "about". |

**A ping** (`PingRecord`): one line of Recent Pings.

| Field | Meaning |
|---|---|
| `date` | When it was sent. |
| `kind` | `scheduled`, `keepGoing`, or `manual` (you chose Ping Now). |
| `ok` | Whether it got through. |
| `resetsAt` | When the window resets, if it got through. |
| `note` | What went wrong, if it didn't. |
| `tokens` | What it cost, as counted by Claude Code. |

**A report** (`PingReport`): what one ping told Tuloy. It has a `window` reading, a `week` reading, `blockedBy` (`window` or `week` when a limit turned the ping away), and `tokens`. Any of them can be empty.

### 3.5 Files on disk

| File | Who writes it | What it is |
|---|---|---|
| `~/.tuloy/` | Tuloy | Tuloy's folder. Pings run from here so they never pick up a project's settings. |
| `~/.tuloy/statusline.json` | Claude Code, through the script | The latest live usage (4.4). Only when live usage is connected. |
| `~/.tuloy/statusline.sh` | Tuloy, on Connect | The script Claude Code runs as its status line. |
| `~/.tuloy/statusline-original.sh` | Tuloy, on Connect | The status line command you had before, so it keeps running. Absent if you had none. |
| `~/.tuloy/settings-backup.json` | Tuloy, on Connect and Disconnect | A copy of Claude Code's settings file from just before Tuloy changed it. |
| `~/.tuloy/Sign in to Claude Code.command` | Tuloy, when you choose Sign In… | A short script that Terminal runs: it starts Claude Code's own sign-in (5.13). |
| `~/.claude/settings.json` | You and Claude Code | Claude Code's settings. Tuloy changes only the `statusLine` entry, and only when you choose Connect or Disconnect. |

---

## 4. What Tuloy reads from Claude Code

Tuloy talks to Claude Code in three ways. Each has its own format.

### 4.1 A ping's output

A ping prints one JSON event per line. Tuloy uses two kinds and ignores the rest.

**`rate_limit_event`**: Claude Code's report on a limit.

```json
{"type":"rate_limit_event","rate_limit_info":{"status":"allowed","rateLimitType":"five_hour","resetsAt":1790018000,"utilization":0.87}}
```

| Field | How Tuloy uses it |
|---|---|
| `status` | `allowed`, `allowed_warning` or `rejected`. `rejected` means that limit is used up. |
| `rateLimitType` | `five_hour` is your window. Anything starting `seven_day` is your week. Others are ignored. If it's missing, Tuloy tells them apart by how far away the reset is. |
| `resetsAt` | When that limit resets, as Unix time (seconds or milliseconds both work). |
| `utilization` | How much is used, as a fraction (0.87 = 87%). Often missing until you're getting close to the limit. |
| `unifiedWindows` | If present, a list of every limit at once. Tuloy reads `five_hour` and `seven_day` from it. |

Tuloy double-checks every report: a "window" that resets more than 5 hours 10 minutes from now, or has already reset, is ignored.

Claude Code's published reference lists only `status`, `resetsAt` and `utilization`. Tuloy reads `rateLimitType` and `unifiedWindows` when they're there and manages without them when they aren't.

**`result`**: the last line.

```json
{"type":"result","subtype":"success","is_error":false,"result":"ok","usage":{"input_tokens":21,"output_tokens":4}}
```

| Field | How Tuloy uses it |
|---|---|
| `is_error` | Whether the reply failed. |
| `result`, `errors` | The error text, when it failed. Tuloy sorts it into "signed out", "offline", "too old" or "something else". |
| `usage`, `modelUsage` | Token counts, added up into the ping's `tokens`. |

**Did the ping get through?** In this order:

1. A window was reported → **yes**, even if the reply failed. (At your limit the reply fails, but the report proves a window is open and says when it resets.)
2. Your week is used up → **reported, but no window can start**. Tuloy rests until the week resets.
3. Exit code 0 and no error → **yes**, with no report. Tuloy assumes the window resets 5 hours from now.
4. Anything else → **no**, with the reason.

### 4.2 The sign-in check

`claude auth status` prints one JSON object and sends no message.

```json
{"loggedIn":true,"authMethod":"claude.ai","subscriptionType":"pro"}
```

| What it says | What Tuloy shows |
|---|---|
| `loggedIn` is false, or `authMethod` is `none` | Claude Code is signed out |
| `authMethod` is `api_key`, `api_key_helper` or `third_party` | Claude Code isn't using your Claude plan |
| Anything else that's signed in | Ready, with your plan's name |
| Not JSON (a very old Claude Code) | Couldn't check. Tuloy finds out at the next ping |

Claude Code keeps this sign-in to itself. Being signed in to the Claude desktop app or claude.ai does not sign in the `claude` command, so a new user is usually "signed out" here until they run `claude auth login` once.

When the check comes back "ready" after having said otherwise, Tuloy drops any "signed out" or "can't find Claude Code" problem it was showing and lifts the hold, so pings can try again straight away.

### 4.3 The `claude` command itself

Tuloy looks for it in `~/.local/bin`, `~/.claude/local`, `/opt/homebrew/bin` and `/usr/local/bin`, then asks your login shell (`command -v claude`).

### 4.4 The live usage file

When live usage is connected, Claude Code hands its status line data to Tuloy's script after each reply. Tuloy reads one part of it:

```json
{"rate_limits":{"five_hour":{"used_percentage":23.5,"resets_at":1738425600},"seven_day":{"used_percentage":41.2,"resets_at":1738857600}}}
```

`used_percentage` is 0 to 100 and `resets_at` is Unix seconds. Claude Code only includes `rate_limits` on a Pro or Max plan, after the first reply of a session.

---

## 5. What Tuloy does, step by step

### 5.1 When it starts

1. Makes `~/.tuloy` if it isn't there.
2. Tells macOS not to nap the app, so its clock stays on time. (The Mac itself can still sleep.)
3. Asks permission to send notifications, if they're on.
4. If no `nextPingAt` is saved, works one out (5.3).
5. Starts the 30-second loop (5.2).
6. Starts listening for three things: the Mac waking, the internet coming back, and the time zone changing.
7. Checks whether live usage is connected.
8. Runs the sign-in check (4.2). If Claude Code isn't ready, the menu bar shows ⚠ right away.
9. Decides which windows to show (5.12): the welcome the first time; after that the main window, unless Tuloy was started by "launch at login"; and the mini window if you asked for it.

### 5.2 The loop

Every 30 seconds, and also 5 seconds after the Mac wakes and whenever the internet comes back:

1. Update `now`.
2. If the live usage file changed, read it (5.7).
3. Ask the Planner what to do (5.4).
4. **Wait** → nothing. **Skip** → work out the next scheduled ping. **Ping** → send one (5.5), but only if online; otherwise try again next time round.

Checking a clock every 30 seconds, instead of setting one timer for 6:00 AM, is what makes sleep harmless: when the Mac wakes, the next check simply sees that a ping is overdue.

### 5.3 Working out the next scheduled ping

`Schedule.nextPing(after: now)`:

1. Look at today, then each of the next 8 days.
2. Skip days that are switched off.
3. Take that day's fresh time and go back 5 hours, then forward 15 seconds. (The 15 seconds mean a slightly fast clock can't send the ping just before the time you meant.)
4. The first result that's still in the future is `nextPingAt`.

A fresh time before 5:00 AM means the ping goes out the evening before.

This runs when you change the schedule, resume from pause, after a scheduled ping gets through, and after one is skipped.

### 5.4 The decision

`Planner.decide(at: now)` answers one question: wait, ping, or skip? It checks these in order and stops at the first that applies.

| # | If… | Then |
|---|---|---|
| 1 | Tuloy is paused | **wait** |
| 2 | The scheduled ping is due, but more than 5 hours overdue | **skip**. Your fresh time has passed, so a late ping can't help. |
| 3 | The scheduled ping is due | a `scheduled` ping is wanted → go to 6 |
| 4 | Keep going is on and it's within keep-going hours (5.6) | a `keepGoing` ping is wanted → go to 6 |
| 5 | Otherwise | **wait** |
| 6 | Pings are waiting on you (5.5) | **wait**. Retrying can't fix it. |
| 6b | A window Tuloy knows about is open, or reset less than a minute ago | **wait**. A ping now would start nothing. |
| 7 | Tuloy is on hold after a failed ping (5.5) | **wait** |
| 8 | Otherwise | **ping** |

Some examples, with a fresh window at 11:00 AM (ping due 6:00:15):

| Situation | Decision |
|---|---|
| 5:59 AM | wait |
| 6:00:15 AM | ping (scheduled) |
| Mac opened at 8:00 AM, ping not sent yet | ping (scheduled). Fresh window at 1:00 PM instead of 11:00: late, but still earlier than doing nothing. |
| Mac opened at 11:30 AM, ping not sent yet | skip |
| 6:00 AM, but you worked late and a window is open until 8:00 | wait until 8:01, then ping |
| 11:01 AM, the morning window just reset, keep going off | wait until tomorrow |
| 11:01 AM, the morning window just reset, keep going on | ping (keep going) |

### 5.5 Sending a ping

1. **Find `claude`** (4.3). Not found → "Can't find Claude Code".
2. **Set up its surroundings.** Tuloy passes on its own environment with a few changes:
   - Removed: `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_BASE_URL`, `CLAUDE_CODE_USE_BEDROCK`, `CLAUDE_CODE_USE_VERTEX`, so the ping can only use your Claude plan. Also `CLAUDE_CODE_SIMPLE`, which would switch on "bare mode" and skip your login.
   - Added: `MAX_THINKING_TOKENS=0` (no thinking) and `CLAUDE_CODE_SIMPLE_SYSTEM_PROMPT=1` (shorter built-in instructions, for the fallback in step 4).
   - `PATH` gets `claude`'s own folder and the Homebrew folders, because apps don't get your shell's `PATH`.
3. **Run the ping** from `~/.tuloy`, with a 90-second limit:

   ```sh
   claude -p hi \
     --system-prompt "Reply with only the word ok." \
     --model haiku --tools "" --strict-mcp-config \
     --safe-mode --no-session-persistence \
     --output-format stream-json --verbose
   ```

   | Part | Why |
   |---|---|
   | `-p hi` | Send one message and exit. |
   | `--system-prompt …` | Replaces Claude Code's long built-in instructions with one line that keeps the reply to one word. |
   | `--model haiku` | The smallest model. |
   | `--tools ""`, `--strict-mcp-config` | No tools and no MCP servers, so nothing extra is sent. |
   | `--safe-mode` | Skips your hooks, plugins, skills and CLAUDE.md. Sign-in still works normally. |
   | `--no-session-persistence` | Doesn't save a transcript. |
   | `--output-format stream-json --verbose` | Prints the events in 4.1, including the usage report. |

4. **If that fails**, the plain version, which works on any Claude Code, is tried once, but only when the newer flags could be to blame: an "unknown option" error always; any other unexplained error only if the small ping has never worked here, or Claude Code's version has changed since it did. Tuloy remembers which command worked and on which version (`pingMemory`), so a failure never re-runs a command already known to be fine.

   ```sh
   claude -p "Reply with only the word ok." --model haiku --tools "" --strict-mcp-config --output-format stream-json --verbose
   ```

5. **If it's a sign-in error**, run the sign-in check (4.2). Signed out → "Claude Code needs its own sign-in". Signed in → "The ping couldn't use your Claude login", which means the login has gone stale or Claude Code has changed how `claude -p` signs in (section 8).
6. **Read the output** (4.1), including Claude Code's version from its first line.

**Then, if the ping got through:**

1. Clear any problem. Mark Claude Code as ready. Remember the command and version that worked.
2. Save the week reading, if there was one.
3. Save the window reading. If there wasn't one and no window is known to be open, assume one that resets 5 hours from now, marked as an estimate.
4. Clear the hold and the failure count.
5. Add it to Recent pings, and to the list of windows: "opened by Tuloy", or "already open" if Tuloy knew of it or it began more than about 20 minutes before the ping.
6. If the fresh window isn't within 10 minutes of the one you asked for, write down why (5.17).
7. If a scheduled ping was due, it's now done: work out the next one (5.3). This is also true of a Ping Now that happens to land while one was waiting.
8. Say what happened (5.18): "Pinged. Fresh window at 8:00 PM." or "Pinged. Your window was already open; it resets at 8:00 PM."

**If your week is used up:** save the week reading, rest until it resets, and add a "Weekly limit used up" line to Recent pings.

**If the ping failed**, what happens next depends on whether trying again could help:

| What happened | Tries again by itself? | Tries again when |
|---|---|---|
| Claude Code not found | no | the free check finds it |
| Needs its own sign-in | no | the free check says signed in |
| API key, not your plan | no | the free check says it's your plan |
| Signed in, but the ping was refused | once, at the next scheduled time | a ping works |
| Claude Code too old | no | its version changes |
| Offline | waits for the network | it comes back |
| Took too long | yes: after 1, 2, 5, 15, then 30 minutes | |
| Anything else | yes, 5 tries like that, then once an hour | |

For the "no" rows Tuloy is **waiting on you**. It sends one notification, shows the problem, and then looks in with the free sign-in check (no message is sent): every 5 minutes for the first hour, then every 30. It also checks at once when the sign-in script finishes (5.13), and when a Tuloy window shows the Connection steps. When the check passes, the problem is cleared and the waiting ping goes out at the next tick. A check that says "not ready" before any ping has failed also puts Tuloy in this state, so no ping is wasted finding out. Ping Now always works, whatever the state.

If Claude Code's version is different from the last one a ping worked on, the problem gains a line: "This started after Claude Code updated from 2.1.288 to 2.2.0."

### 5.6 Keep going

With keep going on, Tuloy also pings whenever all of these are true:

1. It's between your fresh time and your stop time, on a day that's switched on. (A stop time at or before the fresh time means "after midnight".)
2. A window started now would be over before the next scheduled ping. This stops keep going from pushing back tomorrow's fresh window.
3. No window is open (rule 6 in 5.4).

So with a fresh window at 11:00 AM and keep going until 6:00 PM, the day runs: ping at 6:00 AM (scheduled), 11:01 AM and 4:01 PM (keep going). At 9:01 PM the stop time has passed, so nothing.

Keep going uses the real reset time from each ping, not a fixed timetable, so it stays right even when a window started later than planned.

### 5.7 Live usage

**Connect** (Connection, step 4: Connect…, which shows what will change and waits for you to confirm):

1. Read `~/.claude/settings.json`. If it isn't valid JSON, stop and change nothing.
2. If you already have a status line, save its command to `~/.tuloy/statusline-original.sh`.
3. Write `~/.tuloy/statusline.sh`.
4. Copy the settings file to `~/.tuloy/settings-backup.json`.
5. Set `statusLine` to `{"type": "command", "command": "~/.tuloy/statusline.sh"}`, keeping any other options you had on it. Tuloy edits the file as text, so every other line stays exactly as it was. If the result wouldn't be valid JSON, stop and change nothing.

**The script**, each time Claude Code runs it:

1. Saves what Claude Code sent to `~/.tuloy/statusline.json`.
2. Runs your original status line with the same data, so it shows as before.

Claude Code only runs a status line in Terminal. The Claude desktop app and claude.ai never run the script, so for people who use Claude that way live usage stays empty and usage updates with each ping instead.

**Reading**, on each tick: if the file changed since last time, read it (4.4). A reading replaces what Tuloy has only if it's newer and its reset time is still ahead.

**Disconnect:** put your original command back (or remove `statusLine` if you had none), then delete the script, the saved original and the usage file.

### 5.8 Notifications

- **Fresh window.** Whenever the window's reset time changes, Tuloy schedules one notification for that moment, replacing the old one. Off if you turn notifications off.
- **A problem you need to fix.** Sent once when it first appears: Claude Code missing, signed out, not on your plan, or too old.

### 5.9 The menu bar icon

The first that applies:

1. ⚠ if a ping failed or Claude Code isn't ready.
2. Paused, if you paused it.
3. Resting, if your week is used up.
4. Otherwise your chosen look: ✓, the usage ring, the countdown, or both.

"Fresh window at…" is the open window's reset time. With no window open, it's the next scheduled ping plus 5 hours.

### 5.10 Pause, resume, Ping Now

- **Pause** stops all pings. **Resume** plans the next scheduled ping from now, so pings missed while paused aren't sent late.
- **Ping Now** sends a ping whatever the Planner thinks, and handles the result the same way (5.5).
- **Changing the schedule** plans again from now and clears any hold.
- **Changing time zone** plans again, unless a ping is already due (that one goes out first).

### 5.11 Demo mode

`make demo` starts Tuloy with `--demo`. In demo mode Tuloy never runs `claude`, never reads or writes your real settings (it uses a separate set, emptied at every start), sends no notifications, and won't touch Claude Code's settings. The loop only moves the clock. Ping Now waits a second and pretends, and so does Sign In. The **Demo Scene** submenu fills in made-up data for each state. It opens the main and mini windows; add `--setup` to see the welcome instead.

Demo mode is also on whenever Tuloy's code runs inside another program, which is how the tests run it. A test can never send a ping or touch your settings, and one test exists only to prove that.

### 5.12 The windows

Tuloy has one menu bar item, a panel under it, and four windows. Closing a window never quits Tuloy.

| Window | Opens | What's in it |
|---|---|---|
| **Tuloy** (main) | When you open the app; "Open Tuloy…" in the menu | A sidebar with Home, Schedule, Connection, Preferences and Help. |
| **Welcome** | The first time; "Show the Welcome Again" in Help | Four pages: the idea, connect, pick a time, where to find Tuloy. Finishing opens the main window. |
| **The panel** | A click on the menu bar icon | The ring, your fresh time, how old the usage number is, the week, Ping Now, Pause, the next ping and its reason, and what just happened. Its (…) button has Settings, Connection, Help, Recent Pings and Quit. Escape closes it. |
| **Mini** | From Home or the panel; at start if you chose that | The same panel, floating above other windows, on every desktop. |
| **Guide** | From Connection or Help | Every connecting step and command. Also floats, so it stays visible beside Terminal. |

How a window gets opened: on macOS only a view can open a window, and the menu bar item is the one view that's always there. So anything that wants a window (the menu, a button in another window, starting up) adds it to `windowRequests`, and the menu bar item opens whatever is in that list and brings Tuloy to the front.

What opens at start:

1. First time ever → the welcome.
2. Otherwise, if "Show this window when I open Tuloy" is on **and** macOS didn't start Tuloy as a login item → the main window.
3. If "Show the mini window when Tuloy starts" is on → the mini window too.
4. Opening the app again while it's running → the main window.

Tuloy tells macOS not to restore old windows, so these rules are the only thing that decides.

### 5.13 Signing in

Tuloy can't sign in for you and never sees your login. **Sign In…** in Connection does this:

1. Writes `~/.tuloy/Sign in to Claude Code.command`, a small script that runs `claude auth login` and then leaves an empty marker file, `~/.tuloy/signed-in`.
2. Opens that file, which makes Terminal run it.
3. Claude Code opens your browser. You sign in there and approve.
4. macOS tells Tuloy the moment its folder changes. Tuloy sees the marker, deletes it and the script, runs the sign-in check (4.2) once, comes to the front on Connection, and says "Signed in. Send a test ping to finish."
5. **Send Test Ping** then confirms the whole thing with a real ping. (Tuloy doesn't send it by itself.)

If you sign in by typing the command yourself, there's no marker; the repeated free check from 5.5 notices within 5 minutes.

### 5.14 What happens next: the forecast

`Planner.forecast` answers "when is the next ping, and why then?" It doesn't have its own rules. It asks `decide` (5.4) about each moment something could change (now, the scheduled time, when the open window ends, when a hold lifts, when keep going starts), in order, and reports the first moment that says "ping". So it can never promise a ping that wouldn't be sent; a test checks exactly that.

| Reason | What you read |
|---|---|
| Scheduled | "Next ping 5:00 AM tomorrow: 5 hours before your 10:00 AM fresh window" |
| Keep going | "Next ping 8:01 PM: when this window ends" |
| Waiting for a window | "Next ping 8:01 AM: a window is open until 8:00 AM" |
| Retrying | "Next try 6:08 AM: the last one didn't get through" |
| Waiting on you | "Next ping after you sign in" |
| Paused | "No pings while paused" |
| Resting | "Resting until Wed 8:00 PM: when your week resets" |

### 5.15 Nearly out

On every new reading, for the window and for the week: if usage has reached 80% or 95% and that level hasn't been announced for this window (or week), notify once. Not if the reading is over 10 minutes old, and for a window not if the reset is under 10 minutes away. Each has its own switch in Preferences.

### 5.16 The morning check

An hour before each scheduled ping, Tuloy runs the free sign-in check. If Claude Code isn't ready it notifies once ("Fix it before 5:00 AM to keep your 10:00 AM fresh window") and starts waiting on you. If all is well it says nothing. The check only confirms a login is stored; it can't promise the login still works.

### 5.17 The plan against the truth, and today's windows

When a scheduled ping's window isn't within 10 minutes of the fresh time you asked for, Tuloy keeps one sentence saying so, with the reason when it knows it: a window was already running; a window was still open so Tuloy waited; or the ping went out late. With no known reason it states the two times and nothing more. Home shows it under the status while that window is open.

Home's **Today** bar is drawn from the list of windows (3.2): filled blocks for windows so far, filled as high as usage got; a line for now; dashed outlines for what the forecast says is still to come.

### 5.18 What just happened

Every action sets one short line (`notice`): after a ping, a pause, a resume, a schedule change, a sign-in, connecting live usage. The panel shows it for 8 seconds, and VoiceOver reads it out.

---

## 6. What a ping costs

Each ping is one request to the smallest model with:

| Part | Size |
|---|---|
| Instructions | One line: "Reply with only the word ok." |
| Your message | "hi" |
| Thinking | Off |
| Tools, MCP servers, hooks, plugins, CLAUDE.md | None |
| The reply | "ok" |
| Whatever Claude Code itself adds to every request | Can't be removed from outside |

Why "hi" plus an instruction, and not just "hi" or "."? Words Claude writes count for more than words it reads, and a bare "hi" gets a whole greeting back. The instruction costs a few tokens and saves more.

Haiku has no effort levels, so there's no lower "setting" to choose. Turning thinking off is the one dial it has.

The real number is in **Recent Pings**: each line ends with the tokens Claude Code counted for that ping.

---

## 7. What Tuloy never does

- **Never reads your login or tokens.** The official `claude` command signs in by itself.
- **Never uses API billing.** API keys are removed from the ping's environment.
- **Never sends anything but the ping.** No analytics, no server of its own.
- **Never changes Claude Code's settings by itself.** Only when you choose Connect or Disconnect, only the `statusLine` entry, with a backup.
- **Never runs your hooks or plugins** during a ping.

---

## 8. Not confirmed yet

These are the places where Tuloy follows Claude Code's documentation or a careful guess, and a real ping on your Mac will settle it. Recent Pings is where to look.

| Question | Why it matters | What to look for |
|---|---|---|
| Does every ping come back with a window report? | **Yes, so far.** Six real pings on 6 October 2026 each reported an exact reset time and a percentage, for the window and the week. | |
| Do windows start on the hour? | **No: on 10-minute marks** (5 or 20 would also fit the six pings seen). One reset at 4:40 AM rules out the hour. The time picker still offers any minute until one deliberate ping at an odd minute settles the step. | Ping Now at a minute ending in 5 to 9, with no window open, and see where the reset lands. |
| How many tokens does a ping really use? | **350**, every time, on Claude Code 2.1.288. | The token count on each Recent pings line. |
| Can usage be checked without spending tokens? | Not yet known. Claude Code's `/usage` command may answer without asking the model. Until that's tested, usage only updates with a ping (or the status line), and the panel shows how old the number is. | Run `claude -p "/usage" --output-format json` in Terminal and look at the token counts. |
| Do the newer flags work with a subscription login? | If not, every ping quietly uses the plain fallback, which is larger. | A token count far bigger than a one-word exchange should need. |

**A Claude Code change to watch for.** Claude Code's documentation says "bare mode" will become the default for `claude -p` in a future release, and bare mode doesn't read your Claude login. There is no documented way to ask for the normal mode today. If that ships, pings will fail with "The ping couldn't use your Claude login", and `ClaudeCLI.swift` will need whatever new flag turns bare mode off. Tuloy already removes the environment variable that forces bare mode, and the error message tells this case apart from being signed out.

**When your Mac is asleep.** Tuloy can't wake it. The README shows how to have an iPhone send the early ping instead.

---

## 9. Words used here

| Word | Meaning |
|---|---|
| **Window** | Claude's 5-hour usage period. Starts with your first message. |
| **Fresh window** | The moment a window resets and your allowance is full again. |
| **Ping** | The tiny message Tuloy sends to start a window. |
| **Scheduled ping** | The one 5 hours before your fresh time. |
| **Keep going** | Pinging again each time a window ends. |
| **Week** | Claude's weekly limit, separate from the 5-hour one. |
| **Hold** | A pause before retrying after a failed ping. |
| **Resting** | Waiting for a used-up week to reset. |
| **Tick** | One pass of the 30-second loop. |

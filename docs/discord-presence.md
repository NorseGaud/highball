# Discord game activity on macOS

Discord sharing is off by default. Enable **Share game activity with Discord** in
Settings → Engine to share tracked Windows game sessions while Discord for Mac is
open. With sharing off, Highball performs no Discord process discovery, starts no
bridge helper, and makes no catalog request. Turning it off clears activity and
stops the helpers without stopping the games. Discord's Activity Privacy settings
also control whether friends see the activity.

* **Basic presence:** Highball uses its existing game sessions, their Steam IDs,
  titles, and executable markers. It resolves the game's Discord application ID from Discord's public
  detection catalog and publishes the game's name and elapsed time through local
  IPC. Steam IDs take precedence over titles; executable names are accepted only
  when unambiguous. No Highball application ID or Discord account token is required.
* **Rich Presence pass-through:** a small Windows helper creates
  `\\.\pipe\discord-ipc-0` through `discord-ipc-9` in each environment with a tracked game session. It
  connects to a native loopback listener authenticated with a per-run random token.
  Highball relays framed messages and replies to Discord's Unix socket, replacing
  Windows PIDs with Highball's macOS PID. Application IDs, assets, details, party
  data, join secrets, subscriptions, and events retain the original game's values.
  This forwards RPC; it does not implement an overlay or launch/join protocol handlers.

A game's own Rich Presence takes priority over basic presence. Basic presence
resumes after the richer connection ends. With multiple games running, Highball
keeps its selected basic activity until that game closes, then picks the newest
recognised game. Games absent from Discord's catalog cannot receive basic presence;
Rich Presence pass-through remains available for those games.

The catalog endpoint (`https://discord.com/api/v10/applications/detectable`) is
public but undocumented and can change. The last valid catalog is cached as
`discord-games.json` in Highball's data directory, refreshed weekly when a game and
Discord are running. Failed requests are retried at most hourly. Game titles,
process arguments, and account tokens are not sent in this request. An unavailable
catalog or Discord client never prevents a game launch.

The bridge starts on a background session worker after a game is running; game
launches and installers never wait for it. It reuses the existing session watcher's
process snapshot to read the game's Wine environment, without an additional process
scan. Discord availability is checked through macOS's running applications. Closing
Discord stops the bridges, and reopening it resumes sharing for active sessions.

Presence follows sessions started through Highball. Games started directly in a
launcher, or left running across a Highball restart, are not discovered separately.
Quitting Highball closes the IPC connections and ends its Windows helpers,
including when Windows programs are left running. The helpers run in `drive_c/windows`, so they count as plumbing for
Highball's idle-prefix and renderer restart rules. No service, LaunchAgent, engine
patch, or replacement Discord DLL is installed.

## Local build and validation

```sh
Scripts/make-app.sh debug 0.10.7-discord-local
open dist/Highball.app
```

The Windows helper is built from `spike/discord-bridge/main.c` with mingw-w64 and
bundled as `Contents/Resources/highball-discord-bridge.exe`. Release builds require
mingw-w64; debug builds warn when it is absent (basic presence still works).
Bare `swift run HighballApp` builds can find the helper under `spike/discord-bridge`
when run from the repository root; run its `build.sh` first.

```sh
swift test --filter DiscordPresenceTests
spike/discord-bridge/build.sh
x86_64-w64-mingw32-gcc -O2 -Wall -Wextra -Werror -static -s \
  -o spike/discord-bridge/probe.exe spike/discord-bridge/probe.c
HIGHBALL_DISCORD_SMOKE_ENGINE="/path/to/installed/Highball/engine" \
  swift test --filter DiscordPresenceTests/testWineNamedPipeSmokeWhenRequested
```

Tests use a fake Discord Unix socket and publish nothing to the user's Discord.
The optional Wine smoke boots a throwaway prefix with an installed engine, exercises
fragmented SDK frames on slots 0 and 9, checks native PID translation and bidirectional
replies, shuts down the bridge, verifies the helper exits, and repeats after restarting it.

To check activity locally, enable sharing in Highball's Settings → Engine and in
Discord, then start Geometry Dash through Highball. Check that Discord shows
**Playing Geometry Dash** and clears it after quitting the game. Repeat with a game
that has its own Rich Presence and restart Discord while playing. Turn Highball's
sharing switch off during play: activity should clear while the game keeps running.

Protocol reference: https://github.com/discord/discord-rpc/blob/master/documentation/hard-mode.md

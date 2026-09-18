# Denizens

A WoW: Forever addon that turns `/who` results into a sortable table, inside
Blizzard's own window. `/dz` opens a second window with a query builder, a
results filter, and a deep scan that gets past the server's 50-result cap.
Everything it sees is saved to a census.

## Install

Drop the `Denizens` folder into `Interface/AddOns` in your WoW: Forever
install and restart the client. There is nothing to configure.

## Usage

`/dz` toggles the window. `/dz z-"Elwynn Forest" 4-10` opens it and runs that
search. Click a column header to sort, click again to reverse. Click a row
to start a whisper.

`/dz` and `/denizens` are the same command.

- `/dz`: toggle the window
- `/dz <query>`: open the window and run that search, e.g.
  `/dz z-"Elwynn Forest" 4-10`
- `/dz deep [query]`: deep scan; defaults to whatever query is already on
  screen
- `/dz cancel` or `/dz stop`: stop a running scan and keep what it found so
  far
- `/dz census`: print what the census knows
- `/dz wipe`: clear the census
- `/dz debug`: show the recent internal log
- `/dz debug on`, `/dz debug off`: toggle live debug output to chat
- `/dz takeover off`: stop replacing Blizzard's `/who` pane; use the `/dz`
  window only
- `/dz takeover on`: put the table back in Blizzard's pane
- `/dz help`: list these commands in chat

`/reload` to apply either takeover setting.

## What it does

- **Sortable columns.** Name, level, class, race, zone, guild, over the live
  result set. Client-side, because this client has no `SortWho`.
- **A query builder.** Name, guild, zone, class, race, and a level range,
  building the exact `n-`/`g-`/`z-`/`r-`/`c-` token string `/who` expects,
  shown and editable before it's sent.
- **Deep scan.** A query that returns exactly 50 results has been cut off,
  not completed. Deep scan splits the level range in half and recurses on
  each half until every sub-query comes back under the cap, merging and
  dropping duplicates as replies arrive. It's cancellable mid-scan.
- **A census.** Every reply, including an ordinary `/who` you typed
  yourself, is folded into a saved census: an "active" count (seen in the
  last 7 days) and a "known ever" count (an upper bound, since a deleted or
  renamed character can't be told apart from one that hasn't logged in).

## The in-pane takeover, and the risk

By default Denizens installs into Blizzard's own `/who` window
(`LFGWhoListFrame`) rather than opening beside it, so you keep the native
frame, border, portrait and position. That frame lives under
`LFGParentFrame`, the Group Finder, and writing to a frame there can "taint"
it, which is what makes the client refuse to run a *protected* action (such
as queueing for a dungeon) from that path afterward.

This hasn't been observed in testing, but the mechanism is real. `/dz
takeover off` (then `/reload`) stops Denizens writing into Blizzard's `/who`
pane; you use the `/dz` window instead. It still closes Blizzard's `/who`
window when one of its own queries comes back, and that currently closes
the Group Finder too if you have it open.

## How it works

`/who` is server-throttled. Fire queries back to back and the extras are
silently dropped. So every query goes through a one-at-a-time queue, 2.5
seconds apart, and a query that gets no reply is retried with a longer gap,
up to 12 seconds. Replies are read through `C_FriendList.GetWhoInfo` and
merged into the result set by character name, so overlapping deep-scan
queries do not double-count. Every reply also goes into the census.

Two front ends share that result set. The takeover gives `LFGWhoListFrame`'s
`ScrollBox` a six-column element initializer and sortable headers instead of
Blizzard's card layout, by overriding its `UpdateWhoList` entry point rather
than hooking it, so the card layout never repaints over ours. The standalone
window (`/dz`, whether takeover is on or off) is built entirely from
`CreateFrame`, textures, and font strings, on the assumption that Forever
removed the old `WhoFrame` and there's no telling which other Classic UI
templates survived the port.

## Compatibility

Written against `## Interface: 16001` (the WoW: Forever public beta). Not
tested on any other client, or alongside other addons that also modify the
`/who` window or the Group Finder frames it lives under.

## Known limits

- The server caps every `/who` reply at 50; deep scan works around it by
  splitting on level, but a scan across a wide range can still take a while
  given the server's own throttle.
- A scan given no level range defaults to 1-60.
- The "Zone" column is the client's `area` field, which is the subzone
  ("Echo Ridge Mine"), not the parent zone; there's no separate zone field
  in what the client returns.
- Six columns are fit into whatever width the pane ends up at. A cell
  that's cut off shows the rest in a tooltip.
- The census only knows who it has seen. Offline characters are invisible,
  and a deleted, renamed or transferred character looks the same as one who
  has not logged in, so "known ever" is an upper bound. It keeps the 25,000
  most recently seen characters and drops the oldest past that.
- The in-pane table shows a plain count and no capped hint; the `/dz`
  window is where both of those live.

## Development notes

Five files:

- `Core.lua`: query building, the send queue, result capture, sorting, deep
  scan
- `Census.lua`: the saved census
- `UI.lua`: the `/dz` window and slash command
- `Takeover.lua`: installs into Blizzard's pane; `/dztakeover` retries it by
  hand
- `Probe.lua`: `/dzprobe` dumps the client's `/who` API and frame structure.
  Not needed in normal use. Paste its output into a bug report if a client
  patch breaks something.

`SavedVariables`: `DenizensDB`. `## Interface: 16001` in `Denizens.toc` is
duplicated as `ns.BUILT_FOR` in `Core.lua`, because `GetAddOnMetadata` can't
read the Interface field back out of the TOC, and the startup line compares
against it to warn when the addon is out of date for the client it's
running on. Releases are cut by tagging a version and pushing; a GitHub
Action packages the zip and uploads it to whichever sites have a token
configured -- see `RELEASING.md`.

Issues: github.com/KonigTX/Denizens/issues

## Licence

MIT.

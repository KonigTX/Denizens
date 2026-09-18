# Rollcall

A replacement for the `/who` results list in World of Warcraft: Forever. It
sorts, it filters, and it can see past the server's 50-result cap.

Forever's `/who` pane returns a flat list of cards. You cannot sort it, you
cannot narrow it by guild or location once it is on screen, and the full query
syntax is available only if you already know how to type it. Rollcall rebuilds
the contents of that pane — the real one, not a copy — as a sortable table, and
adds a query builder and a saved roster.

## Install

Drop the `Rollcall` folder into:

```
World of Warcraft/_classic_beta_/Interface/AddOns/
```

Restart the client. Nothing to configure; `/who` works differently the first
time you open it.

## What it does

**Sortable columns.** Name, level, class, race, zone and guild. Click a header
to sort, click again to reverse. Names are class-coloured. Forever's client has
no `SortWho`, so the sorting is done locally over the returned set.

**A query builder.** `/rc` opens a window with fields for name, guild and zone,
dropdowns for class and race, and a level range — and it shows you the exact
query string it is about to send, which you can edit by hand. The whole `/who`
syntax (`n-` `g-` `z-` `r-` `c-` and level ranges) without memorising it.

**Live filtering.** Narrow what is already on screen without spending another
query on the server.

**Deep scan.** The important one. A `/who` reply is capped at 50 results, so a
query that returns exactly 50 has been *truncated* — "50 People Found" is a
ceiling, not a population, and you are looking at an arbitrary subset. Deep scan
notices that, splits the level range in half, asks again for each half, and
recurses until every sub-query comes back under the cap. Results are merged and
de-duplicated. If a single level is still capped it says so rather than
pretending the list is complete.

**A saved roster.** Every reply — from a scan, or from a `/who` you typed
yourself — is folded into a per-realm roster that persists across sessions.
`/rc census` reports it.

## Commands

| | |
| --- | --- |
| `/rc` | open the window |
| `/rc <query>` | search, e.g. `/rc z-"Elwynn Forest" 4-10` |
| `/rc deep [query]` | deep scan; defaults to whatever query is on screen |
| `/rc cancel` | stop a running scan and keep what it found |
| `/rc census` | what the saved roster knows |
| `/rc wipe` | clear the roster for this realm |
| `/rc debug` | show the recent internal log |
| `/rc takeover off` | leave Blizzard's pane alone, use the window only |
| `/rcprobe` | print the client's `/who` API surface |
| `/rcprobe inspect` | dump a Blizzard frame's structure |

## What a census can and cannot tell you

Rollcall reports two numbers and they mean different things.

**Active** is how many characters have been seen in the last seven days. This
is the defensible figure.

**Known ever** only grows. Deletes, renames and transfers are unobservable over
`/who`: a character that no longer exists looks exactly like one that has not
logged in. Neither number is a server population — `/who` sees only players who
are online at the moment you ask, so a census is a sample of the online
population at the times you happened to scan. Treat *active* as real and *known*
as an upper bound.

The `zone` column is the value the client returns in `area`, which is the
**subzone** ("Echo Ridge Mine", not "Elwynn Forest"). There is no separate zone
field in the client's data.

## The in-pane takeover

By default Rollcall replaces the contents of Blizzard's own `/who` pane, so you
keep the native frame, border, portrait, position and ESC-to-close.

That means writing to a frame that lives under `LFGParentFrame`, the Group
Finder. Addon writes make a frame "tainted", and the game refuses to run
*protected* actions — such as queueing for a dungeon — from a tainted path, with
the message `Interface action failed because of an AddOn`. This has not been
observed in Rollcall, but the mechanism is real and worth stating plainly.

If you would rather not take the risk:

```
/rc takeover off
/reload
```

The standalone window has the same table, plus the query builder, and touches
none of Blizzard's frames.

## Compatibility

Written against Forever build `1.60.1` (`## Interface: 16001`). Forever carries
Classic-style version numbers over a Mainline UI codebase, so the modern
`C_FriendList` API is present while the old globals (`SendWho`, `WhoFrame`,
`SortWho`) are gone. The client is in beta and may change under this addon; if
something breaks, `/rcprobe` prints what the client is currently offering.

## Licence

MIT.

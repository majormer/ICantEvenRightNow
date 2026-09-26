# Troubleshooting

How to diagnose problems in game, and the failure patterns seen so far. Release and packaging problems are in `Release_Process.md`.

## Where errors go

| Source | Where | When it is written |
| --- | --- | --- |
| The addon's own log | `/icanteven errors` (clear with `/icanteven clearerrors`); stored in `ICantEvenRightNowDB.errorLog` | Kept in memory; saved on reload or logout |
| BugGrabber / BugSack | `WTF/Account/<ACCOUNT>/SavedVariables/!BugGrabber.lua` (entries have `message`, `stack`, `locals`, `session`) | Saved on reload or logout |

Errors from a session that hasn't reloaded or logged out yet are only in memory. If the game crashes, that session's errors are lost. When the UI is broken, `/reload` once and read `!BugGrabber.lua`: the newest `session` number is the session that just ended.

To find this addon's recent errors:

```bash
grep -n '"message"\] = "Interface/AddOns/ICantEvenRightNow' '!BugGrabber.lua' | tail
```

## Enhanced logging

Settings > "Enhanced logging (for troubleshooting)", or `/icanteven log on`. Off by default. It records, with timestamps:

- `load`, `migration`: addon load and upgrade results
- `context`: each change of bank / vendor / auction house / mailbox / combat, with the signal that detected the bank (event, interaction, window name, API)
- `scan`: scope, stack counts, missing item data, item-data retries
- `notice`, `task`: the notice shown at a bank or vendor, and tasks opened (with route and availability)
- `transfer`: every move or sale (item, slot, destination, result or block reason) and a summary per click
- `handoff`, `auction`: hand-offs queued, Auctionator searches, and auction candidates with their price sources
- `error`: the addon's own errors

The last 2,000 lines are kept in `ICantEvenRightNowDB.debugLog` (saved on reload or logout). `/icanteven log [count]` shows the newest lines, `/icanteven log clear` empties it, `/icanteven log off` stops it. Turn it on, reproduce the problem, `/reload`, then read the log or the saved file.

## Diagnostic commands

| Command | Shows |
| --- | --- |
| `/icanteven ctx` | Each bank-detection signal separately, and what context the addon believes it is in |
| `/icanteven bankdiag` | Bank container IDs and tab data |
| `/icanteven itemdata` | Bag stacks missing item details, and what the client returns for them now |
| `/icanteven auction` | Each auction candidate with its price and source, plus sellable gear left out and why |
| `/icanteven why [all]` | Why items are held, grouped by reason |
| `/icanteven diag` | Version and basic environment (with debug mode on) |
| `/icanteven log [on\|off\|clear\|count]` | Enhanced log (see above) |

## Known failure patterns

### The window draws every tab at once, and nothing responds

An error inside a refresh stops it halfway, after panels are shown but before the inactive ones are hidden. Look for this addon's errors in `!BugGrabber.lua`. `UpdateContext` runs before every refresh and scan, so an error there breaks everything.

### "script ran too long" / the game stalls while loading

A refresh did too much work in one go. The known case: walking every frame (`EnumerateFrames`) on each refresh. Never walk all frames on a refresh path. A test (`context detection never walks every frame`) guards this.

### Errors mentioning "bad self" or "forbidden object"

Some frames are forbidden to addons, and any method call on them errors. Check `frame:IsForbidden()` first and use `pcall`, or better, don't touch frames you didn't create or look up by name.

### Bank detected where there is no bank

Check `/icanteven ctx`. Known false signals, all removed:

- Bank bags answer `GetContainerNumFreeSlots` with 0 away from a bank.
- A child frame keeps its own shown flag while its parent is hidden (`BankPanelCopperButton`). Use `IsVisible`, not `IsShown`.
- Broad name patterns such as `bank` match unrelated frames.

### Items vanish at a vendor before you click anything

Another addon sold them (seen with the "Vendor" addon). This addon only sells selected items from a Sell click, at most 12 per click. Check the Buyback tab, and disable auto-sell in other addons while testing.

### Movement keys work, but you can't type in chat

Not this addon: its only text boxes (Transfer search and item level) never take focus by themselves, and a focused box would also block movement. Two causes seen in testing:

- Another window holds keyboard focus (a Windows notification did once). WoW still reads movement keys but typed characters go to the focused window. Dismiss notifications (Win+N) and click into the game.
- Another addon: disable all addons, then re-enable in groups. In 2026-09 it was TomTom v4.3.11 (no errors were logged; the culprit took input silently).

### "Getting ready... checking N items" / counts that used to change by themselves

Gear is judged partly on its main stat and appearance, which the game loads on demand. After a reload, or when a bank, vendor or auction house opens, the addon requests those details and waits (at most 8 seconds) before showing counts or actions (the notice says "Getting ready..." meanwhile), so the numbers don't change while you watch. Items still missing after that are reported as "N items couldn't be checked". Details arriving later show "Some item details arrived after checking: Rescan to include them"; the screen doesn't change until you click Rescan. The log shows `[ready]` lines for each wait (with a "not checked" line naming each item it gave up on and what it was waiting for), `[itemdata]` lines when it gives up on or later receives an item's details, and `[list]` lines for what each task included. Gear whose details didn't load reads "Item details didn't load: Rescan to try again" and gets no verdict; Rescan asks the game again.

### An item reads "BoE" in the Warband bank but "Warbound until equipped" in bags

In the Warband bank the game's binding functions report such items as unbound; the addon reads the tooltip there instead (`ITEM_ACCOUNTBOUND_UNTIL_EQUIP`).

### Items show without names, or as "Item 12345"

The client hadn't loaded their data when they were scanned. `/icanteven itemdata` shows what's still missing. Scans retry when data arrives (`GET_ITEM_INFO_RECEIVED`).

### Auction values look far too high

Run `/icanteven auction`. Stale prices (older than the freshness limit), approximate gear prices (below Auctionator's item-level threshold), and unconfirmed outliers are left out of values. A single high price on a non-gear item (for example a rare transmog drop) can be genuine.

## Reporting a problem

Turn on enhanced logging, reproduce the problem, and include the newest `/icanteven log` lines, the output of `/icanteven errors`, the relevant diagnostic command, and, when the UI is broken, the addon's entries from `!BugGrabber.lua` after one `/reload`.

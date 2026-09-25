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

## Diagnostic commands

| Command | Shows |
| --- | --- |
| `/icanteven ctx` | Each bank-detection signal separately, and what context the addon believes it is in |
| `/icanteven bankdiag` | Bank container IDs and tab data |
| `/icanteven itemdata` | Bag stacks missing item details, and what the client returns for them now |
| `/icanteven auction` | Each auction candidate with its price and source, plus sellable gear left out and why |
| `/icanteven why [all]` | Why items are held, grouped by reason |
| `/icanteven diag` | Version and basic environment (with debug mode on) |

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

### Items show without names, or as "Item 12345"

The client hadn't loaded their data when they were scanned. `/icanteven itemdata` shows what's still missing. Scans retry when data arrives (`GET_ITEM_INFO_RECEIVED`).

### Auction values look far too high

Run `/icanteven auction`. Stale prices (older than the freshness limit), approximate gear prices (below Auctionator's item-level threshold), and unconfirmed outliers are left out of values. A single high price on a non-gear item (for example a rare transmog drop) can be genuine.

## Reporting a problem

Include the output of `/icanteven errors`, the relevant diagnostic command, and, when the UI is broken, the addon's entries from `!BugGrabber.lua` after one `/reload`.

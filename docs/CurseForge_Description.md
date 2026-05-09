# I Can't Even Right Now (With My Bags and Bank)

I Can't Even Right Now (With My Bags and Bank) is a conservative inventory cleanup console for World of Warcraft Retail.

It helps you scan your bags, private bank, reagent bank, and warband bank, then explains which items look like old clutter, useful current-content items, shared warband candidates, vendor candidates, or items that need review. Nothing moves or sells automatically. The addon keeps recommendations, eligibility, and player selection separate so you stay in control.

## Who This Addon Is For

- Players with crowded bags who want safer cleanup than one-click auto-sort tools.
- Alt-heavy players who manage bank, reagent bank, and warband storage regularly.
- Anyone who wants clear reasoning before moving or selling items.

If you want full automation with zero review, this addon is probably not a fit. If you want visibility and control, it is designed for exactly that.

## Features

- Six-tab cleanup console: Summary, Move, Organize, Vendor, Rules, and Settings.
- Scan bags, bank, reagent bank, and warband bank storage.
- Classify items by expansion, type, binding, storage location, and safety.
- Review old-content banking and recall recommendations.
- Organize bank storage between private and warband storage.
- Review conservative vendor candidates before selling.
- Protect current-content, quest, unknown, legendary, and rule-protected items by default.
- Add item-ID rules for protect, ignore, never move, never sell, always bank, and related overrides.
- Use context checks for bank access, vendor access, and combat state before actions are enabled.

## First 5 Minutes (Quick Start)

1. Open the console with `/icanteven`.
2. Click `Scan Bags` on the Summary tab.
3. Open your bank, then run `/icanteven scan bank` (or click scan in the UI).
4. Go to the Move tab and choose a mode:
	- `Dump to Bank` to move older clutter out of bags.
	- `Recall from Bank` to pull useful items back to bags.
5. Filter by expansion and item type, select exact rows, then click the action button.

Tip: if you are doing a conservative cleanup pass, start with old expansions and small batches.

## Common Workflows

### 1) Legacy Bag Cleanup

- Open bank.
- Move tab -> `Dump to Bank`.
- Filter to older expansions.
- Review rows and `Bank Selected`.

### 2) AH Prep (Find Auctionable Gear)

- Open bank.
- Move tab -> `Recall from Bank`.
- Filter type to `BoE`.
- Select and recall only what you want to list.

### 3) Vendor Pass

- At bank: Vendor tab can prepare candidates by recalling to bags.
- At vendor: Vendor tab shows sell-ready candidates.
- Use rules (`Never Sell`, `Protect`) to keep favorites safe next time.

## How to Read Recommendations

- `Recommended` means the addon thinks an action is sensible.
- `Blocked` means context, safety, or rules currently prevent action.
- Not recommended does not mean invisible forever; adjust filters and review manually.

The addon is built to explain "why" before anything happens.

## Slash Commands

- `/icanteven` or `/icant` opens the cleanup console.
- `/icanteven scan [bags|bank|all]` scans available storage.
- `/icanteven summary`, `/icanteven move`, `/icanteven organize`, `/icanteven vendor`, `/icanteven rules`, `/icanteven settings` open specific tabs.
- `/icanteven dump <expansion>` and `/icanteven recall <expansion>` set mode presets.
- `/icanteven minimap` toggles the minimap launcher.
- `/icanteven buttons` shows launcher status.
- `/icanteven bankdiag` or `/icanteven bankids` prints bank container diagnostics.

## New User FAQ

### Why do I see no rows?

Most often this is one of these:

- You have not scanned the relevant storage yet.
- The required context is not open (bank or vendor).
- Your current filters hide matching rows.

### Will this sell or move things automatically?

No. Actions require your explicit row selection.

### Can I protect items permanently?

Yes. Add item rules like `Protect`, `Ignore`, `Never Move`, or `Never Sell`.

## Philosophy

This addon is cautious on purpose. It is not a bag replacement, and it is not an automatic cleanup tool. It gives you a clearer view of your inventory clutter, explains its reasoning, and lets you decide exactly what to process.

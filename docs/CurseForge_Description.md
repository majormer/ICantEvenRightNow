# I Can't Even Right Now (With My Bags and Bank)

I Can't Even Right Now (With My Bags and Bank) is a conservative inventory cleanup console for World of Warcraft Retail.

It helps you scan your bags, bank, and warband bank, then move or sell items on your terms. You pick where items come from, where they go, and which ones to act on. Nothing moves or sells automatically.

## Who This Addon Is For

- Players with crowded bags who want safer cleanup than one-click auto-sort tools.
- Alt-heavy players who manage bank and warband storage regularly.
- Anyone who wants clear reasoning before moving or selling items.

If you want full automation with zero review, this addon is probably not a fit. If you want visibility and control, it is designed for exactly that.

## Features

- Four-tab cleanup console: Summary, Transfer, Rules, and Settings.
- Scan bags, private bank (all tabs or individual), and warband bank storage.
- Unified Transfer tab: pick any Source and Destination — Bags, Bank tabs, Warband Bank, or Vendor — and act on exactly that combination.
- Filter by expansion, binding, item type, slot, upgrade potential, item level, or name search within any transfer.
- Five quick tasks configure common deposit, withdrawal, vendor, and Warband jobs instantly.
- Saved workflows remember the route, filters, Actionable only, search, item-level range, and sort order.
- Compact advanced filters, route swapping, and sorting by name, status, item level, vendor value, expansion, or binding.
- Scrollable item list with per-item block reasons.
- Actionable-only toggle: hide blocked rows and focus on what you can move right now.
- Result counts show how many source items match, can move, are blocked, and are selected.
- Per-item block reasons explain exactly why an item cannot be moved (bank closed, vendor closed, no slots, item rule, equipped, etc.).
- Protect current-content, quest, legendary, and rule-protected items by default.
- Per-item rules: Protect, Ignore, Never Sell. Rules always win.
- Context checks for bank access, vendor access, and combat state gate all actions.
- Summary tab shows inventory scope counts: items in bags, items in bank, old-content in bags and bank, warband bank items, active rules, and unclassified items.
- Error log captures Lua errors to SavedVariables for diagnostics.

## First 5 Minutes (Quick Start)

1. Open the console with `/icanteven`.
2. Click `Scan Bags` on the Transfer tab.
3. Open your bank, then click `Scan Bank`.
4. Load a quick task or set **From** and **To** manually.
5. Refine the results, select movable rows, then use the contextual action button.

Tip: use the Actionable Only checkbox to hide anything currently blocked so you only see what you can act on right now.

## Common Workflows

### 1) Legacy Bag Cleanup

- Open bank.
- Load **Deposit Old Items**.
- Review rows and deposit the selected items.

### 2) AH Prep (Find Auctionable Gear)

- Open bank.
- Load **Pull Auctionable BoEs**.
- Select and recall only what you want to list.

### 3) Vendor Pass

- At a vendor with items in your bags.
- Load **Sell Old Consumables**.
- Review rows — Never Sell rules block protected items automatically — then use the Sell action.

### 4) Warband Storage Shuffle

- Open the bank and load **Consolidate Warbound Gear**, or configure any other Source/Destination pair manually.

## Per-Item Rules

Rules apply regardless of what Source or Destination you choose.

- **Protect** — blocks item from any transfer.
- **Ignore** — blocks item and marks it as intentionally skipped.
- **Never Sell** — blocks the item when Vendor is the destination; other transfers are unaffected.

Add rules from the Rules tab or via the rule menu on any Transfer row. Remove them at any time.

## Slash Commands

- `/icanteven` or `/icant` — open the cleanup console.
- `/icanteven scan [bags|bank|all]` — scan storage.
- `/icanteven summary`, `transfer`, `rules`, `settings` — open a specific tab.
- `/icanteven dump <expansion>` — pre-configure Transfer for a Bags → Bank dump filtered to that expansion.
- `/icanteven recall <expansion>` — pre-configure Transfer for a Bank → Bags recall filtered to that expansion.
- `/icanteven vendor` — pre-configure Transfer for a Bags → Vendor sell pass.
- `/icanteven minimap` — toggle the minimap launcher.
- `/icanteven buttons` — show launcher status.
- `/icanteven bankdiag` or `/icanteven bankids` — print bank container diagnostics.
- `/icanteven errors` — show captured Lua errors.
- `/icanteven clearerrors` — clear the error log.

## Filters Explained

- **Expansion filter**: Items by expansion (current, old, unknown)
- **Binding filter**: Items by bind type (BoE, WuE, Soulbound, Warbound, BoP)
- **Type filter**: Items by category (Consumable, Reputation, Quest, etc.)
- **Slot filter**: Gear by equipment slot (Head, Chest, Finger, etc.)
- **Upgrade filter**: Gear that beats your currently equipped item level
- **Item Level filter**: Gear by minimum/maximum item level
- **Armor Type filter**: Armor by material type (Cloth, Leather, Mail, Plate)

## New User FAQ

### Why do I see no rows?

Most often this is one of these:

- You have not scanned the relevant storage yet (use Scan Bags or Scan Bank).
- The required context is not open (bank must be open to use bank sources/destinations; vendor must be open to sell).
- Your current filters or the Actionable Only toggle are hiding matching rows.

### Will this sell or move things automatically?

No. Actions require your explicit row selection and a button click.

### Can I protect items permanently?

Yes. Add a Protect or Never Sell rule from any Transfer row's rule menu, or from the Rules tab.

## Philosophy

This addon is cautious on purpose. It is not a bag replacement and it is not an automatic cleanup tool. It gives you a clearer view of your inventory, explains why each item is blocked or movable, and lets you decide exactly what to transfer.

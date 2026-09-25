# I Can't Even Right Now (With My Bags and Bank)

A World of Warcraft Retail addon that makes inventory cleanup a short, safe routine: it finds the items worth moving or letting go, explains why each one is there, knows which of your characters can use it, and waits for your click before anything moves.

## Overview

I Can't Even Right Now (With My Bags and Bank) is a cleanup console, not a bag replacement. The addon does the finding, sorting, and explaining; you review the list and confirm.

It is cautious on purpose. Protected, quest, current-content, and ruled items are blocked by default, every move or sale needs an explicit selection and click, and selling stops at 12 items per click so every sale stays in the vendor's buyback.

## Features

### Home: tasks, not settings

- The console opens on **Home**, where every task is a card with a live count and value ("Deposit Old Items: 23 ready").
- Cards that need a bank or vendor say so ("12 waiting: Visit a bank"). Click a card to open its review list.
- Built-in tasks: Deposit Old Items, Pull Bank Upgrades, Pull Auctionable BoEs, Sell Old Consumables, Deposit to Warband, Consolidate Warbound Gear, Pull Items That Can Go, Sell Items That Can Go, Auction Candidates, Send to Alts, Waiting for You, Price My Items.
- **Save as task** turns any custom setup (route, filters, search, item level, sort) into your own card.
- At a bank or vendor, a small notice names the task that's ready (or the console opens, or nothing; your choice).

### Your characters and who benefits

- The **Characters** tab lists every character that has logged in with the addon.
- Give each a role: **Main / Active**, **Leveling**, **Crafter**, or **Utility**. Unassigned characters are ignored, so dozens of unsorted alts never flood decisions.
- Roles come with suggestions (max level, gaining levels, professions) that learn from your own choices; accept them one by one or all at once.
- Hints name who benefits: "Upgrade for Tankalt (Leveling)", "Used by Stitcher (Tailoring)".

### Warband bank

- Each Warband tab is its own source and destination.
- **Warband (by tab settings)** sends each item to the tab whose own Blizzard "assign to" settings match it. The addon never changes your tab settings.
- **Alt hand-offs:** mark an item "Send to an alt...", deposit it with Send to Alts, and that character sees **Waiting for You**.
- Item tooltips can show how many your account holds and where; `/icanteven where <name>` searches every character.

### Why is this here?

- Every row explains why the item is being kept: appearance already collected, collectible not learned, quest in progress or already done, a crafter who uses it, gear a played character can wear, current-expansion content, time held, and more.
- Tooltips add what letting it go would cost ("You keep the appearance. Worth 4g at a vendor.").
- Mark items as Keepsake, Keep for an alt, Keep for an event, or Investment (with a reminder) to stop suggestions.
- `/icanteven why` prints a read-only summary grouped into Can go, Your call, and Worth keeping.

### Value awareness

- Auction prices from Auctionator or TSM when installed, or from **Price My Items** at an auction house (only items you own, paced).
- With Auctionator: search all auction candidates in its Shopping tab with one click (or save them as a shopping list), and hand price checks to Auctionator. Gear prices known only for the base item are marked "approximate".
- Each price shows its source and age. Items worth noticeably more at auction are flagged at vendors and never pre-selected for selling.

### Safety

- Explicit selection and a click before every move or sale; pre-selection is an optional setting, off by default.
- Every action re-checks the slot first; items that moved since the last scan are skipped.
- Protect, Ignore, and Never Sell rules always win.
- Bank, vendor, and combat checks gate every action.
- Selling stops at 12 per click (the buyback limit).

## Installation

1. Download the latest release.
2. Extract it to your WoW addon directory:
   - **Windows:** `C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\`
   - **Mac:** `/Applications/World of Warcraft/_retail_/Interface/AddOns/`
   - **Linux:** Ensure the folder is extracted to the equivalent path in your Wine prefix.
3. Ensure the folder is named `ICantEvenRightNow`.
4. Restart WoW or type `/reload` in-game.

Upgrading from an earlier version keeps your rules, saved presets, and settings. A "What's new" card explains what changed, and `/icanteven migration` shows exactly what was carried over.

## Usage

### Slash Commands

- `/icanteven` or `/icant` - Open Home.
- `/icanteven transfer` - Open the Transfer view.
- `/icanteven characters` - Open the Characters tab (roles).
- `/icanteven why [all]` - Explain why items are being kept (read-only).
- `/icanteven where <name>` - Find an item across all your characters and the Warband bank.
- `/icanteven scan [bags|bank|all]` - Scan inventory.
- `/icanteven dump [expansion]` / `recall [expansion]` / `vendor` - Pre-configure a route and open it.
- `/icanteven rules` - Open the Rules tab.
- `/icanteven settings` - Open Settings.
- `/icanteven migration` - Show the upgrade report.
- `/icanteven minimap` - Show or hide the minimap button.
- `/icanteven errors` / `clearerrors` - View or clear logged Lua errors.
- `/icanteven bankdiag`, `diag`, `debug`, `buttons` - Diagnostics.

### Typical Workflow

1. Walk up to a bank. A notice names the ready task, or open Home with `/icanteven`.
2. Click a card, for example **Deposit Old Items** or **Deposit to Warband**.
3. Review the list; each row says why the item is there and what happens to it.
4. Select (or use Select Movable) and click Deposit.
5. At a vendor, use **Sell Items That Can Go**; selling stops at 12 per click.

## Technical Details

### File Structure

```text
ICantEvenRightNow/
├── ICantEvenRightNow.toc  # Addon metadata (load order)
├── Data.lua               # Static data and saved-variable defaults
├── Debug.lua              # Debug utilities
├── Shared.lua             # Constants, bag IDs, storage kinds, context detection
├── Migration.lua          # Versioned, backed-up upgrade of saved data
├── Characters.lua         # Roster, roles, suggestions, per-character snapshots
├── Evaluator.lua          # Binding detection, item classification, decisions
├── Reasons.lua            # "Why is this here?" detectors, time held, keep reasons
├── Warband.lua            # Warband tab routing and the alt hand-off queue
├── Filter.lua             # Filter state and matching, quick tasks, saved tasks
├── Scanner.lua            # Container scanning
├── Transfer.lua           # Block reasons, slot verification, moves and sales
├── Tasks.lua              # Task cards: counts, availability, pre-selection
├── UI.lua                 # Console frame, Transfer, Rules, Settings
├── HomeUI.lua             # Home, Characters, notices, hand-off picker, where-is-it
├── Value.lua              # Auction prices, freshness, vendor protection
├── Onboarding.lua         # What's new, tips, welcome back
├── Integrations.lua       # Optional BetterBags categories
├── Core.lua               # Lifecycle, events, slash commands
├── tests/                 # Offline test suite (not packaged)
└── docs/
```

Modules share symbols through `ns.Private`. The offline test suite (`tests/`) runs the addon against a simulated WoW client; `scripts/Test-Addon.ps1` runs it together with the static checks.

### Key Concepts

- **Task** - A route (source and destination) plus filters for a common job, shown as a Home card.
- **Role** - Who a character is (Main, Leveling, Crafter, Utility); decides who benefits from an item.
- **Reason** - Why an item is being kept, with a disposition: keep, can go, or your call.
- **Block Reason** - Why an item cannot be moved right now (bank closed, no slots, Protect rule, item moved since the scan, and so on).
- **Rule** - An item-ID override: Protect, Ignore, Never Sell, or a keep reason.

### Saved Variables

- `ICantEvenRightNowDB` (account-wide) - Rules, saved tasks, settings, the character roster with per-character snapshots, the Warband snapshot, hand-offs, prices, time held, and migration backups.

## Compatibility

- **Game Version:** World of Warcraft Retail 12.1 (Midnight)
- **Dependencies:** None required
- **Optional:** LibDataBroker-1.1 and LibDBIcon-1.0 (minimap launcher), Auctionator or TradeSkillMaster (auction prices), BetterBags (categories)
- **Conflicts:** None known

## Support

Bug reports and feature requests are welcome through the GitHub issue tracker.

Optional support is available on Ko-fi: <https://ko-fi.com/finalomega>

## License

Source code is MIT licensed. The addon artwork and Finalomega brand assets are all rights reserved and are not licensed for reuse. See [LICENSE](LICENSE) for details.

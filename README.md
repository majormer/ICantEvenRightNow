# I Can't Even Right Now (With My Bags and Bank)

A World of Warcraft Retail addon for conservative inventory cleanup: scan your bags and bank, classify clutter, bank old content safely, recall useful items, organize bank storage, and review vendor candidates before anything moves.

## Overview

I Can't Even Right Now (With My Bags and Bank) is a small cleanup console, not a bag replacement. It keeps recommendation, eligibility, and selection separate so the addon can explain what it thinks without turning that recommendation into an automatic action.

The addon is intentionally cautious. Unknown, quest, legendary, and protected items are blocked by default, and every movement or sell action requires explicit selection.

## Features

### Smart Inventory Classification

- **Expansion Detection** - Identifies old, current, and unknown-expansion items using Blizzard expansion metadata.
- **Item Type Categorization** - Classifies reputation, quest, profession, seasonal, consumable, BoE, currency-like, equipment, material, and unknown items.
- **Armor Type Filter** - Filter armor items by type (Cloth, Leather, Mail, Plate) for targeted gear management.
- **Current-Content Protection** - Keeps current expansion and protected seasonal items, including Mythic Keystones, out of old-content cleanup flows.
- **Explainable Decisions** - Shows recommendation, reason, blocking status, and rule state before you act.
- **Quick Tasks** - Load complete setups for common jobs such as depositing old items, pulling upgrades or auctionable BoEs, selling old consumables, and consolidating Warbound gear.
- **Saved Workflows** - Save Source, Destination, filters, Actionable only, search, item-level range, and sort order for one-click reuse across sessions.

### Cleanup Console UI

The addon has four tabs:

1. **Summary** - Inventory scope counts: items in bags, items in bank, old-content counts, Warband bank items, active rules, and last scan timestamps.
2. **Transfer** - Move items between any combination of Bags, Private Bank, Warband Bank, Vendor, or individual Bank tabs. Start with a quick task or saved workflow, refine by Expansion, Binding, Type, Slot, Upgrade, item level, or name, then sort and select. Per-item block reasons and an Actionable only toggle keep the list focused.
3. **Rules** - Item-ID overrides: Protect, Ignore, or Never Sell. Each rule shows its origin and can be removed individually.
4. **Settings** - Configure the minimap launcher and inspect quick-access status.

Quick access uses a minimap launcher. The minimap launcher uses LibDataBroker/LibDBIcon when available so minimap button organizers can collect it.

### Context-Aware Behavior

Actions are enabled only when the related game context is available:

- Bags, character bank tabs, and Warband bank scanning
- Bank-open checks for movement and organization
- Merchant-open checks for selling
- Combat-state checks before sensitive actions
- Optional minimap launcher for opening the cleanup console

### Safety-First Design

- **Scoped Selection** - Select movable rows instead of using broad destructive actions.
- **Explicit Confirmation** - The addon acts only on selected rows.
- **Manual Intent Preserved** - Transfer choices remain player-driven when rules, context, and capacity allow them.
- **Rule Overrides** - Item-ID rules let you protect favorites or teach the addon how to handle edge cases.

## Installation

1. Download the latest release.
2. Extract it to your WoW addon directory:
   - **Windows:** `C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\`
   - **Mac:** `/Applications/World of Warcraft/_retail_/Interface/AddOns/`
   - **Linux:** Ensure the folder is extracted to the equivalent path in your Wine prefix.
3. Ensure the folder is named `ICantEvenRightNow`.
4. Restart WoW or type `/reload` in-game.

## Usage

### Slash Commands

- `/icanteven` or `/icant` - Open the cleanup console.
- `/icanteven scan [bags|bank|all]` - Scan inventory.
- `/icanteven summary` - Open the Summary tab.
- `/icanteven transfer` - Open the Transfer tab.
- `/icanteven dump [expansion]` - Pre-configure Transfer to bank old content and open it.
- `/icanteven recall [expansion]` - Pre-configure Transfer to recall from bank and open it.
- `/icanteven organize` - Pre-configure Transfer for bank organization and open it.
- `/icanteven vendor` - Pre-configure Transfer for vendor selling and open it.
- `/icanteven rules` - Open the Rules tab.
- `/icanteven settings` or `/icanteven options` - Open the Settings tab.
- `/icanteven minimap` - Show or hide the minimap button.
- `/icanteven buttons` - Print quick-access launcher status.
- `/icanteven bankdiag` or `/icanteven bankids` - Print resolved bank container diagnostics.
- `/icanteven errors` - View logged Lua errors.
- `/icanteven clearerrors` - Clear the error log.
- `/icanteven debug` - Toggle debug output.
- `/icanteven diag` - Run a diagnostic dump.

### Typical Workflow

1. Open the console with `/icanteven`.
2. Scan bags, bank, or all available storage.
3. In the Transfer tab, choose a Source and Destination.
4. Load a quick task or saved workflow, or configure the route manually.
5. Refine and sort the results; save the complete setup as a workflow if you want to reuse it.
6. Select the rows you want to act on.
7. Transfer or sell selected items.
8. Add Rules for any item you want handled differently next time.

## Recent Changes

**0.6.0** (in development):
- Added five quick tasks and complete saved workflows
- Added compact advanced filters, route swapping, and six result sort modes
- Added source/match/movable/blocked/selected counts and contextual empty states
- Added contextual Deposit, Withdraw, Move, and Sell actions with last-result status
- Added debounced inventory refresh and WoW Retail 12.1 compatibility metadata

**0.5.0** (2026-05-11):
- Added Armor Type filter for gear (Cloth/Leather/Mail/Plate)
- Transfer tab is now the default landing tab
- Fixed Upgrade filter crash (API change in patch 12.x)
- Fixed Slot and Armor Type filter forward-reference errors
- Fixed Transfer tab scrollbar and selection issues
- Improved source/destination validation with context notices

**0.4.0** (2026-05-09):
- Replaced paginated list with scrollable FauxScrollFrame
- Added Item Level, Slot, and Upgrade filters
- Added saved filter presets ("Favorites")
- Split Core.lua into focused modules for maintainability
- Renamed "Bind" filter to "Binding"

## Technical Details

### File Structure

```text
ICantEvenRightNow/
├── ICantEvenRightNow.toc  # Addon metadata
├── ICantEvenRightNow.png  # Addon icon/art
├── Data.lua               # Static data tables and defaults
├── Debug.lua              # Debug utilities
├── Shared.lua             # Constants, bag ID resolution, context detection, storage helpers
├── Evaluator.lua          # Binding detection, item classification, decision building
├── Filter.lua             # Filter state, matching logic, quick/saved workflows, sorting inputs, upgrade detection
├── Scanner.lua            # Container scanning and bank diagnostics
├── Transfer.lua           # Movement execution and vendor selling
├── UI.lua                 # UI construction and refresh (FauxScrollFrame, tab frames)
├── Core.lua               # Addon lifecycle, events, slash commands, UI coordination
└── docs/
```

The addon uses a modular architecture introduced in 0.4.0. Modules communicate through a shared namespace (`ns.Private`) with clear separation of concerns: Shared provides utilities, Evaluator classifies items, Filter manages filter state, Scanner handles container scanning, Transfer executes movements, UI builds the interface, and Core coordinates everything.

### Key Concepts

- **Source / Destination** - Where items are coming from and going to. The player sets both explicitly.
- **Filter** - Narrows the Transfer list by Expansion, Binding, Type, Slot, Upgrade potential, item level, or name search.
- **Quick Task** - A built-in route and filter setup for a common inventory job.
- **Saved Workflow** - A user-named route, filter, actionable-only, query, and sort setup that can be reloaded in one click.
- **Block Reason** - Why a specific item cannot be transferred right now (bank closed, vendor closed, no slots, Protect rule, etc.).
- **Rule** - An item-ID override: Protect, Ignore, or Never Sell.

Transfer intent is always player-driven. The addon classifies and explains; the player decides.

### Saved Variables

- `ICantEvenRightNowDB` - Stores rules, UI state, context state, scan data, error log, and saved workflows.

## Compatibility

- **Game Version:** World of Warcraft Retail 12.1 (Midnight)
- **Dependencies:** None required
- **Optional:** LibStub, LibDataBroker-1.1, and LibDBIcon-1.0 for standard minimap launcher integration
- **Conflicts:** None known

## Support

Bug reports and feature requests are welcome through the GitHub issue tracker.

Optional support is available on Ko-fi: <https://ko-fi.com/finalomega>

## License

Source code is MIT licensed. The addon artwork and Finalomega brand assets are all rights reserved and are not licensed for reuse. See [LICENSE](LICENSE) for details.

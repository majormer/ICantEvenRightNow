# I Can't Even Right Now (With My Bags and Bank)

A World of Warcraft Retail addon for conservative inventory cleanup: scan your bags and bank, classify clutter, bank old content safely, recall useful items, organize bank storage, and review vendor candidates before anything moves.

## Overview

I Can't Even Right Now (With My Bags and Bank) is a small cleanup console, not a bag replacement. It keeps recommendation, eligibility, and selection separate so the addon can explain what it thinks without turning that recommendation into an automatic action.

The addon is intentionally cautious. Unknown, quest, legendary, and protected items are blocked by default, and every movement or sell action requires explicit selection.

## Features

### Smart Inventory Classification

- **Expansion Detection** - Identifies old, current, and unknown-expansion items using Blizzard expansion metadata.
- **Item Type Categorization** - Classifies reputation, quest, profession, seasonal, consumable, BoE, currency-like, equipment, material, and unknown items.
- **Current-Content Protection** - Keeps current expansion and protected seasonal items, including Mythic Keystones, out of old-content cleanup flows.
- **Explainable Decisions** - Shows recommendation, reason, blocking status, and rule state before you act.

### Cleanup Console UI

The addon has four tabs:

1. **Summary** - Inventory scope counts: items in bags, items in bank, old-content counts, Warband bank items, active rules, and last scan timestamps.
2. **Transfer** - Move items between any combination of Bags, Private Bank, Warband Bank, Vendor, or individual Bank tabs. Filter by Expansion, Binding, Type, Slot, Upgrade, item level, or name. Save named filter presets to reload common setups instantly. Per-item block reasons and an actionable-only toggle keep the list focused.
3. **Rules** - Item-ID overrides: Protect, Ignore, or Never Sell. Each rule shows its origin and can be removed individually.
4. **Settings** - Configure the minimap launcher and inspect quick-access status.

Quick access uses a minimap launcher. The minimap launcher uses LibDataBroker/LibDBIcon when available so minimap button organizers can collect it.

### Context-Aware Behavior

Actions are enabled only when the related game context is available:

- Bags, private bank, reagent bank, and warband bank scanning
- Bank-open checks for movement and organization
- Merchant-open checks for selling
- Combat-state checks before sensitive actions
- Optional minimap launcher for opening the cleanup console

### Safety-First Design

- **Scoped Selection** - Select visible or recommended rows instead of using broad destructive actions.
- **Explicit Confirmation** - The addon acts only on selected rows.
- **Manual Actions Allowed** - In Move tab, manual bank/recall actions are available regardless of recommendation when rules, context, and capacity allow it.
- **Rule Overrides** - Item-ID rules let you protect favorites or teach the addon how to handle edge cases.

## Installation

1. Download the latest release.
2. Extract it to your WoW addon directory:
   - **Windows:** `C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\`
   - **Mac:** `/Applications/World of Warcraft/_retail_/Interface/AddOns/`
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
4. Apply filters — Expansion, Binding, Type, Slot, Upgrade, or item level — to narrow the list.
5. Load a saved filter preset or save the current filter combination for reuse.
6. Select the rows you want to act on.
7. Transfer or sell selected items.
8. Add Rules for any item you want handled differently next time.

## Technical Details

### File Structure

```text
ICantEvenRightNow/
├── ICantEvenRightNow.toc  # Addon metadata
├── ICantEvenRightNow.png  # Addon icon/art
├── Data.lua               # Static data tables and defaults
├── Debug.lua              # Debug utilities
├── Shared.lua             # Constants, bag ID resolution, context detection
├── Evaluator.lua          # Binding detection, item classification, decision building
├── Filter.lua             # Filter state, matching logic, option builders, saved presets
├── Scanner.lua            # Container scanning and bank diagnostics
├── Transfer.lua           # Movement execution and vendor selling
├── UI.lua                 # UI construction and refresh
├── Core.lua               # Addon lifecycle, events, slash commands
└── docs/
```

### Key Concepts

- **Source / Destination** - Where items are coming from and going to. The player sets both explicitly.
- **Filter** - Narrows the Transfer list by Expansion, Binding, Type, Slot, Upgrade potential, item level, or name search.
- **Saved Filter Preset** - A named combination of categorical filters that can be saved and reloaded in one click.
- **Block Reason** - Why a specific item cannot be transferred right now (bank closed, vendor closed, no slots, Protect rule, etc.).
- **Rule** - An item-ID override: Protect, Ignore, or Never Sell.

Transfer intent is always player-driven. The addon classifies and explains; the player decides.

### Saved Variables

- `ICantEvenRightNowDB` - Stores rules, UI state, context state, scan data, error log, and saved filter presets.

## Compatibility

- **Game Version:** World of Warcraft Retail (12.x / Midnight)
- **Dependencies:** None required
- **Optional:** LibStub, LibDataBroker-1.1, and LibDBIcon-1.0 for standard minimap launcher integration
- **Conflicts:** None known

## Support

Bug reports and feature requests are welcome through the GitHub issue tracker.

Optional support is available on Ko-fi: <https://ko-fi.com/finalomega>

## License

Source code is MIT licensed. The addon artwork and Finalomega brand assets are all rights reserved and are not licensed for reuse. See [LICENSE](LICENSE) for details.

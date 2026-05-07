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

The addon has six tabs:

1. **Summary** - Current context, scan status, and category totals.
2. **Move** - Bank old content or recall relevant items with expansion/type filters and scoped selection.
3. **Organize** - Review searchable bank-to-bank moves that group items into more sensible storage locations.
4. **Vendor** - Review searchable safe sell candidates and recall-to-bags steps for vendoring.
5. **Rules** - Teach the addon item-ID rules for protect, ignore, never move, never sell, always bank, and similar overrides.
6. **Settings** - Configure the minimap launcher and inspect quick-access status.

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
- `/icanteven move` - Open the Move tab.
- `/icanteven dump <expansion>` - Prepare old-content banking for an expansion filter.
- `/icanteven recall <expansion>` - Prepare recall from bank for an expansion filter.
- `/icanteven organize` - Open the Organize tab.
- `/icanteven vendor` or `/icanteven sell` - Open the Vendor tab.
- `/icanteven rules` - Open the Rules tab.
- `/icanteven settings` or `/icanteven options` - Open the Settings tab.
- `/icanteven minimap` - Show or hide the minimap button.
- `/icanteven buttons` - Print quick-access launcher status.
- `/icanteven bankdiag` or `/icanteven bankids` - Print resolved bank container diagnostics.
- `/icanteven debug` - Toggle debug output.
- `/icanteven diag` - Run a diagnostic dump.

### Typical Workflow

1. Open the console with `/icanteven`.
2. Scan bags, bank, or all available storage.
3. Review recommendations and blocked reasons.
4. Filter by mode, expansion, item type, or storage source.
5. Select the exact rows you want to process.
6. Execute the selected move, organize, recall, or vendor action.
7. Add rules for any item you want handled differently next time.

## Technical Details

### File Structure

```text
ICantEvenRightNow/
├── ICantEvenRightNow.toc  # Addon metadata
├── ICantEvenRightNow.png  # Addon icon/art
├── Core.lua               # Main UI, logic, event handlers
├── Data.lua               # Static data tables and defaults
├── Debug.lua              # Debug utilities
└── docs/
```

### Key Concepts

- **Recommendation** - What the classifier thinks should happen.
- **Eligibility** - Whether the action is safe and currently possible.
- **Selection** - What the player chose for this run.

These stay separate so recommended never accidentally means will be moved.

### Saved Variables

- `ICantEvenRightNowDB` - Stores rules, UI state, context state, and scan data.

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

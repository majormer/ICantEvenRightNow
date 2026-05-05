# I Can't Even Right Now (With My Bags and Bank)

A World of Warcraft Retail addon for intelligent inventory cleanup - bank old content items, recall relevant items, and manage inventory clutter.

## Overview

I Can't Even Right Now (With My Bags and Bank) helps you manage inventory clutter by identifying old content items that can be safely banked, recalling relevant items for current activities, and providing a clean interface for inventory organization.

## Features (Planned)

### Smart Inventory Classification

- **Expansion Detection** — Automatically identifies items from old expansions
- **Item Type Categorization** — Classifies items as reputation, quest, profession, consumable, BoE, currency-like, or unknown
- **Curated Item Tables** — Maintains curated lists of known items per expansion with recommended actions
- **Safety Defaults** — Blocks dangerous actions on unknown, quest, legendary, and soulbound items

### Context-Aware Behavior

The addon constantly tracks your current context to enable safe actions:

- Bank open/closed status (including reagent bank and warband bank)
- Vendor availability
- Auction house status
- Mailbox access
- Combat state

Actions are only available when safe and appropriate for the current context.

### Cleanup Console UI

Three-tab interface for inventory management:

1. **Summary Tab** — Shows current state, last scan time, and summary cards for item categories
2. **Move Tab** — Core feature for banking old items and recalling relevant ones with filters and scoped selection
3. **Rules Tab** — Teach the addon your preferences with item-ID based rules (protect, never move, never sell, always bank, etc.)

### Safety-First Design

- **Scoped Selection** — No dangerous "select everything" buttons; use visible/recommended/expansion/tag scoped selection
- **Explicit Confirmation** — Actions require explicit user selection and confirmation
- **Reversible by Default** — Bank movement is reversible; selling is much narrower and post-MVP
- **Explainable Decisions** — Each item row shows recommendation, reason, and rule status

## Installation

1. Download the latest release
2. Extract to your WoW addon directory:
   - **Windows:** `C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\`
   - **Mac:** `/Applications/World of Warcraft/_retail_/Interface/AddOns/`
3. Ensure the folder is named `ICantEvenRightNow`
4. Restart WoW or type `/reload` in-game

## Usage

### Slash Commands

- `/icanteven scan [bags|bank]` — Scan inventory
- `/icanteven summary` — Show summary UI
- `/icanteven debug` — Toggle debug mode
- `/icanteven diag` — Run diagnostic dump

### Planned Workflow

1. **Scan Inventory** — Use `/icanteven scan` to analyze bags and bank
2. **Review Summary** — Check the Summary tab for overview of item categories
3. **Select Items** — In the Move tab, filter by expansion/type and select items
4. **Execute Move** — Use scoped selection (visible/recommended) and confirm movement
5. **Teach Rules** — Add rules for items you want to protect or handle specially

## MVP Scope

The first usable version will include:

- Bag and bank scanning
- Summary UI with context awareness
- Move tab with filters and scoped selection
- Rules tab for item-ID based rules
- Bank dump preview and movement after explicit selection

**Not included in MVP:** Selling functionality (bank movement is reversible and is the primary feature).

## Technical Details

### File Structure

```
ICantEvenRightNow/
├── ICantEvenRightNow.toc  # Addon metadata
├── Core.lua               # Main UI, logic, event handlers
├── Data.lua               # Static data tables (expansions, item types, curated items)
├── Debug.lua              # Debug utility
└── docs/
```

### Key Concepts

- **Recommendation** — What the classifier thinks should happen
- **Eligibility** — Whether the action is safe and currently possible
- **Selection** — What the user chose for this run

These are kept separate to prevent "recommended" from accidentally meaning "will be moved."

### Saved Variables

- `ICantEvenRightNowDB` — Stores rules, context state, and last scan timestamps

## Compatibility

- **Game Version:** World of Warcraft Retail (12.x / Midnight)
- **Dependencies:** None
- **Conflicts:** None known

## Contributing

When contributing code, please follow standard WoW addon development practices:

- Use `C_*` namespaced APIs over legacy globals
- Use `BackdropTemplate` for frames with `SetBackdrop`
- Use `SecureActionButtonTemplate` for protected actions
- Test with `InCombatLockdown()` checks before modifying secure frames

## License

MIT License - see [LICENSE](LICENSE) for details

## Feedback

Report bugs or feature requests via the GitHub issue tracker.

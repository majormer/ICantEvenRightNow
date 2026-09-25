# UX Improvement Roadmap

## 1. Context

This document tracks UX friction and improvement opportunities as the addon evolves. Items marked **Done** have shipped or are implemented in the current development cycle.

## 2. UX Goals

- Reduce setup clicks for common workflows
- Keep conservative safeguards while allowing intentional manual workflows
- Make filter behavior predictable and discoverable
- Explain blocked and empty states clearly

## 3. Improvements Shipped

### Done in 0.3.0

- **Unified Transfer tab**: Replaced Move, Organize, and Vendor tabs with a single Source → Destination model. Eliminates tab-switching between bank and vendor.
- **Per-item block reasons**: Each row in the Transfer list explains why an item cannot be moved (context, rule, capacity).
- **Actionable-only toggle**: "Actionable only" hides blocked rows so users can focus on what they can actually do right now.
- **Context-gated dropdowns**: Bank and Vendor destination options are hidden when the relevant context is not open, eliminating context-mismatch errors.

### Done in 0.4.0

- **Scrollable list**: Replaced paginated Transfer list with a FauxScrollFrame. No more page navigation.
- **Saved Filter Presets**: Named combinations of Expansion, Binding, Type, Slot, and Upgrade filters. Users can save, load, and remove presets from the Transfer tab. Two defaults ship: "Old Gear Dump" and "Upgrade Check".
- **Item Level filter**: Min/max ilvl range filter, applied only to equippable gear.
- **Slot filter**: Narrow Transfer list to a specific gear slot.
- **Upgrade filter**: Show only gear that beats the currently equipped piece (weaker slot used for rings/trinkets).
- **Split filter dropdowns**: Binding is now a separate dropdown from item Type, eliminating the old combined "BoE" entry in the Type filter.

### Done in 0.5.0

- **Armor Type filter**: Filter armor items by material type (Cloth, Leather, Mail, Plate). Non-armor items are unaffected.
- **Transfer as default tab**: Transfer tab is now the landing tab when opening the addon.
- **Context validation with notices**: Source/Destination dropdowns reset to valid defaults when context changes (bank/vendor close), with an in-panel notice explaining the reset.
- **Preset name visibility**: Saved preset dropdown now shows the active preset name after loading or saving.
- **Bulk selection fixes**: "Select Visible" button now correctly selects all visible rows; removed "Select All" to prevent selecting blocked rows.
- **Scrollbar fix**: Transfer tab scrollbar now correctly reflects full list length (was using hard-coded visible row count).
- **Lua language-server config**: Fixed to enable undefined-field diagnostics instead of disabling all to work around false positives.
- **Upgrade filter API fix**: Replaced removed `GetInventoryItemLevel` API with `C_Item.GetCurrentItemLevel` (patch 12.x).
- **Slot/Armor Type filter fix**: Resolved forward-reference error that caused Lua errors when using Slot or Armor Type filters.

### Implemented for 0.6.0

- **Quick tasks**: Five built-in route/filter setups cover the most common deposit, withdrawal, vendor, and Warband workflows.
- **Complete saved workflows**: Saved entries now include Source, Destination, every filter, Actionable only, query fields, and sort order while retaining legacy custom presets.
- **Progressive filter disclosure**: Search, item level, Actionable only, and sorting remain visible; categorical filters live in an expandable drawer with an active count.
- **Result funnel**: Source, matching, movable, blocked, and selected counts make each narrowing stage visible.
- **Contextual empty states**: Missing scans, empty storage, filter exclusions, and hidden blocked results now have distinct explanations.
- **Contextual primary action**: The footer says Deposit, Withdraw, Move, or Sell and includes the selected count and vendor value where applicable.
- **Route swap and sorting**: Non-vendor routes can be reversed, and results can be sorted by six useful dimensions.
- **Event-driven refresh**: Bank-open scans and debounced bag/bank change events keep visible data current; the panel reports refresh and transfer status.
- **Context lifecycle**: Source/Destination options refresh as bank or vendor access changes, and a panel opened from those contexts closes when the context closes.

## 4. Current Friction Areas

### A. Block-reason Breakdown

Status: Open — the result funnel shows total blocked rows, while detailed reasons remain per-item.

Potential next step: add a compact breakdown such as "3 protected, 2 no space" without crowding the primary list.

Priority: P2

### B. Workflow Management

Status: Open — workflows can be saved, overwritten, loaded, and removed, but not reordered or duplicated.

Potential next step: add lightweight rename/duplicate controls only if real use shows the current name-overwrite model is limiting.

Priority: P3

### C. Scan Freshness

Status: Partial — inventory changes refresh automatically while context permits, but freshness is expressed as a timestamp/status rather than a confidence indicator.

Potential next step: flag bank results as stale after changing characters or when the bank has not been opened in the current session.

Priority: P2

## 5. Safety Guardrails to Preserve

Do not remove:

- Explicit user selection before action
- Rule-based hard blocks (`Protect`, `Ignore`, `Never Sell`)
- Context checks (bank/vendor/combat)
- Conservative defaults for ambiguous content

The roadmap should improve speed and clarity without relaxing core safety principles.

## 6. Acceptance Criteria for AH Pull UX

A successful AH pull UX should satisfy all:

1. From bank, user can load the built-in "Pull Auctionable BoEs" quick task.
2. List shows only auctionable BoE items.
3. WuE items are excluded unless explicitly requested.
4. Selected items are immediately transferable.
5. Empty states explain exactly why no rows are shown.

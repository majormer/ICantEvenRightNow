# UX Improvement Roadmap

## 1. Context

This document tracks UX friction and improvement opportunities as the addon evolves. Items marked **Done** were addressed during the 0.3.0 or 0.4.0 cycles.

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

## 4. Current Friction Areas

### A. Empty-state Explanations

Status: Partial — block reasons exist per-row, but top-level empty states ("0 items") do not yet summarize why.

Proposed:

- Show a count summary when list is empty: e.g. "12 items filtered out — 3 blocked by rules, 9 outside Expansion filter."
- Distinguish between: no scan data, nothing passes filters, all rows blocked.

Priority: P1

### B. Scan on Context Open

Status: Deferred — the addon does not auto-scan when a bank or vendor window opens.

Proposed:

- When bank window opens and last scan is stale, trigger a background bank scan automatically.
- Show a brief notice when an auto-scan completes.

Priority: P1

### C. Auto-close Stale Context

Status: Partial — Source/Destination dropdowns now validate and reset to valid defaults with in-panel notices when context changes (bank/vendor close).

Remaining:

- Context notices are shown but dropdowns are not automatically cleared mid-session without user interaction.

Priority: P2 (deferred; current validation with notices provides good UX)

### D. Workflow-specific Footer Actions

Status: Not started.

Proposed:

- Contextual button label text, for example "Bank Selected" when Destination is Bank, "Sell Selected" when Destination is Vendor.

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

1. From bank, user can run one command or load a saved preset.
2. List shows only auctionable BoE items.
3. WuE items are excluded unless explicitly requested.
4. Selected items are immediately transferable.
5. Empty states explain exactly why no rows are shown.

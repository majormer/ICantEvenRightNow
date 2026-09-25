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

Potential next step: flag bank results as stale after changing characters or when the bank has not been opened in the current session. Addressed structurally by W1 below.

Priority: P2

## 5. Planned: Warband Workflows (target 0.7.0)

### Principle: the Warband bank is for sharing

The Warband bank is the only storage every character on the account can reach, across realms and factions. An item belongs there when **another character benefits from it**, not merely because it is allowed there. Otherwise the character bank is the better home: it is per-character space, and it keeps shared space free for what actually needs sharing.

Items with a real reason to be in Warband storage:

- **Warbound and Warbound-until-equipped items**: the Warband bank is how they reach another character.
- **Crafting reagents**: usable directly from the Warband bank for crafting and crafting orders, so any crafter on the account can use them without withdrawing.
- **Unbound BoE gear and tradeable goods**: the account's designated seller or an alt who can use them can collect them.
- **Consumables and materials shared by several alts.**

Items without a reason to be there: soulbound items (not allowed), items only this character uses, and old gear whose appearance is already collected (transmog is account-wide, so the item itself is not needed to keep it).

The current evaluator already leans this way (shared crafting materials, BoE, and Warbound items go to Warband storage). The roadmap below makes the "who benefits" question answerable.

### W1. Per-character and account snapshots (foundation)

Status: Planned. Priority: P1.

Problem: scans live in account-wide SavedVariables without a character key, so an alt can see another character's character-bank data until it opens a bank. Nothing is known about other characters.

Plan:

- Store bags and character bank per character (`Name-Realm`), and the Warband bank once per account, each with a scan time.
- Record lightweight character facts for routing: class, level, professions.
- Label all non-live data with its age ("Warband bank, scanned 2 days ago"). Snapshots are display-only; actions keep verifying the live slot.
- Migrate the existing single scan to the current character on first load.

### W2. Warband tabs as first-class Source/Destination

Status: Planned. Priority: P1.

- Read Warband tab data with `C_Bank.FetchPurchasedBankTabData(Enum.BankType.Account)` (available only at a banker) and cache it with the account snapshot.
- Offer each tab by its player-given name and icon, like character-bank tabs, alongside "Warband Bank (All Tabs)".

### W3. Tab-settings routing

Status: Planned. Priority: P1.

- Warband tabs carry the player's own "assign to" settings (`depositFlags`: Equipment, Consumables, Profession Goods, Reagents, Junk, Current/Legacy expansion).
- A "Deposit to Warband" quick task routes each item to the matching tab, showing why per row (e.g. "→ Mats (tab accepts Reagents)").
- No new configuration: it follows choices already made in Blizzard's tab settings. Preview and confirmation are unchanged.
- Do not use `C_Bank.AutoDepositItemsIntoBank`; it bypasses item rules and preview.

### W4. Alt hand-off queue

Status: Planned. Priority: P2. Depends on W1.

- On character A, mark items "for Alt B"; they travel through the normal Warband deposit.
- On character B at a bank, a "Waiting for you (N)" quick task appears, pre-filtered to those items. Nothing is withdrawn without confirmation.
- The queue records intent only; stale entries (item gone, withdrawn elsewhere) clear themselves on the next Warband scan.

### W5. Cross-character "Where is it?"

Status: Planned. Priority: P2. Depends on W1.

- Search all snapshots: "Also on: Alt B (bags), Warband: Mats (2 days ago)".
- Tooltip line on items that other characters also hold.

### W6. "Who benefits" routing hints

Status: Idea. Priority: P3. Depends on W1.

- Use snapshot character facts to explain Warband routing: "Reagent for Tailoring (Alt C)", "Plate upgrade for Alt D", "No other character uses this; keep in character bank".
- Hints only: they explain and pre-filter, and never move items on their own.

## 6. Safety Guardrails to Preserve

Do not remove:

- Explicit user selection before action
- Rule-based hard blocks (`Protect`, `Ignore`, `Never Sell`)
- Context checks (bank/vendor/combat)
- Conservative defaults for ambiguous content

The roadmap should improve speed and clarity without relaxing core safety principles.

## 7. Acceptance Criteria for AH Pull UX

A successful AH pull UX should satisfy all:

1. From bank, user can load the built-in "Pull Auctionable BoEs" quick task.
2. List shows only auctionable BoE items.
3. WuE items are excluded unless explicitly requested.
4. Selected items are immediately transferable.
5. Empty states explain exactly why no rows are shown.

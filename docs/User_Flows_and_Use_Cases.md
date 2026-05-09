# User Flows and Use Cases

## 1. Product Fit Summary

The addon is strongest when users want to:

- Classify a large mixed inventory with conservative safety defaults
- Move filtered subsets across storage tiers in controlled batches
- Use explicit selection instead of one-click automation
- Build repeatable behavior with item-level rules over time
- Save common filter configurations for fast recall across sessions

It is not optimized for:

- Fully automated cleanup without any review
- Instant "do everything" actions

## 2. User Personas

### A. Auction House Character Operator

Goal:

- Pull auctionable BoE items from bank quickly
- Avoid accidentally pulling WuE or soulbound items

Primary flow:

- Transfer tab, Source: Bank (All Tabs), Destination: Bags, Binding filter: BoE

Common friction:

- BoE vs WuE differentiation must be precise to avoid wasted pulls
- Requires a fresh bank scan if the bank has not been scanned recently

Saved preset opportunity:

- Save Binding=BoE, Expansion=All as "AH Pull" for one-click setup (not a default; must be saved once)

### B. Main Character Cleanup Pass

Goal:

- Bank old expansion clutter from bags
- Keep active/current gear and consumables unblocked

Primary flow:

- Transfer tab, Source: Bags, Destination: Bank (All Tabs), Expansion filter: Not current

Common friction:

- Some expected items require a Protect rule to keep them out of the filtered list
- Requires a fresh bag scan

Saved preset opportunity:

- Default preset "Old Gear Dump" covers this case out of the box

### C. Warband Storage Consolidator

Goal:

- Move warband-eligible items (WuE, old BoE, old account-transferable) from private bank to Warband Bank
- Make gear available to alts without bag juggling

Primary flow:

- Transfer tab, Source: Bank (Private), Destination: Warband Bank, Binding filter: WuE or leave at All

Common friction:

- Requires bank to be open
- Warband Bank must have free slots; private bank items that are soulbound will be blocked automatically

### D. Gear Upgrade Scout — Identify upgrades in bags

Goal:

- Find gear in bags that beats currently equipped items before deciding to bank, equip, or vendor it

Primary flow:

- Transfer tab, Source: Bags, Destination: Bank (or leave unset for review only), Upgrade filter: Upgrade
- Optionally narrow by Slot

Saved preset opportunity:

- Default preset "Upgrade Check" covers this case out of the box

### E. Gear Upgrade Scout — Pull potential upgrades from bank

Goal:

- Retrieve bank items that beat current equipped gear for testing

Primary flow:

- Transfer tab, Source: Bank (All Tabs), Destination: Bags, Upgrade filter: Upgrade
- Optionally narrow by Slot and ilvl Min

Common friction:

- Requires a bank scan first
- Only equippable gear with a higher item level than the current equipped slot will appear

### F. Bank Organizer

Goal:

- Recall specific bank items to bags for use, AH, or vendor prep
- Does not involve cross-tier bank sorting (private ↔ Warband); see Warband Consolidator flow

Primary flow:

- Transfer tab, Source: Bank (All Tabs or a specific bank tab), Destination: Bags
- Use search, type, or expansion filters to narrow

Common friction:

- Storage model can vary by patch/client API
- Bank tab availability differs across characters
- `/icanteven organize` is a preset that opens this same bank→bags recall view

### G. Vendor Cleanup User

Goal:

- Sell old low-value items at a vendor without accidentally selling current or valuable gear

Primary flow:

- At vendor: Transfer tab, Source: Bags, Destination: Vendor
- Apply Expansion: Not current and/or Type: Consumable filters to narrow safely
- Enable Actionable only to see only items that can be sold right now

Key behavior to understand:

- The Transfer pipeline with Destination=Vendor allows any item with a sell price through, including gear. Users are responsible for applying appropriate filters.
- The Never Sell rule is the durable long-term guard against repeat mistakes
- Vendor context must be open; the addon detects the merchant window automatically

## 3. End-to-End Flow Maps

> **Scanning prerequisite**: The Transfer list works from cached scan data. Scan the relevant scope before using the Transfer tab. The Transfer tab has its own "Scan Bags" and "Scan Bank" buttons next to the Source/Destination dropdowns. You can also use `/icanteven scan [bags|bank|all]` or the buttons on the Summary tab.

### Flow A: AH Pull (BoE recall from bank)

Steps:

1. Open bank
2. Open Transfer tab → click "Scan Bank" (or scan bank from Summary tab first)
3. Source: Bank (All Tabs), Destination: Bags
4. Load saved "AH Pull" preset if you have one, or set Binding filter to BoE
5. Enable "Actionable only" to hide blocked items
6. Select visible rows
7. Transfer selected to bags
8. Go to AH and list

Friction points:

- Bank must be open; otherwise all bank rows are blocked ("Bank is not open")
- The "AH Pull" preset is user-saved, not a default — create it once under any name after step 4

### Flow B: Legacy Bag Cleanup

Steps:

1. Open bank
2. Open Transfer tab → click "Scan Bags" (bag scan is the critical one; bank scan is optional for Summary accuracy)
3. Source: Bags, Destination: Bank (All Tabs)
4. Load "Old Gear Dump" preset or set Expansion filter to Not current
5. Enable "Actionable only"
6. Review the list; add Protect rules for anything that should stay in bags
7. Select rows and Transfer selected
8. Bank must be open or items will appear blocked ("Bank is not open")

Why this flow works well:

- Expansion filter maps directly to "things I probably don't need in bags anymore"
- Selection stays explicit; nothing moves without confirmation

### Flow C: Upgrade Scouting — Review bags

Steps:

1. Scan bags (Transfer tab "Scan Bags" button or Summary tab)
2. Transfer tab → Source: Bags, Destination: Bank (if banking non-upgrades)
3. Load "Upgrade Check" preset or set Upgrade filter to Upgrade
4. Optionally narrow by Slot for a specific slot comparison
5. Inspect the filtered list — these items beat what you have equipped
6. Transfer non-upgrades to bank, or simply equip upgrade candidates directly from bags

Why this flow works well:

- The upgrade filter uses the actual equipped item level as a baseline; two-slot types (rings, trinkets) use the weaker of the two equipped items
- Slot filter lets you focus on a single comparison without noise from other slots

### Flow D: Upgrade Scouting — Pull from bank

Steps:

1. Open bank → scan bank (Transfer tab "Scan Bank" or Summary tab)
2. Transfer tab → Source: Bank (All Tabs), Destination: Bags
3. Set Upgrade filter to Upgrade; optionally narrow by Slot or ilvl Min
4. Select candidates and transfer to bags
5. Try items on in bags; bank or vendor what doesn't fit the character

Why this flow works well:

- Brings only items that beat current gear into bags, keeping clutter minimal
- The ilvl Min filter lets you set a floor (e.g. "only pull gear 600+")

### Flow E: Warband Storage Consolidation

Steps:

1. Open bank → scan bank
2. Transfer tab → Source: Bank (Private), Destination: Warband Bank
3. Set Binding filter to WuE (Warbound Until Equipped) for WuE items, or leave at All and use the list's block reasons to identify ineligible items
4. Enable "Actionable only" to skip soulbound or otherwise blocked items
5. Select rows and transfer

Why this flow works well:

- Makes old BoE and WuE gear accessible to alts through Warband Bank without manual mailing
- Block reasons explain exactly why specific items cannot move (soulbound, protect rule, no Warband slots)

### Flow F: Vendor Liquidation

Steps:

1. At vendor: Transfer tab → Source: Bags, Destination: Vendor
2. Apply Expansion: Not current and Type: Consumable filters for conservative selling
3. Enable "Actionable only"
4. Review the remaining list carefully — any item with a sell price can appear
5. Select rows and Transfer (sell) selected
6. Add Never Sell rules to any item that showed up unexpectedly

Why this flow works well:

- Explicit selection lowers accidental selling risk
- Never Sell rule provides a durable safety net for future scans
- Context is automatically detected when the vendor window is open

## 4. Use Case Matrix

| Use Case | Source | Destination | Core Filters | Default Preset |
| --- | --- | --- | --- | --- |
| AH BoE pull | Bank (All Tabs) | Bags | Binding=BoE | — (user-saved) |
| Legacy bag cleanup | Bags | Bank (All Tabs) | Expansion=Not current | Old Gear Dump |
| Upgrade review (bags) | Bags | Bank or none | Upgrade=Upgrade | Upgrade Check |
| Upgrade pull (bank) | Bank (All Tabs) | Bags | Upgrade=Upgrade | Upgrade Check |
| Warband consolidation | Bank (Private) | Warband Bank | Binding=WuE or All | — |
| Bank recall / organize | Bank (All Tabs) | Bags | Search, Type | — |
| Vendor liquidation | Bags | Vendor | Expansion=Not current, Type=Consumable | — |
| Exception control | — | — | Rules tab (item-ID based) | — |

## 5. Where the Addon is Most Valuable

Most valuable scenarios:

- Repeated inventory maintenance across many characters
- Users who care about safety and visibility over speed
- Users who want deterministic, teachable behavior with rules
- Users who run the same cleanup pattern repeatedly (saved filter presets eliminate repetitive setup)

Less valuable scenarios:

- Users wanting instant fully automatic sorting with no review
- One-off users with very small inventories and no bank discipline

## 6. Behavioral Principles for Future UX

- Manual intent should never be silently blocked; block reasons must be visible per row
- Filters should map to player vocabulary (BoE, WuE, current, old, bank, bags)
- "No rows" states should explain whether the cause is a missing scan, active filters, or context gating
- High-frequency flows should be accessible via saved presets or slash commands to reduce repetitive setup
- The Transfer tab's conservative scope (manual selection, per-item block reasons) is a feature, not a limitation

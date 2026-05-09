# Technical Architecture

## 1. Purpose and Architecture Style

I Can't Even Right Now is a standalone WoW Retail addon focused on conservative inventory management.

Architecture characteristics:

- Multi-module runtime: `Shared` → `Evaluator` → `Filter` → `Scanner` → `Transfer` → `UI` → `Core`
- Static configuration and defaults in `Data.lua`
- Optional diagnostics in `Debug.lua`
- SavedVariables persistence in `ICantEvenRightNowDB`
- UI-first interaction model with explicit selection before actions
- All inter-module symbols exposed on `ns.Private` (aliased as `P` in each module)

Design intent:

- Transfer intent is always player-driven (Source + Destination chosen explicitly)
- Prefer explainability over automation
- Keep risky actions conservative and contextual

## 2. Runtime Modules

### `Data.lua`

Primary responsibilities:

- Expansion definitions and current expansion marker
- Item type and action constants
- Curated item overrides
- Profession subclass mapping
- Default DB schema (`DefaultDB`)

### `Debug.lua`

Primary responsibilities:

- Debug mode toggles
- Diagnostic dump helpers

### `Shared.lua`

Primary responsibilities:

- Display/identity constants and storage-kind string constants
- Filter sentinel values and scope constants
- Bag ID resolution: `BAG_IDS`, `PRIVATE_BANK_IDS`, `REAGENT_BANK_IDS`, `WARBAND_BANK_IDS`, `NORMAL_BAG_IDS`
- Bank tab data refresh (`RefreshBankTabData`, `BANK_TAB_DATA`)
- Context detection: `IsBankContextDetected`, `IsPlayerBankInteractionActive`, `IsBankViewableByAPI`, `IsBankStorageAccessible`
- Storage helpers: `GetStorageBagIDs`, `GetStorageDisplayName`, `GetStorageKindForBagID`
- Utility functions: `Print`, `FormatTimestamp`, `LocationKey`, `SlotKey`, `SafeCopyDefaults`
- Expansion helpers: `IsCurrentExpansion`, `IsOldExpansion`, `IsUnknownExpansion`, `GetExpansionName`

### `Evaluator.lua`

Primary responsibilities:

- Binding detection (`GetBindingDetails`): soulbound, warband-bound, BoE, WuE, BoP classification
- Item classification: `GetItemTypeTag`, `GetAllDecisions`, `BuildDecision`
- Curated item lookups (`FindCuratedItem`)
- Rule helpers (`EnsureRule`)
- Preferred bank storage routing (`GetPreferredBankStorage`)
- Shared-value item detection (`IsTransferableSharedValueItem`)

### `Filter.lua`

Primary responsibilities:

- Filter state management (`EnsureTabFilters`, lazy init per tab)
- Filter mutations: `SetFilterInclude`, `SetFilterSearch`, `SetFilterHideBlocked`, `SetFilterItemLevel`, `SetFilterSlot`, `SetFilterUpgrade`, `ResetTabFilters`
- Filter matching: `MatchesTabFilters`, `PlanMatchesTabFilters`
- Option builders: `GetExpansionOptions`, `GetBindFilterOptions`, `GetTypeFilterOptions`, `GetSlotFilterOptions`, `GetUpgradeFilterOptions`
- Upgrade detection: `GetEquippedItemLevel`, `INVTYPE_TO_SLOTS` mapping
- Slot label mapping: `EQUIPLOC_TO_SLOT_LABEL`
- Saved filter presets: `SeedDefaultSavedFilters`, `GetSavedFiltersOptions`, `FindSavedFilter`, `ApplySavedFilter`, `SaveFilter`, `DeleteSavedFilter`
- Label helpers: `GetExpansionFilterLabel`, `GetMultiSelectLabel`, `BuildFilterSummary`

### `Scanner.lua`

Primary responsibilities:

- Container scanning: `ScanContainerBag`, `ScanBags`, `ScanBank`
- Cache-warm rescan scheduling (`ScheduleRescanAfterMove`)
- Optimistic scan removal (`RemoveMovedItemsFromScan`)
- Bank diagnostics slash helpers

### `Transfer.lua`

Primary responsibilities:

- Transfer candidate generation (`GetTransferCandidates`)
- Block reason evaluation (`GetTransferBlockReason`)
- Free slot finding (`FindFreeSlot`)
- Movement execution: `ExecuteTransferOne`, `ExecuteTransferSelected`
- Vendor sell execution (via `C_Container.UseContainerItem` from hardware event context)
- Source/Destination option builders: `GetTransferSourceOptions`, `GetTransferDestOptions`
- Dropdown refresh (`RefreshTransferDropdowns`) on context change

### `UI.lua`

Primary responsibilities:

- All frame construction (`BuildSummaryTab`, `BuildTransferTab`, `BuildRulesTab`, `BuildSettingsTab`)
- Per-tab refresh: `Core.RefreshSummary`, `Core.RefreshTransfer`, `Core.RefreshRules`
- Transfer tab: FauxScrollFrame scrollable list (8 visible rows, `ROW_HEIGHT = 42`)
- Transfer tab filter row: Expansion, Type, Binding, Slot, Upgrade dropdowns
- Transfer tab presets row: Load dropdown, name EditBox, Save and Remove buttons
- Quick-access minimap launcher construction and updates
- Context notice display

### `Core.lua`

Primary responsibilities:

- Addon lifecycle (`Core.OnAddonLoaded`)
- DB initialisation: `SafeCopyDefaults(Data.DefaultDB, ...)` + `MigrateLegacyTabFilters` + `SeedDefaultSavedFilters`
- Event registration and dispatch
- Context detection updates (`Core.UpdateContext`)
- Inventory scanning entry point (`Core.ScanInventory`)
- Transfer execution entry points (`Core.ExecuteTransferOne`, `Core.ExecuteTransferSelected`)
- Slash command registration and handling
- UI coordination (`Core.CreateUI`, `Core.RefreshUI`)

## 3. SavedVariables Data Model

Root object: `ICantEvenRightNowDB`

Key sections:

- `rules.items`: Item-ID-specific behavior overrides
- `context`: Live interaction/combat state flags
- `lastScan`: Timestamps for bags and bank scans
- `scans.bags` and `scans.bank`: Last scanned item records
- `ui`: UI preferences and active filter state (`ui.tabFilters`)
- `savedFilters`: Array of named filter presets `{ name, expansion, bind, type, slot, upgrade }`
- `savedFiltersSeeded`: Bool — true after default presets are written once
- `errorLog`: Capped array of Lua error entries `{ time, msg }`

Rule schema (per itemID):

- `protect`
- `neverSell`
- `ignore`
- `expansionOverride`
- `notes`
- `createdFrom`

Filter state schema (per tab, under `ui.tabFilters[tabName]`):

- `expansion.include`: expansion ID, `EXPANSION_FILTER_ALL`, `EXPANSION_FILTER_NOT_CURRENT`, or `EXPANSION_FILTER_UNKNOWN`
- `bind.include`: `BIND_FILTER_ALL`, `"BoE"`, `"WuE"`, `"Soulbound"`, `"Warbound"`, `"BoP"`
- `type.include`: `"All"` or multi-select table
- `slot.include`: `"All"` or multi-select table of slot labels
- `upgrade.include`: `"All"`, `"Upgrade"`, or `"Not Upgrade"`
- `itemLevel.min`, `itemLevel.max`: optional numeric bounds (equippable gear only)
- `name.includeText`, `name.excludeText`: search strings
- `hideBlocked`: bool

## 4. Container and Storage Model

Storage tiers represented internally:

- Bags
- Private Bank
- Reagent Bank (only when distinct IDs are present in the client)
- Warband Bank
- Bank (All Tabs) — convenience aggregate for source/dest selection
- Bank: [named tab] — individual bank tabs resolved from `C_Bank` API

Container IDs are resolved from `Enum.BagIndex` and refreshed in `RefreshBankTabData`. Overlap removal and compatibility fallbacks are handled in `Shared.lua`.

## 5. Scan Pipeline

Entry point: `Core.ScanInventory(scope, quiet)`

High-level sequence:

1. Refresh context
2. Resolve scan scope (`bags`, `bank`, `all`)
3. Validate required context (bank must be open for bank scan)
4. Scan container slots using `C_Container` APIs
5. Build per-item records with metadata from `GetItemInfo`
6. Enrich binding details via `GetBindingDetails`
7. Save scan results to `ns.DB.scans`
8. Schedule cache-warm rescan when item info is incomplete

Scan record fields include:

- identity: `itemID`, `name`, `link`, `icon`, `quality`, `count`
- location: `scope`, `bagID`, `slot`, `storageKind`, `location`
- item metadata: `itemLevel`, `equipLoc`, `classID`, `subclassID`, `maxStack`, `sellPrice`, `expansionID`
- binding metadata: `isBound`, `isSoulbound`, `isWarbandBound`, `accountBankAllowed`, `bindingScope`

## 6. Transfer Pipeline

Entry point: player selects Source, Destination, and filters in the Transfer tab.

`GetTransferCandidates(source, dest)` produces a list of plan objects:

- `plan.item`: the scanned item record
- `plan.movable`: bool — can this item be transferred right now
- `plan.blocked`: string — human-readable block reason if not movable
- `plan.key`: unique location key for selection tracking

`GetTransferBlockReason(item, source, dest)` checks in order:

1. Protect rule
2. Context (bank closed, vendor closed, combat)
3. Source/dest scope mismatch
4. Never Sell rule (when dest is Vendor)
5. Free slot availability
6. Filter applicability

Execution calls `C_Container.PickupContainerItem` for moves or `C_Container.UseContainerItem` for vendor sells (hardware event context required for vendor).

After execution: `ScheduleRescanAfterMove` + `Core.RefreshUI`.

## 7. Filter System

All filter state lives in `ns.DB.ui.tabFilters[tabName]`, lazily initialised by `EnsureTabFilters`.

Matching is stateless: `MatchesTabFilters(item, tabName)` and `PlanMatchesTabFilters(plan, tabName)` read the DB directly.

Saved filter presets:

- Stored in `ns.DB.savedFilters` as an ordered array
- Each preset stores: `name`, `expansion`, `bind`, `type`, `slot`, `upgrade`
- ilvl range and search text are intentionally excluded (too query-specific for reuse)
- `SeedDefaultSavedFilters` writes two defaults on first load: "Old Gear Dump" and "Upgrade Check"
- Applying a preset calls `ApplySavedFilter(preset, tabName)`, then `Core.RefreshUI`

## 8. UI Model
- `scans.bags` and `scans.bank`: Last scanned item stacks
- `ui`: UI preferences and active filters

Rule schema (per itemID):

- `protect`
- `neverSell`
- `ignore`
- `expansionOverride`
- `notes`
- `createdFrom`

## 4. Container and Storage Model

Storage tiers represented internally:

- Bags
- Private Bank
- Reagent Bank (only when distinct IDs exist)
- Warband Bank

Container IDs are resolved from `Enum.BagIndex` with compatibility fallbacks and overlap removal.

Important compatibility behavior:

- Aggregate tab IDs are avoided for primary scanning where possible
- If reagent bank container IDs are absent in client API, reagent storage rows are normalized to private bank

## 5. Scan Pipeline

Entry point: `Core.ScanInventory(scope, quiet)`

High-level sequence:

1. Refresh context
2. Resolve scan scope (`bags`, `bank`, `all`)
3. Validate required context (bank must be open for bank scan)
4. Scan container slots using `C_Container` APIs
5. Build per-item records with metadata from `GetItemInfo`
6. Enrich binding details (including account-bank eligibility and WuE checks)
7. Save scan results
8. Optionally schedule cache-warm rescan when item info is incomplete

Scan record fields include:

- identity: `itemID`, `name`, `link`
- location: `scope`, `bagID`, `slot`, `storageKind`, `location`
- item metadata: quality, class/subclass, maxStack, sellPrice, expansionID
- binding metadata: `isBound`, `isSoulbound`, `isWarbandBound`, `accountBankAllowed`, `bindingScope`

## 6. Decision Engine

Entry point: `BuildDecision(item)`

Decision outputs:

- recommendation (`BANK`, `RECALL`, `REVIEW`, `BLOCKED`, etc.)
- recommended action (`Bank`, `Recall`, `Review`, `None`)
- group label for list ordering
- reason text and blocked reasons
- eligibility flags (`eligibleForBankMove`, `eligibleForRecall`)
- preferred bank storage target for banking moves

Decision order emphasizes:

1. User rule overrides
2. Hard protection (quest, mythic key, soulbound equipment)
3. Curated exceptions
4. Expansion + type heuristics
5. Transferability and storage targeting

Current notable behavior:

- Move-tab manual actions (dump and recall) are not gated by recommendation state
- Recommendation is a display/sorting signal, while rule/context/capacity checks gate actionability
- WuE filtering and routing is supported as a first-class path

## 7. Move/Organize/Vendor Execution Paths

### Move tab

- `MoveOneItem` for row-level actions
- `MoveSelected` for batch actions
- Separate logic paths for dump vs recall
- Uses optimistic local removal plus scheduled rescans

### Organize tab

- Builds bank-to-bank plans with target tier recommendations
- Executes selected plans through container pickup operations

### Vendor tab

- Supports recall from bank for vendor prep
- Supports sell at merchant when vendor context is active

## 8. UI Model

Tabbed frame (4 tabs):

- Summary
- Transfer
- Rules
- Settings

UI state is persisted in DB filters and toggles.

Transfer tab layout:

1. Source / Destination dropdowns (context-gated: bank options hidden unless bank is open; vendor hidden unless vendor is open)
2. Preset row: "Preset:" dropdown to load a saved filter, name EditBox, Save and Remove buttons
3. Filter rows: Expansion, Type, Binding, Slot, Upgrade dropdowns; ilvl min/max inputs; Search text
4. Action row: "Actionable only" toggle, Transfer All, Transfer Selected, Deselect All buttons
5. Scrollable item list: FauxScrollFrame, 8 visible rows, each row shows item link, item level, binding, and block reason

Interaction model:

- Source/Destination determines candidates; filters narrow them
- "Actionable only" hides blocked rows for focused batch operations
- Hard blockers come from Protect rules, context, capacity, and Never Sell rules
- Per-row block reason text explains why an item cannot be transferred

Quick access behavior:

- Minimap launcher supported
- Bank/vendor launcher buttons intentionally disabled

## 9. Slash Command Surface

Core command groups:

- open and scan: `/icanteven`, `/icanteven scan [bags|bank|all]`
- tab navigation: `summary`, `transfer`, `rules`, `settings`
- mode presets: `dump [expansion]`, `recall [expansion]`, `organize`, `vendor`
- quick access: `minimap`, `buttons`
- diagnostics: `debug`, `diag`, `bankdiag`
- error log: `errors`, `clearerrors`

## 10. Strengths and Constraints

### Strengths

- Conservative defaults reduce accidental destructive actions
- Good explainability (block reasons surfaced per item)
- Single Transfer tab replaces the old three-tab Move/Organize/Vendor split
- Filter system is comprehensive: Expansion, Binding, Type, Slot, Upgrade, ilvl, Search
- Saved filter presets reduce repetitive setup for common workflows
- Works across modern and shifting bank API layouts

### Constraints

- Transfer intent is always manual (no automated execution)
- Depends on asynchronous WoW data settlement and frame timing
- Filter semantics are comprehensive but can require multiple dropdowns for precise targeting

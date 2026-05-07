# Technical Architecture

## 1. Purpose and Architecture Style

I Can't Even Right Now is a standalone WoW Retail addon focused on conservative inventory management.

Architecture characteristics:

- Single-module runtime orchestration in `Core.lua`
- Static configuration and defaults in `Data.lua`
- Optional diagnostics in `Debug.lua`
- SavedVariables persistence in `ICantEvenRightNowDB`
- UI-first interaction model with explicit selection before actions

Design intent:

- Keep recommendation and execution separate
- Prefer explainability over automation
- Keep risky actions conservative and contextual

## 2. Runtime Modules

### `Core.lua`

Primary responsibilities:

- Context detection (bank/vendor/combat/frame state)
- Inventory scanning for bags and bank containers
- Decision engine and recommendation generation
- Move/organize/vendor planning and execution
- UI creation and per-tab refresh logic
- Slash command handling
- Quick-access launcher management (minimap only in current behavior)

### `Data.lua`

Primary responsibilities:

- Expansion definitions and current expansion marker
- Item type, recommendation, and action constants
- Curated item overrides
- Profession subclass mapping
- Default DB schema

### `Debug.lua`

Primary responsibilities:

- Debug mode toggles
- Diagnostic dump helpers

## 3. SavedVariables Data Model

Root object: `ICantEvenRightNowDB`

Key sections:

- `rules.items`: Item-ID-specific behavior overrides
- `context`: Live interaction/combat state flags
- `lastScan`: Timestamps for bags and bank scans
- `scans.bags` and `scans.bank`: Last scanned item stacks
- `ui`: UI preferences and active filters

Rule schema (per itemID):

- `protect`
- `neverMove`
- `neverSell`
- `ignore`
- `expansionOverride`
- `actionOverride`
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

Tabbed frame:

- Summary
- Move
- Organize
- Vendor
- Rules
- Settings

UI state is persisted in DB filters and toggles.

Interaction model:

- Rows can be selected for manual movement even when not currently recommended
- Hard blockers come from rules, context, and capacity checks
- Footer actions are enabled only when context and selection permit
- Tooltips explain reasons and blockers

Current quick access behavior:

- Minimap launcher supported
- Bank/vendor launcher buttons intentionally disabled

## 9. Slash Command Surface

Core command groups:

- open and scan: `/icanteven`, `/icanteven scan`
- tab navigation: `summary`, `move`, `organize`, `vendor`, `rules`, `settings`
- mode presets: `dump`, `recall`
- quick access: `minimap`, `buttons`
- diagnostics: `debug`, `diag`, `bankdiag`

## 10. Strengths and Constraints

### Strengths

- Conservative defaults reduce accidental destructive actions
- Good explainability (reasons and blockers surfaced)
- Multi-tab flows cover major cleanup patterns
- Works across modern and shifting bank API layouts

### Constraints

- Single large `Core.lua` creates coupling across concerns
- Recommendation logic and actionability logic can conflict in UX
- Depends on asynchronous WoW data settlement and frame timing
- Filter semantics are powerful but currently not workflow-optimized

## 11. Refactor Opportunities

Recommended technical decomposition:

- `scan.lua`: container discovery and scanning
- `decision.lua`: recommendation engine and policy checks
- `plans.lua`: move/organize/vendor plan generation
- `ui/*.lua`: per-tab rendering and interactions
- `commands.lua`: slash command routing

This split would reduce regressions when changing one workflow (for example AH recall) without destabilizing others.

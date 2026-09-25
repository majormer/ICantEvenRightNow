# Technical Architecture

## 1. Purpose and Architecture Style

I Can't Even Right Now is a standalone WoW Retail addon for low-friction, conservative inventory management.

Architecture characteristics:

- Multi-module runtime in TOC order: `Data` → `Debug` → `Shared` → `Migration` → `Characters` → `Evaluator` → `Reasons` → `Warband` → `Filter` → `Scanner` → `Transfer` → `Tasks` → `UI` → `HomeUI` → `Value` → `Onboarding` → `Integrations` → `Core`
- Account-wide SavedVariables (`ICantEvenRightNowDB`) with an explicit `schemaVersion` and stepwise migrations
- All inter-module symbols on `ns.Private` (aliased as `P`)
- Offline test suite (`tests/`) that loads the TOC files into a simulated WoW client

Design intent:

- The addon finds, explains, and routes; the player reviews and clicks. Nothing moves or sells without explicit selection and a click.
- Prefer explanation over automation: every row says why an item is there and what an action will do.
- Roles decide who benefits; unassigned characters never count.

## 2. Runtime Modules

| Module | Responsibilities |
|---|---|
| `Data.lua` | Expansions, item types, curated items, profession-to-subclass map, `DefaultDB` |
| `Debug.lua` | Debug toggle and diagnostic dump |
| `Shared.lua` | Storage-kind constants (incl. `WarbandTab:<bagID>` and `Warband (by tab settings)`), bag ID resolution (`Enum.BagIndex`), character and Warband tab data (`RefreshBankTabData`), storage helpers, `NeedsBankStorage`, bank context detection, shared UI state |
| `Log.lua` | Enhanced logging (off by default): `P.Log(category, fmt, ...)` into a 2,000-line ring buffer at `ICantEvenRightNowDB.debugLog`; `P.GetLogLines`, `P.ClearLog`, `P.SetLogging`. Keep calls out of hot loops. |
| `Migration.lua` | `SCHEMA_VERSION`, source-version inference, copy-then-swap migration steps, `migrationBackup`, `legacy` parking, migration report |
| `Characters.lua` | Roster keyed `Name-Realm`, character facts (class, armor type, level history, professions, equipped item levels), roles and capabilities, role suggestions, per-character and Warband snapshots (`GetScanList`, `AllSnapshots`) |
| `Evaluator.lua` | Binding detection, item type classification, decisions (`BuildDecision`, `GetAllDecisions`) |
| `Reasons.lua` | "Why is this here?" detectors, time held per location, keep reasons, `ExplainItem`, `/icanteven why` report, who-benefits hints, reason-driven tasks |
| `Warband.lua` | Warband tab routing by `depositFlags`, alt hand-off queue |
| `Filter.lua` | Filter state and matching, upgrade detection, quick tasks (`QUICK_WORKFLOWS`), saved tasks |
| `Scanner.lua` | Container scanning (incl. quest info), bounded item-data retries, time-held and hand-off upkeep after scans |
| `Transfer.lua` | Block reasons, target bags, slot verification, target-slot reservations, moves and sales (12 per click) |
| `Tasks.lua` | Task list (quick, saved, registered), card evaluation (ready/waiting/value), per-refresh evaluation cache, pre-selection |
| `UI.lua` | Console frame and tabs, Transfer view (grouped/compact rows, filters, Save as task), Rules, Settings, minimap launcher, widget kit (`P.UIKit`) |
| `HomeUI.lua` | Home cards and notices, Characters tab, bank/vendor notice, hand-off picker, where-is-it (slash and item tooltip) |
| `Value.lua` | Auction prices (Auctionator, TSM, own paced lookup), freshness, vendor protection, auction advice, value tooltips |
| `Onboarding.lua` | What's New (with migration summary), first-time tips, welcome back, max-level role check, Warband settings hint |
| `Integrations.lua` | Optional BetterBags categories |
| `Core.lua` | Lifecycle, migration and defaults, event wiring, slash commands |

## 3. SavedVariables Data Model

Root: `ICantEvenRightNowDB` (account-wide).

| Key | Contents |
|---|---|
| `schemaVersion` | Current schema (2). Set by `Migration.lua` |
| `rules.items[itemID]` | `protect`, `ignore`, `neverSell`, `keepReason` (`keepsake`/`alt`/`event`/`investment`), `keepUntil`, `name`, `notes`, `createdFrom`, `expansionOverride`, `typeOverride` |
| `characters["Name-Realm"]` | `name`, `realm`, `className`, `classFile`, `armorSubclass`, `level`, `levelHistory`, `professions`, `equipped[slot]`, `role`, `roleSetAt`, `firstSeen`, `lastSeen`, `scans = { bags, bank }`, `lastScan = { bags, bank }`, onboarding flags |
| `warband` | `items` (account snapshot), `scannedAt`, `tabs` (`bagID`, `name`, `flags`) |
| `timeHeld[locationKey]` | `since` and `items[itemID] = firstSeen`; keys `char:<Name-Realm>:bags`, `char:<Name-Realm>:bank`, `warband` |
| `handoff` | `nextID`, `entries` (`itemID`, `name`, `count`, `from`, `to`, `at`, `state`, `depositedAt`) |
| `prices[key]` | `price`, `at`; `c:<itemID>` (commodities, region-wide) or `i:<itemID>:<realm>` |
| `savedFilters` | Saved tasks (route, filters, Actionable only, search, item level, sort); legacy filter-only presets still load |
| `ui` | Transfer filters (`tabFilters.Transfer`), sort, minimap, and settings (`preselectQuickTasks`, `groupIdenticalRows`, `compactRows`, `contextNotice`, `whereTooltip`, `tipsEnabled`, `betterBagsCategories`, price thresholds) |
| `tipsSeen`, `whatsNewSeen` | Onboarding state (account-wide) |
| `migrationBackup[fromVersion]` | Copy of rules, saved presets, and UI settings taken before migrating |
| `migrationReports` | What each migration carried over, converted, or could not port |
| `legacy` | Parked obsolete keys (old UI filters, legacy tab filters, removed rule fields) |
| `errorLog` | Capped Lua error log |

## 4. Storage Model

- Bags: `Enum.BagIndex` 0 to 5 (normal moves use 0 to 4).
- Character bank tabs: 6 to 11 (`BankTab:<bagID>` when tab data is known).
- Warband bank tabs: 12 to 16 (`WarbandTab:<bagID>`); scanned items keep `storageKind = "Warband Bank"`.
- `Bank (All Tabs)` and `Warband Bank` are aggregates; `Warband (by tab settings)` resolves per item to one tab.

## 5. Scan Pipeline

Entry point: `Core.ScanInventory(scope, quiet)`.

1. Refresh context; resolve scope (`bags`, `bank`, `all`); bank scans require the bank.
2. Scan container slots (`C_Container`), including quest info (`GetContainerItemQuestInfo`, completion via `C_QuestLog`) captured for the owning character.
3. Enrich binding details (`GetBindingDetails`).
4. Store bags and character bank on the current character; Warband items on the account snapshot.
5. Record time held per location; clean up stale hand-offs.
6. If item data is missing from the client cache, schedule a bounded retry (`ScheduleItemDataRetry`).

Rescans run when the console opens, at bank and vendor open, and (debounced) on bag and bank slot events.

## 6. Transfer Pipeline

`GetTransferCandidates(source, dest)` builds plans (`item`, `key`, `movable`, `blocked`).

`GetTransferBlockReason` checks: combat; same route; bank or vendor context; vendor-sellable; Warband eligibility; Protect / Ignore / Never Sell rules; equipped and keystone blocks; already in the destination; routing (for `Warband (by tab settings)`); and room in the target bags (cached empty-slot and partial-stack checks per refresh).

Execution (`ExecuteTransferOne`, `ExecuteTransferSelected`):

- `VerifySourceSlot` confirms the scanned item is still in the slot, unlocked, and the cursor is empty; stale slots are skipped and trigger a rescan.
- Moves confirm the pickup before dropping; target slots used by recent moves stay reserved for two seconds.
- Vendor sales use `C_Container.UseContainerItem` from a click, at most 12 per click (buyback limit); the rest stay selected.
- Successful moves notify the hand-off queue and schedule a fallback rescan.

## 7. Tasks and Home

- Tasks come from quick tasks (`Filter.lua`), registered tasks (`P.RegisterTask` from Reasons, Value, Warband), and saved tasks.
- `P.EvaluateTask` counts plans that match the task's filters and predicate: ready (movable now) and waiting (blocked only by context), plus value.
- `P.GetTaskCards` evaluates all tasks inside a shared evaluation cache (one candidate list per route, one explanation per item).
- Home shows cards (ready first, then waiting, then empty) and the top notice from `P.RegisterHomeNotice` providers (What's New, welcome back, role question, tips, price and hand-off reminders, opt-ins).
- `P.OpenTask(name)` applies the task's route and filters, optionally pre-selects safe items, and opens the Transfer view.

## 8. Reasons

`P.ExplainItem(item, ctx)` returns all detected reasons and a primary one. Dispositions: keep, free (can go), review (your call), info. Keep always outranks free; a due investment reminder ranks between them. Gear and materials are never called free until roles are assigned.

## 9. Value

`P.GetAuctionPrice` prefers Auctionator (with age), then TSM, then stored own-lookup prices, and marks freshness (commodities 3 days, items 7 days by default). `P.AuctionAdvice` compares auction net (after 5% cut) with vendor value against a minimum gain (5g). `P.IsValueFlagged` protects vendor sales. The own lookup (`P.StartPriceLookup`) queries only owned, tradeable items, one at a time when the throttle is ready, from a click at the auction house.

## 10. UI Model

Tabs: Home, Transfer, Characters, Rules, Settings.

- Home: context line, scan ages, notice strip, six task cards per page.
- Transfer: task title with "(modified)", route summary, search, Filters and Customize drawers (route, Save as task), grouped or compact rows with reason text, result funnel, contextual action button.
- Characters: roster with role dropdowns, suggestions, Accept all suggestions.
- Rules: Protect, Ignore, Never Sell, and keep reasons.
- Settings: minimap launcher, workflow options, bank/vendor notice mode, tips, BetterBags, command reference.

## 11. Testing

- `tests/run.lua` (plain Lua 5.1) runs `tests/**/test_*.lua`.
- `tests/harness/wow.lua` simulates the client: containers and item cache, cursor and locks, asynchronous server moves, bank tabs, vendor with 12-item buyback, auction house lookups, quests, collections, timers, events, and hardware-event gating for protected calls.
- `tests/harness/frames.lua` records a headless widget tree so UI flows are driven by simulated clicks.
- `scripts/Test-Addon.ps1` runs the suite with the static checks; the pre-commit hook runs it on every commit.
- A real save can be placed in `tests/fixtures/local/` (git-ignored) to exercise migration.

## 12. Constraints

- Transfer intent stays manual: no automated execution.
- Game behavior (secret values, protected actions, server timing, UI rendering) still needs in-game verification; the offline suite reflects the API as documented.
- Characters are known only after logging in once with the addon enabled.

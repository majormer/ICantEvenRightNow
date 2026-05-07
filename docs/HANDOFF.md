# ICantEvenRightNow Handoff

This handoff captures the current 0.2.0 work-in-progress state for I Can't Even Right Now (With My Bags and Bank).

## Project Snapshot

- Addon type: WoW Retail standalone cleanup console
- Runtime files: Core.lua, Data.lua, Debug.lua
- Persistent DB: ICantEvenRightNowDB
- Current branch context: dev includes post-main fixes with no git tag baseline

## Current Product Behavior

- Six tabs: Summary, Move, Organize, Vendor, Rules, Settings.
- Recommendation, eligibility, and selection remain separate.
- Manual Move-tab actions are allowed even when items are not recommended, unless blocked by rule/context/capacity.
- Move Type filter splits BoE and WuE (WuE detection uses live binding checks).
- Bank scanning resolves container IDs with compatibility fallbacks and overlap removal.
- Legacy clients without distinct reagent bank IDs normalize reagent rows to Private Bank.
- Quick-access launchers: minimap supported; bank/vendor frame launchers intentionally disabled.

## High-Value Commands

- /icanteven or /icant
- /icanteven scan [bags|bank|all]
- /icanteven move | organize | vendor | rules | settings
- /icanteven dump <expansion>
- /icanteven recall <expansion>
- /icanteven minimap
- /icanteven buttons
- /icanteven bankdiag (alias: bankids)
- /icanteven debug
- /icanteven diag

## Architecture Notes

- Core.lua is still monolithic and owns scan, decision, UI, commands, and movement execution.
- Data.lua contains constants/defaults and launcher default flags (bank/vendor launchers disabled by default).
- Debug.lua provides diagnostic and debug utilities.
- UI footer state now refreshes immediately when selection checkboxes are clicked.

## Known Risk Areas

- Bank container API variation across clients/patch levels.
- Async settlement after moves can briefly desync visible recommendations before scheduled refresh.
- Any future recommendation changes should avoid reintroducing action-gating regressions in manual workflows.

## Local Test Loop

1. Run .\scripts\Copy-ToWoW.ps1
2. In game, run /reload
3. Validate bank scan + Move dump/recall + Organize + Vendor flows
4. If bank behavior is unexpected, run /icanteven bankdiag and capture output

## Release Notes Source of Truth

- CHANGELOG.md has been consolidated for 0.2.0 based on branch state.
- README.md and docs in docs/ are aligned to current launcher and movement behavior.

# ICantEvenRightNow Handoff

This document is for handing the project from Codex to GitHub Copilot or another coding assistant.

## Project Goal

`I Can't Even Right Now (With My Bags and Bank)` is a standalone World of Warcraft Retail addon for inventory cleanup. It should be a small cleanup console, not a bag replacement and not a BetterBags plugin.

The core loop is:

1. Scan bags and bank.
2. Classify items conservatively.
3. Explain recommendations.
4. Let the player explicitly select items.
5. Move selected items between bags and bank.
6. Let the player create item-ID rules to protect, ignore, or override items.

Selling is intentionally out of scope for the first usable version.

## Current Files Of Interest

- `ICantEvenRightNow.toc`: addon metadata and load order.
- `Data.lua`: expansion metadata, item type constants, action/recommendation constants, default saved variables.
- `Debug.lua`: debug utilities.
- `Core.lua`: current all-in-one implementation for scanning, classification, UI, slash commands, rules, and movement.
- `scripts/Copy-ToWoW.ps1`: ignored local deploy script.
- `scripts/Remove-FromWoW.ps1`: ignored local removal script.

The scripts default to:

```text
F:\Battle.Net\World of Warcraft\_retail_\Interface\AddOns
```

The user wants changes deployed after edits with:

```powershell
.\scripts\Copy-ToWoW.ps1
```

Then they test in WoW with `/reload`.

## Git / Workspace State

Known modified tracked files:

- `Core.lua`
- `Data.lua`
- `Debug.lua`

Known ignored/untracked local files/folders:

- `scripts/`
- `.github/`
- `.vscode/`
- `smlmcp_fastmcp.log`

Do not treat `scripts/` as accidental junk; it is intentionally ignored and used locally for testing.

## Implemented So Far

### Slash Commands

Implemented commands include:

```text
/icanteven
/icant
/icanteven scan [bags|bank|all]
/icanteven summary
/icanteven move
/icanteven dump <expansion>
/icanteven recall <expansion>
/icanteven rules
/icanteven config
/icanteven protect
/icanteven debug
/icanteven diag
```

### UI

The UI has three tabs:

```text
Summary | Move | Rules
```

The frame was raised to `FULLSCREEN_DIALOG`, set top-level, and clamped to screen so it appears above open bags/bank frames.

### Summary Tab

Shows:

- current context
- last bag/bank scan timestamps
- scan buttons
- summary cards for old-content items, bank candidates, recall candidates, unknown/review, protected, etc.

### Move Tab

Current behavior:

- mode selector:
  - `Dump to Bank`
  - `Recall from Bank`
- dropdown filters:
  - expansion
  - type
  - location
- recommended-only checkbox
- search box
- paged list, currently 10 rows per page
- footer action bar that no longer overlaps the list
- selected count in footer
- mode-specific action button:
  - `Bank Selected`
  - `Recall Selected`

The expansion dropdown currently includes all expansions from `Classic` through `Midnight`, plus `All expansions`.

### Movement

Movement is constrained by active mode:

- `Dump to Bank` only moves bag items with `eligibleForBankMove`.
- `Recall from Bank` only moves bank items with `eligibleForRecall`.

After moving:

- current selection is cleared
- moved rows are optimistically removed from current scan state
- quiet rescans are scheduled at approximately `0.25s`, `0.8s`, and `1.6s`

This was added because WoW inventory updates settle asynchronously and stale recommendations could otherwise be selected again.

### Rules

Rules are stored at:

```lua
ICantEvenRightNowDB.rules.items[itemID] = {
  protect = false,
  neverMove = false,
  neverSell = false,
  ignore = false,
  expansionOverride = nil,
  actionOverride = nil,
  notes = nil,
  createdFrom = "Rules tab",
}
```

Current Move-row rule buttons create rules:

- `Bank` creates an `Always Bank` action override.
- `Recall` creates an `Always Recall` action override.
- `Protect` creates a protect rule.
- `Ignore` creates an ignore rule.

Important UX issue: these labels are misleading. The user correctly noted that `Bank` looks like a one-off move action, not a rule creation action.

## Current User Requests Not Fully Completed

These are the immediate next tasks.

### 1. Add Clear All Rules Button

In the Rules tab, add a `Clear All Rules` button.

Requirements:

- It must require confirmation before clearing.
- It should reset `ICantEvenRightNowDB.rules.items` to `{}`.
- It should refresh the UI afterward.
- Good simple confirmation pattern for WoW:
  - first click changes button text to something like `Confirm Clear All`
  - second click within a short time clears rules
  - timeout resets the button text

Avoid a single-click destructive action.

### 2. Make Rule-Creation Buttons Explicit

The Move tab row buttons should not read like one-off actions.

Current labels:

```text
Bank | Recall | Protect | Ignore
```

Better labels or workflow:

```text
Rule: Bank | Rule: Recall | Protect | Ignore
```

or, if space is tight:

```text
+Bank Rule | +Recall | Protect | Ignore
```

Even better later: move rule creation into an expanded item detail panel or selected-item action area, since four rule buttons per row is cramped.

### 3. Primordial Stone Classification

The user reported Dragonflight Primordial Stones are not classified as Dragonflight and are being offered as bank candidates.

A partial patch has already been applied in `Core.lua`:

```lua
local function InferExpansionOverride(item)
    local name = (item.name or ""):lower()
    local subtype = (item.itemSubTypeName or ""):lower()

    if name:find("primordial stone", 1, true) or subtype:find("primordial stone", 1, true) then
        return 10, "Dragonflight Primordial Stone"
    end

    return nil, nil
end
```

`BuildDecision` now applies the inferred expansion before classification.

This needs in-game validation. If the item names do not literally contain `Primordial Stone`, use item IDs or another API field. The screenshot showed labels like `DF. Primordial Stones`, but that may be the bag addon category, not the item name/subtype.

## Important Known Issues / Risks

### WoW API Risk

This code has not been parsed by a local Lua interpreter in this environment. The user is testing by deploying and `/reload` in-game.

Use WoW Lua errors as the source of truth.

### Bank Bag IDs

Current `BANK_IDS` are:

```lua
local BANK_IDS = { -1, 5, 6, 7, 8, 9, 10, 11, -3 }
```

This may not be fully correct for modern Retail, reagent bank, or warband bank. Treat bank/reagent/warband destination routing as a future cleanup area.

### Recall Recommendations

Recall recommendations were initially absent. Current logic recommends recall for:

- banked old expansion materials/consumables/curated items
- banked current-expansion materials/consumables/currency-like items

This is intentionally rough. Future work should separate:

```text
Recommendation
Destination/source
Eligibility
Selection
```

### Dropdowns

Custom dropdowns are implemented instead of `UIDropDownMenuTemplate`. They work by creating a small frame under each button. If they stack weirdly in-game, inspect frame strata/level.

## Product Direction Notes

The addon should stay conservative.

Default blocked:

- unknown items
- quest items
- legendary/special items
- reputation items unless explicitly included
- soulbound gear
- equipment-set items
- current expansion items
- protected items
- unclear location/state

Default allowed for bank movement:

- old expansion materials
- old currency-like items
- old keep-candidates
- manually approved items

The user raised an important future design issue:

Bank destination should not be a single bucket. Eventually classify destination separately:

```text
Character Bank
Reagent Bank
Warband Bank
Review
```

Example policy:

- reagents/materials -> reagent bank if available
- soulbound character-specific items -> character bank
- BoEs/account-relevant items -> warband bank, likely opt-in or reviewed

## Testing Workflow

After edits:

```powershell
.\scripts\Copy-ToWoW.ps1
```

Then in WoW:

```text
/reload
/icanteven
```

Typical manual tests:

1. Open bags only.
2. Verify Summary context says `Bags only`.
3. Scan bags.
4. Open bank.
5. Scan bank.
6. Move tab -> `Dump to Bank` -> recommended only -> select recommended -> bank selected.
7. Move tab -> `Recall from Bank` -> expansion filter -> recommended only -> select recommended -> recall selected.
8. Verify recommendations clear after action/rescan.
9. Rules tab -> create a few rules from Move rows -> remove one -> clear all rules after confirmation.

## Suggested Next Implementation Order

1. Finish `Clear All Rules` with confirmation.
2. Rename/reposition Move-row rule buttons so they are clearly rule creation, not one-off item moves.
3. Validate and improve Primordial Stone classification.
4. Deploy with `.\scripts\Copy-ToWoW.ps1`.
5. Ask user to `/reload` and test Rules tab plus Primordial Stone behavior.


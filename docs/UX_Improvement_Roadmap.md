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

## 5. Planned: Warband Workflows (target 0.6.0)

### Principle: the Warband bank is for sharing

The Warband bank is the only storage every character on the account can reach, across realms and factions. An item belongs there when **another character benefits from it**, not merely because it is allowed there. Otherwise the character bank is the better home: it is per-character space, and it keeps shared space free for what actually needs sharing.

Items with a real reason to be in Warband storage:

- **Warbound and Warbound-until-equipped items**: the Warband bank is how they reach another character.
- **Crafting reagents**: usable directly from the Warband bank for crafting and crafting orders, so any crafter on the account can use them without withdrawing.
- **Unbound BoE gear and tradeable goods**: the account's designated seller or an alt who can use them can collect them.
- **Consumables and materials shared by several alts.**

Items without a reason to be there: soulbound items (not allowed), items only this character uses, and old gear whose appearance is already collected (transmog is account-wide, so the item itself is not needed to keep it).

The current evaluator already leans this way (shared crafting materials, BoE, and Warbound items go to Warband storage). The roadmap below makes the "who benefits" question answerable.

### W0. Character roles (defines "who benefits")

Status: Planned. Priority: P1. Built together with W1; W3 to W6 depend on it.

Problem: accounts often have dozens of alts, most of them never played. Counting every alt as a possible beneficiary would make almost any gear look like an upgrade for some low-level alt, and would offer leveling gear to characters that only exist for professions or gold farming.

Each character gets exactly one role, set account-wide from any character:

| Role | Receives gear | Receives crafting materials | Typical use |
|---|---|---|---|
| Main / Active | Yes | For its professions | Characters actually played |
| Leveling | Yes, level-appropriate only | For its professions | Alts being leveled |
| Crafter | Never | For its professions | Tradeskill-only alts |
| Utility | Never | Never | Garrison gold farmers, bank or AH mules |
| Unassigned (default) | Never | Never | Every character not yet sorted |

Decisions (2026-09-25):

- Roles are presented as a single dropdown, not raw toggles. Internally each role maps to two capabilities (`receivesGear`, `receivesMaterials`) so a Custom role can be added later without changing consumers.
- Unassigned characters are ignored in all "who benefits" logic. Newly seen characters start Unassigned, so an unsorted roster never floods decisions.
- Main / Active and Leveling stay separate roles: Leveling characters are offered only gear they can use at their current level.

Behavior:

- **Gear**: upgrade checks consider only characters that receive gear. When an item is an upgrade for none of them, the row says so and suggests selling (auction house for BoE, vendor otherwise).
- **Materials**: reagents are worth sharing only if a character that receives materials has the matching profession; otherwise the row says no crafter uses it.
- **On a Utility character**: its own "upgrade" results are empty; the natural tasks are sending items to Warband storage or selling them.
- **Honest basis**: every roster-based hint states what it is based on, e.g. "Not an upgrade for your 4 active characters (19 unassigned)".
- **Safety unchanged**: roles change row text, hints, and quick-task pre-filters only. Nothing moves or sells without selection and confirmation.

Constraints:

- A character is known only after it has logged in once with the addon enabled; the game does not expose unseen characters to addons. Class, level, and professions are recorded automatically at login; the role can then be set from any character.
- UI: a Characters list (Settings tab or its own tab) showing name, realm, class, level, professions, last seen, and the role dropdown, with an option to hide Unassigned.

### W1. Per-character and account snapshots (foundation)

Status: Planned. Priority: P1.

Problem: scans live in account-wide SavedVariables without a character key, so an alt can see another character's character-bank data until it opens a bank. Nothing is known about other characters.

Plan:

- Store bags and character bank per character (`Name-Realm`), and the Warband bank once per account, each with a scan time.
- Record lightweight character facts for routing: class, armor type, level, professions, and the W0 role.
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

Status: Planned. Priority: P2. Depends on W0 and W1.

- On character A, mark items "for Alt B" (the picker lists only characters whose role can receive that kind of item); they travel through the normal Warband deposit.
- On character B at a bank, a "Waiting for you (N)" quick task appears, pre-filtered to those items. Nothing is withdrawn without confirmation.
- The queue records intent only; stale entries (item gone, withdrawn elsewhere) clear themselves on the next Warband scan.

### W5. Cross-character "Where is it?"

Status: Planned. Priority: P2. Depends on W1.

- Search all snapshots: "Also on: Alt B (bags), Warband: Mats (2 days ago)".
- Tooltip line on items that other characters also hold.

### W6. "Who benefits" routing hints

Status: Idea. Priority: P3. Depends on W0 and W1.

- Use W0 roles and snapshot character facts to explain routing: "Reagent for Tailoring (Alt C, Crafter)", "Plate upgrade for Alt D (Leveling)", "No other character uses this; keep in character bank", "No active character can use this; sell it".
- Hints only: they explain and pre-filter, and never move items on their own.

## 6. Planned: Home Screen and Friction Fixes (target 0.6.0)

Assessment basis (2026-09-25): code review of the 0.6.0 Transfer tab. The main job today (deposit old items at a bank) takes: open bank, open console by minimap or slash command, pick a task, Select Movable, page through a 6-row list, Deposit. Steps 2 to 4 repeat on every visit.

### H1. Home screen of task cards (replaces Summary and the Task dropdown)

Status: Planned. Priority: P1.

- The console opens to a Home screen of task cards, one per quick task and saved workflow, each showing a live count and value, e.g. "Deposit Old Items: 23 ready", "Sell Old Consumables: 8 (12g), at a vendor", "Waiting for you: 3".
- Cards are ordered by what the current context allows; unavailable cards say what they need ("Visit a bank") instead of failing after selection.
- Clicking a card opens its review list (the Transfer view). Summary counts are no longer passive numbers; each count is a card.
- The Transfer view keeps route and filter editing for custom work.
- Scan age is shown on cards that rely on non-live data ("bank as of yesterday").

### H2. Presence at the bank and vendor

Status: Planned. Priority: P1.

- When a bank or vendor opens, show a small non-blocking notice with the top card's count ("23 ready to deposit") that opens Home. A setting chooses Notice (default), Auto-open, or Off.
- The earlier bank/vendor frame launchers were disabled intentionally; the notice must not attach to or depend on specific bag or bank frames (see Known Pitfalls).

### H3. Pre-selection for quick tasks

Status: Planned. Priority: P1. Decided 2026-09-25: a setting, off by default.

- When enabled, loading a quick task (from a Home card or the task list) pre-selects its movable items; the action button still reads "Deposit 23" and still requires a click after the list is visible.
- When disabled (default), tasks load with nothing selected, as today.
- Blocked items are never pre-selected, and pre-selection never triggers an action on its own.

### H4. Faster review

Status: Planned. Priority: P1.

- Group identical items into one row ("Linen Cloth ×3 stacks").
- Optional grouping by category with counts.
- Compact row density option; the list currently shows 6 rows of 42 px.

### H5. Vendor buyback safety

Status: Planned. Priority: P1 (safety).

- The vendor buyback list holds a limited number of items (believed 12; verify in game). Large sell batches make earlier items unrecoverable.
- Sell in buyback-sized batches or warn before a larger sell ("30 items; only the last 12 can be bought back").

### H6. One place to save a task

Status: Planned. Priority: P2.

- "Save as task…" next to the current task name saves the full current state (route, filters, sort).
- The Customize drawer shrinks to route editing only.
- Editing a loaded task shows "Deposit Old Items (modified)" instead of "Custom transfer".

## 7. Planned: Onboarding Across Characters (target 0.6.0)

Goal: zero required setup, at most one question per character, and every answer makes the next character easier.

### Principles

1. Useful on first open with no setup; conservative defaults already protect current-content, quest, legendary, and ruled items.
2. Account-wide by default: rules, saved tasks, settings, and the Warband bank snapshot are shared by every character automatically (the addon already uses account-wide SavedVariables).
3. The only per-character setup is the W0 role, and it is always offered with a suggested answer.
4. Never block. An unanswered question leaves the character Unassigned, which is ignored and therefore safe.
5. Each answer improves the next suggestion.
6. On return, show what changed since last time instead of asking again.

### O1. Role suggestions

Status: Planned. Priority: P1. Depends on W0/W1.

Suggested, never assumed; one click to accept or change:

- First character to load the addon at max level: suggest Main / Active.
- Max level: suggest Main / Active (or the role most often chosen for max-level characters so far).
- Below max level and gaining levels between sessions: suggest Leveling.
- Low level with professions: suggest Crafter.
- Low level without professions, or parked in a garrison: suggest Utility.
- Offer "Same as <last configured character> (Crafter)".
- Once several characters share a pattern (e.g. three low-level alts set to Crafter), offer to make that the default suggestion for matching new characters.

### O2. Roster setup in bulk

Status: Planned. Priority: P1.

- The Characters list shows every known character with its suggested role, last seen, level, and professions.
- "Accept all suggestions" and multi-select role assignment, so dozens of alts are sorted in one sitting from any character.
- Characters appear only after logging in once with the addon; the list says so.

### O3. Lifecycle walkthroughs (acceptance scenarios)

| Moment | What the player sees | Setup cost |
|---|---|---|
| Main, first login | One-time welcome notice. Opening the console shows Home with bag-based cards and one role card ("This looks like your main. Main / Active?"). Bank cards say "Visit a bank". | 1 click |
| Main, first bank visit | Notice "23 ready to deposit". Bank and Warband bank are scanned; Warband tabs and their Blizzard tab settings are recorded for routing. | 0 |
| Main, day 2 | No prompts. Home cards show counts, with scan ages for non-live data. At a bank: notice, card, review, confirm. | 0 |
| Alt, first login | Rules, tasks, and settings already apply. One role card with a suggestion (e.g. "Crafter: low level with Tailoring and Enchanting", or "Same as Alt C"). Account cards appear immediately ("Waiting for you: 3", "Warband has 12 reagents for your Tailoring"). | 0 to 1 click |
| Alt, day 2 | No prompts; role-appropriate cards only (a Utility alt sees Send to Warband and Sell, never upgrades). | 0 |
| Alt, day 30 | Character facts refresh silently at login. A "Since you were last here" card: hand-off items waiting, bank snapshot age, and a role check only if something changed (e.g. "Reached max level; switch Leveling to Main?"). Stale hand-off entries clear on the next Warband scan. | 0 to 1 click |
| Sender side | Hand-off items not collected after a long time show on the sender's Home ("3 items waiting for Alt B for 30 days"). | 0 |

### O4. In-context opt-ins

Status: Planned. Priority: P2.

- If BetterBags is loaded, a one-time Home card offers to enable the categories (section 8) instead of hiding the option in Settings.
- Settings stays available for everything, but no feature requires visiting it.

### O5. First-time tips and "What's new" (instead of a tutorial)

Status: Planned. Priority: P1.

A step-by-step tutorial is not planned: it contradicts "useful on first open, at most one question", it would run at login when the interesting actions (bank, vendor, Warband) are unavailable, and skipped tutorials leave nothing behind. Instead:

- **Just-in-time tips**, each shown the first time its moment happens:
  - First bank visit, on the top card: "Tasks find items for you. Review the list, then click Deposit. Nothing moves without your click."
  - First review list: row reasons and +Rule ("Blocked rows tell you why. Protect items so they're never touched.").
  - First vendor visit: buyback-sized batches (H5).
  - First Warband tab routing: items follow the matching Blizzard tab settings (W3).
- Each tip shows once, **account-wide** (seen on the main means alts never see it), and is dismissible in one click.
- Settings: "Show tips again" and "Turn off tips".
- **"What's new in 0.6.0" card** for existing users on first open after upgrading: Summary is now Home, tasks are cards, plus Warband features and character roles, with where each thing moved. Shown once; new installs skip it.
- **Empty states keep teaching**: Home cards follow the Transfer empty-state pattern of saying why and offering the fix ("No bank data yet: visit a bank").
- If no Warband tab has "assign to" settings, a card explains that setting them in Blizzard's bank tab settings enables smart routing. The addon does not change tab settings itself.

## 8. Planned: BetterBags Categories (target 0.6.0)

Status: Planned. Priority: P2. Optional; off until enabled.

Verified 2026-09-25 against BetterBags `main` (v0.5.11, Interface 120100): external addons get the Categories module via `LibStub("AceAddon-3.0"):GetAddon("BetterBags")`, register `RegisterCategoryFunction(id, func)` (func returns a category name or nil per item), and refresh with `WipeCategory` then `ReprocessAllItems`. **Categories are assigned per item ID, not per slot**, so only decisions that hold for every copy of an item can be published.

| Category | Contents |
|---|---|
| Protected | Items with a Protect rule |
| Never Sell | Items with a Never Sell rule |
| Sell Candidates | Items the Sell task would offer (old consumables, junk) |
| Old Content | Items the Deposit Old Items task would move |
| For the Warband | Warbound items and reagents used by a Crafter, Main, or Leveling character's professions |
| Waiting for You | Items in this character's hand-off queue |

- Not published: per-copy decisions such as "upgrade for Alt D" (copies differ in item level and binding).
- `## OptionalDeps: BetterBags`; hook on `ADDON_LOADED`. Default priority so the player's own categories win; players can reprioritize, disable, or delete ours in BetterBags' Categories pane.
- Refresh after rule, role, or scan changes: `WipeCategory` + `ReprocessAllItems`, deferred until out of combat.
- Display only: categories never trigger actions.
- BetterBags treats character and Warband bank tabs as one bank view; categories apply there too.

## 9. Safety Guardrails to Preserve

Do not remove:

- Explicit user selection before action
- Rule-based hard blocks (`Protect`, `Ignore`, `Never Sell`)
- Context checks (bank/vendor/combat)
- Conservative defaults for ambiguous content

The roadmap should improve speed and clarity without relaxing core safety principles.

## 10. Acceptance Criteria for AH Pull UX

A successful AH pull UX should satisfy all:

1. From bank, user can load the built-in "Pull Auctionable BoEs" quick task.
2. List shows only auctionable BoE items.
3. WuE items are excluded unless explicitly requested.
4. Selected items are immediately transferable.
5. Empty states explain exactly why no rows are shown.

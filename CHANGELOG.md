# Changelog

All notable changes to I Can't Even Right Now (With My Bags and Bank) will be documented in this file.

Changelog entries are written for addon users, not as an internal development log. Focus on visible features, behavior changes, compatibility notes, and documentation or integration changes that matter to users or packagers. Technical implementation details belong here only when they affect installation, integrations, repository documentation, or release packaging.

Release note rules:
- Record only user-facing deltas from the previous released version.
- Do not list mid-cycle test/build fixes as separate "Fixed" items unless that behavior was present in a previously released version.
- Prefer "Added", "Changed", and "Improved" wording for features refined during the same unreleased development cycle.

## [Unreleased]

## [0.5.0] - 2026-05-10

### Added

- Armor Type filter in the Transfer tab: filter armor items by type (Cloth, Leather, Mail, Plate). Non-armor items are unaffected by this filter.
- Transfer is now the default landing tab when opening the addon without requesting a specific tab.

### Fixed

- Transfer tab filter controls are less crowded, with Armor Type moved alongside the search and item-level controls.
- Transfer tab controls now use cleaner, aligned rows for transfer flow, presets, filters, search, results, and footer actions.
- Transfer tab rows now use the wider console space for metadata, with row buttons and scrollbar anchored to the expanded list boundary.
- Rules tab now uses the wider console layout with anchored columns, footer spacing, and scrolling when many rules exist.
- Settings tab now includes a slash command reference for common workflows, views, and diagnostics.
- Navigation tabs now look and behave more like tabs, with a distinct active state instead of a disabled-button appearance.
- Settings tab minimap launcher toggle now refreshes from saved settings and immediately hides or shows the registered minimap icon.
- Upgrade filtering now implicitly limits results to wearable gear, and only treats items as upgrades when they meet the current character's level requirement and armor/shield suitability.
- Transfer tab list/footer spacing now keeps all eight rendered rows clear of the footer, and opening one dropdown now closes any previously open dropdown.
- Transfer rows now front the decision reason and show more useful context such as binding, gear details, target storage, and vendor value.
- Transfer source/destination auto-resets now show an in-panel notice when context changes make the previous option unavailable.
- Saved preset dropdowns now keep the active preset name visible after loading or saving.
- The bulk selection buttons no longer select blocked transfer rows.
- Lua language-server configuration no longer disables all undefined-field diagnostics to work around `string.lower` false positives.
- Upgrade filter no longer crashes on load; replaced removed `GetInventoryItemLevel` API with `C_Item.GetCurrentItemLevel` (API removed in patch 12.x).
- Slot and Armor Type filters no longer cause Lua errors due to a forward-reference issue in the filter matching code.
- Saved filter presets now preserve Armor Type selections.
- Transfer tab "Select Visible" button now correctly selects all visible rows (was only selecting 6 of 8 due to a hard-coded value).
- Transfer tab scrollbar now correctly reflects the full list length (visible row count was hard-coded in scroll update).
- Source/Destination dropdowns now reset to valid defaults when the previously selected option becomes unavailable (e.g., bank closing).
- Addon metadata now reports version 0.5.0.

## [0.4.0] - 2026-05-09

### Added

- Transfer tab now uses a scrollable list for all items instead of a paginated presentation.
- Item Level filter in the Transfer tab: filter equippable gear by a minimum and/or maximum item level.
- Slot filter in the Transfer tab: narrow the list to a specific gear slot (Head, Chest, Finger, etc.).
- Upgrade filter in the Transfer tab: show only gear that is a strict item level upgrade over what the character currently has equipped. For two-slot types (rings, trinkets), the weaker of the two equipped items is used as the baseline.
- Saved Filter presets ("Favorites"): save a named combination of Expansion, Binding, Type, Slot, and Upgrade filter selections, then reload any saved preset from a dropdown. Two presets ship by default and can be removed: "Old Gear Dump" (Expansion: Not current) and "Upgrade Check" (Upgrade: Upgrade).

### Changed

- "Bind" filter label renamed to "Binding" to match WoW tooltip language and reduce ambiguity.
- BoE removed from the Type filter; it is already covered by the Binding filter.
- Bank and Vendor options in Source/Destination dropdowns are now hidden when the respective context is not available, preventing inaccessible transfer configurations.

### Fixed

- Soulbound detection corrected to reliably identify soulbound items across all scanned locations.
- Transfer tab now refreshes bag and bank counts after every action, including vendor sales.

### Maintenance

- Core.lua split into focused modules (Shared, Evaluator, Filter, Scanner, Transfer, UI) for long-term maintainability.

## [0.3.0] - 2026-05-08

### Added

- Unified Transfer tab replaces the separate Move, Organize, and Vendor tabs.
- Transfer tab supports any combination of Source and Destination: Bags, Private Bank, Reagent Bank, Warband Bank, or Vendor.
- From/To dropdowns let you pick exactly what to move where, without switching between three separate UIs.
- Per-item block reason display: items that cannot be transferred show why (bank closed, vendor closed, no slots, rules, etc.).
- Actionable-only toggle to hide blocked items and focus on what can be moved now.
- Select Movable and Select Page shortcuts for batch selection.
- Slash command presets (`/icanteven dump`, `recall`, `organize`, `vendor`) now pre-configure the Transfer tab Source and Destination and open it directly.
- Rules tab now shows all active per-item rules with name, flags (Protect / Ignore / Never Sell), origin, and a Remove button per rule.
- Summary tab now shows inventory scope counts: items in bags, items in bank, old-content in bags, old-content in bank, Warband bank items, active rules, unclassified items, and last scan time.
- Error logging captures Lua errors to SavedVariables (`/icanteven errors` to view, `/icanteven clearerrors` to reset).
- Bank (All Tabs) source/destination covers all character bank tabs in a single selection.

### Changed

- Navigation simplified to four tabs: Summary, Transfer, Rules, Settings.
- Summary tab redesigned around inventory scope counts rather than recommendation-driven card groups.
- Per-item rule flags reduced to three: Protect, Ignore, Never Sell. Never Move and Action Override have been removed as they were superseded by the Source/Destination pipeline.
- Item evaluator no longer assigns recommendation groups or recommended actions; transfer intent is driven entirely by the player-selected Source and Destination.

## [0.2.0] - 2026-05-06

### Added

- Minimap button for opening the cleanup console from anywhere.
- Settings tab for launcher visibility and status checks.
- Unknown expansion filter for reviewing items without reliable expansion metadata.
- Search fields for narrowing Move, Organize, and Vendor recommendations.
- Bank diagnostics slash command support (`/icanteven bankdiag` and `/icanteven bankids`).

### Changed

- Move, Organize, Vendor, and Rules tabs now use more consistent list, empty-state, and footer layouts.
- Move rows now use direct `Bank` or `Recall` row actions, while rule actions are grouped under a compact `+Rule` menu.
- Move-tab manual actions are available even when an item is not recommended; recommendation is advisory while rule/context/capacity checks gate execution.
- Move tab bank recommendations now surface preferred target storage for reagents and other materials, including Reagent Bank, Private Bank, and Warband Bank destinations.
- Move Type filters now split `BoE` and `WuE` so auctionable BoEs exclude Warbound-until-equipped gear.
- Organizer and vendor bulk-select buttons now select only the current page and are labeled `Select Page`.
- Organizer now recommends transferable non-profession shared-value items, such as Housing dyes, for Warband bank storage.
- Quick access is minimap-only in this release; bank-window and vendor-window launchers are disabled.

### Improved

- Bank and reagent storage detection is more reliable across different client API layouts, reducing misclassified bank rows.
- Dump-to-bank routing is more resilient when a preferred bank destination is unavailable.
- Transferable shared-value items, such as Housing dyes, can now be selected for banking in Move flows.
- Reagent and profession-material handling is clearer in recall and dump flows, including better blocked-state messaging in organizer views.
- Recall-to-bags behavior is more predictable and now keeps withdrawn items in normal character bags.
- Minimap launcher visibility after login/reload is more reliable.
- Move-tab empty states now better explain whether rows are missing due to scan scope, recommendation filters, or other filters.
- Move selection state now updates footer action enablement immediately after checkbox clicks.

### Documentation

- Expanded and synchronized repository documentation across README, architecture, UX, flows, and handoff docs for current 0.2.0 behavior.

## [0.1.0] - 2026-05-05

Initial CurseForge release.

### Added

- Five-tab cleanup console: Summary, Move, Organize, Vendor, and Rules.
- Bag, private bank, reagent bank, and warband bank scanning.
- Expansion-aware item classification for old, current, and unknown content.
- Conservative recommendation engine with visible reasons, blocked states, and explicit selection.
- Move workflow for banking old-content items and recalling useful banked items.
- Organize workflow for reviewing private bank and warband bank storage placement.
- Vendor workflow for reviewing safe old consumable candidates before selling.
- Rules workflow for item-ID overrides such as protect, ignore, never move, never sell, always bank, and recall.
- Context checks for bank access, vendor access, and combat state before actions are enabled.
- Mythic Keystone and current-content protection.
- Addon artwork at `ICantEvenRightNow.png`.
- Optional Ko-fi support link in project documentation.
- CurseForge-ready metadata, packaging configuration, GitHub release workflow, and manual release zip builder.

### Changed

- Present the addon publicly as `I Can't Even Right Now (With My Bags and Bank)` while keeping file names, saved variables, and slash commands compact.
- Point addon icon metadata at the root addon artwork.
- Clarify that source code is MIT licensed while addon artwork and Finalomega brand assets remain all rights reserved.

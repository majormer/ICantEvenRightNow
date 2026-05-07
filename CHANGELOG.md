# Changelog

All notable changes to I Can't Even Right Now (With My Bags and Bank) will be documented in this file.

Changelog entries are written for addon users, not as an internal development log. Focus on visible features, behavior changes, compatibility notes, and documentation or integration changes that matter to users or packagers. Technical implementation details belong here only when they affect installation, integrations, repository documentation, or release packaging.

Release note rules:
- Record only user-facing deltas from the previous released version.
- Do not list mid-cycle test/build fixes as separate "Fixed" items unless that behavior was present in a previously released version.
- Prefer "Added", "Changed", and "Improved" wording for features refined during the same unreleased development cycle.

## [Unreleased]

- No changes yet.

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

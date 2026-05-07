# I Can't Even Right Now (With My Bags and Bank)

I Can't Even Right Now is a conservative World of Warcraft Retail inventory cleanup console. It scans bags and bank storage, classifies clutter, explains recommendations, and lets you explicitly choose what to move, organize, recall, or vendor.

It is not a bag replacement and it does not automatically act on recommendations. Unknown, quest, legendary, protected, and unsafe items are blocked by default, and every movement or sell action requires player selection.

## Features

- Six-tab cleanup console: Summary, Move, Organize, Vendor, Rules, and Settings.
- Expansion-aware item classification for old, current, and unknown content.
- Conservative recommendations with visible reasons and blocked states.
- Bank movement and recall workflows for old-content cleanup.
- Move-tab manual actions are available regardless of recommendation when rules, context, and capacity permit.
- Searchable bank organizer for private bank, reagent bank, and warband bank review.
- Searchable vendor review flow for safe old consumable candidates.
- Item-ID rules for protect, ignore, never move, never sell, always bank, and similar overrides.
- Context checks for bank access, merchant access, and combat state.
- Optional minimap launcher for opening the cleanup console.

## Slash Commands

- `/icanteven` or `/icant` opens the cleanup console.
- `/icanteven scan [bags|bank|all]` scans available storage.
- `/icanteven move`, `/icanteven organize`, `/icanteven vendor`, and `/icanteven rules` open workflow tabs.
- `/icanteven dump <expansion>` and `/icanteven recall <expansion>` set workflow mode and expansion filter.
- `/icanteven minimap` toggles the minimap launcher.
- `/icanteven buttons` prints quick-access status.
- `/icanteven bankdiag` prints bank container diagnostics.

## Support

Bug reports and feature requests are welcome through the GitHub issue tracker.

Optional support is available on Ko-fi: <https://ko-fi.com/finalomega>

## License

Source code is MIT licensed. The addon artwork and Finalomega brand assets are all rights reserved and are not licensed for reuse outside official addon releases.

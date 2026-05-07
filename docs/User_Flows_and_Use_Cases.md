# User Flows and Use Cases

## 1. Product Fit Summary

The addon is strongest when users want to:

- Classify a large mixed inventory with conservative safety defaults
- Move filtered subsets across storage tiers in controlled batches
- Use explicit selection instead of one-click automation
- Build repeatable behavior with item-level rules over time

It is not optimized for:

- Fully automated cleanup
- Instant "do everything" actions
- Minimal-click, preset-driven role workflows (yet)

## 2. User Personas

### A. Auction House Character Operator

Goal:

- Pull auctionable items from bank quickly
- Exclude non-auctionable WuE items

Primary tabs:

- Move (Recall from Bank)

Common filters:

- Type: BoE
- Location: Bank/All
- Recommended only: off (in current behavior)

Pain points observed:

- Recommendation semantics can conflict with manual recall intent
- Filter definitions and bind semantics can be confusing

### B. Main Character Cleanup Pass

Goal:

- Bank old expansion clutter from bags
- Keep active/current essentials unblocked

Primary tabs:

- Move (Dump to Bank)
- Rules

Common filters:

- Expansion: Not current
- Recommended only: on

Pain points observed:

- Users can misunderstand row actions vs rule actions
- Some useful exceptions require explicit rules

### C. Bank Organizer

Goal:

- Normalize storage layout across private/warband/reagent contexts
- Keep shared-value items in shared storage

Primary tabs:

- Organize

Pain points observed:

- Storage model can vary by patch/client API
- Reagent-bank expectations differ across versions

### D. Vendor Cleanup User

Goal:

- Safely identify low-risk, low-value old consumables
- Recall from bank then sell at merchant

Primary tabs:

- Vendor

Pain points observed:

- Context switching between bank and vendor
- Narrow candidate policy may hide expected rows

## 3. End-to-End Flow Maps

## Flow A: AH Pull (BoE sell prep)

Current path:

1. Open bank
2. Open Move tab
3. Set mode to Recall from Bank
4. Set Type filter to BoE
5. Disable Recommended only
6. Select page or specific rows
7. Recall selected to bags
8. Go to AH and list

Where friction appears:

- Recommended-only defaults create a hidden empty-state trap
- BoE vs WuE differentiation must be precise to avoid wasted pulls

Target outcome:

- One-click mode preset plus clean bind filters

## Flow B: Legacy Cleanup

Current path:

1. Open bank
2. Scan all
3. Move tab -> Dump to Bank
4. Expansion: Not current
5. Recommended only on
6. Select recommended page
7. Bank selected
8. Add Protect/Ignore/NeverMove rules for exceptions

Why this flow works well:

- Conservative recommendations align with user intent
- Selection remains explicit

## Flow C: Cross-tier Reorganization

Current path:

1. Open bank
2. Organize tab
3. Optional search filter
4. Select movable rows
5. Move selected
6. Review blocked details and re-run after freeing slots

Why this flow works well:

- Moves are explainable and constrained
- Useful for ongoing hygiene instead of one-off cleanup

## Flow D: Vendor Liquidation

Current path:

1. At bank: Vendor tab -> recall candidates to bags
2. At vendor: Vendor tab -> process selected
3. Use Never Sell rules to prevent future false positives

Why this flow works well:

- Explicit two-step workflow lowers accidental selling risk

## 4. Use Case Matrix

| Use Case | Best Tab | Recommended only | Core Filters | Outcome |
| --- | --- | --- | --- | --- |
| AH BoE pull | Move (Recall) | Off | Type=BoE | Pull auctionable gear only |
| WuE grouping | Move (Dump) | Off/On | Type=WuE | Move WuE to warband target |
| Legacy bag cleanup | Move (Dump) | On | Expansion=Not current | Bank old clutter safely |
| Bank layout normalization | Organize | N/A | Search + movable only | Improve storage consistency |
| Vendor liquidation | Vendor | N/A | Show candidates | Sell safe old consumables |
| Exception control | Rules | N/A | Item-ID based | Encode user intent |

## 5. Where the Addon is Most Valuable

Most valuable scenarios:

- Repeated inventory maintenance across many characters
- Users who care about safety and visibility over speed
- Users who want deterministic, teachable behavior with rules

Less valuable scenarios:

- Users wanting instant fully automatic sorting with no review
- One-off users with very small inventories and no bank discipline

## 6. Behavioral Principles for Future UX

- Manual intent should never be blocked by recommendation-only policy unless explicitly selected
- Filters should map to player vocabulary (BoE, WuE, current, old, bank, bags)
- "No rows" states should always explain whether the cause is scan scope, filters, recommendation policy, or context gating
- High-frequency flows should be preset-driven to reduce repetitive setup

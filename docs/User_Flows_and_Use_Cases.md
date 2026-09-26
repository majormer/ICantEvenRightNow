# User Flows and Use Cases

## 1. Product Fit Summary

The addon is strongest when players want to:

- Clear bags and banks quickly without risking items they care about
- Understand why items are being kept before letting them go
- Share items across many characters through the Warband bank, with roles deciding who benefits
- Repeat common cleanup jobs as one-click tasks, with a review step every time

It is not built for:

- Fully automated cleanup without review
- Posting or buying on the auction house (Auctionator or TSM do that; this addon only reads prices)

## 2. Personas

### A. Alt-heavy player

Dozens of characters, few played. Some farm gold (garrisons), some only craft.

- Sets roles once: played characters Main / Active, alts being leveled Leveling (including alts that also craft), alts kept only for professions Crafting only, farmers and mules Utility. Unassigned alts are ignored.
- Uses Deposit to Warband to share only what another character benefits from, and Send to Alts / Waiting for You for specific hand-offs.
- Relies on "Upgrade for <alt>" and "Used by <alt> (<profession>)" hints; gear nobody played can wear is suggested for selling instead of hoarding.

### B. Main character cleanup pass

- Opens Home at a bank; clicks Deposit Old Items; reviews and deposits.
- At a vendor, uses Sell Items That Can Go (junk, collected appearances, spent consumables); selling stops at 12 per click.

### C. Auction house operator

- Pull Auctionable BoEs and Auction Candidates gather items to post.
- Prices come from Auctionator or TSM, or Price My Items at the auction house; vendor rows warn when something is worth more at auction.

### D. Gear upgrade scout

- Pull Bank Upgrades lists bank gear that beats what this character wears.
- Tooltips name upgrades for other characters with gear-receiving roles.

### E. Collector and keepsake holder

- "Why is this here?" separates "appearance already collected" from "appearance not collected yet" and unlearned toys, mounts, and pets.
- Keepsake, Keep for an alt, Keep for an event, and Investment reasons silence suggestions for items that matter.

### F. Returning player

- A "What's new" card after upgrading, with what was carried over.
- A welcome back after a week away, with waiting hand-offs and stale bank lists.

## 3. End-to-End Flows

### Flow A: First login on a main (day 1)

1. `/icanteven` opens Home. One question: "What is <name>? Suggested: Main / Active." One click.
2. Cards show bag tasks ready and bank tasks waiting ("Visit a bank").

### Flow B: Bank visit

1. At the bank, a notice names the top ready task ("Deposit Old Items: 23 ready"). Open.
2. The review list shows each item with a reason and destination. Select Movable, Deposit.
3. Warband tabs and their settings are recorded for routing and for other characters.

### Flow C: Share with the Warband by tab settings

1. Home card Deposit to Warband: Warbound items, BoE gear, and materials another character's crafting role uses.
2. Each row says which tab it goes to and why ("Mats (accepts Reagents)", "For Stitcher").
3. Deposit.

### Flow D: Hand an item to a specific alt

1. Row menu: Send to an alt... Pick from characters whose role can use it.
2. At a bank: Send to Alts, Deposit.
3. On the alt: Waiting for You, Withdraw.

### Flow E: Let go of what isn't needed

1. `/icanteven why` or the row reasons show what can go.
2. At a bank: Pull Items That Can Go. At a vendor: Sell Items That Can Go (12 per click).
3. Items worth more at auction are left out and show up under Auction Candidates instead.

### Flow F: Alt first login and day 30

1. First login: rules and saved tasks from other characters already apply; one role question with a suggestion or "Same as <last alt>"; Waiting for You if something was sent.
2. After 30 days away: welcome back with waiting items and bank age; a Leveling alt that reached max level is offered Main / Active.

### Flow G: Custom transfer

1. Home: Custom transfer (or `/icanteven transfer`).
2. Customize: choose From and To (including individual bank and Warband tabs); Filters for expansion, type, binding, slot, armor, upgrade, item level, search, and sort.
3. Save as task to add it to Home.

## 4. Use Case Matrix

| Use case | Starting point | Route | Key safety |
|---|---|---|---|
| Bank old content | Deposit Old Items | Bags → Bank (All Tabs) | Current-content and ruled items blocked |
| Share with alts | Deposit to Warband | Bags → Warband (by tab settings) | Soulbound blocked; only items someone else benefits from |
| Specific hand-off | Send to Alts / Waiting for You | Bags → Warband → alt's bags | Recipient filtered by role and usability |
| Sell | Sell Items That Can Go / Sell Old Consumables | Bags → Vendor | 12 per click; value-flagged items excluded |
| Auction prep | Auction Candidates / Pull Auctionable BoEs | Bank → Bags | Bound items never candidates |
| Upgrades | Pull Bank Upgrades | Bank → Bags | Class, level, and slot checks |

## 5. Behavioral Principles

- The addon finds, explains, and routes; the player reviews and clicks.
- One question per character at most, always with a suggested answer; skipping is safe.
- Account-wide by default: rules, tasks, settings, and the Warband snapshot are shared.
- Never call something "can go" when the addon cannot know who uses it.
- Never weaken the safety model to save a click.

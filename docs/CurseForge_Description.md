# I Can't Even Right Now (With My Bags and Bank)

I Can't Even Right Now (With My Bags and Bank) turns inventory cleanup into a short, safe routine. It finds the items worth moving or letting go, explains why each one is there, knows which of your characters can use it, and waits for your click before anything moves.

## Who This Addon Is For

- Players with full bags and banks who want cleanup without the risk of one-click tools.
- Alt-heavy players who share items through the Warband bank, including accounts with dozens of alts that are rarely played.
- Anyone who wants to know **why** an item is being kept before deciding to let it go.

If you want full automation with no review, this addon is probably not a fit. If you want less work without losing control, it is built for exactly that.

## Features

### Home: tasks with live counts

- Open the console and see what's ready: "Deposit Old Items: 23 ready", "Sell Items That Can Go: 14 (38g)".
- Cards that need a bank or vendor say so. Click a card, review the list, click the action.
- Built-in tasks for banking old content, pulling upgrades and auctionable BoEs, selling junk and spent consumables, sharing with the Warband, and handing items to specific alts.
- Save any custom setup as your own task.
- At a bank or vendor, a small notice tells you what's ready.

### Characters and roles

- Give each character a role: Main / Active, Leveling (gear it can wear plus materials for its professions), Crafting only (materials, never gear), or Utility (nothing). Unassigned characters are ignored.
- Suggested roles (max level, leveling, professions) that learn from your choices; accept them all at once.
- Hints like "Upgrade for Tankalt (Leveling)" and "Used by Stitcher (Tailoring)".

### Warband bank

- Every Warband tab is a destination. "Warband (by tab settings)" sends each item to the tab whose own Blizzard settings match it.
- Send an item to a specific alt; that character sees "Waiting for You".
- Item tooltips can show how many your whole account holds and where.

### Why is this here?

- Every item says why it's being kept: appearance already collected, collectible not learned, quest in progress or already done, a crafter who uses it, gear one of your characters wears, how long it has sat untouched.
- See what letting it go costs: "You keep the appearance. Worth 4g at a vendor."
- Mark keepsakes and investments so the addon stops suggesting them.

### Auction value

- Prices from Auctionator or TSM, or look up your own items at the auction house.
- With Auctionator: one click searches all your auction candidates in its Shopping tab, or saves them as a shopping list.
- Items worth more at auction are flagged at vendors and never pre-selected for selling.

### Safety first

- Nothing moves or sells without your selection and click.
- Every action re-checks the bag slot first; items that moved are skipped.
- Protect, Ignore, and Never Sell rules always win.
- Selling stops at 12 items per click, so every sale stays in the vendor's buyback.

### Optional BetterBags categories

Protected, Never Sell, Sell Candidates, For the Warband, Old Content, and Waiting for You as BetterBags categories (off until you enable them).

## First 5 Minutes

1. Type `/icanteven`. Answer one question: what is this character? (A suggestion is ready.)
2. Visit a bank. A notice names the ready task; open it.
3. Review the list, Select Movable, click Deposit.
4. Visit a vendor and use **Sell Items That Can Go**.

## Upgrading

Your rules, saved presets, and settings carry over. A "What's new" card explains the changes, and `/icanteven migration` lists exactly what was carried over.

## Slash Commands

- `/icanteven` or `/icant` - open Home.
- `/icanteven transfer` - custom transfers.
- `/icanteven characters` - roles.
- `/icanteven why [all]` - why items are being kept.
- `/icanteven where <name>` - find an item across your characters and Warband bank.
- `/icanteven rules`, `/icanteven settings`, `/icanteven migration`.
- `/icanteven scan [bags|bank|all]`, `/icanteven minimap`, `/icanteven errors`.

## FAQ

**Will this sell or move things automatically?**
No. Every action needs your selection and click. Pre-selecting items when a task opens is an optional setting, off by default.

**Why doesn't it know about my other characters?**
Each character appears after logging in once with the addon enabled. After that, you can set its role from any character.

**Does it post auctions?**
No. It reads prices to warn you before vendoring something valuable and to list auction candidates. Posting stays with your auction addon.

## Philosophy

The addon finds, explains, and routes; you decide. It asks at most one question per character, and skipping any question is always safe.

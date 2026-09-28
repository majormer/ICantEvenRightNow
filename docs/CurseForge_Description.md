# I Can't Even Right Now (With My Bags and Bank)

*A Finalomega Labs project.*

**Your bank is not a museum.**

Somewhere in your bank is a stack of Titan Training Matrices that stopped doing anything two expansions ago. Next to it: a ring from a questline you finished in 2024, 31 archaeology crates, and three copies of a trinket "just in case." Your Warband bank is full, and your alts are wearing worse gear than what's sitting in it.

I Can't Even Right Now is an **anti-hoarding addon**. Every item in your bags, bank and Warband bank has to justify its slot. The addon tells you what each one is for, which of your characters could use it, and what it's worth, and then helps you bank it, hand it to an alt, sell it, auction it, or let it go. Nothing moves until you click.

<!-- Screenshot: the Justify every item screen on one item -->

## Justify every item

The heart of the addon. Open **Justify every item** and go through your bank, Warband bank or bags one item at a time:

- **What it is and why it's here:** "Appearance already collected." "Starts a quest you already completed." "Used by Stitcher (Tailoring)." "Upgrade for Tankalt."
- **What you can actually do with it:** only the options that exist for that item. Soulbound items can't be auctioned, so the addon won't offer it.
- **A recommendation,** with the reason and a Wowhead link.
- **Your decision sticks.** Choose sell, auction, keep, carry, use, destroy or "ask me in 30 days", and every task acts on it from then on. Keep 60 of 620 oils and auction the rest? Type 60 in the Keep box.

Kept something as an upgrade that nobody needs anymore? It comes back and asks again.

## Bag space and bank space, in a few clicks

<!-- Screenshot: Home with the trip line -->

Type `/icanteven` and Home shows what's ready, with counts and value: "Deposit Old Items: 23 ready", "Sell Items That Can Go: 14 (38g)". It even plans the trip: *here: bank (4 tasks) → auction house (8 to list) → vendor (44 to sell)*.

Built-in tasks cover the usual chores:

- Bank old-expansion items; pull upgrades and auctionable BoEs back out
- Sell what can go, junk and spent consumables included
- Move crafting materials to where your crafters can reach them
- Destroy what nothing will take (one click each, and only what you decided or what truly has no buyer)

Save any custom transfer as your own task.

## Warband bank and alts

- Give each character a role (Main, Leveling, Crafting only, Utility), and the addon knows who can use what: "Upgrade for Tankalt (Leveling)", "Used by Stitcher (Tailoring)".
- **Warband (by tab settings)** sends each item to the tab whose Blizzard "assign to" settings match it. Your tab settings are never changed.
- Hand an item to a specific alt, and that character sees **Waiting for You** when it logs in.
- Item tooltips can show how many your whole account holds, and where. `/icanteven where <name>` finds it.

## Sell and auction without the guesswork

- Prices from Auctionator or TSM, or look up your own items at the auction house. Each price shows its source and age.
- Items worth more at auction are flagged at the vendor and never pre-selected for selling.
- **One-button listing:** at the auction house, each item shows the price it will post at. Click once per auction (the game allows one per click).
- **One auction character:** tick "Auctions" on one character, and every other character hands its auctionables to that one through the Warband bank. All your gold and returns end up in one mailbox, and a reminder warns you before auction mail expires.

## Transmog, collectibles and quests

The addon checks what letting go would cost you before it suggests anything:

- Appearances you haven't collected, pets you have room for, toys and recipes you haven't learned
- Items a quest in your log uses; destroying those would drop the quest, so the addon won't
- Set pieces, gear on an upgrade track, and anything in a saved equipment set

## Safety first

- Nothing moves, sells, lists or gets destroyed without your selection and click.
- Every action re-checks the bag slot first; items that moved are skipped.
- Protect, Ignore and Never Sell rules always win.
- Selling stops at 12 items per click, so every sale stays in the vendor's buyback.
- Results are honest: "22 moved, 3 blocked: Warband tab full" rather than a quiet partial move.
- Moves can be undone with `/icanteven undo`.

<!-- Screenshot: a transfer result ("22 moved, 3 blocked") -->

## Plays well with others

This addon decides what should stay. It doesn't replace the addons you already use:

- **Junk sellers** (Scrap, Dejunk): keep them for greys. This addon handles everything that isn't grey.
- **Bag addons** (Baganator, BetterBags, ArkInventory): keep your look. Optional BetterBags categories show Protected, Never Sell, Sell Candidates, For the Warband, Old Content and Waiting for You.
- **Price addons** (Auctionator, TSM): used for prices when installed, never required.

## First 5 minutes

1. Type `/icanteven`. Answer one question: what is this character? A suggestion is ready.
2. Visit a bank. A small notice names what's ready; open it.
3. Review the list, click **Select Movable**, then **Deposit**.
4. Visit a vendor and use **Sell Items That Can Go**.
5. When you have ten minutes, open **Justify every item**.

## Slash commands

- `/icanteven` or `/icant`: open Home
- `/icanteven characters`: roles
- `/icanteven why [all]`: why items are being kept
- `/icanteven where <name>`: find an item across your characters and Warband bank
- `/icanteven explain <name>`: everything the addon knows about one item
- `/icanteven undo`: pre-select the last move to reverse it
- `/icanteven transfer`, `rules`, `settings`, `migration`, `minimap`, `errors`

## FAQ

**Will it sell, move or destroy things automatically?**
No. Every action needs your selection and a click. Pre-selecting items when a task opens is an optional setting, off by default, and destroys are never pre-selected unless you decided on them.

**Does it post auctions?**
Yes, at the auction house: each item shows the price it will post at, and each click posts one auction (the game's rule). Items with no price, or a price far above their usual one, are blocked with the reason so you can price them yourself.

**Do I need Auctionator or TSM?**
No. They make prices better, but the addon can look up prices for your own items at the auction house.

**Can I undo something?**
Moves: `/icanteven undo` pre-selects the last batch so you can move it back. Sales: the addon sells 12 per click so everything stays in the vendor's buyback. Destroys can't be undone, which is why each one takes its own click.

**Why does it say "Getting ready..."?**
After a reload, or when a bank or vendor opens, the game can take a moment to deliver item details. The addon waits for them instead of guessing, then shows one stable result.

**Something sold that I didn't sell. Was it this addon?**
The addon only sells from its own Sell button. If you also run an auto-seller, it may have acted first; the addon reports what it actually sold.

**Why doesn't it know about my other characters?**
Each character appears after logging in once with the addon enabled. After that, you can set its role from any character.

**I only play one character. Is it still useful?**
Yes. Roles matter most with alts, but banking, selling, auction pricing and Justify every item work the same with one character.

## Upgrading from 0.5

Your rules, saved presets and settings carry over. A "What's new" card explains the changes, and `/icanteven migration` lists exactly what was carried over.

## The idea

The addon finds, explains and routes. You decide. It asks at most one question per character, and skipping any question is always safe.

## Support and credits

- Guide and FAQ: https://github.com/majormer/ICantEvenRightNow/wiki
- Bugs and requests: https://github.com/majormer/ICantEvenRightNow/issues
- Optional support on Ko-fi: https://ko-fi.com/finalomega

I Can't Even Right Now (With My Bags and Bank) is a Finalomega Labs project. Source code is MIT licensed; the addon artwork and the Finalomega Labs brand assets are all rights reserved and are not licensed for reuse outside official Finalomega Labs releases.

© 2026 Finalomega Labs. All rights reserved.

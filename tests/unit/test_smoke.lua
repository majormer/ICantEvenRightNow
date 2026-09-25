local T = ...

T.test("addon loads and initializes saved variables", function()
    local game = T.game()
    local db = game:db()
    T.ok(db, "ICantEvenRightNowDB created")
    T.ok(db.rules and db.rules.items, "rules table exists")
    T.ok(game.env.SlashCmdList.ICANTEVEN, "slash command registered")
    T.contains(game:printed(), "Loaded.")
end)

T.test("console opens from the slash command without errors", function()
    local game = T.game()
    game:slash("")
    local UI = game:UI()
    T.ok(UI.frame and UI.frame:IsShown(), "console shown")
end)

T.test("no unexpected undefined globals are read during load and open", function()
    local game = T.game()
    game:slash("")
    game:openBank()
    game:closeBank()
    local allowed = {
        -- Feature checks the addon performs for optional APIs/addons.
        LibStub = true, issecretvalue = true, BetterBags = true, Auctionator = true, TSM_API = true,
        -- Saved variable before the first save.
        ICantEvenRightNowDB = true,
        -- Blizzard frames checked for context detection.
        AuctionHouseFrame = true, MailFrame = true, MerchantFrame = true, ReagentBankFrame = true,
    }
    -- Bank frames from Blizzard and bag addons, probed by name on purpose.
    for _, name in ipairs(game:P().BANK_FRAME_NAMES) do allowed[name] = true end
    local unexpected = {}
    for name in pairs(game.world.missingGlobals) do
        if not allowed[name] then table.insert(unexpected, name) end
    end
    table.sort(unexpected)
    T.eq(table.concat(unexpected, ", "), "", "undefined globals read")
end)

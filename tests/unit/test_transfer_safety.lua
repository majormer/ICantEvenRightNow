local T = ...
local F = require("fixtures")
local I = F.ITEMS

-- Select every visible candidate for a route and return them.
local function selectRoute(game, source, dest)
    local P, UI = game:P(), game:UI()
    UI.transferSource, UI.transferDest = source, dest
    UI.transferSelected = {}
    local candidates = P.GetTransferCandidates(source, dest)
    UI.transferVisible = candidates
    for _, plan in ipairs(candidates) do
        if plan.movable then UI.transferSelected[plan.key] = true end
    end
    return candidates
end

local function execute(game)
    game.world:withHardwareEvent(function() game:Core().ExecuteTransferSelected() end)
end

T.test("deposit moves selected bag items into the bank", function()
    local game = T.game({ setup = F.setup(function(w)
        w:put(0, 1, I.OLD_POTION, 5)
        w:put(0, 2, I.LINEN, 40)
    end) })
    game:openBank()
    local candidates = selectRoute(game, "Bags", "Bank (All Tabs)")
    T.ok(#candidates >= 2, "candidates found")
    execute(game)
    game:advance(2)
    T.eq(game.world:getStack(0, 1), nil, "potion left the bag")
    T.eq(game.world:getStack(0, 2), nil, "linen left the bag")
    local potion = game.world:findItem(I.OLD_POTION)[1]
    T.ok(potion.bagID == 6, "potion is in the character bank tab")
end)

T.test("a stale scan never moves the item now in that slot", function()
    local game = T.game({ setup = F.setup(function(w)
        w:put(0, 1, I.OLD_POTION, 5)
    end) })
    game:openBank()
    selectRoute(game, "Bags", "Bank (All Tabs)")
    -- Bags change after the scan: the potion is replaced by a different item.
    game.world.containers[0].slots[1] = nil
    game.world:put(0, 1, I.BOUND_HELM, 1, { bound = true })
    local mark = game:logMark()
    execute(game)
    game:advance(2)
    local helm = game.world:getStack(0, 1)
    T.ok(helm and helm.itemID == I.BOUND_HELM, "the helm in that slot was not touched")
    T.contains(game:printed(mark), "moved since the last scan")
end)

T.test("a locked item is skipped", function()
    local game = T.game({ setup = F.setup(function(w)
        w:put(0, 1, I.OLD_POTION, 5)
    end) })
    game:openBank()
    selectRoute(game, "Bags", "Bank (All Tabs)")
    game.world:getStack(0, 1).locked = true
    local mark = game:logMark()
    execute(game)
    T.ok(game.world:getStack(0, 1), "item stayed in the bag")
    T.contains(game:printed(mark), "Item is locked")
end)

T.test("nothing moves while the cursor is holding an item", function()
    local game = T.game({ setup = F.setup(function(w)
        w:put(0, 1, I.OLD_POTION, 5)
        w:put(0, 2, I.LINEN, 5)
    end) })
    game:openBank()
    selectRoute(game, "Bags", "Bank (All Tabs)")
    game.world:pickup(0, 2)          -- player is holding the linen
    local mark = game:logMark()
    execute(game)
    T.ok(game.world:getStack(0, 1), "potion stayed in the bag")
    T.contains(game:printed(mark), "Cursor is holding something")
end)

T.test("Protect rule blocks every route", function()
    local game = T.game({ setup = F.setup(function(w)
        w:put(0, 1, I.OLD_POTION, 5)
    end) })
    game:db().rules.items[I.OLD_POTION] = { protect = true }
    game:openBank()
    local candidates = game:P().GetTransferCandidates("Bags", "Bank (All Tabs)")
    T.eq(#candidates, 1)
    T.no(candidates[1].movable, "protected item is not movable")
    T.eq(candidates[1].blocked, "Protected by item rule")
end)

T.test("Never Sell blocks only the vendor route", function()
    local game = T.game({ setup = F.setup(function(w)
        w:put(0, 1, I.OLD_POTION, 5)
    end) })
    game:db().rules.items[I.OLD_POTION] = { neverSell = true }
    game:openVendor()
    local toVendor = game:P().GetTransferCandidates("Bags", "Vendor")
    T.eq(toVendor[1].blocked, "Never sell rule")
    game:closeVendor()
    game:openBank()
    local toBank = game:P().GetTransferCandidates("Bags", "Bank (All Tabs)")
    T.ok(toBank[1].movable, "bank route still allowed")
end)

T.test("vendor sales only happen inside a real click", function()
    local game = T.game({ setup = F.setup(function(w)
        w:put(0, 1, I.OLD_POTION, 5)
    end) })
    game:openVendor()
    selectRoute(game, "Bags", "Vendor")
    -- Outside a hardware event the protected call is blocked by the client.
    local ok = pcall(function() game:Core().ExecuteTransferSelected() end)
    T.no(ok and #game.world.sold > 0, "no sale without a click")
    T.ok(#game.world.blockedActions > 0, "the client blocked the protected call")
end)

T.test("vendor sale inside a click sells and credits money", function()
    local game = T.game({ setup = F.setup(function(w)
        w:put(0, 1, I.OLD_POTION, 5)
    end) })
    game:openVendor()
    selectRoute(game, "Bags", "Vendor")
    execute(game)
    T.eq(#game.world.sold, 1)
    T.eq(game.world.money, 150 * 5)
end)

T.test("bank-to-bank move is blocked when the item is already there", function()
    local game = T.game({ setup = F.setup(function(w)
        w:put(12, 1, I.WARBOUND_TOY, 1)
    end) })
    game:openBank()
    local candidates = game:P().GetTransferCandidates("Warband Bank", "Warband Bank")
    -- Same source and destination is blocked outright.
    T.eq(candidates[1].blocked, "Source and destination are the same")
end)

T.test("quick successive single moves use different target slots", function()
    local game = T.game({ asyncMoves = true, setup = F.setup(function(w)
        w:put(0, 1, I.OLD_POTION, 5)
        w:put(0, 2, I.OLD_SWORD, 1)
    end) })
    game:openBank()
    local P, Core, UI = game:P(), game:Core(), game:UI()
    UI.transferSource, UI.transferDest = "Bags", "Bank (All Tabs)"
    local candidates = P.GetTransferCandidates("Bags", "Bank (All Tabs)")
    game.world:withHardwareEvent(function()
        Core.ExecuteTransferOne(candidates[1])
        Core.ExecuteTransferOne(candidates[2])
    end)
    game:advance(3)
    local a = game.world:findItem(I.OLD_POTION)[1]
    local b = game.world:findItem(I.OLD_SWORD)[1]
    T.ok(a and b, "both items exist")
    T.ok(a.bagID == 6 and b.bagID == 6, "both reached the bank")
    T.neq(a.slot, b.slot, "different target slots")
end)

T.test("item-data retries are bounded when data never loads", function()
    local game = T.game({ setup = F.setup(function(w)
        w:defineItem(9999, { name = "Mystery", cached = false, neverLoads = true })
        w:put(0, 1, 9999, 1)
    end) })
    local scans = 0
    local Core = game:Core()
    local original = Core.ScanInventory
    Core.ScanInventory = function(...) scans = scans + 1 return original(...) end
    original("bags", true)
    game:advance(60)
    T.ok(scans <= 4, "at most three retries after the first scan (got " .. scans .. ")")
end)

T.test("full bags: withdrawing is allowed only onto a partial stack of the same item", function()
    local game = T.game({ setup = F.setup(function(w)
        for bag = 1, 4 do w:setContainer(bag, 0) end
        for slot = 1, 20 do w:put(0, slot, I.OLD_SWORD, 1) end
        w.containers[0].slots[20] = nil
        w:put(0, 20, I.LINEN, 150)                  -- partial stack (max 200)
        w:put(6, 1, I.LINEN, 30)
        w:put(6, 2, I.OLD_POTION, 3)
    end) })
    game:openBank()
    local P = game:P()
    P.WithEvaluationCache(function()
        local blocked = {}
        for _, plan in ipairs(P.GetTransferCandidates("Bank (All Tabs)", "Bags")) do
            blocked[plan.item.itemID] = plan.blocked or "ok"
        end
        T.eq(blocked[I.LINEN], "ok", "linen can join the partial stack")
        T.eq(blocked[I.OLD_POTION], "No empty bag slots")
    end)
end)
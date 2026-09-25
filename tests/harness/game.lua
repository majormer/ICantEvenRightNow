-- Loads the addon into a simulated world and exposes test helpers.

local World = require("wow")

local Game = {}
Game.__index = Game

local ADDON_NAME = "ICantEvenRightNow"

local function readTocFiles(root)
    local files = {}
    local handle = assert(io.open(root .. "/" .. ADDON_NAME .. ".toc", "r"))
    for line in handle:lines() do
        line = line:gsub("\r$", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" and not line:match("^#") then
            table.insert(files, (line:gsub("\\", "/")))
        end
    end
    handle:close()
    return files
end

-- opts:
--   savedVariables   table copied into ICantEvenRightNowDB before load
--   player           overrides for world.player
--   setup(world)     called before the addon loads (define items, bank tabs...)
--   noLogin          load files but do not fire login events
--   asyncMoves       item moves complete after latency (like the real server)
function Game.new(opts)
    opts = opts or {}
    local self = setmetatable({}, Game)
    self.world = World.new(opts)
    self.env = self.world.env
    self.ns = {}
    if opts.savedVariables then
        self.env.ICantEvenRightNowDB = World.deepcopy(opts.savedVariables)
    end
    if opts.setup then opts.setup(self.world, self) end

    for _, file in ipairs(readTocFiles(ROOT)) do
        local chunk, err = loadfile(ROOT .. "/" .. file)
        if not chunk then error("load " .. file .. ": " .. tostring(err), 0) end
        setfenv(chunk, self.env)
        chunk(ADDON_NAME, self.ns)
    end

    if not opts.noLogin then self:login() end
    return self
end

function Game:login()
    self.world:fire("ADDON_LOADED", ADDON_NAME)
    self.world:fire("PLAYER_LOGIN")
    self.world:fire("PLAYER_ENTERING_WORLD", true, false)
    self.world:advance(0)
end

-- Simulate logging out: returns a copy of the saved variables as WoW would write them.
function Game:logout()
    self.world:fire("PLAYER_LOGOUT")
    return World.deepcopy(self.env.ICantEvenRightNowDB)
end

function Game:P() return self.ns.Private end
function Game:Core() return self.ns.Core end
function Game:db() return self.env.ICantEvenRightNowDB end
function Game:UI() return self.ns.Private.UI end

function Game:advance(seconds) self.world:advance(seconds) end
function Game:openBank() self.world:openBank(); self.world:advance(0) end
function Game:closeBank() self.world:closeBank(); self.world:advance(0) end
function Game:openVendor() self.world:openVendor(); self.world:advance(0) end
function Game:closeVendor() self.world:closeVendor(); self.world:advance(0) end
function Game:openAuctionHouse() self.world:openAuctionHouse(); self.world:advance(0) end
function Game:closeAuctionHouse() self.world:closeAuctionHouse(); self.world:advance(0) end

function Game:slash(msg)
    local handler = self.env.SlashCmdList and self.env.SlashCmdList.ICANTEVEN
    assert(handler, "slash command not registered")
    handler(msg or "")
end

-- A real mouse click: fires OnClick inside a hardware event.
function Game:click(widget, button)
    assert(widget, "click: widget is nil")
    assert(widget:IsVisible(), "click: widget is not visible: " .. tostring(widget._text or widget))
    assert(widget:IsEnabled(), "click: widget is disabled: " .. tostring(widget._text or widget))
    local world = self.world
    world:withHardwareEvent(function()
        if widget._type == "CheckButton" then widget._checked = not widget._checked end
        widget:_fire("OnClick", button or "LeftButton", true)
    end)
end

-- Type into an edit box (fires OnTextChanged like user input).
function Game:type(editBox, text)
    editBox:SetText(text)
    editBox:_fire("OnTextChanged", true)
end

-- Visible widgets whose text contains `text`.
function Game:findText(text, opts)
    return self.world.frames.findByText(text, opts)
end

-- The single visible widget whose text contains `text` (errors if 0 or many buttons match).
function Game:button(text)
    local matches = {}
    for _, w in ipairs(self:findText(text)) do
        if w._type == "Button" or w._type == "CheckButton" then table.insert(matches, w) end
    end
    assert(#matches > 0, "no visible button with text: " .. text)
    assert(#matches == 1, "more than one visible button with text: " .. text)
    return matches[1]
end

-- Chat output printed by the addon since the game started (or since mark).
function Game:printed(fromIndex)
    local out = {}
    for i = fromIndex or 1, #self.world.log do out[#out + 1] = self.world.log[i] end
    return table.concat(out, "\n")
end

function Game:logMark() return #self.world.log + 1 end

return Game

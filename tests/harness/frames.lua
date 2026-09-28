-- Headless widget fake for offline tests.
-- Frames record their state (text, shown, enabled, checked, scripts, anchors)
-- so tests can inspect the UI and fire scripts without a game client.
-- Unknown Set*/Get*/Is* methods fall back to generic property storage; any
-- other unknown capitalized member is a harmless stub so Blizzard template
-- children (frame.CloseButton, frame.Text, ...) can be used without errors.

local Frames = {}

-- A universal stub: callable, indexable, always returns itself or nil.
local Stub
Stub = setmetatable({}, {
    __call = function() return nil end,
    __index = function() return Stub end,
})
Frames.Stub = Stub

function Frames.new(world)
    local lib = { all = {}, byName = {} }
    local Widget = {}

    local function generic(key)
        local setName = key:match("^Set(%u%w*)$")
        if setName then
            return function(self, value, ...)
                self._props[setName] = value
                self._propArgs[setName] = { value, ... }
            end
        end
        local getName = key:match("^Get(%u%w*)$")
        if getName then
            return function(self) return self._props[getName] end
        end
        local isName = key:match("^Is(%u%w*)$")
        if isName then
            return function(self) return self._props[isName] and true or false end
        end
        return nil
    end

    local mt = {}
    mt.__index = function(self, key)
        local method = Widget[key]
        if method ~= nil then return method end
        if type(key) == "string" and key:match("^%u") then
            local g = generic(key)
            if g then return g end
            return Stub
        end
        return nil
    end
    mt.__tostring = function(self)
        return "Widget<" .. tostring(self._type) .. ":" .. tostring(self._name or "?") .. ">"
    end

    local function newWidget(objectType, name, parent, template)
        local w = setmetatable({
            _type = objectType,
            _name = name,
            _parent = parent,
            _children = {},
            _props = {},
            _propArgs = {},
            _scripts = {},
            _hooks = {},
            _events = {},
            _shown = true,
            _enabled = true,
            _checked = false,
            _text = nil,
            _points = {},
            _width = 0,
            _height = 0,
            _template = template,
        }, mt)
        if parent and parent._children then table.insert(parent._children, w) end
        table.insert(lib.all, w)
        if name then
            lib.byName[name] = w
            if world.env then rawset(world.env, name, w) end
        end
        return w
    end

    local function applyTemplate(w, template)
        if not template then return end
        for part in tostring(template):gmatch("[^,%s]+") do
            if part == "UICheckButtonTemplate" or part == "InterfaceOptionsCheckButtonTemplate" then
                w.Text = newWidget("FontString", nil, w)
                w.text = w.Text
            elseif part == "BasicFrameTemplateWithInset" or part == "BasicFrameTemplate"
                or part == "PortraitFrameTemplate" or part == "ButtonFrameTemplate" then
                w.CloseButton = newWidget("Button", nil, w)
                w.CloseButton:SetScript("OnClick", function() w:Hide() end)
                w.TitleBg = newWidget("Texture", nil, w)
                w.TitleText = newWidget("FontString", nil, w)
                w.TitleContainer = newWidget("Frame", nil, w)
                w.TitleContainer.TitleText = w.TitleText
                w.Inset = newWidget("Frame", nil, w)
            elseif part == "FauxScrollFrameTemplate" or part == "UIPanelScrollFrameTemplate"
                or part == "ScrollFrameTemplate" then
                w.ScrollBar = newWidget("Slider", nil, w)
                w._offset = 0
            elseif part == "UIPanelButtonTemplate" or part == "UIPanelButtonNoTooltipTemplate" then
                w.Text = newWidget("FontString", nil, w)
            end
        end
    end

    function lib.CreateFrame(objectType, name, parent, template)
        local w = newWidget(objectType or "Frame", name, parent, template)
        applyTemplate(w, template)
        return w
    end

    -- ---------------------------------------------------------------------
    -- Visibility
    -- ---------------------------------------------------------------------
    function Widget:Show()
        local was = self._shown
        self._shown = true
        if not was then self:_fire("OnShow") end
    end
    function Widget:Hide()
        local was = self._shown
        self._shown = false
        if was then self:_fire("OnHide") end
    end
    function Widget:SetShown(shown) if shown then self:Show() else self:Hide() end end
    function Widget:IsShown() return self._shown end
    function Widget:IsVisible()
        local w = self
        while w do
            if not w._shown then return false end
            w = w._parent
        end
        return true
    end

    -- ---------------------------------------------------------------------
    -- Text
    -- ---------------------------------------------------------------------
    -- Like the real client, setting text from code fires OnTextChanged with
    -- userInput = false (edit boxes only), deferred to a later frame.
    function Widget:SetText(text)
        local new = text ~= nil and tostring(text) or nil
        local changed = new ~= self._text
        self._text = new
        -- Fired on a later frame, like the client (after any refresh guard).
        if changed and self._type == "EditBox" then
            world:after(0, function() self:_fire("OnTextChanged", false) end)
        end
    end
    function Widget:GetText() return self._text end
    function Widget:SetFormattedText(fmt, ...) self._text = string.format(fmt, ...) end
    function Widget:GetStringWidth() return #(self._text or "") * 6 end
    function Widget:GetNumber() return tonumber(self._text) or 0 end
    function Widget:SetNumber(n) self._text = tostring(n) end

    -- ---------------------------------------------------------------------
    -- Scripts and events
    -- ---------------------------------------------------------------------
    function Widget:SetScript(name, fn) self._scripts[name] = fn end
    function Widget:GetScript(name) return self._scripts[name] end
    function Widget:HasScript() return true end
    function Widget:HookScript(name, fn)
        self._hooks[name] = self._hooks[name] or {}
        table.insert(self._hooks[name], fn)
    end
    function Widget:_fire(name, ...)
        local fn = self._scripts[name]
        if fn then fn(self, ...) end
        for _, hook in ipairs(self._hooks[name] or {}) do hook(self, ...) end
    end
    function Widget:RegisterEvent(event)
        self._events[event] = true
        world:_registerEventFrame(self)
    end
    function Widget:UnregisterEvent(event) self._events[event] = nil end
    function Widget:UnregisterAllEvents() self._events = {} end
    function Widget:IsEventRegistered(event) return self._events[event] and true or false end
    function Widget:RegisterUnitEvent(event) self:RegisterEvent(event) end

    -- Programmatic click (not a hardware event). Tests use game:click().
    function Widget:Click(button)
        if self._enabled then self:_fire("OnClick", button or "LeftButton", false) end
    end

    -- ---------------------------------------------------------------------
    -- Enabled / checked
    -- ---------------------------------------------------------------------
    function Widget:Enable() self._enabled = true end
    function Widget:Disable() self._enabled = false end
    function Widget:SetEnabled(enabled) self._enabled = enabled and true or false end
    function Widget:IsEnabled() return self._enabled end
    function Widget:SetChecked(checked) self._checked = checked and true or false end
    function Widget:GetChecked() return self._checked end

    -- ---------------------------------------------------------------------
    -- Hierarchy
    -- ---------------------------------------------------------------------
    function Widget:GetName() return self._name end
    function Widget:GetParent() return self._parent end
    function Widget:SetParent(parent)
        if self._parent and self._parent._children then
            for i, child in ipairs(self._parent._children) do
                if child == self then table.remove(self._parent._children, i) break end
            end
        end
        self._parent = parent
        if parent and parent._children then table.insert(parent._children, self) end
    end
    function Widget:GetChildren() return unpack(self._children) end
    function Widget:GetObjectType() return self._type end
    function Widget:IsObjectType(t) return self._type == t end
    function Widget:CreateTexture(name) return newWidget("Texture", name, self) end
    function Widget:CreateFontString(name) return newWidget("FontString", name, self) end
    function Widget:CreateMaskTexture(name) return newWidget("Texture", name, self) end
    function Widget:CreateLine(name) return newWidget("Line", name, self) end
    function Widget:CreateAnimationGroup()
        local g = newWidget("AnimationGroup", nil, self)
        g.CreateAnimation = function(grp) return newWidget("Animation", nil, grp) end
        g.Play = function(grp) grp._playing = true end
        g.Stop = function(grp) grp._playing = false end
        g.IsPlaying = function(grp) return grp._playing and true or false end
        return g
    end

    -- ---------------------------------------------------------------------
    -- Layout
    -- ---------------------------------------------------------------------
    function Widget:SetPoint(point, relativeTo, relativePoint, x, y)
        table.insert(self._points, { point, relativeTo, relativePoint, x, y })
    end
    function Widget:ClearAllPoints() self._points = {} end
    function Widget:SetAllPoints(relativeTo) self._points = { { "ALL", relativeTo } } end
    function Widget:GetNumPoints() return #self._points end
    function Widget:GetPoint(i)
        local p = self._points[i or 1]
        if p then return p[1], p[2], p[3], p[4], p[5] end
    end
    function Widget:SetSize(w, h) self._width, self._height = w or 0, h or 0 end
    function Widget:SetWidth(w) self._width = w or 0 end
    function Widget:SetHeight(h) self._height = h or 0 end
    function Widget:GetWidth() return self._width end
    function Widget:GetHeight() return self._height end
    function Widget:GetSize() return self._width, self._height end
    function Widget:GetLeft() return 0 end
    function Widget:GetTop() return 0 end
    function Widget:GetRight() return self._width end
    function Widget:GetBottom() return 0 end
    function Widget:GetCenter() return self._width / 2, self._height / 2 end
    function Widget:GetEffectiveScale() return 1 end
    function Widget:GetScale() return 1 end
    function Widget:GetFrameLevel() return self._props.FrameLevel or 1 end
    function Widget:GetFrameStrata() return self._props.FrameStrata or "MEDIUM" end

    -- ---------------------------------------------------------------------
    -- Edit boxes, sliders
    -- ---------------------------------------------------------------------
    function Widget:SetFocus() self._focus = true end
    function Widget:ClearFocus() self._focus = false end
    function Widget:HasFocus() return self._focus and true or false end
    function Widget:SetValue(v) self._value = v; self:_fire("OnValueChanged", v, false) end
    function Widget:GetValue() return self._value or 0 end
    function Widget:SetMinMaxValues(lo, hi) self._min, self._max = lo, hi end
    function Widget:GetMinMaxValues() return self._min or 0, self._max or 0 end
    function Widget:SetVerticalScroll(v) self._vscroll = v end
    function Widget:GetVerticalScroll() return self._vscroll or 0 end

    -- ---------------------------------------------------------------------
    -- Test helpers (not part of the WoW API)
    -- ---------------------------------------------------------------------
    -- Iterate over this widget and all descendants.
    function Widget:_descendants()
        local out = {}
        local function walk(w)
            table.insert(out, w)
            for _, child in ipairs(w._children) do walk(child) end
        end
        walk(self)
        return out
    end

    -- EnumerateFrames(previous) iterates named and unnamed frames in creation order.
    function lib.EnumerateFrames(previous)
        local index = 0
        if previous then
            for i, w in ipairs(lib.all) do
                if w == previous then index = i break end
            end
        end
        for i = index + 1, #lib.all do
            local w = lib.all[i]
            if w._type ~= "Texture" and w._type ~= "FontString" then return w end
        end
        return nil
    end

    -- Find visible widgets whose text contains the given plain substring.
    function lib.findByText(text, opts)
        opts = opts or {}
        local found = {}
        for _, w in ipairs(lib.all) do
            if w._text and w._text:find(text, 1, true) and (opts.hidden or w:IsVisible()) then
                table.insert(found, w)
            end
        end
        return found
    end

    lib.Widget = Widget
    return lib
end

return Frames

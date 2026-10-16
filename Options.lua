-- GatherPath Forever: the window (/gpf), in the shared look (Theme.lua).
-- Tabs down the left: Routes (the ones you have), New route, Display.
--
-- Layout rules: rows 26 apart; a dropdown after a row label starts at DROP_X;
-- lists that can grow (routes, kinds of node) scroll.

local ADDON, ns = ...
local GP = ns.GP
local T = ns.Theme
local C, Text, FlatButton, Card = T.C, T.Text, T.FlatButton, T.Card

local PAGE_W = T.WINDOW.PAGE_W
local BODY_H = T.WINDOW.BODY_H
local DROP_X = 52
local COL2 = 270

local refreshers = {}
local function AddRefresher(fn) table.insert(refreshers, fn) end

-- The window's widgets the tests look at
local refs = {}
GP.ui = refs

-- A colored square that opens the game's color picker. get(self) is the color
-- now ({ r, g, b }, nil = nothing to pick), set(self, r, g, b) keeps a new one.
local function Swatch(parent, get, set, title, tip)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(22, 22)
    b.fill = T.Fill(b, { 1, 1, 1, 1 }, "ARTWORK")
    T.Border(b, C.edge)
    function b:Paint(c) self.fill:SetColorTexture(c[1], c[2], c[3], 1) end
    T.Disabler(b, { b })
    b:SetScript("OnClick", function(self)
        local now = not self.disabled and get(self)
        local picker = ColorPickerFrame
        if not (now and picker and picker.SetupColorPickerAndShow) then return end
        local before = { unpack(now) }
        picker:SetupColorPickerAndShow({
            r = before[1], g = before[2], b = before[3], hasOpacity = false,
            swatchFunc = function()
                local r, g, bl = picker:GetColorRGB()
                set(self, r, g, bl)
            end,
            cancelFunc = function()
                set(self, before[1], before[2], before[3])
            end,
        })
    end)
    T.Tooltip(b, title, tip)
    return b
end

---------------------------------------------------------------------------
-- A small "are you sure" window
---------------------------------------------------------------------------
function GP:Confirm(text, yesLabel, onYes)
    local f = self.confirmWindow
    if not f then
        f = CreateFrame("Frame", "GatherPathForeverConfirm", UIParent)
        f:SetSize(380, 130)
        f:SetPoint("CENTER", 0, 80)
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:SetToplevel(true)
        f:EnableMouse(true)
        f:Hide()
        table.insert(UISpecialFrames, "GatherPathForeverConfirm")   -- Escape is Cancel
        T.Fill(f, C.win)
        T.Border(f, C.edge)
        f.text = Text(f, "", "GameFontHighlight")
        f.text:SetPoint("TOPLEFT", 16, -16)
        f.text:SetWidth(348)
        f.text:SetWordWrap(true)
        f.no = FlatButton(f, "Cancel", 100)
        f.no:SetPoint("BOTTOMRIGHT", -16, 14)
        f.no:SetScript("OnClick", function() f:Hide() end)
        f.yes = FlatButton(f, "", 120)
        f.yes:SetPoint("RIGHT", f.no, "LEFT", -8, 0)
        self.confirmWindow = f
    end
    f.text:SetText(text)
    f.yes:SetText(yesLabel)
    f.yes:SetScript("OnClick", function()
        f:Hide()
        onYes()
    end)
    f:Show()
    return f
end

---------------------------------------------------------------------------
-- Routes tab
---------------------------------------------------------------------------
local ROW_H = 74
local INFO_W = PAGE_W - 16 - 84 - 40 - 10   -- from under the name to Show
local routesZone   -- the map whose routes are listed

local function RoutesZoneChoices()
    local list = GP:RouteZones()
    local here = GP:PlayerMap()
    local has = false
    for _, m in ipairs(list) do if m == here then has = true end end
    if here and not has then table.insert(list, 1, here) end
    return list
end

local function PickRoutesZone()
    local list = RoutesZoneChoices()
    for _, m in ipairs(list) do if m == routesZone then return end end
    local here = GP:PlayerMap()
    if here and #GP:RoutesOn(here) > 0 then routesZone = here return end
    routesZone = GP:RouteZones()[1] or here
end

local function BuildRoutes(p)
    T.RowLabel(p, "Zone", 0, 0)
    local zone = T.Dropdown(p, 300, {}, function(k) return GP:MapName(k) end,
        function() return routesZone end, function(k) routesZone = k; GP:RefreshConfig() end)
    zone:SetPoint("TOPLEFT", DROP_X, 0)
    zone.menuScroll = 300
    refs.routesZone = zone

    local make = FlatButton(p, "New route", 110)
    make:SetPoint("TOPRIGHT", 0, 0)
    make:SetScript("OnClick", function() GP:NewRouteInWindow(routesZone) end)
    T.Tooltip(make, "New route", "Make a route in the zone picked here.")
    refs.routesNew = make

    local holder = CreateFrame("Frame", nil, p)
    holder:SetPoint("TOPLEFT", 0, -34)
    holder:SetSize(PAGE_W, BODY_H - 34)
    local scroll = T.ScrollArea(holder, BODY_H - 34)
    local list = scroll.child
    local empty = T.Note(p, "", 0, -44, PAGE_W)
    refs.routesEmpty = empty
    local rows = {}
    refs.routeRows = rows

    local function Row(i)
        if rows[i] then return rows[i] end
        local r = CreateFrame("Frame", nil, list)
        r:SetSize(PAGE_W - 16, ROW_H - 6)
        T.Fill(r, C.card)
        T.Border(r, C.line)
        -- top: color, name, Edit, Rebuild, Delete; below: what it is, Show
        r.swatch = Swatch(r,
            function(b) return b.route and b.route.color end,
            function(b, cr, cg, cb) GP:SetRouteColor(b.route, cr, cg, cb) end,
            "Line color", "Click to pick the color of this route's line.")
        r.swatch:SetPoint("TOPLEFT", 10, -8)
        r.name = T.EditBox(r, 230)
        r.name:SetPoint("LEFT", r.swatch, "RIGHT", 8, 0)
        local function rename(self)
            if r.route and self:GetText() ~= r.route.name then GP:RenameRoute(r.route, self:GetText()) end
            if r.route then self:SetText(r.route.name) end
        end
        r.name:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        r.name:SetScript("OnEditFocusLost", rename)
        r.edit = FlatButton(r, "Edit", 60, 20)
        r.edit:SetPoint("LEFT", r.name, "RIGHT", 8, 0)
        r.edit:SetScript("OnClick", function(self)
            if self.disabled or not r.route then return end
            GP:EditRouteInWindow(r.route)
        end)
        T.Disabler(r.edit, { r.edit })
        T.Tooltip(r.edit, "Edit", "Change this route's zone, nodes, name and pass distance, "
            .. "then find its loop again.")
        r.rebuild = FlatButton(r, "Rebuild", 76, 20)
        r.rebuild:SetPoint("LEFT", r.edit, "RIGHT", 6, 0)
        r.rebuild:SetScript("OnClick", function(self)
            if self.disabled or not r.route then return end
            GP:RebuildRoute(r.route)
        end)
        T.Disabler(r.rebuild, { r.rebuild })
        T.Tooltip(r.rebuild, "Rebuild", "Reads this route's nodes from GatherMate2 again (it may know more by now) "
            .. "and finds the shortest loop again.")
        r.delete = FlatButton(r, "Delete", 70, 20)
        r.delete:SetPoint("LEFT", r.rebuild, "RIGHT", 6, 0)
        r.info = Text(r, "", "GameFontDisableSmall")
        r.info:SetPoint("TOPLEFT", 40, -38)
        r.info:SetWidth(INFO_W)
        r.info:SetWordWrap(true)
        r.show = T.LabeledSwitch(r, "Show", PAGE_W - 16 - 84, -40)
        r.show:SetScript("OnClick", function(self)
            if r.route then GP:SetRouteShown(r.route, not self:IsOn()) end
        end)
        T.Tooltip(r.show, "Show", "Draw this route on the world map and the minimap.")
        r.delete:SetScript("OnClick", function()
            local route = r.route
            if not route then return end
            GP:Confirm(("Delete the route |cffffd100%s|r?"):format(route.name), "Delete",
                function() GP:DeleteRoute(route) end)
        end)
        rows[i] = r
        return r
    end

    AddRefresher(function()
        PickRoutesZone()
        zone.keys = RoutesZoneChoices()
        zone:Refresh()
        local routes = routesZone and GP:RoutesOn(routesZone) or {}
        for i, route in ipairs(routes) do
            local r = Row(i)
            r.route = route
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
            r:Show()
            r.swatch.route = route
            r.swatch:Paint(route.color)
            if not r.name:HasFocus() then r.name:SetText(route.name) end
            r.show:SetOn(route.shown)
            if route.working then
                r.info:SetText("Working out the shortest loop...")
            else
                local kinds = {}
                for kind, names in pairs(route.kinds) do
                    if next(names) then kinds[#kinds + 1] = GP:KindName(kind) end
                end
                table.sort(kinds)
                -- two short lines, so nothing is cut off
                local line2 = (route.sight or 0) > 0 and ("\nPasses within " .. route.sight .. " yards") or ""
                r.info:SetText(("%d nodes  -  %s round  -  %s%s"):format(GP:RouteNodes(route),
                    GP.FormatYards(route.length or GP:RouteLength(route)), table.concat(kinds, ", "), line2))
            end
            r.rebuild:SetDisabled(GP:Busy())
            r.edit:SetDisabled(route.working)
        end
        for i = #routes + 1, #rows do rows[i]:Hide(); rows[i].route = nil end
        scroll:SetContent(PAGE_W - 16, math.max(1, #routes * ROW_H), true)
        if #routes == 0 then
            empty:SetText(GP:HasGatherMate()
                and "No routes in this zone yet. Click New route to make one."
                or "GatherPath needs GatherMate2, where the herb and ore nodes come from. Install it from CurseForge, then /reload.")
        else
            empty:SetText("")
        end
    end)
end

---------------------------------------------------------------------------
-- New route tab (also where a route is edited)
---------------------------------------------------------------------------
-- What's picked. Opening the tab starts it blank (ResetNew); Edit fills it
-- from a route (EditInWindow) and Save changes that route.
local newZone, picked, newSight, editing = nil, {}, nil, nil
local nameBox

local function Sight() return newSight or GP.DEFAULTS.sight end

local function ResetNew()
    newZone, picked, newSight, editing = nil, {}, nil, nil
    if nameBox then nameBox:SetText(""); nameBox:ClearFocus() end
end

local function EditInWindow(route)
    newZone, newSight, editing = route.mapID, route.sight or 0, route
    picked = {}
    for kind, names in pairs(route.kinds) do
        for n in pairs(names) do
            picked[kind] = picked[kind] or {}
            picked[kind][n] = true
        end
    end
    nameBox:SetText(route.name)
    nameBox:ClearFocus()
end

local function BuildNew(p, page)
    T.RowLabel(p, "Zone", 0, 0)
    local zone = T.Dropdown(p, 300, {}, function(k) return k and GP:MapName(k) or "Pick a zone" end,
        function() return newZone end, function(k)
            if k ~= newZone then newZone, picked = k, {} end
            GP:RefreshConfig()
        end)
    zone:SetPoint("TOPLEFT", DROP_X, 0)
    zone.menuScroll = 300
    refs.newZone = zone
    local here = FlatButton(p, "My zone", 90)
    here:SetPoint("LEFT", zone, "RIGHT", 8, 0)
    here:SetScript("OnClick", function()
        local m = GP:PlayerMap()
        if m and m ~= newZone then newZone, picked = m, {} end
        GP:RefreshConfig()
    end)
    T.Tooltip(here, "My zone", "Pick the zone you're in.")
    refs.myZone = here

    local LIST_H = 210
    local holder = CreateFrame("Frame", nil, p)
    holder:SetPoint("TOPLEFT", 0, -34)
    holder:SetSize(PAGE_W, LIST_H)
    T.Fill(holder, C.card)
    T.Border(holder, C.line)
    local inner = CreateFrame("Frame", nil, holder)
    inner:SetPoint("TOPLEFT", 10, -8)
    inner:SetPoint("BOTTOMRIGHT", -4, 8)
    local scroll = T.ScrollArea(inner, LIST_H - 16)
    local list = scroll.child
    local note = T.Note(holder, "", 12, -12, PAGE_W - 24)
    refs.newNote = note
    local heads, switches = {}, {}
    refs.kindSwitches = switches

    -- below the list: name, passes within, make (or save and cancel)
    local y = -34 - LIST_H - 14
    T.RowLabel(p, "Name", 0, y)
    local name = T.EditBox(p, 300)
    name:SetPoint("TOPLEFT", DROP_X, y)
    nameBox = name
    local hint = Text(name, "", "GameFontDisableSmall")
    hint:SetPoint("LEFT", 6, 0)
    name:SetScript("OnEditFocusGained", function() hint:Hide() end)
    name:SetScript("OnEditFocusLost", function(self) hint:SetShown(self:GetText() == "") end)
    name:SetScript("OnTextChanged", function(self) hint:SetShown(self:GetText() == "" and not self:HasFocus()) end)
    refs.newName = name

    local sight = T.Slider(p, "Route passes within", 0, y - 36, 300, Sight,
        function(v) newSight = v end,
        GP.RANGES.sight[1], GP.RANGES.sight[2], " yards", 10, nil, "Off")
    T.Tooltip(sight, "Route passes within",
        "With Find Herbs or Find Minerals on, you see a node on the minimap before you reach it. "
        .. "The route only has to come this close to each node, so it cuts corners and is shorter, "
        .. "and nodes close together become one stop. Off takes you right up to every node.")
    AddRefresher(sight.Refresh)
    refs.sightSlider = sight

    local make = FlatButton(p, "Make route", 130, 26)
    make:SetPoint("TOPRIGHT", 0, y - 40)
    refs.makeButton = make
    make:SetScript("OnClick", function(self)
        if self.disabled then return end
        local kinds = {}
        for kind, names in pairs(picked) do
            for n, on in pairs(names) do
                if on then
                    kinds[kind] = kinds[kind] or {}
                    kinds[kind][n] = true
                end
            end
        end
        local opts = { mapID = newZone, kinds = kinds, name = name:GetText(), sight = Sight() }
        local route
        if editing then
            route = GP:EditRoute(editing, opts) and editing
        else
            route = GP:NewRoute(opts)
        end
        if route then
            ResetNew()
            routesZone = route.mapID
            GP:OpenConfig("routes")
        end
    end)
    T.Disabler(make, { make })

    local cancel = FlatButton(p, "Cancel", 130, 22)
    cancel:SetPoint("TOPRIGHT", 0, y - 74)
    cancel:SetScript("OnClick", function()
        local route = editing
        ResetNew()
        if route then routesZone = route.mapID end
        GP:OpenConfig("routes")
    end)
    T.Tooltip(cancel, "Cancel", "Leave the route as it was.")
    refs.cancelButton = cancel

    local function Head(i)
        if heads[i] then return heads[i] end
        heads[i] = Text(list, "", "GameFontNormalSmall", C.orange)
        return heads[i]
    end
    local function Switch(i)
        if switches[i] then return switches[i] end
        local sw = T.LabeledSwitch(list, "", 0, 0, 200)
        sw:SetScript("OnClick", function(self)
            local e = self.entry
            if not e then return end
            picked[e.kind] = picked[e.kind] or {}
            picked[e.kind][e.name] = not self:IsOn() or nil
            GP:RefreshConfig()
        end)
        switches[i] = sw
        return sw
    end

    AddRefresher(function()
        -- the route being edited was deleted meanwhile
        if editing then
            local found = false
            for _, r in ipairs(GP.db.routes) do if r == editing then found = true end end
            if not found then ResetNew() end
        end
        page.title:SetText(editing and "Edit route" or "New route")
        zone.keys = GP:GatherZones()
        zone:Refresh()
        local nodes = newZone and GP:ZoneNodes(newZone) or {}
        local yy, nh, ns_, col = 0, 0, 0, 0
        local lastKind
        for _, e in ipairs(nodes) do
            if e.kind ~= lastKind then
                if col == 1 then yy = yy - 26 end
                col = 0
                nh = nh + 1
                local h = Head(nh)
                h:ClearAllPoints()
                h:SetPoint("TOPLEFT", 0, yy - (nh > 1 and 6 or 0))
                h:SetText(GP:KindName(e.kind):upper())
                h:Show()
                yy = yy - 22 - (nh > 1 and 6 or 0)
                lastKind = e.kind
            end
            ns_ = ns_ + 1
            local sw = Switch(ns_)
            sw.entry = e
            sw:ClearAllPoints()
            sw:SetPoint("TOPLEFT", col == 0 and 0 or COL2 - 10, yy)
            sw.label:SetText(("%s |cff8a8070(%d)|r"):format(e.name, e.count))
            T.ClickableLabel(sw, sw.label)
            sw:SetOn(picked[e.kind] and picked[e.kind][e.name] or false)
            sw:Show()
            sw.label:Show()
            if col == 1 then yy = yy - 26 end
            col = 1 - col
        end
        if col == 1 then yy = yy - 26 end
        for i = nh + 1, #heads do heads[i]:Hide() end
        for i = ns_ + 1, #switches do switches[i]:Hide(); switches[i].label:Hide(); switches[i].entry = nil end
        scroll:SetContent(PAGE_W - 30, math.max(1, -yy), true)

        if not GP:HasGatherMate() then
            note:SetText("GatherPath needs GatherMate2, where the herb and ore nodes come from. "
                .. "Install it from CurseForge, then /reload.")
        elseif not newZone then
            note:SetText("Pick a zone above, or click My zone for the one you're in.")
        elseif #nodes == 0 then
            note:SetText("GatherMate2 has no nodes in " .. GP:MapName(newZone) .. " yet. Gather there (or import "
                .. "GatherMate2 data), then come back.")
        else
            note:SetText("")
        end

        local any = false
        for _, names in pairs(picked) do if next(names) then any = true end end
        local kinds = {}
        for kind, names in pairs(picked) do if next(names) then kinds[kind] = names end end
        hint:SetText(any and ("Name: " .. GP:RouteName(newZone, kinds)) or "Name (made from what you pick)")
        hint:SetShown(name:GetText() == "" and not name:HasFocus())
        make:SetDisabled(not any or GP:Busy())
        make:SetText(GP:Busy() and "Working..." or editing and "Save changes" or "Make route")
        cancel:SetShown(editing ~= nil)
    end)
end

---------------------------------------------------------------------------
-- Display tab
---------------------------------------------------------------------------
local function Setting(parent, text, x, y, key, tip, after)
    local sw = T.LabeledSwitch(parent, text, x, y)
    sw:SetScript("OnClick", function(self)
        GP.db[key] = not self:IsOn()
        if after then after() end
        GP:Changed()
    end)
    if tip then T.Tooltip(sw, text, tip) end
    AddRefresher(function() sw:SetOn(GP.db[key]) end)
    return sw
end

local function Slider(parent, text, x, y, key, suffix, tip)
    local r = GP.RANGES[key]
    local s = T.Slider(parent, text, x, y, 244,
        function() return GP.db[key] end,
        function(v) GP.db[key] = v; GP:Changed() end,
        r[1], r[2], suffix)
    if tip then T.Tooltip(s, text, tip) end
    AddRefresher(s.Refresh)
    return s
end

-- "Each route's own color" and, under it, the one color for every line on
-- that map ("world" or "minimap"), greyed out while routes keep their own
local function LineColor(parent, x, y, where, place)
    local key = where .. "RouteColor"
    local sw = Setting(parent, "Each route's own color", x, y, key,
        "Draw each route " .. place .. " in the color it has on the Routes tab. "
        .. "Turn this off to draw every route there in the color below.")
    local swatch = Swatch(parent,
        function() return GP.db[where .. "Color"] end,
        function(_, r, g, b) GP:SetLineColor(where, r, g, b) end,
        "Line color", "Click to pick the color of every route's line " .. place
        .. ". Turn off Each route's own color to use it.")
    swatch:SetPoint("TOPLEFT", x, y - 28)
    local label = Text(parent, "Line color", "GameFontHighlight")
    label:SetPoint("LEFT", swatch, "RIGHT", 8, 0)
    AddRefresher(function()
        swatch:Paint(GP.db[where .. "Color"])
        swatch:SetDisabled(GP.db[key])
        label:SetAlpha(GP.db[key] and 0.4 or 1)
    end)
    return sw, swatch
end

local function BuildDisplay(p)
    local card = Card(p, "Lines", 0, 0, PAGE_W, 222)
    refs.worldSwitch = Setting(card, "On the world map", 12, -30, "worldMap",
        "Draw the routes on the world map, on their zone's map (and thinner on the continent's).")
    refs.minimapSwitch = Setting(card, "On the minimap", COL2, -30, "minimap",
        "Draw the routes on the minimap, round you.")
    Slider(card, "World map line width", 12, -64, "worldWidth")
    Slider(card, "Minimap line width", COL2, -64, "minimapWidth")
    refs.worldAlpha = Slider(card, "World map opacity", 12, -108, "worldAlpha", "%")
    refs.minimapAlpha = Slider(card, "Minimap opacity", COL2, -108, "minimapAlpha", "%")
    refs.worldRouteColor, refs.worldColor = LineColor(card, 12, -152, "world", "on the world map")
    refs.minimapRouteColor, refs.minimapColor = LineColor(card, COL2, -152, "minimap", "on the minimap")

    local card2 = Card(p, "More", 0, -234, PAGE_W, 86)
    Setting(card2, "Add new nodes to routes", 12, -30, "autoAdd",
        "When GatherMate2 records a node you just found, it joins the routes in that zone that have its kind, "
        .. "where it adds the least walking.")
    Setting(card2, "Minimap button", COL2, -30, "minimapButton",
        "The GatherPath button on the minimap: left-click opens this window, right-click shows or hides the lines.",
        function() GP:UpdateMinimapButton() end)
    T.Note(card2, "Right-click the minimap button (or type /gpf hide, /gpf show) to hide every line for a while.",
        12, -60, PAGE_W - 24)
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local TABS = {
    { key = "routes",  label = "Routes",    icon = "Interface\\Icons\\INV_Misc_Map_01",   build = BuildRoutes },
    { key = "new",     label = "New route", icon = "Interface\\Icons\\INV_Misc_Flower_02", build = BuildNew },
    { key = "display", label = "Display",   icon = "Interface\\Icons\\INV_Misc_Spyglass_03", build = BuildDisplay },
}
GP.CONFIG_TABS = TABS

function GP:BuildConfig()
    if self.config then return self.config end
    self.config = T.Window({
        name = "GatherPathForeverConfig",
        tabs = TABS,
        hint = "/gpf opens this window",
        version = function()
            local get = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
            local v = get and get(ADDON, "Version")
            if v and v:find("@") then return nil end
            return v and v:gsub("^v", "")
        end,
        onShow = function()
            if GP.config and GP.config.currentTab == "new" then ResetNew() end
            GP:RefreshConfig()
        end,
        onTab = function(key)
            if key == "new" then ResetNew() end
            GP:RefreshConfig()
        end,
    })
    return self.config
end

-- Opens New route blank but on this zone (the Routes tab's New route button)
function GP:NewRouteInWindow(mapID)
    self:OpenConfig("new")
    newZone = mapID
    self:RefreshConfig()
end

-- Opens New route filled in from this route; Save changes then changes it
function GP:EditRouteInWindow(route)
    self:OpenConfig("new")
    EditInWindow(route)
    self:RefreshConfig()
end

function GP:RefreshConfig()
    if not (self.config and self.config:IsShown()) then return end
    for _, fn in ipairs(refreshers) do fn() end
end

function GP:OpenConfig(tab)
    local win = self:BuildConfig()
    if tab then
        win:Show()
        win:ShowTab(tab)
    elseif win:IsShown() then
        win:Hide()
    else
        win:Show()
    end
    self:RefreshConfig()
end

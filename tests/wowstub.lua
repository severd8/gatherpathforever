-- A small fake of the game's API: enough to load GatherPath Forever outside
-- the game and drive it. Frames take any method; the ones the tests look at
-- remember what they were given.

LOG = {}
local realPrint = print
function print(...)
    local t = {}
    for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end
    LOG[#LOG + 1] = table.concat(t, " ")
end
REAL_PRINT = realPrint

ALL_FRAMES = {}
local Methods = {}
-- Methods the addon adds to its own widgets: a real frame doesn't have them, so
-- calling one that was never added is an error here too (as in the game)
local ADDON_METHODS = { SetDisabled = true, SetOn = true, IsOn = true, SetHover = true, Paint = true,
    Refresh = true, Choose = true, SetContent = true }
local MT = {
    __index = function(obj, k)
        if Methods[k] then return Methods[k] end
        if type(k) == "string" and k:sub(1, 2) == "__" then return nil end
        if ADDON_METHODS[k] then return nil end
        return function() end   -- anything else does nothing
    end,
}

local function newObj(kind, name, parent)
    local o = setmetatable({ __kind = kind, __name = name, __parent = parent, __scripts = {}, __children = {},
        __shown = true, __text = "", __w = 100, __h = 20 }, MT)
    if parent and parent.__children then table.insert(parent.__children, o) end
    if name then _G[name] = o end
    ALL_FRAMES[#ALL_FRAMES + 1] = o
    return o
end
NewObj = newObj

function Methods:CreateTexture() return newObj("Texture", nil, self) end
function Methods:CreateFontString() return newObj("FontString", nil, self) end
function Methods:CreateLine() return newObj("Line", nil, self) end
function Methods:Show()
    local was = self.__shown
    self.__shown = true
    if not was and self.__scripts.OnShow then self.__scripts.OnShow(self) end
end
function Methods:Hide()
    local was = self.__shown
    self.__shown = false
    if was and self.__scripts.OnHide then self.__scripts.OnHide(self) end
end
function Methods:SetShown(v) if v then self:Show() else self:Hide() end end
function Methods:IsShown() return self.__shown end
function Methods:IsVisible()
    local o = self
    while o do
        if not o.__shown then return false end
        o = o.__parent
    end
    return true
end
function Methods:SetScript(k, fn) self.__scripts[k] = fn end
function Methods:GetScript(k) return self.__scripts[k] end
function Methods:HookScript(k, fn)
    local old = self.__scripts[k]
    self.__scripts[k] = function(...) if old then old(...) end fn(...) end
end
function Methods:SetText(t) self.__text = t == nil and "" or tostring(t) end
function Methods:GetText() return self.__text end
function Methods:SetFontString(fs) self.__fs = fs end
function Methods:GetFont() return "Fonts\\FRIZQT__.TTF", 12, "" end
function Methods:GetStringWidth() return #(self.__text or "") * 6 end
function Methods:SetSize(w, h) self.__w, self.__h = w, h end
function Methods:SetWidth(w) self.__w = w end
function Methods:SetHeight(h) self.__h = h end
function Methods:GetWidth() return self.__w end
function Methods:GetHeight() return self.__h end
function Methods:GetEffectiveScale() return 1 end
function Methods:GetFrameLevel() return 1 end
function Methods:SetPoint(...) self.__points = self.__points or {} table.insert(self.__points, { ... }) end
function Methods:ClearAllPoints() self.__points = {} end
function Methods:GetName() return self.__name end
function Methods:GetObjectType() return self.__kind end
function Methods:RegisterEvent(e) self.__events = self.__events or {} self.__events[e] = true end
function Methods:SetValue(v)
    self.__value = v
    if self.__scripts.OnValueChanged then self.__scripts.OnValueChanged(self, v) end
end
function Methods:GetValue() return self.__value or 0 end
function Methods:SetColorTexture(r, g, b, a) self.__color = { r, g, b, a } end
function Methods:SetVertexColor(r, g, b, a) self.__color = { r, g, b, a } end
function Methods:SetThickness(t) self.__thickness = t end
function Methods:SetStartPoint(_, rel, x, y) self.__from = { x, y }; self.__rel = rel end
function Methods:SetEndPoint(_, rel, x, y) self.__to = { x, y } end
function Methods:SetAlpha(a) self.__alpha = a end
function Methods:GetAlpha() return self.__alpha or 1 end
function Methods:HasFocus() return self.__focus end
function Methods:SetFocus() self.__focus = true end
function Methods:ClearFocus()
    if self.__focus then
        self.__focus = false
        if self.__scripts.OnEditFocusLost then self.__scripts.OnEditFocusLost(self) end
    end
end
function Methods:GetCenter() return 500, 400 end

function CreateFrame(kind, name, parent) return newObj(kind, name, parent) end

-- Clicks a button the way the game does
function Click(b, which)
    assert(b.__scripts.OnClick, "nothing to click")
    b.__scripts.OnClick(b, which or "LeftButton")
end

UIParent = newObj("Frame", "UIParent")
Minimap = newObj("Frame", "Minimap")
Minimap.__w, Minimap.__h = 140, 140
GameTooltip = newObj("GameTooltip", "GameTooltip")
UISpecialFrames = {}
GameFontHighlightSmall = {}
SlashCmdList = {}

FAKE_TIME = 1000
function GetTime() return FAKE_TIME end
local profile = 0
function debugprofilestop() profile = profile + 0.5 return profile end

CVARS = { rotateMinimap = "0" }
function GetCVar(k) return CVARS[k] end
FACING = 0
function GetPlayerFacing() return FACING end
function GetCursorPosition() return 0, 0 end

-- Maps: Elwynn Forest (1429) inside Eastern Kingdoms (1415)
MAPS = {
    [1429] = { name = "Elwynn Forest", w = 1600, h = 1066, parent = 1415, rect = { 0.40, 0.48, 0.70, 0.78 } },
    [1436] = { name = "Westfall", w = 1500, h = 1000, parent = 1415, rect = { 0.36, 0.44, 0.74, 0.82 } },
    [1415] = { name = "Eastern Kingdoms" },
}
PLAYER = { map = 1429, x = 0.5, y = 0.5 }
VIEW_RADIUS = 150
UNIT_SPEED = 7
SECRET = setmetatable({}, { __lt = function() error("compared a secret value") end, __le = function() error("compared a secret value") end })
function issecretvalue(v) return v == SECRET end
function GetUnitSpeed(unit) return UNIT_SPEED, UNIT_SPEED, 7, 4.7 end

C_Map = {}
function C_Map.GetMapInfo(id) local m = MAPS[id] return m and { mapID = id, name = m.name } end
function C_Map.GetBestMapForUnit() return PLAYER.map end
function C_Map.GetMapWorldSize(id) local m = MAPS[id] return m and m.w or 0, m and m.h or 0 end
function C_Map.GetPlayerMapPosition(id)
    if id ~= PLAYER.map then return nil end
    return { x = PLAYER.x, y = PLAYER.y }
end
function C_Map.GetMapRectOnMap(id, top)
    local m = MAPS[id]
    if m and m.parent == top and m.rect then return unpack(m.rect) end
end
C_Minimap = { GetViewRadius = function() return VIEW_RADIUS end }
C_AddOns = { GetAddOnMetadata = function() return "@project-version@" end }

function CreateFromMixins(...)
    local t = {}
    for i = 1, select("#", ...) do for k, v in pairs((select(i, ...))) do t[k] = v end end
    return t
end
function CreateColor(r, g, b, a) return { r = r, g = g, b = b, a = a } end

-- The world map's pin and data provider bases (just what the addon calls)
MapCanvasPinMixin = {
    SetIgnoreGlobalPinScale = function() end,
    UseFrameLevelType = function(self, t) self.__levelType = t end,
    SetPosition = function(self, x, y) self.__pos = { x, y } end,
    GetMap = function(self) return self.__map end,
}
MapCanvasDataProviderMixin = {
    OnAdded = function(self, map) self.__map = map end,
    OnRemoved = function(self) self.__map = nil end,
}

-- A world map that makes pins from GatherPathForeverPinMixin, as Pin.xml does
WorldMapFrame = newObj("Frame", "WorldMapFrame")
WorldMapFrame.__w, WorldMapFrame.__h = 1000, 667
WorldMapFrame.__mapID = 1429
function WorldMapFrame:GetMapID() return self.__mapID end
function WorldMapFrame:DenormalizeHorizontalSize(v) return v * 1000 end
function WorldMapFrame:DenormalizeVerticalSize(v) return v * 667 end
function WorldMapFrame:AddDataProvider(p) self.__providers = self.__providers or {}; table.insert(self.__providers, p); p:OnAdded(self) end
function WorldMapFrame:AcquirePin(template)
    assert(template == "GatherPathForeverPinTemplate")
    local pin = newObj("Frame", nil, self)
    for k, v in pairs(GatherPathForeverPinMixin) do pin[k] = v end
    pin.__map = self
    pin:OnLoad()
    pin:OnAcquired()
    return pin
end
function WorldMapFrame:RemoveAllPinsByTemplate() end
function WorldMapFrame:SetMapID(id)
    self.__mapID = id
    for _, p in ipairs(self.__providers or {}) do p:OnMapChanged() end
end

-- Menus: the dropdowns step through their choices when this is missing
MenuUtil = nil

-- Runs the frames' OnUpdate scripts (only shown ones, as the game does)
function Tick(seconds)
    for _, f in ipairs(ALL_FRAMES) do
        local fn = f.__scripts.OnUpdate
        if fn and f:IsVisible() then fn(f, seconds or 0.05) end
    end
end

function FireEvent(event, ...)
    for _, f in ipairs(ALL_FRAMES) do
        if f.__events and f.__events[event] and f.__scripts.OnEvent then f.__scripts.OnEvent(f, event, ...) end
    end
end

---------------------------------------------------------------------------
-- A fake GatherMate2 with nodes, and its messages
---------------------------------------------------------------------------
function FakeGatherMate(nodes)
    local gm = { db_types = { "Herb Gathering", "Mining", "Fishing", "Treasure" }, gmdbs = {}, listeners = {} }
    local names = { ["Herb Gathering"] = { [1] = "Peacebloom", [2] = "Silverleaf", [3] = "Earthroot" },
        ["Mining"] = { [10] = "Copper Vein", [11] = "Tin Vein" } }
    gm.names = names
    for _, kind in ipairs(gm.db_types) do gm.gmdbs[kind] = {} end
    function gm:EncodeLoc(x, y)
        return math.floor(x * 10000 + 0.5) * 1000000 + math.floor(y * 10000 + 0.5) * 100
    end
    function gm:DecodeLoc(id)
        return math.floor(id / 1000000) / 10000, math.floor(id % 1000000 / 100) / 10000
    end
    function gm:GetNameForNode(kind, id) return names[kind] and names[kind][id] end
    function gm:GetNodesForZone(zone, kind)
        local t = self.gmdbs[kind][zone] or {}
        return pairs(t)
    end
    function gm:Add(zone, kind, id, x, y, quiet)
        self.gmdbs[kind][zone] = self.gmdbs[kind][zone] or {}
        local coord = self:EncodeLoc(x, y)
        self.gmdbs[kind][zone][coord] = id
        if not quiet then self:Send("GatherMate2NodeAdded", zone, kind, coord, names[kind][id]) end
        return coord
    end
    function gm:Delete(zone, kind, x, y)
        local coord = self:EncodeLoc(x, y)
        local id = self.gmdbs[kind][zone][coord]
        self.gmdbs[kind][zone][coord] = nil
        self:Send("GatherMate2NodeDeleted", zone, kind, coord, names[kind][id])
    end
    function gm.RegisterMessage(owner, msg, fn) gm.listeners[#gm.listeners + 1] = { msg, fn } end
    function gm:Send(msg, ...)
        for _, l in ipairs(self.listeners) do if l[1] == msg then l[2](msg, ...) end end
    end
    for _, n in ipairs(nodes or {}) do gm:Add(n[1], n[2], n[3], n[4], n[5], true) end
    GatherMate2 = gm
    return gm
end

-- Loads the addon's files in .toc order
function LoadAddon(dir)
    local ns = {}
    for _, f in ipairs({ "Theme.lua", "Optimize.lua", "Core.lua", "Options.lua" }) do
        local chunk = assert(loadfile(dir .. "/" .. f))
        chunk("GatherPathForever", ns)
    end
    return ns
end
